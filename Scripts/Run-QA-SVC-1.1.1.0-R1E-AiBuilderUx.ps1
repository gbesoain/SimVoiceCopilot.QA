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

$form = Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs'

Assert-Contains $form 'new RowStyle(SizeType.Absolute, 96F)' 'compact Proposed plan row'
Assert-Contains $form 'new RowStyle(SizeType.Absolute, 42F)' 'compact Action plan help row'
Assert-Contains $form 'Math.Min(900, Math.Max(620, working.Height - 24))' '900px working-area layout'
Assert-Contains $form 'SIMVOICE_1_1_1_0_R1E_DYNAMIC_CATALOG_EXAMPLES' 'dynamic examples marker'
Assert-Contains $form 'random-current-catalog-natural-resolver-validated' 'Natural Resolver example strategy'
Assert-Contains $form 'active-user-keyboard-command' 'user keyboard catalog source'
Assert-Contains $form 'readSimVarItems' 'SimVar catalog examples'
Assert-Contains $form 'BuildIntentExamplePlaceholder(' 'placeholder refresh'
Assert-Contains $form '«Cuando...» aún no es automático' 'compact failure guidance'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R1E AI BUILDER UX QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
