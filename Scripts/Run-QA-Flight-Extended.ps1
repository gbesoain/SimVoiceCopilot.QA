[CmdletBinding()]
param(
    [ValidateSet("StatesInternalEN", "StatesInternalES", "CalloutsInternalEN", "CalloutsInternalES", "NegativeInternalEN", "NegativeInternalES", "SessionInternalEN", "SessionInternalES")]
    [string]$Suite = "StatesInternalEN",

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
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$oracleScript = Join-Path $PSScriptRoot "Run-QA-SimConnect-Oracle.ps1"
$catalogPath = Join-Path $projectRoot "FlightFunctional\extended-test-cases.json"
$runStarted = Get-Date
$runStamp = $runStarted.ToString("yyyyMMdd-HHmmss")

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot ("QA-Runs\FlightExtended\EXTENDED-{0}-{1}" -f $runStamp, $Suite)
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
        [ValidateSet("ping", "status", "synthesize", "reset-state", "wait-speech-idle")]
        [string]$Action,
        [string]$Text = "",
        [string]$Language = "",
        [int]$TimeoutMs = 30000,
        [int]$SpeechRate = 0,
        [bool]$WaitForCalloutResponse = $false,
        [bool]$WaitForAiIdle = $false,
        [int]$PostCommandWaitMs = 300,
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
            WaitForCalloutResponse = $WaitForCalloutResponse
            WaitForAiIdle = $WaitForAiIdle
            PostCommandWaitMs = $PostCommandWaitMs
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

function Reset-QaInteractionState {
    param([int]$TimeoutMs = 5000)
    return Invoke-InternalAudioRequest -Action "reset-state" -TimeoutMs $TimeoutMs -CorrelationId ("reset-" + [guid]::NewGuid().ToString("N"))
}

function Wait-QaSpeechIdle {
    param([int]$TimeoutMs = 30000)
    return Invoke-InternalAudioRequest -Action "wait-speech-idle" -TimeoutMs $TimeoutMs -CorrelationId ("speech-idle-" + [guid]::NewGuid().ToString("N"))
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
        "SelectedVerticalSpeed" = "SelectedVerticalSpeedFpm"
        "Transponder" = "TransponderCode"
        "AutopilotMaster" = "AutopilotMaster"
        "HeadingHold" = "HeadingHold"
        "AltitudeHold" = "AltitudeHold"
        "VerticalSpeedHold" = "VerticalSpeedHold"
        "ParkingBrake" = "ParkingBrake"
        "GearHandle" = "GearHandlePosition"
        "FlapsHandleIndex" = "FlapsHandleIndex"
        "PlaneAltitude" = "PlaneAltitudeFeet"
        "PlaneHeading" = "PlaneHeadingMagneticDegrees"
        "FuelGallons" = "FuelTotalQuantityGallons"
        "GroundSpeed" = "GroundSpeedKnots"
        "ActualVerticalSpeed" = "ActualVerticalSpeedFpm"
        "WindDirection" = "WindDirectionDegrees"
        "WindSpeed" = "WindSpeedKnots"
        "IndicatedAirspeed" = "IndicatedAirspeedKnots"
        "TrueAirspeed" = "TrueAirspeedKnots"
        "AmbientTemperature" = "AmbientTemperatureCelsius"
        "AircraftAgl" = "AircraftAglFeet"
        "EngineRpm1" = "GeneralEngineRpm1"
        "EngineRpm2" = "GeneralEngineRpm2"
        "FuelLeftMain" = "FuelLeftMainGallons"
        "FuelRightMain" = "FuelRightMainGallons"
        "LandingLight" = "LandingLight"
        "BeaconLight" = "BeaconLight"
        "NavLight" = "NavLight"
        "TaxiLight" = "TaxiLight"
        "StrobeLight" = "StrobeLight"
        "MasterBattery" = "MasterBattery"
        "AvionicsMaster" = "AvionicsMaster"
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

    if ($Variable -in @("HeadingBug", "PlaneHeading", "WindDirection")) {
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

    throw "The process '$ProcessName' did not expose a main window within $TimeoutSeconds seconds."
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
        RunId = "EXTENDED-$runStamp-$Suite"
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

    $report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $Results | Select-Object TestId, Type, Suite, Language, Phrase, RecognizedText, CommandFeedback, CalloutResponse, FeedbackMessages, SynthesizerVoice, SpeechRate, Variable, Before, Expected, Observed, Tolerance, Attempts, InjectionElapsedMs, LatencySeconds, AwaitingNumberInput, AiIdle, ExpectedInteraction, PostCleanupAwaitingNumberInput, CleanupStatus, SpeechIdleStatus, Passed, Message, OracleDirectory |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    $resultClass = if ($Success) { "pass" } else { "fail" }
    $resultText = if ($Success) { "PASS" } else { "FAIL" }
    $rows = New-Object Text.StringBuilder
    foreach ($item in $Results) {
        $rowClass = if ($item.Passed) { "pass" } else { "fail" }
        $cells = @(
            $item.TestId, $item.Type, $item.Phrase, $item.RecognizedText,
            $item.CommandFeedback, $item.CalloutResponse, $item.Variable,
            $item.Before, $item.Expected, $item.Observed, $item.LatencySeconds,
            $(if ($item.Passed) { "PASS" } else { "FAIL" }), $item.Message
        )
        [void]$rows.Append("<tr>")
        for ($i = 0; $i -lt $cells.Count; $i++) {
            $css = if ($i -eq 11) { " class='$rowClass'" } else { "" }
            [void]$rows.Append("<td$css>").Append((HtmlEncode $cells[$i])).Append("</td>")
        }
        [void]$rows.Append("</tr>")
    }

    $html = @"
<!doctype html>
<html><head><meta charset="utf-8"><title>SimVoice Copilot Extended Flight QA</title>
<style>body{font-family:Segoe UI,Arial;margin:28px;color:#202124}h1{margin-bottom:4px}.pass{color:#187a2f;font-weight:700}.fail{color:#b42318;font-weight:700}table{border-collapse:collapse;width:100%;margin-top:18px}th,td{border:1px solid #d0d5dd;padding:7px 9px;text-align:left;vertical-align:top}th{background:#f2f4f7}code{background:#f2f4f7;padding:2px 4px}.meta{line-height:1.55}</style>
</head><body>
<h1>SimVoice Copilot — Phase 2.4 Extended Flight Functional QA</h1>
<p class="$resultClass">$resultText</p>
<p class="meta">Suite: <code>$(HtmlEncode $Suite)</code><br>App: <code>$(HtmlEncode $AppDisplayName)</code><br>SimConnect: <code>$(HtmlEncode $ConnectedStatus)</code><br>Passed: $(@($Results | Where-Object { $_.Passed }).Count) &nbsp; Failed: $(@($Results | Where-Object { -not $_.Passed }).Count)</p>
<table><thead><tr><th>Test</th><th>Type</th><th>Phrase</th><th>Recognized</th><th>Command feedback</th><th>Call-out response</th><th>Variable</th><th>Before</th><th>Expected</th><th>Observed</th><th>Latency s</th><th>Result</th><th>Message</th></tr></thead><tbody>$($rows.ToString())</tbody></table>
</body></html>
"@
    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

    return [pscustomobject]@{ Json = $jsonPath; Csv = $csvPath; Html = $htmlPath }
}

function Get-FeedbackText {
    param([object]$Injection)
    if ($null -eq $Injection) { return "" }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($value in @([string]$Injection.CommandFeedback, [string]$Injection.CalloutResponse)) {
        if (-not [string]::IsNullOrWhiteSpace($value)) { $parts.Add($value.Trim()) }
    }
    $feedbackProperty = $Injection.PSObject.Properties["FeedbackMessages"]
    if ($null -ne $feedbackProperty) {
        foreach ($value in @($feedbackProperty.Value)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $parts.Add(([string]$value).Trim()) }
        }
    }
    return (($parts | Select-Object -Unique) -join " || ")
}

function Get-ResponseNumbers {
    param([string]$Text)
    $numbers = New-Object 'System.Collections.Generic.List[double]'
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    foreach ($match in [regex]::Matches($Text, '-?\d+(?:[\.,]\d+)?')) {
        $normalized = $match.Value.Replace(',', '.')
        $number = 0.0
        if ([double]::TryParse($normalized, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
            $numbers.Add($number)
        }
    }
    return @($numbers)
}

function Test-ObservedMatch {
    param([string]$Variable, [object]$Observed, [object]$Expected, [double]$Tolerance)
    if ($Observed -is [bool] -or $Expected -is [bool]) {
        return [Convert]::ToBoolean($Observed) -eq [Convert]::ToBoolean($Expected)
    }
    $a = [Convert]::ToDouble($Observed, [Globalization.CultureInfo]::InvariantCulture)
    $b = [Convert]::ToDouble($Expected, [Globalization.CultureInfo]::InvariantCulture)
    return (Get-NumericDifference -Variable $Variable -Observed $a -Expected $b) -le $Tolerance
}

function Get-GuardTolerance {
    param([string]$Variable)
    switch ($Variable) {
        "HeadingBug" { return 2.0 }
        "SelectedAltitude" { return 50.0 }
        "SelectedVerticalSpeed" { return 50.0 }
        default { return 0.0 }
    }
}

function Invoke-CleanupPhrase {
    param(
        [string]$Phrase,
        [string]$Language,
        [string]$Variable = "",
        [string]$Expected = "",
        [double]$Tolerance = 0,
        [string]$Directory,
        [int]$PreDelayMs = 0
    )
    if ([string]::IsNullOrWhiteSpace($Phrase)) { return "Not required" }
    try {
        # Direct commands intentionally suppress an identical repeat for 3.5 seconds.
        # A toggle restore that is injected immediately is therefore recognized but not
        # executed. Drain spoken feedback and wait beyond that production safety window
        # before issuing the same phrase again.
        $idleBeforeCleanup = Wait-QaSpeechIdle -TimeoutMs 30000
        if ($null -eq $idleBeforeCleanup -or -not [bool]$idleBeforeCleanup.Success) {
            return "FAIL: spoken-feedback queue did not become idle before cleanup"
        }
        if ($PreDelayMs -gt 0) {
            Start-Sleep -Milliseconds $PreDelayMs
        }

        if (-not [string]::IsNullOrWhiteSpace($Variable)) {
            $wait = Start-OracleWait -Directory $Directory -Variable $Variable -Expected $Expected -Tolerance $Tolerance -TimeoutSeconds 25
            Start-Sleep -Milliseconds 400
            $cleanupInjection = Invoke-InternalAudioRequest -Action synthesize -Text $Phrase -Language $Language -SpeechRate 0 -TimeoutMs 30000 -PostCommandWaitMs 500 -CorrelationId ("cleanup-" + [guid]::NewGuid().ToString("N"))
            if ($null -eq $cleanupInjection -or -not [bool]$cleanupInjection.Success) {
                Stop-And-WaitProcess -Process $wait.Process
                try { $wait.Process.Dispose() } catch { }
                $cleanupError = if ($null -ne $cleanupInjection) { [string]$cleanupInjection.Error } else { "empty bridge response" }
                return "FAIL: cleanup audio injection failed: " + $cleanupError
            }
            $cleanupExited = $wait.Process.WaitForExit(30000)
            if (-not $cleanupExited) { Stop-And-WaitProcess -Process $wait.Process }
            $report = Read-OracleReport -Path $wait.ReportPath
            try { $wait.Process.Dispose() } catch { }
            if ($null -ne $report -and [bool]$report.Success) { return "PASS" }
            return "FAIL: cleanup target was not observed"
        }
        $cleanupInjection = Invoke-InternalAudioRequest -Action synthesize -Text $Phrase -Language $Language -SpeechRate 0 -TimeoutMs 20000 -PostCommandWaitMs 600 -CorrelationId ("cleanup-" + [guid]::NewGuid().ToString("N"))
        return $(if ($null -ne $cleanupInjection -and [bool]$cleanupInjection.Success) { "PASS" } else { "FAIL: " + [string]$cleanupInjection.Error })
    }
    catch { return "FAIL: " + $_.Exception.Message }
}

if (-not (Test-Path -LiteralPath $oracleScript)) {
    throw "Oracle launcher not found: $oracleScript"
}
if (-not (Test-Path -LiteralPath $catalogPath)) {
    throw "Functional test catalog not found: $catalogPath"
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

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

Write-RunLog "SimVoice Copilot QA Phase 2.4.4 — Extended Flight Functional QA"
Write-RunLog ("Suite: {0}" -f $Suite)
Write-RunLog ("Output: {0}" -f $OutputDirectory)

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$suiteProperty = $catalog.suites.PSObject.Properties[$Suite]
if ($null -eq $suiteProperty) {
    throw "Suite '$Suite' was not found in $catalogPath."
}
$tests = @($suiteProperty.Value)
if ($tests.Count -eq 0) { throw "Suite '$Suite' contains no tests." }

$app = Find-SimVoiceApp
Write-RunLog ("Installed MSIX: {0} [{1}]" -f $app.Name, $app.AppID)

$simVoiceProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $simVoiceProcess -and -not $SkipAppLaunch) {
    Write-RunLog "Launching installed MSIX package."
    Start-Process "explorer.exe" ("shell:AppsFolder\{0}" -f $app.AppID)
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
$initialReset = Reset-QaInteractionState -TimeoutMs 10000
if (-not [bool]$initialReset.Success) { throw ("Could not isolate the QA interaction state before the suite: {0}" -f [string]$initialReset.Error) }
$initialSpeechIdle = Wait-QaSpeechIdle -TimeoutMs 30000
if (-not [bool]$initialSpeechIdle.Success) { throw ("Spoken feedback was not idle before the suite: {0}" -f [string]$initialSpeechIdle.Error) }
Write-RunLog "QA interaction state reset and spoken-feedback queue idle before the suite."
Write-Host ""
Write-Host "EXTENDED FLIGHT PRECHECK: PASS" -ForegroundColor Green
Write-Host ("  Voice profile/language : {0}" -f $suiteLanguage)
Write-Host ("  Internal audio pipe    : {0}" -f $pipeName)
Write-Host "  Microphone             : not used"
Write-Host "  Audio source           : Windows speech synthesis -> 16 kHz PCM -> normal Vosk pipeline"
Write-Host "  Simulator              : active flight; do not operate the tested controls manually"
Write-Host ""

$results = New-Object 'System.Collections.Generic.List[object]'
$testNumber = 0

foreach ($test in $tests) {
    $testNumber++
    $testId = [string]$test.id
    $testType = if ($null -ne $test.PSObject.Properties["type"]) { [string]$test.type } else { "value" }
    $language = [string]$test.language
    $safeTestId = $testId -replace '[^A-Za-z0-9_.-]', '_'
    $testRoot = Join-Path $oracleRoot ("{0:00}-{1}" -f $testNumber, $safeTestId)
    $beforeDirectory = Join-Path $testRoot "before"
    Write-Host ""
    Write-Host ("[{0}/{1}] {2} [{3}]" -f $testNumber, $tests.Count, $testId, $testType) -ForegroundColor Cyan

    $beforeRun = Invoke-OracleSync -Mode "Snapshot" -Directory $beforeDirectory -TimeoutSeconds 20 -IntervalMs 500 -UseNoBuild
    $beforeReport = Read-OracleReport -Path $beforeRun.ReportPath
    if ($beforeRun.ExitCode -ne 0 -or $null -eq $beforeReport -or @($beforeReport.Snapshots).Count -eq 0) {
        $results.Add([pscustomobject][ordered]@{ TestId=$testId;Type=$testType;Suite=$Suite;Language=$language;Phrase="";RecognizedText="";CommandFeedback="";CalloutResponse="";FeedbackMessages="";SynthesizerVoice="";SpeechRate=0;Variable="";Before="";Expected="";Observed="";Tolerance=0;Attempts=0;InjectionElapsedMs=0;LatencySeconds=0;AwaitingNumberInput=$false;CleanupStatus="";Passed=$false;Message="Could not capture the pre-command Oracle snapshot.";OracleDirectory=$testRoot })
        Write-RunLog ("{0}: FAIL - pre-command snapshot unavailable" -f $testId) "ERROR"
        continue
    }

    $beforeSnapshot = @($beforeReport.Snapshots)[-1]
    $phrase = if ($null -ne $test.PSObject.Properties["phrase"]) { [string]$test.phrase } else { "" }
    $variable = if ($null -ne $test.PSObject.Properties["variable"]) { [string]$test.variable } else { "" }
    $beforeObserved = if (-not [string]::IsNullOrWhiteSpace($variable)) { Get-SnapshotObservedValue -Snapshot $beforeSnapshot -Variable $variable } else { "" }
    $expected = ""
    $observed = ""
    $tolerance = if ($null -ne $test.PSObject.Properties["tolerance"]) { [double]$test.tolerance } else { 0.0 }
    $attempts = 0
    $latency = 0.0
    $injectionElapsedMs = 0
    $speechRate = 0
    $recognizedText = ""
    $commandFeedback = ""
    $calloutResponse = ""
    $feedbackMessages = ""
    $synthesizerVoice = ""
    $awaitingNumberInput = $false
    $aiIdle = $true
    $postCleanupAwaitingNumberInput = $false
    $cleanupStatus = ""
    $speechIdleStatus = ""
    $expectedInteraction = ""
    $passed = $false
    $message = ""
    $lastDirectory = $testRoot

    try {
        if ($testType -eq "callout") {
            $attempts = 1
            $speechRate = Get-TestSpeechRate -Test $test -Attempt 1
            Write-Host ("Audio    : internally synthesize '{0}'" -f $phrase) -ForegroundColor Yellow
            $started = Get-Date
            $injection = Invoke-InternalAudioRequest -Action synthesize -Text $phrase -Language $language -SpeechRate $speechRate -WaitForCalloutResponse $true -PostCommandWaitMs 300 -TimeoutMs (([int]$test.timeoutSeconds * 1000) + 10000) -CorrelationId $testId
            $latency = [Math]::Round(((Get-Date)-$started).TotalSeconds,3)
            $recognizedText = [string]$injection.RecognizedText
            $commandFeedback = [string]$injection.CommandFeedback
            $calloutResponse = [string]$injection.CalloutResponse
            $feedbackMessages = Get-FeedbackText -Injection $injection
            $synthesizerVoice = [string]$injection.SynthesizerVoice
            $injectionElapsedMs = [int64]$injection.ElapsedMs
            $awaitingNumberInput = [bool]$injection.AwaitingNumberInput
            $numbers = @(Get-ResponseNumbers -Text $calloutResponse)
            $errors = New-Object 'System.Collections.Generic.List[string]'
            if (-not [bool]$injection.Success) { $errors.Add("Injection failed: " + [string]$injection.Error) }
            if ([string]::IsNullOrWhiteSpace($calloutResponse)) { $errors.Add("No final call-out response was captured.") }
            foreach ($measurement in @($test.measurements)) {
                $index = [int]$measurement.responseNumberIndex
                if ($index -ge $numbers.Count) { $errors.Add("Response numeric value #$index was not present."); continue }
                $oracleValue = Get-SnapshotObservedValue -Snapshot $beforeSnapshot -Variable ([string]$measurement.variable)
                $responseValue = [double]$numbers[$index]
                if (-not (Test-ObservedMatch -Variable ([string]$measurement.variable) -Observed $responseValue -Expected $oracleValue -Tolerance ([double]$measurement.tolerance))) {
                    $errors.Add(("{0}: response={1}, oracle={2}, tolerance={3}" -f $measurement.variable,$responseValue,$oracleValue,$measurement.tolerance))
                }
            }
            $passed = $errors.Count -eq 0
            $message = if ($passed) { "Call-out response matched the independent Oracle snapshot." } else { $errors -join " | " }
            $observed = $calloutResponse
            $expected = (@($test.measurements) | ForEach-Object { "{0}={1}" -f $_.variable,(Get-SnapshotObservedValue -Snapshot $beforeSnapshot -Variable ([string]$_.variable)) }) -join "; "
        }
        elseif ($testType -eq "negative") {
            $attempts = 1
            $speechRate = Get-TestSpeechRate -Test $test -Attempt 1
            $expectedInteraction = if ($null -ne $test.PSObject.Properties["expectedInteraction"]) { [string]$test.expectedInteraction } else { "no-match" }
            Write-Host ("Negative audio: '{0}'" -f $phrase) -ForegroundColor Yellow
            $started = Get-Date
            # Return as soon as the recognition outcome is known. Numeric prompts are
            # scheduled 1.5 seconds later, so the QA reset below can cancel them before
            # they are spoken or contaminate the following case.
            $waitForAiIdle = $false
            if ($null -ne $test.PSObject.Properties["waitForAiIdle"]) {
                $waitForAiIdle = [bool]$test.waitForAiIdle
            }
            elseif ($expectedInteraction -eq "safe-rejection") {
                $waitForAiIdle = $true
            }

            $injection = Invoke-InternalAudioRequest -Action synthesize -Text $phrase -Language $language -SpeechRate $speechRate -TimeoutMs (([int]$test.timeoutSeconds * 1000)+10000) -WaitForAiIdle $waitForAiIdle -PostCommandWaitMs 100 -CorrelationId $testId
            $latency = [Math]::Round(((Get-Date)-$started).TotalSeconds,3)
            $recognizedText = [string]$injection.RecognizedText
            $commandFeedback = [string]$injection.CommandFeedback
            $calloutResponse = [string]$injection.CalloutResponse
            $feedbackMessages = Get-FeedbackText -Injection $injection
            $synthesizerVoice = [string]$injection.SynthesizerVoice
            $injectionElapsedMs = [int64]$injection.ElapsedMs
            $awaitingNumberInput = [bool]$injection.AwaitingNumberInput
            $aiIdle = if ($null -ne $injection.PSObject.Properties["AiIdle"]) { [bool]$injection.AiIdle } else { -not $waitForAiIdle }

            $errors = New-Object 'System.Collections.Generic.List[string]'

            # For a deliberate no-match case, the private bridge reports Success=false
            # when Vosk produced native text but deterministic arbitration rejected every
            # candidate. That is the exact safety outcome this test is intended to prove,
            # not an audio transport or application failure.
            $expectedDeterministicNoMatch = $false
            $injectionError = [string]$injection.Error
            if ($expectedInteraction -eq "no-match" -and
                -not [bool]$injection.Success -and
                -not $awaitingNumberInput -and
                $injectionError -match '(?i)deterministic command arbitration rejected every candidate') {
                $expectedDeterministicNoMatch = $true
                Write-RunLog ("{0}: expected deterministic no-match observed: {1}" -f $testId, $injectionError)
            }

            if (-not [bool]$injection.Success -and -not $expectedDeterministicNoMatch) {
                $errors.Add("Injection did not complete successfully: " + $injectionError)
            }
            if ($expectedInteraction -eq "value-prompt" -and -not $awaitingNumberInput) {
                $errors.Add("Expected the invalid/incomplete command to enter target-value mode, but it did not.")
            }
            elseif ($expectedInteraction -eq "no-match" -and $awaitingNumberInput) {
                $errors.Add("Unexpected target-value mode was entered for a phrase that should be rejected as no-match.")
            }
            elseif ($expectedInteraction -eq "safe-rejection") {
                if ($waitForAiIdle -and -not $aiIdle) {
                    $errors.Add("The local AI fallback did not become idle before the safety result was evaluated.")
                }

                if (-not $awaitingNumberInput) {
                    $requiredPattern = if ($null -ne $test.PSObject.Properties["requiredFeedbackPattern"]) {
                        [string]$test.requiredFeedbackPattern
                    } else {
                        "(?i)(no safe match|no matching command|not executed|invalid|blocked)"
                    }

                    if ($feedbackMessages -match '(?i)AI fallback analyzing' -and
                        $feedbackMessages -notmatch '(?i)(no safe match|no matching command|not executed|invalid|blocked)') {
                        $errors.Add("Only an interim AI analyzing message was captured; no final safe rejection was observed.")
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($requiredPattern) -and
                            $feedbackMessages -notmatch $requiredPattern) {
                        $errors.Add("The phrase remained idle, but the expected final safe-rejection feedback was not captured: $feedbackMessages")
                    }
                }
            }
            elseif ($expectedInteraction -ne "value-prompt" -and $expectedInteraction -ne "no-match") {
                $errors.Add("Unsupported expectedInteraction value: $expectedInteraction")
            }

            # Cleanup is a direct QA housekeeping action, not a second recognition test.
            # The previous implementation synthesized 'cancel', but every synthetic
            # injection resets numeric mode before recognition, so that cleanup could
            # never test or clear the intended state reliably.
            $reset = Reset-QaInteractionState -TimeoutMs 5000
            $postCleanupAwaitingNumberInput = [bool]$reset.AwaitingNumberInput
            $cleanupStatus = if ([bool]$reset.Success -and -not $postCleanupAwaitingNumberInput) { "PASS: interaction state reset" } else { "FAIL: " + [string]$reset.Error }
            if (-not [bool]$reset.Success -or $postCleanupAwaitingNumberInput) {
                $errors.Add("QA cleanup did not return the app to an idle command state: $cleanupStatus")
            }

            Start-Sleep -Milliseconds 200
            $afterDirectory = Join-Path $testRoot "after"
            $afterRun = Invoke-OracleSync -Mode "Snapshot" -Directory $afterDirectory -TimeoutSeconds 20 -IntervalMs 500 -UseNoBuild
            $afterReport = Read-OracleReport -Path $afterRun.ReportPath
            if ($afterRun.ExitCode -ne 0 -or $null -eq $afterReport -or @($afterReport.Snapshots).Count -eq 0) { $errors.Add("Post-command snapshot unavailable.") }
            else {
                $afterSnapshot = @($afterReport.Snapshots)[-1]
                foreach ($guard in @($test.guardVariables)) {
                    $beforeValue = Get-SnapshotObservedValue -Snapshot $beforeSnapshot -Variable ([string]$guard)
                    $afterValue = Get-SnapshotObservedValue -Snapshot $afterSnapshot -Variable ([string]$guard)
                    $guardTolerance = Get-GuardTolerance -Variable ([string]$guard)
                    if (-not (Test-ObservedMatch -Variable ([string]$guard) -Observed $afterValue -Expected $beforeValue -Tolerance $guardTolerance)) {
                        $errors.Add(("Unexpected state change {0}: {1} -> {2}" -f $guard,$beforeValue,$afterValue))
                    }
                }
            }
            $forbidden = [string]$test.forbiddenFeedbackPattern
            if (-not [string]::IsNullOrWhiteSpace($forbidden) -and $feedbackMessages -match $forbidden) { $errors.Add("Feedback indicates that a simulator command may have executed: $feedbackMessages") }
            $speechIdleStatus = if ($null -ne $reset.Diagnostics -and [bool]$reset.Diagnostics.speechIdle) { "PASS" } else { "FAIL" }
            $passed = $errors.Count -eq 0
            if ($passed) {
                $message = if ($expectedInteraction -eq "value-prompt") {
                    "No protected state changed; the expected target-value prompt state was observed and cleared before speech."
                } elseif ($expectedInteraction -eq "safe-rejection") {
                    if ($awaitingNumberInput) {
                        "No protected state changed; the phrase was safely diverted to target-value mode and the state was cleared."
                    } else {
                        "No protected state changed; the final AI/deterministic rejection was observed and no residual operation remained."
                    }
                } else {
                    if ($expectedDeterministicNoMatch) {
                        "No protected state changed; Vosk produced text and deterministic command arbitration rejected every candidate, as expected."
                    } else {
                        "No protected state changed; the phrase was rejected and the app remained idle."
                    }
                }
            } else {
                $message = $errors -join " | "
            }
            $expected = "No protected state change; interaction=$expectedInteraction; aiIdle=$waitForAiIdle; cleanup=idle"
            $observed = if ($expectedDeterministicNoMatch -and [string]::IsNullOrWhiteSpace($feedbackMessages)) {
                "Deterministic no-match: " + $injectionError
            } else {
                $feedbackMessages
            }
        }
        else {
            # value and toggle tests use the Oracle wait path.
            if ($testType -eq "toggle") {
                $expectedBool = -not [Convert]::ToBoolean($beforeObserved)
                $expected = $expectedBool.ToString().ToLowerInvariant()
            }
            else {
                $variant = Select-TestVariant -Test $test -Observed $beforeObserved
                if ($null -eq $variant) { throw "All configured target variants already match the current simulator value." }
                $phrase = [string]$variant.phrase
                $expected = [string]$variant.expected
            }

            while (-not $passed -and $attempts -lt $MaxAttempts) {
                $attempts++
                $speechRate = Get-TestSpeechRate -Test $test -Attempt $attempts
                $attemptDirectory = Join-Path $testRoot ("attempt-{0}" -f $attempts)
                $lastDirectory = $attemptDirectory
                Write-Host ("Variable : {0}" -f $variable) -ForegroundColor DarkGray
                Write-Host ("Before   : {0}" -f $beforeObserved) -ForegroundColor DarkGray
                Write-Host ("Expected : {0}" -f $expected) -ForegroundColor DarkGray
                Write-Host ("Audio    : internally synthesize '{0}'" -f $phrase) -ForegroundColor Yellow
                $wait = Start-OracleWait -Directory $attemptDirectory -Variable $variable -Expected $expected -Tolerance $tolerance -TimeoutSeconds ([int]$test.timeoutSeconds)
                Start-Sleep -Milliseconds 500
                $started = Get-Date
                $injection = Invoke-InternalAudioRequest -Action synthesize -Text $phrase -Language $language -SpeechRate $speechRate -TimeoutMs (([int]$test.timeoutSeconds*1000)+10000) -PostCommandWaitMs 500 -CorrelationId ("{0}-{1}" -f $testId,$attempts)
                $recognizedText = [string]$injection.RecognizedText
                $commandFeedback = [string]$injection.CommandFeedback
                $calloutResponse = [string]$injection.CalloutResponse
                $feedbackMessages = Get-FeedbackText -Injection $injection
                $synthesizerVoice = [string]$injection.SynthesizerVoice
                $injectionElapsedMs = [int64]$injection.ElapsedMs
                $awaitingNumberInput = [bool]$injection.AwaitingNumberInput
                $waitExited = $wait.Process.WaitForExit(([int]$test.timeoutSeconds+20)*1000)
                if (-not $waitExited) { Stop-And-WaitProcess -Process $wait.Process }
                $latency = [Math]::Round(((Get-Date)-$started).TotalSeconds,3)
                $attemptReport = Read-OracleReport -Path $wait.ReportPath
                try { $wait.Process.Dispose() } catch { }
                if ($null -ne $attemptReport -and $null -ne $attemptReport.Assertion) {
                    $observed = [string]$attemptReport.Assertion.Observed
                    $passed = [bool]$attemptReport.Success
                    $message = [string]$attemptReport.Message
                } else { $message = "Oracle did not generate a valid assertion report." }
                if (-not $passed -and $attempts -lt $MaxAttempts) { Start-Sleep -Seconds 1 }
            }
            if ($passed -and $testType -eq "toggle" -and $null -ne $test.PSObject.Properties["restore"] -and [bool]$test.restore) {
                $cleanupStatus = Invoke-CleanupPhrase -Phrase $phrase -Language $language -Variable $variable -Expected ([Convert]::ToString($beforeObserved,[Globalization.CultureInfo]::InvariantCulture)) -Tolerance $tolerance -Directory (Join-Path $testRoot "restore") -PreDelayMs 4000
                if ($cleanupStatus -notmatch '^PASS(?:$|:)') {
                    $passed = $false
                    $message = (($message + " | State restoration failed: " + $cleanupStatus).Trim())
                }
            }
            if ($null -ne $test.PSObject.Properties["cleanupPhrase"]) {
                $cleanupStatus = Invoke-CleanupPhrase -Phrase ([string]$test.cleanupPhrase) -Language $language -Variable ([string]$test.cleanupVariable) -Expected ([string]$test.cleanupExpected) -Tolerance ([double]$test.cleanupTolerance) -Directory (Join-Path $testRoot "cleanup")
                if ($cleanupStatus -notmatch '^PASS(?:$|:)') {
                    $passed = $false
                    $message = (($message + " | Cleanup failed: " + $cleanupStatus).Trim())
                }
            }
        }
    }
    catch {
        $passed = $false
        $message = $_.Exception.Message
    }

    if ($testType -ne "negative") {
        try {
            $speechIdle = Wait-QaSpeechIdle -TimeoutMs 30000
            $speechIdleStatus = if ([bool]$speechIdle.Success) { "PASS" } else { "FAIL: " + [string]$speechIdle.Error }
            if (-not [bool]$speechIdle.Success) {
                $passed = $false
                $message = (($message + " | Spoken-feedback queue did not become idle: " + [string]$speechIdle.Error).Trim())
            }
        }
        catch {
            $speechIdleStatus = "FAIL: " + $_.Exception.Message
            $passed = $false
            $message = (($message + " | " + $speechIdleStatus).Trim())
        }
    }

    $result = [pscustomobject][ordered]@{
        TestId=$testId;Type=$testType;Suite=$Suite;Language=$language;Phrase=$phrase;
        RecognizedText=$recognizedText;CommandFeedback=$commandFeedback;CalloutResponse=$calloutResponse;FeedbackMessages=$feedbackMessages;
        SynthesizerVoice=$synthesizerVoice;SpeechRate=$speechRate;Variable=$variable;Before=[string]$beforeObserved;Expected=$expected;Observed=$observed;
        Tolerance=$tolerance;Attempts=$attempts;InjectionElapsedMs=$injectionElapsedMs;LatencySeconds=$latency;AwaitingNumberInput=$awaitingNumberInput;AiIdle=$aiIdle;
        ExpectedInteraction=$expectedInteraction;PostCleanupAwaitingNumberInput=$postCleanupAwaitingNumberInput;CleanupStatus=$cleanupStatus;SpeechIdleStatus=$speechIdleStatus;
        Passed=$passed;Message=$message;OracleDirectory=$lastDirectory
    }
    $results.Add($result)
    if ($passed) {
        Write-Host ("PASS: {0}" -f $message) -ForegroundColor Green
        Write-RunLog ("{0}: PASS type={1} phrase='{2}' observed='{3}' latency={4}s" -f $testId,$testType,$phrase,$observed,$latency)
    } else {
        Write-Host ("FAIL: {0}" -f $message) -ForegroundColor Red
        Write-RunLog ("{0}: FAIL type={1} phrase='{2}': {3}" -f $testId,$testType,$phrase,$message) "ERROR"
    }
}

Copy-FeedbackLogs -Since $runStarted
$overallSuccess = ($results.Count -eq $tests.Count) -and (@($results | Where-Object { -not $_.Passed }).Count -eq 0)
$resultArray = @($results | ForEach-Object { $_ })
$reports = Write-FunctionalReports -Results $resultArray -Success $overallSuccess -AppDisplayName ([string]$app.Name) -AppId ([string]$app.AppID) -ConnectedStatus $connectedStatus

if ($CloseAppAtEnd -and $null -ne $simVoiceProcess -and -not $simVoiceProcess.HasExited) {
    try { $simVoiceProcess.CloseMainWindow() | Out-Null; if (-not $simVoiceProcess.WaitForExit(10000)) { Stop-Process -Id $simVoiceProcess.Id -Force -ErrorAction SilentlyContinue } } catch { }
}

Write-Host ""
Write-Host $(if ($overallSuccess) { "EXTENDED FLIGHT FUNCTIONAL RESULT: PASS" } else { "EXTENDED FLIGHT FUNCTIONAL RESULT: FAIL" }) -ForegroundColor $(if ($overallSuccess) { "Green" } else { "Red" })
Write-Host ("Results: {0}" -f $OutputDirectory)
Write-Host ("HTML   : {0}" -f $reports.Html)
Write-Host ("JSON   : {0}" -f $reports.Json)
Write-Host ("CSV    : {0}" -f $reports.Csv)
if ($overallSuccess) { exit 0 }
exit 1
