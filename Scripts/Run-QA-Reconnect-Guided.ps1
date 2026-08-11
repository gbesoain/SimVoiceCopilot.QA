[CmdletBinding()]
param(
    [ValidateSet("EN", "ES")]
    [string]$Language = "EN",
    [string]$AppNamePattern = "*SimVoice*",
    [string]$ProcessName = "SimVoiceCopilotApp",
    [string]$SimConnectDll = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp\Microsoft.FlightSimulator.SimConnect.dll",
    [ValidateRange(60, 900)]
    [int]$ReconnectTimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$oracle = Join-Path $PSScriptRoot "Run-QA-SimConnect-Oracle.ps1"
$internal = Join-Path $PSScriptRoot "Run-QA-Flight-InternalAudio.ps1"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$output = Join-Path $projectRoot "QA-Runs\FlightExtended\RECONNECT-$stamp-$Language"
New-Item -ItemType Directory -Path $output -Force | Out-Null
$log = Join-Path $output "reconnect-run.log"
function Log([string]$message) { $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"),$message; Add-Content -LiteralPath $log -Value $line -Encoding UTF8; Write-Host $line }
function Probe([string]$name) {
    $dir = Join-Path $output $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $consoleLog = Join-Path $dir "console.log"
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # A disconnected Oracle is an expected probe result during this test.
        # Capture every child PowerShell stream without turning its non-zero exit
        # code into a terminating error in the parent script.
        $ErrorActionPreference = "Continue"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $oracle -Mode Probe -OutputDirectory $dir -SimConnectDll $SimConnectDll -NoBuild *> $consoleLog
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return $exitCode -eq 0
}

Log "Phase 2.4 guided SimConnect reconnection test started."
if (-not (Probe "01-connected-before")) { throw "Initial Oracle probe failed. Load an active flight before starting." }
$app = @(Get-StartApps | Where-Object { $_.Name -like $AppNamePattern } | Select-Object -First 1)
$process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $process) { Start-Process explorer.exe ("shell:AppsFolder\{0}" -f $app.AppID); Start-Sleep -Seconds 5; $process = Get-Process -Name $ProcessName -ErrorAction Stop | Select-Object -First 1 }
Log ("SimVoice PID={0} is running." -f $process.Id)
Write-Host ""
Read-Host "Close Microsoft Flight Simulator completely, then press ENTER"
$deadline = (Get-Date).AddSeconds(120)
$disconnected = $false
while ((Get-Date) -lt $deadline) {
    if (-not (Probe ("02-disconnect-check-" + (Get-Date -Format "HHmmss")))) { $disconnected = $true; break }
    Start-Sleep -Seconds 3
}
if (-not $disconnected) { throw "The Oracle remained connected after the disconnect window." }
$process.Refresh()
if ($process.HasExited -or -not $process.Responding) { throw "SimVoice did not remain alive and responsive after MSFS closed." }
Log "Disconnect detected; SimVoice remained alive and responsive."
Write-Host ""
Read-Host "Start MSFS, load the C172 G1000 into an active flight, then press ENTER"
$deadline = (Get-Date).AddSeconds($ReconnectTimeoutSeconds)
$reconnected = $false
while ((Get-Date) -lt $deadline) {
    if (Probe ("03-reconnect-check-" + (Get-Date -Format "HHmmss"))) { $reconnected = $true; break }
    Start-Sleep -Seconds 5
}
if (-not $reconnected) { throw "MSFS did not become available through SimConnect within the configured timeout." }
Log "Oracle reconnection: PASS. Running a post-reconnect internal-audio smoke suite."
$suite = if ($Language -eq "ES") { "SmokeInternalES" } else { "SmokeInternalEN" }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $internal -Suite $suite -SkipAppLaunch -NoBuild -MaxAttempts 1 -SimConnectDll $SimConnectDll
if ($LASTEXITCODE -ne 0) { throw "Post-reconnect command suite failed." }
Log "PHASE 2.4 RECONNECT RESULT: PASS"
Write-Host ("Results: {0}" -f $output) -ForegroundColor Green
