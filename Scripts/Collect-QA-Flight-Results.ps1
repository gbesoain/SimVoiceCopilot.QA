[CmdletBinding()]
param(
    [string]$OutputZip = "$env:USERPROFILE\Downloads\SimVoice-QA-Flight-Functional-Results.zip"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$base = Join-Path $projectRoot "QA-Runs\FlightFunctional"

if (-not (Test-Path -LiteralPath $base)) {
    throw "No FlightFunctional result directory exists: $base"
}

$latest = Get-ChildItem -LiteralPath $base -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $latest) {
    throw "No FlightFunctional run was found in: $base"
}

if (Test-Path -LiteralPath $OutputZip) {
    Remove-Item -LiteralPath $OutputZip -Force
}

Compress-Archive -LiteralPath $latest.FullName -DestinationPath $OutputZip -Force
Write-Host "Run : $($latest.FullName)"
Write-Host "ZIP : $OutputZip"
