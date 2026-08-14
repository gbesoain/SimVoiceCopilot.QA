[CmdletBinding()]
param(
    [string]$WindowsAppPath = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp",
    [string]$EfbPath = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS",
    [string]$QaPath = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA",
    [ValidateRange(60, 600)]
    [int]$BuildTimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$downloads = Join-Path $env:USERPROFILE "Downloads"
$reportRoot = Join-Path $downloads "SimVoiceCopilot-1.0.20.0-HF35-QA-$stamp"
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][ValidateSet("PASS", "FAIL", "WARN")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    switch ($Status) {
        "PASS" { $script:PassCount++ }
        "FAIL" { $script:FailCount++ }
        "WARN" { $script:WarnCount++ }
    }

    $script:Results.Add([pscustomobject]@{
        id = $Id
        status = $Status
        detail = $Detail
    })

    $color = if ($Status -eq "PASS") { "Green" } elseif ($Status -eq "FAIL") { "Red" } else { "Yellow" }
    Write-Host ("[{0}] {1} - {2}" -f $Status, $Id, $Detail) -ForegroundColor $color
}

function Assert-Contains {
    param(
        [string]$Id,
        [string]$Path,
        [string]$Needle
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Result $Id "FAIL" "File not found: $Path"
        return
    }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) {
        Add-Result $Id "PASS" "Found required semantic marker/text."
    }
    else {
        Add-Result $Id "FAIL" "Missing: $Needle"
    }
}

function Assert-NotContains {
    param(
        [string]$Id,
        [string]$Path,
        [string]$Needle
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Result $Id "FAIL" "File not found: $Path"
        return
    }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        Add-Result $Id "PASS" "Forbidden regression pattern is absent."
    }
    else {
        Add-Result $Id "FAIL" "Forbidden regression pattern remains: $Needle"
    }
}

function Quote-NativeArgument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [int]$TimeoutSeconds = 300
    )

    $safeId = ($Id -replace '[^A-Za-z0-9_.-]', '_')
    $stdout = Join-Path $reportRoot ($safeId + "-stdout.log")
    $stderr = Join-Path $reportRoot ($safeId + "-stderr.log")
    $argumentString = ($ArgumentList | ForEach-Object { Quote-NativeArgument ([string]$_) }) -join " "

    try {
        $process = Start-Process -FilePath $FilePath `
            -ArgumentList $argumentString `
            -WorkingDirectory $WorkingDirectory `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -WindowStyle Hidden `
            -PassThru

        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            try { & taskkill.exe /PID $process.Id /T /F | Out-Null } catch { }
            Add-Result $Id "FAIL" "Timeout after $TimeoutSeconds seconds."
            $process.Dispose()
            return $false
        }

        $exitCode = [int]$process.ExitCode
        $process.Dispose()
        if ($exitCode -eq 0) {
            Add-Result $Id "PASS" "ExitCode=0"
            return $true
        }

        Add-Result $Id "FAIL" "ExitCode=$exitCode. See $stdout and $stderr"
        return $false
    }
    catch {
        Add-Result $Id "FAIL" $_.Exception.Message
        return $false
    }
}

function Find-MSBuild {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        try {
            $found = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" 2>$null | Select-Object -First 1
            if (-not [string]::IsNullOrWhiteSpace([string]$found) -and (Test-Path -LiteralPath $found -PathType Leaf)) {
                return [string]$found
            }
        }
        catch { }
    }

    $command = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $command = Get-Command msbuild -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    return ""
}

function Test-GitClean {
    param([string]$Id, [string]$Repo)
    try {
        $status = & git -C $Repo status --porcelain 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Result $Id "FAIL" ("git status failed: " + ($status -join " | "))
            return
        }
        if (@($status).Count -eq 0) {
            Add-Result $Id "PASS" "Repository is clean."
        }
        else {
            Add-Result $Id "WARN" ("Repository has local changes: " + (($status | Select-Object -First 8) -join " | "))
        }
    }
    catch {
        Add-Result $Id "WARN" ("Could not inspect git status: " + $_.Exception.Message)
    }
}

Write-Host "SimVoice Copilot 1.0.20.0 HF35 focused QA" -ForegroundColor Cyan
Write-Host "Report: $reportRoot" -ForegroundColor DarkGray

