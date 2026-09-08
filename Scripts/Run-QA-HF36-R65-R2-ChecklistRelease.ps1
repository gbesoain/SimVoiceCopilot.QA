param(
    [string]$WindowsAppPath = "$env:USERPROFILE\Desktop\MSFS_App\MSFSVoiceMapperApp",
    [string]$EfbPath = "$env:USERPROFILE\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS",
    [string]$QaPath = "$env:USERPROFILE\Desktop\MSFS_App\SimVoiceCopilot.QA"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ProductVersion = '1.0.20.0'
$Hotfix = 'HF36-R65-R2'
$QaVersion = 'QA15-R2'
$ExpectedEfbVersion = '0.1.69'
$ExpectedR64Marker = 'SIMVOICE_1_0_20_HF36_R64_STRUCTURAL_EVIDENCE_V2'
$ExpectedR63Marker = 'SIMVOICE_1_0_20_HF36_R63_SR22_NATIVE_LIST_BOUNDARY_NO_FIGHT'
$ExpectedR55Marker = 'SIMVOICE_1_0_20_HF36_R55_SR22_INDEX_MAP_FAIL_CLOSED'
$ExpectedR57Marker = 'SIMVOICE_1_0_20_HF36_R57_DEFAULT_CHECKLIST_TAB'
$ExpectedR65Marker = 'SIMVOICE_1_0_20_HF36_R65_SUBSCRIPTION_RESILIENCE_CACHE'
$Downloads = Join-Path $env:USERPROFILE 'Downloads'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Work = Join-Path $env:TEMP ('SimVoiceCopilot-' + $Hotfix + '-' + $QaVersion + '-' + [Guid]::NewGuid().ToString('N'))
$LogPath = Join-Path $Downloads ('SimVoiceCopilot-' + $ProductVersion + '-' + $Hotfix + '-' + $QaVersion + '-ChecklistRelease-' + $Stamp + '.log')
$EvidenceZip = Join-Path $Downloads ('SimVoiceCopilot-' + $ProductVersion + '-' + $Hotfix + '-' + $QaVersion + '-ChecklistRelease-Evidence-' + $Stamp + '.zip')
$Results = New-Object System.Collections.Generic.List[object]
$CurrentStage = 'startup'
$FailureReason = ''
$Success = $false
$TranscriptStarted = $false
$UiBaseline = @{}
$UiSnapshotTaken = $false
$GitBaseline = @{}
$RunStarted = Get-Date

New-Item -ItemType Directory -Path $Work -Force | Out-Null

function Write-Stage([string]$Name) {
    $script:CurrentStage = $Name
    Write-Host ''
    Write-Host '====================================================================' -ForegroundColor Cyan
    Write-Host ('STAGE: ' + $Name) -ForegroundColor Cyan
    Write-Host '====================================================================' -ForegroundColor Cyan
}

function Add-Result([string]$Id, [string]$Status, [string]$Detail) {
    $Results.Add([pscustomobject]@{ Id = $Id; Status = $Status; Detail = $Detail }) | Out-Null
    $color = 'White'
    if ($Status -eq 'PASS') { $color = 'Green' }
    elseif ($Status -eq 'WARN') { $color = 'Yellow' }
    elseif ($Status -eq 'FAIL') { $color = 'Red' }
    Write-Host ('[{0}] {1} - {2}' -f $Status, $Id, $Detail) -ForegroundColor $color
}

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Assert-FileExists([string]$Id, [string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { Add-Result $Id 'PASS' $Path }
    else { Add-Result $Id 'FAIL' ('Missing file: ' + $Path) }
}

function Assert-DirectoryExists([string]$Id, [string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Container) { Add-Result $Id 'PASS' $Path }
    else { Add-Result $Id 'FAIL' ('Missing directory: ' + $Path) }
}

function Assert-FileHash([string]$Id, [string]$Path, [string]$Expected) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Result $Id 'FAIL' ('Missing file: ' + $Path)
        return
    }
    $actual = Get-Sha256 $Path
    if ($actual -eq $Expected.ToUpperInvariant()) { Add-Result $Id 'PASS' ('SHA256=' + $actual) }
    else { Add-Result $Id 'FAIL' ('Expected ' + $Expected.ToUpperInvariant() + ', found ' + $actual) }
}

function Assert-Contains([string]$Id, [string]$Path, [string]$Needle) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Result $Id 'FAIL' ('Missing file: ' + $Path)
        return
    }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) { Add-Result $Id 'PASS' ('Found: ' + $Needle) }
    else { Add-Result $Id 'FAIL' ('Missing semantic marker/text: ' + $Needle) }
}

function Assert-NotRegex([string]$Id, [string]$Path, [string]$Pattern) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Result $Id 'FAIL' ('Missing file: ' + $Path)
        return
    }
    $text = [System.IO.File]::ReadAllText($Path)
    if ([regex]::IsMatch($text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        Add-Result $Id 'FAIL' ('Forbidden pattern found: ' + $Pattern)
    } else {
        Add-Result $Id 'PASS' ('Forbidden pattern absent: ' + $Pattern)
    }
}

