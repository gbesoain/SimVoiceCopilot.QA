[CmdletBinding()]
param(
    [string]$ZipPath = "$env:USERPROFILE\Downloads\SimVoiceCopilot-QA-MSIX-Desktop-v1.0.4.zip",
    [string]$Destination = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "ZIP not found: $ZipPath"
}

Get-Process "SimVoiceCopilotApp" -ErrorAction SilentlyContinue |
    Stop-Process -Force

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
Remove-Item (Join-Path $Destination "bin") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Destination "obj") -Recurse -Force -ErrorAction SilentlyContinue

Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force

Write-Host "QA sources installed in: $Destination" -ForegroundColor Green
Write-Host "SimVoice Copilot source path (reference only): C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp" -ForegroundColor DarkGray
Write-Host "The QA runner will target only the installed MSIX package." -ForegroundColor Cyan
