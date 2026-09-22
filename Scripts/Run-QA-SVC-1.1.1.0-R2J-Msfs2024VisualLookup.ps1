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
$learning=Join-Path $WindowsProjectRoot 'ChecklistProcedureLearningService.cs'
$app=Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$build=Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

# Installed R2H/R2I baseline remains present.
Assert-Contains $learning 'SIMVOICE_1_1_1_0_R2H_SOURCE_CHECKPOINT_LOOKUP' 'R2H learning baseline'
Assert-Contains $resolver 'SIMVOICE_1_1_1_0_R2I_TT_CHECKPOINT_LOOKUP' 'R2I resolver baseline'
Assert-Contains $resolver 'VisualDefinition definition = null;' 'R2H FIX2 compiler guard'
Assert-NotContains $resolver 'VisualDefinition definition;' 'obsolete CS0165 declaration'

# R2J must patch the actual MSFS 2024 EFB parser.
Assert-Contains $parser2024 'using System.Collections.Generic;' 'R2J FIX1 generic collections import'
Assert-Contains $parser2024 'PackageVisualLookupTarget = packageVisualLookupTarget' 'MSFS2024 item lookup key'
Assert-Contains $parser2024 'ExtractMsfs2024VisualHelperIds(element, item);' 'MSFS2024 direct visual metadata extraction'
Assert-Contains $parser2024 'BuildMsfs2024ItemLookupKey' 'MSFS2024 exact content lookup'
Assert-Contains $parser2024 'CHECKLIST_MSFS2024_VISUAL_METADATA_PARSED' 'MSFS2024 parser diagnostic'
Assert-Contains $parser2024 'SIMVOICE_1_1_1_0_R2J_MSFS2024_VISUAL_METADATA' 'R2J parser marker'

# Package resolver must now index Item as well as Checkpoint.
Assert-Contains $resolver 'GetVisualNodeKeys' 'generic visual node key resolver'
Assert-Contains $resolver '"Item"' 'MSFS2024 Item package indexing'
Assert-Contains $resolver 'BuildMsfs2024ItemLookupKey' 'matching MSFS2024 content key'
Assert-Contains $resolver 'SIMVOICE_1_1_1_0_R2J_MSFS2024_ITEM_LOOKUP' 'R2J resolver marker'

Assert-Contains $app "const EFB_VERSION = '0.1.113';" 'EFB 0.1.113'
Assert-Contains $build '$ExpectedEfbVersion = "0.1.113"' 'EFB build 0.1.113'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2J MSFS2024 VISUAL LOOKUP FIX1 QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
