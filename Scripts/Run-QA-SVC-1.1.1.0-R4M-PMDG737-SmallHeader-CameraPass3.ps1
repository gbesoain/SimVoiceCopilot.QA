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

$versionPath = Join-Path $WindowsProjectRoot 'Version.props'
$cameraPath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs'
$cameraStorePath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraCalibrationStore.cs'
$mcpPath = Join-Path $WindowsProjectRoot 'Pmdg737McpCommandService.cs'
$voskPath = Join-Path $WindowsProjectRoot 'VoskRecognizer.cs'
$controllerPath = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$efbPath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$stylePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css'
$buildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'
@($versionPath,$cameraPath,$cameraStorePath,$mcpPath,$voskPath,$controllerPath,$efbPath,$stylePath,$buildPath) | ForEach-Object { Require-File $_ }

$t=$null;$e=$null
[System.Management.Automation.Language.Parser]::ParseFile($buildPath,[ref]$t,[ref]$e) | Out-Null
if ($e -and $e.Count -gt 0) { throw ('R4M EFB PowerShell parser gate failed: ' + (($e | ForEach-Object {$_.Message}) -join ' | ')) }

[xml]$v = Get-Content -LiteralPath $versionPath -Raw
if ($v.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion').InnerText.Trim() -ne '1.1.1.0' -or
    $v.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion').InnerText.Trim() -ne '1.1.1.0') {
    throw 'Windows Version.props must remain exactly 1.1.1.0.'
}

$camera=[IO.File]::ReadAllText($cameraPath)
$cameraStore=[IO.File]::ReadAllText($cameraStorePath)
$mcp=[IO.File]::ReadAllText($mcpPath)
$vosk=[IO.File]::ReadAllText($voskPath)
$controller=[IO.File]::ReadAllText($controllerPath)
$efb=[IO.File]::ReadAllText($efbPath)
$style=[IO.File]::ReadAllText($stylePath)
$build=[IO.File]::ReadAllText($buildPath)

foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4M_PMDG737_FACTORY_CURATED_CAMERA_MAP',
    'R4MFactoryPass3Overrides',
    'R4MCuratedTargetCount = 373',
    'R4MPass3Confirmations = 529',
    'R4MPass3UniqueTargets = 353',
    'R4MPass3ManualPressesCommitted = 195',
    'R4MPass3ManualTargets = 99',
    'R4MPass3MultiTrialTargets = 41',
    'R4MPass3Corrections = 21',
    'pmdg-r4m-factory-pass3-exact-native-target-map',
    'pmdg-r4m-factory-curated-exact-native-target-map',
    'Pmdg737ChecklistCameraCalibrationStore.TryGet'
)) { Require-Contains $camera $required 'R4M PMDG camera curation' }

$overrideStart=$camera.IndexOf('private static readonly Dictionary<string, int> R4MFactoryPass3Overrides',[StringComparison]::Ordinal)
$resolveStart=$camera.IndexOf('public static bool IsCurrentAircraftPmdg737',[StringComparison]::Ordinal)
if ($overrideStart -lt 0 -or $resolveStart -le $overrideStart) { throw 'R4M pass3 overlay block bounds invalid.' }
$overlayText=$camera.Substring($overrideStart,$resolveStart-$overrideStart)
$overlayCount=([regex]::Matches($overlayText,'\{ "native:\d+:\d+", \d \}, // pass3-')).Count
if ($overlayCount -ne 21) { throw "R4M pass3 overlay must contain exactly 21 camera corrections; found $overlayCount." }

$learnedIndex=$camera.IndexOf('Pmdg737ChecklistCameraCalibrationStore.TryGet',[StringComparison]::Ordinal)
$r4mIndex=$camera.IndexOf('R4MFactoryPass3Overrides.TryGetValue',[StringComparison]::Ordinal)
$r4lIndex=$camera.IndexOf('R4LFactoryCuratedHotKeys.TryGetValue',[StringComparison]::Ordinal)
if ($learnedIndex -lt 0 -or $r4mIndex -lt 0 -or $r4lIndex -lt 0 -or
    $learnedIndex -gt $r4mIndex -or $r4mIndex -gt $r4lIndex) {
    throw 'Camera priority must be local QA override > R4M pass3 correction > R4L cumulative factory map.'
}

foreach ($required in @(
    "const EFB_VERSION = '0.1.126';",
    'SIMVOICE_1_1_1_0_R4M_PMDG_SMALL_FOCUS_HEADER_ALIGNMENT',
    'data-simvoice-size',
    "const sizeClass = width <= 520 ? 'small'",
    'SIMVOICE_1_1_1_0_R4L_PMDG_CAMERA_CALIBRATION_LAYOUT',
    'CÁMARA QA · Shift+'
)) { Require-Contains $efb $required 'R4M EFB SMALL/calibration' }

foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4M_PMDG_SMALL_FOCUS_HEADER_ALIGNMENT',
    '.simvoice-copilot-root[data-simvoice-size="small"] .sv-current-item-heading',
    'grid-template-columns: minmax(0, 1fr) auto !important;',
    'justify-self: end !important;',
    'height: 19px !important;',
    'SIMVOICE_1_1_1_0_R4L_PMDG_CAMERA_CALIBRATION_LAYOUT'
)) { Require-Contains $style $required 'R4M SMALL header CSS' }

Require-Contains $build '$ExpectedEfbVersion = "0.1.126"' 'R4M EFB build version'
Require-Contains $build 'R4M SMALL current-item header alignment source semantics: PASS' 'R4M EFB build semantic gate'

# Frozen baselines from R4J/R4H.
foreach ($required in @('Pmdg737CameraMap','camera-map.json','SourceContentHash','CurrentTarget')) { Require-Contains $cameraStore $required 'R4J calibration store baseline' }
foreach ($required in @('PMDG737_VS_MODE_PREACTIVATION','EVT_MCP_CRS_L_SET','EVT_MCP_CRS_R_SET')) { Require-Contains $mcp $required 'R4J PMDG MCP baseline' }
foreach ($required in @('ExecutePmdg737McpButtonCommandAsync','CALLOUT_PROTECTION_STALE_IGNORED')) { Require-Contains $vosk $required 'R4J Vosk/MCP baseline' }
Require-Contains $controller 'SIMVOICE_1_1_1_0_R4H_EFB_READY_CATALOG_REUSE' 'R4H catalog reuse baseline'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R4M SMALL HEADER + CAMERA PASS3 QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'Camera: 353/373 factory targets revalidated in pass3; 21 corrections promoted; local QA overrides still win.'
Write-Host 'Pass3: 529 confirmations; 195 committed camera presses; 99 manually touched targets; 41 targets had multiple trials.'
Write-Host 'EFB v0.1.126: SMALL places AUTO/MARK/FOCUS at the right of the ELEMENTO ACTUAL header line.'
Write-Host 'Camera calibration controls intentionally remain visible for more curation passes.'
exit 0
