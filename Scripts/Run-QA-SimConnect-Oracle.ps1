[CmdletBinding()]
param(
    [ValidateSet("Probe", "Snapshot", "Watch", "Assert", "Wait")]
    [string]$Mode = "Probe",
    [string]$Variable = "",
    [string]$Expected = "",
    [ValidateRange(0, 1000000)]
    [double]$Tolerance = 0,
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 30,
    [ValidateRange(1, 86400)]
    [int]$DurationSeconds = 60,
    [ValidateRange(50, 60000)]
    [int]$IntervalMs = 1000,
    [string]$OutputDirectory = "",
    [string]$SimConnectDll = "",
    [switch]$AllowMenu,
    [switch]$ListVariables,
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$oracleProject = Join-Path $projectRoot "SimConnectOracle\SimVoiceCopilot.QA.SimConnectOracle.csproj"
$oracleOutput = Join-Path $projectRoot "SimConnectOracle\bin\x64\Release\net48"
$oracleExe = Join-Path $oracleOutput "SimVoiceCopilot.QA.SimConnectOracle.exe"
$runtimeManagedDll = Join-Path $oracleOutput "Microsoft.FlightSimulator.SimConnect.dll"

function Find-MSBuild {
    $candidates = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $command = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    throw "MSBuild.exe was not found. Install Visual Studio 2022 or Build Tools with .NET Framework 4.8 targeting pack."
}

function Add-Candidate([System.Collections.Generic.List[string]]$List, [string]$Path) {
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $List.Add([Environment]::ExpandEnvironmentVariables($Path))
    }
}

function Find-SimConnectManagedDll([string]$ExplicitPath) {
    $found = New-Object System.Collections.Generic.List[string]

    # 1. Explicit path always wins.
    Add-Candidate $found $ExplicitPath

    # 2. Prefer the exact wrapper already used by the real SimVoice Copilot sources.
    $appRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp"
    Add-Candidate $found (Join-Path $appRoot "Microsoft.FlightSimulator.SimConnect.dll")
    Add-Candidate $found (Join-Path $appRoot "bin\Release\net48\Microsoft.FlightSimulator.SimConnect.dll")
    Add-Candidate $found (Join-Path $appRoot "bin\Debug\net48\Microsoft.FlightSimulator.SimConnect.dll")
    Add-Candidate $found (Join-Path $appRoot "Store\obj\PackageRoot\Microsoft.FlightSimulator.SimConnect.dll")

    # 3. Environment-selected SDKs, preferring 2024.
    foreach ($sdkRoot in @($env:MSFS2024_SDK, $env:MSFS_SDK, $env:MSFS2020_SDK)) {
        if (-not [string]::IsNullOrWhiteSpace($sdkRoot)) {
            Add-Candidate $found (Join-Path $sdkRoot "SimConnect SDK\lib\managed\Microsoft.FlightSimulator.SimConnect.dll")
        }
    }

    # 4. Known SDK paths.
    Add-Candidate $found "C:\MSFS 2024 SDK\SimConnect SDK\lib\managed\Microsoft.FlightSimulator.SimConnect.dll"
    Add-Candidate $found "C:\MSFS SDK\SimConnect SDK\lib\managed\Microsoft.FlightSimulator.SimConnect.dll"
    Add-Candidate $found "${env:ProgramFiles}\Microsoft Flight Simulator 2024 SDK\SimConnect SDK\lib\managed\Microsoft.FlightSimulator.SimConnect.dll"
    Add-Candidate $found "${env:ProgramFiles(x86)}\Microsoft Flight Simulator 2024 SDK\SimConnect SDK\lib\managed\Microsoft.FlightSimulator.SimConnect.dll"

    foreach ($candidate in $found | Select-Object -Unique) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate)) { continue }

        try {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
            $assemblyName = [Reflection.AssemblyName]::GetAssemblyName($resolved)
            if ($assemblyName.Name -eq "Microsoft.FlightSimulator.SimConnect") {
                return $resolved
            }
        }
        catch {
            Write-Warning "Ignoring invalid SimConnect managed assembly '$candidate': $($_.Exception.Message)"
        }
    }

    throw @"
Microsoft.FlightSimulator.SimConnect.dll was not found or was not a valid managed SimConnect assembly.
Use the wrapper already used by SimVoice Copilot, for example:
  -SimConnectDll "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp\bin\Release\net48\Microsoft.FlightSimulator.SimConnect.dll"
"@
}

function Get-PeMachine([string]$Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.BinaryReader($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { return 0 }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { return 0 }
        return $reader.ReadUInt16()
    }
    finally {
        $stream.Dispose()
    }
}

function Find-SimConnectNativeDll([string]$ManagedDll) {
    $searchRoots = New-Object System.Collections.Generic.List[string]
    $managedDir = Split-Path -Parent $ManagedDll
    Add-Candidate $searchRoots $managedDir
    Add-Candidate $searchRoots "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp"
    Add-Candidate $searchRoots "C:\MSFS 2024 SDK\SimConnect SDK"
    Add-Candidate $searchRoots "C:\MSFS SDK\SimConnect SDK"

    foreach ($root in $searchRoots | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        $matches = Get-ChildItem -LiteralPath $root -Filter "SimConnect.dll" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq "SimConnect.dll" }

        foreach ($native in $matches) {
            try {
                # IMAGE_FILE_MACHINE_AMD64 = 0x8664. Ignore x86 DLLs for this x64 Oracle.
                if ((Get-PeMachine $native.FullName) -eq 0x8664) {
                    return $native.FullName
                }
            }
            catch {
                Write-Warning "Ignoring native SimConnect candidate '$($native.FullName)': $($_.Exception.Message)"
            }
        }
    }

    return $null
}

