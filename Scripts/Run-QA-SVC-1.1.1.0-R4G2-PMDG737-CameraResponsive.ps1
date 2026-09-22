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
$servicePath = Join-Path $WindowsProjectRoot 'AutopilotAltitudeService.cs'
$altAdapterPath = Join-Path $WindowsProjectRoot 'Pmdg737AltitudeAdapter.cs'
$sdkPath = Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs'
$mcpPath = Join-Path $WindowsProjectRoot 'Pmdg737McpCommandService.cs'
$cameraPath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs'
$ahkBridgePath = Join-Path $WindowsProjectRoot 'SimVoiceAhkInputBridge.cs'
$controllerPath = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$voskPath = Join-Path $WindowsProjectRoot 'VoskRecognizer.cs'
$efbUiPath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$efbStylePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css'
$efbWrapperStylePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\TemplateApp.scss'
$efbBuildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

@($versionPath,$servicePath,$altAdapterPath,$sdkPath,$mcpPath,$cameraPath,$ahkBridgePath,$controllerPath,$voskPath,$efbUiPath,$efbStylePath,$efbWrapperStylePath,$efbBuildPath) | ForEach-Object { Require-File $_ }

# R4G2 delivery gate: the EFB build script itself must parse under Windows PowerShell 5.1.
$psTokens = $null
$psErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($efbBuildPath,[ref]$psTokens,[ref]$psErrors) | Out-Null
if ($psErrors -and $psErrors.Count -gt 0) {
    throw ('R4G2 EFB PowerShell parser gate failed: ' + (($psErrors | ForEach-Object { $_.Message }) -join ' | '))
}

[xml]$versionXml = Get-Content -LiteralPath $versionPath -Raw
$versionNode = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
if ($null -eq $versionNode -or $versionNode.InnerText.Trim() -ne '1.1.1.0') { throw 'Version.props must remain 1.1.1.0.' }

$service = Get-Content -LiteralPath $servicePath -Raw
$altAdapter = Get-Content -LiteralPath $altAdapterPath -Raw
$sdk = Get-Content -LiteralPath $sdkPath -Raw
$mcp = Get-Content -LiteralPath $mcpPath -Raw
$camera = Get-Content -LiteralPath $cameraPath -Raw
$ahk = Get-Content -LiteralPath $ahkBridgePath -Raw
$controller = Get-Content -LiteralPath $controllerPath -Raw
$vosk = Get-Content -LiteralPath $voskPath -Raw
$efb = Get-Content -LiteralPath $efbUiPath -Raw
$style = Get-Content -LiteralPath $efbStylePath -Raw
$wrapperStyle = Get-Content -LiteralPath $efbWrapperStylePath -Raw
$efbBuild = Get-Content -LiteralPath $efbBuildPath -Raw

# R4G2 delivery gate: MARK reuses sv-auto-focus-toggle; reject the stale
# impossible .sv-mark-button compiled-CSS gate that blocked R4G1.
Require-NotContains $efbBuild 'R2 MARK active/disabled CSS states are missing from built TemplateApp.css.' 'Stale R2 MARK compiled-CSS gate'
Require-Contains $efbBuild 'R4G2 PMDG MARK style source semantics: PASS' 'R4G2 source-semantic MARK build gate'
Require-Contains $efb 'const markEnabled = this.checklistMarkModeEnabled;' 'PMDG MARK state source'
Require-Contains $efb 'sv-auto-focus-toggle' 'PMDG MARK shared toggle styling'
Require-Contains $efb "markButton.setAttribute('aria-pressed', markEnabled ? 'true' : 'false');" 'PMDG MARK accessibility state'

# Frozen R4D/R4F autopilot authority.
Require-Contains $service 'reason"] = "pmdg-737-ng3-title-match"' 'PMDG altitude identity override'
Require-Contains $altAdapter 'McpAltitudeSetKeyEvent' 'PMDG altitude event'
Require-Contains $altAdapter 'McpAltitudeWindowLvar' 'PMDG altitude readback'
Require-Contains $sdk 'EvtMcpAltitudeSet = ThirdPartyEventIdMin + 14505' 'PMDG ALT direct-set event'
Require-Contains $mcp 'EVT_MCP_HDG_SET' 'PMDG heading direct-set'
Require-Contains $mcp 'EVT_MCP_IAS_SET' 'PMDG IAS direct-set'
Require-Contains $mcp 'EVT_MCP_VS_SET' 'PMDG V/S direct-set'
Require-Contains $vosk 'ExecuteAutopilotAltitudeCommandAsync' 'Proven PMDG altitude route'
Require-Contains $vosk 'Pmdg737McpCommandService.IsCandidateAircraft' 'PMDG MCP route'

