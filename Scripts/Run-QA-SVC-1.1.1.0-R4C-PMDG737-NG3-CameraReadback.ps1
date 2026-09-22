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

function Reject-Text {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Needle,
        [Parameter(Mandatory=$true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("{0} missing file: {1}" -f $Label,$Path)
    }

    $text = Get-Content -LiteralPath $Path -Raw
    if ($text.IndexOf($Needle,[System.StringComparison]::Ordinal) -ge 0) {
        throw ("{0} contains forbidden text: {1}" -f $Label,$Needle)
    }
}

$version = Join-Path $WindowsProjectRoot 'Version.props'
$sdk = Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs'
$reader = Join-Path $WindowsProjectRoot 'Pmdg737Ng3ClientDataReader.cs'
$altitude = Join-Path $WindowsProjectRoot 'Pmdg737AltitudeAdapter.cs'
$camera = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs'
$controller = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$bridge = Join-Path $WindowsProjectRoot 'SimConnectBridge.cs'

Require-Text $version '<SimVoiceVersion>1.1.1.0</SimVoiceVersion>' 'R4C Windows version'
Require-Text $sdk '737-800 PAX SSW SC' 'R4C PMDG identity'
Require-Text $sdk 'EvtMcpAltitudeSet = ThirdPartyEventIdMin + 14505' 'R4C proven MCP ALT write event'
Require-Text $sdk 'ClientDataScanWordCount = 512' 'R4C adaptive ClientData scan'

Require-Text $bridge 'Pmdg737Ng3ClientDataReader.Attach(simconnect);' 'R4C SimConnect ClientData attach'
Require-Text $bridge 'Pmdg737Ng3ClientDataReader.Detach();' 'R4C SimConnect ClientData detach'
Require-Text $reader 'PMDG737_CLIENTDATA_OFFSET_DISCOVERED' 'R4C runtime MCP offset learning'
Require-Text $reader 'fixedOffsetUsed' 'R4C fixed-offset telemetry'
Require-Text $reader '["fixedOffsetUsed"] = false' 'R4C fixed offset disabled'
Reject-Text $reader 'McpAltitudeOffset = 430' 'R4C obsolete MCP offset'
Require-Text $altitude 'pmdg-ng3-direct-alt-set-adaptive-clientdata' 'R4C authoritative PMDG altitude verification'
Require-Text $altitude 'ReadWordSnapshotAsync' 'R4C pre-write ClientData snapshot'

Require-Text $camera 'PMDG737_CHECKLIST_CAMERA_FOCUS' 'R4C PMDG camera telemetry'
Require-Text $camera 'CAMERA VIEW TYPE AND INDEX:0' 'R4C instrument camera type'
Require-Text $camera 'CAMERA VIEW TYPE AND INDEX:1' 'R4C instrument camera index'
Require-Text $camera 'CAMERA SUBSTATE,Enum' 'R4C instrument camera substate'
Require-Text $camera 'SubCategory' 'R4C cameras.cfg parser'
Require-Text $camera 'Instrument' 'R4C instrument camera catalog'

Require-Text $controller 'Pmdg737ChecklistCameraAdapter.IsCurrentAircraftPmdg737()' 'R4C PMDG camera route'
Require-Text $controller 'Pmdg737ChecklistCameraAdapter.TryFocusAsync(' 'R4C PMDG camera fallback call'
Require-Text $controller 'Msfs2024FocusInstrumentBridge.TryFocus(' 'R4C generic non-PMDG fallback preserved'
Require-Text $controller 'EFB_NATIVE_CHECKLIST_CALLBACK_QUEUED' 'R4C R2R checklist delivery preserved'

Write-Host '============================================================'
Write-Host ' SVC 1.1.1.0 R4C PMDG737 CAMERA + READBACK QA: PASS'
Write-Host '============================================================'
Write-Host 'PMDG MCP ALT uses the proven direct setter plus adaptive ClientData verification.'
Write-Host 'PMDG checklist helper keeps highlight ownership; SVC supplies only the missing camera movement.'
