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
Write-Host "SimVoice Copilot 1.0.19.0 - Guided Voice Checklist Focus QA" -ForegroundColor Cyan
Write-Host ""
Write-Host "Preconditions" -ForegroundColor Yellow
Write-Host "1. Run MSFS 2024 and load an aircraft with a native checklist that exposes visual helpers." -ForegroundColor Yellow
Write-Host "2. Recommended first target: Cessna 172 G1000 or another default aircraft whose native EFB checklist eye button focuses cockpit controls." -ForegroundColor Yellow
Write-Host "3. Run the current private/QA SimVoice Copilot build and confirm Flight Simulator: Connected." -ForegroundColor Yellow
Write-Host "4. Open the SimVoice Copilot EFB and select the Checklist tab." -ForegroundColor Yellow
Write-Host ""
Read-Host "Press ENTER when ready"

$started = Get-Date
$results = New-Object System.Collections.Generic.List[object]

$version = Read-PassFail "Does the EFB show EFB v0.1.18 at the absolute bottom-left edge?"
$results.Add([pscustomobject]@{ id='EFB_VERSION_0117_BOTTOM_EDGE'; success=$version })

$buttonVisible = Read-PassFail "For an item with a native visual helper, are both Auto and Focus/Enfocar visible in the current-item card?"
$results.Add([pscustomobject]@{ id='EFB_FOCUS_CONTROLS_VISIBLE'; success=$buttonVisible })

$autoOn = Read-PassFail "With Auto enabled, advance to a visual-helper item. Did MSFS automatically highlight/focus the correct cockpit control?"
$results.Add([pscustomobject]@{ id='AUTO_FOCUS_ENABLED'; success=$autoOn })

$autoOff = Read-PassFail "Turn Auto OFF, then advance to another visual-helper item. Did the checklist advance WITHOUT automatically moving/focusing the camera?"
$results.Add([pscustomobject]@{ id='AUTO_FOCUS_DISABLED'; success=$autoOff })

$manual = Read-PassFail "While Auto is OFF, press Focus/Enfocar. Did MSFS still highlight/focus the correct cockpit control?"
$results.Add([pscustomobject]@{ id='MANUAL_FOCUS_WITH_AUTO_OFF'; success=$manual })

$autoRestore = Read-PassFail "Turn Auto ON again and advance to another visual-helper item. Did automatic focus resume?"
$results.Add([pscustomobject]@{ id='AUTO_FOCUS_REENABLED'; success=$autoRestore })

$noHelper = Read-PassFail "On an item with no visual helper (if available), did the checklist continue normally without a broken Focus control or error?"
$results.Add([pscustomobject]@{ id='NO_HELPER_FALLBACK'; success=$noHelper })

$silent = Read-PassFail "On one normal voice-confirmation item, remain completely silent through the prompt and for at least 5 seconds afterward. Did SVC remain on that SAME item without confirming it by itself?"
$results.Add([pscustomobject]@{ id='NO_UNSOLICITED_CONFIRM_WHILE_SILENT'; success=$silent })

$cameraReset = Read-PassFail "Complete the checklist while the camera is focused away from the pilot view. Did the blue highlight clear AND did the camera return to the default pilot cockpit view?"
$results.Add([pscustomobject]@{ id='CAMERA_RESET_ON_COMPLETE'; success=$cameraReset })

$persist = Read-PassFail "If you changed Auto, close/reopen SVC/EFB or restart the QA app. Was the Auto preference preserved?"
$results.Add([pscustomobject]@{ id='AUTO_FOCUS_PERSISTENCE'; success=$persist })

$report = [ordered]@{
    suite = 'GuidedChecklistFocus-1.0.19.0-R8-raceguard'
    startedAt = $started.ToString('o')
    finishedAt = (Get-Date).ToString('o')
    results = @($results)
    success = -not (@($results | Where-Object { -not $_.success }).Count -gt 0)
}

$reportPath = Join-Path $OutputDirectory 'guided-checklist-focus-result.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ""
if ($report.success) {
    Write-Host "Guided Checklist Focus R8 QA: PASS" -ForegroundColor Green
    Write-Host "Report: $reportPath" -ForegroundColor DarkGray
    exit 0
}

Write-Host "Guided Checklist Focus R8 QA: FAIL" -ForegroundColor Red
Write-Host "Report: $reportPath" -ForegroundColor DarkGray
Write-Host "If a focus/reset step fails, also send the SimVoice support package. Look for GUIDED_CHECKLIST_* and EFB_NATIVE_* markers." -ForegroundColor Yellow
exit 1

# R8 lifecycle-specific manual checks
Write-Host ""
Write-Host "R8 lifecycle checks:" -ForegroundColor Cyan
Write-Host " - Complete a focused item whose next item has NO focus: view must reset immediately."
Write-Host " - Disable Auto, press Enfocar, then confirm the item: view must reset to pilot default."
Write-Host " - Complete a checklist: view must reset BEFORE pressing Siguiente checklist."
Write-Host " - After completion, press the Checklist tab again in Windows/EFB: Windows selection must open silently."