function Assert-TopLevelSourceContains([string]$Id, [string]$Root, [string]$Needle, [bool]$Required) {
    $found = $false
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Filter '*.cs' -ErrorAction SilentlyContinue)) {
        try {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) { $found = $true; break }
        } catch { }
    }
    if ($found) { Add-Result $Id 'PASS' ('Found in Windows top-level source: ' + $Needle) }
    elseif ($Required) { Add-Result $Id 'FAIL' ('Required Windows marker/text not found: ' + $Needle) }
    else { Add-Result $Id 'WARN' ('Advisory marker not found: ' + $Needle) }
}

function Assert-NoFailures([string]$Context) {
    $failCount = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    if ($failCount -gt 0) { throw ($Context + ' has ' + $failCount + ' FAIL gate(s).') }
}

function Quote-ProcessArg([string]$Value) {
    if ($null -eq $Value) { return '""' }
    if ($Value.Length -eq 0) { return '""' }
    if ($Value.IndexOf(' ') -lt 0 -and $Value.IndexOf("`t") -lt 0 -and $Value.IndexOf('"') -lt 0) { return $Value }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Join-ProcessArgs([string[]]$Arguments) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($arg in $Arguments) { $parts.Add((Quote-ProcessArg ([string]$arg))) | Out-Null }
    return ($parts -join ' ')
}

function Invoke-VisibleProcess([string]$Id, [string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory) {
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw ('Executable/script host missing: ' + $FilePath) }
    Write-Host ('[RUN] ' + $Id + ': ' + $FilePath + ' ' + (Join-ProcessArgs $Arguments)) -ForegroundColor DarkGray
    $previousLocation = Get-Location
    $previousErrorAction = $ErrorActionPreference
    try {
        Set-Location -LiteralPath $WorkingDirectory
        $ErrorActionPreference = 'Continue'
        & $FilePath @Arguments
        $code = [int]$LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
        Set-Location -LiteralPath $previousLocation
    }
    if ($code -eq 0) { Add-Result $Id 'PASS' 'ExitCode=0'; return }
    Add-Result $Id 'FAIL' ('ExitCode=' + $code)
    throw ($Id + ' failed with exit code ' + $code + '.')
}

function Invoke-CapturedProcess([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = Join-ProcessArgs $Arguments
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    $code = [int]$p.ExitCode
    $p.Dispose()
    return [pscustomobject]@{ ExitCode = $code; StdOut = $stdout; StdErr = $stderr }
}

function Find-MSBuild {
    $candidates = @(
        'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    $cmd = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Source }
    throw 'MSBuild.exe was not found.'
}

function Get-GitStatus([string]$Repo) {
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -eq $git) { $git = Get-Command git -ErrorAction SilentlyContinue }
    if ($null -eq $git) { throw 'git was not found in PATH.' }
    $r = Invoke-CapturedProcess $git.Source @('-C', $Repo, 'status', '--porcelain') $Repo
    if ($r.ExitCode -ne 0) { throw ('git status failed for ' + $Repo + ': ' + $r.StdErr) }
    return ([string]$r.StdOut).Replace("`r`n", "`n").TrimEnd([char]10)
}

function Snapshot-GitStatus([string]$Name, [string]$Repo) {
    $status = Get-GitStatus $Repo
    $script:GitBaseline[$Name] = $status
    if ([string]::IsNullOrWhiteSpace($status)) { Add-Result ('GIT-' + $Name + '-BASELINE') 'PASS' 'Repository clean.' }
    else { Add-Result ('GIT-' + $Name + '-BASELINE') 'PASS' ('Pre-existing working changes preserved as baseline: ' + (($status -split "`n" | Select-Object -First 8) -join ' | ')) }
}

function Assert-GitStatusUnchanged([string]$Name, [string]$Repo) {
    $current = Get-GitStatus $Repo
    $baseline = [string]$script:GitBaseline[$Name]
    if ($current -ceq $baseline) { Add-Result ('GIT-' + $Name + '-UNCHANGED') 'PASS' 'git status is byte-for-byte equivalent to QA baseline.' }
    else {
        Add-Result ('GIT-' + $Name + '-UNCHANGED') 'FAIL' ('QA changed repository working state. Before=[' + $baseline + '] After=[' + $current + ']')
    }
}

function Get-UiSettingsPaths {
    $paths = New-Object System.Collections.Generic.List[string]
    $fixed = @(
        (Join-Path $env:LOCALAPPDATA 'SimVoiceCopilot\ui_settings.json'),
        (Join-Path $env:LOCALAPPDATA 'SimVoiceCopilot\ui-settings.json'),
        (Join-Path $env:LOCALAPPDATA 'SimTechAviation\SimVoiceCopilot\ui_settings.json'),
        (Join-Path $env:LOCALAPPDATA 'SimTechAviation\SimVoiceCopilot\ui-settings.json')
    )
    foreach ($p in $fixed) { if (Test-Path -LiteralPath $p -PathType Leaf) { $paths.Add($p) | Out-Null } }
    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot -PathType Container) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $packagesRoot -Directory -Filter 'SimTechAviation.SimVoiceCopilot*' -ErrorAction SilentlyContinue)) {
            foreach ($name in @('ui_settings.json', 'ui-settings.json')) {
                $p = Join-Path $dir.FullName ('LocalState\' + $name)
                if (Test-Path -LiteralPath $p -PathType Leaf) { $paths.Add($p) | Out-Null }
            }
        }
    }
    return @($paths | Select-Object -Unique)
}

