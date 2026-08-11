param(
    [string]$ProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp",
    [string]$QaRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA",
    [int]$UiCycles = 25,
    [int]$LifecycleCycles = 30,
    [switch]$SkipWack
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ExpectedVersion = "1.0.18.0"
$HarnessVersion = "3.0.1"
$RunStartLocal = Get-Date
$RunStartUtc = $RunStartLocal.ToUniversalTime()

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

$CertificationRoot = Join-Path $QaRoot "QA-Runs\Certification"
Ensure-Directory $CertificationRoot

$RunId = "CERT-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")
$RunDir = Join-Path $CertificationRoot $RunId
Ensure-Directory $RunDir
$LogPath = Join-Path $RunDir "certification-run.log"
$Stages = New-Object System.Collections.ArrayList
$script:HasFailure = $false
$script:HasWarning = $false
$script:ProductionMsix = $null

function Write-Log([string]$Message, [string]$Level = "INFO") {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "PASS"  { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
}

function Add-StageResult(
    [string]$Name,
    [string]$Status,
    [string]$Detail,
    [datetime]$Started,
    [datetime]$Finished
) {
    $null = $Stages.Add([pscustomobject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
        StartedLocal = $Started.ToString("o")
        FinishedLocal = $Finished.ToString("o")
        DurationSeconds = [Math]::Round(($Finished - $Started).TotalSeconds, 2)
    })
    if ($Status -eq "FAIL") { $script:HasFailure = $true }
    if ($Status -eq "WARN") { $script:HasWarning = $true }
}

function Invoke-Stage([string]$Name, [scriptblock]$Action) {
    $started = Get-Date
    Write-Log ""
    Write-Log ("=" * 72)
    Write-Log ("START: " + $Name)
    try {
        $detail = & $Action
        if ($null -eq $detail) { $detail = "PASS" }
        $finished = Get-Date
        Add-StageResult $Name "PASS" ([string]$detail) $started $finished
        Write-Log ("PASS: " + $Name + " - " + [string]$detail) "PASS"
    } catch {
        $finished = Get-Date
        $detail = $_.Exception.Message
        Add-StageResult $Name "FAIL" $detail $started $finished
        Write-Log ("FAIL: " + $Name + " - " + $detail) "ERROR"
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace "ERROR"
        }
    }
}

function Invoke-WarningStage([string]$Name, [scriptblock]$Action) {
    $started = Get-Date
    Write-Log ""
    Write-Log ("=" * 72)
    Write-Log ("START: " + $Name)
    try {
        $detail = & $Action
        if ($null -eq $detail) { $detail = "PASS" }
        $finished = Get-Date
        Add-StageResult $Name "PASS" ([string]$detail) $started $finished
        Write-Log ("PASS: " + $Name + " - " + [string]$detail) "PASS"
    } catch {
        $finished = Get-Date
        $detail = $_.Exception.Message
        Add-StageResult $Name "WARN" $detail $started $finished
        Write-Log ("WARN: " + $Name + " - " + $detail) "WARN"
    }
}

function Find-MSBuild {
    $cmd = Get-Command "msbuild.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    throw "MSBuild.exe was not found. Visual Studio 2022 / Build Tools is required."
}

function Run-ExternalCapture([string]$FilePath, [string[]]$Arguments, [string]$StageLog) {
    Write-Log ("EXEC: " + $FilePath + " " + ($Arguments -join " "))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ($Arguments | ForEach-Object {
        if ($_ -match '\s' -and $_ -notmatch '^".*"$') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
    }) -join " "
    $psi.WorkingDirectory = $ProjectRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($stdout) {
        Add-Content -LiteralPath $StageLog -Value $stdout -Encoding UTF8
        Write-Host $stdout
    }
    if ($stderr) {
        Add-Content -LiteralPath $StageLog -Value $stderr -Encoding UTF8
        Write-Host $stderr -ForegroundColor Yellow
    }

    return [int]$p.ExitCode
}

