#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp',
    [string]$EfbProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-RequiredText {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing required file: $Path" }
    return [IO.File]::ReadAllText($Path)
}
function Require-Contains {
    param([string]$Text,[string]$Needle,[string]$Label)
    if ($Text.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "$Label missing semantic: $Needle" }
}
function Require-NotContains {
    param([string]$Text,[string]$Needle,[string]$Label)
    if ($Text.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "$Label contains forbidden semantic: $Needle" }
}

try {
    $versionPath = Join-Path $WindowsProjectRoot 'Version.props'
    if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        $version = Read-RequiredText $versionPath
        Require-Contains $version '<SimVoiceVersion>1.1.2.0</SimVoiceVersion>' 'Windows version'
        Require-Contains $version '<SimVoiceDisplayVersion>1.1.2.0</SimVoiceDisplayVersion>' 'Windows display version'
    }

    $settings = Read-RequiredText (Join-Path $WindowsProjectRoot 'VoiceSettingsForm.cs')
    Require-Contains $settings 'ApplySettingsComboScale' 'R4R10 Settings combo DPI helper'
    Require-Contains $settings 'ApplySettingsComboScaling' 'R4R10 Settings combo DPI application'
    Require-Contains $settings 'combo.ItemHeight = itemHeight' 'R4R10 Settings combo item height'
    Require-Contains $settings 'combo.DropDownHeight' 'R4R10 Settings combo dropdown height'
    Require-Contains $settings 'combo.MinimumSize' 'R4R10 Settings combo minimum height'
    Require-Contains $settings 'DpiChanged +=' 'Settings DPI relayout continuity'

    $advancedForm = Read-RequiredText (Join-Path $WindowsProjectRoot 'AdvancedSimulatorActionsForm.cs')
    Require-Contains $advancedForm 'DrawMode = DrawMode.OwnerDrawFixed' 'R4R10 Advanced list contrast'
    Require-Contains $advancedForm 'DrawActionListItem' 'R4R10 Advanced owner draw'
    Require-Contains $advancedForm 'ThemeManager.GetSurfaceAltColor' 'R4R10 Advanced normal list surface'
    Require-Contains $advancedForm 'ThemeManager.GetPrimaryColor' 'R4R10 Advanced selected list surface'
    Require-Contains $advancedForm 'FormatExecutionResultForUi' 'R4R10 Advanced localized result formatter'
    Require-Contains $advancedForm 'ENVIADA:' 'R4R10 Spanish sent result'
    Require-Contains $advancedForm 'VERIFICADA:' 'R4R10 Spanish verified result'
    Require-Contains $advancedForm 'BLOQUEADA:' 'R4R10 Spanish scope result'

    $controller = Read-RequiredText (Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs')
    Require-Contains $controller 'SIMVOICE_1_1_2_0_R4R10_USER_CAMERA_SINGLE_AUTHORITY' 'R4R10 Windows camera single authority marker'
    Require-Contains $controller 'CHECKLIST_USER_CAMERA_NATIVE_DEFERRED' 'R4R10 Windows native camera defer'
    Require-Contains $controller 'userCameraDeferredToEfb' 'R4R10 camera diagnostic'
    Require-Contains $controller 'SetUserCameraCaptureFeedback(snapshot, "cleared", "FS Default")' 'R4R10 clear feedback reset'
    Require-Contains $controller 'userCameraCaptureFeedbackExpiresUtc' 'R4R10 camera feedback expiry'

    $efbUi = Read-RequiredText (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts')
    Require-Contains $efbUi "const EFB_VERSION = '0.1.141'" 'R4R10 EFB version'
    Require-Contains $efbUi 'SIMVOICE_1_1_2_0_R4R10_USER_CAMERA_SINGLE_AUTHORITY' 'R4R10 EFB single authority marker'
    Require-Contains $efbUi 'USER_CAMERA_AFTER_NATIVE_SETTLE_MS = 1200' 'R4R10 camera settle'
    Require-Contains $efbUi 'userCameraClearSuppressedItemIdentity' 'R4R10 clear delayed-camera suppression'
    Require-Contains $efbUi 'liveChecklist?.userCameraBindingConfigured === true' 'R4R10 default fallback suppression while user camera configured'
    Require-Contains $efbUi "reason: 'user-camera-cleared-restore-curated'" 'R4R10 curated fallback after clear'
    Require-Contains $efbUi 'helperRestarted=false' 'R4R10 clear does not restart native helper'
    Require-Contains $efbUi "this.language === 'es' ? 'BORRAR' : 'CLEAR'" 'R4R10 compact clear label'
    Require-NotContains $efbUi "await this.startNativeChecklistHelper(liveTarget, 'simvoice-manual', true);" 'R4R10 clear duplicate helper regression'

    $css = Read-RequiredText (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css')
    Require-Contains $css '.sv-camera-binding-clear-button' 'R4R10 clear button style'
    Require-Contains $css 'max-width: 48px !important' 'R4R10 compact clear button small layout'

    $build = Read-RequiredText (Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1')
    Require-Contains $build '$ExpectedEfbVersion = "0.1.141"' 'R4R10 EFB build version'
    Require-Contains $build 'SIMVOICE_1_1_2_0_R4R10_USER_CAMERA_SINGLE_AUTHORITY' 'R4R10 EFB build semantic gate'

    Write-Host 'QA STATIC/SOURCE: PASS' -ForegroundColor Green
    Write-Host 'Windows: 1.1.2.0 | EFB: 0.1.141 | WASM/Backend: unchanged' -ForegroundColor Green
    Write-Host 'Physical QA required: Settings combo scaling, Advanced list/result UX, CAM custom-vs-default ordering, single-item clear, highlight continuity.' -ForegroundColor Yellow
    exit 0
}
catch {
    Write-Host ('QA STATIC/SOURCE: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
