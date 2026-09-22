#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp',
    [string]$EfbProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-File {
    param([string]$Path,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ("Missing {0}: {1}" -f $Label,$Path) }
}
function Assert-Contains {
    param([string]$Path,[string]$Needle,[string]$Label)
    Assert-File $Path $Label
    $text = [IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle,[StringComparison]::Ordinal) -lt 0) { throw ("{0} missing: {1}" -f $Label,$Needle) }
}
function Assert-NotContains {
    param([string]$Path,[string]$Needle,[string]$Label)
    Assert-File $Path $Label
    $text = [IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle,[StringComparison]::Ordinal) -ge 0) { throw ("{0} unexpectedly contains: {1}" -f $Label,$Needle) }
}
function Get-PackageVersion {
    param([string]$PackageRoot)
    $manifestPath = Join-Path $PackageRoot 'manifest.json'
    Assert-File $manifestPath 'EFB manifest'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($name in @('package_version','packageVersion','version','Version')) {
        $p = $manifest.PSObject.Properties[$name]
        if ($null -ne $p -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)) { return ([string]$p.Value).Trim() }
    }
    return ''
}

$version = Join-Path $WindowsProjectRoot 'Version.props'
$controller = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$sidecar = Join-Path $WindowsProjectRoot 'MarkCompatibilitySidecar.cs'
$app = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$build = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

# Version authority only; PC source bytes are authoritative and are not SHA-gated.
Assert-Contains $version '<SimVoiceVersion>1.1.1.0</SimVoiceVersion>' 'Version.props'
Assert-Contains $version '<AssemblyVersion>$(SimVoiceVersion)</AssemblyVersion>' 'AssemblyVersion authority'

# R2M sidecar: external, verified, fail-closed and data-only.
Assert-Contains $sidecar 'SIMVOICE_1_1_1_0_R2M_MARK_COMPATIBILITY_SIDECAR' 'R2M sidecar marker'
Assert-Contains $sidecar 'mark-compatibility.json' 'R2M mapping authority'
Assert-Contains $sidecar 'entry.Verified' 'R2M verified mapping gate'
Assert-Contains $sidecar 'no-verified-exact-mapping' 'R2M fail-closed decision'
Assert-NotContains $sidecar 'CHECKLIST_START_HELP' 'R2M sidecar START_HELP ban'
Assert-NotContains $sidecar 'Msfs2024EfbChecklistParser' 'R2M parser isolation'
Assert-NotContains $sidecar 'NativeFs2024ChecklistCatalogReceiver' 'R2M catalog isolation'

# Windows integration: sidecar is used by MARK and START_HELP remains disallowed for that decision.
Assert-Contains $controller 'MarkCompatibilitySidecar.Resolve(snapshot, aircraftTitle)' 'R2M MARK resolution'
Assert-Contains $controller 'GUIDED_CHECKLIST_MARK_SIDECAR_DECISION' 'R2M decision diagnostics'
Assert-Contains $controller '["startHelpAllowed"] = false' 'R2M START_HELP fail-closed diagnostic'
Assert-Contains $controller 'markResolution.PartIds' 'R2M PartID path'
Assert-Contains $controller 'markResolution.HtmlIds' 'R2M HtmlID path'

# EFB: 0.1.116 and no dedicated MARK START_HELP helper.
Assert-Contains $app "const EFB_VERSION = '0.1.116';" 'R2M EFB version'
Assert-Contains $app 'SIMVOICE_1_1_1_0_R2M_MARK_NO_START_HELP' 'R2M EFB fail-closed marker'
Assert-NotContains $app 'private async startNativeChecklistMarkHelper' 'Retired MARK START_HELP helper'
Assert-Contains $build '$ExpectedEfbVersion = "0.1.116"' 'R2M build version authority'
Assert-Contains $build 'R2M MARK bundle-text gates: SKIPPED' 'R2M relaxed bundle gate marker'

# Final package versions. No minified-bundle text matching.
foreach ($packageRoot in @(
    (Join-Path $EfbProjectRoot 'Packages\simtech-simvoice-efb'),
    (Join-Path $WindowsProjectRoot 'MSFS\Packages\simtech-simvoice-efb'),
    (Join-Path $WindowsProjectRoot 'Store\Runtime\MSFS\Packages\simtech-simvoice-efb')
)) {
    $actual = Get-PackageVersion $packageRoot
    if ($actual -ne '0.1.116') { throw ("EFB package version mismatch. Expected 0.1.116; actual {0}; root {1}" -f $actual,$packageRoot) }
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2M-R4 MARK COMPATIBILITY SIDECAR QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'PC source bytes are authoritative; QA validates functionality/version, not historical source hashes.' -ForegroundColor Yellow
exit 0
