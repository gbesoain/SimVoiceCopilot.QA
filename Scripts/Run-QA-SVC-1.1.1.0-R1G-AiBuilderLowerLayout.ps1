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
    $t=[System.IO.File]::ReadAllText($Path)
    if ($t.IndexOf($Needle,[System.StringComparison]::Ordinal)-lt 0) {
        throw ("{0} missing: {1}" -f $Label,$Needle)
    }
}

function Assert-NotContains {
    param([string]$Path,[string]$Needle,[string]$Label)
    $t=[System.IO.File]::ReadAllText($Path)
    if ($t.IndexOf($Needle,[System.StringComparison]::Ordinal)-ge 0) {
        throw ("{0} unexpectedly present: {1}" -f $Label,$Needle)
    }
}

$form=Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs'
Assert-Contains $form 'SIMVOICE_1_1_1_0_R1F_FRIENDLY_DYNAMIC_EXAMPLES' 'R1F examples baseline'
Assert-Contains $form 'new RowStyle(SizeType.Absolute, 172F)' 'R1G action-grid row'
Assert-Contains $form 'dgvActions.MinimumSize = new Size(0, 0);' 'R1G no grid spill'
Assert-Contains $form 'dgvActions.Margin = new Padding(0, 0, 0, 6);' 'R1G grid/button separation'
Assert-Contains $form 'new RowStyle(SizeType.Absolute, 58F)' 'R1G action-button band'
Assert-Contains $form 'new RowStyle(SizeType.Absolute, 62F)' 'R1G footer band'
Assert-Contains $form 'Math.Min(970, Math.Max(620, working.Height - 12))' 'R1G working-height usage'
Assert-NotContains $form 'dgvActions.MinimumSize = new Size(0, 160);' 'obsolete grid overflow cause'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R1G AI BUILDER LOWER LAYOUT QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
