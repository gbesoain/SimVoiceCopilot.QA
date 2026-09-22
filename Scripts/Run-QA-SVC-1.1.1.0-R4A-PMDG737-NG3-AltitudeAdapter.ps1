#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WindowsProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Text,[string]$Needle,[string]$Label)
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing: {1}" -f $Label,$Needle)
    }
}

$versionPath = Join-Path $WindowsProjectRoot 'Version.props'
$sdkPath = Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs'
$adapterPath = Join-Path $WindowsProjectRoot 'Pmdg737AltitudeAdapter.cs'
$servicePath = Join-Path $WindowsProjectRoot 'AutopilotAltitudeService.cs'
$configPath = Join-Path $WindowsProjectRoot 'aircraft_event_map.json'

foreach ($path in @($versionPath,$sdkPath,$adapterPath,$servicePath,$configPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ("Required R4A file missing: {0}" -f $path)
    }
}

[xml]$versionXml = Get-Content -LiteralPath $versionPath -Raw
$version = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
if ($null -eq $version -or $version.InnerText.Trim() -ne '1.1.1.0') {
    throw 'R4A must keep Windows version 1.1.1.0.'
}

$sdk = Get-Content -LiteralPath $sdkPath -Raw
$adapter = Get-Content -LiteralPath $adapterPath -Raw
$service = Get-Content -LiteralPath $servicePath -Raw

Assert-Contains $sdk 'EvtMcpAltitudeSet = ThirdPartyEventIdMin + 14505' 'PMDG SDK direct altitude constant'
Assert-Contains $sdk '737-800 PAX SSW SC' 'Observed PMDG 737-800 title'
Assert-Contains $adapter 'Pmdg737Ng3Sdk.McpAltitudeSetKeyEvent' 'PMDG altitude direct Key Event route'
Assert-Contains $adapter 'PMDG737_ALTITUDE_DIRECT_SET' 'PMDG altitude diagnostic'
Assert-Contains $adapter 'PMDG737_ALTITUDE_READBACK' 'PMDG altitude read-back diagnostic'
Assert-Contains $adapter 'PMDG737_ALTITUDE_RESULT' 'PMDG altitude result diagnostic'
Assert-Contains $service 'new Pmdg737AltitudeAdapter()' 'PMDG adapter registration'
Assert-Contains $service 'pmdg-737-ng3-title-match' 'PMDG identity-first routing'
Assert-Contains $service 'requestedAdapter.Equals("pmdg-737-ng3"' 'PMDG profile routing'

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$profile = @($config.profiles | Where-Object { $_.id -eq 'pmdg-737-ng3' }) | Select-Object -First 1
if ($null -eq $profile) { throw 'PMDG profile pmdg-737-ng3 is missing.' }
if ($profile.adapter -ne 'pmdg-737-ng3') { throw 'PMDG profile adapter is not pmdg-737-ng3.' }
if ($profile.absoluteEvent -ne '#84137') { throw 'PMDG direct altitude event must be #84137.' }
if (@($profile.titleContainsAny) -notcontains '737-800 PAX SSW SC') {
    throw 'Observed PMDG title 737-800 PAX SSW SC is missing from the profile.'
}
if ($profile.enableIncrementalFallback -ne $false) {
    throw 'PMDG adapter must not fall back to generic incremental altitude events.'
}

Write-Host '============================================================'
Write-Host ' SVC 1.1.1.0 R4A PMDG 737 NG3 ALTITUDE ADAPTER QA: PASS'
Write-Host '============================================================'
Write-Host 'PMDG #84137 direct MCP altitude route is installed; generic fallback remains disabled.'
exit 0
