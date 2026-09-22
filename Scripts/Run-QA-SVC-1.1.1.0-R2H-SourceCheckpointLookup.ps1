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
    $t=[System.IO.File]::ReadAllText($Path)
    if ($t.IndexOf($Needle,[System.StringComparison]::Ordinal)-lt 0) {
        throw ("{0} missing: {1}" -f $Label,$Needle)
    }
}

function Assert-NotContains {
    param([string]$Path,[string]$Needle,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Missing {0}: {1}" -f $Label,$Path)
    }
    $t=[System.IO.File]::ReadAllText($Path)
    if ($t.IndexOf($Needle,[System.StringComparison]::Ordinal)-ge 0) {
        throw ("{0} unexpectedly present: {1}" -f $Label,$Needle)
    }
}

$models=Join-Path $WindowsProjectRoot 'ChecklistModels.cs'
$parser=Join-Path $WindowsProjectRoot 'Msfs2020LegacyChecklistParser.cs'
$resolver=Join-Path $WindowsProjectRoot 'ChecklistPackageVisualHelperResolver.cs'
$learning=Join-Path $WindowsProjectRoot 'ChecklistProcedureLearningService.cs'
$app=Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$build=Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

Assert-Contains $models 'PackageVisualLookupTarget' 'separate package visual lookup identity'
Assert-Contains $models 'PackageVisualLookupTarget = PackageVisualLookupTarget' 'session clone lookup identity'
Assert-Contains $parser 'string inlineCheckpointId' 'inline Checkpoint Id capture'
Assert-Contains $parser 'PackageVisualLookupTarget = packageVisualLookupTarget' 'parser lookup identity assignment'
Assert-Contains $resolver 'SIMVOICE_1_1_1_0_R2G_PACKAGE_XML_VISUAL_RESOLVER' 'R2G package resolver retained'
Assert-Contains $resolver 'VisualDefinition definition = null;' 'R2H FIX2 definite-assignment guard'
Assert-NotContains $resolver 'VisualDefinition definition;' 'obsolete uninitialized local'
Assert-Contains $learning 'donorItem.PackageVisualLookupTarget' 'R2H resolver entry key'
Assert-Contains $learning 'SIMVOICE_1_1_1_0_R2H_SOURCE_CHECKPOINT_LOOKUP' 'R2H runtime marker'
Assert-Contains $learning 'r2hLookupAttempts' 'R2H resolver attempt diagnostic'
Assert-Contains $learning 'r2hLookupResolved' 'R2H resolver resolved diagnostic'
Assert-Contains $learning 'packageVisualLookupTarget' 'learned lookup-key persistence'
Assert-Contains $app "const EFB_VERSION = '0.1.111';" 'EFB 0.1.111'
Assert-Contains $build '$ExpectedEfbVersion = "0.1.111"' 'EFB build 0.1.111'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2H SOURCE CHECKPOINT LOOKUP FIX2 QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