function Snapshot-UiSettings {
    foreach ($path in @(Get-UiSettingsPaths)) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $script:UiBaseline[$path] = $bytes
        Add-Result 'UI-SETTINGS-SNAPSHOT' 'PASS' ($path + ' SHA256=' + (Get-Sha256 $path))
    }
    if ($script:UiBaseline.Count -eq 0) { Add-Result 'UI-SETTINGS-SNAPSHOT' 'PASS' 'No ui_settings file existed before QA.' }
    $script:UiSnapshotTaken = $true
}

function Restore-UiSettings {
    if (-not $script:UiSnapshotTaken) { return }
    $currentPaths = @(Get-UiSettingsPaths)
    foreach ($path in $currentPaths) {
        if (-not $script:UiBaseline.ContainsKey($path)) {
            try { [System.IO.File]::Delete($path); Add-Result 'UI-SETTINGS-RESTORE-NEW' 'PASS' ('Removed QA-created settings file: ' + $path) }
            catch { Add-Result 'UI-SETTINGS-RESTORE-NEW' 'FAIL' ('Failed to remove QA-created settings file: ' + $path + ' :: ' + $_.Exception.Message) }
        }
    }
    foreach ($path in @($script:UiBaseline.Keys)) {
        try {
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::WriteAllBytes($path, [byte[]]$script:UiBaseline[$path])
            $now = [System.IO.File]::ReadAllBytes($path)
            $before64 = [Convert]::ToBase64String([byte[]]$script:UiBaseline[$path])
            $after64 = [Convert]::ToBase64String([byte[]]$now)
            if ($before64 -ceq $after64) {
                Add-Result 'UI-SETTINGS-RESTORE' 'PASS' ('Restored byte-for-byte: ' + $path)
            } else { Add-Result 'UI-SETTINGS-RESTORE' 'FAIL' ('Byte comparison failed after restore: ' + $path) }
        } catch { Add-Result 'UI-SETTINGS-RESTORE' 'FAIL' ('Restore failed: ' + $path + ' :: ' + $_.Exception.Message) }
    }
}

function Assert-EfbManifestVersion([string]$Id, [string]$ManifestPath) {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { Add-Result $Id 'FAIL' ('Missing manifest: ' + $ManifestPath); return }
    try {
        $m = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        $v = [string]$m.package_version
        if ([string]::IsNullOrWhiteSpace($v)) { $v = [string]$m.version }
        if ($v -eq $ExpectedEfbVersion) { Add-Result $Id 'PASS' ('EFB version=' + $v) }
        else { Add-Result $Id 'FAIL' ('Expected EFB ' + $ExpectedEfbVersion + ', found ' + $v) }
    } catch { Add-Result $Id 'FAIL' $_.Exception.Message }
}

function Capture-NewChildEvidence {
    $dest = Join-Path $Work 'child-evidence'
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $patterns = @('INTERNAL-*.zip', 'INTERNAL-*.log', 'SimVoiceCopilot-1.0.20.0-*-AutomatedQA-*.zip', 'SimVoiceCopilot-1.0.20.0-*-AutomatedQA-*.log')
    $seen = @{}
    foreach ($pattern in $patterns) {
        foreach ($file in @(Get-ChildItem -LiteralPath $Downloads -File -Filter $pattern -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $RunStarted.AddMinutes(-1) })) {
            if ($seen.ContainsKey($file.FullName)) { continue }
            $seen[$file.FullName] = $true
            $line = $file.FullName + ' | ' + $file.Length + ' bytes | SHA256=' + (Get-Sha256 $file.FullName)
            Add-Content -LiteralPath (Join-Path $dest 'CHILD-EVIDENCE-MANIFEST.txt') -Value $line -Encoding UTF8
            if ($file.Length -le 52428800) {
                $target = Join-Path $dest $file.Name
                [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($file.FullName))
            }
        }
    }
}