function Run-External([string]$FilePath, [string[]]$Arguments, [string]$StageLog) {
    $exitCode = Run-ExternalCapture $FilePath $Arguments $StageLog
    if ($exitCode -ne 0) {
        throw ("Command failed with exit code {0}: {1}" -f $exitCode, $FilePath)
    }
}

function Get-DiagnosticLogPath {
    return Join-Path $env:LOCALAPPDATA ("SimVoiceCopilot\Logs\feedback-{0}.jsonl" -f (Get-Date -Format "yyyyMMdd"))
}

function Get-NewDiagnosticLines([string]$Path, [int]$BeforeCount) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(Get-Content -LiteralPath $Path -Encoding UTF8 | Select-Object -Skip $BeforeCount)
}

function Stop-SimVoiceProcesses {
    Get-Process -Name "SimVoiceCopilotApp" -ErrorAction SilentlyContinue | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {}
    }
    Start-Sleep -Milliseconds 500
}

function Get-SimVoiceCrashEvents([datetime]$AfterLocal) {
    try {
        $null = Get-WinEvent -ListLog "Application" -ErrorAction Stop

        $events = @(
            Get-WinEvent -FilterHashtable @{ LogName="Application"; StartTime=$AfterLocal } `
                -ErrorAction SilentlyContinue
        )

        if ($events.Count -eq 0) {
            return @()
        }

        return @(
            $events | Where-Object {
                ($_.ProviderName -in @("Application Error", ".NET Runtime", "Windows Error Reporting")) -and
                ($_.Message -match "(?i)SimVoiceCopilotApp\.exe|SimTechAviation\.SimVoiceCopilot|libvosk\.dll") -and
                ($_.Message -match "(?i)c0000005|0xc0000005|AccessViolationException|faulting|errores|crash|termin[oó] debido")
            }
        )
    } catch {
        throw ("Could not access Windows Application event log: " + $_.Exception.Message)
    }
}

function Find-StartAppId {
    $apps = @(Get-StartApps | Where-Object {
        $_.Name -like "*SimVoice Copilot*" -or $_.AppID -like "*SimVoiceCopilot*"
    })
    if ($apps.Count -eq 0) {
        throw "Installed SimVoice Copilot Start-app identity was not found."
    }
    $preferred = $apps | Where-Object { $_.AppID -like "*SimTechAviation.SimVoiceCopilot*" } | Select-Object -First 1
    if ($preferred) { return $preferred.AppID }
    return ($apps | Select-Object -First 1).AppID
}

function Launch-PackagedApp([string]$AppId) {
    Start-Process -FilePath "explorer.exe" -ArgumentList ("shell:AppsFolder\" + $AppId) | Out-Null
}

function Wait-ForSimVoiceProcess([int]$Seconds = 15) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $p = Get-Process -Name "SimVoiceCopilotApp" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p) { return $p }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Find-LatestMsix {
    $outDir = Join-Path $ProjectRoot "Store\Output"
    if (-not (Test-Path -LiteralPath $outDir)) { return $null }
    return Get-ChildItem -LiteralPath $outDir -Filter "*.msix" -File |
        Where-Object { $_.Name -match [regex]::Escape($ExpectedVersion) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Test-FileContainsAscii([string]$Path, [string]$Needle) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    return $text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Write-Reports {
    $finishedLocal = Get-Date
    $finishedUtc = $finishedLocal.ToUniversalTime()

    $requiredFailures = @($Stages | Where-Object { $_.Status -eq "FAIL" })
    if ($requiredFailures.Count -gt 0) {
        $verdict = "NO-GO"
        $summary = "At least one required certification QA stage failed. Do NOT upload this build to Partner Center."
    } else {
        $verdict = "AUTOMATED PASS"
        $summary = "Automated certification QA passed. The production MSIX is installed and ready for the two short final smoke tests."
    }

    $result = [pscustomobject]@{
        Product = "SimVoice Copilot"
        AppVersion = $ExpectedVersion
        HarnessVersion = $HarnessVersion
        RunId = $RunId
        StartedLocal = $RunStartLocal.ToString("o")
        StartedUtc = $RunStartUtc.ToString("o")
        FinishedLocal = $finishedLocal.ToString("o")
        FinishedUtc = $finishedUtc.ToString("o")
        ProjectRoot = $ProjectRoot
        QaRoot = $QaRoot
        UiCycles = $UiCycles
        LifecycleCycles = $LifecycleCycles
        WackSkipped = [bool]$SkipWack
        Verdict = $verdict
        Summary = $summary
        ProductionMsix = if ($script:ProductionMsix) { $script:ProductionMsix.FullName } else { "" }
        Stages = @($Stages)
    }

    $jsonPath = Join-Path $RunDir "CERTIFICATION-RESULT.json"
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $rows = foreach ($s in $Stages) {
        $color = if ($s.Status -eq "PASS") { "#159947" } elseif ($s.Status -eq "WARN") { "#c68a00" } else { "#c62828" }
        "<tr><td>$([System.Net.WebUtility]::HtmlEncode($s.Name))</td><td style='font-weight:bold;color:$color'>$($s.Status)</td><td>$([System.Net.WebUtility]::HtmlEncode($s.Detail))</td><td>$($s.DurationSeconds)s</td></tr>"
    }

    $verdictColor = if ($verdict -eq "AUTOMATED PASS") { "#159947" } else { "#c62828" }
    $html = @"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>SimVoice Copilot $ExpectedVersion - Store Certification QA</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:36px;color:#1f2937}
h1{margin-bottom:4px}
.small{color:#6b7280}
.verdict{font-size:26px;font-weight:700;color:$verdictColor;margin:22px 0}
table{border-collapse:collapse;width:100%;margin-top:20px}
th,td{border:1px solid #d1d5db;padding:9px;text-align:left;vertical-align:top}
th{background:#f3f4f6}
code{background:#f3f4f6;padding:2px 5px}
</style>
</head>
<body>
<h1>SimVoice Copilot $ExpectedVersion</h1>
<div class="small">Store Certification QA harness $HarnessVersion · $RunId</div>
<div class="verdict">$verdict</div>
<p>$([System.Net.WebUtility]::HtmlEncode($summary))</p>
<table>
<tr><th>Stage</th><th>Status</th><th>Detail</th><th>Time</th></tr>
$($rows -join "`r`n")
</table>
<p><b>Production MSIX:</b> $([System.Net.WebUtility]::HtmlEncode([string]$result.ProductionMsix))</p>
<p><b>Run directory:</b> <code>$([System.Net.WebUtility]::HtmlEncode($RunDir))</code></p>
</body>
</html>
"@
    $htmlPath = Join-Path $RunDir "CERTIFICATION-REPORT.html"
    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

    if ($verdict -eq "AUTOMATED PASS") {
        $marker = Join-Path (Split-Path -Parent $PSCommandPath) "LAST-AUTOMATED-PASS-UTC.txt"
        Set-Content -LiteralPath $marker -Value $finishedUtc.ToString("o") -Encoding ASCII
    }

    Write-Host ""
    Write-Host ("=" * 72)
    if ($verdict -eq "AUTOMATED PASS") {
        Write-Host "AUTOMATED PASS" -ForegroundColor Green
        Write-Host "Do the two short final smoke tests. Do not rebuild between QA and Store upload." -ForegroundColor Green
    } else {
        Write-Host "NO-GO" -ForegroundColor Red
        Write-Host "Do NOT upload this build to Partner Center." -ForegroundColor Red
    }
    Write-Host ("Report: " + $htmlPath)
    Write-Host ("JSON  : " + $jsonPath)
    Write-Host ("Log   : " + $LogPath)
    Write-Host ("=" * 72)

    return $verdict
}

Write-Log "SimVoice Copilot Store Certification QA $HarnessVersion"
Write-Log ("Target app version: " + $ExpectedVersion)
Write-Log ("ProjectRoot: " + $ProjectRoot)
Write-Log ("QaRoot: " + $QaRoot)
Write-Log ("RunDir: " + $RunDir)
Write-Log ("Run started UTC: " + $RunStartUtc.ToString("o"))

Invoke-Stage "1. Source truth and clean-tree guard" {
    if (-not (Test-Path -LiteralPath $ProjectRoot)) { throw "ProjectRoot does not exist: $ProjectRoot" }
    if (-not (Test-Path -LiteralPath $QaRoot)) { throw "QaRoot does not exist: $QaRoot" }

    $csproj = Join-Path $ProjectRoot "SimVoiceCopilotApp.csproj"
    $privateQaBuild = Join-Path $ProjectRoot "Store\Build-QA-InternalAudio-MSIX.ps1"
    $storeBuild = Join-Path $ProjectRoot "Store\Build-StoreMSIX.ps1"
    $qaRun = Join-Path $QaRoot "Scripts\Run-QA-MSIX.ps1"

    foreach ($required in @($csproj, $privateQaBuild, $storeBuild, $qaRun)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Required file not found: $required" }
    }

    Push-Location $ProjectRoot
    try {
        $branch = (& git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if ($LASTEXITCODE -ne 0) { throw "git rev-parse failed." }
        if ($branch -ne "1.0.18.0") {
            throw "Wrong Git branch: '$branch'. Expected exactly '1.0.18.0'."
        }
        $dirty = @(& git status --porcelain)
        if ($LASTEXITCODE -ne 0) { throw "git status failed." }
        if ($dirty.Count -gt 0) {
            $dirtyText = ($dirty -join "; ")
            throw "Git working tree is not clean. Commit/stash first. Changes: $dirtyText"
        }
        $head = (& git rev-parse HEAD).Trim()
    } finally {
        Pop-Location
    }

    # Semantic guards against accidentally certifying an old/pre-HF32H source tree.
    $markers = @(
        "CHECKLIST_PRIORITY_OPEN_REPLAY_IGNORED",
        "AssertSpanishOnOffRecognitionAliases",
        "AssertEfbSpanishOnOffDisplayAliases",
        "AssertChecklistCrossDecoderReplayGuard",
        "AssertChecklistPluralMarkerSpeechSanitization",
        "AssertChecklistSelectionRestoredAfterCancel",
        "CHECKLIST_TRANSLATION_PREFETCH_STARTED",
        "simvoicecopilot://launch?source=msfs2024-efb"
    )
    $sourceFiles = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Include *.cs,*.ps1,*.js,*.html,*.htm,*.xml,*.json |
        Where-Object { $_.FullName -notmatch "\\(bin|obj|\.git|Store\\Output|QA-Runs)\\" }

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($marker in $markers) {
        $found = $false
        foreach ($f in $sourceFiles) {
            if (Select-String -LiteralPath $f.FullName -SimpleMatch -Pattern $marker -Quiet -ErrorAction SilentlyContinue) {
                $found = $true
                break
            }
        }
        if (-not $found) { $missing.Add($marker) }
    }
    if ($missing.Count -gt 0) {
        throw ("Required 1.0.18.0 RC semantic markers are missing: " + ($missing -join ", "))
    }

    "Git branch 1.0.18.0 clean; HEAD=$head; RC semantic guards present."
}

Invoke-WarningStage "2. Environment cleanliness" {
    $sim = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match "(?i)FlightSimulator|MicrosoftFlightSimulator"
    })
    if ($sim.Count -gt 0) {
        throw "MSFS appears to be running. The QA can continue, but for the cleanest automated result close MSFS before rerunning."
    }
    "MSFS is not running; clean automated environment."
}

Invoke-Stage "3. Build Debug + deterministic regression suite" {
    Stop-SimVoiceProcesses
    $msbuild = Find-MSBuild
    $stageLog = Join-Path $RunDir "03-debug-build.log"
    Run-External $msbuild @(
        (Join-Path $ProjectRoot "SimVoiceCopilotApp.csproj"),
        "/t:Rebuild",
        "/p:Configuration=Debug",
        "/m"
    ) $stageLog

    $exe = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "bin\Debug") -Recurse -Filter "SimVoiceCopilotApp.exe" -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $exe) { throw "Debug SimVoiceCopilotApp.exe was not produced." }

    $diagLog = Get-DiagnosticLogPath
    $beforeCount = if (Test-Path -LiteralPath $diagLog) { @(Get-Content -LiteralPath $diagLog -Encoding UTF8).Count } else { 0 }

    $p = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru
    Start-Sleep -Seconds 10
    if (-not $p.HasExited) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
    }

    Start-Sleep -Milliseconds 500
    $newLines = Get-NewDiagnosticLines $diagLog $beforeCount
    Set-Content -LiteralPath (Join-Path $RunDir "03-debug-new-diagnostics.jsonl") -Value $newLines -Encoding UTF8

    $joined = $newLines -join "`n"
    if ($joined -match '"category"\s*:\s*"REGRESSION_TEST_FAILED"') {
        throw "The application logged REGRESSION_TEST_FAILED."
    }
    if ($joined -notmatch "PARAMETERIZED_REGRESSION_TESTS_PASS") {
        throw "PARAMETERIZED_REGRESSION_TESTS_PASS was not observed."
    }
    if ($joined -notmatch "CHECKLIST_REGRESSION_TESTS_PASS") {
        throw "CHECKLIST_REGRESSION_TESTS_PASS was not observed."
    }

    "Debug build PASS; parameterized and checklist deterministic regression suites PASS."
}

Invoke-Stage "4. Build/install private Internal Audio QA MSIX" {
    Stop-SimVoiceProcesses
    $scriptPath = Join-Path $ProjectRoot "Store\Build-QA-InternalAudio-MSIX.ps1"
    $stageLog = Join-Path $RunDir "04-private-internal-audio-build.log"

    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1 |
            Tee-Object -FilePath $stageLog |
            ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "Build-QA-InternalAudio-MSIX.ps1 returned exit code $LASTEXITCODE."
        }
    } catch {
        throw
    }

    $text = if (Test-Path -LiteralPath $stageLog) { Get-Content -LiteralPath $stageLog -Raw } else { "" }
    if ($text -notmatch "(?i)Internal Audio QA") {
        throw "Private build log does not prove that Internal Audio QA was enabled."
    }
    "Private Internal Audio QA MSIX built and installed."
}

