[CmdletBinding()]
param(
    [string]$ZipPath = "$env:USERPROFILE\Downloads\SimVoiceCopilot-QA-Flight-Functional-v2.1.1.zip",
    [string]$Destination = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "ZIP was not found: $ZipPath"
}

Set-Location "$env:USERPROFILE\Downloads"
Get-Process "SimVoiceCopilotApp" -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

Get-ChildItem -LiteralPath $Destination -Force |
    Where-Object { $_.Name -ne "QA-Runs" } |
    Remove-Item -Recurse -Force

Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
Set-Location $Destination

Write-Host "Installed SimVoice Copilot QA Phase 2.1." -ForegroundColor Green
Get-Content .\VERSION.txt
