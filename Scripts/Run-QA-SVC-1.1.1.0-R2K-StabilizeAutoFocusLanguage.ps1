#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp",
    [string]$EfbProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS"
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

function Assert-NotContains {
    param([string]$Path,[string]$Needle,[string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Missing {0}: {1}" -f $Label,$Path)
    }

    $text=[System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle,[System.StringComparison]::Ordinal)-ge 0) {
        throw ("{0} unexpectedly present: {1}" -f $Label,$Needle)
    }
}

$parser2024=Join-Path $WindowsProjectRoot 'Msfs2024EfbChecklistParser.cs'
$resolver=Join-Path $WindowsProjectRoot 'ChecklistPackageVisualHelperResolver.cs'
$main=Join-Path $WindowsProjectRoot 'MainForm.cs'
$builder=Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs'
$app=Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$build=Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

# R2J must be absent from the MSFS2024 parsing/focus path.
Assert-NotContains $parser2024 'SIMVOICE_1_1_1_0_R2J_MSFS2024_VISUAL_METADATA' 'R2J parser instrumentation'
Assert-NotContains $parser2024 'CHECKLIST_MSFS2024_VISUAL_METADATA_PARSED' 'R2J parser diagnostic'
Assert-NotContains $parser2024 'ExtractMsfs2024VisualHelperIds' 'R2J parser visual extraction'
Assert-NotContains $parser2024 'PackageVisualLookupTarget = packageVisualLookupTarget' 'R2J parser lookup mutation'

Assert-NotContains $resolver 'SIMVOICE_1_1_1_0_R2J_MSFS2024_ITEM_LOOKUP' 'R2J Item package resolver'
Assert-NotContains $resolver 'GetVisualNodeKeys' 'R2J Item indexing'
Assert-NotContains $resolver 'BuildMsfs2024ItemLookupKey' 'R2J Item key builder'

# Preserve the known pre-R2J R2I baseline, including the compiler fix.
Assert-Contains $resolver 'SIMVOICE_1_1_1_0_R2I_TT_CHECKPOINT_LOOKUP' 'R2I resolver baseline'
Assert-Contains $resolver 'VisualDefinition definition = null;' 'R2H FIX2 definite assignment'

# Explicitly protect already-approved features.
Assert-Contains $main 'SIMVOICE_1_1_1_0_R3D_RESTORE_LANGUAGE_PRESERVATION' 'R3D Spanish resume'
Assert-Contains $builder 'SIMVOICE_1_1_1_0_R1F_FRIENDLY_DYNAMIC_EXAMPLES' 'R1F Builder examples'
Assert-Contains $builder 'dgvActions.MinimumSize = new Size(0, 0);' 'R1G Builder layout'

Assert-Contains $app "const EFB_VERSION = '0.1.114';" 'EFB 0.1.114'
Assert-Contains $build '$ExpectedEfbVersion = "0.1.114"' 'EFB build 0.1.114'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2K AUTO/FOCUS/LANGUAGE STABILIZATION QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
