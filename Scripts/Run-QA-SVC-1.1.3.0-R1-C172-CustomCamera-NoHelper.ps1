#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-RequiredText {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing required file: $Path" }
    return [IO.File]::ReadAllText($Path)
}
function Require-Contains {
    param([string]$Text,[string]$Needle,[string]$Label)
    if ($Text.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "$Label missing semantic: $Needle" }
}
function Require-Regex {
    param([string]$Text,[string]$Pattern,[string]$Label)
    if (-not [regex]::IsMatch($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::Singleline)) { throw "$Label missing regex semantic: $Pattern" }
}

try {
    $version = Read-RequiredText (Join-Path $WindowsProjectRoot 'Version.props')
    Require-Contains $version '<SimVoiceVersion>1.1.3.0</SimVoiceVersion>' 'Windows version'
    Require-Contains $version '<SimVoiceDisplayVersion>1.1.3.0</SimVoiceDisplayVersion>' 'Windows display version'

    $controller = Read-RequiredText (Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs')
    Require-Contains $controller 'SIMVOICE_1_1_3_0_R1_USER_CAMERA_NO_NATIVE_HELPER_DIRECT' 'R1 no-helper direct-dispatch marker'
    Require-Contains $controller 'CHECKLIST_USER_CAMERA_NATIVE_NO_HELPER_DIRECT' 'R1 no-helper diagnostic'
    Require-Contains $controller 'snapshot.CurrentNativeVisualHelperAvailable || pmdgNativeCameraTarget' 'R1 helper-aware deferral'
    Require-Contains $controller 'Pmdg737ChecklistCameraAdapter.IsCurrentAircraftPmdg737()' 'R1 PMDG compatibility guard'
    Require-Contains $controller 'ChecklistCameraBindingDispatcher.TryDispatch' 'Existing direct camera dispatcher continuity'
    Require-Contains $controller 'CHECKLIST_USER_CAMERA_NATIVE_DEFERRED' 'R4R10 helper-first single-authority continuity'

    # The broad R4R10 condition that deferred every native:* target is the regression.
    $broadPattern = 'bool\s+nativeUserCameraDeferredToEfb\s*=\s*hasUserCameraBinding\s*&&\s*!string\.IsNullOrWhiteSpace\(snapshot\.CurrentTarget\)\s*&&\s*snapshot\.CurrentTarget\.StartsWith\("native:",\s*StringComparison\.OrdinalIgnoreCase\)\s*;'
    if ([regex]::IsMatch($controller,$broadPattern,[Text.RegularExpressions.RegexOptions]::Singleline)) {
        throw 'Regression remains: all native:* user cameras are still deferred to EFB regardless of helper availability.'
    }

    Require-Regex $controller 'bool\s+nativeUserCameraTarget\s*=\s*hasUserCameraBinding.*?bool\s+nativeUserCameraDeferredToEfb\s*=\s*nativeUserCameraTarget\s*&&\s*\(snapshot\.CurrentNativeVisualHelperAvailable\s*\|\|\s*pmdgNativeCameraTarget\)\s*;' 'R1 exact helper-aware policy'

    Write-Host 'QA STATIC/SOURCE: PASS' -ForegroundColor Green
    Write-Host 'Windows/MSIX: 1.1.3.0 | EFB/WASM/Backend unchanged by R1' -ForegroundColor Green
    Write-Host 'Physical QA required: C172SP G1000 Before Engine Start items 1-3 custom CAM + helper item 4 + PMDG sanity.' -ForegroundColor Yellow
    exit 0
}
catch {
    Write-Host ('QA STATIC/SOURCE: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
