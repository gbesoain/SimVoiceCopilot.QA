[CmdletBinding()]
param(
    [string]$QaRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA",
    [string]$Destination = "$env:USERPROFILE\Downloads\SimVoice-QA-Phase2.4-Extended-Results.zip",
    [ValidateRange(1, 20)]
    [int]$LatestRuns = 8
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$root = Join-Path $QaRoot "QA-Runs\FlightExtended"
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "No Phase 2.4 result folder exists: $root" }
$runs = @(Get-ChildItem -LiteralPath $root -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First $LatestRuns)
if ($runs.Count -eq 0) { throw "No Phase 2.4 runs were found." }
if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
Compress-Archive -Path $runs.FullName -DestinationPath $Destination -Force
Write-Host "Phase 2.4 results package created:" -ForegroundColor Green
Write-Host $Destination
