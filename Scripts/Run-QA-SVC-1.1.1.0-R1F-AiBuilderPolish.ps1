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
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing: {1}" -f $Label,$Needle)
    }
}

$form = Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs'

Assert-Contains $form 'new RowStyle(SizeType.Absolute, 52F)' 'action-buttons fixed row'
Assert-Contains $form 'new RowStyle(SizeType.Absolute, 56F)' 'footer fixed row'
Assert-Contains $form 'Padding = new Padding(0, 10, 0, 4)' 'lower-button padding'
Assert-Contains $form 'Math.Min(930, Math.Max(620, working.Height - 16))' 'working-area height'
Assert-Contains $form 'SIMVOICE_1_1_1_0_R1F_FRIENDLY_DYNAMIC_EXAMPLES' 'friendly examples marker'
Assert-Contains $form 'random-friendly-current-catalog-natural-resolver-validated' 'Natural Resolver validation'
Assert-Contains $form 'IsFriendlyBuilderExampleAction' 'technical phrase filter'
Assert-Contains $form 'BuildFriendlySimVarExample' 'pilot-facing SimVar examples'
Assert-Contains $form 'Ejemplos reales de tu catálogo:' 'visible current-catalog explanation'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R1F AI BUILDER POLISH QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
