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
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -ge 0) { throw "$Label unexpectedly contains: $Needle" }
}

$versionPath = Join-Path $WindowsProjectRoot 'Version.props'
$cameraPath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs'
$cameraStorePath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraCalibrationStore.cs'
$controllerPath = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$sdkPath = Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs'
$mcpPath = Join-Path $WindowsProjectRoot 'Pmdg737McpCommandService.cs'
$voskPath = Join-Path $WindowsProjectRoot 'VoskRecognizer.cs'
$efbUiPath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$efbStylePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css'
$efbBuildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

@($versionPath,$cameraPath,$cameraStorePath,$controllerPath,$sdkPath,$mcpPath,$voskPath,$efbUiPath,$efbStylePath,$efbBuildPath) |
    ForEach-Object { Require-File $_ }

$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($efbBuildPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw ('R4J EFB PowerShell parser gate failed: ' + (($errors | ForEach-Object {$_.Message}) -join ' | '))
}

[xml]$versionXml = Get-Content -LiteralPath $versionPath -Raw
$versionNode = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
$displayNode = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion')
if ($null -eq $versionNode -or $null -eq $displayNode -or
    $versionNode.InnerText.Trim() -ne '1.1.1.0' -or $displayNode.InnerText.Trim() -ne '1.1.1.0') {
    throw 'Windows Version.props must remain exactly 1.1.1.0.'
}

$camera = Get-Content -LiteralPath $cameraPath -Raw
$cameraStore = Get-Content -LiteralPath $cameraStorePath -Raw
$controller = Get-Content -LiteralPath $controllerPath -Raw
$sdk = Get-Content -LiteralPath $sdkPath -Raw
$mcp = Get-Content -LiteralPath $mcpPath -Raw
$vosk = Get-Content -LiteralPath $voskPath -Raw
$efb = Get-Content -LiteralPath $efbUiPath -Raw
$style = Get-Content -LiteralPath $efbStylePath -Raw
$efbBuild = Get-Content -LiteralPath $efbBuildPath -Raw

# R4I frozen camera transport and static seed map remain available, but R4J
# learned exact entries have absolute priority and are scoped by content identity.
Require-Contains $camera 'SIMVOICE_1_1_1_0_R4I_PMDG737_EXACT_TARGET_CAMERA_MAP' 'R4I seed camera baseline'
Require-Contains $camera 'Pmdg737ChecklistCameraCalibrationStore.TryGet' 'R4J learned camera priority'
Require-Contains $camera 'pmdg-r4j-learned-exact-native-target-map' 'R4J learned camera resolution source'
Require-Contains $camera 'pmdg-r4i-seed-exact-native-target-map' 'R4I seed fallback source'
$learnedIndex = $camera.IndexOf('Pmdg737ChecklistCameraCalibrationStore.TryGet',[System.StringComparison]::Ordinal)
$seedIndex = $camera.IndexOf('ExactNativeTargetHotKeys.TryGetValue',[System.StringComparison]::Ordinal)
if ($learnedIndex -lt 0 -or $seedIndex -lt 0 -or $learnedIndex -gt $seedIndex) {
    throw 'R4J camera priority gate failed: learned exact mapping must be checked before the shipped R4I seed map.'
}
Require-Contains $cameraStore 'SIMVOICE_1_1_1_0_R4J_PMDG737_LEARNED_EXACT_CAMERA_MAP' 'R4J calibration-store marker'
Require-Contains $cameraStore 'Pmdg737CameraMap' 'R4J calibration-store LocalAppData folder'
Require-Contains $cameraStore 'camera-map.json' 'R4J calibration-store file'
Require-Contains $cameraStore 'SourceContentHash' 'R4J content-hash scope'
Require-Contains $cameraStore 'SourceStructureFingerprint' 'R4J structure-fingerprint fallback'
Require-Contains $cameraStore 'CurrentTarget' 'R4J exact native target scope'
Require-Contains $cameraStore 'File.Replace' 'R4J atomic calibration persistence'
Require-Contains $controller 'case "checklist.camera.pmdg.calibrate"' 'R4J EFB calibration action'
Require-Contains $controller 'Pmdg737ChecklistCameraCalibrationStore.Save' 'R4J calibration save route'
Require-Contains $controller 'pmdg-checklist-camera-calibration-preview' 'R4J Shift+n preview route'
Require-Contains $controller 'SimVoiceAhkInputBridge.TryQueue' 'R4J AHK preview transport'

# PMDG MCP dedicated SDK: buttons use native PMDG event IDs plus a complete
# MOUSE_FLAG_LEFTSINGLE click. COURSE and V/S values use direct setters/readback.
foreach ($required in @(
    'MouseFlagLeftSingle = 0x20000000',
    'EvtMcpN1Switch = 70013',
    'EvtMcpSpeedSwitch = 70014',
    'EvtMcpVnavSwitch = 70018',
    'EvtMcpLvlChgSwitch = 70023',
    'EvtMcpAppSwitch = 70025',
    'EvtMcpAltHoldSwitch = 70026',
    'EvtMcpVsSwitch = 70027',
    'EvtMcpVorLocSwitch = 70028',
    'EvtMcpLnavSwitch = 70029',
    'EvtMcpCourseLeftSet = ThirdPartyEventIdMin + 14500',
    'EvtMcpCourseRightSet = ThirdPartyEventIdMin + 14501',
    'EvtMcpVerticalSpeedSet = ThirdPartyEventIdMin + 14506'
)) { Require-Contains $sdk $required 'R4J PMDG SDK constants' }

