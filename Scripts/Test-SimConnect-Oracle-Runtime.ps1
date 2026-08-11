[CmdletBinding()]
param(
    [string]$SimConnectDll = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$output = Join-Path $projectRoot "SimConnectOracle\bin\x64\Release\net48"
$exe = Join-Path $output "SimVoiceCopilot.QA.SimConnectOracle.exe"
$runtimeDll = Join-Path $output "Microsoft.FlightSimulator.SimConnect.dll"

Write-Host "Oracle runtime diagnostics" -ForegroundColor Cyan
Write-Host "Project root : $projectRoot"
Write-Host "Executable   : $exe"
Write-Host "Managed DLL : $runtimeDll"
Write-Host "OS 64-bit   : $([Environment]::Is64BitOperatingSystem)"

if (Test-Path -LiteralPath $runtimeDll) {
    $name = [Reflection.AssemblyName]::GetAssemblyName($runtimeDll)
    Write-Host "Assembly     : $($name.FullName)"
    Write-Host "Size         : $((Get-Item -LiteralPath $runtimeDll).Length) bytes"
}
else {
    Write-Warning "The runtime managed DLL does not exist yet. Run Run-QA-SimConnect-Oracle.ps1 without -NoBuild first."
}

$nativeDll = Join-Path $output "SimConnect.dll"
Write-Host "Native DLL  : $(if (Test-Path -LiteralPath $nativeDll) { $nativeDll } else { 'not app-local' })"
