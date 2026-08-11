[CmdletBinding()]
param(
    [string]$FinalRegressionRoot = "",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($FinalRegressionRoot)) {
    $FinalRegressionRoot = Join-Path $projectRoot "QA-Runs\FinalRegression"
}
if (-not (Test-Path -LiteralPath $FinalRegressionRoot -PathType Container)) {
    throw "Final regression directory was not found: $FinalRegressionRoot"
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot "QA-Runs\FinalPackages"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Get-LatestPhaseSummary {
    param([Parameter(Mandatory = $true)][string]$PhaseName)

    $matches = New-Object 'System.Collections.Generic.List[object]'
    $files = @(Get-ChildItem -LiteralPath $FinalRegressionRoot -Filter "final-phase-summary.json" -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        try {
            $summary = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$summary.phase -eq $PhaseName) {
                $matches.Add([pscustomobject]@{
                    File = $file
                    Directory = $file.Directory
                    Summary = $summary
                    GeneratedAt = [DateTimeOffset]::Parse([string]$summary.generatedAt)
                })
            }
        }
        catch {
            Write-Warning "Ignoring invalid phase summary '$($file.FullName)': $($_.Exception.Message)"
        }
    }

    return @($matches | Sort-Object GeneratedAt -Descending | Select-Object -First 1)
}

$requiredPhases = @("English", "Spanish", "G2")
$selected = New-Object 'System.Collections.Generic.List[object]'
$missing = New-Object 'System.Collections.Generic.List[string]'
$failed = New-Object 'System.Collections.Generic.List[string]'

foreach ($phase in $requiredPhases) {
    $match = Get-LatestPhaseSummary -PhaseName $phase
    if ($null -eq $match -or @($match).Count -eq 0) {
        $missing.Add($phase)
        continue
    }
    $item = @($match)[0]
    $selected.Add($item)
    if (-not [bool]$item.Summary.success) { $failed.Add($phase) }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$staging = Join-Path $env:TEMP ("SimVoiceCopilot-FinalRegression-{0}-{1}" -f $stamp, [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $staging -Force | Out-Null

try {
    foreach ($item in $selected) {
        $phaseName = [string]$item.Summary.phase
        $destination = Join-Path $staging $phaseName
        Copy-Item -LiteralPath $item.Directory.FullName -Destination $destination -Recurse -Force
    }

    $success = ($missing.Count -eq 0 -and $failed.Count -eq 0)
    $summary = [ordered]@{
        schemaVersion = 1
        qaVersion = "2.7.5"
        appVersion = "1.0.17.0"
        generatedAt = (Get-Date).ToString("o")
        success = $success
        requiredPhases = $requiredPhases
        missingPhases = @($missing)
        failedPhases = @($failed)
        phases = @($selected | ForEach-Object {
            [ordered]@{
                phase = [string]$_.Summary.phase
                success = [bool]$_.Summary.success
                generatedAt = [string]$_.Summary.generatedAt
                sourceDirectory = $_.Directory.FullName
                copiedDirectory = [string]$_.Summary.phase
            }
        })
    }
    $summaryPath = Join-Path $staging "final-certification-summary.json"
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    $zipPath = Join-Path $OutputDirectory ("SimVoiceCopilot-1.0.17.0-FinalRegression-{0}.zip" -f $stamp)
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zipPath -CompressionLevel Optimal

    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $receipt = [ordered]@{
        zipPath = $zipPath
        sha256 = $hash
        success = $success
        summaryPathInsideZip = "final-certification-summary.json"
    }
    $receiptPath = $zipPath + ".json"
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

    Write-Host ""
    if ($success) {
        Write-Host "FINAL CERTIFICATION REGRESSION PACKAGE: PASS" -ForegroundColor Green
    }
    else {
        Write-Host "FINAL CERTIFICATION REGRESSION PACKAGE: INCOMPLETE/FAIL" -ForegroundColor Red
        if ($missing.Count -gt 0) { Write-Host ("Missing phases: {0}" -f ($missing -join ", ")) -ForegroundColor Yellow }
        if ($failed.Count -gt 0) { Write-Host ("Failed phases : {0}" -f ($failed -join ", ")) -ForegroundColor Yellow }
    }
    Write-Host ("ZIP    : {0}" -f $zipPath) -ForegroundColor Cyan
    Write-Host ("SHA256 : {0}" -f $hash) -ForegroundColor DarkGray
    Write-Host ("Receipt: {0}" -f $receiptPath) -ForegroundColor DarkGray

    if ($success) { exit 0 }
    exit 1
}
finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}
