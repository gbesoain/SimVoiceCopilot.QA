[CmdletBinding()]
param(
    [string]$AppIdPattern = "SimTechAviation.SimVoiceCopilot.Dev_*",
    [string]$OutputDirectory = "",
    [ValidateRange(5, 60)]
    [int]$StateWaitSeconds = 10
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $OutputDirectory = Join-Path $projectRoot ("QA-Runs\PayloadPreflight\PAYLOAD-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

# Windows PowerShell 5.1-safe: only ordinary PowerShell arrays are used.
$script:checks = @()

function Add-Check {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Detail
    )

    $script:checks += [pscustomobject][ordered]@{
        name = $Name
        success = $Success
        detail = $Detail
    }

    if ($Success) {
        Write-Host ("PASS - {0}: {1}" -f $Name, $Detail) -ForegroundColor Green
    }
    else {
        Write-Host ("FAIL - {0}: {1}" -f $Name, $Detail) -ForegroundColor Red
    }
}

function Get-NormalizedPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    try {
        return [IO.Path]::GetFullPath($expanded)
    }
    catch {
        return $expanded
    }
}

function Get-CommunityRoots {
    $cfgCandidates = @(
        (Join-Path $env:APPDATA "Microsoft Flight Simulator 2024\UserCfg.opt"),
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.Limitless_8wekyb3d8bbwe\LocalCache\UserCfg.opt")
    )

    $packageFamiliesRoot = Join-Path $env:LOCALAPPDATA "Packages"
    if (Test-Path -LiteralPath $packageFamiliesRoot -PathType Container) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $packageFamiliesRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($directory.Name -match "Limitless|FlightSimulator2024") {
                $cfgCandidates += (Join-Path $directory.FullName "LocalCache\UserCfg.opt")
            }
        }
    }

    $roots = @()
    foreach ($cfg in @($cfgCandidates | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) {
            continue
        }

        try {
            $text = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8
            $match = [regex]::Match(
                $text,
                'InstalledPackagesPath\s+"(?<path>[^"]+)"',
                [Text.RegularExpressions.RegexOptions]::IgnoreCase)

            if ($match.Success) {
                $candidate = Get-NormalizedPath (Join-Path $match.Groups["path"].Value.Trim() "Community")
                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                    $roots += $candidate
                }
            }
        }
        catch {
            # Continue with known fallback paths.
        }
    }

    $fallback = Get-NormalizedPath (
        Join-Path $env:LOCALAPPDATA "Packages\Microsoft.Limitless_8wekyb3d8bbwe\LocalCache\Packages\Community")
    if (-not [string]::IsNullOrWhiteSpace($fallback)) {
        $roots += $fallback
    }

    $validRoots = @()
    foreach ($root in @($roots | Sort-Object -Unique)) {
        $parent = Split-Path -Parent $root
        if ((Test-Path -LiteralPath $root -PathType Container) -or
            (Test-Path -LiteralPath $parent -PathType Container)) {
            $validRoots += $root
        }
    }

    return $validRoots
}

function Get-RawSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-CanonicalJson {
    param([string]$Path)

    # Parse and serialize compactly. This intentionally ignores indentation,
    # spaces, UTF-8 BOM and CRLF/LF differences while preserving JSON values.
    $parsed = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return ($parsed | ConvertTo-Json -Depth 100 -Compress)
}

function Get-PayloadComparison {
    param(
        [string]$Source,
        [string]$Destination,
        [bool]$JsonSemantic
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            success = $false
            comparison = "missing"
            detail = "Bundled file missing: $Source"
        }
    }

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            success = $false
            comparison = "missing"
            detail = "Deployed file missing: $Destination"
        }
    }

    $sourceHash = Get-RawSha256 $Source
    $destinationHash = Get-RawSha256 $Destination

    if (-not $JsonSemantic) {
        $sameBinary = [string]::Equals(
            $sourceHash,
            $destinationHash,
            [StringComparison]::OrdinalIgnoreCase)

        return [pscustomobject][ordered]@{
            success = $sameBinary
            comparison = "binary-sha256"
            detail = "source=$sourceHash; deployed=$destinationHash; path=$Destination"
        }
    }

    try {
        $sourceCanonical = Get-CanonicalJson $Source
        $destinationCanonical = Get-CanonicalJson $Destination
        $sameJson = [string]::Equals(
            $sourceCanonical,
            $destinationCanonical,
            [StringComparison]::Ordinal)

        if ($sameJson) {
            $detail = "semantic JSON match"
            if (-not [string]::Equals($sourceHash, $destinationHash, [StringComparison]::OrdinalIgnoreCase)) {
                $detail += "; raw SHA differs only by JSON serialization/line endings"
            }
            $detail += "; source=$sourceHash; deployed=$destinationHash; path=$Destination"
        }
        else {
            $detail = "semantic JSON differs; source=$sourceHash; deployed=$destinationHash; path=$Destination"
        }

        return [pscustomobject][ordered]@{
            success = $sameJson
            comparison = "semantic-json"
            detail = $detail
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            success = $false
            comparison = "semantic-json"
            detail = "JSON comparison failed: $($_.Exception.Message); path=$Destination"
        }
    }
}

$identityNamePattern = $AppIdPattern -replace "_\*$", ""
$packages = @(Get-AppxPackage | Where-Object {
    $_.Name -like $identityNamePattern -or
    $_.PackageFamilyName -like $AppIdPattern
} | Sort-Object Version -Descending)

$package = $null
if ($packages.Count -gt 0) {
    $package = $packages[0]
}

