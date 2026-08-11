[CmdletBinding()]
param(
    [ValidateSet("English", "Spanish", "G2", "All", "Collect")]
    [string]$Phase = "English",

    [string]$AppIdPattern = "SimTechAviation.SimVoiceCopilot.Dev_*",
    [string]$AppNamePattern = "*SimVoice Copilot*",
    [string]$ProcessName = "SimVoiceCopilotApp",
    [string]$SimConnectDll = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp\Microsoft.FlightSimulator.SimConnect.dll",
    [string]$StandardAircraftPattern = "*C172*",

    [ValidateRange(1, 25)]
    [int]$UiCycles = 5,

    [switch]$SkipUi,
    [switch]$SkipSession,
    [switch]$SkipVoiceChecklists,
    [switch]$SkipG3000ChecklistSync,
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$finalRoot = Join-Path $projectRoot "QA-Runs\FinalRegression"
New-Item -ItemType Directory -Path $finalRoot -Force | Out-Null

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

function Invoke-ChildStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [ValidateRange(30, 7200)][int]$TimeoutSeconds = 900
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Required QA script was not found: $ScriptPath"
    }

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $stdout = Join-Path $OutputDirectory "console-out.log"
    $stderr = Join-Path $OutputDirectory "console-error.log"
    $powershellExe = Get-WindowsPowerShell

    $allArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments
    $argumentString = ($allArguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "

    Write-Host ""
    Write-Host ("=== {0} ===" -f $Name) -ForegroundColor Cyan
    Write-Host ("Script  : {0}" -f $ScriptPath) -ForegroundColor DarkGray
    Write-Host ("Results : {0}" -f $OutputDirectory) -ForegroundColor DarkGray

    $started = Get-Date
    $process = Start-Process -FilePath $powershellExe `
        -ArgumentList $argumentString `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        Write-Host ("STEP TIMEOUT: {0} exceeded {1} seconds." -f $Name, $TimeoutSeconds) -ForegroundColor Red
        try {
            & taskkill.exe /PID $process.Id /T /F | Out-Null
        }
        catch {
            try { $process.Kill() } catch { }
        }
        $exitCode = 124
    }
    else {
        $exitCode = [int]$process.ExitCode
    }
    $process.Dispose()
    $finished = Get-Date

    if (Test-Path -LiteralPath $stdout) {
        Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ([string]$_) }
    }
    if (Test-Path -LiteralPath $stderr) {
        Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ([string]$_) -ForegroundColor DarkYellow }
    }

    $result = [pscustomobject][ordered]@{
        name = $Name
        script = $ScriptPath
        outputDirectory = $OutputDirectory
        startedAt = $started.ToString("o")
        finishedAt = $finished.ToString("o")
        durationSeconds = [Math]::Round(($finished - $started).TotalSeconds, 3)
        exitCode = $exitCode
        success = ($exitCode -eq 0)
        timedOut = $timedOut
        timeoutSeconds = $TimeoutSeconds
        stdout = $stdout
        stderr = $stderr
    }

    if ($exitCode -ne 0) {
        Write-Host ("STEP FAILED: {0} (exit code {1})" -f $Name, $exitCode) -ForegroundColor Red
    }
    else {
        Write-Host ("STEP PASS: {0}" -f $Name) -ForegroundColor Green
    }

    return $result
}


function Confirm-StepReportSuccess {
    param(
        [Parameter(Mandatory = $true)][object]$Step,
        [Parameter(Mandatory = $true)][string]$ReportPath,
        [string]$SuccessProperty = "Success"
    )

    $reportedSuccess = $false
    $reportError = ""
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
        $reportError = "Expected result artifact was not generated: $ReportPath"
    }
    else {
        try {
            $report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $property = $report.PSObject.Properties[$SuccessProperty]
            if ($null -eq $property) {
                $reportError = "Result artifact does not contain '$SuccessProperty': $ReportPath"
            }
            else {
                $reportedSuccess = [bool]$property.Value
                if (-not $reportedSuccess) {
                    $reportError = "Result artifact reports failure: $ReportPath"
                }
            }
        }
        catch {
            $reportError = "Could not read result artifact '$ReportPath': $($_.Exception.Message)"
        }
    }

    $Step | Add-Member -NotePropertyName reportPath -NotePropertyValue $ReportPath -Force
    $Step | Add-Member -NotePropertyName reportSuccess -NotePropertyValue $reportedSuccess -Force
    if (-not $reportedSuccess) {
        $Step.success = $false
        $Step.exitCode = 1
        $Step | Add-Member -NotePropertyName reportError -NotePropertyValue $reportError -Force
        Write-Host ("STEP ARTIFACT FAILED: {0}" -f $reportError) -ForegroundColor Red
    }
    return $Step
}