$syncFile = Join-Path $WindowsAppPath "ChecklistAircraftSyncService.cs"
$regressionFile = Join-Path $WindowsAppPath "ChecklistRegressionTests.cs"
$versionProps = Join-Path $WindowsAppPath "Version.props"
$subscriptionFile = Join-Path $WindowsAppPath "SubscriptionService.cs"
$efbUi = Join-Path $EfbPath "PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts"
$efbBuild = Join-Path $EfbPath "scripts\Build-SimVoiceEfb.ps1"
$efbDefinition = Join-Path $EfbPath "PackageDefinitions\simtech-simvoice-efb.xml"

Assert-Contains "HF35-WIN-MARKER" $syncFile "SIMVOICE_1_0_20_HF35_G3000_PREVIOUS_SHARED_TOGGLE_AND_CURSOR_PROBE"
Assert-Contains "HF35-PREVIOUS-SINGLE-TOGGLE" $syncFile 'TrySendPushCore(primary, "previous-uncheck")'
Assert-Contains "HF35-PREVIOUS-SECONDARY-SUPPRESSED" $syncFile '["secondaryPushSuppressed"] = true'
Assert-Contains "HF35-PREVIOUS-PRIMARY-RESTORE" $syncFile 'previous-uncheck-primary-cursor-restore'
Assert-Contains "HF35-COMPLETED-TRACKING" $syncFile 'sessionCompletedPositions.Contains(targetPosition)'
Assert-Contains "HF35-CURSOR-PROBE" $syncFile 'CHECKLIST_AIRCRAFT_CURSOR_PROBE'
Assert-Contains "HF35-REGRESSION" $regressionFile 'SelectPreviousSharedToggleEndpointsForRegression'
Assert-Contains "VERSION-WINDOWS-1.0.20.0" $versionProps '<SimVoiceVersion>1.0.20.0</SimVoiceVersion>'
Assert-Contains "VERSION-USERAGENT-1.0.20.0" $subscriptionFile 'SimVoiceCopilotApp/1.0.20.0'

Assert-Contains "HF35-EFB-NO-CAMERA-RESET" $efbUi "stopNativeChecklistHelper('checklist-tab-reset', true, false)"
Assert-NotContains "HF35-EFB-OLD-CAMERA-RESET-ABSENT" $efbUi "stopNativeChecklistHelperAndReset('checklist-tab-reset', true)"
Assert-Contains "HF35-EFB-MARKER" $efbUi "SIMVOICE_1_0_20_HF35_CHECKLIST_TAB_NO_CAMERA_RESET"
Assert-Contains "VERSION-EFB-SOURCE-0.1.36" $efbUi "const EFB_VERSION = '0.1.36';"
Assert-Contains "VERSION-EFB-BUILD-0.1.36" $efbBuild '$ExpectedEfbVersion = "0.1.36"'
Assert-Contains "VERSION-EFB-DEFINITION-0.1.36" $efbDefinition 'Version="0.1.36"'
Assert-Contains "HF35-EFB-BUILD-VALIDATION" $efbBuild "HF35 Checklist-tab no-camera-reset marker is missing from built TemplateApp.js."

Test-GitClean "GIT-WINDOWS" $WindowsAppPath
Test-GitClean "GIT-EFB" $EfbPath
Test-GitClean "GIT-QA" $QaPath

