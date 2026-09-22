#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp',
    [string]$EfbProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file missing: $Path"
    }
}

function Require-Contains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) {
        throw "$Label missing: $Needle"
    }
}

function Require-NotContains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -ge 0) {
        throw "$Label unexpectedly contains: $Needle"
    }
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
$efbBuildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

@($versionPath,$servicePath,$altAdapterPath,$sdkPath,$mcpPath,$cameraPath,$ahkBridgePath,$controllerPath,$voskPath,$efbUiPath,$efbBuildPath) | ForEach-Object { Require-File $_ }

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
$vosk = Get-Content -LiteralPath $voskPath -Raw
$efb = Get-Content -LiteralPath $efbUiPath -Raw
$efbBuild = Get-Content -LiteralPath $efbBuildPath -Raw

# ALT: restore the exact R4D proven adapter path and identity-first selection.
Require-Contains $service 'reason"] = "pmdg-737-ng3-title-match"' 'PMDG altitude identity override'
Require-Contains $altAdapter 'McpAltitudeSetKeyEvent' 'PMDG altitude event'
Require-Contains $altAdapter 'McpAltitudeWindowLvar' 'PMDG altitude LVar readback'
Require-Contains $altAdapter 'PMDG737_ALTITUDE_LVAR_READBACK' 'PMDG altitude verified readback log'
Require-Contains $sdk 'EvtMcpAltitudeSet = ThirdPartyEventIdMin + 14505' 'PMDG ALT direct-set event'
Require-Contains $sdk 'McpAltitudeWindowLvar = "ngx_ALTwindow"' 'PMDG ALT window LVar'

# Remaining MCP controls: same direct-set + live window pattern.
Require-Contains $mcp 'EVT_MCP_HDG_SET' 'PMDG heading direct-set'
Require-Contains $mcp 'McpHeadingWindowLvar' 'PMDG heading readback'
Require-Contains $mcp 'EVT_MCP_IAS_SET' 'PMDG IAS direct-set'
Require-Contains $mcp 'McpSpeedWindowLvar' 'PMDG IAS readback'
Require-Contains $mcp 'EVT_MCP_VS_SET' 'PMDG V/S direct-set'
Require-Contains $mcp 'McpVerticalSpeedWindowLvar' 'PMDG V/S readback'
Require-Contains $mcp 'value => value + 10000' 'PMDG V/S wire encoding'

# Keep altitude on the proven AutopilotAltitudeService path before the R4E MCP branch.
$altIndex = $vosk.IndexOf('if (action.Equals("AP_ALT_VAR_SET_ENGLISH"',[System.StringComparison]::Ordinal)
$pmdgIndex = $vosk.IndexOf('bool isPmdg737McpAction',[System.StringComparison]::Ordinal)
if ($altIndex -lt 0 -or $pmdgIndex -lt 0 -or $altIndex -gt $pmdgIndex) {
    throw 'Vosk PMDG routing regression: proven altitude path must precede the PMDG HDG/IAS/V-S branch.'
}
Require-Contains $vosk 'ExecuteAutopilotAltitudeCommandAsync' 'Proven PMDG altitude route'
Require-Contains $vosk 'Pmdg737McpCommandService.IsCandidateAircraft' 'PMDG remaining MCP route'

# Camera: PMDG uses the same packaged AHK feeder as working Keyboard Commands.
Require-Contains $ahk 'SimVoiceInputCommands.exe' 'Internal AHK feeder executable'
Require-Contains $ahk 'C:\Temp\msfs_command.txt' 'Internal AHK command file'
Require-Contains $camera 'SimVoiceAhkInputBridge.TryQueue' 'PMDG camera AHK transport'
Require-Contains $camera 'System.Threading.CancellationToken.None' 'PMDG camera CancellationToken compile qualification'
Require-Contains $camera 'FormatAhkShiftChord' 'PMDG Shift+number AHK code'
Require-Contains $camera 'PMDG737_CAMERA_HOTKEY_DEDUPED' 'PMDG duplicate camera suppression'
Require-NotContains $camera 'private static extern uint SendInput' 'PMDG camera adapter direct SendInput'
Require-Contains $controller 'SchedulePmdg737CameraFallbackFromCapture' 'PMDG camera trigger from native helper capture'
Require-Contains $controller 'pmdg-checklist-camera-restore-1' 'PMDG AHK camera restore'
Require-Contains $controller 'SIMVOICE_AHK_LEFT_SHIFT_1_TWICE_R4F' 'PMDG AHK restore authority'

# R2R restart delivery must remain present.
Require-Contains $controller 'EFB_NATIVE_CHECKLIST_CALLBACK_QUEUED' 'R2R restart checklist delivery'

# PMDG-only MARK: direct native helper, no camera transaction. Generic MARK remains frozen.
Require-Contains $efb "const EFB_VERSION = '0.1.118';" 'R4F EFB version'
Require-Contains $efb 'SIMVOICE_1_1_1_0_R4F_PMDG_NATIVE_MARK_NO_CAMERA' 'PMDG MARK marker'
Require-Contains $efb 'isPmdg737NativeMarkAvailable' 'PMDG MARK aircraft gate'
Require-Contains $efb "await coherent.call('CHECKLIST_START_HELP', pageId, checkpointId);" 'PMDG MARK native highlight'
Require-Contains $efb "await coherent.call('CHECKLIST_STOP_HELP', pageId, checkpointId);" 'PMDG MARK native stop'
Require-Contains $efb "? 'MARCAR' : 'MARK'" 'PMDG MARK button'
Require-Contains $efb 'ignored-non-pmdg' 'Generic MARK remains frozen'

$markStart = $efb.IndexOf('private async startPmdgNativeChecklistMarkHelper(',[System.StringComparison]::Ordinal)
$markEnd = $efb.IndexOf('private async stopPmdgNativeChecklistMarkHelper(',[System.StringComparison]::Ordinal)
if ($markStart -lt 0 -or $markEnd -le $markStart) {
    throw 'PMDG MARK helper method boundaries not found.'
}
$markMethod = $efb.Substring($markStart,$markEnd-$markStart)
Require-NotContains $markMethod "sendAction('checklist.camera.capture_previous'" 'PMDG MARK camera capture'
Require-NotContains $markMethod 'Pmdg737ChecklistCameraAdapter' 'PMDG MARK camera fallback'
Require-NotContains $markMethod 'restore_previous' 'PMDG MARK camera restore'

Require-Contains $efbBuild '$ExpectedEfbVersion = "0.1.118"' 'R4F EFB build version'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R4F2 PMDG737 EFB RUNNER FIX QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'ALT R4D path restored; HDG/IAS/V-S use PMDG direct-set + ngx readback.'
Write-Host 'PMDG camera uses internal SimVoiceInputCommands.exe AHK transport.'
Write-Host 'PMDG-only MARK uses native CHECKLIST_START_HELP without camera transaction.'
exit 0
