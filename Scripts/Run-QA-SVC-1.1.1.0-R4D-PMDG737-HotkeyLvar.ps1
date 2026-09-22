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
        throw ("{0} contains obsolete path: {1}" -f $Label,$Needle)
    }
}

$version = Join-Path $WindowsProjectRoot 'Version.props'
$sdk = Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs'
$altitude = Join-Path $WindowsProjectRoot 'Pmdg737AltitudeAdapter.cs'
$camera = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs'
$controller = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'

Require-Text $version '<SimVoiceVersion>1.1.1.0</SimVoiceVersion>' 'R4D Windows version'

Require-Text $sdk '737-800 PAX SSW SC' 'R4D PMDG identity'
Require-Text $sdk 'EvtMcpAltitudeSet = ThirdPartyEventIdMin + 14505' 'R4D proven MCP ALT write event'
Require-Text $sdk 'McpAltitudeWindowLvar = "ngx_ALTwindow"' 'R4D PMDG MCP window LVar'

Require-Text $altitude 'PMDG737_ALTITUDE_LVAR_READBACK' 'R4D fast altitude readback telemetry'
Require-Text $altitude 'pmdg-ng3-direct-alt-set-ngx-altwindow' 'R4D LVar verification result'
Require-Text $altitude 'SimVoiceWasmBridgeClient.ExecuteRpnAndReadAsync' 'R4D WASM RPN readback'
Require-Text $altitude 'clientDataRequiredForThisOperation"] = false' 'R4D ClientData independence'
Reject-Text $altitude 'ReadMcpAltitudeAsync' 'R4D obsolete ClientData altitude readback'
Reject-Text $altitude 'ReadWordSnapshotAsync' 'R4D obsolete adaptive ClientData scan'
Reject-Text $altitude 'ReadAutopilotSelectedAltitudeAsync' 'R4D obsolete generic AP slot verification'

Require-Text $camera 'SIMVOICE_1_1_1_0_R4D_PMDG737_CHECKLIST_CAMERA_HOTKEY' 'R4D camera marker'
Require-Text $camera 'TrySendCtrlDigitChord' 'R4D PMDG Ctrl+number camera path'
Require-Text $camera 'PMDG737_CAMERA_HOTKEY_SENT' 'R4D camera dispatch telemetry'
Require-Text $camera 'SendInput(' 'R4D real keyboard input'
Require-Text $camera 'ScanLeftCtrl = 0x001D' 'R4D left Ctrl scan code'
Require-Text $camera 'FlightSimulator' 'R4D foreground safety gate'

Require-Text $controller 'SchedulePmdg737CameraFallbackFromCapture(captureReason);' 'R4D reliable capture trigger'
Require-Text $controller 'PMDG737_CAMERA_FALLBACK_FROM_CAPTURE' 'R4D delayed PMDG camera telemetry'
Require-Text $controller 'await Task.Delay(420)' 'R4D native highlight lead time'
Require-Text $controller 'EFB_NATIVE_CHECKLIST_CALLBACK_QUEUED' 'R4D R2R restart delivery preserved'

Write-Host '============================================================'
Write-Host ' SVC 1.1.1.0 R4D PMDG737 HOTKEY + LVAR QA: PASS'
Write-Host '============================================================'
Write-Host 'PMDG MCP ALT keeps the proven direct event and verifies via ngx_ALTwindow.'
Write-Host 'PMDG native checklist helper keeps highlight ownership; camera fallback is triggered from the reliable pre-helper capture event and dispatches Ctrl+instrument-view.'
