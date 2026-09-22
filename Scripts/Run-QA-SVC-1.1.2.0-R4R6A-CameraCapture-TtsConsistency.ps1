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
function Read-Text([string]$Path) { Require-File $Path; return [IO.File]::ReadAllText($Path) }
function Require-Contains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[StringComparison]::Ordinal) -lt 0) { throw "$Label missing semantic: $Needle" }
}
function Require-NotContains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[StringComparison]::Ordinal) -ge 0) { throw "$Label contains rejected semantic: $Needle" }
}

try {
    Write-Host 'R4R6A QA started...' -ForegroundColor Cyan

    [xml]$versionXml = Get-Content -LiteralPath (Join-Path $WindowsProjectRoot 'Version.props') -Raw
    $version = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
    $display = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion')
    if ($null -eq $version -or $null -eq $display -or
        $version.InnerText.Trim() -ne '1.1.2.0' -or
        $display.InnerText.Trim() -ne '1.1.2.0') {
        throw 'Windows version must remain 1.1.2.0.'
    }

    $store = Read-Text (Join-Path $WindowsProjectRoot 'ChecklistCameraBindingStore.cs')
    $capture = Read-Text (Join-Path $WindowsProjectRoot 'ChecklistCameraBindingCaptureService.cs')
    $controller = Read-Text (Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs')
    $speech = Read-Text (Join-Path $WindowsProjectRoot 'SpeechManager.cs')
    $neural = Read-Text (Join-Path $WindowsProjectRoot 'NeuralVoiceClient.cs')

    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R6_USER_CHECKLIST_CAMERA_BINDING',
        'SaveCapturedScanCodes',
        'BuildStableKey',
        'IsSupportedBaseScanCode',
        'IsModifierScanCode',
        'SimVoiceAhkInputBridge.TryQueue'
    )) { Require-Contains $store $required 'R4R6A camera binding store' }

    foreach ($required in @(
        'SIMVOICE_1_1_2_0_R4R6A_USER_CAMERA_GLOBAL_KEY_CAPTURE',
        'SetWindowsHookEx',
        'WhKeyboardLl = 13',
        'CallNextHookEx',
        'ChecklistCameraBindingCaptureOutcome.Clear',
        'CHECKLIST_USER_CAMERA_CAPTURE_STARTED'
    )) { Require-Contains $capture $required 'R4R6A global capture service' }
    Require-NotContains $capture 'SendInput(' 'R4R6A capture transport'

    foreach ($required in @(
        'case "checklist.camera.user.capture.begin"',
        'case "checklist.camera.user.capture.cancel"',
        'ChecklistCameraBindingCaptureService.Begin',
        'OnChecklistCameraBindingCaptureCompleted',
        'SaveCapturedScanCodes',
        '"userCameraBindingCaptureActive"'
    )) { Require-Contains $controller $required 'R4R6A EFB controller' }

    foreach ($required in @(
        'SIMVOICE_1_1_2_0_R4R6A_NEURAL_PROVIDER_CONSISTENCY',
        'ShouldAttemptNeuralVoice',
        'NEURAL_TTS_PROVIDER_LOCK_SYSTEM',
        'NEURAL_TTS_SYSTEM_PROVIDER_SELECTED',
        'balance_below_estimated_request'
    )) { Require-Contains $speech $required 'R4R6A TTS provider consistency' }

    foreach ($required in @(
        'MarkGenerationBalanceRejected',
        'TryGetLastGenerationBalanceRejectedUtc'
    )) { Require-Contains $neural $required 'R4R6A Neural balance rejection state' }

    $ui = Read-Text (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts')
    $protocol = Read-Text (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\core\protocol.ts')
    $style = Read-Text (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css')
    $build = Read-Text (Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1')

    Require-Contains $ui "const EFB_VERSION = '0.1.137';" 'R4R6A EFB version'
    foreach ($required in @(
        'USER_CAMERA_GLOBAL_CAPTURE_R4R6A_MARKER',
        'checklist.camera.user.capture.begin',
        'checklist.camera.user.capture.cancel',
        'userCameraBindingCaptureActive',
        'CAM: FS Default',
        'Delete/Backspace = FS Default'
    )) { Require-Contains $ui $required 'R4R6A EFB UI' }

    Require-NotContains $ui 'sv-camera-binding-capture-input' 'R4R6A EFB camera capture'
    Require-Contains $protocol 'userCameraBindingCaptureActive?: boolean' 'R4R6A protocol'
    Require-Contains $style '.sv-camera-binding-capture-hint' 'R4R6A style'
    Require-NotContains $style '.sv-camera-binding-capture-input' 'R4R6A style'
    Require-Contains $build '$ExpectedEfbVersion = "0.1.137"' 'R4R6A EFB build version'
    Require-Contains $build 'R4R6A global camera capture + Neural/System provider consistency semantics: PASS' 'R4R6A build gate'

    Write-Host 'R4R6A SOURCE QA: PASS' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ('R4R6A SOURCE QA: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
