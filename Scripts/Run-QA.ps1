[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [Parameter(Mandatory = $true)]
    [string]$ConfigFile,
    [ValidateRange(1, 10000)]
    [int]$Cycles = 25,
    [string]$OutputDirectory = "",
    [switch]$DiagnoseUi,
    [switch]$NoClose
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $projectRoot "SimVoiceCopilot.QA.csproj"
$ConfigFile = [System.IO.Path]::GetFullPath($ConfigFile)

function Find-MSBuild {
    $msbuild = Get-Command "msbuild.exe" -ErrorAction SilentlyContinue
    if ($msbuild) {
        return $msbuild.Source
    }

    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $path = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
            -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
        if ($path) {
            return $path
        }
    }

    return $null
}

if (-not (Test-Path -LiteralPath $projectFile)) {
    throw "QA project file not found: $projectFile"
}

if (-not (Test-Path -LiteralPath $ConfigFile)) {
    throw "Configuration file not found: $ConfigFile"
}

$msbuildPath = Find-MSBuild
if ($msbuildPath) {
    Write-Host "Building with MSBuild: $msbuildPath" -ForegroundColor Cyan
    & $msbuildPath $projectFile /restore /t:Build /p:Configuration=$Configuration /p:Platform=x64 /m
}
else {
    $dotnet = Get-Command "dotnet.exe" -ErrorAction SilentlyContinue
    if (-not $dotnet) {
        throw "MSBuild or dotnet SDK was not found. Install Visual Studio 2022 with the .NET Framework 4.8 targeting pack."
    }

    Write-Host "Building with dotnet SDK: $($dotnet.Source)" -ForegroundColor Cyan
    & $dotnet.Source build $projectFile -c $Configuration -p:Platform=x64
}

if ($LASTEXITCODE -ne 0) {
    throw "QA project build failed with exit code $LASTEXITCODE."
}

$exeCandidates = @(
    (Join-Path $projectRoot "bin\x64\$Configuration\net48\SimVoiceCopilot.QA.exe"),
    (Join-Path $projectRoot "bin\$Configuration\net48\SimVoiceCopilot.QA.exe")
)

$exe = $exeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $exe) {
    throw "QA executable was not generated. Checked: $($exeCandidates -join '; ')"
}

$argsList = @("--config", $ConfigFile, "--cycles", $Cycles.ToString())
if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $argsList += @("--output", [System.IO.Path]::GetFullPath($OutputDirectory))
}
if ($DiagnoseUi) {
    $argsList += "--diagnose-ui"
}
if ($NoClose) {
    $argsList += "--no-close"
}

Write-Host "Running SimVoice Copilot QA against the installed MSIX package..." -ForegroundColor Cyan
& $exe @argsList
exit $LASTEXITCODE
