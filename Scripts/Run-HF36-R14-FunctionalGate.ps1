param(
    [ValidateSet("CoreEN","CoreES")]
    [string]$Suite = "CoreEN",
    [string]$QaRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA",
    [switch]$NoLaunch,
    [switch]$KeepAppRunning
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$Version = "1.0.20.0"
$Hotfix = "HF36-R14"
$GateVersion = "v2-R2"
$GateRoot = Join-Path $env:LOCALAPPDATA "SimVoiceCopilot\QAFunctionalGate\HF36-R14-v2-R2"
$GateExe = Join-Path $GateRoot "FunctionalGate\bin\Release\SimVoiceCopilot.FunctionalGate.exe"
$QaAssembly = Join-Path $QaRoot "bin\x64\Release\net48\SimVoiceCopilot.QA.exe"
$Cases = Join-Path $GateRoot ("FunctionalGate\functional-gate-cases." + $(if ($Suite -eq "CoreES") { "es-ES" } else { "en-US" }) + ".json")
$Downloads = Join-Path $env:USERPROFILE "Downloads"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $QaRoot ("QA-Runs\FlightFunctionalGate\GATE-" + $stamp + "-" + $Suite)

function Wait-ForProcess([string]$Name, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $p = Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p) { return $p }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

function Get-SimVoicePackage {
    $all = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "SimTechAviation.SimVoiceCopilot*" -and $_.Version.ToString() -eq $Version
    })
    if (-not $all) { return $null }
    $dev = $all | Where-Object { $_.Name -like "*.Dev" } | Select-Object -First 1
    if ($dev) { return $dev }
    return $all | Select-Object -First 1
}

Write-Host "SimVoice Copilot $Version $Hotfix - Functional Flight Gate $GateVersion" -ForegroundColor Cyan
Write-Host "Suite: $Suite" -ForegroundColor Cyan
Write-Host "This expanded gate changes heading, altitude, vertical speed, COM1/COM2, NAV1/NAV2 and transponder selections. Run it on the ground, not during an active flight." -ForegroundColor Yellow

foreach ($required in @($GateExe, $QaAssembly, $Cases)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required functional-gate file is missing: $required. Run the Functional Gate installer first."
    }
}

$pkg = Get-SimVoicePackage
if (-not $pkg) {
    throw "SimVoice Copilot $Version package was not found. Install the current private Internal Audio MSIX first."
}
Write-Host ("[PASS] Installed package: " + $pkg.Name + " " + $pkg.Version) -ForegroundColor Green

$startedByGate = $false
if (-not $NoLaunch) {
    $existing = Get-Process -Name "SimVoiceCopilotApp" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $existing) {
        $startApp = Get-StartApps | Where-Object { $_.Name -eq "SimVoice Copilot" } | Select-Object -First 1
        if (-not $startApp) {
            throw "SimVoice Copilot Start-menu AppID was not found."
        }
        Write-Host "[INFO] Launching installed SimVoice Copilot..." -ForegroundColor Cyan
        Start-Process explorer.exe -ArgumentList ("shell:AppsFolder\" + $startApp.AppID) | Out-Null
        $startedByGate = $true
    }
}

$p = Wait-ForProcess "SimVoiceCopilotApp" 15
if (-not $p) { throw "SimVoiceCopilotApp did not become ready." }
Write-Host ("[PASS] SimVoiceCopilotApp running. PID=" + $p.Id) -ForegroundColor Green

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

# Preserve a light preflight inventory for diagnosis.
@{
    generatedLocal = (Get-Date).ToString("o")
    suite = $Suite
    productVersion = $Version
    hotfix = $Hotfix
    packageName = $pkg.Name
    packageFullName = $pkg.PackageFullName
    qaAssembly = $QaAssembly
    gateExe = $GateExe
    cases = $Cases
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runRoot "preflight.json") -Encoding UTF8

Write-Host "[INFO] Running independent SimConnect oracle + internal-audio E2E suite..." -ForegroundColor Cyan
& $GateExe `
    --qa-assembly $QaAssembly `
    --cases $Cases `
    --output $runRoot
$exit = $LASTEXITCODE

$reportTxt = Join-Path $runRoot "functional-report.txt"
if (Test-Path -LiteralPath $reportTxt) {
    Write-Host ""
    Get-Content -LiteralPath $reportTxt | ForEach-Object { Write-Host $_ }
}

$reportZip = Join-Path $Downloads ("SimVoiceCopilot-$Version-$Hotfix-FunctionalGate-$GateVersion-$Suite-$stamp.zip")
if (Test-Path -LiteralPath $reportZip) { Remove-Item -LiteralPath $reportZip -Force }
Compress-Archive -Path (Join-Path $runRoot "*") -DestinationPath $reportZip -CompressionLevel Optimal

if ($startedByGate -and -not $KeepAppRunning) {
    Get-Process -Name "SimVoiceCopilotApp" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($exit -eq 0) {
    Write-Host "FUNCTIONAL FLIGHT GATE: PASS" -ForegroundColor Green
} else {
    Write-Host ("FUNCTIONAL FLIGHT GATE: FAIL (exit " + $exit + ")") -ForegroundColor Red
}
Write-Host ("Report ZIP: " + $reportZip) -ForegroundColor Cyan
Write-Host "G2 manual QA remains a separate mandatory gate." -ForegroundColor Yellow
exit $exit
