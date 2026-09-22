#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-RequiredText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing required file: $Path" }
    return [IO.File]::ReadAllText($Path)
}
function Require-Contains {
    param([string]$Text,[string]$Needle,[string]$Label)
    if ($Text.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "$Label missing: $Needle" }
}

try {
    $version = Read-RequiredText (Join-Path $WindowsProjectRoot 'Version.props')
    Require-Contains $version '<SimVoiceVersion>1.1.3.0</SimVoiceVersion>' 'Windows version'
    Require-Contains $version '<SimVoiceDisplayVersion>1.1.3.0</SimVoiceDisplayVersion>' 'Windows display version'

    $controller = Read-RequiredText (Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs')
    Require-Contains $controller 'SIMVOICE_1_1_3_0_R1_USER_CAMERA_NO_NATIVE_HELPER_DIRECT' 'R1 continuity'
    Require-Contains $controller 'SIMVOICE_1_1_3_0_R2_FIRST_ITEM_CAMERA_SETTLE' 'R2 marker'
    Require-Contains $controller 'bool justStarted = guidedChecklistStateInitialized' 'R2 checklist-start transition detection'
    Require-Contains $controller 'checklist-start-first-item' 'R2 first-item reason'
    Require-Contains $controller 'ScheduleFirstItemUserCameraReplay' 'R2 replay scheduler'
    Require-Contains $controller 'ReplayFirstItemUserCameraAfterChecklistStartAsync' 'R2 delayed replay method'
    Require-Contains $controller 'await Task.Delay(750).ConfigureAwait(false)' 'R2 settle delay'
    Require-Contains $controller 'checklist-start-first-item-settled' 'R2 replay reason'
    Require-Contains $controller 'BuildGuidedChecklistItemKey(live)' 'R2 same-item guard'
    Require-Contains $controller 'live.CurrentTarget ?? string.Empty' 'R2 same-target guard'
    Require-Contains $controller 'ChecklistCameraBindingStore.TryGet(live' 'R2 live binding guard'
    Require-Contains $controller 'ChecklistCameraBindingDispatcher.TryDispatch(' 'R2 dispatcher reuse'
    Require-Contains $controller '"CHECKLIST_USER_CAMERA_FIRST_ITEM_SETTLED_REPLAY"' 'R2 diagnostic category'

    Write-Host 'QA STATIC/SOURCE: PASS' -ForegroundColor Green
    Write-Host 'Windows/MSIX: 1.1.3.0 | EFB/WASM/Backend unchanged' -ForegroundColor Green
    Write-Host 'R2 scope: delayed first-item replay only for generic native items without a runtime helper.' -ForegroundColor Yellow
    exit 0
}
catch {
    Write-Host ('QA STATIC/SOURCE: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
