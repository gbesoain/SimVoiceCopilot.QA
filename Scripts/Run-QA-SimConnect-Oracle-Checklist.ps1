[CmdletBinding()]
param(
    [string]$SimConnectDll = "",
    [double]$Heading = 210,
    [double]$Altitude = 8000,
    [double]$VerticalSpeed = -1000,
    [int]$Transponder = 4321
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$run = Join-Path $PSScriptRoot "Run-QA-SimConnect-Oracle.ps1"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$root = Join-Path $projectRoot "QA-Runs\FlightOracle\CHECKLIST-$stamp"
New-Item -ItemType Directory -Path $root -Force | Out-Null

function Run-OracleStep {
    param(
        [string]$Name,
        [string]$Mode,
        [string]$Variable = "",
        [string]$Expected = "",
        [double]$Tolerance = 0,
        [int]$TimeoutSeconds = 30
    )

    $parameters = @{
        Mode = $Mode
        OutputDirectory = (Join-Path $root $Name)
        Tolerance = $Tolerance
        TimeoutSeconds = $TimeoutSeconds
        SimConnectDll = $SimConnectDll
        NoBuild = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($Variable)) {
        $parameters.Variable = $Variable
        $parameters.Expected = $Expected
    }

    & $run @parameters
    if ($LASTEXITCODE -ne 0) {
        throw "Checklist step '$Name' failed. Review: $($parameters.OutputDirectory)"
    }
}

Write-Host "Building and probing the SimConnect Oracle..." -ForegroundColor Cyan
& $run -Mode Probe -OutputDirectory (Join-Path $root "00-Probe") -SimConnectDll $SimConnectDll
if ($LASTEXITCODE -ne 0) { throw "Initial SimConnect probe failed." }

Write-Host ""
Write-Host "MANUAL ORACLE VALIDATION" -ForegroundColor Cyan
Write-Host "Use the aircraft controls in MSFS, not SimVoice Copilot, for these setup steps." -ForegroundColor Yellow

Read-Host "Set the HEADING BUG to $Heading degrees, then press ENTER"
Run-OracleStep -Name "01-HeadingBug" -Mode Assert -Variable HeadingBug -Expected $Heading.ToString([Globalization.CultureInfo]::InvariantCulture) -Tolerance 1

Read-Host "Set the SELECTED ALTITUDE to $Altitude feet, then press ENTER"
Run-OracleStep -Name "02-SelectedAltitude" -Mode Assert -Variable SelectedAltitude -Expected $Altitude.ToString([Globalization.CultureInfo]::InvariantCulture) -Tolerance 100

Read-Host "Set the SELECTED VERTICAL SPEED to $VerticalSpeed ft/min, then press ENTER"
Run-OracleStep -Name "03-SelectedVerticalSpeed" -Mode Assert -Variable SelectedVerticalSpeed -Expected $VerticalSpeed.ToString([Globalization.CultureInfo]::InvariantCulture) -Tolerance 100

Read-Host "Set the TRANSPONDER code to $Transponder, then press ENTER"
Run-OracleStep -Name "04-Transponder" -Mode Assert -Variable Transponder -Expected $Transponder.ToString([Globalization.CultureInfo]::InvariantCulture) -Tolerance 0

Write-Host ""
Write-Host "SIMCONNECT ORACLE CHECKLIST: PASS" -ForegroundColor Green
Write-Host "Results: $root" -ForegroundColor DarkGray
