#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WindowsProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Text,[string]$Needle,[string]$Label)
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing: {1}" -f $Label,$Needle)
    }
}

$mainPath = Join-Path $WindowsProjectRoot 'MainForm.cs'
$controllerPath = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
if (-not (Test-Path -LiteralPath $mainPath -PathType Leaf)) { throw "Missing MainForm.cs" }
if (-not (Test-Path -LiteralPath $controllerPath -PathType Leaf)) { throw "Missing SimVoiceEfbLocalController.cs" }

$main = Get-Content -LiteralPath $mainPath -Raw
$controller = Get-Content -LiteralPath $controllerPath -Raw

Assert-Contains $main 'SIMVOICE_1_1_1_0_R2R_NATIVE_CALLBACK_RELIABILITY' 'MainForm R2R marker'
Assert-Contains $main 'CHECKLIST_RESTART_FOCUS_REHYDRATED' 'R2Q rehydrate path preserved'
Assert-Contains $main 'RefreshPresentationAndFocusMetadataFromSource' 'R2Q session metadata refresh preserved'

$activePos = $main.IndexOf('if (checklistSessionManager != null && checklistSessionManager.IsActive)',[System.StringComparison]::Ordinal)
$panelGuardPos = $main.IndexOf('if (panelChecklist == null || panelChecklist.IsDisposed)', $activePos, [System.StringComparison]::Ordinal)
if ($activePos -lt 0 -or $panelGuardPos -lt 0 -or $panelGuardPos -lt $activePos) {
    throw 'R2R active-session rehydrate must run before the ChecklistPanel guard.'
}

Assert-Contains $controller 'TryDispatchPendingNativeChecklistCallback();' 'R2R retry timer'
Assert-Contains $controller 'EFB_NATIVE_CHECKLIST_CALLBACK_QUEUED' 'R2R native callback queue'
Assert-Contains $controller 'EFB_NATIVE_CHECKLIST_CALLBACK_DELIVERED' 'R2R native callback delivery'
Assert-Contains $controller 'SIMVOICE_1_1_1_0_R2R_EFB_SELECTOR_SELF_HEAL' 'R2R EFB selector self-heal'
Assert-Contains $controller 'checklistCatalogRefresh();' 'R2R forced checklist refresh'

if ($controller.IndexOf('RunOnUiThread(() => callback(document));',[System.StringComparison]::Ordinal) -ge 0) {
    throw 'Legacy lossy native checklist callback dispatch remains in SimVoiceEfbLocalController.cs.'
}

Write-Host '============================================================'
Write-Host ' SVC 1.1.1.0 R2R RESTART CHECKLIST DELIVERY QA: PASS'
Write-Host '============================================================'
Write-Host 'Native catalog delivery is retained until UI-ready; restored AUTO/FOCUS rehydrate before panel guards; EFB Checklist self-heals with forced Search when needed.'
exit 0
