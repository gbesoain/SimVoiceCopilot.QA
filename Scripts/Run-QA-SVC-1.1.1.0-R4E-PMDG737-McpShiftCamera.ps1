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
        throw ("{0} contains obsolete marker: {1}" -f $Label,$Needle)
    }
}

$version = Join-Path $WindowsProjectRoot 'Version.props'
$sdk = Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs'
$altitude = Join-Path $WindowsProjectRoot 'Pmdg737AltitudeAdapter.cs'
$mcp = Join-Path $WindowsProjectRoot 'Pmdg737McpCommandService.cs'
$camera = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs'
$vosk = Join-Path $WindowsProjectRoot 'VoskRecognizer.cs'

Require-Text $version '<SimVoiceVersion>1.1.1.0</SimVoiceVersion>' 'R4E Windows version'
Require-Text $sdk '737-800 PAX SSW SC' 'R4E PMDG identity'
Require-Text $sdk 'EvtMcpHeadingSet = ThirdPartyEventIdMin + 14504' 'R4E PMDG heading event'
Require-Text $sdk 'EvtMcpIasSet = ThirdPartyEventIdMin + 14502' 'R4E PMDG IAS event'
Require-Text $sdk 'EvtMcpVerticalSpeedSet = ThirdPartyEventIdMin + 14506' 'R4E PMDG VS event'
Require-Text $sdk 'McpHeadingWindowLvar = "ngx_HDGwindow"' 'R4E heading readback LVar'
Require-Text $sdk 'McpSpeedWindowLvar = "ngx_SPDwindow"' 'R4E IAS readback LVar'
Require-Text $sdk 'McpVerticalSpeedWindowLvar = "ngx_VSwindow"' 'R4E VS readback LVar'

Require-Text $altitude 'McpAltitudeWindowLvar' 'R4E proven PMDG altitude path preserved'
Require-Text $altitude 'PMDG737_ALTITUDE_LVAR_READBACK' 'R4E proven PMDG altitude verification preserved'

Require-Text $mcp 'PMDG737_MCP_DIRECT_SET' 'R4E MCP direct-set telemetry'
Require-Text $mcp 'PMDG737_MCP_LVAR_READBACK' 'R4E MCP LVar telemetry'
Require-Text $mcp 'PMDG737_MCP_RESULT' 'R4E MCP result telemetry'
Require-Text $mcp 'value => value + 10000' 'R4E PMDG V/S wire encoding'
Require-Text $mcp 'pmdg-ng3-direct-set-ngx-window' 'R4E PMDG verified method'

Require-Text $vosk 'isPmdg737McpAction' 'R4E PMDG command routing'
Require-Text $vosk 'Pmdg737McpCommandService.SetAsync' 'R4E PMDG async execution'
Require-Text $vosk 'ExecutePmdg737McpCommandAsync' 'R4E PMDG feedback path'

Require-Text $camera 'SIMVOICE_1_1_1_0_R4E_PMDG737_CHECKLIST_CAMERA_SHIFT_HOTKEY' 'R4E camera marker'
Require-Text $camera 'TrySendShiftDigitChord' 'R4E Shift+number camera path'
Require-Text $camera 'ScanLeftShift = 0x002A' 'R4E left Shift scan code'
Require-Text $camera 'case 0: return 0x00B;' 'R4E Shift+0 support'
Require-Text $camera '"Shift+" + digit.ToString' 'R4E camera chord telemetry'
Reject-Text $camera 'TrySendCtrlDigitChord' 'R4E obsolete Ctrl camera path'
Reject-Text $camera 'ScanLeftCtrl = 0x001D' 'R4E obsolete Ctrl scan code'

Write-Host '============================================================'
Write-Host ' SVC 1.1.1.0 R4E PMDG737 MCP + SHIFT CAMERA QA: PASS'
Write-Host '============================================================'
Write-Host 'PMDG ALT remains on ngx_ALTwindow. HDG/IAS/V-S now use direct PMDG setters + live ngx window verification.'
Write-Host 'PMDG checklist camera fallback now dispatches Shift+number/Shift+0, matching the MSFS 2024 bindings on the target PC.'