foreach ($required in @(
    'IsModeButtonAction',
    'PressModeButtonAsync',
    'pmdg-ng3-mouse-leftsingle',
    'PMDG737_MCP_BUTTON_PRESS',
    'VOR1_SET',
    'EVT_MCP_CRS_L_SET',
    'VOR2_SET',
    'EVT_MCP_CRS_R_SET',
    'PMDG737_VS_MODE_PREACTIVATION',
    'McpVerticalSpeedWindowLvar',
    'before.Value <= -19000.0'
)) { Require-Contains $mcp $required 'R4J PMDG MCP service' }

# Voice integration: intercept PMDG mode buttons before generic SendCommand,
# add direct COURSE vocabulary, and ignore stale callout-protection evidence.
foreach ($required in @(
    'Pmdg737McpCommandService.IsModeButtonAction(action)',
    'ExecutePmdg737McpButtonCommandAsync',
    'activar n1',
    'activar speed',
    'activar vnav',
    'activar lnav',
    'activar cambio de nivel',
    'activar vor loc',
    'activar app',
    'activar alt hold',
    'activar velocidad vertical',
    'establecer curso',
    'establecer curso izquierdo',
    'establecer curso derecho',
    'HasCalloutProtectionTopicOverlap',
    'CALLOUT_PROTECTION_STALE_IGNORED'
)) { Require-Contains $vosk $required 'R4J Vosk/voice integration' }
Require-NotContains $vosk 'Reset(parameterizedRecognizer)' 'R4J stale-evidence fix must not reset native Vosk recognizer'

# R4J EFB: active reader receives a measured pixel budget, camera calibration is
# exposed only with PMDG MARK active, and prepared selection anchors upper-third.
foreach ($required in @(
    "const EFB_VERSION = '0.1.123';",
    'SIMVOICE_1_1_1_0_R4J_ACTIVE_CHECKLIST_PIXEL_FIT',
    'fitActiveChecklistReaderToContainer',
    "card.style.setProperty('height'",
    "current.style.setProperty('height'",
    'readerHeight',
    'SIMVOICE_1_1_1_0_R4J_PMDG_LEARNED_EXACT_CAMERA_MAP',
    "this.checklistMarkModeEnabled &&",
    "this.transport.sendAction('checklist.camera.pmdg.calibrate'",
    'SIMVOICE_1_1_1_0_R4J_PREPARED_SELECTION_UPPER_THIRD',
    'body.clientHeight * 0.30'
)) { Require-Contains $efb $required 'R4J EFB source' }
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4J_ACTIVE_CHECKLIST_PIXEL_FIT',
    '.sv-pmdg-camera-calibrator-grid',
    'grid-template-columns: repeat(10, minmax(0, 1fr));',
    '.sv-pmdg-camera-key'
)) { Require-Contains $style $required 'R4J EFB style' }

Require-Contains $efbBuild '$ExpectedEfbVersion = "0.1.123"' 'R4J EFB build version'
Require-Contains $efbBuild 'R4J pixel-measured reader + PMDG learned camera map + prepared-row anchor source semantics: PASS' 'R4J EFB build semantic gate'

# R2R/R4H ready-catalog reuse must remain intact and normal EFB tab navigation
# must not force a rescan while the catalog is already ready.
Require-Contains $controller 'SIMVOICE_1_1_1_0_R4H_EFB_READY_CATALOG_REUSE' 'R4H ready-catalog baseline'
Require-Contains $controller 'if (!catalogReady)' 'R4H refresh-only-when-not-ready gate'
Require-NotContains $controller 'if (resetToSelection || !catalogReady)' 'forced checklist refresh regression'
Require-Contains $controller 'SIMVOICE_1_1_1_0_R2R_EFB_SELECTOR_SELF_HEAL' 'R2R self-heal retained'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R4J PMDG LEARNED CAMERA + MCP + EFB/VOSK QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'EFB: active checklist reader is fitted with measured pixel heights; v0.1.123.'
Write-Host 'PMDG camera: MARK exposes 1..0 calibration; learned SourceContentHash+CurrentTarget mapping overrides seed map.'
Write-Host 'PMDG MCP: N1/SPEED/VNAV/LNAV/LVL CHG/VORLOC/APP/ALT HLD/V/S use PMDG SDK button events.'
Write-Host 'PMDG values: COURSE L/R direct-set+ngx readback; V/S activates mode before setter when window is inactive.'
Write-Host 'Voice: stale callout-protection evidence is ignored by topic without resetting the native Vosk recognizer.'
Write-Host 'Checklist selector: prepared row is deliberately anchored near the upper third once.'
exit 0