$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($null -eq $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
if ($null -eq $npm) {
    Add-Result "EFB-TYPECHECK" "FAIL" "npm was not found."
}
else {
    $efbAppRoot = Join-Path $EfbPath "PackageSources\TemplateApp"
    Invoke-NativeProcess `
        -Id "EFB-TYPECHECK" `
        -FilePath $npm.Source `
        -ArgumentList @("run", "typecheck") `
        -WorkingDirectory $efbAppRoot `
        -TimeoutSeconds $BuildTimeoutSeconds | Out-Null
}

$msbuild = Find-MSBuild
if ([string]::IsNullOrWhiteSpace($msbuild)) {
    Add-Result "WINDOWS-BUILD" "FAIL" "MSBuild was not found."
}
else {
    $project = Join-Path $WindowsAppPath "SimVoiceCopilotApp.csproj"
    $buildOk = Invoke-NativeProcess `
        -Id "WINDOWS-BUILD" `
        -FilePath $msbuild `
        -ArgumentList @($project, "/t:Build", "/p:Configuration=Debug", "/m:1", "/nr:false") `
        -WorkingDirectory $WindowsAppPath `
        -TimeoutSeconds $BuildTimeoutSeconds

    if ($buildOk) {
        $exe1 = Join-Path $WindowsAppPath "bin\Debug\net48\SimVoiceCopilotApp.exe"
        $exe2 = Join-Path $WindowsAppPath "bin\Debug\SimVoiceCopilotApp.exe"
        if ((Test-Path -LiteralPath $exe1 -PathType Leaf) -or (Test-Path -LiteralPath $exe2 -PathType Leaf)) {
            Add-Result "WINDOWS-DEBUG-OUTPUT" "PASS" "Authoritative Debug executable exists."
        }
        else {
            Add-Result "WINDOWS-DEBUG-OUTPUT" "FAIL" "No Debug executable found in net48 or legacy Debug output."
        }
    }
}

$manual = @'
HF35 MANUAL MSFS 2024 / VISION JET G2 QA

A. Checklist button / camera
1. Load Vision Jet G2 and start a Guided Checklist with a native helper/focus available.
2. Move the cockpit camera to a clearly non-default viewpoint.
3. Press the active EFB "Checklist" tab to return to checklist selection.
4. PASS: helper/highlight may stop, but the camera viewpoint does NOT reset or move.
5. Repeat with Auto ON and Auto OFF.

B. Previous shared completion toggle
1. Open the SAME native checklist and SAME starting item on both G3000 checklist displays and in SimVoice.
2. Confirm at least three consecutive items through SimVoice/EFB.
3. Press Previous once.
4. PASS: both display cursors return to the previous item; that item becomes blank/uncompleted on BOTH lists.
5. PASS: only ONE shared BUTTON toggle is emitted; there is no second BUTTON toggle for TSC2.
6. PASS: after the toggle, only the primary TSC cursor is restored one step so both cursors remain aligned on the blank item.
7. Press Previous again and repeat.
8. Re-confirm the blank item: it marks once and advances normally.
9. Include a Skip case: Previous to an item skipped by SimVoice must NOT mark it.

C. Cursor probe research
1. During the same session perform Confirm, Previous and Skip several times.
2. Generate a SimVoice Support package.
3. The support must contain CHECKLIST_AIRCRAFT_CURSOR_PROBE records with candidateValue and expectedSessionItemPosition.
4. These values are diagnostic only in HF35. They must NOT be used as cursor authority until correlation is demonstrated.

D. Regression
1. Complete/cancel a checklist using the already-certified lifecycle.
2. Verify the R24 camera ownership/reset behavior still occurs only in its intended lifecycle paths.
3. Verify Auto ON/OFF does not introduce the old global opacity overlay.
'@
$manualPath = Join-Path $reportRoot "MANUAL-MSFS-QA.txt"
[System.IO.File]::WriteAllText($manualPath, $manual, [System.Text.UTF8Encoding]::new($false))

$summary = [ordered]@{
    qa = "SimVoice Copilot 1.0.20.0 HF35"
    timestamp = (Get-Date).ToString("o")
    pass = $script:PassCount
    fail = $script:FailCount
    warn = $script:WarnCount
    automatedStatus = if ($script:FailCount -eq 0) { "PASS" } else { "FAIL" }
    certificationStatus = "PENDING_MANUAL_MSFS_QA"
    results = @($script:Results)
}
$summaryPath = Join-Path $reportRoot "qa-summary.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$txt = New-Object System.Collections.Generic.List[string]
$txt.Add("SimVoice Copilot 1.0.20.0 HF35 QA")
$txt.Add("PASS=$($script:PassCount) FAIL=$($script:FailCount) WARN=$($script:WarnCount)")
$txt.Add("Certification=PENDING_MANUAL_MSFS_QA")
foreach ($item in $script:Results) {
    $txt.Add(("[{0}] {1}: {2}" -f $item.status, $item.id, $item.detail))
}
$txt | Set-Content -LiteralPath (Join-Path $reportRoot "qa-summary.txt") -Encoding UTF8

$zipPath = Join-Path $downloads ("SimVoiceCopilot-1.0.20.0-HF35-QA-Report-{0}.zip" -f $stamp)
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $reportRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ""
Write-Host ("Automated QA: {0} PASS / {1} FAIL / {2} WARN" -f $script:PassCount, $script:FailCount, $script:WarnCount) -ForegroundColor $(if ($script:FailCount -eq 0) { "Green" } else { "Red" })
Write-Host "Manual MSFS QA remains mandatory before HF35 can be CERTIFIED." -ForegroundColor Yellow
Write-Host "Report ZIP: $zipPath" -ForegroundColor Cyan

if ($script:FailCount -gt 0) { exit 1 }
exit 0
