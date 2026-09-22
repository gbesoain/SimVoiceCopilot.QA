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
$supportPath = Join-Path $WindowsProjectRoot 'SupportPackageExporter.cs'
$voskPath = Join-Path $WindowsProjectRoot 'VoskRecognizer.cs'
$efbUiPath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$efbStylePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css'
$efbWrapperStylePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\TemplateApp.scss'
$efbBuildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

@(
    $versionPath,$servicePath,$altAdapterPath,$sdkPath,$mcpPath,$cameraPath,
    $ahkBridgePath,$controllerPath,$supportPath,$voskPath,$efbUiPath,
    $efbStylePath,$efbWrapperStylePath,$efbBuildPath
) | ForEach-Object { Require-File $_ }

# The installed EFB build script must parse under Windows PowerShell 5.1.
$psTokens = $null
$psErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($efbBuildPath,[ref]$psTokens,[ref]$psErrors) | Out-Null
if ($psErrors -and $psErrors.Count -gt 0) {
    throw ('R4I EFB PowerShell parser gate failed: ' + (($psErrors | ForEach-Object { $_.Message }) -join ' | '))
}

[xml]$versionXml = Get-Content -LiteralPath $versionPath -Raw
$versionNode = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
if ($null -eq $versionNode -or $versionNode.InnerText.Trim() -ne '1.1.1.0') {
    throw 'Version.props must remain 1.1.1.0.'
}

$service = Get-Content -LiteralPath $servicePath -Raw
$altAdapter = Get-Content -LiteralPath $altAdapterPath -Raw
$sdk = Get-Content -LiteralPath $sdkPath -Raw
$mcp = Get-Content -LiteralPath $mcpPath -Raw
$camera = Get-Content -LiteralPath $cameraPath -Raw
$ahk = Get-Content -LiteralPath $ahkBridgePath -Raw
$controller = Get-Content -LiteralPath $controllerPath -Raw
$support = Get-Content -LiteralPath $supportPath -Raw
$vosk = Get-Content -LiteralPath $voskPath -Raw
$efb = Get-Content -LiteralPath $efbUiPath -Raw
$style = Get-Content -LiteralPath $efbStylePath -Raw
$wrapperStyle = Get-Content -LiteralPath $efbWrapperStylePath -Raw
$efbBuild = Get-Content -LiteralPath $efbBuildPath -Raw

# Frozen PMDG autopilot authority from R4D/R4F.
Require-Contains $service 'reason"] = "pmdg-737-ng3-title-match"' 'PMDG altitude identity override'
Require-Contains $altAdapter 'McpAltitudeSetKeyEvent' 'PMDG altitude event'
Require-Contains $altAdapter 'McpAltitudeWindowLvar' 'PMDG altitude readback'
Require-Contains $sdk 'EvtMcpAltitudeSet = ThirdPartyEventIdMin + 14505' 'PMDG ALT direct-set event'
Require-Contains $mcp 'EVT_MCP_HDG_SET' 'PMDG heading direct-set'
Require-Contains $mcp 'EVT_MCP_IAS_SET' 'PMDG IAS direct-set'
Require-Contains $mcp 'EVT_MCP_VS_SET' 'PMDG V/S direct-set'
Require-Contains $vosk 'ExecuteAutopilotAltitudeCommandAsync' 'Proven PMDG altitude route'
Require-Contains $vosk 'Pmdg737McpCommandService.IsCandidateAircraft' 'PMDG MCP route'

# R2R / R4H ready-catalog reuse must remain isolated from normal tab navigation.
Require-Contains $controller 'SIMVOICE_1_1_1_0_R4H_EFB_READY_CATALOG_REUSE' 'R4H ready catalog reuse marker'
Require-Contains $controller 'EFB_CHECKLIST_OPEN_REUSED_READY_CATALOG' 'R4H ready catalog reuse event'
Require-Contains $controller 'if (!catalogReady)' 'R4H refresh-only-when-not-ready gate'
Require-NotContains $controller 'if (resetToSelection || !catalogReady)' 'R2R selector-reset forced refresh regression'
Require-Contains $controller 'SIMVOICE_1_1_1_0_R2R_EFB_SELECTOR_SELF_HEAL' 'R2R self-heal retained'

# R4I one-to-one PMDG camera mapping: all 217 visual targets observed in the
# current 737-800 catalog are explicit. Runtime semantic guessing is forbidden.
Require-Contains $ahk 'SimVoiceInputCommands.exe' 'Internal AHK feeder executable'
Require-Contains $ahk 'C:\Temp\msfs_command.txt' 'Internal AHK command file'
Require-Contains $camera 'SIMVOICE_1_1_1_0_R4I_PMDG737_EXACT_TARGET_CAMERA_MAP' 'R4I camera marker'
Require-Contains $camera 'ExactNativeTargetHotKeys' 'R4I exact native target map'
Require-Contains $camera 'pmdg-r4i-exact-native-target-map' 'R4I exact mapping resolution source'
Require-Contains $camera 'PMDG737_CAMERA_EXACT_MAP_MISS' 'R4I unmapped-target diagnostic'
Require-Contains $camera '{ "native:7:6", Pmdg737Ng3Sdk.CameraHotKeyForwardOverhead }' 'Fuel panel exact Shift+6 target'
Require-Contains $camera 'mappedTargetCount' 'R4I map-count diagnostics'
Require-Contains $camera 'automatic-item-lifetime' 'Automatic item-lifetime de-duplication'
Require-Contains $camera 'SimVoiceAhkInputBridge.TryQueue' 'PMDG camera AHK transport'
Require-Contains $camera 'System.Threading.CancellationToken.None' 'Qualified CancellationToken'
Require-NotContains $camera 'pmdg-r4g-semantic-fallback' 'Runtime semantic camera fallback'
Require-NotContains $camera 'private static extern uint SendInput' 'PMDG direct SendInput'