Invoke-Stage "5. Installed-MSIX UI regression/stability loop" {
    Stop-SimVoiceProcesses
    $qaRun = Join-Path $QaRoot "Scripts\Run-QA-MSIX.ps1"
    $stageLog = Join-Path $RunDir "05-ui-qa.log"

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $qaRun `
        -AppNamePattern "*SimVoice*" `
        -Cycles $UiCycles 2>&1 |
        Tee-Object -FilePath $stageLog |
        ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -ne 0) {
        throw "Run-QA-MSIX.ps1 returned exit code $LASTEXITCODE."
    }

    $text = Get-Content -LiteralPath $stageLog -Raw
    if ($text -notmatch "(?i)QA RESULT:\s*PASS") {
        throw "The existing QA runner did not report 'QA RESULT: PASS'."
    }

    "Installed MSIX UI/stability QA PASS ($UiCycles cycles)."
}

Invoke-Stage "6. Vosk/native recognizer lifecycle stress" {
    Stop-SimVoiceProcesses
    $stageStart = Get-Date
    $diagLog = Get-DiagnosticLogPath
    $beforeCount = if (Test-Path -LiteralPath $diagLog) { @(Get-Content -LiteralPath $diagLog -Encoding UTF8).Count } else { 0 }

    $appId = Find-StartAppId
    $forcedStops = 0
    $launchFailures = 0

    for ($i = 1; $i -le $LifecycleCycles; $i++) {
        Write-Log ("Lifecycle cycle {0}/{1}" -f $i, $LifecycleCycles)
        Stop-SimVoiceProcesses
        Launch-PackagedApp $appId
        $p = Wait-ForSimVoiceProcess 15
        if (-not $p) {
            $launchFailures++
            throw "SimVoice failed to start during lifecycle cycle $i."
        }

        Start-Sleep -Seconds 2

        # Ask the WinForms main window to close normally first; if tray behavior keeps
        # the process alive, force it only after giving disposal logic time to run.
        try { $null = $p.CloseMainWindow() } catch {}
        $deadline = (Get-Date).AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 250
            try { $p.Refresh() } catch {}
        } while ((-not $p.HasExited) -and ((Get-Date) -lt $deadline))

        if (-not $p.HasExited) {
            $forcedStops++
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        }

        Start-Sleep -Milliseconds 500

        $cycleCrashes = @(Get-SimVoiceCrashEvents $stageStart)
        if ($cycleCrashes.Count -gt 0) {
            $crashDump = $cycleCrashes | Select-Object TimeCreated,ProviderName,Id,Message | Format-List | Out-String
            Set-Content -LiteralPath (Join-Path $RunDir "06-vosk-crash-events.txt") -Value $crashDump -Encoding UTF8
            throw "A new SimVoice/Vosk Windows crash was detected during lifecycle stress."
        }
    }

    $newLines = Get-NewDiagnosticLines $diagLog $beforeCount
    Set-Content -LiteralPath (Join-Path $RunDir "06-vosk-lifecycle-diagnostics.jsonl") -Value $newLines -Encoding UTF8
    $joined = $newLines -join "`n"
    $starts = ([regex]::Matches($joined, '"category"\s*:\s*"VOSK_AUDIO_WORKER_START"')).Count
    $stops = ([regex]::Matches($joined, '"category"\s*:\s*"VOSK_AUDIO_WORKER_STOP"')).Count

    if ($starts -lt [Math]::Min(5, $LifecycleCycles)) {
        throw "Lifecycle stress did not observe enough VOSK_AUDIO_WORKER_START events ($starts)."
    }

    "No native/.NET crash across $LifecycleCycles launches. Vosk worker starts=$starts, stops=$stops, forced process stops=$forcedStops."
}

