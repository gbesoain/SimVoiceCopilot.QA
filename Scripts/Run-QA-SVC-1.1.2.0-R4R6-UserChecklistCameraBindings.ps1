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
function Read-WindowsText([string]$Relative) { return Read-Text (Join-Path $WindowsProjectRoot $Relative) }
function Require-Contains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[StringComparison]::Ordinal) -lt 0) { throw "$Label missing semantic: $Needle" }
}
function Require-ContainsIgnoreCase([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "$Label missing semantic: $Needle" }
}
function Require-NotContains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[StringComparison]::Ordinal) -ge 0) { throw "$Label contains rejected pattern: $Needle" }
}

try {
    Write-Host 'R4R6 QA started...' -ForegroundColor Cyan

    $versionPath = Join-Path $WindowsProjectRoot 'Version.props'
    Require-File $versionPath
    [xml]$versionXml = Get-Content -LiteralPath $versionPath -Raw
    $version = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
    $display = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion')
    if ($null -eq $version -or $null -eq $display -or
        $version.InnerText.Trim() -ne '1.1.2.0' -or
        $display.InnerText.Trim() -ne '1.1.2.0') {
        throw 'Windows version must be 1.1.2.0.'
    }

    # R4R6 Windows contract.
    $store = Read-WindowsText 'ChecklistCameraBindingStore.cs'
    $controller = Read-WindowsText 'SimVoiceEfbLocalController.cs'
    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R6_USER_CHECKLIST_CAMERA_BINDING',
        'SIMVOICE_1_1_1_0_R4R6_USER_CHECKLIST_CAMERA_DISPATCH',
        'ChecklistCameraBindings',
        'camera-bindings.json',
        'CurrentItemId',
        'Item identity deliberately excludes CurrentLabel/CurrentAction',
        'BaseKeys.TryGetValue',
        'executionCode = "SC:"',
        'SimVoiceAhkInputBridge.TryQueue',
        'CHECKLIST_USER_CAMERA_BINDING_RETAINED'
    )) { Require-Contains $store $required 'R4R6 camera binding store' }
    Require-NotContains $store 'SendInput(' 'R4R6 camera binding transport'

    foreach ($required in @(
        'case "checklist.camera.user.save"',
        'case "checklist.camera.user.clear"',
        'case "checklist.camera.user.apply"',
        'ChecklistCameraBindingStore.Save',
        'ChecklistCameraBindingStore.Clear',
        'ChecklistCameraBindingDispatcher.TryDispatch',
        'current-item-without-user-camera',
        '"canConfigureUserCameraBinding"',
        '"userCameraBindingConfigured"',
        '"userCameraBindingDisplay"',
        '"userCameraBindingShortDisplay"'
    )) { Require-Contains $controller $required 'R4R6 EFB local controller' }

    # Preserve R4R5A / R4R4 release baseline.
    $pmdgSdk = Read-WindowsText 'Pmdg737Ng3Sdk.cs'
    $pmdgMcp = Read-WindowsText 'Pmdg737McpCommandService.cs'
    $camera = Read-WindowsText 'Pmdg737ChecklistCameraAdapter.cs'
    $neural = Read-WindowsText 'NeuralVoiceClient.cs'
    $speech = Read-WindowsText 'SpeechManager.cs'
    $catalog = Read-WindowsText 'MsfsSdkCatalogService.cs'
    $iflySdk = Read-WindowsText 'Ifly737MaxSdk.cs'
    $iflyMcp = Read-WindowsText 'Ifly737MaxMcpCommandService.cs'
    foreach ($required in @('SIMVOICE_1_1_1_0_R4R5_PMDG737700_800_NG3_FAMILY','IsPmdg737700CandidateTitle','IsPmdg737800CandidateTitle','SIMVOICE_1_1_1_0_R4R2_PMDG737800_ASYNC_NG3_SIGNATURE')) { Require-Contains $pmdgSdk $required 'R4R5A PMDG baseline' }
    Require-NotContains $pmdgSdk '.GetAwaiter().GetResult()' 'R4R5A PMDG async identity'
    foreach ($required in @('SIMVOICE_1_1_1_0_R4R3_PMDG737_VS_HANDSHAKE_MACH','PMDG737_VS_WINDOW_READY','AP_MACH_VAR_SET')) { Require-Contains $pmdgMcp $required 'R4R3 PMDG MCP baseline' }
    Require-Contains $camera 'R4MCuratedTargetCount = 373' 'PMDG 737-800 camera baseline'
    Require-Contains $neural 'SIMVOICE_1_1_1_0_R4R5_CHECKLIST_NEURAL_TTS_PREFETCH' 'R4R5 TTS prefetch baseline'
    Require-Contains $speech 'PrefetchNeuralVoiceAsync' 'R4R5 TTS scheduler baseline'
    Require-Contains $catalog 'SIMVOICE_1_1_1_0_R4R4_FAST_INPUT_EVENT_CACHE' 'R4R4 performance baseline'
    Require-Contains $iflySdk 'SIMVOICE_1_1_1_0_R4R4_IFLY737MAX_SDK_V15' 'R4R4 iFly SDK baseline'
    Require-Contains $iflyMcp 'SIMVOICE_1_1_1_0_R4R4_IFLY737MAX_MCP_CORE' 'R4R4 iFly MCP baseline'

    # R4R6 EFB contract.
    $uiPath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
    $protocolPath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\core\protocol.ts'
    $stylePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css'
    $buildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'
    $ui = Read-Text $uiPath
    $protocol = Read-Text $protocolPath
    $style = Read-Text $stylePath
    $build = Read-Text $buildPath

    Require-Contains $ui "const EFB_VERSION = '0.1.136';" 'R4R6 EFB version'
    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R6_USER_CHECKLIST_CAMERA_BINDING',
        'beginUserCameraBindingCapture',
        'endUserCameraBindingCapture',
        'applyUserCameraBinding',
        'checklist.camera.user.save',
        'checklist.camera.user.clear',
        'checklist.camera.user.apply',
        'Delete/Backspace = FS Default',
        'userCameraBindingConfigured',
        'native-helper-suppressed',
        'SIMVOICE_1_1_1_0_R4R6_USER_CAMERA_RETAINED_AUTO_NO_FORCE',
        'CAM: FS Default'
    )) { Require-Contains $ui $required 'R4R6 EFB UI' }
    foreach ($required in @('canConfigureUserCameraBinding?: boolean','userCameraBindingConfigured?: boolean','userCameraBindingDisplay?: string','userCameraBindingShortDisplay?: string')) { Require-Contains $protocol $required 'R4R6 protocol' }
    foreach ($required in @('.sv-camera-binding-button','.sv-camera-binding-capture-input','.sv-camera-binding-capture-hint','grid-template-columns: repeat(4, minmax(0, 1fr))')) { Require-Contains $style $required 'R4R6 EFB style' }
    Require-Contains $ui 'SIMVOICE_1_1_1_0_R4R2_EFB_EDGE_AND_SMALL_DOCK_FIT' 'R4R2 layout baseline'
    Require-Contains $build '$ExpectedEfbVersion = "0.1.136"' 'R4R6 EFB build version'
    Require-Contains $build 'R4R6 user checklist camera binding source semantics: PASS' 'R4R6 build semantic gate'
    Require-Contains $build 'R4R5 PMDG 737-700 NG3 + checklist Neural TTS prefetch semantics: PASS' 'R4R5 build baseline gate'
    Require-Contains $build 'R4R4 fast command/AI load + single-call planner + iFly SDK/checklist core semantics: PASS' 'R4R4 build baseline gate'
    Require-NotContains $build 'Join-Path $SourceRoot' 'R4R6 EFB build contract'

    Write-Host 'R4R6 1.1.2.0 SOURCE QA: PASS' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ('R4R6 SOURCE QA: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
