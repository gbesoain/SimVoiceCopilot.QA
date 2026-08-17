[CmdletBinding()]
param(
    [ValidateSet("SmokeInternalEN", "CoreInternalEN", "NoConnectorInternalEN", "ExtendedRadioInternalEN", "RecognitionStressInternalEN", "SyntaxVariantsInternalEN", "SmokeInternalES", "CoreInternalES")]
    [string]$Suite = "SmokeInternalEN",

    [ValidateSet("Heading", "Altitude", "Airspeed", "VerticalSpeed", "Radio", "Transponder")]
    [string[]]$Category = @(),

    [string]$AppNamePattern = "*SimVoice*",
    [string]$AppIdPattern = "*",
    [string]$ProcessName = "SimVoiceCopilotApp",
    [string]$SimConnectDll = "",
    [string]$OutputDirectory = "",

    [ValidateRange(10, 180)]
    [int]$ConnectionTimeoutSeconds = 60,

    [ValidateRange(1, 5)]
    [int]$MaxAttempts = 2,

    [switch]$SkipAppLaunch,
    [switch]$CloseAppAtEnd,
    [switch]$NoBuild,

    # Keep QA much faster than a human session, but never stack spoken feedback
    # from several commands on top of each other.
    [ValidateRange(0, 5000)]
    [int]$InterCommandPauseMs = 650,

    [ValidateRange(5, 120)]
    [int]$SpeechIdleTimeoutSeconds = 20,

    # HF36-R24 QA11: when the Internal Audio bridge has already completed arbitration
    # and proves that no simulator command was executed, do not waste the full Oracle
    # timeout. A short pause is enough before the next synthesized retry.
    [ValidateRange(0, 3000)]
    [int]$DefinitiveFailureRetryPauseMs = 500,

    # HF36-R15: one-time QA-only settle after the internal bridge is ready. This
    # prevents the first synthesized command from landing on the product's normal
    # recognizer warm-up boundary; the product acceptance gate itself is unchanged.
    [ValidateRange(0, 5000)]
    [int]$InitialRecognizerSettleMs = 1250,

    # Final pre-certification runs stop after the first command that still fails
    # after all configured attempts. Use this switch only when collecting a full
    # failure matrix is more useful than a fast diagnostic.
    [switch]$ContinueAfterFailure
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$oracleScript = Join-Path $PSScriptRoot "Run-QA-SimConnect-Oracle.ps1"
$catalogPath = Join-Path $projectRoot "FlightFunctional\internal-audio-test-cases.json"
$runStarted = Get-Date
$runStamp = $runStarted.ToString("yyyyMMdd-HHmmss")

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot ("QA-Runs\FlightInternalAudio\INTERNAL-{0}-{1}" -f $runStamp, $Suite)
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$oracleRoot = Join-Path $OutputDirectory "oracle"
$feedbackOutput = Join-Path $OutputDirectory "app-feedback-logs"
New-Item -ItemType Directory -Path $oracleRoot -Force | Out-Null
New-Item -ItemType Directory -Path $feedbackOutput -Force | Out-Null
$runLog = Join-Path $OutputDirectory "internal-audio-run.log"
$pipeName = "SimVoiceCopilot.QA.InternalAudio.v1"

function Write-RunLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff zzz"), $Level, $Message
    Add-Content -LiteralPath $runLog -Value $line -Encoding UTF8
    if ($Level -eq "ERROR") {
        Write-Host $line -ForegroundColor Red
    }
    elseif ($Level -eq "WARN") {
        Write-Host $line -ForegroundColor Yellow
    }
    else {
        Write-Host $line
    }
}

function Invoke-InternalAudioRequest {
    param(
        [ValidateSet("ping", "synthesize", "wait-speech-idle")]
        [string]$Action,
        [string]$Text = "",
        [string]$Language = "",
        [int]$TimeoutMs = 30000,
        [int]$SpeechRate = 0,
        [string]$CorrelationId = ""
    )

    if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
        $CorrelationId = [guid]::NewGuid().ToString("N")
    }

    $pipe = $null
    $reader = $null
    $writer = $null
    try {
        $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
            ".",
            $pipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            [System.IO.Pipes.PipeOptions]::Asynchronous)
        $pipe.Connect([Math]::Max(1000, [Math]::Min(30000, $TimeoutMs)))

        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $reader = [System.IO.StreamReader]::new($pipe, $utf8, $false, 65536, $true)
        $writer = [System.IO.StreamWriter]::new($pipe, $utf8, 65536, $true)
        $writer.AutoFlush = $true

        $request = [ordered]@{
            ProtocolVersion = 1
            Action = $Action
            CorrelationId = $CorrelationId
            Text = $Text
            Language = $Language
            TimeoutMs = $TimeoutMs
            SpeechRate = $SpeechRate
        }
        $writer.WriteLine(($request | ConvertTo-Json -Compress))

        $readTask = $reader.ReadLineAsync()
        if (-not $readTask.Wait([Math]::Max(3000, $TimeoutMs + 10000))) {
            throw "Timed out waiting for the Internal Audio QA bridge response."
        }

        $line = $readTask.Result
        if ([string]::IsNullOrWhiteSpace($line)) {
            throw "Internal Audio QA bridge returned an empty response."
        }

        return $line | ConvertFrom-Json
    }
    finally {
        if ($writer) { try { $writer.Dispose() } catch { } }
        if ($reader) { try { $reader.Dispose() } catch { } }
        if ($pipe) { try { $pipe.Dispose() } catch { } }
    }
}

