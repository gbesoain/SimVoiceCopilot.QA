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
        throw ("Missing {0}: {1}" -f $Label, $Path)
    }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing in {1}: {2}" -f $Label, $Path, $Needle)
    }
}

$main = Join-Path $WindowsProjectRoot 'MainForm.cs'

Assert-Contains $main 'SIMVOICE_1_1_1_0_R3C_LEARNED_VERSION_RESTORE' 'R3C marker'
Assert-Contains $main 'CHECKLIST_SESSION_RESTORE_MATCHED_LEARNED_VERSION' 'learned-version match diagnostic'
Assert-Contains $main 'ExtractPersistedChecklistDocumentId' 'saved learned document ID'
Assert-Contains $main 'PersistedChecklistProgressIndexesExist' 'progress SourceIndex safety gate'
Assert-Contains $main 'candidate.LocalLearnedRuntimeSource' 'learned source type gate'
Assert-Contains $main 'candidate.Id ?? string.Empty' 'exact learned document version gate'
Assert-Contains $main 'persisted.GroupIndex' 'saved group index'
Assert-Contains $main 'persisted.ListIndex' 'saved list index'
Assert-Contains $main 'learnedCandidateIds' 'no-match learned evidence'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R3C CHECKLIST RESUME QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
