[CmdletBinding()]
param(
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputDirectory = Join-Path $projectRoot "QA-Runs\GuidedChecklistFocus\Focus-$stamp"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Read-PassFail {
    param([Parameter(Mandatory=$true)][string]$Question)
    while ($true) {
        $answer = (Read-Host "$Question (Y/N)").Trim()
        if ($answer.StartsWith("Y", [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($answer.StartsWith("N", [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
}

Write-Host ""
Write-Host "SimVoice Copilot 1.0.19.0 - Guided Voice Checklist Focus R10 QA" -ForegroundColor Cyan
Write-Host ""
Write-Host "Preconditions" -ForegroundColor Yellow
Write-Host "1. MSFS 2024 is running with the same C172 G1000 (or another aircraft with working native checklist eye helpers)."
Write-Host "2. SimVoice Copilot 1.0.19.0 QA is connected to FS2024."
Write-Host "3. Configuration -> MSFS 2024 components shows Included 0.1.20 | Installed 0.1.20."
Write-Host "4. The in-sim EFB shows EFB v0.1.20 at the bottom-left edge."
Write-Host ""
Read-Host "Press ENTER when ready"

$started = Get-Date
$results = New-Object System.Collections.Generic.List[object]

function Add-Result([string]$Id,[string]$Question) {
    $ok = Read-PassFail $Question
    $results.Add([pscustomobject]@{ id=$Id; success=$ok })
}

Add-Result 'EFB_VERSION_0120_BOTTOM_EDGE' 'Does the EFB show EFB v0.1.20 at the absolute bottom-left edge?'
Add-Result 'EFB_FOCUS_CONTROLS_VISIBLE' 'For an item with a native visual helper, are both Auto and Focus/Enfocar visible?'
Add-Result 'AUTO_FOCUS_ENABLED' 'With Auto enabled, did entering a visual-helper item automatically focus/highlight the correct control?'
Add-Result 'FOCUS_TO_NO_HELPER_RESETS' 'Advance from a focused item to an item WITHOUT a visual helper. Did the highlight clear AND the camera return immediately to the default Pilot cockpit view?'
Add-Result 'AUTO_FOCUS_DISABLED' 'Turn Auto OFF and advance to another visual-helper item. Did it advance WITHOUT automatically moving the camera?'
Add-Result 'MANUAL_FOCUS_WITH_AUTO_OFF' 'With Auto OFF, press Focus/Enfocar. Did it focus/highlight the correct control?'
Add-Result 'MANUAL_FOCUS_END_RESETS' 'After that manual focus, confirm/complete the item. Did the camera return to the default Pilot view immediately, regardless of whether the next item has a helper?'
Add-Result 'AUTO_FOCUS_REENABLED' 'Turn Auto ON again. Did automatic focus resume on the next visual-helper item?'
Add-Result 'CAMERA_RESET_ON_COMPLETE' 'Complete a checklist while focused. Did highlight clear AND camera return to default Pilot view BEFORE pressing Siguiente checklist?'
Add-Result 'NEXT_LIST_NO_DELAYED_RESET' 'After completion, press Siguiente checklist. Did it avoid any delayed camera reset belonging to the previous list?'
Add-Result 'WINDOWS_CHECKLIST_TAB_SELECTION_ANY_STATE' 'In Windows SVC, while a checklist is RUNNING, press the already-active Checklist tab again. Did it immediately reset/abandon the list and silently show checklist selection?'
Add-Result 'EFB_CHECKLIST_TAB_SELECTION_ANY_STATE' 'In the in-sim EFB, while a checklist is RUNNING and Checklist is already active, press Checklist again. Did it immediately reset/abandon the list and silently show the REAL list selector?'
Add-Result 'EFB_SELECTION_SCROLLS' 'With more lists than fit on screen, can you scroll the EFB list selector by touch/drag (and wheel if available)?'
Add-Result 'EFB_SELECTION_STARTS_CHOSEN_LIST' 'From that EFB selector, choose a list. Did SVC start exactly the selected list?'
Add-Result 'NO_UNSOLICITED_CONFIRM_WHILE_SILENT' 'On a normal item, remain completely silent for at least 5 seconds after the prompt. Did SVC stay on the same item?'
Add-Result 'AUTO_FOCUS_PERSISTENCE' 'If Auto was changed, did its setting remain preserved after reopening SVC/EFB?'

$failed = @($results | Where-Object { -not $_.success })
$report = [ordered]@{
    suite = 'GuidedChecklistFocus-1.0.19.0-R10-lifecycle-selector'
    startedAt = $started.ToString('o')
    finishedAt = (Get-Date).ToString('o')
    results = @($results)
    success = ($failed.Count -eq 0)
}

$reportPath = Join-Path $OutputDirectory 'guided-checklist-focus-result.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ""
if ($report.success) {
    Write-Host "Guided Checklist Focus R10 QA: PASS" -ForegroundColor Green
    Write-Host "Report: $reportPath" -ForegroundColor DarkGray
    exit 0
}

Write-Host "Guided Checklist Focus R10 QA: FAIL" -ForegroundColor Red
Write-Host "Report: $reportPath" -ForegroundColor DarkGray
Write-Host "Generate a SimVoice Support Package immediately after any failed camera/selection transition." -ForegroundColor Yellow
exit 1
