param(
    [string]$ProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp",
    [string]$QaRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA",
    [int]$UiCycles = 25,
    [int]$LifecycleCycles = 30,
    [switch]$SkipWack
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-Argument([string]$Value) {
    return '"' + ($Value -replace '"','\"') + '"'
}

if ((-not $SkipWack) -and (-not (Test-IsAdministrator))) {
    Write-Host ""
    Write-Host "Store Certification QA needs one elevated PowerShell session for WACK." -ForegroundColor Yellow
    Write-Host "Accept the UAC prompt. The NEW elevated window will run the COMPLETE QA." -ForegroundColor Yellow
    Write-Host "This launcher window will return when that QA finishes." -ForegroundColor Yellow
    Write-Host ""

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-Argument $PSCommandPath),
        "-ProjectRoot", (Quote-Argument $ProjectRoot),
        "-QaRoot", (Quote-Argument $QaRoot),
        "-UiCycles", $UiCycles,
        "-LifecycleCycles", $LifecycleCycles
    )

    $p = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList ($args -join " ") -Wait -PassThru
    exit $p.ExitCode
}

$impl = Join-Path $PSScriptRoot "Scripts\Invoke-SimVoiceStoreCertificationQA.ps1"
if (-not (Test-Path -LiteralPath $impl)) {
    throw "Certification QA implementation not found: $impl"
}

& $impl `
    -ProjectRoot $ProjectRoot `
    -QaRoot $QaRoot `
    -UiCycles $UiCycles `
    -LifecycleCycles $LifecycleCycles `
    -SkipWack:$SkipWack

exit $LASTEXITCODE