function Wait-QaHumanPace {
    param(
        [string]$Reason = "between commands"
    )

    try {
        $idle = Invoke-InternalAudioRequest `
            -Action "wait-speech-idle" `
            -TimeoutMs ($SpeechIdleTimeoutSeconds * 1000) `
            -CorrelationId ("pace-" + [guid]::NewGuid().ToString("N"))

        if ($null -eq $idle -or -not [bool]$idle.Success) {
            $detail = if ($null -ne $idle) { [string]$idle.Error } else { "No bridge response" }
            Write-RunLog ("QA pacing: speech-idle wait did not complete ({0}): {1}" -f $Reason, $detail) "WARN"
        }
        else {
            $pending = ""
            try { $pending = [string]$idle.Diagnostics.pendingSpeechCount } catch { }
            Write-RunLog ("QA pacing: spoken feedback idle ({0}), pending={1}" -f $Reason, $pending)
        }
    }
    catch {
        Write-RunLog ("QA pacing: speech-idle wait failed ({0}): {1}" -f $Reason, $_.Exception.Message) "WARN"
    }

    if ($InterCommandPauseMs -gt 0) {
        Start-Sleep -Milliseconds $InterCommandPauseMs
    }
}

function Get-QaDefinitiveNoExecutionReason {
    param(
        [bool]$InjectionSuccess,
        [string]$CommandFeedback
    )

    if (-not $InjectionSuccess) {
        return ""
    }

    $feedback = if ($null -eq $CommandFeedback) { "" } else { $CommandFeedback.Trim() }

    # In the Internal Audio protocol the synthesize response is returned only after
    # deterministic arbitration for that utterance has completed. Every successful
    # functional execution emits CommandFeedback. Therefore an empty feedback string
    # is a definitive "no command executed", not a reason to keep polling SimConnect.
    if ([string]::IsNullOrWhiteSpace($feedback)) {
        return "Internal Audio arbitration completed without command feedback; no simulator command was executed."
    }

    if ($feedback.StartsWith(
            "Listening for target value",
            [System.StringComparison]::OrdinalIgnoreCase) -or
        $feedback.IndexOf(
            "Continue with the number",
            [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    {
        return "Parameterized command was incomplete and entered target-value prompt mode."
    }

    return ""
}

function Clear-QaPendingValuePrompt {
    param(
        [string]$Language,
        [string]$Reason
    )

    try {
        $cancelWord = if ($Language.StartsWith("es", [System.StringComparison]::OrdinalIgnoreCase)) {
            "cancelar"
        }
        else {
            "cancel"
        }

        $cancel = Invoke-InternalAudioRequest `
            -Action "synthesize" `
            -Text $cancelWord `
            -Language $Language `
            -SpeechRate 0 `
            -TimeoutMs 6000 `
            -CorrelationId ("qa-fast-fail-cancel-" + [guid]::NewGuid().ToString("N"))

        Write-RunLog (
            "QA fast-fail: cleared pending value prompt ({0}); recognized='{1}' feedback='{2}' success={3}" -f
                $Reason,
                [string]$cancel.RecognizedText,
                [string]$cancel.CommandFeedback,
                [bool]$cancel.Success)
    }
    catch {
        Write-RunLog (
            "QA fast-fail: value-prompt cancellation failed ({0}): {1}" -f
                $Reason,
                $_.Exception.Message) "WARN"
    }
}

function Wait-InternalAudioBridge {
    param(
        [string]$ExpectedLanguage,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = ""
    do {
        try {
            $response = Invoke-InternalAudioRequest -Action ping -TimeoutMs 3000
            if ($null -ne $response -and [bool]$response.Success) {
                $configuredLanguage = [string]$response.VoiceLanguage
                if (-not [string]::IsNullOrWhiteSpace($ExpectedLanguage) -and
                    -not [string]::IsNullOrWhiteSpace($configuredLanguage) -and
                    -not $configuredLanguage.StartsWith($ExpectedLanguage.Substring(0, 2), [StringComparison]::OrdinalIgnoreCase)) {
                    throw ("SimVoice voice-recognition language is '{0}', but suite '{1}' requires '{2}'. Change Voice Settings and restart the QA package." -f $configuredLanguage, $Suite, $ExpectedLanguage)
                }
                return $response
            }
            $lastError = if ($null -ne $response) { [string]$response.Error } else { "No response" }
        }
        catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    throw ("Internal Audio QA bridge was not ready within {0} seconds. Last error: {1}. Confirm that the installed app title includes '[QA Internal Audio]'." -f $TimeoutSeconds, $lastError)
}

function Start-SimVoiceQaPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId
    )

    # HF36-R21-QA8:
    # Activate the packaged app through the Windows ApplicationActivationManager.
    # explorer.exe shell:AppsFolder is kept only as a fallback because Explorer can
    # silently ignore an activation request while still returning success.
    try {
        [uint32]$activationPid = [SimVoiceQa.PackageActivation]::Activate($AppId)
        Write-RunLog (
            "MSIX activation via ApplicationActivationManager: AppID={0}, activation PID={1}" -f
            $AppId, $activationPid)
        return
    }
    catch {
        Write-RunLog (
            "ApplicationActivationManager failed for AppID={0}: {1}. Falling back to shell:AppsFolder." -f
            $AppId, $_.Exception.Message) "WARN"
    }

    Start-Process "explorer.exe" ("shell:AppsFolder\{0}" -f $AppId)
    Write-RunLog ("MSIX activation fallback submitted through Explorer: AppID={0}" -f $AppId)
}

function Restart-SimVoiceForQaMatrix {
    param(
        [string]$AppId,
        [string]$ExpectedLanguage,
        [int]$TimeoutSeconds,
        [string]$Reason
    )

    Write-RunLog ("QA recovery: restarting SimVoice after {0}." -f $Reason) "WARN"

    $existing = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    foreach ($process in $existing) {
        try {
            $process.Refresh()
            if (-not $process.HasExited) {
                try { $process.CloseMainWindow() | Out-Null } catch { }
                if (-not $process.WaitForExit(4000)) {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch { }
        try { $process.Dispose() } catch { }
    }

    Start-SimVoiceQaPackage -AppId $AppId
    $restarted = Wait-SimVoiceProcess -TimeoutSeconds $TimeoutSeconds
    Write-RunLog ("QA recovery: SimVoice process ready PID={0}." -f $restarted.Id)

    $bridge = Wait-InternalAudioBridge -ExpectedLanguage $ExpectedLanguage -TimeoutSeconds $TimeoutSeconds
    Write-RunLog ("QA recovery: Internal Audio bridge ready after restart; language={0}." -f $bridge.VoiceLanguage)

    if ($InitialRecognizerSettleMs -gt 0) {
        Write-RunLog ("QA recovery: recognizer settle {0} ms after restart." -f $InitialRecognizerSettleMs)
        Start-Sleep -Milliseconds $InitialRecognizerSettleMs
    }

    return $restarted
}

function Get-WindowsPowerShell {
    $candidate = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    $command = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    throw "Windows PowerShell 5.1 was not found."
}

function Get-OracleArguments {
    param(
        [string]$Mode,
        [string]$Directory,
        [string]$Variable = "",
        [string]$Expected = "",
        [double]$Tolerance = 0,
        [int]$TimeoutSeconds = 30,
        [int]$IntervalMs = 250,
        [switch]$UseNoBuild
    )

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $oracleScript,
        "-Mode", $Mode,
        "-OutputDirectory", $Directory,
        "-TimeoutSeconds", $TimeoutSeconds,
        "-IntervalMs", $IntervalMs
    )

    if (-not [string]::IsNullOrWhiteSpace($Variable)) {
        $arguments += @("-Variable", $Variable, "-Expected", $Expected, "-Tolerance", $Tolerance)
    }

    if (-not [string]::IsNullOrWhiteSpace($SimConnectDll)) {
        $arguments += @("-SimConnectDll", $SimConnectDll)
    }

    if ($UseNoBuild) { $arguments += "-NoBuild" }
    return $arguments
}

function Invoke-OracleSync {
    param(
        [string]$Mode,
        [string]$Directory,
        [string]$Variable = "",
        [string]$Expected = "",
        [double]$Tolerance = 0,
        [int]$TimeoutSeconds = 30,
        [int]$IntervalMs = 250,
        [switch]$UseNoBuild
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $powershellExe = Get-WindowsPowerShell
    $arguments = Get-OracleArguments -Mode $Mode -Directory $Directory -Variable $Variable -Expected $Expected -Tolerance $Tolerance -TimeoutSeconds $TimeoutSeconds -IntervalMs $IntervalMs -UseNoBuild:$UseNoBuild
    $argumentString = ($arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "
    $stdout = Join-Path $Directory "oracle-sync-console-out.log"
    $stderr = Join-Path $Directory "oracle-sync-console-error.log"

    # Do not execute the child PowerShell directly in this pipeline. Native
    # stderr records can become terminating RemoteException/NativeCommandError
    # objects under $ErrorActionPreference='Stop', aborting the entire suite.
    $process = Start-Process -FilePath $powershellExe `
        -ArgumentList $argumentString `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -WindowStyle Hidden `
        -PassThru

    $process.WaitForExit()
    $code = [int]$process.ExitCode
    $process.Dispose()

    if (Test-Path -LiteralPath $stdout) {
        Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host ([string]$_) }
    }
    if (Test-Path -LiteralPath $stderr) {
        Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host ([string]$_) -ForegroundColor DarkYellow }
    }

    return [pscustomobject][ordered]@{
        ExitCode = $code
        Directory = $Directory
        ReportPath = Join-Path $Directory "oracle-report.json"
    }
}