function Restart-PrivateQaApp {
    Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline -and
           $null -ne (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        Start-Sleep -Milliseconds 250
    }

    Start-Sleep -Milliseconds 700
    return Start-PrivateQaApp
}

function Invoke-InteractiveChildStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$OutputDirectory
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Required QA script was not found: $ScriptPath"
    }

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $powershellExe = Get-WindowsPowerShell
    $allArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments
    $argumentString = ($allArguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "

    Write-Host ""
    Write-Host ("=== {0} ===" -f $Name) -ForegroundColor Cyan
    Write-Host ("Script  : {0}" -f $ScriptPath) -ForegroundColor DarkGray
    Write-Host ("Results : {0}" -f $OutputDirectory) -ForegroundColor DarkGray

    $started = Get-Date
    $process = Start-Process -FilePath $powershellExe `
        -ArgumentList $argumentString `
        -NoNewWindow `
        -Wait `
        -PassThru
    $exitCode = [int]$process.ExitCode
    $process.Dispose()
    $finished = Get-Date

    $result = [pscustomobject][ordered]@{
        name = $Name
        script = $ScriptPath
        outputDirectory = $OutputDirectory
        startedAt = $started.ToString("o")
        finishedAt = $finished.ToString("o")
        durationSeconds = [Math]::Round(($finished - $started).TotalSeconds, 3)
        exitCode = $exitCode
        success = ($exitCode -eq 0)
        stdout = $null
        stderr = $null
    }

    if ($exitCode -eq 0) {
        Write-Host ("STEP PASS: {0}" -f $Name) -ForegroundColor Green
    }
    else {
        Write-Host ("STEP FAILED: {0} (exit code {1})" -f $Name, $exitCode) -ForegroundColor Red
    }
    return $result
}

function Invoke-BridgeRequest {
    param(
        [string]$Action = "ping",
        [int]$TimeoutMs = 5000
    )

    $pipe = $null
    $reader = $null
    $writer = $null
    try {
        $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
            ".",
            "SimVoiceCopilot.QA.InternalAudio.v1",
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
            Text = ""
            Language = ""
            TimeoutMs = $TimeoutMs
            SpeechRate = 0
            PostCommandWaitMs = 300
        }
        $writer.WriteLine(($request | ConvertTo-Json -Compress))
        $task = $reader.ReadLineAsync()
        if (-not $task.Wait($TimeoutMs + 10000)) {
            throw "Timed out waiting for the Internal Audio QA bridge."
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
            if ($null -ne $ping -and [bool]$ping.Success) { return [pscustomobject]@{ App = $apps[0]; Ping = $ping } }
            $lastError = if ($null -ne $ping) { [string]$ping.Error } else { "No response" }
        }
        catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 500
    }

    throw "The private QA app did not expose the Internal Audio bridge. Last error: $lastError"
}

function Assert-ExpectedLanguage {
    param(
        [Parameter(Mandatory = $true)][object]$Ping,
        [Parameter(Mandatory = $true)][string]$ExpectedPrefix
    )

    $language = [string]$Ping.VoiceLanguage
    if ([string]::IsNullOrWhiteSpace($language) -or
        -not $language.StartsWith($ExpectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The active SimVoice recognition language is '$language'. This phase requires '$ExpectedPrefix'. Change Settings > Voice language, restart the private QA app, and run the phase again."
    }
    return $language
}

function Get-ProbeSnapshot {
    param([string]$ProbeDirectory)
    $reportPath = Join-Path $ProbeDirectory "oracle-report.json"
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        throw "Oracle probe report was not generated: $reportPath"
    }
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$report.Success -or @($report.Snapshots).Count -eq 0) {
        throw "Oracle probe did not return a valid active-flight snapshot. Review: $reportPath"
    }
    return @($report.Snapshots)[-1]
}

