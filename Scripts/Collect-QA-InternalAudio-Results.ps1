[CmdletBinding()]
param(
    [string]$OutputZip = "$env:USERPROFILE\Downloads\SimVoice-QA-InternalAudio-Results.zip"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$base = Join-Path $projectRoot "QA-Runs\FlightInternalAudio"
if (-not (Test-Path -LiteralPath $base -PathType Container)) {
    throw "No FlightInternalAudio result directory exists: $base"
}

$latest = Get-ChildItem -LiteralPath $base -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $latest) {
    throw "No Internal Audio QA run was found in: $base"
}

if (Test-Path -LiteralPath $OutputZip) {
    Remove-Item -LiteralPath $OutputZip -Force
}
Compress-Archive -LiteralPath $latest.FullName -DestinationPath $OutputZip -Force
Write-Host ("Run : {0}" -f $latest.FullName)
Write-Host ("ZIP : {0}" -f $OutputZip)