# R4G camera mapping and de-duplication.
Require-Contains $ahk 'SimVoiceInputCommands.exe' 'Internal AHK feeder executable'
Require-Contains $ahk 'C:\Temp\msfs_command.txt' 'Internal AHK command file'
Require-Contains $camera 'SIMVOICE_1_1_1_0_R4G_PMDG737_CHECKLIST_CAMERA_DETERMINISTIC' 'R4G camera marker'
Require-Contains $camera '"fuel panel", "panel de combustible"' 'Fuel-panel semantic forward-overhead mapping'
Require-Contains $camera 'ObservedNativeTargetHotKeys' 'Observed PMDG native-target camera map'
Require-Contains $camera '{ "native:7:6", Pmdg737Ng3Sdk.CameraHotKeyForwardOverhead }' 'Fuel panel observed Shift+6 target'
$observedTargetMatches = [System.Text.RegularExpressions.Regex]::Matches($camera,'\{ "native:\d+:\d+", Pmdg737Ng3Sdk\.CameraHotKey')
if ($observedTargetMatches.Count -ne 86) { throw "R4G observed PMDG target map count is $($observedTargetMatches.Count), expected 86 observed visual targets." }
Require-Contains $camera 'pmdg-r4g-observed-native-target-map' 'Observed target resolution source'
Require-Contains $camera 'pmdg-r4g-semantic-fallback' 'Unknown-target semantic fallback'
Require-Contains $camera 'automatic-item-lifetime' 'Automatic item-lifetime camera de-duplication'
Require-Contains $camera 'Reserve the automatic item key while still holding Sync' 'Atomic automatic camera reservation'
Require-Contains $camera 'IsStrongSemanticCameraMatch' 'Strong cameras.cfg semantic guard'
Require-Contains $camera 'pmdg-r4g-deterministic-zone-map' 'Deterministic PMDG hotkey map'
Require-Contains $camera 'SimVoiceAhkInputBridge.TryQueue' 'PMDG camera AHK transport'
Require-Contains $camera 'System.Threading.CancellationToken.None' 'Qualified CancellationToken'
Require-NotContains $camera 'private static extern uint SendInput' 'PMDG adapter direct SendInput'

# There must be only one mention of the old capture scheduler: its dormant method definition.
$scheduleMatches = [System.Text.RegularExpressions.Regex]::Matches($controller,'SchedulePmdg737CameraFallbackFromCapture\s*\(')
if ($scheduleMatches.Count -ne 1) { throw "R4G PMDG camera single-authority gate failed; capture scheduler occurrence count is $($scheduleMatches.Count), expected 1 definition only." }
Require-Contains $controller 'checklist.camera.pmdg.cancel_pending' 'PMDG pending-camera cancel action'
Require-Contains $controller 'SIMVOICE_1_1_1_0_R4G_PMDG_CAMERA_SINGLE_DISPATCH' 'PMDG camera generation guard'
Require-Contains $controller 'pmdgFallbackGeneration != Volatile.Read(ref pmdg737CameraFallbackSerial)' 'PMDG stale fallback suppression'
Require-Contains $controller 'EFB_NATIVE_CHECKLIST_CALLBACK_QUEUED' 'R2R restart checklist delivery'
Require-Contains $controller 'pmdg-checklist-camera-restore-1' 'Existing PMDG restore path retained for normal AUTO chain exit'

# R4G PMDG MARK transition: no camera movement on AUTO -> MARK.
Require-Contains $efb "const EFB_VERSION = '0.1.120';" 'R4G EFB version'
Require-Contains $efb 'SIMVOICE_1_1_1_0_R4G_PMDG_MARK_CAMERA_STABLE' 'PMDG MARK camera-stable marker'
Require-Contains $efb "sendAction('checklist.camera.pmdg.cancel_pending'" 'PMDG pending-camera cancellation from EFB'
Require-Contains $efb "stopNativeChecklistHelper('pmdg-mark-enabled-no-camera-restore', true, false)" 'AUTO-to-MARK no-restore transition'
Require-Contains $efb "await coherent.call('CHECKLIST_START_HELP', pageId, checkpointId);" 'PMDG MARK native highlight'
Require-Contains $efb "await coherent.call('CHECKLIST_STOP_HELP', pageId, checkpointId);" 'PMDG MARK native stop'
Require-Contains $efb "? 'MARCAR' : 'MARK'" 'PMDG MARK button'
Require-Contains $efb 'ignored-non-pmdg' 'Generic MARK remains frozen'

# Actual container geometry, not outer browser vh, drives landscape density.
Require-Contains $efb 'SIMVOICE_1_1_1_0_R4G_CONTAINER_GEOMETRY' 'Measured-container runtime marker'
Require-Contains $efb 'ResizeObserver' 'Container ResizeObserver path'
Require-Contains $efb 'this.root.clientWidth' 'Measured container width'
Require-Contains $efb 'this.root.clientHeight' 'Measured container height'
Require-Contains $efb "data-simvoice-orientation" 'Container orientation attribute'
Require-Contains $efb "data-simvoice-density" 'Container density attribute'
Require-Contains $style 'SIMVOICE_1_1_1_0_R4G_CONTAINER_GEOMETRY' 'Measured-container CSS marker'
Require-Contains $style 'grid-template-columns: repeat(3, minmax(0, 1fr)) !important;' 'Landscape 3x2 action grid'
Require-Contains $style 'height: auto !important;' 'Landscape item container-relative sizing'
Require-Contains $style 'flex: 1 1 auto !important;' 'Landscape flex sizing'
Require-Contains $wrapperStyle 'min-height: 0;' 'EFB wrapper can shrink to actual container'
Require-NotContains $wrapperStyle 'min-height: 520px;' 'Legacy fixed wrapper minimum height'
Require-Contains $efbBuild '$ExpectedEfbVersion = "0.1.120"' 'R4G EFB build version'
Require-Contains $efbBuild 'R4G measured-container landscape layout source + real build: PASS' 'R4G EFB build gate'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R4G2 PMDG CAMERA + RESPONSIVE EFB QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '86 observed PMDG visual targets have a deterministic camera map; Fuel panel native:7:6 => Shift+6.'
Write-Host 'PMDG AUTO camera has one post-START_HELP authority and item-lifetime de-duplication.'
Write-Host 'AUTO -> MARK invalidates pending camera work and does not restore/move the camera.'
Write-Host 'EFB v0.1.120 measures its real container and uses landscape/compact density rules.'
exit 0
