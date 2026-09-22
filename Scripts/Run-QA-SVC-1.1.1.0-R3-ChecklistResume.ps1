#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp"
)

$ErrorActionPreference = 'Stop'

function Assert-NotContains {
    param([string]$Path, [string]$Needle, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Missing file for {0}: {1}" -f $Label, $Path)
    }

    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) {
        throw ("{0} unexpectedly found in {1}: {2}" -f $Label, $Path, $Needle)
    }
}

function Assert-Contains {
    param([string]$Path, [string]$Needle, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Missing file for {0}: {1}" -f $Label, $Path)
    }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing in {1}: {2}" -f $Label, $Path, $Needle)
    }
}

$manager = Join-Path $WindowsProjectRoot 'ChecklistSessionManager.cs'
$panel = Join-Path $WindowsProjectRoot 'ChecklistPanel.cs'
$main = Join-Path $WindowsProjectRoot 'MainForm.cs'
$service = Join-Path $WindowsProjectRoot 'ChecklistSessionPersistenceService.cs'

Assert-NotContains $service '\ufeffusing' 'literal Unicode BOM escape'
Assert-Contains $service 'SIMVOICE_1_1_1_0_R3_CHECKLIST_SESSION_RESUME' 'R3 persistence marker'
Assert-Contains $service 'active-session.json' 'active-session bookmark file'
Assert-Contains $service 'TimeSpan.FromHours(24)' 'stale bookmark guard'
Assert-Contains $service 'File.Replace(tempPath, statePath, null);' 'atomic bookmark write'

Assert-Contains $manager 'CapturePersistenceState(' 'session bookmark capture'
Assert-Contains $manager 'public bool Restore(' 'session restore entrypoint'
Assert-Contains $manager 'CompletedSourceIndexes' 'completed item persistence'
Assert-Contains $manager 'SkippedSourceIndexes' 'skipped item persistence'
Assert-Contains $manager 'FindNextPendingActionableIndex' 'pending-item restore fallback'
Assert-Contains $manager 'RaiseStateChanged();' 'restored state publication'

Assert-Contains $panel 'SelectChecklistForRestoredSession' 'exact checklist UI selection restore'

Assert-Contains $main 'PersistOrClearChecklistSessionBookmark(snapshot, "state-changed")' 'bookmark save on checklist transitions'
Assert-Contains $main 'PersistOrClearChecklistSessionBookmark(closingSnapshot, "shutdown")' 'bookmark refresh at shutdown/restart'
Assert-Contains $main 'TryRestorePersistedChecklistSession(' 'catalog restore path'
Assert-Contains $main '"late-native-catalog"' 'late native catalog second restore chance'
Assert-Contains $main 'ChecklistSessionAircraftMatchesForRestore' 'same-aircraft restore guard'
Assert-Contains $main 'checklistSessionPersistenceService.Clear();' 'stale/different-aircraft cleanup'
Assert-Contains $main 'Checklist resumed after restart:' 'resume feedback EN'
Assert-Contains $main 'Checklist reanudada después del reinicio:' 'resume feedback ES'
Assert-Contains $main 'startChecklistAfterScan = false;' 'resume wins over queued fresh start'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R3 CHECKLIST RESUME SOURCE QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
