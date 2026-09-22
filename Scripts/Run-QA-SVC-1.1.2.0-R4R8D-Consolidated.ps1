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
    $version = Read-RequiredText (Join-Path $WindowsProjectRoot 'Version.props')
    Require-Contains $version '<SimVoiceVersion>1.1.2.0</SimVoiceVersion>' 'Windows version'
    Require-Contains $version '<SimVoiceDisplayVersion>1.1.2.0</SimVoiceDisplayVersion>' 'Windows display version'

    # R4R7/R4R7A continuity.
    $capture = Read-RequiredText (Join-Path $WindowsProjectRoot 'ChecklistCameraBindingCaptureService.cs')
    Require-Contains $capture 'SIMVOICE_1_1_2_0_R4R7_USER_CAMERA_ASYNC_KEY_STATE_CAPTURE' 'R4R7 camera capture'
    Require-Contains $capture 'GetAsyncKeyState' 'R4R7 bounded physical key observation'

    $ifly = Read-RequiredText (Join-Path $WindowsProjectRoot 'Ifly737MaxCockpitCommandService.cs')
    Require-Contains $ifly 'SIMVOICE_1_1_2_0_R4R7_IFLY737MAX_COCKPIT_SDK_V15' 'R4R7 iFly cockpit SDK'
    $iflySdk = Read-RequiredText (Join-Path $WindowsProjectRoot 'Ifly737MaxSdk.cs')
    foreach ($member in @('CmdTaxiLightSet','CmdRunwayTurnoffLeftSet','CmdRunwayTurnoffRightSet','CmdEngine1StartSet','CmdEngine2StartSet','CmdApuSet','CmdXpndrReplySelectorSet','CmdBaroStdLeft','CmdBaroStdRight')) {
        Require-Contains $iflySdk $member ("R4R8D iFly SDK backward-compatibility member $member")
    }
    $legacySystemServicePath = Join-Path $WindowsProjectRoot 'Ifly737MaxSystemCommandService.cs'
    if (Test-Path -LiteralPath $legacySystemServicePath -PathType Leaf) {
        $legacySystemService = Read-RequiredText $legacySystemServicePath
        $matches = [regex]::Matches($legacySystemService, 'Ifly737MaxSdk\.([A-Za-z_][A-Za-z0-9_]*)')
        foreach ($match in $matches) {
            $member = $match.Groups[1].Value
            Require-Contains $iflySdk $member ("iFly SDK compatibility with authoritative SystemCommandService member $member")
        }
    }
    $checklist = Read-RequiredText (Join-Path $WindowsProjectRoot 'ChecklistPanel.cs')
    Require-Contains $checklist 'SIMVOICE_1_1_2_0_R4R7_NAMED_CHECKLIST_VOICE_START' 'R4R7 named checklist voice'

    $efbUi = Read-RequiredText (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts')
    Require-Contains $efbUi "const EFB_VERSION = '0.1.139'" 'R4R7A EFB version'
    Require-Contains $efbUi 'SIMVOICE_1_1_2_0_R4R7A_USER_CAMERA_IMMEDIATE_RECORDING' 'R4R7A immediate CAM UI'
    Require-Contains $efbUi 'SIMVOICE_1_1_2_0_R4R7A_USER_CAMERA_ITEM_ISOLATION' 'R4R7A per-item camera isolation'
    Require-Contains $efbUi "reason: 'checklist-item-changed'" 'R4R7A cancel capture on checklist item change'
    Require-Contains $efbUi 'R4R8D: camera state is used both by the button row and by the feedback panel' 'R4R8D camera feedback lexical-scope fix'

    # R1 Settings DPI/resize.
    $settingsDesigner = Read-RequiredText (Join-Path $WindowsProjectRoot 'VoiceSettingsForm.Designer.cs')
    $settings = Read-RequiredText (Join-Path $WindowsProjectRoot 'VoiceSettingsForm.cs')
    Require-Contains $settingsDesigner 'AutoScaleMode = System.Windows.Forms.AutoScaleMode.Dpi' 'Settings DPI autoscale'
    Require-Contains $settingsDesigner 'FormBorderStyle = System.Windows.Forms.FormBorderStyle.Sizable' 'Settings resizable border'
    Require-Contains $settingsDesigner 'MaximizeBox = true' 'Settings maximize'
    Require-Contains $settings 'SIMVOICE_1_1_2_0_R4R8_SETTINGS_DPI_RESIZE' 'R4R8 Settings contract'
    Require-Contains $settings 'pnlContenido.AutoScroll = true' 'Settings constrained-display scrolling'
    Require-Contains $settings 'Screen.FromControl(this).WorkingArea' 'Settings working-area clamp'
    Require-Contains $settings 'System.Drawing.Rectangle working' 'Settings System.Drawing Rectangle qualification'
    Require-Contains $settings 'MinimumSize = new System.Drawing.Size' 'Settings minimum size'
    Require-Contains $settings 'ApplyResponsiveSettingsLayout' 'Settings responsive layout'
    Require-Contains $settings 'DpiChanged +=' 'Settings per-monitor DPI relayout hook'
    Require-NotContains $settings 'ClientSize = new System.Drawing.Size(ClientSize.Width, 950)' 'Settings fixed 950 client height'
    Require-NotContains $settings 'ClientSize = new System.Drawing.Size(ClientSize.Width, 850)' 'Settings fixed 850 client height'

    # R2 model/executor/security.
    $advanced = Read-RequiredText (Join-Path $WindowsProjectRoot 'AdvancedSimulatorActions.cs')
    $advancedForm = Read-RequiredText (Join-Path $WindowsProjectRoot 'AdvancedSimulatorActionsForm.cs')
    Require-Contains $advanced 'SIMVOICE_1_1_2_0_R4R8_ADVANCED_SIMULATOR_ACTIONS' 'R4R8 Advanced Actions contract'
    foreach ($type in @('simconnect_event','k_event','input_event','h_event','lvar_write','rpn_expression')) {
        Require-Contains $advanced ('"' + $type + '"') "Advanced type $type"
    }
    Require-Contains $advanced 'SimConnectBridge.TrySendParameterizedEvent' 'Advanced SimConnect/K transport reuse'
    Require-Contains $advanced 'Msfs2024InputEventBridge.TrySetInputEventByNameAsync' 'Advanced Input Event transport reuse'
    Require-Contains $advanced 'SimVoiceWasmBridgeClient.ExecuteRpnAndReadAsync' 'Advanced H/L/RPN bridge reuse'
    Require-Contains $advanced 'prefix = "B:"' 'Input Event B: prefix normalization'
    Require-Contains $advanced 'string expression = "1 (>H:"' 'H Event RPN stack ordering'
    Require-Contains $advanced 'AdvancedActions' 'Advanced per-profile companion storage'
    Require-Contains $advanced 'File.Replace(temp, path, backup, true)' 'Advanced atomic persisted update'
    Require-Contains $advanced 'Verified successfully. LVar read-back matches' 'Advanced LVar verification distinction'
    Require-Contains $advanced 'The aircraft result was not read back' 'Advanced SENT vs VERIFIED distinction'

    $securityCombined = $advanced + "`n" + $advancedForm
    foreach ($forbidden in @('Process.Start','cmd.exe','powershell.exe','System.Diagnostics.Process')) {
        Require-NotContains $securityCombined $forbidden 'Advanced Actions OS execution boundary'
    }
    Require-Contains $advancedForm 'Test Action' 'Advanced Test Action UX'
    Require-Contains $advancedForm 'Any aircraft' 'Advanced aircraft scope UX'
    Require-Contains $advancedForm 'Parameterized Advanced Actions are not enabled in this MVP' 'Advanced constant-only MVP guard'
    Require-Contains $advancedForm 'FreemiumLimitedFeature.VoiceCommands' 'Existing Free voice-command limit preservation'

    # Normal command pipeline + Builder integration.
    $mapper = Read-RequiredText (Join-Path $WindowsProjectRoot 'CommandMapperForm.cs')
    Require-Contains $mapper 'btnAdvancedSimulatorActions' 'Advanced Actions command editor entry'
    Require-Contains $mapper 'AdvancedSimulatorActionStore.BuildTarget' 'Advanced actions event catalogue integration'
    Require-Contains $mapper 'AdvancedSimulatorActionStore.SaveForProfile' 'Advanced actions Save As preservation'

    $builder = Read-RequiredText (Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs')
    Require-Contains $builder 'user-advanced-simulator-action' 'Builder existing-action semantic catalog'
    Require-Contains $builder 'ActionType = "advanced_action"' 'Builder advanced action type'
    Require-Contains $builder 'Builder never invents or executes raw' 'Builder no raw-code invention contract'

    $vosk = Read-RequiredText (Join-Path $WindowsProjectRoot 'VoskRecognizer.cs')
    Require-Contains $vosk 'SIMVOICE_1_1_2_0_R4R8_ADVANCED_ACTION_PIPELINE' 'Advanced runtime pipeline'
    Require-Contains $vosk 'AdvancedSimulatorActionExecutor' 'Advanced runtime executor'
    Require-Contains $vosk 'plannedActionType == "advanced_action"' 'Advanced Group/Builder runtime route'

    # Preserve prior key contracts if present in payload/SOT.
    $telemetryPath = Join-Path $WindowsProjectRoot 'FreemiumTelemetryMilestoneService.cs'
    if (Test-Path -LiteralPath $telemetryPath -PathType Leaf) {
        $telemetry = Read-RequiredText $telemetryPath
        foreach ($evt in @('free_app_activated','free_meaningful_usage','premium_upgrade_prompt_shown')) {
            Require-Contains $telemetry $evt 'Freemium Telemetry R2 preservation'
        }
    }
    $speechPath = Join-Path $WindowsProjectRoot 'SpeechManager.cs'
    if (Test-Path -LiteralPath $speechPath -PathType Leaf) {
        Require-Contains (Read-RequiredText $speechPath) 'SIMVOICE_1_1_2_0_R4R6A_NEURAL_PROVIDER_CONSISTENCY' 'Neural provider consistency preservation'
    }

    Write-Host 'QA STATIC/SOURCE: PASS' -ForegroundColor Green
    Write-Host 'Windows: 1.1.2.0 | EFB: 0.1.139 | WASM: unchanged' -ForegroundColor Green
    Write-Host 'Physical QA is still required for R4R7A CAM, Settings DPI matrix, and simulator execution of Advanced Actions.' -ForegroundColor Yellow
    exit 0
}
catch {
    Write-Host ('QA STATIC/SOURCE: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