Invoke-Stage "7. Build/install FINAL production MSIX" {
    Stop-SimVoiceProcesses
    $scriptPath = Join-Path $ProjectRoot "Store\Build-StoreMSIX.ps1"
    $stageLog = Join-Path $RunDir "07-production-msix-build.log"

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -SignAndInstall 2>&1 |
        Tee-Object -FilePath $stageLog |
        ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -ne 0) {
        throw "Build-StoreMSIX.ps1 -SignAndInstall returned exit code $LASTEXITCODE."
    }

    $msix = Find-LatestMsix
    if (-not $msix) { throw "Production MSIX $ExpectedVersion was not found in Store\Output." }
    $script:ProductionMsix = $msix

    "Production MSIX built and installed: $($msix.FullName)"
}

Invoke-Stage "8. Production MSIX payload/pre-certification guard" {
    if (-not $script:ProductionMsix) { throw "Production MSIX is unavailable." }

    $extract = Join-Path $RunDir "08-msix-unpacked"
    Ensure-Directory $extract
    $zipCopy = Join-Path $RunDir "08-production-msix.zip"
    Copy-Item -LiteralPath $script:ProductionMsix.FullName -Destination $zipCopy -Force
    Expand-Archive -LiteralPath $zipCopy -DestinationPath $extract -Force

    $manifest = Join-Path $extract "AppxManifest.xml"
    if (-not (Test-Path -LiteralPath $manifest)) {
        $manifest = Get-ChildItem -LiteralPath $extract -Recurse -Filter "AppxManifest.xml" -File | Select-Object -First 1
        if ($manifest) { $manifest = $manifest.FullName }
    }
    if (-not $manifest -or -not (Test-Path -LiteralPath $manifest)) {
        throw "AppxManifest.xml was not found inside the production MSIX."
    }

    $manifestText = Get-Content -LiteralPath $manifest -Raw
    if ($manifestText -notmatch ('Version="' + [regex]::Escape($ExpectedVersion) + '"')) {
        throw "Manifest version is not $ExpectedVersion."
    }
    if ($manifestText -notmatch "(?i)simvoicecopilot") {
        throw "windows.protocol registration for simvoicecopilot was not found in manifest."
    }
    if ($manifestText -notmatch "(?i)runFullTrust") {
        throw "runFullTrust capability was not found in manifest."
    }

    $exe = Join-Path $extract "SimVoiceCopilotApp.exe"
    if (-not (Test-Path -LiteralPath $exe)) { throw "SimVoiceCopilotApp.exe is missing from MSIX." }
    if (Test-FileContainsAscii $exe "QA Internal Audio") {
        throw "PRIVATE QA marker 'QA Internal Audio' is present in production executable."
    }

    $wasmRoot = Join-Path $extract "MSFS\Packages\simtech-simvoice-wasm-bridge"
    foreach ($rel in @("manifest.json","layout.json","modules\SimVoiceWasmBridge.wasm")) {
        $p = Join-Path $wasmRoot $rel
        if (-not (Test-Path -LiteralPath $p)) { throw "WASM bridge payload missing: $rel" }
    }

    $gguf = @(Get-ChildItem -LiteralPath $extract -Recurse -Filter "*.gguf" -File -ErrorAction SilentlyContinue)
    if ($gguf.Count -gt 0) {
        throw "Unexpected GGUF model is packaged in production MSIX. Optional 2.3 GB model must remain external."
    }

    # The default language can live in resources.pri; a dedicated language-en.pri
    # is not required. Validate declared languages from AppxManifest.xml instead.
    if ($manifestText -notmatch '(?i)<Resource\s+Language="en(?:-US)?"') {
        throw "English resource language declaration was not found in AppxManifest.xml."
    }
    if ($manifestText -notmatch '(?i)<Resource\s+Language="es(?:-ES)?"') {
        throw "Spanish resource language declaration was not found in AppxManifest.xml."
    }

    $priFiles = @(Get-ChildItem -LiteralPath $extract -Recurse -Filter "*.pri" -File -ErrorAction SilentlyContinue)
    if ($priFiles.Count -eq 0) {
        throw "No PRI resource file was found in the production MSIX."
    }

    # EFB -> Windows launch URI must be present somewhere in the packaged EFB text assets.
    $efbUriFound = $false
    $textFiles = Get-ChildItem -LiteralPath $extract -Recurse -File -Include *.js,*.html,*.htm,*.xml,*.json |
        Where-Object { $_.FullName -match "(?i)MSFS|EFB|simvoice" }
    foreach ($f in $textFiles) {
        if (Select-String -LiteralPath $f.FullName -SimpleMatch -Pattern "simvoicecopilot://launch?source=msfs2024-efb" -Quiet -ErrorAction SilentlyContinue) {
            $efbUriFound = $true
            break
        }
    }
    if (-not $efbUriFound) {
        throw "Packaged EFB launch URI simvoicecopilot://launch?source=msfs2024-efb was not found."
    }

    $hash = (Get-FileHash -LiteralPath $script:ProductionMsix.FullName -Algorithm SHA256).Hash
    Set-Content -LiteralPath (Join-Path $RunDir "08-production-msix-sha256.txt") `
        -Value ("{0}  {1}" -f $hash, $script:ProductionMsix.Name) -Encoding ASCII

    "MSIX version/protocol/EFB/WASM/languages/production-marker guards PASS. SHA256=$hash"
}

if (-not $SkipWack) {
    Invoke-Stage "9. Windows App Certification Kit (WACK)" {
        if (-not $script:ProductionMsix) { throw "Production MSIX is unavailable." }

        $appcert = "${env:ProgramFiles(x86)}\Windows Kits\10\App Certification Kit\appcert.exe"
        if (-not (Test-Path -LiteralPath $appcert)) {
            $appcert = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits" -Recurse -Filter "appcert.exe" -File -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName }
        }
        if (-not $appcert -or -not (Test-Path -LiteralPath $appcert)) {
            throw "Windows App Certification Kit (appcert.exe) was not found."
        }

        $resetLog = Join-Path $RunDir "09-wack-reset.log"
        $resetCode = Run-ExternalCapture $appcert @("reset") $resetLog

        if ($resetCode -ne 0) {
            Write-Log ("WACK reset returned exit code {0}; continuing to the authoritative WACK test." -f $resetCode) "WARN"
        } else {
            Write-Log "WACK reset: PASS" "PASS"
        }

        $report = Join-Path $RunDir "WACK-1.0.18.0.xml"
        $testLog = Join-Path $RunDir "09-wack-test.log"
        $testCode = Run-ExternalCapture $appcert @(
            "test",
            "-appxpackagepath", $script:ProductionMsix.FullName,
            "-reportoutputpath", $report
        ) $testLog

        if ($testCode -ne 0) {
            throw "WACK certification test failed with exit code $testCode. Review 09-wack-test.log."
        }

        if (-not (Test-Path -LiteralPath $report)) {
            $candidate = Get-ChildItem -LiteralPath $RunDir -File |
                Where-Object { $_.Name -match "(?i)WACK|report" -and $_.Extension -match "(?i)\.xml|\.htm|\.html" } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1

            if (-not $candidate) {
                throw "WACK test exited successfully but no report file was produced."
            }

            $report = $candidate.FullName
        }

        "WACK certification test PASS. resetExitCode=$resetCode; report=$report"
    }
} else {
    $started = Get-Date
    Add-StageResult "9. Windows App Certification Kit (WACK)" "WARN" "Skipped by -SkipWack; result is incomplete for Store certification." $started (Get-Date)
    $script:HasWarning = $true
}

Invoke-Stage "10. Final crash/event-log gate" {
    $crashes = @(Get-SimVoiceCrashEvents $RunStartLocal)
    if ($crashes.Count -gt 0) {
        $dump = $crashes | Select-Object TimeCreated,ProviderName,Id,Message | Format-List | Out-String
        Set-Content -LiteralPath (Join-Path $RunDir "10-new-windows-crashes.txt") -Value $dump -Encoding UTF8
        throw "One or more NEW SimVoice/Vosk crash records were generated during this certification run."
    }

    $diagLog = Get-DiagnosticLogPath
    if (Test-Path -LiteralPath $diagLog) {
        $today = @(Get-Content -LiteralPath $diagLog -Encoding UTF8)
        $fatal = @($today | Where-Object {
            $_ -match '"category"\s*:\s*"(REGRESSION_TEST_FAILED|UNHANDLED_EXCEPTION|APPLICATION_FATAL|QA_INTERNAL_AUDIO_INJECT_FAILED)"'
        })
        # Restrict fatal diagnostic lines to the run window by parsing JSON timestamps.
        $fatalAfter = New-Object System.Collections.ArrayList
        foreach ($line in $fatal) {
            try {
                $o = $line | ConvertFrom-Json
                if ($o.timestampUtc) {
                    $t = [datetimeoffset]::Parse([string]$o.timestampUtc).UtcDateTime
                    if ($t -ge $RunStartUtc) { $null = $fatalAfter.Add($line) }
                }
            } catch {}
        }
        if ($fatalAfter.Count -gt 0) {
            Set-Content -LiteralPath (Join-Path $RunDir "10-fatal-diagnostic-lines.jsonl") -Value @($fatalAfter) -Encoding UTF8
            throw "Fatal application diagnostic categories were logged during this certification run."
        }
    }

    "No NEW Windows crash or fatal diagnostic event during the complete automated QA."
}

$verdict = Write-Reports
if ($verdict -eq "AUTOMATED PASS") {
    exit 0
}
exit 1