function Quote-ProcessArgument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-OracleWait {
    param(
        [string]$Directory,
        [string]$Variable,
        [string]$Expected,
        [double]$Tolerance,
        [int]$TimeoutSeconds
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $powershellExe = Get-WindowsPowerShell
    $arguments = Get-OracleArguments -Mode "Wait" -Directory $Directory -Variable $Variable -Expected $Expected -Tolerance $Tolerance -TimeoutSeconds $TimeoutSeconds -IntervalMs 250 -UseNoBuild
    $argumentString = ($arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "
    $stdout = Join-Path $Directory "oracle-console-out.log"
    $stderr = Join-Path $Directory "oracle-console-error.log"

    $process = Start-Process -FilePath $powershellExe `
        -ArgumentList $argumentString `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -WindowStyle Hidden `
        -PassThru

    return [pscustomobject]@{
        Process = $process
        Directory = $Directory
        ReportPath = Join-Path $Directory "oracle-report.json"
        StandardOutput = $stdout
        StandardError = $stderr
    }
}

function Read-OracleReport {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-SnapshotObservedValue {
    param(
        [object]$Snapshot,
        [string]$Variable
    )

    $propertyMap = @{
        "HeadingBug" = "HeadingBugDegrees"
        "SelectedAltitude" = "SelectedAltitudeFeet"
        "SelectedAirspeed" = "SelectedAirspeedKnots"
        "SelectedVerticalSpeed" = "SelectedVerticalSpeedFpm"
        "Com1Active" = "Com1ActiveFrequencyMHz"
        "Com1Standby" = "Com1StandbyFrequencyMHz"
        "Com2Active" = "Com2ActiveFrequencyMHz"
        "Com2Standby" = "Com2StandbyFrequencyMHz"
        "Nav1Active" = "Nav1ActiveFrequencyMHz"
        "Nav1Standby" = "Nav1StandbyFrequencyMHz"
        "Nav2Active" = "Nav2ActiveFrequencyMHz"
        "Nav2Standby" = "Nav2StandbyFrequencyMHz"
        "Transponder" = "TransponderCode"
        "AutopilotMaster" = "AutopilotMaster"
        "HeadingHold" = "HeadingHold"
        "AltitudeHold" = "AltitudeHold"
        "VerticalSpeedHold" = "VerticalSpeedHold"
        "ParkingBrake" = "ParkingBrake"
        "GearHandle" = "GearHandlePosition"
        "FlapsHandleIndex" = "FlapsHandleIndex"
    }

    if (-not $propertyMap.ContainsKey($Variable)) {
        throw "The functional runner does not have a snapshot property mapping for '$Variable'."
    }

    $propertyName = $propertyMap[$Variable]
    $property = $Snapshot.PSObject.Properties[$propertyName]
    if ($null -eq $property) {
        throw "Oracle snapshot property '$propertyName' was not found for variable '$Variable'."
    }

    return $property.Value
}

function Get-NumericDifference {
    param(
        [string]$Variable,
        [double]$Observed,
        [double]$Expected
    )

    if ($Variable -eq "HeadingBug") {
        $a = (($Observed % 360) + 360) % 360
        $b = (($Expected % 360) + 360) % 360
        $difference = [Math]::Abs($a - $b)
        return [Math]::Min($difference, 360 - $difference)
    }

    return [Math]::Abs($Observed - $Expected)
}

function Select-TestVariant {
    param(
        [object]$Test,
        [object]$Observed
    )

    foreach ($variant in @($Test.variants)) {
        $expected = [double]::Parse([string]$variant.expected, [Globalization.CultureInfo]::InvariantCulture)
        $observedNumber = [Convert]::ToDouble($Observed, [Globalization.CultureInfo]::InvariantCulture)
        $difference = Get-NumericDifference -Variable ([string]$Test.variable) -Observed $observedNumber -Expected $expected
        if ($difference -gt ([double]$Test.tolerance)) {
            return $variant
        }
    }

    return $null
}

function Get-RequiredTarget {
    param([object]$Test)

    $property = $Test.PSObject.Properties["requiredTarget"]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $null
    }

    return $property.Value
}

function Get-TestPrecondition {
    param([object]$Test)

    $property = $Test.PSObject.Properties["precondition"]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $null
    }

    return $property.Value
}

function Test-ObservedMatchesExpected {
    param(
        [string]$Variable,
        [object]$Observed,
        [string]$Expected,
        [double]$Tolerance
    )

    $expectedNumber = [double]::Parse($Expected, [Globalization.CultureInfo]::InvariantCulture)
    $observedNumber = [Convert]::ToDouble($Observed, [Globalization.CultureInfo]::InvariantCulture)
    return (Get-NumericDifference -Variable $Variable -Observed $observedNumber -Expected $expectedNumber) -le $Tolerance
}

function Invoke-InternalAudioPrecondition {
    param(
        [object]$Test,
        [object]$Variant,
        [string]$TestRoot,
        [int]$AttemptNumber = 1
    )

    $phrase = [string]$Variant.phrase
    $expected = [string]$Variant.expected
    $variable = [string]$Test.variable
    $tolerance = [double]$Test.tolerance
    $timeoutSeconds = [int]$Test.timeoutSeconds
    $speechRate = Get-TestSpeechRate -Test $Test -Attempt $AttemptNumber
    $directory = Join-Path $TestRoot ("precondition-{0}" -f $AttemptNumber)

    Write-Host ("Precondition: internally synthesize '{0}' -> {1}" -f $phrase, $expected) -ForegroundColor DarkYellow

    $wait = Start-OracleWait -Directory $directory -Variable $variable -Expected $expected -Tolerance $tolerance -TimeoutSeconds $timeoutSeconds
    Start-Sleep -Milliseconds 500

    try {
        $injection = Invoke-InternalAudioRequest `
            -Action synthesize `
            -Text $phrase `
            -Language ([string]$Test.language) `
            -SpeechRate $speechRate `
            -TimeoutMs (($timeoutSeconds * 1000) + 10000) `
            -CorrelationId ("{0}-precondition-{1}" -f ([string]$Test.id), $AttemptNumber)

        $preconditionEvidence = [ordered]@{
            TestId = [string]$Test.id
            Attempt = $AttemptNumber
            Phrase = $phrase
            SpeechRate = $speechRate
            Success = [bool]$injection.Success
            RecognizedText = [string]$injection.RecognizedText
            CommandFeedback = [string]$injection.CommandFeedback
            Error = [string]$injection.Error
            SynthesizerVoice = [string]$injection.SynthesizerVoice
            ElapsedMs = [int64]$injection.ElapsedMs
            CapturedAtLocal = (Get-Date).ToString("o")
        }
        $preconditionEvidence |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $directory "internal-audio-response.json") -Encoding UTF8

        Write-RunLog ("{0}: precondition speechRate={1} success={2} recognized='{3}' feedback='{4}' error='{5}'" -f `
            [string]$Test.id, $speechRate, [bool]$injection.Success, [string]$injection.RecognizedText, `
            [string]$injection.CommandFeedback, [string]$injection.Error)

        if (-not [bool]$injection.Success) {
            Stop-And-WaitProcess -Process $wait.Process
            return [pscustomobject]@{
                Passed = $false
                Observed = ""
                Message = "Internal-audio precondition injection failed: " + [string]$injection.Error
                Directory = $directory
            }
        }

        $definitivePreconditionFailure = Get-QaDefinitiveNoExecutionReason `
            -InjectionSuccess ([bool]$injection.Success) `
            -CommandFeedback ([string]$injection.CommandFeedback)

        if (-not [string]::IsNullOrWhiteSpace($definitivePreconditionFailure)) {
            if ([string]$injection.CommandFeedback -match '(?i)Listening for target value|Continue with the number') {
                Clear-QaPendingValuePrompt `
                    -Language ([string]$Test.language) `
                    -Reason ("precondition for " + [string]$Test.id)
            }

            Stop-And-WaitProcess -Process $wait.Process
            Write-RunLog (
                "{0}: FAST-FAIL precondition; skipped {1}s Oracle timeout: {2}" -f
                    [string]$Test.id,
                    $timeoutSeconds,
                    $definitivePreconditionFailure) "WARN"

            return [pscustomobject]@{
                Passed = $false
                Observed = ""
                Message = "QA fast-fail: " + $definitivePreconditionFailure
                Directory = $directory
            }
        }

        $hardDeadline = (Get-Date).AddSeconds($timeoutSeconds + 20)
        while (-not $wait.Process.HasExited -and (Get-Date) -lt $hardDeadline) {
            Start-Sleep -Milliseconds 250
            $wait.Process.Refresh()
        }

        if (-not $wait.Process.HasExited) {
            Stop-And-WaitProcess -Process $wait.Process
            return [pscustomobject]@{
                Passed = $false
                Observed = ""
                Message = "Precondition Oracle wait exceeded its hard timeout."
                Directory = $directory
            }
        }

        $wait.Process.WaitForExit()
        $report = Read-OracleReport -Path $wait.ReportPath
        if ($null -eq $report -or $null -eq $report.Assertion) {
            return [pscustomobject]@{
                Passed = $false
                Observed = ""
                Message = "Precondition Oracle did not generate a valid assertion report."
                Directory = $directory
            }
        }

        $preconditionPassed = [bool]$report.Success
        if ($preconditionPassed) {
            Wait-QaHumanPace -Reason ("after precondition for " + [string]$Test.id)
        }

        return [pscustomobject]@{
            Passed = $preconditionPassed
            Observed = [string]$report.Assertion.Observed
            Message = [string]$report.Message
            Directory = $directory
        }
    }
    finally {
        try { $wait.Process.Dispose() } catch { }
    }
}

function Get-TestSpeechRate {
    param(
        [object]$Test,
        [int]$Attempt
    )

    $property = $Test.PSObject.Properties["speechRates"]
    if ($null -ne $property) {
        $rates = @($property.Value)
        if ($rates.Count -gt 0) {
            $index = [Math]::Min([Math]::Max(0, $Attempt - 1), $rates.Count - 1)
            return [int]$rates[$index]
        }
    }

    if ($Attempt -le 1) { return 0 }
    return -2
}

function Stop-And-WaitProcess {
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) { return }
    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            [void]$Process.WaitForExit(5000)
        }
    }
    catch { }
}

function Find-SimVoiceApp {
    $apps = @(Get-StartApps | Where-Object { $_.Name -like $AppNamePattern -and $_.AppID -like $AppIdPattern })
    if ($apps.Count -eq 0) {
        throw "No installed Start app matched name '$AppNamePattern' and AppID '$AppIdPattern'."
    }
    if ($apps.Count -gt 1) {
        $names = ($apps | ForEach-Object { "{0} [{1}]" -f $_.Name, $_.AppID }) -join "; "
        throw "More than one installed app matched name '$AppNamePattern' and AppID '$AppIdPattern': $names. Use exact patterns."
    }
    return $apps[0]
}

function Wait-SimVoiceProcess {
    param([int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $process) {
            $process.Refresh()
            if ($process.MainWindowHandle -ne 0) { return $process }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    $lastProcesses = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    if ($lastProcesses.Count -gt 0) {
        $details = ($lastProcesses | ForEach-Object {
            try {
                $_.Refresh()
                "PID={0}, HasExited={1}, MainWindowHandle=0x{2:X}" -f
                    $_.Id, $_.HasExited, $_.MainWindowHandle.ToInt64()
            }
            catch {
                "PID={0}, state=unreadable" -f $_.Id
            }
        }) -join "; "

        throw (
            "The process '{0}' existed but did not expose a main window within {1} seconds. {2}" -f
            $ProcessName, $TimeoutSeconds, $details)
    }

    throw (
        "The process '{0}' was not created within {1} seconds after the MSIX activation request." -f
        $ProcessName, $TimeoutSeconds)
}

function Get-UiElementName {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$AutomationId
    )

    try {
        $Process.Refresh()
        if ($Process.MainWindowHandle -ne 0) {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
            if ($null -ne $root) {
                $condition = [System.Windows.Automation.PropertyCondition]::new(
                    [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
                    $AutomationId)
                $element = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
                if ($null -ne $element -and -not [string]::IsNullOrWhiteSpace([string]$element.Current.Name)) {
                    return [string]$element.Current.Name
                }
            }
        }

        # Packaged WinForms applications can expose a valid main HWND while UI Automation
        # does not return descendants from AutomationElement.FromHandle(). Search the
        # desktop tree by process id as a second UIA strategy.
        $processCondition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
            $Process.Id)
        $automationCondition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            $AutomationId)
        $combined = [System.Windows.Automation.AndCondition]::new($processCondition, $automationCondition)
        $desktopElement = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            $combined)
        if ($null -ne $desktopElement) {
            return [string]$desktopElement.Current.Name
        }
    }
    catch {
        return ""
    }

    return ""
}

function Get-NativeSimVoiceStatus {
    param([System.Diagnostics.Process]$Process)

    try {
        $Process.Refresh()
        if ($Process.MainWindowHandle -eq 0) { return "" }
        $texts = [SimVoiceQa.NativeWindowTextReader]::GetDescendantTexts($Process.MainWindowHandle)
        foreach ($text in $texts) {
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            if ($text -match '(?i)flight\s+simulator|simulador') {
                return [string]$text
            }
        }
    }
    catch {
        return ""
    }

    return ""
}

function Get-SimVoiceStatus {
    param([System.Diagnostics.Process]$Process)

    $uiaStatus = Get-UiElementName -Process $Process -AutomationId "lblSimConnectStatus"
    if (-not [string]::IsNullOrWhiteSpace($uiaStatus)) {
        return [pscustomobject]@{ Text = $uiaStatus; Source = "UIAutomation" }
    }

    $nativeStatus = Get-NativeSimVoiceStatus -Process $Process
    if (-not [string]::IsNullOrWhiteSpace($nativeStatus)) {
        return [pscustomobject]@{ Text = $nativeStatus; Source = "Win32" }
    }

    return [pscustomobject]@{ Text = ""; Source = "Unavailable" }
}

function Wait-SimVoiceConnected {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds
    )

    $started = Get-Date
    $deadline = $started.AddSeconds($TimeoutSeconds)
    $unavailableFallbackAt = $started.AddSeconds([Math]::Min(12, $TimeoutSeconds))
    $lastStatus = ""
    $lastSource = "Unavailable"
    $everReadStatus = $false

    do {
        $Process.Refresh()
        if ($Process.HasExited) { throw "SimVoice Copilot exited while waiting for SimConnect." }

        $status = Get-SimVoiceStatus -Process $Process
        $lastStatus = [string]$status.Text
        $lastSource = [string]$status.Source
        if (-not [string]::IsNullOrWhiteSpace($lastStatus)) {
            $everReadStatus = $true
            $isDisconnected = $lastStatus -match '(?i)not\s+connected|no\s+conectado|desconectado|connecting|conectando'
            $isConnected = $lastStatus -match '(?i)(flight\s+simulator|simulador).*(:|-)\s*(connected|conectado)(?:\s+to|\b)'
            if ($isConnected -and -not $isDisconnected) {
                return [pscustomobject]@{
                    Text = $lastStatus
                    Source = $lastSource
                    Verified = $true
                }
            }
        }
        elseif (-not $everReadStatus -and (Get-Date) -ge $unavailableFallbackAt) {
            # UI text is useful evidence but not the oracle of truth. Some MSIX/WinForms
            # combinations do not expose label text to an external process. Continue and
            # let the independent SimConnect Oracle plus the actual command result prove
            # end-to-end connectivity instead of producing a false infrastructure FAIL.
            return [pscustomobject]@{
                Text = "Status text unavailable; connectivity will be validated by the independent Oracle and command outcomes."
                Source = "OracleFallback"
                Verified = $false
            }
        }

        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)

    if (-not $everReadStatus) {
        return [pscustomobject]@{
            Text = "Status text unavailable; connectivity will be validated by the independent Oracle and command outcomes."
            Source = "OracleFallback"
            Verified = $false
        }
    }

    throw "SimVoice Copilot did not report a connected simulator within $TimeoutSeconds seconds. Last status from ${lastSource}: '$lastStatus'."
}

function Copy-FeedbackLogs {
    param([datetime]$Since)
    $logRoot = Join-Path $env:LOCALAPPDATA "SimVoiceCopilot\Logs"
    if (-not (Test-Path -LiteralPath $logRoot)) { return }

    Get-ChildItem -LiteralPath $logRoot -Filter "feedback-*.jsonl" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since.AddMinutes(-1) } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $feedbackOutput $_.Name) -Force
        }
}

function HtmlEncode {
    param([object]$Value)
    return [System.Net.WebUtility]::HtmlEncode([Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture))
}

function Write-FunctionalReports {
    param(
        [object[]]$Results,
        [bool]$Success,
        [string]$AppDisplayName,
        [string]$AppId,
        [string]$ConnectedStatus
    )

    $finished = Get-Date
    $report = [ordered]@{
        RunId = "FLIGHT-$runStamp-$Suite"
        Suite = $Suite
        StartedAtLocal = $runStarted.ToString("o")
        FinishedAtLocal = $finished.ToString("o")
        MachineName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        AppDisplayName = $AppDisplayName
        AppId = $AppId
        ProcessName = $ProcessName
        SimVoiceConnectedStatus = $ConnectedStatus
        Success = $Success
        Passed = @($Results | Where-Object { $_.Passed }).Count
        Failed = @($Results | Where-Object { -not $_.Passed }).Count
        Results = $Results
    }

    $jsonPath = Join-Path $OutputDirectory "functional-results.json"
    $csvPath = Join-Path $OutputDirectory "command-results.csv"
    $htmlPath = Join-Path $OutputDirectory "functional-report.html"

    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $Results | Select-Object TestId, Category, Suite, Language, Phrase, RecognizedText, CommandFeedback, SynthesizerVoice, SpeechRate, Variable, Before, Expected, Observed, Tolerance, Attempts, InjectionElapsedMs, LatencySeconds, Passed, Message, OracleDirectory |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    $resultClass = if ($Success) { "pass" } else { "fail" }
    $resultText = if ($Success) { "PASS" } else { "FAIL" }
    $rows = New-Object Text.StringBuilder
    foreach ($item in $Results) {
        $rowClass = if ($item.Passed) { "pass" } else { "fail" }
        [void]$rows.Append("<tr><td>").Append((HtmlEncode $item.TestId)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Phrase)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.RecognizedText)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.CommandFeedback)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.SynthesizerVoice)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Variable)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Before)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Expected)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Observed)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.InjectionElapsedMs)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.LatencySeconds)).Append("</td><td class='").Append($rowClass).Append("'>")
        $itemResultText = if ($item.Passed) { "PASS" } else { "FAIL" }
        [void]$rows.Append($itemResultText).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Message)).Append("</td></tr>")
    }

    $html = @"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>SimVoice Copilot Flight Functional QA</title>
<style>
body{font-family:Segoe UI,Arial;margin:28px;color:#202124}h1{margin-bottom:4px}.pass{color:#187a2f;font-weight:700}.fail{color:#b42318;font-weight:700}table{border-collapse:collapse;width:100%;margin-top:18px}th,td{border:1px solid #d0d5dd;padding:7px 9px;text-align:left;vertical-align:top}th{background:#f2f4f7}code{background:#f2f4f7;padding:2px 4px}.meta{line-height:1.55}
</style>
</head>
<body>
<h1>SimVoice Copilot — Internal Audio Flight Functional QA</h1>
<p class="$resultClass">$resultText</p>
<p class="meta">Suite: <code>$(HtmlEncode $Suite)</code><br>
App: <code>$(HtmlEncode $AppDisplayName)</code><br>
SimConnect status: <code>$(HtmlEncode $ConnectedStatus)</code><br>
Passed: $(@($Results | Where-Object { $_.Passed }).Count) &nbsp; Failed: $(@($Results | Where-Object { -not $_.Passed }).Count)</p>
<table>
<thead><tr><th>Test</th><th>Synthesized phrase</th><th>Vosk recognized</th><th>Command feedback</th><th>TTS voice</th><th>Variable</th><th>Before</th><th>Expected</th><th>Observed</th><th>Injection ms</th><th>Latency s</th><th>Result</th><th>Message</th></tr></thead>
<tbody>$($rows.ToString())</tbody>
</table>
</body>
</html>
"@
    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

    return [pscustomobject]@{
        Json = $jsonPath
        Csv = $csvPath
        Html = $htmlPath
    }
}

if (-not (Test-Path -LiteralPath $oracleScript)) {
    throw "Oracle launcher not found: $oracleScript"
}
if (-not (Test-Path -LiteralPath $catalogPath)) {
    throw "Functional test catalog not found: $catalogPath"
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

if (-not ("SimVoiceQa.PackageActivation" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace SimVoiceQa
{
    [Flags]
    public enum ActivateOptions
    {
        None = 0x00000000,
        DesignMode = 0x00000001,
        NoErrorUI = 0x00000002,
        NoSplashScreen = 0x00000004
    }

    [ComImport]
    [Guid("2e941141-7f97-4756-ba1d-9decde894a3d")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IApplicationActivationManager
    {
        [PreserveSig]
        int ActivateApplication(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [MarshalAs(UnmanagedType.LPWStr)] string arguments,
            ActivateOptions options,
            out uint processId);
    }

    [ComImport]
    [Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    internal class ApplicationActivationManager
    {
    }

    public static class PackageActivation
    {
        public static uint Activate(string appUserModelId)
        {
            if (String.IsNullOrWhiteSpace(appUserModelId))
                throw new ArgumentException("AppUserModelId is empty.", "appUserModelId");

            IApplicationActivationManager manager =
                (IApplicationActivationManager)new ApplicationActivationManager();

            uint processId;
            int hr = manager.ActivateApplication(
                appUserModelId,
                null,
                ActivateOptions.NoErrorUI,
                out processId);

            if (hr < 0)
                Marshal.ThrowExceptionForHR(hr);

            return processId;
        }
    }
}
"@
}

if (-not ("SimVoiceQa.NativeWindowTextReader" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace SimVoiceQa
{
    public static class NativeWindowTextReader
    {
        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int GetWindowTextLength(IntPtr hWnd);

        public static string[] GetDescendantTexts(IntPtr parent)
        {
            var values = new List<string>();
            if (parent == IntPtr.Zero)
                return values.ToArray();

            EnumChildWindows(parent, delegate(IntPtr hWnd, IntPtr lParam)
            {
                int length = GetWindowTextLength(hWnd);
                if (length > 0)
                {
                    var builder = new StringBuilder(length + 1);
                    GetWindowText(hWnd, builder, builder.Capacity);
                    string value = builder.ToString().Trim();
                    if (value.Length > 0)
                        values.Add(value);
                }
                return true;
            }, IntPtr.Zero);

            return values.ToArray();
        }
    }
}
"@ -Language CSharp
}

Write-RunLog "SimVoice Copilot QA Phase 2.3.7 — HF36-R24 QA11 Definitive Failure Fast-Fail"
Write-RunLog ("Suite: {0}" -f $Suite)
Write-RunLog ("Output: {0}" -f $OutputDirectory)

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$suiteProperty = $catalog.suites.PSObject.Properties[$Suite]
if ($null -eq $suiteProperty) {
    throw "Suite '$Suite' was not found in $catalogPath."
}
$tests = @($suiteProperty.Value)
$suiteCatalogCount = $tests.Count

# Validate the complete suite before applying an optional category filter.
# HF36-R14 CoreInternalEN v2 intentionally contains 36 canonical functional
# cases; alias/radio-extension stress lives in separate optional suites.
if ($Suite -eq "CoreInternalEN" -and $suiteCatalogCount -ne 36) {
    throw "HF36-R14 CoreInternalEN gate must contain exactly 36 cases; catalog contains $suiteCatalogCount."
}
if ($Suite -eq "CoreInternalES" -and $suiteCatalogCount -ne 50) {
    throw "HF36-R21-R2 QA9 CoreInternalES principal Spanish gate must contain exactly 50 cases; catalog contains $suiteCatalogCount."
}
if ($Suite -eq "NoConnectorInternalEN" -and $suiteCatalogCount -ne 30) {
    throw "HF36-R17 NoConnectorInternalEN gate must contain exactly 30 cases; catalog contains $suiteCatalogCount."
}
if ($Suite -eq "SyntaxVariantsInternalEN" -and $suiteCatalogCount -ne 26) {
    throw "HF36-R20 QA7 SyntaxVariantsInternalEN gate must contain exactly 26 cases; catalog contains $suiteCatalogCount."
}

if ($Category.Count -gt 0) {
    $tests = @($tests | Where-Object {
        $categoryProperty = $_.PSObject.Properties["category"]
        $null -ne $categoryProperty -and $Category -contains [string]$categoryProperty.Value
    })
}
if ($tests.Count -eq 0) { throw "Suite '$Suite' contains no tests after applying the requested category filter." }

$app = Find-SimVoiceApp
Write-RunLog ("Installed MSIX: {0} [{1}]" -f $app.Name, $app.AppID)

$simVoiceProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $simVoiceProcess -and -not $SkipAppLaunch) {
    Write-RunLog "Launching installed MSIX package."
    Start-SimVoiceQaPackage -AppId ([string]$app.AppID)
}

$simVoiceProcess = Wait-SimVoiceProcess -TimeoutSeconds $ConnectionTimeoutSeconds
Write-RunLog ("SimVoice process ready: PID={0}, HWND=0x{1:X}" -f $simVoiceProcess.Id, $simVoiceProcess.MainWindowHandle.ToInt64())

# Establish the simulator truth first. UI Automation status text is secondary evidence
# and must never block a valid flight-functional run when the MSIX is visibly running.
$probeDirectory = Join-Path $oracleRoot "00-preflight-probe"
$probe = Invoke-OracleSync -Mode "Probe" -Directory $probeDirectory -TimeoutSeconds 30 -IntervalMs 500 -UseNoBuild:$NoBuild
if ($probe.ExitCode -ne 0) {
    throw "Independent SimConnect Oracle preflight failed. Review: $probeDirectory"
}
Write-RunLog "Independent Oracle preflight: PASS"

$connectedStatusResult = Wait-SimVoiceConnected -Process $simVoiceProcess -TimeoutSeconds $ConnectionTimeoutSeconds
$connectedStatus = [string]$connectedStatusResult.Text
if ([bool]$connectedStatusResult.Verified) {
    Write-RunLog ("SimVoice connected status ({0}): {1}" -f $connectedStatusResult.Source, $connectedStatus)
}
else {
    Write-RunLog ("SimVoice status text could not be read externally ({0}). Continuing because Oracle preflight passed; command outcomes remain authoritative." -f $connectedStatusResult.Source) "WARN"
}

$suiteLanguage = [string]$tests[0].language
$bridgeStatus = Wait-InternalAudioBridge -ExpectedLanguage $suiteLanguage -TimeoutSeconds $ConnectionTimeoutSeconds
Write-RunLog ("Internal audio bridge ready: pipe={0}, app={1}, configured language={2}" -f $pipeName, $bridgeStatus.AppVersion, $bridgeStatus.VoiceLanguage)
if ($InitialRecognizerSettleMs -gt 0) {
    Write-RunLog ("QA initial recognizer settle: waiting {0} ms once before the first command." -f $InitialRecognizerSettleMs)
    Start-Sleep -Milliseconds $InitialRecognizerSettleMs
}
Write-Host ""
Write-Host "INTERNAL AUDIO PRECHECK: PASS" -ForegroundColor Green
Write-Host ("  Voice profile/language : {0}" -f $suiteLanguage)
Write-Host ("  Internal audio pipe    : {0}" -f $pipeName)
Write-Host "  Microphone             : not used"
Write-Host "  Audio source           : Windows speech synthesis -> 16 kHz PCM -> normal Vosk pipeline"
Write-Host "  Simulator              : active flight; do not operate the tested controls manually"
Write-Host ("  QA initial settle      : {0} ms once after bridge ready" -f $InitialRecognizerSettleMs)
Write-Host ("  QA pacing              : wait for spoken feedback idle + {0} ms gap" -f $InterCommandPauseMs)
Write-Host ""

$results = New-Object 'System.Collections.Generic.List[object]' 
$aborted = $false
$testNumber = 0

foreach ($test in $tests) {
    if ($aborted) { break }
    try { $simVoiceProcess.Refresh() } catch { }
    if ($simVoiceProcess.HasExited) {
        if ($ContinueAfterFailure) {
            try {
                $simVoiceProcess = Restart-SimVoiceForQaMatrix `
                    -AppId ([string]$app.AppID) `
                    -ExpectedLanguage ([string]$tests[0].language) `
                    -TimeoutSeconds $ConnectionTimeoutSeconds `
                    -Reason "process exit before next command"
            }
            catch {
                $aborted = $true
                Write-RunLog ("QA recovery failed before next command: {0}" -f $_.Exception.Message) "ERROR"
                break
            }
        }
        else {
            $aborted = $true
            Write-RunLog "SimVoice Copilot exited before the next command. The suite is aborting because -ContinueAfterFailure was not requested." "ERROR"
            break
        }
    }
    $testNumber++
    $testId = [string]$test.id
    $safeTestId = $testId -replace '[^A-Za-z0-9_.-]', '_'
    $testRoot = Join-Path $oracleRoot ("{0:00}-{1}" -f $testNumber, $safeTestId)
    $beforeDirectory = Join-Path $testRoot "before"

    Write-Host ""
    Write-Host ("[{0}/{1}] {2}" -f $testNumber, $tests.Count, $testId) -ForegroundColor Cyan

    $beforeRun = Invoke-OracleSync -Mode "Snapshot" -Directory $beforeDirectory -TimeoutSeconds 20 -IntervalMs 500 -UseNoBuild
    $beforeReport = Read-OracleReport -Path $beforeRun.ReportPath
    if ($beforeRun.ExitCode -ne 0 -or $null -eq $beforeReport -or @($beforeReport.Snapshots).Count -eq 0) {
        $results.Add([pscustomobject][ordered]@{
            TestId = $testId; Suite = $Suite; Language = [string]$test.language; Phrase = "";
            Variable = [string]$test.variable; Before = ""; Expected = ""; Observed = "";
            Tolerance = [double]$test.tolerance; Attempts = 0; LatencySeconds = 0; Passed = $false;
            Message = "Could not capture the pre-command Oracle snapshot."; OracleDirectory = $testRoot
        })
        Write-RunLog ("{0}: FAIL - pre-command snapshot unavailable" -f $testId) "ERROR"
        continue
    }

    $beforeSnapshot = @($beforeReport.Snapshots)[-1]
    $beforeObserved = Get-SnapshotObservedValue -Snapshot $beforeSnapshot -Variable ([string]$test.variable)

    $requiredTarget = Get-RequiredTarget -Test $test
    if ($null -ne $requiredTarget) {
        $variant = $requiredTarget

        if (Test-ObservedMatchesExpected `
                -Variable ([string]$test.variable) `
                -Observed $beforeObserved `
                -Expected ([string]$requiredTarget.expected) `
                -Tolerance ([double]$test.tolerance)) {

            $precondition = Get-TestPrecondition -Test $test
            if ($null -eq $precondition) {
                $results.Add([pscustomobject][ordered]@{
                    TestId = $testId; Suite = $Suite; Language = [string]$test.language; Phrase = [string]$requiredTarget.phrase;
                    RecognizedText = ""; CommandFeedback = ""; SynthesizerVoice = ""; SpeechRate = 0; InjectionElapsedMs = 0;
                    Variable = [string]$test.variable; Before = [string]$beforeObserved; Expected = [string]$requiredTarget.expected; Observed = [string]$beforeObserved;
                    Tolerance = [double]$test.tolerance; Attempts = 0; LatencySeconds = 0; Passed = $false;
                    Message = "Required target already matched current simulator value and no deterministic precondition was configured."; OracleDirectory = $testRoot
                })
                Write-RunLog ("{0}: FAIL - required target already matched and no precondition was configured." -f $testId) "ERROR"
                continue
            }

            $preconditionResult = Invoke-InternalAudioPrecondition -Test $test -Variant $precondition -TestRoot $testRoot
            if (-not [bool]$preconditionResult.Passed) {
                $results.Add([pscustomobject][ordered]@{
                    TestId = $testId; Suite = $Suite; Language = [string]$test.language; Phrase = [string]$requiredTarget.phrase;
                    RecognizedText = ""; CommandFeedback = ""; SynthesizerVoice = ""; SpeechRate = 0; InjectionElapsedMs = 0;
                    Variable = [string]$test.variable; Before = [string]$beforeObserved; Expected = [string]$requiredTarget.expected; Observed = [string]$preconditionResult.Observed;
                    Tolerance = [double]$test.tolerance; Attempts = 0; LatencySeconds = 0; Passed = $false;
                    Message = "Could not establish deterministic precondition: " + [string]$preconditionResult.Message; OracleDirectory = [string]$preconditionResult.Directory
                })
                Write-RunLog ("{0}: FAIL - deterministic precondition failed: {1}" -f $testId, [string]$preconditionResult.Message) "ERROR"
                continue
            }

            $preparedDirectory = Join-Path $testRoot "before-after-precondition"
            $preparedRun = Invoke-OracleSync -Mode "Snapshot" -Directory $preparedDirectory -TimeoutSeconds 20 -IntervalMs 500 -UseNoBuild
            $preparedReport = Read-OracleReport -Path $preparedRun.ReportPath
            if ($preparedRun.ExitCode -ne 0 -or $null -eq $preparedReport -or @($preparedReport.Snapshots).Count -eq 0) {
                $results.Add([pscustomobject][ordered]@{
                    TestId = $testId; Suite = $Suite; Language = [string]$test.language; Phrase = [string]$requiredTarget.phrase;
                    RecognizedText = ""; CommandFeedback = ""; SynthesizerVoice = ""; SpeechRate = 0; InjectionElapsedMs = 0;
                    Variable = [string]$test.variable; Before = [string]$beforeObserved; Expected = [string]$requiredTarget.expected; Observed = "";
                    Tolerance = [double]$test.tolerance; Attempts = 0; LatencySeconds = 0; Passed = $false;
                    Message = "Precondition succeeded but the post-precondition Oracle snapshot was unavailable."; OracleDirectory = $testRoot
                })
                Write-RunLog ("{0}: FAIL - post-precondition snapshot unavailable." -f $testId) "ERROR"
                continue
            }

            $beforeSnapshot = @($preparedReport.Snapshots)[-1]
            $beforeObserved = Get-SnapshotObservedValue -Snapshot $beforeSnapshot -Variable ([string]$test.variable)
        }
    }
    else {
        $variant = Select-TestVariant -Test $test -Observed $beforeObserved

        if ($null -eq $variant) {
            $results.Add([pscustomobject][ordered]@{
                TestId = $testId; Suite = $Suite; Language = [string]$test.language; Phrase = "";
                RecognizedText = ""; CommandFeedback = ""; SynthesizerVoice = ""; SpeechRate = 0; InjectionElapsedMs = 0;
                Variable = [string]$test.variable; Before = [string]$beforeObserved; Expected = ""; Observed = [string]$beforeObserved;
                Tolerance = [double]$test.tolerance; Attempts = 0; LatencySeconds = 0; Passed = $false;
                Message = "All configured target variants already matched the current simulator value; no valid precondition was available."; OracleDirectory = $testRoot
            })
            Write-RunLog ("{0}: FAIL - no target differs from current value {1}" -f $testId, $beforeObserved) "ERROR"
            continue
        }
    }

    $phrase = [string]$variant.phrase
    $expected = [string]$variant.expected
    $attempt = 0
    $passed = $false
    $observed = ""
    $message = ""
    $latency = 0.0
    $lastAttemptDirectory = ""
    $recognizedText = ""
    $commandFeedback = ""
    $synthesizerVoice = ""
    $injectionElapsedMs = 0
    $speechRate = 0
    $recoveryNeeded = $false

    while (-not $passed -and $attempt -lt $MaxAttempts) {
        $attempt++

        if ($attempt -gt 1) {
            $retryBeforeDirectory = Join-Path $testRoot ("before-retry-{0}" -f $attempt)
            $retryBeforeRun = Invoke-OracleSync -Mode "Snapshot" -Directory $retryBeforeDirectory -TimeoutSeconds 20 -IntervalMs 500 -UseNoBuild
            $retryBeforeReport = Read-OracleReport -Path $retryBeforeRun.ReportPath
            if ($retryBeforeRun.ExitCode -eq 0 -and $null -ne $retryBeforeReport -and @($retryBeforeReport.Snapshots).Count -gt 0) {
                $retrySnapshot = @($retryBeforeReport.Snapshots)[-1]
                $beforeObserved = Get-SnapshotObservedValue -Snapshot $retrySnapshot -Variable ([string]$test.variable)
                $retryRequiredTarget = Get-RequiredTarget -Test $test
                if ($null -ne $retryRequiredTarget) {
                    $variant = $retryRequiredTarget
                    $phrase = [string]$variant.phrase
                    $expected = [string]$variant.expected
                }
                else {
                    $retryVariant = Select-TestVariant -Test $test -Observed $beforeObserved
                    if ($null -ne $retryVariant) {
                        $variant = $retryVariant
                        $phrase = [string]$variant.phrase
                        $expected = [string]$variant.expected
                    }
                }
            }
        }

        $attemptDirectory = Join-Path $testRoot ("attempt-{0}" -f $attempt)
        $lastAttemptDirectory = $attemptDirectory
        $speechRate = Get-TestSpeechRate -Test $test -Attempt $attempt

        Write-Host ("Variable : {0}" -f $test.variable) -ForegroundColor DarkGray
        Write-Host ("Before   : {0}" -f $beforeObserved) -ForegroundColor DarkGray
        Write-Host ("Expected : {0} (tolerance {1})" -f $expected, $test.tolerance) -ForegroundColor DarkGray
        Write-Host ("Audio    : internally synthesize '{0}' (speech rate {1})" -f $phrase, $speechRate) -ForegroundColor Yellow

        $recognizedText = ""
        $commandFeedback = ""
        $synthesizerVoice = ""
        $injectionElapsedMs = 0
        $injectionError = ""
        $definitiveNoExecution = $false

        $wait = Start-OracleWait -Directory $attemptDirectory -Variable ([string]$test.variable) -Expected $expected -Tolerance ([double]$test.tolerance) -TimeoutSeconds ([int]$test.timeoutSeconds)
        Start-Sleep -Milliseconds 500
        $injectionStarted = Get-Date
        try {
            $injection = Invoke-InternalAudioRequest `
                -Action synthesize `
                -Text $phrase `
                -Language ([string]$test.language) `
                -SpeechRate $speechRate `
                -TimeoutMs (([int]$test.timeoutSeconds * 1000) + 10000) `
                -CorrelationId ("{0}-{1}" -f $testId, $attempt)

            $recognizedText = [string]$injection.RecognizedText
            $commandFeedback = [string]$injection.CommandFeedback
            $synthesizerVoice = [string]$injection.SynthesizerVoice
            $injectionElapsedMs = [int64]$injection.ElapsedMs
            if (-not [bool]$injection.Success) {
                $injectionError = [string]$injection.Error
            }

            # Persist the bridge response before any later failure/cancellation.
            $bridgeEvidence = [ordered]@{
                TestId = $testId
                Attempt = $attempt
                Phrase = $phrase
                SpeechRate = $speechRate
                Success = [bool]$injection.Success
                RecognizedText = $recognizedText
                CommandFeedback = $commandFeedback
                Error = [string]$injection.Error
                SynthesizerVoice = $synthesizerVoice
                ElapsedMs = $injectionElapsedMs
                CapturedAtLocal = (Get-Date).ToString("o")
            }
            $bridgeEvidence |
                ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath (Join-Path $attemptDirectory "internal-audio-response.json") -Encoding UTF8

            Write-Host ("Recognized: {0}" -f $recognizedText) -ForegroundColor Cyan
            Write-Host ("Feedback  : {0}" -f $commandFeedback) -ForegroundColor DarkGray
            Write-Host ("TTS voice : {0}" -f $synthesizerVoice) -ForegroundColor DarkGray
            Write-RunLog ("{0}: bridge attempt={1} speechRate={2} success={3} recognized='{4}' feedback='{5}' error='{6}'" -f `
                $testId, $attempt, $speechRate, [bool]$injection.Success, $recognizedText, $commandFeedback, [string]$injection.Error)
        }
        catch {
            $injectionError = $_.Exception.Message
        }

        if (-not [string]::IsNullOrWhiteSpace($injectionError)) {
            Stop-And-WaitProcess -Process $wait.Process
            try { $wait.Process.Dispose() } catch { }
            try { $simVoiceProcess.Refresh() } catch { }
            if ($simVoiceProcess.HasExited) {
                $message = "SimVoice Copilot process exited during internal audio injection: $injectionError"
                $recoveryNeeded = $true
                if (-not $ContinueAfterFailure) {
                    $aborted = $true
                }
            }
            else {
                $message = "Internal audio injection failed while SimVoice remained running: $injectionError"
            }
            $passed = $false
        }
        else {
            $definitiveFailureReason = Get-QaDefinitiveNoExecutionReason `
                -InjectionSuccess $true `
                -CommandFeedback $commandFeedback

            if (-not [string]::IsNullOrWhiteSpace($definitiveFailureReason)) {
                $definitiveNoExecution = $true

                if ($commandFeedback -match '(?i)Listening for target value|Continue with the number') {
                    Clear-QaPendingValuePrompt `
                        -Language ([string]$test.language) `
                        -Reason ("attempt " + $attempt + " of " + $testId)
                }

                Stop-And-WaitProcess -Process $wait.Process
                try { $wait.Process.Dispose() } catch { }

                $latency = [Math]::Round(((Get-Date) - $injectionStarted).TotalSeconds, 3)
                $observed = [string]$beforeObserved
                $message = "QA fast-fail: " + $definitiveFailureReason

                Write-RunLog (
                    "{0}: FAST-FAIL attempt={1}; skipped {2}s Oracle timeout; recognized='{3}' feedback='{4}'" -f
                        $testId,
                        $attempt,
                        [int]$test.timeoutSeconds,
                        $recognizedText,
                        $commandFeedback) "WARN"

                $passed = $false
            }
            else {
                $hardDeadline = (Get-Date).AddSeconds(([int]$test.timeoutSeconds + 20))
                while (-not $wait.Process.HasExited -and (Get-Date) -lt $hardDeadline) {
                    Start-Sleep -Milliseconds 250
                    $wait.Process.Refresh()
                    if ($simVoiceProcess.HasExited) {
                        Stop-And-WaitProcess -Process $wait.Process
                        break
                    }
                }

                if (-not $wait.Process.HasExited) {
                Stop-And-WaitProcess -Process $wait.Process
                try { $wait.Process.Dispose() } catch { }
                $message = "Oracle wait subprocess exceeded its hard timeout."
                $passed = $false
            }
            elseif ($simVoiceProcess.HasExited) {
                try { $wait.Process.Dispose() } catch { }
                $message = "SimVoice Copilot process exited during the command test."
                $passed = $false
                $recoveryNeeded = $true
                if (-not $ContinueAfterFailure) {
                    $aborted = $true
                }
            }
            else {
                $wait.Process.WaitForExit()
                $latency = [Math]::Round(((Get-Date) - $injectionStarted).TotalSeconds, 3)
                $attemptReport = Read-OracleReport -Path $wait.ReportPath
                try { $wait.Process.Dispose() } catch { }
                if ($null -ne $attemptReport -and $null -ne $attemptReport.Assertion) {
                    $observed = [string]$attemptReport.Assertion.Observed
                    $message = [string]$attemptReport.Message
                    $passed = [bool]$attemptReport.Success
                }
                else {
                    $message = "Oracle did not generate a valid assertion report."
                    $passed = $false
                }
            }
            }
        }

        if ($passed) {
            Write-Host ("PASS: observed {0} in {1} seconds" -f $observed, $latency) -ForegroundColor Green
            Write-RunLog ("{0}: PASS phrase='{1}' before={2} expected={3} observed={4} latency={5}s attempt={6} speechRate={7}" -f $testId, $phrase, $beforeObserved, $expected, $observed, $latency, $attempt, $speechRate)
        }
        else {
            Write-Host ("FAIL: {0}" -f $message) -ForegroundColor Red
            Write-RunLog ("{0}: FAIL phrase='{1}' before={2} expected={3} observed={4} attempt={5} speechRate={6}: {7}" -f $testId, $phrase, $beforeObserved, $expected, $observed, $attempt, $speechRate, $message) "ERROR"

            if (-not $aborted -and $attempt -lt $MaxAttempts) {
                if ($recoveryNeeded) {
                    try {
                        $simVoiceProcess = Restart-SimVoiceForQaMatrix `
                            -AppId ([string]$app.AppID) `
                            -ExpectedLanguage ([string]$test.language) `
                            -TimeoutSeconds $ConnectionTimeoutSeconds `
                            -Reason ("failed attempt " + $attempt + " of " + $testId)
                        $recoveryNeeded = $false
                    }
                    catch {
                        $aborted = $true
                        $message = $message + " | QA recovery failed: " + $_.Exception.Message
                        Write-RunLog ("{0}: QA recovery failed before retry: {1}" -f $testId, $_.Exception.Message) "ERROR"
                        break
                    }
                }

                Write-Host "Retrying automatically with a fresh Oracle snapshot..." -ForegroundColor Yellow
                if ($definitiveNoExecution) {
                    if ($DefinitiveFailureRetryPauseMs -gt 0) {
                        Start-Sleep -Milliseconds $DefinitiveFailureRetryPauseMs
                    }
                }
                else {
                    Start-Sleep -Seconds 2
                }
            }
        }
    }

    $results.Add([pscustomobject][ordered]@{
        TestId = $testId
        Category = if ($null -ne $test.PSObject.Properties["category"]) { [string]$test.category } else { "" }
        Suite = $Suite
        Language = [string]$test.language
        Phrase = $phrase
        Variable = [string]$test.variable
        Before = [string]$beforeObserved
        Expected = $expected
        Observed = $observed
        Tolerance = [double]$test.tolerance
        Attempts = $attempt
        LatencySeconds = $latency
        InjectionElapsedMs = $injectionElapsedMs
        SpeechRate = $speechRate
        RecognizedText = $recognizedText
        CommandFeedback = $commandFeedback
        SynthesizerVoice = $synthesizerVoice
        Passed = $passed
        Message = $message
        OracleDirectory = $lastAttemptDirectory
    })

    if ($passed -and -not $aborted) {
        Wait-QaHumanPace -Reason ("after " + $testId)
    }

    if (-not $passed -and $recoveryNeeded -and $ContinueAfterFailure -and -not $aborted) {
        try {
            $simVoiceProcess = Restart-SimVoiceForQaMatrix `
                -AppId ([string]$app.AppID) `
                -ExpectedLanguage ([string]$test.language) `
                -TimeoutSeconds $ConnectionTimeoutSeconds `
                -Reason ("failed final attempt of " + $testId + "; continuing matrix")
            $recoveryNeeded = $false
        }
        catch {
            $aborted = $true
            Write-RunLog ("{0}: QA recovery failed before next case: {1}" -f $testId, $_.Exception.Message) "ERROR"
        }
    }

    if ($aborted) {
        Write-Host "ABORTED: SimVoice Copilot could not be kept/recovered for the remaining command cases." -ForegroundColor Red
        break
    }

    if (-not $passed -and -not $ContinueAfterFailure) {
        Write-RunLog ("FAIL-FAST: stopping after {0}. Use -ContinueAfterFailure to collect the complete failure matrix." -f $testId) "ERROR"
        Write-Host "FAIL-FAST: remaining command cases were not executed." -ForegroundColor Red
        break
    }
}

