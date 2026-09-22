#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp",
    [string]$EfbProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS"
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Path, [string]$Needle, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Missing file for {0}: {1}" -f $Label, $Path)
    }

    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing in {1}: {2}" -f $Label, $Path, $Needle)
    }
}

function Assert-NotContains {
    param([string]$Path, [string]$Needle, [string]$Label)
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) {
        throw ("{0} unexpectedly present in {1}: {2}" -f $Label, $Path, $Needle)
    }
}

$controller = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$app = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$i18n = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\core\i18n.ts'
$build = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

Assert-Contains $app "const EFB_VERSION = '0.1.106';" 'R2C EFB version'
Assert-Contains $app 'SIMVOICE_1_1_1_0_MARK_PERSISTENT_MODE_R2C' 'persistent MARK marker'
Assert-Contains $app 'SIMVOICE_1_1_1_0_MARK_NATIVE_ASYNC_NO_CAMERA_R2C' 'native async MARK marker'
Assert-Contains $app 'private checklistMarkModeEnabled = false;' 'persistent MARK mode state'
Assert-Contains $app 'private checklistMarkAppliedItemIdentity' 'per-item MARK application ownership'
Assert-Contains $app 'void this.updatePersistentChecklistMarkMode(checklist, previousChecklist);' 'MARK state advancement hook'
Assert-Contains $app 'markButton.disabled = false;' 'MARK available on non-highlightable items'
Assert-Contains $app 'void this.setChecklistMarkMode(!this.checklistMarkModeEnabled, checklist);' 'MARK persistent toggle'
Assert-Contains $app 'if (enabled && this.checklistMarkModeEnabled)' 'AUTO disables MARK first'
Assert-Contains $app "await this.transport.sendAction('checklist.autofocus.set', { enabled: false });" 'MARK disables AUTO'
Assert-Contains $app "await this.transport.sendAction('checklist.mark.clear'" 'explicit direct MARK cleanup'
Assert-Contains $controller 'case "checklist.mark.clear":' 'Windows direct MARK clear route'

# Exact direct-ID path remains camera-free.
Assert-Contains $controller 'Msfs2024FocusInstrumentBridge.TryFocus(' 'direct FocusInstrumentAction path'
Assert-Contains $controller 'false,' 'direct MARK SetCamera false'

# Native helper-only path must not await START_HELP before scheduling camera return.
# R2C uses the already validated/captured coherentCall function so TypeScript keeps
# the function narrow inside the asynchronous callback.
Assert-Contains $app "startPromise = coherentCall('CHECKLIST_START_HELP', pageId, checkpointId);" 'native MARK START_HELP issued asynchronously'
Assert-Contains $app 'R2C KEY CHANGE: do not await START_HELP' 'native MARK non-blocking rationale'
Assert-NotContains $app 'toggleNativeChecklistMarker' 'old one-shot native MARK toggle removed'
Assert-Contains $app "window.setTimeout(() => { void probe('early'); }, 20);" 'early camera return probe'
Assert-Contains $app "window.setTimeout(() => { void probe('settled'); }, 620);" 'settled camera return probe'
Assert-Contains $app "window.setTimeout(() => { void probe('late'); }, 1250);" 'late camera return probe'
Assert-Contains $app 'MARK remains ON and simply waits for the' 'no-helper item preserves MARK mode'

Assert-Contains $i18n 'Keep MARK on and highlight supported cockpit controls as the checklist advances' 'MARK mode hint EN'
Assert-Contains $i18n 'Mantener MARCAR activo y resaltar los controles compatibles al avanzar la checklist' 'MARK mode hint ES'

Assert-Contains $build '$ExpectedEfbVersion = "0.1.106"' 'R2C build version'
Assert-Contains $build 'SIMVOICE_1_1_1_0_MARK_PERSISTENT_MODE_R2C' 'R2C build persistent gate'
Assert-Contains $build 'SIMVOICE_1_1_1_0_MARK_NATIVE_ASYNC_NO_CAMERA_R2C' 'R2C build async gate'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2C PERSISTENT MARK SOURCE QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