if ($null -eq $package) {
    Add-Check "Private QA MSIX installed" $false "No package matched '$AppIdPattern'."
}
else {
    Add-Check "Private QA MSIX installed" $true ("{0} {1}" -f $package.Name, $package.Version)
}

$bundledRoot = ""
if ($null -ne $package) {
    $bundledRoot = Join-Path $package.InstallLocation "MSFS\Packages\simtech-simvoice-wasm-bridge"

    $manifest = Join-Path $bundledRoot "manifest.json"
    $layout = Join-Path $bundledRoot "layout.json"
    $module = Join-Path $bundledRoot "modules\SimVoiceWasmBridge.wasm"

    Add-Check "WASM manifest bundled in MSIX" (Test-Path -LiteralPath $manifest -PathType Leaf) $manifest
    Add-Check "WASM layout bundled in MSIX" (Test-Path -LiteralPath $layout -PathType Leaf) $layout
    Add-Check "WASM module bundled in MSIX" (Test-Path -LiteralPath $module -PathType Leaf) $module

    if ((Test-Path -LiteralPath $layout -PathType Leaf) -and
        (Test-Path -LiteralPath $module -PathType Leaf)) {
        try {
            $layoutJson = Get-Content -LiteralPath $layout -Raw -Encoding UTF8 | ConvertFrom-Json
            $moduleEntry = $null
            foreach ($entry in @($layoutJson.content)) {
                if (([string]$entry.path).Replace("\", "/") -eq "modules/SimVoiceWasmBridge.wasm") {
                    $moduleEntry = $entry
                    break
                }
            }

            $actualSize = [int64](Get-Item -LiteralPath $module).Length
            $declaredSize = -1L
            if ($null -ne $moduleEntry) {
                $declaredSize = [int64]$moduleEntry.size
            }

            Add-Check "WASM layout size matches module" `
                (($null -ne $moduleEntry) -and ($declaredSize -eq $actualSize)) `
                ("layout={0}; actual={1}" -f $declaredSize, $actualSize)
        }
        catch {
            Add-Check "WASM layout size matches module" $false $_.Exception.Message
        }
    }
}

$communityRoots = @(Get-CommunityRoots)
Add-Check "MSFS 2024 Community folder detected" `
    ($communityRoots.Count -gt 0) `
    ($communityRoots -join "; ")

$relativeFiles = @(
    [pscustomobject][ordered]@{ path = "manifest.json"; json = $true },
    [pscustomobject][ordered]@{ path = "layout.json"; json = $true },
    [pscustomobject][ordered]@{ path = "modules\SimVoiceWasmBridge.wasm"; json = $false }
)

$payloadResults = @()
if ($null -ne $package -and $communityRoots.Count -gt 0) {
    $deadline = (Get-Date).AddSeconds($StateWaitSeconds)

    do {
        $payloadResults = @()

        foreach ($communityRoot in $communityRoots) {
            $destinationRoot = Join-Path $communityRoot "simtech-simvoice-wasm-bridge"

            foreach ($relativeFile in $relativeFiles) {
                $relativePath = [string]$relativeFile.path
                $comparison = Get-PayloadComparison `
                    -Source (Join-Path $bundledRoot $relativePath) `
                    -Destination (Join-Path $destinationRoot $relativePath) `
                    -JsonSemantic ([bool]$relativeFile.json)

                $payloadResults += [pscustomobject][ordered]@{
                    communityRoot = [string]$communityRoot
                    relativeFile = $relativePath
                    success = [bool]$comparison.success
                    comparison = [string]$comparison.comparison
                    detail = [string]$comparison.detail
                }
            }
        }

        $failedPayloadItems = @($payloadResults | Where-Object { -not [bool]$_.success })
        if ($payloadResults.Count -gt 0 -and $failedPayloadItems.Count -eq 0) {
            break
        }

        Start-Sleep -Milliseconds 500
    }
    while ((Get-Date) -lt $deadline)

    foreach ($payloadEntry in $payloadResults) {
        Add-Check `
            ("Community payload current: " + [string]$payloadEntry.relativeFile) `
            ([bool]$payloadEntry.success) `
            ([string]$payloadEntry.detail)
    }
}

$failedChecks = @($script:checks | Where-Object { -not [bool]$_.success })
$success = ($failedChecks.Count -eq 0)

$packageFamilyName = ""
if ($null -ne $package) {
    $packageFamilyName = [string]$package.PackageFamilyName
}

$report = [ordered]@{
    schemaVersion = 5
    qaVersion = "2.7.9"
    appVersion = "1.0.17.0"
    generatedAt = (Get-Date).ToString("o")
    success = $success
    packageFamilyName = $packageFamilyName
    communityRoots = @($communityRoots)
    comparisonPolicy = [ordered]@{
        manifestJson = "semantic JSON"
        layoutJson = "semantic JSON"
        wasmModule = "binary SHA-256"
    }
    checks = @($script:checks)
}

$reportPath = Join-Path $OutputDirectory "precertification-payload-result.json"
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($success) {
    Write-Host ""
    Write-Host "PRE-CERTIFICATION PAYLOAD: PASS" -ForegroundColor Green
    Write-Host ("Report: {0}" -f $reportPath) -ForegroundColor DarkGray
    exit 0
}

Write-Host ""
Write-Host "PRE-CERTIFICATION PAYLOAD: FAIL" -ForegroundColor Red
Write-Host ("Report: {0}" -f $reportPath) -ForegroundColor DarkGray
exit 1