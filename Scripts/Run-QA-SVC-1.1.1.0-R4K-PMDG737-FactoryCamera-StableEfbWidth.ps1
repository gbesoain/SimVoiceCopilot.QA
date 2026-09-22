#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp',
    [string]$EfbProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Require-File([string]$Path) { if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file missing: $Path" } }
function Require-Contains([string]$Text,[string]$Needle,[string]$Label) { if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) { throw "$Label missing: $Needle" } }

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

$t=$null; $e=$null
[System.Management.Automation.Language.Parser]::ParseFile($buildPath,[ref]$t,[ref]$e) | Out-Null
if ($e -and $e.Count -gt 0) { throw ('R4K EFB PowerShell parser gate failed: ' + (($e | ForEach-Object {$_.Message}) -join ' | ')) }

[xml]$v = Get-Content -LiteralPath $versionPath -Raw
if ($v.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion').InnerText.Trim() -ne '1.1.1.0' -or
    $v.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion').InnerText.Trim() -ne '1.1.1.0') { throw 'Windows Version.props must remain exactly 1.1.1.0.' }

$camera=[IO.File]::ReadAllText($cameraPath)
$cameraStore=[IO.File]::ReadAllText($cameraStorePath)
$mcp=[IO.File]::ReadAllText($mcpPath)
$vosk=[IO.File]::ReadAllText($voskPath)
$controller=[IO.File]::ReadAllText($controllerPath)
$efb=[IO.File]::ReadAllText($efbPath)
$style=[IO.File]::ReadAllText($stylePath)
$build=[IO.File]::ReadAllText($buildPath)

foreach ($required in @(
  'SIMVOICE_1_1_1_0_R4K_PMDG737_FACTORY_WALKTHROUGH_CAMERA_MAP',
  'D3AEE769708C68F4AE30055D59ABF6946E5826A599C0A578D1745EC6B45670B7',
  'R4KFactoryWalkthroughHotKeys',
  'pmdg-r4k-factory-walkthrough-exact-native-target-map',
  'pmdg-r4k-current-catalog-not-yet-walked',
  'PMDG737_CAMERA_FACTORY_MAP_MISS',
  'Pmdg737ChecklistCameraCalibrationStore.TryGet'
)) { Require-Contains $camera $required 'R4K PMDG factory camera map' }

$entryCount = ([regex]::Matches($camera, '\{ "native:\d+:\d+", \d \}, // (clicked|inherited):')).Count
if ($entryCount -ne 183) { throw "R4K factory walkthrough map must contain exactly 183 support-derived targets; found $entryCount." }
$clickedCount = ([regex]::Matches($camera, '// clicked:')).Count
$inheritedCount = ([regex]::Matches($camera, '// inherited:')).Count
if ($clickedCount -ne 147 -or $inheritedCount -ne 36) { throw "R4K camera evidence counts mismatch. clicked=$clickedCount inherited=$inheritedCount" }

$learnedIndex=$camera.IndexOf('Pmdg737ChecklistCameraCalibrationStore.TryGet',[StringComparison]::Ordinal)
$factoryIndex=$camera.IndexOf('R4KFactoryWalkthroughHotKeys.TryGetValue',[StringComparison]::Ordinal)
if ($learnedIndex -lt 0 -or $factoryIndex -lt 0 -or $learnedIndex -gt $factoryIndex) { throw 'Local learned correction must retain priority over the R4K factory walkthrough map.' }

foreach ($required in @(
  "const EFB_VERSION = '0.1.124';",
  'SIMVOICE_1_1_1_0_R4K_ACTIVE_CHECKLIST_STABLE_WIDTH',
  'data-simvoice-width-class',
  'data-simvoice-stable-width',
  'geometryChanged || needsFreshFit',
  "actions.style.setProperty('margin-left', '0px', 'important')",
  'current.dataset.simvoiceStableWidth'
)) { Require-Contains $efb $required 'R4K stable EFB width source' }
foreach ($required in @(
  'SIMVOICE_1_1_1_0_R4K_ACTIVE_CHECKLIST_STABLE_WIDTH',
  'data-simvoice-width-class="narrow"',
  'flex-wrap: wrap !important;',
  'word-break: break-word !important;',
  '.sv-checklist-card > .sv-actions-docked'
)) { Require-Contains $style $required 'R4K stable EFB width style' }
Require-Contains $build '$ExpectedEfbVersion = "0.1.124"' 'R4K EFB version build gate'

# Frozen R4J/R4H/R2R functionality must still be present.
foreach ($required in @('Pmdg737CameraMap','camera-map.json','SourceContentHash','CurrentTarget')) { Require-Contains $cameraStore $required 'R4J calibration baseline' }
foreach ($required in @('PMDG737_VS_MODE_PREACTIVATION','EVT_MCP_CRS_L_SET','EVT_MCP_CRS_R_SET')) { Require-Contains $mcp $required 'R4J PMDG MCP baseline' }
foreach ($required in @('ExecutePmdg737McpButtonCommandAsync','CALLOUT_PROTECTION_STALE_IGNORED')) { Require-Contains $vosk $required 'R4J Vosk/MCP baseline' }
Require-Contains $controller 'SIMVOICE_1_1_1_0_R4H_EFB_READY_CATALOG_REUSE' 'R4H ready-catalog baseline'
Require-Contains $controller 'if (!catalogReady)' 'R4H refresh-only-when-not-ready baseline'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R4K FACTORY CAMERA + STABLE EFB WIDTH QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'PMDG camera: 183 QA-walked targets promoted to current-catalog factory map (147 clicked, 36 inherited).'
Write-Host 'PMDG camera: local QA corrections still override factory map; current-catalog unvisited targets fail closed.'
Write-Host 'EFB v0.1.124: measured width is pinned; narrow portrait focus controls wrap; 450ms poll no longer refits unchanged DOM.'
Write-Host 'R4J MCP/Vosk and R4H/R2R checklist catalog behavior retained.'
exit 0
