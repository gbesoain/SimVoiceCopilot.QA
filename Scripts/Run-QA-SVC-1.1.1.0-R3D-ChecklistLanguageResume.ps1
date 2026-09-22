#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Path,[string]$Needle,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Missing {0}: {1}" -f $Label,$Path)
    }
    $text=[System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle,[System.StringComparison]::Ordinal)-lt 0) {
        throw ("{0} missing: {1}" -f $Label,$Needle)
    }
}

$main = Join-Path $WindowsProjectRoot 'MainForm.cs'
Assert-Contains $main 'SIMVOICE_1_1_1_0_R3C_LEARNED_VERSION_RESTORE' 'R3C restore baseline'
Assert-Contains $main 'TryApplyCachedChecklistTranslationForRestore' 'restore translation helper'
Assert-Contains $main 'CHECKLIST_SESSION_RESTORE_TRANSLATION_CACHE_HIT' 'Spanish restore cache hit diagnostic'
Assert-Contains $main 'SIMVOICE_1_1_1_0_R3D_RESTORE_LANGUAGE_PRESERVATION' 'R3D marker'
Assert-Contains $main 'localizedRestoreProjectionApplied' 'localized restore state'
Assert-Contains $main 'translatedBySourceIndex' 'item translation overlay by stable SourceIndex'
Assert-Contains $main 'localizedRestoreProjection' 'restored diagnostic language evidence'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R3D CHECKLIST LANGUAGE RESUME QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
