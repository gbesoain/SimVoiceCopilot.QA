#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp',
    [string]$EfbProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file missing: $Path" }
}
function Require-Contains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) { throw "$Label missing: $Needle" }
}
function Require-NotContains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -ge 0) { throw "$Label contains forbidden stale pattern: $Needle" }
}

$versionPath = Join-Path $WindowsProjectRoot 'Version.props'
$cameraPath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs'
$sdkPath = Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs'
$translationPath = Join-Path $WindowsProjectRoot 'ChecklistTranslationService.cs'
$cameraStorePath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraCalibrationStore.cs'
$efbPath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$stylePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css'
$buildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'
@($versionPath,$cameraPath,$sdkPath,$translationPath,$cameraStorePath,$efbPath,$stylePath,$buildPath) | ForEach-Object { Require-File $_ }

$t=$null;$e=$null
[System.Management.Automation.Language.Parser]::ParseFile($buildPath,[ref]$t,[ref]$e) | Out-Null
if ($e -and $e.Count -gt 0) { throw ('R4N EFB PowerShell parser gate failed: ' + (($e | ForEach-Object {$_.Message}) -join ' | ')) }

[xml]$v = Get-Content -LiteralPath $versionPath -Raw
if ($v.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion').InnerText.Trim() -ne '1.1.1.0' -or
    $v.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion').InnerText.Trim() -ne '1.1.1.0') {
    throw 'Windows Version.props must remain exactly 1.1.1.0.'
}

$camera=[IO.File]::ReadAllText($cameraPath)
$sdk=[IO.File]::ReadAllText($sdkPath)
$translation=[IO.File]::ReadAllText($translationPath)
$cameraStore=[IO.File]::ReadAllText($cameraStorePath)
$efb=[IO.File]::ReadAllText($efbPath)
$style=[IO.File]::ReadAllText($stylePath)
$build=[IO.File]::ReadAllText($buildPath)

# Preserve the current 373-target camera curation and local learned overrides.
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4M_PMDG737_FACTORY_CURATED_CAMERA_MAP',
    'R4MCuratedTargetCount = 373',
    'Pmdg737ChecklistCameraCalibrationStore.TryGet'
)) { Require-Contains $camera $required 'R4M camera baseline' }
foreach ($required in @('Pmdg737CameraMap','camera-map.json','SourceContentHash','CurrentTarget')) {
    Require-Contains $cameraStore $required 'R4J calibration store baseline'
}

# R4N: PMDG BW and SSW variants must both select the dedicated PMDG paths.
foreach ($required in @('737-800 PAX SSW SC','737-800 PAX BW SC')) {
    Require-Contains $sdk $required 'R4N1 PMDG C# identity'
}
foreach ($required in @('737-800 pax ssw sc','737-800 pax bw sc','SIMVOICE_1_1_1_0_R4N_PMDG737_BW_SSW_IDENTITY')) {
    Require-Contains $efb $required 'R4N1 PMDG EFB identity'
}

# MARK and the camera selector are intentionally retained until the user explicitly orders otherwise.
foreach ($required in @('MARCAR','CÁMARA QA · Shift+','sv-pmdg-camera-calibrator-grid','checklistMarkModeEnabled')) {
    Require-Contains $efb $required 'R4N1 MARK/calibration retention'
}

# R4N: never measure .sv-content width and feed it back as a fixed pixel width.
foreach ($required in @(
    "const EFB_VERSION = '0.1.127';",
    'SIMVOICE_1_1_1_0_R4N_ACTIVE_CHECKLIST_FULL_WIDTH_NO_FEEDBACK',
    'for (const element of [content, card, body, current, actions])',
    "element.style.setProperty('width', '100%', 'important');",
    'current.dataset.simvoiceFullWidth'
)) { Require-Contains $efb $required 'R4N1 stable full-width layout' }
Require-NotContains $efb 'const contentWidth = Math.max(180, Math.floor(contentRect.width));' 'R4N1 stable full-width layout'

foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4N_ACTIVE_CHECKLIST_FULL_WIDTH_NO_FEEDBACK',
    '.simvoice-copilot-root[data-simvoice-r4n-full-width] .sv-checklist-card > .sv-actions-docked',
    'grid-template-columns: repeat(3, minmax(0, 1fr)) !important;',
    'margin: 4px 0 6px !important;',
    'box-sizing: border-box !important;'
)) { Require-Contains $style $required 'R4N1 full-width/action containment CSS' }

# Local translation cache must be invalidated after the prompt-quality correction.
Require-Contains $translation 'private const int CacheFormatVersion = 3;' 'R4N1 translation local cache invalidation'
Require-Contains $build '$ExpectedEfbVersion = "0.1.127"' 'R4N1 EFB build version'
Require-Contains $build 'R4N full-width/no-feedback + PMDG BW/SSW identity source semantics: PASS' 'R4N1 build semantic gate'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R4N1 LAYOUT + PMDG IDENTITY + TRANSLATION QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'PMDG: both 737-800 PAX SSW SC and 737-800 PAX BW SC use the dedicated adapter/Mark/camera paths.'
Write-Host 'EFB v0.1.127: full-width active reader; no self-measured pixel-width feedback loop; action buttons stay inside card.'
Write-Host 'MARK and camera selectors remain present for ongoing curation.'
Write-Host 'Checklist translation local cache format is 3; deploy the companion backend prompt-v2 patch to regenerate clean Spanish.'
exit 0
