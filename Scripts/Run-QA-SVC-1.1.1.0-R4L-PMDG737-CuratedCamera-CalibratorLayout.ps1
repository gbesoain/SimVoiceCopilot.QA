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

$versionPath=Join-Path $WindowsProjectRoot 'Version.props'
$cameraPath=Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs'
$cameraStorePath=Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraCalibrationStore.cs'
$mcpPath=Join-Path $WindowsProjectRoot 'Pmdg737McpCommandService.cs'
$voskPath=Join-Path $WindowsProjectRoot 'VoskRecognizer.cs'
$controllerPath=Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$efbPath=Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$stylePath=Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css'
$buildPath=Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'
@($versionPath,$cameraPath,$cameraStorePath,$mcpPath,$voskPath,$controllerPath,$efbPath,$stylePath,$buildPath)|ForEach-Object{Require-File $_}
$t=$null;$e=$null
[System.Management.Automation.Language.Parser]::ParseFile($buildPath,[ref]$t,[ref]$e)|Out-Null
if($e -and $e.Count -gt 0){throw ('R4L EFB PowerShell parser gate failed: '+(($e|ForEach-Object{$_.Message}) -join ' | '))}
[xml]$v=Get-Content -LiteralPath $versionPath -Raw
if($v.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion').InnerText.Trim() -ne '1.1.1.0' -or $v.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion').InnerText.Trim() -ne '1.1.1.0'){throw 'Windows Version.props must remain exactly 1.1.1.0.'}
$camera=[IO.File]::ReadAllText($cameraPath);$cameraStore=[IO.File]::ReadAllText($cameraStorePath);$mcp=[IO.File]::ReadAllText($mcpPath);$vosk=[IO.File]::ReadAllText($voskPath);$controller=[IO.File]::ReadAllText($controllerPath);$efb=[IO.File]::ReadAllText($efbPath);$style=[IO.File]::ReadAllText($stylePath);$build=[IO.File]::ReadAllText($buildPath)
foreach($required in @(
  'SIMVOICE_1_1_1_0_R4L_PMDG737_FACTORY_CURATED_CAMERA_MAP',
  'D3AEE769708C68F4AE30055D59ABF6946E5826A599C0A578D1745EC6B45670B7',
  'R4LFactoryCuratedHotKeys','R4LCuratedTargetCount = 373','R4LPass2Confirmations = 261',
  'R4LPass2UniqueTargets = 259','R4LPass2ManualPresses = 110','R4LPass2ManualTargets = 62',
  'R4LPass2MultiTrialTargets = 27','pmdg-r4l-factory-curated-exact-native-target-map',
  'Pmdg737ChecklistCameraCalibrationStore.TryGet'
)){Require-Contains $camera $required 'R4L cumulative PMDG factory camera map'}
$entryCount=([regex]::Matches($camera,'\{ "native:\d+:\d+", \d \}, // pass(1|2)-')).Count
if($entryCount -ne 373){throw "R4L cumulative map must contain exactly 373 curated native targets; found $entryCount."}
$learnedIndex=$camera.IndexOf('Pmdg737ChecklistCameraCalibrationStore.TryGet',[StringComparison]::Ordinal)
$factoryIndex=$camera.IndexOf('R4LFactoryCuratedHotKeys.TryGetValue',[StringComparison]::Ordinal)
if($learnedIndex -lt 0 -or $factoryIndex -lt 0 -or $learnedIndex -gt $factoryIndex){throw 'Local QA calibration must retain priority over R4L factory camera map.'}
foreach($required in @("const EFB_VERSION = '0.1.125';",'SIMVOICE_1_1_1_0_R4L_PMDG_CAMERA_CALIBRATION_LAYOUT','sv-current-item-heading-calibrating','sv-current-item-calibrating','CÁMARA QA · Shift+')){Require-Contains $efb $required 'R4L calibration EFB'}
foreach($required in @('SIMVOICE_1_1_1_0_R4L_PMDG_CAMERA_CALIBRATION_LAYOUT','.sv-current-item-heading-calibrating > .sv-focus-controls','grid-template-columns: repeat(5, minmax(0, 1fr)) !important;','grid-template-columns: repeat(10, minmax(0, 1fr)) !important;')){Require-Contains $style $required 'R4L calibration CSS'}
Require-Contains $build '$ExpectedEfbVersion = "0.1.125"' 'R4L EFB build version'
# frozen baselines
foreach($required in @('Pmdg737CameraMap','camera-map.json','SourceContentHash','CurrentTarget')){Require-Contains $cameraStore $required 'R4J calibration store baseline'}
foreach($required in @('PMDG737_VS_MODE_PREACTIVATION','EVT_MCP_CRS_L_SET','EVT_MCP_CRS_R_SET')){Require-Contains $mcp $required 'R4J PMDG MCP baseline'}
foreach($required in @('ExecutePmdg737McpButtonCommandAsync','CALLOUT_PROTECTION_STALE_IGNORED')){Require-Contains $vosk $required 'R4J Vosk/MCP baseline'}
Require-Contains $controller 'SIMVOICE_1_1_1_0_R4H_EFB_READY_CATALOG_REUSE' 'R4H catalog reuse baseline'
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R4L CURATED CAMERA + CALIBRATION LAYOUT QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'Camera: 373 cumulative exact native-target mappings; local QA overrides still win.'
Write-Host 'Pass2: 261 confirmations / 259 unique targets / 110 manual camera presses / 62 manual targets / 27 multi-trial targets.'
Write-Host 'EFB v0.1.125: calibration mode uses a dedicated focus-controls row and 5x2 camera keypad in portrait.'
Write-Host 'Calibration controls intentionally remain visible for additional AUTO curation passes.'
exit 0