if (-not (Test-Path -LiteralPath $oracleProject)) {
    throw "SimConnect Oracle project was not found: $oracleProject"
}

$simConnectManagedDll = Find-SimConnectManagedDll $SimConnectDll
$managedAssemblyName = [Reflection.AssemblyName]::GetAssemblyName($simConnectManagedDll)

if (-not $NoBuild -or -not (Test-Path -LiteralPath $oracleExe)) {
    $msbuild = Find-MSBuild
    Write-Host "Building SimConnect Oracle..." -ForegroundColor Cyan
    Write-Host "MSBuild             : $msbuild" -ForegroundColor DarkGray
    Write-Host "SimConnect managed  : $simConnectManagedDll" -ForegroundColor DarkGray
    Write-Host "Assembly version    : $($managedAssemblyName.Version)" -ForegroundColor DarkGray

    & $msbuild $oracleProject `
        /restore `
        /t:Build `
        /p:Configuration=Release `
        /p:Platform=x64 `
        "/p:SimConnectManagedPath=$simConnectManagedDll" `
        /nologo

    if ($LASTEXITCODE -ne 0) {
        throw "SimConnect Oracle build failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $oracleExe)) {
    throw "Compiled SimConnect Oracle executable was not found: $oracleExe"
}

function Copy-RuntimeDependencyIfNeeded {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $needsCopy = -not (Test-Path -LiteralPath $Destination -PathType Leaf)
    if (-not $needsCopy) {
        try {
            $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
            $needsCopy = -not [string]::Equals($sourceHash, $destinationHash, [StringComparison]::OrdinalIgnoreCase)
        }
        catch {
            $needsCopy = $true
        }
    }

    if (-not $needsCopy) {
        return
    }

    $lastError = $null
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try {
            Copy-Item -LiteralPath $Source -Destination $Destination -Force
            return
        }
        catch {
            $lastError = $_
            Start-Sleep -Milliseconds 250
        }
    }

    throw ("Could not deploy runtime dependency '{0}' to '{1}': {2}" -f $Source, $Destination, $lastError.Exception.Message)
}

# Never rely on MSBuild/GAC copy-local behavior: deploy the exact selected wrapper.
New-Item -ItemType Directory -Path $oracleOutput -Force | Out-Null
Copy-RuntimeDependencyIfNeeded -Source $simConnectManagedDll -Destination $runtimeManagedDll

$nativeSimConnectDll = Find-SimConnectNativeDll $simConnectManagedDll
if ($null -ne $nativeSimConnectDll) {
    $runtimeNativeDll = Join-Path $oracleOutput "SimConnect.dll"
    Copy-RuntimeDependencyIfNeeded -Source $nativeSimConnectDll -Destination $runtimeNativeDll
    Write-Host "SimConnect native   : $nativeSimConnectDll" -ForegroundColor DarkGray
}
else {
    Write-Host "SimConnect native   : not found app-local; Windows/MSFS runtime resolution will be used" -ForegroundColor DarkYellow
}

$runtimeAssemblyName = [Reflection.AssemblyName]::GetAssemblyName($runtimeManagedDll)
Write-Host "Runtime managed DLL : $runtimeManagedDll" -ForegroundColor DarkGray
Write-Host "Runtime version     : $($runtimeAssemblyName.Version)" -ForegroundColor DarkGray
Write-Host "Oracle architecture : x64" -ForegroundColor DarkGray

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputDirectory = Join-Path $projectRoot "QA-Runs\FlightOracle\ORACLE-$stamp-$Mode"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$arguments = @(
    "--mode", $Mode,
    "--output", $OutputDirectory,
    "--timeout-seconds", $TimeoutSeconds.ToString([Globalization.CultureInfo]::InvariantCulture),
    "--duration-seconds", $DurationSeconds.ToString([Globalization.CultureInfo]::InvariantCulture),
    "--interval-ms", $IntervalMs.ToString([Globalization.CultureInfo]::InvariantCulture),
    "--tolerance", $Tolerance.ToString([Globalization.CultureInfo]::InvariantCulture)
)

if (-not [string]::IsNullOrWhiteSpace($Variable)) { $arguments += @("--variable", $Variable) }
if ($PSBoundParameters.ContainsKey("Expected")) { $arguments += @("--expected", $Expected) }
if ($AllowMenu) { $arguments += "--allow-menu" }
if ($ListVariables) { $arguments += "--list-variables" }

Write-Host "Mode      : $Mode" -ForegroundColor Cyan
if (-not [string]::IsNullOrWhiteSpace($Variable)) {
    Write-Host "Variable  : $Variable" -ForegroundColor DarkGray
    Write-Host "Expected  : $Expected" -ForegroundColor DarkGray
    Write-Host "Tolerance : $Tolerance" -ForegroundColor DarkGray
}
Write-Host "Results   : $OutputDirectory" -ForegroundColor DarkGray
Write-Host "MSFS must already be running with an active flight loaded." -ForegroundColor Yellow

$previousManaged = $env:SIMVOICE_QA_SIMCONNECT_MANAGED
$previousPath = $env:PATH
try {
    $env:SIMVOICE_QA_SIMCONNECT_MANAGED = $runtimeManagedDll
    $env:PATH = "$oracleOutput;$previousPath"
    & $oracleExe @arguments
    $oracleExitCode = $LASTEXITCODE
}
finally {
    $env:SIMVOICE_QA_SIMCONNECT_MANAGED = $previousManaged
    $env:PATH = $previousPath
}

exit $oracleExitCode
