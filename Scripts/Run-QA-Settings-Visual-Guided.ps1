[CmdletBinding()]
param(
    [string]$AppIdPattern = "SimTechAviation.SimVoiceCopilot.Dev_*"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$runDirectory = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) `
    ("QA-Runs\SettingsVisual\SETTINGS-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

$app = @(Get-StartApps | Where-Object { $_.AppID -like $AppIdPattern }) | Select-Object -First 1
if ($null -eq $app) {
    throw "Private QA app was not found: $AppIdPattern"
}

if ($null -eq (Get-Process -Name "SimVoiceCopilotApp" -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    Start-Process "explorer.exe" -ArgumentList ("shell:AppsFolder\" + $app.AppID)
    Start-Sleep -Seconds 4
}

Write-Host ""
Write-Host "Guided Settings visual regression" -ForegroundColor Cyan
Write-Host "1. Open Settings > Voice & Audio." -ForegroundColor Yellow
Write-Host "2. Verify literal ampersands are visible in titles such as 'Voice & Audio'." -ForegroundColor Yellow
Write-Host "3. Verify Voice & Audio and Command Behavior have balanced lower padding." -ForegroundColor Yellow
Write-Host "4. Verify Push-to-Talk and Voice Checklist confirmations remain fully visible." -ForegroundColor Yellow

$ampersands = (Read-Host "Are the ampersands displayed correctly? (Y/N)") -match '^[Yy]'
$spacing = (Read-Host "Is the spacing balanced in all four cards? (Y/N)") -match '^[Yy]'
$success = $ampersands -and $spacing

$report = [ordered]@{
    schemaVersion = 1
    qaVersion = "2.7.5"
    appVersion = "1.0.17.0"
    generatedAt = (Get-Date).ToString("o")
    success = $success
    ampersandsVisible = $ampersands
    cardSpacingBalanced = $spacing
}
$reportPath = Join-Path $runDirectory "settings-visual-result.json"
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($success) {
    Write-Host "SETTINGS VISUAL: PASS" -ForegroundColor Green
    Write-Host "Report: $reportPath" -ForegroundColor DarkGray
    exit 0
}

Write-Host "SETTINGS VISUAL: FAIL" -ForegroundColor Red
Write-Host "Report: $reportPath" -ForegroundColor DarkGray
exit 1
