[CmdletBinding()]
param(
    [ValidateSet("EN", "ES")]
    [string]$Language = "EN",
    [string]$AppNamePattern = "*SimVoice*",
    [string]$SimConnectDll = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp\Microsoft.FlightSimulator.SimConnect.dll",
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$runner = Join-Path $PSScriptRoot "Run-QA-Flight-Extended.ps1"
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw "Extended runner not found: $runner" }

$suffix = if ($Language -eq "ES") { "ES" } else { "EN" }
$suites = @("StatesInternal$suffix", "CalloutsInternal$suffix", "NegativeInternal$suffix")
$failures = New-Object 'System.Collections.Generic.List[string]'

foreach ($suite in $suites) {
    Write-Host ""
    Write-Host ("=== Phase 2.4 suite: {0} ===" -f $suite) -ForegroundColor Cyan
    $arguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner,
        "-Suite", $suite,
        "-AppNamePattern", $AppNamePattern,
        "-SimConnectDll", $SimConnectDll
    )
    if ($NoBuild) { $arguments += "-NoBuild" }
    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) { $failures.Add($suite) }
}

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host ("PHASE 2.4 EXTENDED {0}: PASS" -f $suffix) -ForegroundColor Green
    exit 0
}
Write-Host ("PHASE 2.4 EXTENDED {0}: FAIL ({1})" -f $suffix, ($failures -join ", ")) -ForegroundColor Red
exit 1
