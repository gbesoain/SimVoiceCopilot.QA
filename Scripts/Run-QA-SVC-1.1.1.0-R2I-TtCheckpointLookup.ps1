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

$parser=Join-Path $WindowsProjectRoot 'Msfs2020LegacyChecklistParser.cs'
$resolver=Join-Path $WindowsProjectRoot 'ChecklistPackageVisualHelperResolver.cs'
$learning=Join-Path $WindowsProjectRoot 'ChecklistProcedureLearningService.cs'
$app=Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$build=Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

# R2H/R2G baseline retained.
Assert-Contains $learning 'SIMVOICE_1_1_1_0_R2H_SOURCE_CHECKPOINT_LOOKUP' 'R2H lookup baseline'
Assert-Contains $resolver 'SIMVOICE_1_1_1_0_R2G_PACKAGE_XML_VISUAL_RESOLVER' 'R2G package resolver baseline'
Assert-Contains $resolver 'VisualDefinition definition = null;' 'R2H FIX2 definite assignment'
Assert-NotContains $resolver 'VisualDefinition definition;' 'obsolete CS0165 declaration'

# R2I exact TT fallback.
Assert-Contains $parser 'BuildCheckpointDescriptionLookupKey' 'parser TT lookup key'
Assert-Contains $parser 'packageVisualLookupTarget =' 'parser lookup assignment'
Assert-Contains $parser '"tt:" + subject + "|" + expectation' 'parser exact TT composite'

Assert-Contains $resolver 'GetAttributeByNormalizedName' 'resolver TT attribute extraction'
Assert-Contains $resolver 'checkpoint-description-tt' 'resolver TT lookup classification'
Assert-Contains $resolver 'SIMVOICE_1_1_1_0_R2I_TT_CHECKPOINT_LOOKUP' 'R2I runtime marker'
Assert-Contains $resolver '"tt:" + subject + "|" + expectation' 'resolver exact TT composite'

Assert-Contains $app "const EFB_VERSION = '0.1.112';" 'EFB 0.1.112'
Assert-Contains $build '$ExpectedEfbVersion = "0.1.112"' 'EFB build 0.1.112'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2I TT CHECKPOINT LOOKUP QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
