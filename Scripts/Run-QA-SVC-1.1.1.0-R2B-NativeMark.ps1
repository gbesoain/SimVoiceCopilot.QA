#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp",
    [string]$EfbProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS"
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Path, [string]$Needle, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ("Missing file: {0}" -f $Path) }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing in {1}: {2}" -f $Label, $Path, $Needle)
    }
}

$controller = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$app = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$build = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

Assert-Contains $app "const EFB_VERSION = '0.1.105';" 'R2B EFB version'
Assert-Contains $app 'SIMVOICE_1_1_1_0_MARK_HIGHLIGHT_ONLY_R2' 'R2 direct MARK marker'
Assert-Contains $app 'SIMVOICE_1_1_1_0_MARK_NATIVE_HELPER_R2B' 'R2B native helper marker'
Assert-Contains $app 'toggleNativeChecklistMarker' 'R2B native mark toggle'
Assert-Contains $app "'simvoice-mark'" 'R2B native mark ownership'
Assert-Contains $app "checklist.camera.restore_previous_probe" 'R2B camera return probe'
Assert-Contains $app "native-mark-settled" 'R2B settled probe'
Assert-Contains $app "origin !== 'simvoice-mark'" 'R2B suppress native camera fallback'
Assert-Contains $app "this.nativeChecklistMarkTarget === checklist.currentTarget" 'R2B local MARK active state'
Assert-Contains $controller 'snapshot.CurrentNativeVisualHelperAvailable &&' 'R2B native MARK capability'
Assert-Contains $controller 'snapshot.CurrentTarget.StartsWith("native:"' 'R2B native target gate'
Assert-Contains $controller 'Msfs2024FocusInstrumentBridge.IsAvailable' 'R2 direct identifier path preserved'
Assert-Contains $build '$ExpectedEfbVersion = "0.1.105"' 'R2B build version'
Assert-Contains $build 'SIMVOICE_1_1_1_0_MARK_NATIVE_HELPER_R2B' 'R2B build gate'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2B NATIVE MARK SOURCE QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
