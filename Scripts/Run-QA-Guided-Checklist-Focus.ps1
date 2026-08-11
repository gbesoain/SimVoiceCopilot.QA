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

$auto = Read-PassFail "Start a native checklist. When the first actionable item is spoken, did MSFS automatically highlight/focus its cockpit control?"
$results.Add([pscustomobject]@{ id='AUTO_FOCUS_FIRST_ITEM'; success=$auto })

$buttonVisible = Read-PassFail "For an item with a native visual helper, is the Focus/Enfocar button visible in the current-item card?"
$results.Add([pscustomobject]@{ id='EFB_FOCUS_BUTTON_VISIBLE'; success=$buttonVisible })

$manual = Read-PassFail "Move the camera away, press Focus/Enfocar. Did MSFS highlight/focus the correct cockpit control again?"
$results.Add([pscustomobject]@{ id='EFB_MANUAL_FOCUS'; success=$manual })

$advance = Read-PassFail "Confirm/Checked the item. If the next item has a visual helper, did focus move to the next control without leaving the old one highlighted?"
$results.Add([pscustomobject]@{ id='AUTO_FOCUS_ADVANCE'; success=$advance })

$noHelper = Read-PassFail "On an item with no visual helper (if available), did the checklist continue normally without a broken Focus button or error?"
$results.Add([pscustomobject]@{ id='NO_HELPER_FALLBACK'; success=$noHelper })

$cancel = Read-PassFail "Cancel or complete the checklist. Was the active cockpit highlight cleared?"
$results.Add([pscustomobject]@{ id='FOCUS_CLEAR_END'; success=$cancel })

$report = [ordered]@{
    suite = 'GuidedChecklistFocus-1.0.19.0-A1'
    startedAt = $started.ToString('o')
    finishedAt = (Get-Date).ToString('o')
    results = @($results)
    success = -not (@($results | Where-Object { -not $_.success }).Count -gt 0)
}

$reportPath = Join-Path $OutputDirectory 'guided-checklist-focus-result.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ""
if ($report.success) {
    Write-Host "Guided Checklist Focus QA: PASS" -ForegroundColor Green
    Write-Host "Report: $reportPath" -ForegroundColor DarkGray
    exit 0
}

Write-Host "Guided Checklist Focus QA: FAIL" -ForegroundColor Red
Write-Host "Report: $reportPath" -ForegroundColor DarkGray
Write-Host "If Focus is unavailable, also send the SimVoice support package. Look for GUIDED_CHECKLIST_* and EFB_NATIVE_VISUAL_HELPER_* markers." -ForegroundColor Yellow
exit 1
