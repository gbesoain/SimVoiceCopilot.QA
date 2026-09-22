#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Text {
    param([string]$Text,[string]$Needle,[string]$Label)
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing: {1}" -f $Label,$Needle)
    }
}

$bridgePath = Join-Path $WindowsProjectRoot 'Msfs2024FocusInstrumentBridge.cs'
$controllerPath = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
if (-not (Test-Path -LiteralPath $bridgePath -PathType Leaf)) { throw "Missing $bridgePath" }
if (-not (Test-Path -LiteralPath $controllerPath -PathType Leaf)) { throw "Missing $controllerPath" }

$bridge = [IO.File]::ReadAllText($bridgePath)
$controller = [IO.File]::ReadAllText($controllerPath)

Require-Text $bridge 'TryMarkHighlight2024(' 'R2N MARK entry point'
Require-Text $bridge 'ClearMarkHighlight2024(' 'R2N MARK clear entry point'
Require-Text $bridge 'MarkPacketSize2024 = 1 + 16 + 4 + 1 + 1 + 1 + FixedStringBytes + FixedStringBytes' 'R2N MSFS 2024 packet layout'
Require-Text $bridge '"msfs2024-extended-focus-v1"' 'R2N packet diagnostic marker'
Require-Text $bridge 'WriteSingle(packet, ref offset, 0.0f);' 'R2N highlight color R'
Require-Text $bridge 'WriteSingle(packet, ref offset, 1.0f);' 'R2N FLOAT4 packet values'
Require-Text $bridge 'setCamera: false' 'R2N camera-off contract'
Require-Text $bridge 'setPulse: false' 'R2N pulse-off contract'
Require-Text $bridge 'setEyeIcon: false' 'R2N eye-icon-off contract'

$markStart = $controller.IndexOf('        private bool MarkCurrentChecklistItem(',[System.StringComparison]::Ordinal)
$markEnd = $controller.IndexOf('        private void ObserveMarkCompatibilitySidecar(',[System.StringComparison]::Ordinal)
if ($markStart -lt 0 -or $markEnd -le $markStart) { throw 'Unable to isolate MarkCurrentChecklistItem.' }
$markMethod = $controller.Substring($markStart,$markEnd-$markStart)
Require-Text $markMethod 'Msfs2024FocusInstrumentBridge.TryMarkHighlight2024(' 'R2N controller MARK route'
if ($markMethod.IndexOf('Msfs2024FocusInstrumentBridge.TryFocus(',[System.StringComparison]::Ordinal) -ge 0) {
    throw 'MARK still calls the legacy TryFocus packet.'
}
if ($markMethod.IndexOf('CHECKLIST_START_HELP',[System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw 'MARK contains CHECKLIST_START_HELP.'
}

$clearStart = $controller.IndexOf('        private void ClearChecklistMark(',[System.StringComparison]::Ordinal)
$clearEnd = $controller.IndexOf('        private bool FocusCurrentChecklistItem(',[System.StringComparison]::Ordinal)
if ($clearStart -lt 0 -or $clearEnd -le $clearStart) { throw 'Unable to isolate ClearChecklistMark.' }
$clearMethod = $controller.Substring($clearStart,$clearEnd-$clearStart)
Require-Text $clearMethod 'Msfs2024FocusInstrumentBridge.ClearMarkHighlight2024(' 'R2N controller MARK clear route'

# FOCUS remains on the existing legacy path. R2N must not route FOCUS through the MARK packet.
$focusStart = $controller.IndexOf('        private bool FocusCurrentChecklistItem(',[System.StringComparison]::Ordinal)
$focusEnd = $controller.IndexOf('        private static string BuildGuidedChecklistItemKey(',[System.StringComparison]::Ordinal)
if ($focusStart -lt 0 -or $focusEnd -le $focusStart) { throw 'Unable to isolate FocusCurrentChecklistItem.' }
$focusMethod = $controller.Substring($focusStart,$focusEnd-$focusStart)
Require-Text $focusMethod 'Msfs2024FocusInstrumentBridge.TryFocus(' 'baseline FOCUS route preserved'
if ($focusMethod.IndexOf('TryMarkHighlight2024(',[System.StringComparison]::Ordinal) -ge 0) {
    throw 'FOCUS was incorrectly routed through the R2N MARK packet.'
}

Write-Host '============================================================'
Write-Host ' SVC 1.1.1.0 R2N MARK ACTION 2024 QA: PASS'
Write-Host '============================================================'
Write-Host 'MARK uses the extended MSFS 2024 FocusInstrumentAction packet; FOCUS remains on its baseline path.'
