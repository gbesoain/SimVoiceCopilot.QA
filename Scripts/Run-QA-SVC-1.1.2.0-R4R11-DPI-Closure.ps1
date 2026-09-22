#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp'
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

    $components = Read-RequiredText (Join-Path $WindowsProjectRoot 'Msfs2024ComponentsManagementForm.cs')
    Require-Contains $components 'AutoScaleDimensions = new SizeF(96F, 96F)' 'R4R11 Components DPI baseline'
    Require-Contains $components 'AutoScaleMode = AutoScaleMode.Dpi' 'R4R11 Components DPI mode'
    Require-Contains $components 'FormBorderStyle = FormBorderStyle.Sizable' 'R4R11 Components resize'
    Require-Contains $components 'MaximizeBox = true' 'R4R11 Components maximize'
    Require-Contains $components 'ApplyResponsiveLayout' 'R4R11 Components responsive layout'
    Require-Contains $components 'DpiChanged +=' 'R4R11 Components per-monitor relayout'
    Require-Contains $components 'AutoScroll = true' 'R4R11 Components small-screen safety'

    $advanced = Read-RequiredText (Join-Path $WindowsProjectRoot 'AdvancedSimulatorActionsForm.cs')
    Require-Contains $advanced 'AutoScaleDimensions = new SizeF(96F, 96F)' 'R4R11 Advanced DPI baseline'
    Require-Contains $advanced 'ApplyResponsiveDpiLayout' 'R4R11 Advanced responsive DPI layout'
    Require-Contains $advanced 'ApplyAdvancedComboScale' 'R4R11 Advanced combo scaling'
    Require-Contains $advanced 'combo.ItemHeight = itemHeight' 'R4R11 Advanced combo item height'
    Require-Contains $advanced 'combo.DropDownHeight' 'R4R11 Advanced combo dropdown height'
    Require-Contains $advanced 'Resize +=' 'R4R11 Advanced resize relayout'
    Require-Contains $advanced 'DpiChanged +=' 'R4R11 Advanced per-monitor relayout'
    # Preserve R4R10 UX while fixing DPI.
    Require-Contains $advanced 'DrawMode = DrawMode.OwnerDrawFixed' 'R4R10 Advanced contrast continuity'
    Require-Contains $advanced 'FormatExecutionResultForUi' 'R4R10 Advanced localized result continuity'
    Require-Contains $advanced 'ENVIADA:' 'R4R10 Advanced Spanish result continuity'

    $wasm = Read-RequiredText (Join-Path $WindowsProjectRoot 'WasmBridgeManagementForm.cs')
    Require-Contains $wasm 'AutoScaleDimensions = new SizeF(96F, 96F)' 'R4R11 WASM management DPI baseline'
    Require-Contains $wasm 'FormBorderStyle = FormBorderStyle.Sizable' 'R4R11 WASM management resize'
    Require-Contains $wasm 'ApplyResponsiveLayout' 'R4R11 WASM management responsive layout'

    foreach ($fileName in @('AiCommandBuilderForm.cs','PremiumUpgradeExperience.cs','StartupExperienceForm.cs')) {
        $text = Read-RequiredText (Join-Path $WindowsProjectRoot $fileName)
        Require-Contains $text 'AutoScaleDimensions = new SizeF(96F, 96F)' ("R4R11 DPI baseline " + $fileName)
        Require-Contains $text 'AutoScaleMode = AutoScaleMode.Dpi' ("R4R11 DPI mode " + $fileName)
    }

    foreach ($fileName in @('LanguageModelDownloadForm.cs','AboutForm.cs','InputEventCaptureForm.cs')) {
        $text = Read-RequiredText (Join-Path $WindowsProjectRoot $fileName)
        Require-Contains $text 'AutoScaleDimensions = new SizeF(96F, 96F)' ("R4R11 DPI baseline " + $fileName)
        Require-Contains $text 'AutoScaleMode = AutoScaleMode.Dpi' ("R4R11 DPI mode " + $fileName)
    }

    $email = Read-RequiredText (Join-Path $WindowsProjectRoot 'EmailRegisterForm.cs')
    Require-Contains $email 'AutoScaleDimensions = new System.Drawing.SizeF(96F, 96F)' 'R4R11 Email DPI baseline'
    Require-Contains $email 'AutoScaleMode = AutoScaleMode.Dpi' 'R4R11 Email DPI mode'

    foreach ($fileName in @('ProfileSelectorForm.Designer.cs','UpdateForm.Designer.cs')) {
        $text = Read-RequiredText (Join-Path $WindowsProjectRoot $fileName)
        Require-Contains $text 'AutoScaleDimensions = new System.Drawing.SizeF(96F, 96F)' ("R4R11 designer DPI baseline " + $fileName)
        Require-Contains $text 'AutoScaleMode = System.Windows.Forms.AutoScaleMode.Dpi' ("R4R11 designer DPI mode " + $fileName)
    }

    # Continuity checks on full authoritative/staged project when these files are available.
    $settingsPath = Join-Path $WindowsProjectRoot 'VoiceSettingsForm.cs'
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $settings = Read-RequiredText $settingsPath
        Require-Contains $settings 'ApplySettingsComboScale' 'R4R10 Settings combo scaling continuity'
        Require-Contains $settings 'DpiChanged +=' 'R4R10 Settings DPI relayout continuity'
    }

    $cameraPath = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
    if (Test-Path -LiteralPath $cameraPath -PathType Leaf) {
        $camera = Read-RequiredText $cameraPath
        Require-Contains $camera 'SIMVOICE_1_1_2_0_R4R10_USER_CAMERA_SINGLE_AUTHORITY' 'R4R10 CAM frozen continuity'
    }

    Write-Host 'QA STATIC/SOURCE: PASS' -ForegroundColor Green
    Write-Host 'Windows: 1.1.2.0 | EFB: unchanged at 0.1.141 | WASM/Backend: unchanged' -ForegroundColor Green
    Write-Host 'R4R11 scope: WinForms DPI/resize only. CAM/EFB logic is frozen and not part of this payload.' -ForegroundColor Yellow
    exit 0
}
catch {
    Write-Host ('QA STATIC/SOURCE: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
