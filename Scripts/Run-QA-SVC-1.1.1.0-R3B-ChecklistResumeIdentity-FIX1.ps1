#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

$main = Join-Path $WindowsProjectRoot 'MainForm.cs'
$service = Join-Path $WindowsProjectRoot 'ChecklistSessionPersistenceService.cs'

Assert-Contains $service 'SIMVOICE_1_1_1_0_R3_CHECKLIST_SESSION_RESUME' 'R3 persistence baseline'
$manager = Join-Path $WindowsProjectRoot 'ChecklistSessionManager.cs'
$panel = Join-Path $WindowsProjectRoot 'ChecklistPanel.cs'
Assert-Contains $manager 'public sealed class ChecklistSessionManager' 'R3 checklist session manager'
Assert-Contains $panel 'ChecklistSessionManager' 'R3 checklist panel integration'
Assert-Contains $main 'SIMVOICE_1_1_1_0_R3B_CHECKLIST_RESUME_IDENTITY' 'R3B identity marker'
Assert-Contains $main 'CHECKLIST_SESSION_RESTORE_ATTEMPT' 'restore attempt diagnostic'
Assert-Contains $main 'CHECKLIST_SESSION_RESTORE_NO_MATCH' 'restore no-match diagnostic'
Assert-Contains $main 'CHECKLIST_SESSION_RESTORE_MATCHED_FALLBACK' 'stable identity fallback diagnostic'
Assert-Contains $main 'CloneChecklistPersistenceStateForResolvedSource' 'manager-safe resolved identity clone'
Assert-Contains $main 'candidate.ContentHash' 'same-content-hash fallback'
Assert-Contains $main 'SourceStructureFingerprint' 'same-structure gate'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R3B CHECKLIST RESUME IDENTITY QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
