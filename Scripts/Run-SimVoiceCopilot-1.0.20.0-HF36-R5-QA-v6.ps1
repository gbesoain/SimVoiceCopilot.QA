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
$reportRoot = Join-Path $downloads "SimVoiceCopilot-1.0.20.0-HF36-R5-QA-$stamp"
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:Results = @()

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

    $script:Results += [pscustomobject]@{
        id = $Id
        status = $Status
        detail = $Detail
    }

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
    return '"' + $Value.Replace('"', '"') + '"'
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

Write-Host "SimVoice Copilot 1.0.20.0 HF36-R5 focused QA v6" -ForegroundColor Cyan
Write-Host ("PowerShell: {0}" -f $PSVersionTable.PSVersion.ToString()) -ForegroundColor DarkGray
Write-Host "Report: $reportRoot" -ForegroundColor DarkGray

$mainFile = Join-Path $WindowsAppPath "MainForm.cs"
$controllerFile = Join-Path $WindowsAppPath "SimVoiceEfbLocalController.cs"
$versionProps = Join-Path $WindowsAppPath "Version.props"
$syncFile = Join-Path $WindowsAppPath "ChecklistAircraftSyncService.cs"
$efbUi = Join-Path $EfbPath "PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts"
$efbTemplate = Join-Path $EfbPath "PackageSources\TemplateApp\src\TemplateApp.tsx"
$efbBuild = Join-Path $EfbPath "scripts\Build-SimVoiceEfb.ps1"
$efbDefinition = Join-Path $EfbPath "PackageDefinitions\simtech-simvoice-efb.xml"

# HF36: absolute Vision Jet G2 checklist selection through the G3000 EventBus.
Assert-Contains "HF36-G3000-MARKER" $efbUi "SIMVOICE_1_0_20_HF36_G3000_ABSOLUTE_LIST_SYNC"
Assert-Contains "HF36-G3000-EVENT" $efbUi "display_pane_checklist_select_list"
Assert-Contains "HF36-G3000-PUBLISH" $efbUi "this.eventBus.pub('display_pane_view_event'"
Assert-Contains "HF36-G3000-GROUP-READBACK" $efbUi 'checklist_pane_selected_group_index_${paneIndex}'
Assert-Contains "HF36-G3000-LIST-READBACK" $efbUi 'checklist_pane_selected_list_index_${paneIndex}'
Assert-Contains "HF36-G3000-PANES-1-4" $efbUi "for (let paneIndex = 1; paneIndex <= 4; paneIndex++)"
Assert-Contains "HF36-G3000-VISIONJET-GATE" $efbUi "source.includes('vision jet g2')"
Assert-Contains "HF36-G3000-ABSOLUTE-PAYLOAD" $efbUi "g3000AbsoluteSyncAttempted: g3000Sync.attempted"
Assert-Contains "HF36-G3000-BUS-INJECTION" $efbTemplate "BASE_URL || '', this.bus"
Assert-NotContains "HF36-G3000-OLD-PROPS-BUS-ABSENT" $efbTemplate "this.props.bus"
Assert-Contains "HF36-G3000-WINDOWS-BOOL" $controllerFile "Action<string, bool> checklistSelectionStarter"
Assert-Contains "HF36-G3000-WINDOWS-PAYLOAD" $controllerFile 'payload.Value<bool?>("g3000AbsoluteSyncAttempted")'
Assert-Contains "HF36-G3000-LEGACY-SUPPRESS" $mainFile "absoluteSelectionOwnedByEfb"
Assert-Contains "HF36-G3000-OWNERSHIP-DIAGNOSTIC" $mainFile "CHECKLIST_AIRCRAFT_LIST_ABSOLUTE_SELECTION_OWNED_BY_EFB"
Assert-Contains "HF36-G3000-HF35-FALLBACK-PRESERVED" $mainFile "service.NotifySessionAction(ChecklistVoiceIntent.NextChecklist);"

