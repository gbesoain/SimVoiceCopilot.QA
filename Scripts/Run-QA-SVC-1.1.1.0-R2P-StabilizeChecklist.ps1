#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WindowsProjectRoot,
    [Parameter(Mandatory=$true)][string]$EfbProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Path,[string]$Needle,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ("Missing {0}: {1}" -f $Label,$Path) }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) { throw ("{0} missing: {1}" -f $Label,$Needle) }
}

function Assert-NotContains {
    param([string]$Path,[string]$Needle,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ("Missing {0}: {1}" -f $Label,$Path) }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle,[System.StringComparison]::Ordinal) -ge 0) { throw ("{0} still contains retired token: {1}" -f $Label,$Needle) }
}

$main = Join-Path $WindowsProjectRoot 'MainForm.cs'
$persistence = Join-Path $WindowsProjectRoot 'ChecklistSessionPersistenceService.cs'
$builder = Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs'
$focusBridge = Join-Path $WindowsProjectRoot 'Msfs2024FocusInstrumentBridge.cs'
$controller = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$efb = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$nativeBridge = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\native\NativeChecklistBridge.ts'
$runtimeProbe = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\native\MarkRuntimeSidecarProbe.ts'
$markSidecar = Join-Path $WindowsProjectRoot 'MarkCompatibilitySidecar.cs'

Assert-Contains $persistence 'SIMVOICE_1_1_1_0_R2P_COMMAND_BUILDER_CHECKLIST_RESUME_SCOPE' 'Checklist restart scope'
Assert-Contains $persistence 'TryConsumeRestoreAfterCommandBuilderRestart' 'Checklist restart scope consume'
Assert-Contains $builder 'ArmRestoreAfterCommandBuilderRestart' 'AI Builder one-shot resume arm'
Assert-Contains $main 'CHECKLIST_SESSION_RESTORE_SCOPE_SKIPPED' 'Normal-startup resume suppression'
Assert-Contains $main '!checklistRestoreAuthorizedForStartup' 'Restore authorization gate'

Assert-Contains $controller 'SIMVOICE_1_1_1_0_R2P_MARK_REFROZEN' 'Windows MARK freeze'
Assert-NotContains $focusBridge 'TryMarkHighlight2024' 'FOCUS baseline bridge'
Assert-Contains $focusBridge 'public static bool TryFocus(' 'FOCUS baseline bridge'

Assert-Contains $nativeBridge 'SIMVOICE_HF30F_NATIVE_CHECKLIST_BRIDGE' 'Native checklist bridge baseline'
Assert-NotContains $nativeBridge 'MarkRuntimeSidecarProbe' 'R2L runtime MARK observer removed from active bridge'
if (Test-Path -LiteralPath $runtimeProbe -PathType Leaf) { throw ('Retired R2L runtime probe still present: ' + $runtimeProbe) }
if (Test-Path -LiteralPath $markSidecar -PathType Leaf) { throw ('Retired R2M Windows MARK sidecar still present: ' + $markSidecar) }

Assert-Contains $efb "const EFB_VERSION = '0.1.117';" 'EFB version'
Assert-Contains $efb 'SIMVOICE_1_1_1_0_R2P_MARK_REFROZEN' 'EFB MARK freeze'
Assert-Contains $efb 'SIMVOICE_1_1_1_0_R2P_EFB_CHECKLIST_TAB_AUTO_REFRESH' 'EFB checklist auto refresh'
Assert-Contains $efb "const autoFocusEnabled = checklist.autoFocusEnabled !== false;" 'AUTO independent from MARK'
Assert-NotContains $efb 'focusControls.append(autoButton, markButton, focusButton)' 'MARK UI removed'

Write-Host '============================================================'
Write-Host ' SVC 1.1.1.0 R2P STABILIZE AUTO/FOCUS + CHECKLIST STARTUP QA: PASS'
Write-Host '============================================================'
Write-Host 'MARK is re-frozen. AUTO/FOCUS are restored to R2K authority.'
Write-Host 'Checklist resume is scoped to AI Command Builder Finish Edit / Restart.'
Write-Host 'Checklist tab can request catalog refresh directly from the EFB.'
exit 0