$exactTargetMatches = [System.Text.RegularExpressions.Regex]::Matches(
    $camera,
    '\{ "native:\d+:\d+", Pmdg737Ng3Sdk\.CameraHotKey')
if ($exactTargetMatches.Count -ne 217) {
    throw "R4I exact PMDG target map count is $($exactTargetMatches.Count), expected 217."
}

# The EFB must schedule only one PMDG camera for the exact current target and
# never create targetless restore/probe camera movements.
Require-Contains $efb "const EFB_VERSION = '0.1.122';" 'R4I EFB version'
Require-Contains $efb 'SIMVOICE_1_1_1_0_R4H_PMDG_CAMERA_START_ISSUED' 'R4H START_HELP-issued camera baseline'
Require-Contains $efb 'SIMVOICE_1_1_1_0_R4I_PMDG_TARGET_ONLY_CAMERA' 'R4I target-only camera marker'
Require-Contains $efb 'capture-previous-suppressed' 'R4I PMDG capture suppression'
Require-Contains $efb 'restore-suppressed' 'R4I PMDG restore suppression'
Require-Contains $efb 'stop-without-camera-restore' 'R4I PMDG stop-without-restore'
Require-Contains $efb "reason: 'pmdg-start-help-issued-camera-verify'" 'R4H/R4I PMDG camera dispatch reason'
Require-Contains $efb "origin !== 'simvoice-mark'" 'MARK remains camera-free'
Require-Contains $efb 'automatic && this.checklistMarkModeEnabled' 'AUTO-to-MARK stale timer suppression'

# R4I active checklist reader must fit the actual measured root in portrait too.
Require-Contains $efb 'SIMVOICE_1_1_1_0_R4I_ACTIVE_CHECKLIST_CONTAINER_FIT' 'R4I active checklist fit marker'
Require-Contains $efb 'const activeChecklistScale = Math.max(0.68' 'R4I measured active checklist scale'
Require-Contains $efb "this.root.style.setProperty('--sv-active-button-height'" 'R4I action button height variable'
Require-Contains $efb "this.root.style.setProperty('--sv-active-label-font'" 'R4I label font variable'
Require-Contains $efb "height <= 560 ? 'short' : (height <= 760 ? 'compact' : 'normal')" 'R4I measured density thresholds'
Require-Contains $style 'SIMVOICE_1_1_1_0_R4I_ACTIVE_CHECKLIST_CONTAINER_FIT' 'R4I active checklist CSS marker'
Require-Contains $style 'data-simvoice-active-checklist-fit' 'R4I measured-container selector'
Require-Contains $style 'flex: 1 1 0 !important;' 'R4I remaining-height current item'
Require-Contains $style 'var(--sv-active-button-height' 'R4I responsive action height'
Require-Contains $style 'grid-template-columns: repeat(2, minmax(0, 1fr)) !important;' 'R4I portrait 2-column action grid'
Require-Contains $style 'grid-template-columns: repeat(3, minmax(0, 1fr)) !important;' 'R4I landscape 3-column action grid'
Require-Contains $wrapperStyle 'min-height: 0;' 'EFB wrapper can shrink to actual container'
Require-NotContains $wrapperStyle 'min-height: 520px;' 'Legacy fixed wrapper minimum height'

# R4I support export: no active 4-second Input Event probe, no parallel
# aircraft-compatibility sidecar, and fast compression.
Require-Contains $support 'SIMVOICE_1_1_1_0_R4I_SUPPORT_FAST_EXPORT' 'R4I support performance marker'
Require-Contains $support 'cached-snapshot-no-active-enumeration' 'Cached Input Event snapshot mode'
Require-Contains $support 'CompressionLevel.Fastest' 'Fast support ZIP compression'
Require-Contains $support 'compatibilitySidecarCreated"] = false' 'No-sidecar performance diagnostic'
Require-NotContains $support 'EnsureEnumeratedAsync(' 'Support export active Input Event enumeration'
$sidecarCallMatches = [System.Text.RegularExpressions.Regex]::Matches($support,'WriteCompatibilitySidecar\s*\(')
if ($sidecarCallMatches.Count -ne 1) {
    throw "R4I sidecar generation gate failed; WriteCompatibilitySidecar occurrence count is $($sidecarCallMatches.Count), expected one dormant method definition only."
}

Require-Contains $efbBuild '$ExpectedEfbVersion = "0.1.122"' 'R4I EFB build version'
Require-Contains $efbBuild 'R4I active-checklist real-container fit + PMDG target-only camera policy: PASS' 'R4I EFB source gate'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R4I EXACT CAMERA + CONTAINER FIT + FAST SUPPORT QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'PMDG: 217 native visual targets are explicit one-to-one Shift+n mappings; runtime semantic fallback is disabled.'
Write-Host 'PMDG: camera restore/probe movement is suppressed; AUTO/FOCUS move only for the exact current target.'
Write-Host 'EFB: active checklist reader/actions now fit measured container geometry in portrait and landscape.'
Write-Host 'Support ZIP: cached Input Event snapshot, Fastest compression, no parallel compatibility JSON sidecar.'
Write-Host 'R2R and R4H ready-catalog reuse remain intact. EFB v0.1.122; Windows remains 1.1.1.0.'
exit 0
