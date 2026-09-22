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
    if ($Text.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "$Label missing semantic: $Needle"
    }
}

function Require-NotContains {
    param([string]$Text,[string]$Needle,[string]$Label)
    if ($Text.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "$Label contains forbidden semantic: $Needle"
    }
}

try {
    $versionPath = Join-Path $WindowsProjectRoot 'Version.props'
    if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        $version = Read-RequiredText $versionPath
        Require-Contains $version '<SimVoiceVersion>1.1.2.0</SimVoiceVersion>' 'Windows version'
        Require-Contains $version '<SimVoiceDisplayVersion>1.1.2.0</SimVoiceDisplayVersion>' 'Windows display version'
    }

    # R4R9 Settings: measured translated labels + DPI-responsive card heights.
    $settings = Read-RequiredText (Join-Path $WindowsProjectRoot 'VoiceSettingsForm.cs')
    Require-Contains $settings 'SIMVOICE_1_1_2_0_R4R8_SETTINGS_DPI_RESIZE' 'Settings resize continuity'
    Require-Contains $settings 'TextRenderer.MeasureText' 'R4R9 Settings measured text'
    Require-Contains $settings 'MeasureSettingsLabelHeight' 'R4R9 Settings label measurement helper'
    Require-Contains $settings 'tablaContenido.RowStyles.Clear()' 'R4R9 Settings measured row layout'
    Require-Contains $settings 'pnlContenido.AutoScrollMinSize' 'R4R9 Settings constrained-display scroll'
    Require-Contains $settings 'DpiChanged +=' 'R4R9 Settings DPI relayout'
    Require-Contains $settings 'Screen.FromControl(this).WorkingArea' 'R4R9 Settings working-area clamp'
    Require-NotContains $settings 'ClientSize = new System.Drawing.Size(ClientSize.Width, 950)' 'Settings fixed 950px height regression'
    Require-NotContains $settings 'ClientSize = new System.Drawing.Size(ClientSize.Width, 850)' 'Settings fixed 850px height regression'

    # R4R9 camera: native helper/highlight remains authoritative; user CAM is final camera only.
    $efbUi = Read-RequiredText (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts')
    Require-Contains $efbUi "const EFB_VERSION = '0.1.140'" 'R4R9 EFB version'
    Require-Contains $efbUi 'SIMVOICE_1_1_2_0_R4R9_USER_CAMERA_NATIVE_HIGHLIGHT' 'R4R9 native highlight preservation'
    Require-Contains $efbUi 'SIMVOICE_1_1_2_0_R4R9_USER_CAMERA_EXPLICIT_CLEAR' 'R4R9 explicit CAM clear'
    Require-Contains $efbUi "'simvoice-auto-user-camera'" 'R4R9 automatic helper + user camera origin'
    Require-Contains $efbUi "'simvoice-manual-user-camera'" 'R4R9 manual helper + user camera origin'
    Require-Contains $efbUi 'scheduleUserCameraBindingAfterStartIssued' 'R4R9 camera-after-highlight scheduling'
    Require-Contains $efbUi "'native-highlight-user-camera'" 'R4R9 forced user camera after helper settle'
    Require-Contains $efbUi 'CLEAR CAM' 'R4R9 clear CAM control'
    Require-Contains $efbUi 'BORRAR CAM' 'R4R9 Spanish clear CAM control'
    Require-Contains $efbUi 'curatedFactoryPreserved=true' 'R4R9 clear preserves curated/factory map'
    Require-Contains $efbUi 'normal-camera-hierarchy-restored' 'R4R9 immediate fallback after clear'
    Require-Contains $efbUi 'isManualChecklistHelperOrigin' 'R4R9 manual helper lifetime ownership'

    $controller = Read-RequiredText (Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs')
    Require-Contains $controller 'native-start-help-user-camera' 'R4R9 Windows user camera fallback path'
    Require-Contains $controller 'checklist-user-camera-focus' 'R4R9 Windows user camera focus path'
    Require-Contains $controller 'ChecklistCameraBindingStore.Clear' 'R4R9 user override clear path'
    # Both user-camera paths must force dispatch after a helper may have moved the camera.
    if ($controller -notmatch 'native-start-help-user-camera"\s*,\s*true\s*,') {
        throw 'R4R9 native START_HELP user camera dispatch is not forced.'
    }
    if ($controller -notmatch 'checklist-user-camera-focus"\s*,\s*true\s*,') {
        throw 'R4R9 manual/automatic user camera focus dispatch is not forced.'
    }

    # Advanced Actions R4R9 UX/catalog/theme/restart/display separation.
    $advanced = Read-RequiredText (Join-Path $WindowsProjectRoot 'AdvancedSimulatorActions.cs')
    $advancedForm = Read-RequiredText (Join-Path $WindowsProjectRoot 'AdvancedSimulatorActionsForm.cs')
    Require-Contains $advanced 'SIMVOICE_1_1_2_0_R4R8_ADVANCED_SIMULATOR_ACTIONS' 'Advanced Actions runtime continuity'
    Require-Contains $advanced 'SIMVOICE_1_1_2_0_R4R9_ADVANCED_ACTION_UX' 'R4R9 Advanced UX contract'
    Require-Contains $advanced 'GetDisplayTarget' 'R4R9 internal/display target separation'
    Require-Contains $advanced 'ADVANCED_ACTION:' 'Advanced internal namespace retained'
    Require-Contains $advancedForm 'ThemeManager.Apply(this)' 'Advanced window theme integration'
    Require-Contains $advancedForm 'EM_SETCUEBANNER' 'Advanced placeholders'
    Require-Contains $advancedForm 'ConfigurationHelp.ShowAdvancedSimulatorActions' 'Advanced Help button'
    Require-Contains $advancedForm 'LoadKeyEventNamesAsync' 'Advanced SDK Key Event suggestions'
    Require-Contains $advancedForm 'LoadInputEventTargetsFastAsync' 'Advanced live Input Event suggestions'
    Require-Contains $advancedForm 'The Event field remains editable for addon-specific codes.' 'Advanced non-whitelist contract'
    Require-Contains $advancedForm 'ADVANCED_ACTION_VOICE_RESTART_ARMED' 'Advanced voice grammar safe restart'
    Require-Contains $advancedForm 'ArmRestoreAfterCommandBuilderRestart' 'Advanced voice restart checklist preservation'
    Require-Contains $advancedForm 'ReiniciadorAplicacion.Reiniciar' 'Advanced voice full-process safe restart'

    $help = Read-RequiredText (Join-Path $WindowsProjectRoot 'ConfigurationHelp.cs')
    Require-Contains $help 'ShowAdvancedSimulatorActions' 'Advanced Actions Help implementation'
    Require-Contains $help 'SENT' 'Advanced Help SENT semantics'
    Require-Contains $help 'VERIFIED' 'Advanced Help VERIFIED semantics'

    $mapper = Read-RequiredText (Join-Path $WindowsProjectRoot 'CommandMapperForm.cs')
    Require-Contains $mapper 'AdvancedSimulatorActionStore.GetDisplayTarget' 'Voice command grid friendly Advanced display'

    $builder = Read-RequiredText (Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs')
    Require-Contains $builder 'user-advanced-simulator-action' 'Builder pre-existing Advanced action catalog'
    Require-Contains $builder 'AdvancedSimulatorActionStore.GetDisplayTarget' 'Builder plan friendly Advanced display'
    Require-Contains $builder 'Builder never invents or executes raw' 'Builder no raw invention contract'

    # Security boundary remains MSFS-only.
    $securityCombined = $advanced + "`n" + $advancedForm
    foreach ($forbidden in @('Process.Start','powershell.exe','cmd.exe','System.Diagnostics.Process')) {
        Require-NotContains $securityCombined $forbidden 'Advanced Actions OS execution boundary'
    }

    # EFB build script must publish/sync the new R4R9 version.
    $efbBuild = Read-RequiredText (Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1')
    Require-Contains $efbBuild '$ExpectedEfbVersion = "0.1.140"' 'R4R9 EFB build version'

    Write-Host 'QA STATIC/SOURCE: PASS' -ForegroundColor Green
    Write-Host 'Windows: 1.1.2.0 | EFB: 0.1.140 | WASM/Backend: unchanged' -ForegroundColor Green
    Write-Host 'Physical QA still required: Settings 100/125/150%, CAM highlight/execution/clear fallback, Advanced theme/help/catalog/restart/display, regression.' -ForegroundColor Yellow
    exit 0
}
catch {
    Write-Host ('QA STATIC/SOURCE: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
