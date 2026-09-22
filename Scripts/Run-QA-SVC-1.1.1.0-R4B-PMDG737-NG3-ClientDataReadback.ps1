#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WindowsProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Text {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Needle,
        [Parameter(Mandatory=$true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("{0} missing file: {1}" -f $Label,$Path)
    }

    $text = Get-Content -LiteralPath $Path -Raw
    if ($text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing marker: {1}" -f $Label,$Needle)
    }
}

$bridge = Join-Path $WindowsProjectRoot 'SimConnectBridge.cs'
$reader = Join-Path $WindowsProjectRoot 'Pmdg737Ng3ClientDataReader.cs'
$sdk = Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs'
$adapter = Join-Path $WindowsProjectRoot 'Pmdg737AltitudeAdapter.cs'

Require-Text $bridge 'Pmdg737Ng3ClientDataReader.Attach(simconnect);' 'R4B SimConnect attach'
Require-Text $bridge 'Pmdg737Ng3ClientDataReader.Detach();' 'R4B SimConnect detach'
Require-Text $reader 'MapClientDataNameToID(' 'R4B ClientData mapping'
Require-Text $reader 'Pmdg737Ng3Sdk.DataName' 'R4B ClientData area'
Require-Text $reader 'RegisterStruct<SIMCONNECT_RECV_CLIENT_DATA, PmdgMcpAltitudeData>' 'R4B managed ClientData struct'
Require-Text $reader 'SIMCONNECT_CLIENT_DATA_PERIOD.ONCE' 'R4B one-shot readback'
Require-Text $sdk 'internal const string DataName = "PMDG_NG3_Data";' 'R4B SDK data name'
Require-Text $sdk 'internal const uint McpAltitudeOffset = 430;' 'R4B SDK MCP offset'
Require-Text $sdk 'internal const uint McpAltitudeSize = 2;' 'R4B SDK MCP size'
Require-Text $adapter 'PMDG737_ALTITUDE_SDK_READBACK' 'R4B adapter telemetry'
Require-Text $adapter 'pmdg-ng3-direct-alt-set-clientdata' 'R4B verified method'
Require-Text $adapter 'Pmdg737Ng3ClientDataReader.ReadMcpAltitudeAsync' 'R4B SDK readback route'

Write-Host '============================================================'
Write-Host ' SVC 1.1.1.0 R4B PMDG737 NG3 CLIENTDATA READBACK QA: PASS'
Write-Host '============================================================'