function Save-PhaseSummary {
    param(
        [string]$PhaseName,
        [string]$RunDirectory,
        [object[]]$Steps,
        [object]$Context
    )

    $stepArray = @($Steps | ForEach-Object { $_ })
    $success = (@($stepArray | Where-Object { -not [bool]$_.success }).Count -eq 0)
    $summary = [ordered]@{
        schemaVersion = 1
        qaVersion = "2.7.5"
        appVersion = "1.0.17.0"
        phase = $PhaseName
        generatedAt = (Get-Date).ToString("o")
        success = $success
        context = $Context
        steps = $stepArray
    }
    $summaryPath = Join-Path $RunDirectory "final-phase-summary.json"
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    return [pscustomobject]@{ Success = $success; Path = $summaryPath }
}

function Invoke-LanguagePhase {
    param(
        [ValidateSet("English", "Spanish")][string]$LanguagePhase
    )

    $suffix = if ($LanguagePhase -eq "English") { "EN" } else { "ES" }
    $expectedLanguage = if ($suffix -eq "EN") { "en" } else { "es" }
    $coreSuite = "CoreInternal$suffix"
    $statesSuite = "StatesInternal$suffix"
    $calloutsSuite = "CalloutsInternal$suffix"
    $negativeSuite = "NegativeInternal$suffix"
    $sessionSuite = "SessionInternal$suffix"
    $checklistSuite = "Core$suffix"

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $runDirectory = Join-Path $finalRoot ("FINAL-{0}-{1}" -f $stamp, $LanguagePhase)
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    $steps = New-Object 'System.Collections.Generic.List[object]'

    Write-Host ""
    Write-Host ("FINAL REGRESSION — {0}" -f $LanguagePhase.ToUpperInvariant()) -ForegroundColor Cyan
    Write-Host "Use a Cessna 172 G1000 in an active airborne flight, flaps up and autopilot off." -ForegroundColor Yellow
    Write-Host "Do not operate tested controls while the suite is running." -ForegroundColor Yellow
    Read-Host "Press ENTER when MSFS 2024 and the C172 G1000 flight are ready"

    $appState = Start-PrivateQaApp
    $ping = $appState.Ping
    $voiceLanguage = Assert-ExpectedLanguage -Ping $ping -ExpectedPrefix $expectedLanguage

    $packagePreflightDirectory = Join-Path $runDirectory "00-package-preflight"
    $packagePreflightStep = Invoke-ChildStep `
        -Name "MSIX payload, WASM deployment and UI source preflight" `
        -ScriptPath (Join-Path $PSScriptRoot "Test-QA-PreCertification-Payload.ps1") `
        -Arguments @("-AppIdPattern", $AppIdPattern, "-OutputDirectory", $packagePreflightDirectory) `
        -OutputDirectory (Join-Path $runDirectory "00-package-preflight-console") `
        -TimeoutSeconds 90
    $packagePreflightStep = Confirm-StepReportSuccess `
        -Step $packagePreflightStep `
        -ReportPath (Join-Path $packagePreflightDirectory "precertification-payload-result.json") `
        -SuccessProperty "success"
    $steps.Add($packagePreflightStep)
    if (-not $packagePreflightStep.success) {
        return (Finalize-LanguageFailure -LanguagePhase $LanguagePhase -RunDirectory $runDirectory -Steps $steps -VoiceLanguage $voiceLanguage -AircraftTitle "")
    }

    $probeDirectory = Join-Path $runDirectory "00-oracle-probe"
    $probeArgs = @(
        "-Mode", "Probe",
        "-OutputDirectory", $probeDirectory,
        "-SimConnectDll", $SimConnectDll,
        "-TimeoutSeconds", "30",
        "-IntervalMs", "500"
    )
    if ($NoBuild) { $probeArgs += "-NoBuild" }
    $probeStep = Invoke-ChildStep -Name "Independent SimConnect preflight" -ScriptPath (Join-Path $PSScriptRoot "Run-QA-SimConnect-Oracle.ps1") -Arguments $probeArgs -OutputDirectory (Join-Path $runDirectory "00-oracle-console")
    $probeStep = Confirm-StepReportSuccess -Step $probeStep -ReportPath (Join-Path $probeDirectory "oracle-report.json")
    $steps.Add($probeStep)
    if (-not $probeStep.success) {
        $summaryResult = Save-PhaseSummary -PhaseName $LanguagePhase -RunDirectory $runDirectory -Steps $steps -Context @{ voiceLanguage = $voiceLanguage }
        throw "SimConnect preflight failed. Results: $runDirectory"
    }

    $snapshot = Get-ProbeSnapshot -ProbeDirectory $probeDirectory
    $aircraftTitle = [string]$snapshot.AircraftTitle
    if ($aircraftTitle -notlike $StandardAircraftPattern) {
        $summaryResult = Save-PhaseSummary -PhaseName $LanguagePhase -RunDirectory $runDirectory -Steps $steps -Context @{ voiceLanguage = $voiceLanguage; aircraftTitle = $aircraftTitle }
        throw "The active aircraft is '$aircraftTitle'. This deterministic phase requires an aircraft matching '$StandardAircraftPattern' (recommended: C172 G1000)."
    }

    $commonFlightArgs = @(
        "-AppNamePattern", $AppNamePattern,
        "-AppIdPattern", $AppIdPattern,
        "-ProcessName", $ProcessName,
        "-SimConnectDll", $SimConnectDll,
        "-SkipAppLaunch"
    )

    if (-not $SkipUi) {
        $uiArgs = @(
            "-AppIdPattern", $AppIdPattern,
            "-ProcessName", $ProcessName,
            "-Scenario", "All",
            "-Cycles", $UiCycles.ToString(),
            "-OutputDirectory", (Join-Path $runDirectory "01-ui-navigation-tray"),
            "-NoClose"
        )
        $step = Invoke-ChildStep -Name "UI, navigation, tray restore and resource regression" -ScriptPath (Join-Path $PSScriptRoot "Run-QA-MSIX.ps1") -Arguments $uiArgs -OutputDirectory (Join-Path $runDirectory "01-ui-console")
        $step = Confirm-StepReportSuccess -Step $step -ReportPath (Join-Path $runDirectory "01-ui-navigation-tray\results.json")
        $steps.Add($step)
        if (-not $step.success) { return (Finalize-LanguageFailure -LanguagePhase $LanguagePhase -RunDirectory $runDirectory -Steps $steps -VoiceLanguage $voiceLanguage -AircraftTitle $aircraftTitle) }
    }

    # UI/tray stress exercises window lifecycle and can leave the native recognizer in
    # a long-lived state. Start the internal-audio phase with a new QA process so every
    # command regression begins from a clean native decoder state.
    $restartStarted = Get-Date
    try {
        $appState = Restart-PrivateQaApp
        $ping = $appState.Ping
        $voiceLanguage = Assert-ExpectedLanguage -Ping $ping -ExpectedPrefix $expectedLanguage
        $restartFinished = Get-Date
        $restartStep = [pscustomobject][ordered]@{
            name = "Fresh private QA app before internal audio"
            script = "Restart-PrivateQaApp"
            outputDirectory = $runDirectory
            startedAt = $restartStarted.ToString("o")
            finishedAt = $restartFinished.ToString("o")
            durationSeconds = [Math]::Round(($restartFinished - $restartStarted).TotalSeconds, 3)
            exitCode = 0
            success = $true
            stdout = $null
            stderr = $null
        }
        Write-Host "STEP PASS: Fresh private QA app before internal audio" -ForegroundColor Green
    }
    catch {
        $restartFinished = Get-Date
        $restartStep = [pscustomobject][ordered]@{
            name = "Fresh private QA app before internal audio"
            script = "Restart-PrivateQaApp"
            outputDirectory = $runDirectory
            startedAt = $restartStarted.ToString("o")
            finishedAt = $restartFinished.ToString("o")
            durationSeconds = [Math]::Round(($restartFinished - $restartStarted).TotalSeconds, 3)
            exitCode = 1
            success = $false
            stdout = $null
            stderr = $_.Exception.Message
        }
        Write-Host ("STEP FAILED: Could not restart the private QA app: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    $steps.Add($restartStep)
    if (-not $restartStep.success) { return (Finalize-LanguageFailure -LanguagePhase $LanguagePhase -RunDirectory $runDirectory -Steps $steps -VoiceLanguage $voiceLanguage -AircraftTitle $aircraftTitle) }

    $coreArgs = @("-Suite", $coreSuite, "-OutputDirectory", (Join-Path $runDirectory "02-core-commands")) + $commonFlightArgs + @("-NoBuild")
    $step = Invoke-ChildStep -Name "Parameterized commands $coreSuite" -ScriptPath (Join-Path $PSScriptRoot "Run-QA-Flight-InternalAudio.ps1") -Arguments $coreArgs -OutputDirectory (Join-Path $runDirectory "02-core-console") -TimeoutSeconds 420
    $step = Confirm-StepReportSuccess -Step $step -ReportPath (Join-Path $runDirectory "02-core-commands\functional-results.json")
    $steps.Add($step)
    if (-not $step.success) { return (Finalize-LanguageFailure -LanguagePhase $LanguagePhase -RunDirectory $runDirectory -Steps $steps -VoiceLanguage $voiceLanguage -AircraftTitle $aircraftTitle) }

    $extendedSuites = @(
        @{ Name = "State-changing commands $statesSuite"; Suite = $statesSuite; Folder = "03-states" },
        @{ Name = "SimVar call-outs $calloutsSuite"; Suite = $calloutsSuite; Folder = "04-callouts" },
        @{ Name = "Negative and incomplete commands $negativeSuite"; Suite = $negativeSuite; Folder = "05-negative" }
    )

    foreach ($item in $extendedSuites) {
        $suiteArgs = @(
            "-Suite", [string]$item.Suite,
            "-AppNamePattern", $AppNamePattern,
            "-AppIdPattern", $AppIdPattern,
            "-ProcessName", $ProcessName,
            "-SimConnectDll", $SimConnectDll,
            "-OutputDirectory", (Join-Path $runDirectory ([string]$item.Folder)),
            "-SkipAppLaunch",
            "-NoBuild"
        )
        $step = Invoke-ChildStep -Name ([string]$item.Name) -ScriptPath (Join-Path $PSScriptRoot "Run-QA-Flight-Extended.ps1") -Arguments $suiteArgs -OutputDirectory (Join-Path $runDirectory (([string]$item.Folder) + "-console"))
        $step = Confirm-StepReportSuccess -Step $step -ReportPath (Join-Path $runDirectory (([string]$item.Folder) + "\functional-results.json"))
        $steps.Add($step)
        if (-not $step.success) { return (Finalize-LanguageFailure -LanguagePhase $LanguagePhase -RunDirectory $runDirectory -Steps $steps -VoiceLanguage $voiceLanguage -AircraftTitle $aircraftTitle) }
    }

    if (-not $SkipSession) {
        $sessionArgs = @(
            "-Suite", $sessionSuite,
            "-AppNamePattern", $AppNamePattern,
            "-AppIdPattern", $AppIdPattern,
            "-ProcessName", $ProcessName,
            "-SimConnectDll", $SimConnectDll,
            "-OutputDirectory", (Join-Path $runDirectory "06-session-50"),
            "-SkipAppLaunch",
            "-NoBuild"
        )
        $step = Invoke-ChildStep -Name "50-command continuous session $sessionSuite" -ScriptPath (Join-Path $PSScriptRoot "Run-QA-Flight-Extended.ps1") -Arguments $sessionArgs -OutputDirectory (Join-Path $runDirectory "06-session-console")
        $step = Confirm-StepReportSuccess -Step $step -ReportPath (Join-Path $runDirectory "06-session-50\functional-results.json")
        $steps.Add($step)
        if (-not $step.success) { return (Finalize-LanguageFailure -LanguagePhase $LanguagePhase -RunDirectory $runDirectory -Steps $steps -VoiceLanguage $voiceLanguage -AircraftTitle $aircraftTitle) }
    }

    if (-not $SkipVoiceChecklists) {
        # The 50-command session intentionally keeps one native recognizer alive for
        # several minutes. Start Voice Checklists with a fresh private process so the
        # checklist diagnostics providers, dynamic response grammar and TTS queue all
        # begin from a deterministic state.
        $checklistRestartStarted = Get-Date
        try {
            $checklistAppState = Restart-PrivateQaApp
            $checklistPing = $checklistAppState.Ping
            $voiceLanguage = Assert-ExpectedLanguage -Ping $checklistPing -ExpectedPrefix $expectedLanguage
            $checklistRestartFinished = Get-Date
            $checklistRestartStep = [pscustomobject][ordered]@{
                name = "Fresh private QA app before Voice Checklists"
                script = "Restart-PrivateQaApp"
                outputDirectory = $runDirectory
                startedAt = $checklistRestartStarted.ToString("o")
                finishedAt = $checklistRestartFinished.ToString("o")
                durationSeconds = [Math]::Round(($checklistRestartFinished - $checklistRestartStarted).TotalSeconds, 3)
                exitCode = 0
                success = $true
                stdout = $null
                stderr = $null
            }
            Write-Host "STEP PASS: Fresh private QA app before Voice Checklists" -ForegroundColor Green
        }
        catch {
            $checklistRestartFinished = Get-Date
            $checklistRestartStep = [pscustomobject][ordered]@{
                name = "Fresh private QA app before Voice Checklists"
                script = "Restart-PrivateQaApp"
                outputDirectory = $runDirectory
                startedAt = $checklistRestartStarted.ToString("o")
                finishedAt = $checklistRestartFinished.ToString("o")
                durationSeconds = [Math]::Round(($checklistRestartFinished - $checklistRestartStarted).TotalSeconds, 3)
                exitCode = 1
                success = $false
                stdout = $null
                stderr = $_.Exception.Message
            }
            Write-Host ("STEP FAILED: Could not restart before Voice Checklists: {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
        $steps.Add($checklistRestartStep)
        if (-not $checklistRestartStep.success) { return (Finalize-LanguageFailure -LanguagePhase $LanguagePhase -RunDirectory $runDirectory -Steps $steps -VoiceLanguage $voiceLanguage -AircraftTitle $aircraftTitle) }

        $checklistArgs = @(
            "-Suite", $checklistSuite,
            "-AppIdPattern", $AppIdPattern,
            "-ProcessName", $ProcessName,
            "-OutputDirectory", (Join-Path $runDirectory "07-voice-checklists"),
            "-NoClose"
        )
        $step = Invoke-ChildStep -Name "Voice Checklists $checklistSuite" -ScriptPath (Join-Path $PSScriptRoot "Run-QA-Voice-Checklists.ps1") -Arguments $checklistArgs -OutputDirectory (Join-Path $runDirectory "07-checklist-console")
        $step = Confirm-StepReportSuccess -Step $step -ReportPath (Join-Path $runDirectory "07-voice-checklists\results.json")
        $steps.Add($step)
        if (-not $step.success) { return (Finalize-LanguageFailure -LanguagePhase $LanguagePhase -RunDirectory $runDirectory -Steps $steps -VoiceLanguage $voiceLanguage -AircraftTitle $aircraftTitle) }
    }

    $context = [ordered]@{
        voiceLanguage = $voiceLanguage
        aircraftTitle = $aircraftTitle
        simulatorApplication = [string]$snapshot.SimulatorApplication
        flightActive = [bool]$snapshot.FlightActive
        standardAircraftPattern = $StandardAircraftPattern
    }
    $summaryResult = Save-PhaseSummary -PhaseName $LanguagePhase -RunDirectory $runDirectory -Steps $steps -Context $context

    Write-Host ""
    if ($summaryResult.Success) {
        Write-Host ("FINAL {0}: PASS" -f $LanguagePhase.ToUpperInvariant()) -ForegroundColor Green
        Write-Host ("Summary: {0}" -f $summaryResult.Path) -ForegroundColor DarkGray
        return 0
    }

    Write-Host ("FINAL {0}: FAIL" -f $LanguagePhase.ToUpperInvariant()) -ForegroundColor Red
    return 1
}

function Finalize-LanguageFailure {
    param(
        [string]$LanguagePhase,
        [string]$RunDirectory,
        [object[]]$Steps,
        [string]$VoiceLanguage,
        [string]$AircraftTitle
    )
    $context = [ordered]@{ voiceLanguage = $VoiceLanguage; aircraftTitle = $AircraftTitle }
    $summaryResult = Save-PhaseSummary -PhaseName $LanguagePhase -RunDirectory $RunDirectory -Steps $Steps -Context $context
    Write-Host ("FINAL {0}: FAIL" -f $LanguagePhase.ToUpperInvariant()) -ForegroundColor Red
    Write-Host ("Summary: {0}" -f $summaryResult.Path) -ForegroundColor DarkGray
    return 1
}

function Invoke-G2Phase {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $runDirectory = Join-Path $finalRoot ("FINAL-{0}-G2" -f $stamp)
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    $steps = New-Object 'System.Collections.Generic.List[object]'

    $controlArgs = @(
        "-AppIdPattern", $AppIdPattern,
        "-ProcessName", $ProcessName,
        "-SimConnectDll", $SimConnectDll,
        "-OutputDirectory", (Join-Path $runDirectory "01-g2-controls")
    )
    $step = Invoke-InteractiveChildStep -Name "Vision Jet G2 repeated controls and interaction-lock regression" -ScriptPath (Join-Path $PSScriptRoot "Run-QA-G2-Control-Regression-Guided.ps1") -Arguments $controlArgs -OutputDirectory (Join-Path $runDirectory "01-g2-controls-console")
    $step = Confirm-StepReportSuccess -Step $step -ReportPath (Join-Path $runDirectory "01-g2-controls\g2-control-regression-result.json") -SuccessProperty "success"
    $steps.Add($step)
    if (-not $step.success) {
        $summaryResult = Save-PhaseSummary -PhaseName "G2" -RunDirectory $runDirectory -Steps $steps -Context @{}
        Write-Host "FINAL G2: FAIL" -ForegroundColor Red
        return 1
    }

    if (-not $SkipG3000ChecklistSync) {
        $syncArgs = @(
            "-AppIdPattern", $AppIdPattern,
            "-OutputDirectory", (Join-Path $runDirectory "02-g3000-checklist-sync")
        )
        $step = Invoke-InteractiveChildStep -Name "Vision Jet G2 G3000 checklist synchronization" -ScriptPath (Join-Path $PSScriptRoot "Run-QA-Voice-Checklists-G3000-Guided.ps1") -Arguments $syncArgs -OutputDirectory (Join-Path $runDirectory "02-g3000-sync-console")
        $step = Confirm-StepReportSuccess -Step $step -ReportPath (Join-Path $runDirectory "02-g3000-checklist-sync\g3000-guided-result.json") -SuccessProperty "success"
        $steps.Add($step)
    }

    $summaryResult = Save-PhaseSummary -PhaseName "G2" -RunDirectory $runDirectory -Steps $steps -Context @{}
    Write-Host ""
    if ($summaryResult.Success) {
        Write-Host "FINAL G2: PASS" -ForegroundColor Green
        Write-Host ("Summary: {0}" -f $summaryResult.Path) -ForegroundColor DarkGray
        return 0
    }
    Write-Host "FINAL G2: FAIL" -ForegroundColor Red
    return 1
}

function Invoke-Collector {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $collectorOutput = Join-Path $finalRoot ("COLLECT-{0}" -f $stamp)
    $step = Invoke-ChildStep `
        -Name "Collect final certification regression package" `
        -ScriptPath (Join-Path $PSScriptRoot "Collect-QA-Final-Regression.ps1") `
        -Arguments @("-FinalRegressionRoot", $finalRoot) `
        -OutputDirectory $collectorOutput
    return [int]$step.exitCode
}

$exitCode = 0
switch ($Phase) {
    "English" { $exitCode = Invoke-LanguagePhase -LanguagePhase "English" }
    "Spanish" { $exitCode = Invoke-LanguagePhase -LanguagePhase "Spanish" }
    "G2" { $exitCode = Invoke-G2Phase }
    "Collect" { $exitCode = Invoke-Collector }
    "All" {
        $exitCode = Invoke-LanguagePhase -LanguagePhase "English"
        if ($exitCode -ne 0) { break }
        Write-Host ""
        Write-Host "Change SimVoice Copilot to Spanish in Settings, restart the private QA app, and keep the C172 G1000 flight active." -ForegroundColor Yellow
        Read-Host "Press ENTER after the app title is visible again"
        $exitCode = Invoke-LanguagePhase -LanguagePhase "Spanish"
        if ($exitCode -ne 0) { break }
        Write-Host ""
        Write-Host "Load the Cirrus Vision Jet G2 in an airborne flight before the G2 phase." -ForegroundColor Yellow
        Read-Host "Press ENTER when the Vision Jet G2 is stable, gear/flaps UP and autopilot OFF"
        $exitCode = Invoke-G2Phase
        if ($exitCode -ne 0) { break }
        $exitCode = Invoke-Collector
    }
}

exit $exitCode
