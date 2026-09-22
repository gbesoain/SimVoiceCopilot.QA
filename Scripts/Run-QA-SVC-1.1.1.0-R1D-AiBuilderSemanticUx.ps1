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

$form = Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs'
$interpreter = Join-Path $WindowsProjectRoot 'LocalAiCommandInterpreter.cs'

Assert-Contains $form 'BuildIntentExamplePlaceholder' 'catalog-backed Builder examples'
Assert-Contains $form 'CanResolveDirectCatalogPhraseForBuilderExample' 'example semantic validation'
Assert-Contains $form 'protected override void OnFormClosing' 'guaranteed X close guard'
Assert-Contains $form 'SIMVOICE_1_1_1_0_R1D_PENDING_CLOSE_GUARD' 'pending-close diagnostic'
Assert-NotContains $form 'FormClosing += AiCommandBuilderForm_FormClosing;' 'obsolete event-only close guard'
Assert-Contains $form 'new RowStyle(SizeType.Absolute, 118F)' 'expanded Proposed plan'
Assert-Contains $form 'LA IA NO RESPONDIÓ A TIEMPO.' 'visible timeout guidance'
Assert-Contains $form 'NO SE PUDO CREAR UN PLAN SEGURO.' 'visible no-safe-plan guidance'

Assert-Contains $interpreter 'SIMVOICE_1_1_1_0_R1D_SEMANTIC_EXISTING_ACTION' 'semantic existing-action marker'
Assert-Contains $interpreter 'TryResolveDirectCatalogSequence' 'deterministic explicit sequence composition'
Assert-Contains $interpreter 'master-semantic-existing-action' 'Master Semantic Catalog direct resolution'
Assert-Contains $interpreter 'CanResolveDirectCatalogPhraseForBuilderExample' 'Builder example resolver contract'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R1D AI BUILDER SEMANTIC UX QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
