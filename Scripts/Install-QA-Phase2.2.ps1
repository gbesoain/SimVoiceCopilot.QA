[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,
    [string]$Destination = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ZipPath = (Resolve-Path -LiteralPath $ZipPath).Path
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

Get-Process "SimVoiceCopilotApp" -ErrorAction SilentlyContinue |
    Stop-Process -Force

Get-ChildItem -LiteralPath $Destination -Force |
    Where-Object { $_.Name -ne "QA-Runs" } |
    Remove-Item -Recurse -Force

Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force

$versionPath = Join-Path $Destination "VERSION.txt"
if (-not (Test-Path -LiteralPath $versionPath)) {
    throw "Installation completed, but VERSION.txt is missing from the destination root."
}

Get-Content -LiteralPath $versionPath