Copy-FeedbackLogs -Since $runStarted

$overallSuccess = (-not $aborted) -and ($results.Count -eq $tests.Count) -and (@($results | Where-Object { -not $_.Passed }).Count -eq 0)
$resultArray = @($results | ForEach-Object { $_ })
$reports = Write-FunctionalReports -Results $resultArray -Success $overallSuccess -AppDisplayName ([string]$app.Name) -AppId ([string]$app.AppID) -ConnectedStatus $connectedStatus

if ($CloseAppAtEnd -and $null -ne $simVoiceProcess -and -not $simVoiceProcess.HasExited) {
    Write-RunLog "Closing SimVoice Copilot because -CloseAppAtEnd was specified."
    try {
        $simVoiceProcess.CloseMainWindow() | Out-Null
        if (-not $simVoiceProcess.WaitForExit(10000)) {
            Stop-Process -Id $simVoiceProcess.Id -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-RunLog ("Could not close SimVoice Copilot cleanly: {0}" -f $_.Exception.Message) "WARN"
    }
}

Write-Host ""
$overallText = if ($overallSuccess) { "INTERNAL AUDIO FUNCTIONAL RESULT: PASS" } else { "INTERNAL AUDIO FUNCTIONAL RESULT: FAIL" }
$overallColor = if ($overallSuccess) { "Green" } else { "Red" }
Write-Host $overallText -ForegroundColor $overallColor
Write-Host ("Results: {0}" -f $OutputDirectory)
Write-Host ("HTML   : {0}" -f $reports.Html)
Write-Host ("JSON   : {0}" -f $reports.Json)
Write-Host ("CSV    : {0}" -f $reports.Csv)

if ($overallSuccess) { exit 0 }
exit 1
