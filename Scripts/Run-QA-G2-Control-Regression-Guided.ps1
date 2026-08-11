[CmdletBinding()]
param(
    [string]$AppIdPattern = "SimTechAviation.SimVoiceCopilot.Dev_*",
    [string]$ProcessName = "SimVoiceCopilotApp",
    [string]$PipeName = "SimVoiceCopilot.QA.InternalAudio.v1",
    [string]$SimConnectDll = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp\Microsoft.FlightSimulator.SimConnect.dll",
    [string]$OutputDirectory = "",
    [ValidateRange(10, 60)]
    [int]$StateTimeoutSeconds = 25
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$oracleScript = Join-Path $PSScriptRoot "Run-QA-SimConnect-Oracle.ps1"
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputDirectory = Join-Path $projectRoot "QA-Runs\FinalRegression\G2-$stamp"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Quote-ProcessArgument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Get-WindowsPowerShell {
    $candidate = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    $command = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    throw "Windows PowerShell 5.1 was not found."
}

function Invoke-BridgeRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [string]$Text = "",
        [string]$Language = "",
        [int]$TimeoutMs = 30000
    )

    $pipe = $null
    $reader = $null
    $writer = $null
    try {
        $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
            ".",
            $PipeName,
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
            CorrelationId = [guid]::NewGuid().ToString("N")
            Text = $Text
            Language = $Language
            TimeoutMs = $TimeoutMs
            SpeechRate = 0
            WaitForCalloutResponse = $false
            WaitForAiIdle = $false
            PostCommandWaitMs = 700
        }
        $writer.WriteLine(($request | ConvertTo-Json -Compress))
        $task = $reader.ReadLineAsync()
        if (-not $task.Wait($TimeoutMs + 10000)) {
            throw "Timed out waiting for the Internal Audio QA bridge response."
        }
        if ([string]::IsNullOrWhiteSpace($task.Result)) {
            throw "Internal Audio QA bridge returned an empty response."
        }
        return $task.Result | ConvertFrom-Json
    }
    finally {
        if ($writer) { try { $writer.Dispose() } catch { } }
        if ($reader) { try { $reader.Dispose() } catch { } }
        if ($pipe) { try { $pipe.Dispose() } catch { } }
    }
}

function Start-PrivateQaApp {
    $apps = @(Get-StartApps | Where-Object { $_.AppID -like $AppIdPattern })
    if ($apps.Count -ne 1) {
        $detail = ($apps | ForEach-Object { "  $($_.Name) -> $($_.AppID)" }) -join [Environment]::NewLine
        throw "Expected exactly one private QA app matching '$AppIdPattern'. Found $($apps.Count).$([Environment]::NewLine)$detail"
    }
    $existing = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $existing) {
        try {
            $existingPing = Invoke-BridgeRequest -Action "ping" -TimeoutMs 2500
            if ($null -ne $existingPing -and [bool]$existingPing.Success) {
                return [pscustomobject]@{ App = $apps[0]; Ping = $existingPing }
            }
        }
        catch { }

        Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 700
    }

    Start-Process "shell:AppsFolder\$($apps[0].AppID)"

    $deadline = (Get-Date).AddSeconds(60)
    $lastError = ""
    while ((Get-Date) -lt $deadline) {
        try {
            $ping = Invoke-BridgeRequest -Action "ping" -TimeoutMs 3000
            if ($null -ne $ping -and [bool]$ping.Success) {
                return [pscustomobject]@{ App = $apps[0]; Ping = $ping }
            }
            $lastError = if ($null -ne $ping) { [string]$ping.Error } else { "No response" }
        }
        catch { $lastError = $_.Exception.Message }
        Start-Sleep -Milliseconds 500
    }
    throw "Private QA app bridge was not ready. Last error: $lastError"
}