try {
    Start-Transcript -Path $LogPath -Force | Out-Null
    $TranscriptStarted = $true

    Write-Host '====================================================================' -ForegroundColor Cyan
    Write-Host ' SimVoice Copilot 1.0.20.0 - HF36-R65-R2' -ForegroundColor Cyan
    Write-Host ' QA15-R2 CHECKLIST + SUBSCRIPTION RELEASE AUTOMATED QA' -ForegroundColor Cyan
    Write-Host ' Existing QA14-R5 191-case matrix + R55/R57/R63/R64 + R65-R2 subscription release gates' -ForegroundColor Cyan
    Write-Host '====================================================================' -ForegroundColor Cyan
    Write-Host ('Persistent log: ' + $LogPath)
    Write-Host 'Prerequisite: MSFS 2024 must already be running in an ACTIVE FLIGHT.' -ForegroundColor Yellow
    Write-Host 'This QA intentionally builds and installs the private [QA Internal Audio] MSIX.' -ForegroundColor Yellow
    Write-Host 'Manual final checklist QA must later use a fresh NORMAL MSIX.' -ForegroundColor Yellow

    Write-Stage 'preflight'
    Assert-DirectoryExists 'PATH-WINDOWS' $WindowsAppPath
    Assert-DirectoryExists 'PATH-EFB' $EfbPath
    Assert-DirectoryExists 'PATH-QA' $QaPath

    $Project = Join-Path $WindowsAppPath 'SimVoiceCopilotApp.csproj'
    $EfbBuild = Join-Path $EfbPath 'scripts\Build-SimVoiceEfb.ps1'
    $QaBuilder = Join-Path $WindowsAppPath 'Store\Build-QA-InternalAudio-MSIX.ps1'
    $ReleaseMatrix = Join-Path $QaPath 'Scripts\Run-QA-ReleaseCandidate-Matrix.ps1'
    Assert-FileExists 'WINDOWS-CSPROJ' $Project
    Assert-FileExists 'EFB-BUILDER' $EfbBuild
    Assert-FileExists 'QA-INTERNAL-AUDIO-BUILDER' $QaBuilder
    Assert-FileExists 'QA-RELEASE-MATRIX' $ReleaseMatrix

    $sim = @(Get-Process -Name 'FlightSimulator2024','FlightSimulator' -ErrorAction SilentlyContinue)
    if ($sim.Count -gt 0) { Add-Result 'MSFS-PROCESS' 'PASS' ('Detected ' + (($sim | Select-Object -ExpandProperty ProcessName -Unique) -join ', ')) }
    else { Add-Result 'MSFS-PROCESS' 'FAIL' 'MSFS was not detected. Start MSFS 2024 and load an active flight before running QA.' }

    Snapshot-UiSettings
    Snapshot-GitStatus 'WINDOWS' $WindowsAppPath
    Snapshot-GitStatus 'EFB' $EfbPath
    Snapshot-GitStatus 'QA' $QaPath
    Assert-NoFailures 'Preflight'

    Write-Stage 'exact-r64-efb-source-gates'
    $Adapter = Join-Path $EfbPath 'PackageSources\TemplateApp\src\SimVoiceCopilot\native\adapters\Sr22tG1000NxiChecklistAdapter.ts'
    $Learning = Join-Path $EfbPath 'PackageSources\TemplateApp\src\SimVoiceCopilot\native\ChecklistStructuralLearningEngine.ts'
    $EfbApp = Join-Path $EfbPath 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
    $EfbManifest = Join-Path $EfbPath 'Packages\simtech-simvoice-efb\manifest.json'

    Assert-FileHash 'R64-ADAPTER-EXACT' $Adapter '9B83FA92081CA48A5137D148205902DD6E33DC77E8E64300AC4FC357BB8A94BF'
    Assert-FileHash 'R64-LEARNING-EXACT' $Learning '537A63CEB5825C7C9434777CC8D892EEBA97E946CD52739119D5F76FD460266C'
    Assert-FileHash 'R64-EFB-APP-EXACT' $EfbApp 'A3FFD1C101226EA7951AC943CD4378D38C8F05CA87FA95392C576E2686B7699D'
    Assert-FileHash 'R64-EFB-BUILDER-EXACT' $EfbBuild '72A9F007B09358D1F9890DAA6513AC10572B6042C5508C2435086E9A6B9301CE'
    Assert-EfbManifestVersion 'R64-EFB-VERSION' $EfbManifest

    Assert-Contains 'R64-MARKER-ADAPTER' $Adapter $ExpectedR64Marker
    Assert-Contains 'R63-NO-FIGHT-MARKER' $Adapter $ExpectedR63Marker
    Assert-Contains 'R55-FAIL-CLOSE-MARKER' $Adapter $ExpectedR55Marker
    Assert-Contains 'R57-DEFAULT-TAB-MARKER' $EfbApp $ExpectedR57Marker
    Assert-Contains 'R57-DEFAULT-TAB-BEHAVIOR' $EfbApp "private activeTab: TabId = 'checklist';"
    Assert-Contains 'R64-SESSION-START' $Learning "kind: 'structural-session-start'"
    Assert-Contains 'R64-EVIDENCE-CHECKPOINT' $Learning "kind: 'evidence-checkpoint'"
    Assert-Contains 'R64-STRUCTURE-SCORE' $Learning 'structureEvidenceScore'
    Assert-Contains 'R64-ITEM-SCORE' $Learning 'itemMappingScore'
    Assert-Contains 'R64-PROMOTION-SCORE' $Learning 'promotionEvidenceScore'
    Assert-Contains 'R64-AUTO-PROMOTION-FALSE' $Learning 'automaticPromotionAllowed: false'
    Assert-Contains 'R64-AI-PROMOTION-FALSE' $Learning 'aiMayPromote: false'
    Assert-Contains 'R64-SAFE-FOR-WRITE-FALSE' $Learning 'safeForWrite: false'
    Assert-Contains 'R64-MANUAL-ITEM-STATE-UNAVAILABLE' $Adapter 'manualItemStateReadbackAvailable: false'
    Assert-Contains 'R62-LIST-ROUNDTRIP-REQUEST' $Adapter 'checklist.avionics.list_roundtrip_request'
    Assert-Contains 'R63-NATIVE-LIST-BOUNDARY' $Adapter 'checklist.avionics.native_list_boundary'
    Assert-Contains 'R63-NO-FIGHT-DIAGNOSTIC' $Adapter 'native-strict-next-boundary-no-fight'
    Assert-NotRegex 'R45-NO-DISPLAY-PANE-VIEW-PUBLISH' $EfbApp 'eventBus\s*\.\s*pub\s*\([^\r\n]{0,240}displayPaneView'
    Assert-NotRegex 'R45-NO-DISPLAY-PANE-VISIBLE-PUBLISH' $EfbApp 'eventBus\s*\.\s*pub\s*\([^\r\n]{0,240}displayPaneVisible'
    Assert-NoFailures 'Exact R64 EFB source gates'

    Write-Stage 'windows-checklist-safety-gates'
    $SessionManager = Join-Path $WindowsAppPath 'ChecklistSessionManager.cs'
    $SyncService = Join-Path $WindowsAppPath 'ChecklistAircraftSyncService.cs'
    $RegressionTests = Join-Path $WindowsAppPath 'ChecklistRegressionTests.cs'
    $ChecklistModels = Join-Path $WindowsAppPath 'ChecklistModels.cs'
    Assert-FileExists 'WINDOWS-SESSION-MANAGER' $SessionManager
    Assert-FileExists 'WINDOWS-SYNC-SERVICE' $SyncService
    Assert-FileExists 'WINDOWS-CHECKLIST-REGRESSIONS' $RegressionTests
    Assert-FileExists 'WINDOWS-CHECKLIST-MODELS' $ChecklistModels
    Assert-Contains 'R32-CANONICAL-CHECKLIST-ID' $ChecklistModels 'ChecklistId'
    Assert-Contains 'R32-CANONICAL-CURRENT-ITEM-ID' $ChecklistModels 'CurrentItemId'
    Assert-Contains 'R32-CANONICAL-COMPLETED-ITEM-IDS' $ChecklistModels 'CompletedItemIds'
    Assert-Contains 'R55-WINDOWS-AVIONICS-MAP-SAFETY' $SessionManager 'AvionicsIndexMapSafe'
    Assert-Contains 'R55-WINDOWS-CURRENT-AVIONICS-INDEX' $SessionManager 'CurrentItemAvionicsIndex'
    Assert-Contains 'R55-WINDOWS-COMPLETED-AVIONICS-INDEXES' $SessionManager 'CompletedAvionicsIndexes'
    Assert-Contains 'R55-WINDOWS-SKIPPED-AVIONICS-INDEXES' $SessionManager 'SkippedAvionicsIndexes'
    Assert-TopLevelSourceContains 'R56-AIRCRAFT-IDENTITY-MARKER' $WindowsAppPath 'SIMVOICE_1_0_20_HF36_R56' $false
    Assert-TopLevelSourceContains 'R53-HJET-MARKER' $WindowsAppPath 'SIMVOICE_1_0_20_HF36_R53' $false
    Assert-TopLevelSourceContains 'R48-FRESH-SESSION-MARKER' $WindowsAppPath 'SIMVOICE_1_0_20_HF36_R48' $false
    Assert-TopLevelSourceContains 'R32-PANE-GUARD-MARKER' $WindowsAppPath 'SIMVOICE_1_0_20_HF36_R8_G3000_CHECKLIST_VIEW_GUARD' $false
    Assert-NoFailures 'Windows checklist safety gates'

    Write-Stage 'r65-r2-subscription-resilience-gates'
    $SubscriptionService = Join-Path $WindowsAppPath 'SubscriptionService.cs'
    $SubscriptionCache = Join-Path $WindowsAppPath 'SubscriptionResilienceCache.cs'
    $StartupExperience = Join-Path $WindowsAppPath 'StartupExperienceForm.cs'
    $StartupSubscriptionTests = Join-Path $WindowsAppPath 'StartupSubscriptionRegressionTests.cs'
    $EmailManager = Join-Path $WindowsAppPath 'EmailManager.cs'
    $MainForm = Join-Path $WindowsAppPath 'MainForm.cs'

    Assert-FileHash 'R65-SUBSCRIPTION-SERVICE-EXACT' $SubscriptionService 'D9EF94F34B396B657F2323552CEBCAA39B193809E28611279658BCCF097F02B8'
    Assert-FileHash 'R65-CACHE-EXACT' $SubscriptionCache 'ADED1B7A157E7967A6528CCD499B69C52E2E6D8B1E7662B6E406C88579112A65'
    Assert-FileHash 'R65-STARTUP-EXPERIENCE-EXACT' $StartupExperience '3F935790E4028A73E298C58A6C98C46D26EE8C59D32CF434138B0EA957ABC19E'
    Assert-FileHash 'R65-REGRESSION-TESTS-EXACT' $StartupSubscriptionTests '71B70B35DB40A443E740A4D3FBB39DCECC28032C1DD1660E22E7BD065AAE75CF'
    Assert-FileHash 'R65-EMAIL-MANAGER-EXACT' $EmailManager 'BFA8382CF339969C02BC160773F9A06B634AF59C5F244AB635D36B081F0DE969'
    Assert-FileHash 'R65-R2-MAINFORM-EXACT' $MainForm '02A256BECCE09DDDF9965C16E84F0254D6AF2F3652DAA613BD2844299F0C30B8'

    Assert-Contains 'R65-CACHE-MARKER' $SubscriptionCache $ExpectedR65Marker
    Assert-Contains 'R65-DPAPI-PROTECT' $SubscriptionCache 'ProtectedData.Protect('
    Assert-Contains 'R65-DPAPI-CURRENT-USER' $SubscriptionCache 'DataProtectionScope.CurrentUser'
    Assert-Contains 'R65-SEVEN-DAY-GRACE' $SubscriptionCache 'TimeSpan.FromDays(7)'
    Assert-Contains 'R65-CACHE-REFRESHED-DIAGNOSTIC' $SubscriptionService 'STARTUP_SUBSCRIPTION_CACHE_REFRESHED'
    Assert-Contains 'R65-CACHE-HIT-DIAGNOSTIC' $SubscriptionService 'STARTUP_SUBSCRIPTION_CACHE_HIT'
    Assert-Contains 'R65-CACHE-MISS-DIAGNOSTIC' $SubscriptionService 'STARTUP_SUBSCRIPTION_CACHE_MISS'
    Assert-Contains 'R65-HTTP-408' $SubscriptionService 'statusCode == 408'
    Assert-Contains 'R65-HTTP-429' $SubscriptionService 'statusCode == 429'
    Assert-Contains 'R65-HTTP-5XX-LOWER' $SubscriptionService 'statusCode >= 500'
    Assert-Contains 'R65-HTTP-5XX-UPPER' $SubscriptionService 'statusCode <= 599'
    Assert-Contains 'R65-OFFLINE-DIAGNOSTIC' $StartupExperience 'STARTUP_SUBSCRIPTION_OFFLINE'
    Assert-Contains 'R65-LOGOUT-CLEARS-CACHE' $EmailManager 'SubscriptionResilienceCache.Delete();'
    Assert-Contains 'R65-TEST-GRACE-EXPIRED' $StartupSubscriptionTests 'offline-grace-expired'
    Assert-Contains 'R65-TEST-EMAIL-BINDING' $StartupSubscriptionTests 'email-mismatch'
    Assert-Contains 'R65-TEST-DEVICE-BINDING' $StartupSubscriptionTests 'device-mismatch'
    Assert-Contains 'R65-TEST-CLOCK-ROLLBACK' $StartupSubscriptionTests 'clock-before-validation'
    Assert-Contains 'R65-TEST-HTTP-503' $StartupSubscriptionTests 'IsTransientHttpStatusCode(503)'
    Assert-Contains 'R65-TEST-HTTP-403-NO-FALLBACK' $StartupSubscriptionTests 'IsTransientHttpStatusCode(403)'
    Assert-Contains 'R65-R2-AUTHORITY-REUSED' $MainForm 'STARTUP_SUBSCRIPTION_AUTHORITY_REUSED'
    Assert-Contains 'R65-R2-AUTHORITY-INVALID' $MainForm 'STARTUP_SUBSCRIPTION_AUTHORITY_INVALID'
    Assert-NotRegex 'R65-R2-NO-SECOND-SERVER-VALIDATION' $MainForm 'EmailManager\s*\.\s*VerifyEmailWithServer\s*\('
    Assert-NoFailures 'R65-R2 subscription resilience gates'

    Write-Stage 'efb-build-and-runtime-sync' 
    Invoke-VisibleProcess 'EFB-BUILD-SYNC' 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$EfbBuild,'-WindowsProjectRoot',$WindowsAppPath) $EfbPath

    Assert-FileHash 'POSTBUILD-R64-ADAPTER-EXACT' $Adapter '9B83FA92081CA48A5137D148205902DD6E33DC77E8E64300AC4FC357BB8A94BF'
    Assert-FileHash 'POSTBUILD-R64-LEARNING-EXACT' $Learning '537A63CEB5825C7C9434777CC8D892EEBA97E946CD52739119D5F76FD460266C'
    Assert-FileHash 'POSTBUILD-R64-EFB-APP-EXACT' $EfbApp 'A3FFD1C101226EA7951AC943CD4378D38C8F05CA87FA95392C576E2686B7699D'
    Assert-FileHash 'POSTBUILD-R64-EFB-BUILDER-EXACT' $EfbBuild '72A9F007B09358D1F9890DAA6513AC10572B6042C5508C2435086E9A6B9301CE'

    $runtimeRoots = @(
        (Join-Path $EfbPath 'Packages\simtech-simvoice-efb'),
        (Join-Path $WindowsAppPath 'MSFS\Packages\simtech-simvoice-efb'),
        (Join-Path $WindowsAppPath 'Store\Runtime\MSFS\Packages\simtech-simvoice-efb')
    )
    $runtimeJsHashes = New-Object System.Collections.Generic.List[string]
    $runtimeIndex = 0
    foreach ($root in $runtimeRoots) {
        $runtimeIndex++
        $manifest = Join-Path $root 'manifest.json'
        $js = Join-Path $root 'html_ui\efb_ui\efb_apps\SimVoiceCopilot\TemplateApp.js'
        Assert-EfbManifestVersion ('RUNTIME-' + $runtimeIndex + '-VERSION') $manifest
        Assert-Contains ('RUNTIME-' + $runtimeIndex + '-R64-MARKER') $js $ExpectedR64Marker
        if (Test-Path -LiteralPath $js -PathType Leaf) { $runtimeJsHashes.Add((Get-Sha256 $js)) | Out-Null }
    }
    if ($runtimeJsHashes.Count -eq 3 -and $runtimeJsHashes[0] -eq $runtimeJsHashes[1] -and $runtimeJsHashes[0] -eq $runtimeJsHashes[2]) {
        Add-Result 'EFB-RUNTIME-COPIES-IDENTICAL' 'PASS' ('TemplateApp.js SHA256=' + $runtimeJsHashes[0])
    } else { Add-Result 'EFB-RUNTIME-COPIES-IDENTICAL' 'FAIL' ('Runtime JS hashes differ: ' + ($runtimeJsHashes -join ', ')) }
    Assert-NoFailures 'EFB build/runtime sync'

    Write-Stage 'windows-normal-release-rebuild'
    foreach ($p in @(Get-Process -Name 'SimVoiceCopilotApp' -ErrorAction SilentlyContinue)) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
    }
    $MSBuild = Find-MSBuild
    Add-Result 'MSBUILD-FOUND' 'PASS' $MSBuild
    Invoke-VisibleProcess 'WINDOWS-RELEASE-REBUILD' $MSBuild @($Project,'/t:Rebuild','/m:1','/nr:false','/p:Configuration=Release','/p:Platform=x64') $WindowsAppPath

    Write-Stage 'fresh-private-qa-internal-audio-msix'
    Invoke-VisibleProcess 'QA-INTERNAL-AUDIO-MSIX' 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$QaBuilder) $WindowsAppPath

    Write-Stage 'qa14-r5-compatible-191-case-release-matrix'
    Write-Host 'The existing release matrix will print its own per-suite/total progress.' -ForegroundColor Yellow
    Invoke-VisibleProcess 'RELEASE-MATRIX-191' 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$ReleaseMatrix) $QaPath

    Write-Stage 'post-qa-source-and-settings-integrity'
    Assert-FileHash 'FINAL-R64-ADAPTER-EXACT' $Adapter '9B83FA92081CA48A5137D148205902DD6E33DC77E8E64300AC4FC357BB8A94BF'
    Assert-FileHash 'FINAL-R64-LEARNING-EXACT' $Learning '537A63CEB5825C7C9434777CC8D892EEBA97E946CD52739119D5F76FD460266C'
    Assert-FileHash 'FINAL-R64-EFB-APP-EXACT' $EfbApp 'A3FFD1C101226EA7951AC943CD4378D38C8F05CA87FA95392C576E2686B7699D'
    Assert-FileHash 'FINAL-R64-EFB-BUILDER-EXACT' $EfbBuild '72A9F007B09358D1F9890DAA6513AC10572B6042C5508C2435086E9A6B9301CE'
    Assert-FileHash 'FINAL-R65-SUBSCRIPTION-SERVICE-EXACT' $SubscriptionService 'D9EF94F34B396B657F2323552CEBCAA39B193809E28611279658BCCF097F02B8'
    Assert-FileHash 'FINAL-R65-CACHE-EXACT' $SubscriptionCache 'ADED1B7A157E7967A6528CCD499B69C52E2E6D8B1E7662B6E406C88579112A65'
    Assert-FileHash 'FINAL-R65-STARTUP-EXPERIENCE-EXACT' $StartupExperience '3F935790E4028A73E298C58A6C98C46D26EE8C59D32CF434138B0EA957ABC19E'
    Assert-FileHash 'FINAL-R65-REGRESSION-TESTS-EXACT' $StartupSubscriptionTests '71B70B35DB40A443E740A4D3FBB39DCECC28032C1DD1660E22E7BD065AAE75CF'
    Assert-FileHash 'FINAL-R65-EMAIL-MANAGER-EXACT' $EmailManager 'BFA8382CF339969C02BC160773F9A06B634AF59C5F244AB635D36B081F0DE969'
    Assert-FileHash 'FINAL-R65-R2-MAINFORM-EXACT' $MainForm '02A256BECCE09DDDF9965C16E84F0254D6AF2F3652DAA613BD2844299F0C30B8'
    Assert-GitStatusUnchanged 'WINDOWS' $WindowsAppPath
    Assert-GitStatusUnchanged 'EFB' $EfbPath
    Assert-GitStatusUnchanged 'QA' $QaPath

    Restore-UiSettings
    Assert-NoFailures 'Post-QA integrity'

    Capture-NewChildEvidence
    $Success = $true
}
catch {
    $FailureReason = $_.Exception.Message
    Add-Result 'QA-FATAL' 'FAIL' ('Stage=' + $CurrentStage + ' :: ' + $FailureReason)
    try { Restore-UiSettings } catch { }
    try { Capture-NewChildEvidence } catch { }
}
finally {
    $pass = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $fail = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $warn = @($Results | Where-Object { $_.Status -eq 'WARN' }).Count
    if ($fail -gt 0) { $Success = $false }

    $summaryPath = Join-Path $Work 'QA-SUMMARY.txt'
    $summaryLines = New-Object System.Collections.Generic.List[string]
    $summaryLines.Add(('SimVoice Copilot ' + $ProductVersion + ' ' + $Hotfix + ' ' + $QaVersion)) | Out-Null
    $summaryLines.Add(('Generated: ' + (Get-Date -Format o))) | Out-Null
    $summaryLines.Add(('Result: ' + $(if ($Success) { 'PASS' } else { 'FAIL' }))) | Out-Null
    $summaryLines.Add(('Gates: ' + $pass + ' PASS / ' + $fail + ' FAIL / ' + $warn + ' WARN')) | Out-Null
    $summaryLines.Add(('Last stage: ' + $CurrentStage)) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($FailureReason)) { $summaryLines.Add(('Reason: ' + $FailureReason)) | Out-Null }
    $summaryLines.Add('') | Out-Null
    foreach ($r in $Results) { $summaryLines.Add(('[' + $r.Status + '] ' + $r.Id + ' - ' + $r.Detail)) | Out-Null }
    [System.IO.File]::WriteAllLines($summaryPath, $summaryLines.ToArray(), (New-Object System.Text.UTF8Encoding($false)))

    if ($TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
        $TranscriptStarted = $false
    }

    try {
        if (Test-Path -LiteralPath $EvidenceZip -PathType Leaf) { Remove-Item -LiteralPath $EvidenceZip -Force }
        Compress-Archive -Path (Join-Path $Work '*') -DestinationPath $EvidenceZip -CompressionLevel Optimal
    } catch {
        $Success = $false
        $FailureReason = 'Evidence packaging failed: ' + $_.Exception.Message
    }

    $pass = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $fail = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $warn = @($Results | Where-Object { $_.Status -eq 'WARN' }).Count

    $finalLines = New-Object System.Collections.Generic.List[string]
    $finalLines.Add('') | Out-Null
    $finalLines.Add('====================================================================') | Out-Null
    if ($Success) { $finalLines.Add('[PASS] SimVoice Copilot 1.0.20.0 HF36-R65-R2 QA15-R2 CHECKLIST + SUBSCRIPTION RELEASE QA') | Out-Null }
    else { $finalLines.Add('[FAIL] SimVoice Copilot 1.0.20.0 HF36-R65-R2 QA15-R2 CHECKLIST + SUBSCRIPTION RELEASE QA') | Out-Null }
    $finalLines.Add('====================================================================') | Out-Null
    $finalLines.Add(('Gates: ' + $pass + ' PASS / ' + $fail + ' FAIL / ' + $warn + ' WARN')) | Out-Null
    if (-not $Success) {
        $finalLines.Add(('Stage: ' + $CurrentStage)) | Out-Null
        $finalLines.Add(('Reason: ' + $FailureReason)) | Out-Null
    }
    $finalLines.Add(('Log: ' + $LogPath)) | Out-Null
    $finalLines.Add(('Evidence: ' + $EvidenceZip)) | Out-Null
    if ($Success) { $finalLines.Add('NEXT: rebuild/install a fresh NORMAL MSIX before manual MSFS checklist certification.') | Out-Null }
    else { $finalLines.Add('RC/manual certification remains BLOCKED until this QA is PASS.') | Out-Null }

    try { [System.IO.File]::AppendAllLines($LogPath, $finalLines.ToArray(), (New-Object System.Text.UTF8Encoding($false))) } catch { }
    foreach ($line in $finalLines) {
        if ($line.StartsWith('[PASS]')) { Write-Host $line -ForegroundColor Green }
        elseif ($line.StartsWith('[FAIL]')) { Write-Host $line -ForegroundColor Red }
        elseif ($line.StartsWith('NEXT:')) { Write-Host $line -ForegroundColor Yellow }
        else { Write-Host $line }
    }

    try { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

if ($Success) { exit 0 }
exit 1