# HF36: previous-view restore is non-destructive. No custom camera slot may be saved or selected.
Assert-Contains "HF36-CAMERA-MARKER-EFB" $efbUi "SIMVOICE_1_0_20_HF36_CAMERA_PREFOCUS_RESTORE"
Assert-Contains "HF36-CAMERA-CHAIN-SAFE" $efbUi "SIMVOICE_1_0_20_HF36_CAMERA_PREFOCUS_RESTORE_CHAIN_SAFE"
Assert-Contains "HF36-CAMERA-AUTO-CHAIN-RESTORE" $efbUi "auto-focused-item-transition"
Assert-Contains "HF36-CAMERA-DEFERRED-STALE-RESTORE" $efbUi "waitForDeferredStaleCameraRestore"
Assert-Contains "HF36-CAMERA-ACTION" $efbUi "checklist.camera.restore_previous"
Assert-Contains "HF36-CAMERA-WINDOWS-ACTION" $controllerFile 'case "checklist.camera.restore_previous"'
Assert-Contains "HF36-CAMERA-PREVIOUS-EVENT" $controllerFile "VIEW_PREVIOUS_TOGGLE"
Assert-Contains "HF36-CAMERA-NO-CUSTOM-SLOT-DIAGNOSTIC" $controllerFile '["customCameraSlotUsed"] = false'
Assert-NotContains "HF36-CAMERA-NO-SAVE-SLOT" $controllerFile "CAMERA ACTION COCKPIT VIEW SAVE"
Assert-NotContains "HF36-CAMERA-NO-SLOT9-SELECT" $controllerFile "VIEW_CAMERA_SELECT_9"
Assert-NotContains "HF36-EFB-NO-SAVE-SLOT" $efbUi "CAMERA ACTION COCKPIT VIEW SAVE"
Assert-Contains "HF36-CAMERA-COMPLETION-RESTORE" $efbUi "restorePreviousCockpitView('checklist-completed')"
Assert-Contains "HF36-CAMERA-MANUAL-RESTORE" $efbUi "stopNativeChecklistHelperAndRestore('manual-focused-item-action', true)"
Assert-Contains "HF36-CAMERA-SIMCONNECT-END-RESTORE" $controllerFile 'RestorePreviousChecklistCamera("focused-item-ended")'

# Protect HF35-R4 certified behavior.
Assert-Contains "HF35-R4-WINDOWS-SCOPE" $mainFile "SIMVOICE_1_0_20_HF35_R4_G3000_ACTIVE_AIRCRAFT_SCOPE"
Assert-Contains "HF35-R2-PREVIOUS-SINGLE-TOGGLE" $syncFile 'TrySendPushCore(primary, "previous-uncheck")'
Assert-NotContains "HF35-R2-PREVIOUS-NO-EXTRA-DEC" $syncFile 'previous-uncheck-primary-cursor-restore'
Assert-Contains "HF35-EFB-NO-CAMERA-RESET" $efbUi "stopNativeChecklistHelper('checklist-tab-reset', true, false)"
Assert-NotContains "HF35-EFB-OLD-CAMERA-RESET-ABSENT" $efbUi "stopNativeChecklistHelperAndReset('checklist-tab-reset', true)"
Assert-Contains "VERSION-WINDOWS-1.0.20.0" $versionProps '<SimVoiceVersion>1.0.20.0</SimVoiceVersion>'
Assert-Contains "VERSION-EFB-SOURCE-0.1.37" $efbUi "const EFB_VERSION = '0.1.37';"
Assert-Contains "VERSION-EFB-BUILD-0.1.37" $efbBuild '$ExpectedEfbVersion = "0.1.37"'
Assert-Contains "HF36-BUILDER-FAIL-FAST" $efbBuild 'Write-Error ("EFB build failed: " + $message)'
Assert-Contains "HF36-BUILDER-EXIT-FAIL" $efbBuild "exit 1"
Assert-Contains "VERSION-EFB-DEFINITION-0.1.37" $efbDefinition 'Version="0.1.37"'

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