function Invoke-OracleProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$Build
    )

    $directory = Join-Path $OutputDirectory ("oracle-" + $Name)
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $stdout = Join-Path $directory "console-out.log"
    $stderr = Join-Path $directory "console-error.log"

    $arguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $oracleScript,
        "-Mode", "Probe",
        "-OutputDirectory", $directory,
        "-SimConnectDll", $SimConnectDll,
        "-TimeoutSeconds", "20",
        "-IntervalMs", "250"
    )
    if (-not $Build) { $arguments += "-NoBuild" }

    $argumentString = ($arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "
    $process = Start-Process -FilePath (Get-WindowsPowerShell) `
        -ArgumentList $argumentString `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -WindowStyle Hidden `
        -PassThru
    $process.WaitForExit()
    $exitCode = [int]$process.ExitCode
    $process.Dispose()

    $reportPath = Join-Path $directory "oracle-report.json"
    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        throw "Oracle probe '$Name' failed. Review: $directory"
    }

    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$report.Success -or @($report.Snapshots).Count -eq 0) {
        throw "Oracle probe '$Name' did not return a valid snapshot. Review: $reportPath"
    }
    return @($report.Snapshots)[-1]
}

function Wait-ForState {
    param(
        [Parameter(Mandatory = $true)][string]$StepId,
        [Parameter(Mandatory = $true)][scriptblock]$Predicate
    )

    $deadline = (Get-Date).AddSeconds($StateTimeoutSeconds)
    $attempt = 0
    $lastSnapshot = $null
    while ((Get-Date) -lt $deadline) {
        $attempt++
        $lastSnapshot = Invoke-OracleProbe -Name ("{0}-{1:D2}" -f $StepId, $attempt)
        if (& $Predicate $lastSnapshot) {
            return $lastSnapshot
        }
        Start-Sleep -Milliseconds 600
    }
    return $lastSnapshot
}

function Invoke-ControlStep {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string]$Phrase,
        [Parameter(Mandatory = $true)][string]$Language,
        [Parameter(Mandatory = $true)][scriptblock]$Predicate,
        [Parameter(Mandatory = $true)][string]$ObservedProperty
    )

    Write-Host ""
    Write-Host ("[{0}] {1}" -f $Id, $Description) -ForegroundColor Cyan
    Write-Host ("Voice command: {0}" -f $Phrase) -ForegroundColor Yellow
    $started = Get-Date
    $injection = Invoke-BridgeRequest -Action "synthesize" -Text $Phrase -Language $Language -TimeoutMs 40000
    $injectionPath = Join-Path $OutputDirectory ("{0}-injection.json" -f $Id)
    $injection | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $injectionPath -Encoding UTF8

    $snapshot = $null
    $passed = $false
    $errorText = ""
    if (-not [bool]$injection.Success) {
        $errorText = "Voice injection failed: " + [string]$injection.Error
    }
    else {
        $snapshot = Wait-ForState -StepId $Id -Predicate $Predicate
        if ($null -ne $snapshot) {
            $passed = [bool](& $Predicate $snapshot)
        }
        if (-not $passed) {
            $errorText = "The simulator state did not reach the expected value within $StateTimeoutSeconds seconds."
        }
    }

    $observed = $null
    if ($null -ne $snapshot -and $null -ne $snapshot.PSObject.Properties[$ObservedProperty]) {
        $observed = $snapshot.PSObject.Properties[$ObservedProperty].Value
    }
    $finished = Get-Date
    $result = [pscustomobject][ordered]@{
        id = $Id
        description = $Description
        phrase = $Phrase
        language = $Language
        startedAt = $started.ToString("o")
        finishedAt = $finished.ToString("o")
        durationSeconds = [Math]::Round(($finished - $started).TotalSeconds, 3)
        injectionSuccess = [bool]$injection.Success
        recognizedText = [string]$injection.RecognizedText
        commandFeedback = [string]$injection.CommandFeedback
        feedbackMessages = @($injection.FeedbackMessages)
        observedProperty = $ObservedProperty
        observedValue = $observed
        success = $passed
        error = $errorText
    }

    if ($passed) {
        Write-Host ("PASS — {0}={1}" -f $ObservedProperty, $observed) -ForegroundColor Green
    }
    else {
        Write-Host ("FAIL — {0}" -f $errorText) -ForegroundColor Red
    }
    return $result
}

Write-Host ""
Write-Host "Vision Jet G2 repeated-control and interaction-lock regression" -ForegroundColor Cyan
Write-Host "1. Run MSFS 2024 and load the Cirrus Vision Jet G2 in an airborne flight." -ForegroundColor Yellow
Write-Host "2. Set GEAR UP, FLAPS UP and AUTOPILOT OFF before starting." -ForegroundColor Yellow
Write-Host "3. Keep the aircraft stable and do not touch tested controls during automatic steps." -ForegroundColor Yellow
Read-Host "Press ENTER when the aircraft is ready"

$appState = Start-PrivateQaApp
$ping = $appState.Ping
$voiceLanguage = [string]$ping.VoiceLanguage
$isSpanish = $voiceLanguage.StartsWith("es", [StringComparison]::OrdinalIgnoreCase)
$language = if ($isSpanish) { "es-ES" } else { "en-US" }

$phrases = if ($isSpanish) {
    @{
        GearDown = "bajar tren"
        GearUp = "subir tren"
        FlapsDown = "flaps completamente abajo"
        FlapsUp = "flaps completamente arriba"
        Autopilot = "piloto automático"
        HeadingOn = "activar rumbo"
        HeadingOff = "desactivar rumbo"
        AltitudeHold = "mantener altitud del piloto automático"
    }
}
else {
    @{
        GearDown = "gear down"
        GearUp = "gear up"
        FlapsDown = "flaps full down"
        FlapsUp = "flaps full up"
        Autopilot = "autopilot"
        HeadingOn = "heading on"
        HeadingOff = "heading off"
        AltitudeHold = "autopilot altitude hold"
    }
}

$initial = Invoke-OracleProbe -Name "00-preflight" -Build
$aircraftTitle = [string]$initial.AircraftTitle
if ($aircraftTitle.IndexOf("VISION", [StringComparison]::OrdinalIgnoreCase) -lt 0 -and
    $aircraftTitle.IndexOf("SF50", [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw "The active aircraft is '$aircraftTitle'. Load the Cirrus Vision Jet G2 before running this regression."
}
if (-not [bool]$initial.FlightActive) { throw "MSFS does not report an active flight." }
if ([int]$initial.GearHandlePosition -ne 0 -or [double]$initial.FlapsHandleIndex -ne 0 -or [bool]$initial.AutopilotMaster) {
    $initial | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory "preflight-state.json") -Encoding UTF8
    throw "Preflight requires GEAR UP, FLAPS UP and AUTOPILOT OFF. Correct the cockpit state and rerun."
}

$results = New-Object 'System.Collections.Generic.List[object]'
$results.Add((Invoke-ControlStep -Id "01-gear-down-1" -Description "First GEAR DOWN command" -Phrase $phrases.GearDown -Language $language -ObservedProperty "GearHandlePosition" -Predicate { param($s) [int]$s.GearHandlePosition -eq 1 }))
$results.Add((Invoke-ControlStep -Id "02-gear-up-1" -Description "First GEAR UP command after GEAR DOWN" -Phrase $phrases.GearUp -Language $language -ObservedProperty "GearHandlePosition" -Predicate { param($s) [int]$s.GearHandlePosition -eq 0 }))
$results.Add((Invoke-ControlStep -Id "03-gear-down-2" -Description "Second GEAR DOWN command catches one-shot latch regressions" -Phrase $phrases.GearDown -Language $language -ObservedProperty "GearHandlePosition" -Predicate { param($s) [int]$s.GearHandlePosition -eq 1 }))
$results.Add((Invoke-ControlStep -Id "04-gear-up-2" -Description "Second GEAR UP command catches blocked cockpit interaction" -Phrase $phrases.GearUp -Language $language -ObservedProperty "GearHandlePosition" -Predicate { param($s) [int]$s.GearHandlePosition -eq 0 }))
$results.Add((Invoke-ControlStep -Id "05-flaps-down-1" -Description "First full FLAPS DOWN command through the Vision Jet adapter" -Phrase $phrases.FlapsDown -Language $language -ObservedProperty "FlapsHandleIndex" -Predicate { param($s) [double]$s.FlapsHandleIndex -gt 0 }))
$results.Add((Invoke-ControlStep -Id "06-flaps-up-1" -Description "First full FLAPS UP command" -Phrase $phrases.FlapsUp -Language $language -ObservedProperty "FlapsHandleIndex" -Predicate { param($s) [Math]::Abs([double]$s.FlapsHandleIndex) -le 0.01 }))
$results.Add((Invoke-ControlStep -Id "07-flaps-down-2" -Description "Second full FLAPS DOWN command catches repeated-use regressions" -Phrase $phrases.FlapsDown -Language $language -ObservedProperty "FlapsHandleIndex" -Predicate { param($s) [double]$s.FlapsHandleIndex -gt 0 }))
$results.Add((Invoke-ControlStep -Id "08-flaps-up-2" -Description "Second full FLAPS UP command" -Phrase $phrases.FlapsUp -Language $language -ObservedProperty "FlapsHandleIndex" -Predicate { param($s) [Math]::Abs([double]$s.FlapsHandleIndex) -le 0.01 }))
$results.Add((Invoke-ControlStep -Id "09-ap-master" -Description "Engage AP master through the Vision Jet BVar route" -Phrase $phrases.Autopilot -Language $language -ObservedProperty "AutopilotMaster" -Predicate { param($s) [bool]$s.AutopilotMaster }))
$results.Add((Invoke-ControlStep -Id "10-heading-on" -Description "Activate HDG mode" -Phrase $phrases.HeadingOn -Language $language -ObservedProperty "HeadingHold" -Predicate { param($s) [bool]$s.HeadingHold }))
$results.Add((Invoke-ControlStep -Id "11-heading-off" -Description "Deactivate HDG mode and verify the control remains usable" -Phrase $phrases.HeadingOff -Language $language -ObservedProperty "HeadingHold" -Predicate { param($s) -not [bool]$s.HeadingHold }))
$results.Add((Invoke-ControlStep -Id "12-altitude-hold" -Description "Activate ALT mode through the Vision Jet BVar route" -Phrase $phrases.AltitudeHold -Language $language -ObservedProperty "AltitudeHold" -Predicate { param($s) [bool]$s.AltitudeHold }))

Write-Host ""
Write-Host "Manual interaction-latch verification" -ForegroundColor Cyan
Write-Host "After the repeated voice commands, briefly operate the indicated controls with the mouse." -ForegroundColor Yellow
$gearManualText = Read-Host "Does the GEAR lever still respond normally to manual clicks? (Y/N)"
$modesManualText = Read-Host "Can the HDG and ALT buttons still be operated manually? (Y/N)"
$gearAnswer = $gearManualText.Trim()
$modesAnswer = $modesManualText.Trim()
$gearManual = $gearAnswer.StartsWith("Y", [StringComparison]::OrdinalIgnoreCase) -or $gearAnswer.StartsWith("S", [StringComparison]::OrdinalIgnoreCase)
$modesManual = $modesAnswer.StartsWith("Y", [StringComparison]::OrdinalIgnoreCase) -or $modesAnswer.StartsWith("S", [StringComparison]::OrdinalIgnoreCase)

# Windows PowerShell 5.1 can throw "Argument types do not match" when a
# generic List[object] is wrapped directly in an array subexpression during
# report serialization. Materialize a plain Object[] once and use it below.
$resultArray = @($results | ForEach-Object { $_ })
$automaticSuccess = (@($resultArray | Where-Object { -not [bool]$_.success }).Count -eq 0)
$success = $automaticSuccess -and $gearManual -and $modesManual
$report = [ordered]@{
    schemaVersion = 1
    qaVersion = "2.7.5"
    appVersion = [string]$ping.AppVersion
    generatedAt = (Get-Date).ToString("o")
    appId = [string]$appState.App.AppID
    voiceLanguage = $voiceLanguage
    aircraftTitle = $aircraftTitle
    automaticSuccess = $automaticSuccess
    manualGearInteractionPassed = $gearManual
    manualAutopilotModesInteractionPassed = $modesManual
    success = $success
    initialSnapshot = $initial
    steps = $resultArray
}
$reportPath = Join-Path $OutputDirectory "g2-control-regression-result.json"
$report | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ""
if ($success) {
    Write-Host "VISION JET G2 CONTROL REGRESSION: PASS" -ForegroundColor Green
    Write-Host ("Report: {0}" -f $reportPath) -ForegroundColor DarkGray
    exit 0
}

Write-Host "VISION JET G2 CONTROL REGRESSION: FAIL" -ForegroundColor Red
Write-Host ("Report: {0}" -f $reportPath) -ForegroundColor DarkGray
exit 1