# HF36-R5: execute the established real EFB build, not only typecheck.
# The established builder remains authoritative for package publication/synchronization.
$powershellExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue)
if ($null -eq $powershellExe) {
    Add-Result "EFB-BUILD" "FAIL" "powershell.exe was not found."
}
else {
    $efbBuildOk = Invoke-NativeProcess `
        -Id "EFB-BUILD" `
        -FilePath $powershellExe.Source `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $efbBuild, "-WindowsProjectRoot", $WindowsAppPath) `
        -WorkingDirectory $EfbPath `
        -TimeoutSeconds $BuildTimeoutSeconds

    if ($efbBuildOk) {
        $efbBuildStdout = Join-Path $reportRoot "EFB-BUILD-stdout.log"
        if (Test-Path -LiteralPath $efbBuildStdout -PathType Leaf) {
            $efbBuildText = [System.IO.File]::ReadAllText($efbBuildStdout)
            if ($efbBuildText.IndexOf("EFB BUILD + PACKAGE + WINDOWS + STORE RUNTIME SYNC: PASS", [System.StringComparison]::Ordinal) -ge 0) {
                Add-Result "EFB-BUILD-SUCCESS-SENTINEL" "PASS" "Authoritative EFB build PASS sentinel found."
            }
            else {
                Add-Result "EFB-BUILD-SUCCESS-SENTINEL" "FAIL" "EFB process returned ExitCode=0 but authoritative PASS sentinel is missing."
            }
        }
        else {
            Add-Result "EFB-BUILD-SUCCESS-SENTINEL" "FAIL" "EFB build stdout log was not produced."
        }
    }
}

# Forced Rebuild is authoritative for net48 QA. Incremental /t:Build is forbidden here.
$msbuild = Find-MSBuild
if ([string]::IsNullOrWhiteSpace($msbuild)) {
    Add-Result "WINDOWS-REBUILD" "FAIL" "MSBuild was not found."
}
else {
    $project = Join-Path $WindowsAppPath "SimVoiceCopilotApp.csproj"
    $buildOk = Invoke-NativeProcess `
        -Id "WINDOWS-REBUILD" `
        -FilePath $msbuild `
        -ArgumentList @($project, "/t:Rebuild", "/p:Configuration=Debug", "/m:1", "/nr:false") `
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

# The installer builds/synchronizes EFB 0.1.37. Validate every authoritative/final package copy.
$debugRoot = ""
$exe1 = Join-Path $WindowsAppPath "bin\Debug\net48\SimVoiceCopilotApp.exe"
$exe2 = Join-Path $WindowsAppPath "bin\Debug\SimVoiceCopilotApp.exe"
if (Test-Path -LiteralPath $exe1 -PathType Leaf) {
    $debugRoot = Split-Path -Parent $exe1
}
elseif (Test-Path -LiteralPath $exe2 -PathType Leaf) {
    $debugRoot = Split-Path -Parent $exe2
}

$packageChecks = @(
    [pscustomobject]@{
        Id = "EFB-GENERATED"
        Root = (Join-Path $EfbPath "Packages\simtech-simvoice-efb")
    },
    [pscustomobject]@{
        Id = "EFB-WINDOWS-DEV"
        Root = (Join-Path $WindowsAppPath "MSFS\Packages\simtech-simvoice-efb")
    },
    [pscustomobject]@{
        Id = "EFB-STORE-RUNTIME"
        Root = (Join-Path $WindowsAppPath "Store\Runtime\MSFS\Packages\simtech-simvoice-efb")
    }
)

if (-not [string]::IsNullOrWhiteSpace($debugRoot)) {
    $packageChecks += [pscustomobject]@{
        Id = "EFB-DEBUG-BUNDLED"
        Root = (Join-Path $debugRoot "MSFS\Packages\simtech-simvoice-efb")
    }
}
else {
    Add-Result "EFB-DEBUG-BUNDLED" "FAIL" "Authoritative Debug root could not be resolved."
}

foreach ($packageCheck in $packageChecks) {
    $packageRoot = $packageCheck.Root
    $manifestPath = Join-Path $packageRoot "manifest.json"
    $layoutPath = Join-Path $packageRoot "layout.json"
    $jsPath = Join-Path $packageRoot "html_ui\efb_ui\efb_apps\SimVoiceCopilot\TemplateApp.js"

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-Result ($packageCheck.Id + "-MANIFEST") "FAIL" "Missing: $manifestPath"
        continue
    }
    if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf)) {
        Add-Result ($packageCheck.Id + "-LAYOUT") "FAIL" "Missing: $layoutPath"
        continue
    }
    if (-not (Test-Path -LiteralPath $jsPath -PathType Leaf)) {
        Add-Result ($packageCheck.Id + "-JS") "FAIL" "Missing: $jsPath"
        continue
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $version = ""
        foreach ($propertyName in @("package_version", "packageVersion", "version", "Version")) {
            $property = $manifest.PSObject.Properties[$propertyName]
            if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $version = ([string]$property.Value).Trim()
                break
            }
        }

        if ($version -eq "0.1.37") {
            Add-Result ($packageCheck.Id + "-VERSION") "PASS" ("0.1.37 at " + $packageRoot)
        }
        else {
            Add-Result ($packageCheck.Id + "-VERSION") "FAIL" ("Expected 0.1.37, found '" + $version + "' at " + $packageRoot)
        }

        $distJsPath = Join-Path $EfbPath "PackageSources\TemplateApp\dist\TemplateApp.js"
        if (Test-Path -LiteralPath $distJsPath -PathType Leaf) {
            $distHash = (Get-FileHash -LiteralPath $distJsPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $packageHash = (Get-FileHash -LiteralPath $jsPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($distHash -eq $packageHash) {
                Add-Result ($packageCheck.Id + "-DIST-BYTE-IDENTITY") "PASS" ("TemplateApp.js equals compiled dist: " + $distHash)
            }
            else {
                Add-Result ($packageCheck.Id + "-DIST-BYTE-IDENTITY") "FAIL" ("Compiled dist/package mismatch. Dist=" + $distHash + " Package=" + $packageHash)
            }
        }
        else {
            Add-Result ($packageCheck.Id + "-DIST-BYTE-IDENTITY") "FAIL" ("Compiled dist JavaScript missing: " + $distJsPath)
        }

        $jsText = [System.IO.File]::ReadAllText($jsPath)
        if ($jsText.IndexOf("checklist.camera.restore_previous", [System.StringComparison]::Ordinal) -ge 0 -and
            $jsText.IndexOf("display_pane_checklist_select_list", [System.StringComparison]::Ordinal) -ge 0 -and
            $jsText.IndexOf("checklist_pane_selected_group_index_", [System.StringComparison]::Ordinal) -ge 0 -and
            $jsText.IndexOf("checklist_pane_selected_list_index_", [System.StringComparison]::Ordinal) -ge 0 -and
            $jsText.IndexOf("SIMVOICE_1_0_20_HF35_CHECKLIST_TAB_NO_CAMERA_RESET", [System.StringComparison]::Ordinal) -ge 0) {
            Add-Result ($packageCheck.Id + "-RUNTIME-SEMANTICS") "PASS" ("HF36 functional runtime strings and HF35 regression marker present at " + $packageRoot)
        }
        else {
            Add-Result ($packageCheck.Id + "-RUNTIME-SEMANTICS") "FAIL" ("HF36 functional runtime strings are missing at " + $packageRoot)
        }
    }
    catch {
        Add-Result ($packageCheck.Id + "-VALIDATION") "FAIL" $_.Exception.Message
    }
}

$manual = @'
HF36 MANUAL MSFS 2024 / VISION JET G2 QA

A. Arbitrary EFB -> G3000 absolute checklist selection
1. Open the Vision Jet G2 detailed checklist selector in SimVoice EFB (Source must be Vision Jet G2).
2. Put both G3000 checklist displays on a DIFFERENT list from the one you will choose in EFB.
3. Select an arbitrary non-sequential list in EFB (example: jump from Before Engine Start to Before Taxi or another clearly non-adjacent list).
4. PASS: BOTH G3000 displays change directly to exactly the list selected in EFB; there is no stepping through intermediate lists.
5. Repeat with at least three different lists, including one backwards jump.
6. Generate a support package after the manual run so G3000 list-selection/readback and camera restore events can be reviewed.
7. Check paneReadback/matchingPanes. Record which display-pane indices actually report the target group/list.

B. Sequential transition regression
1. Complete a list and select its immediately following list from EFB.
2. PASS: the aircraft changes exactly once to the requested list; it must NOT advance an extra page.
3. Expected Windows diagnostic: CHECKLIST_AIRCRAFT_LIST_ABSOLUTE_SELECTION_OWNED_BY_EFB (legacy HF35 relative NextChecklist suppressed).

C. Camera restore - manual Focus
1. Before Focus, move the cockpit camera to a distinctive arbitrary position/zoom.
2. Press Focus on an item that has a helper.
3. Complete/leave the item so the normal focus lifecycle ends.
4. PASS: camera returns to the exact pre-Focus view, not Pilot/default.
5. Repeat from a different arbitrary cockpit view.

D. Camera restore - Auto
1. Set another distinctive cockpit view before Auto acquires focus.
2. Let Auto Focus an item and advance into a point where the focus lifecycle releases the helper (item without helper, Auto disabled, Cancel, or checklist completion as applicable).
3. PASS: camera returns to the pre-focus view rather than the default cockpit view.
4. If several focused items chain together, note whether the final restore returns to the original pre-chain user view or to an intermediate focused view. This is mandatory evidence for the next refinement if needed.

E. Custom camera slot safety
1. If convenient, assign a recognizable user custom camera to slot 9 before testing.
2. Run both manual and Auto Focus restore tests.
3. Recall slot 9 normally afterward.
4. PASS: slot 9 is unchanged. HF36 contains no SAVE/SELECT operation for custom camera slots.

F. HF35-R4 regression
1. Press Checklist repeatedly: camera must not reset.
2. Previous and Skip: both G3000 lists remain synchronized and Previous unchecks exactly once.
3. Auto-completion: SVC advances and reads the new current item.

G. Evidence
Generate a fresh SimVoiceCopilot-Support-YYYYMMDD-HHMMSS.zip after all tests.
'@
$manualPath = Join-Path $reportRoot "MANUAL-MSFS-QA.txt"
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[System.IO.File]::WriteAllText($manualPath, $manual, $utf8NoBom)

$automatedStatus = if ($script:FailCount -eq 0) { "PASS" } else { "FAIL" }
$summary = [ordered]@{
    qa = "SimVoice Copilot 1.0.20.0 HF36"
    runner = "v1"
    timestamp = (Get-Date).ToString("o")
    pass = $script:PassCount
    fail = $script:FailCount
    warn = $script:WarnCount
    automatedStatus = $automatedStatus
    certificationStatus = "PENDING_MANUAL_MSFS_QA"
    results = $script:Results
}

$summaryPath = Join-Path $reportRoot "qa-summary.json"
try {
    $json = ConvertTo-Json -InputObject $summary -Depth 8
    [System.IO.File]::WriteAllText($summaryPath, $json, $utf8NoBom)
}
catch {
    $script:FailCount++
    Write-Host ("[FAIL] REPORT-JSON - {0}" -f $_.Exception.Message) -ForegroundColor Red
    $fallback = '{"qa":"SimVoice Copilot 1.0.20.0 HF36","runner":"v1","automatedStatus":"FAIL","detail":"qa-summary.json generation failed"}'
    [System.IO.File]::WriteAllText($summaryPath, $fallback, $utf8NoBom)
}

$summaryTextPath = Join-Path $reportRoot "qa-summary.txt"
try {
    $lines = @()
    $lines += "SimVoice Copilot 1.0.20.0 HF36 QA v1"
    $lines += "PASS=$($script:PassCount) FAIL=$($script:FailCount) WARN=$($script:WarnCount)"
    $lines += "Certification=PENDING_MANUAL_MSFS_QA"
    foreach ($item in $script:Results) {
        $lines += ("[{0}] {1}: {2}" -f $item.status, $item.id, $item.detail)
    }
    [System.IO.File]::WriteAllLines($summaryTextPath, [string[]]$lines, $utf8NoBom)
}
catch {
    $script:FailCount++
    Write-Host ("[FAIL] REPORT-TEXT - {0}" -f $_.Exception.Message) -ForegroundColor Red
}

$zipPath = Join-Path $downloads ("SimVoiceCopilot-1.0.20.0-HF36-R5-QA-Report-v6-{0}.zip" -f $stamp)
try {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $reportRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal -ErrorAction Stop
    Write-Host ("[PASS] REPORT-ZIP - {0}" -f $zipPath) -ForegroundColor Green
}
catch {
    $script:FailCount++
    Write-Host ("[FAIL] REPORT-ZIP - {0}" -f $_.Exception.Message) -ForegroundColor Red
}

Write-Host ""
Write-Host ("Automated QA: {0} PASS / {1} FAIL / {2} WARN" -f $script:PassCount, $script:FailCount, $script:WarnCount) -ForegroundColor $(if ($script:FailCount -eq 0) { "Green" } else { "Red" })
Write-Host "Manual MSFS QA remains mandatory before HF36 can be CERTIFIED." -ForegroundColor Yellow
if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
    Write-Host "Report ZIP: $zipPath" -ForegroundColor Cyan
}
else {
    Write-Host "Report directory retained: $reportRoot" -ForegroundColor Yellow
}

if ($script:FailCount -gt 0) { exit 1 }
exit 0
