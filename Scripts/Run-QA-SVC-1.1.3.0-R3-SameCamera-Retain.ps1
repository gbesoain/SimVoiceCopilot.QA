param(
    [Parameter(Mandatory = $false)]
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp"
)

$ErrorActionPreference = "Stop"

function Pass([string]$Message) {
    Write-Host ("QA STATIC/SOURCE: PASS - " + $Message)
}

function Fail([string]$Message) {
    Write-Host ("QA STATIC/SOURCE: FAIL - " + $Message)
    exit 1
}

try {
    if ([string]::IsNullOrWhiteSpace($WindowsProjectRoot)) {
        Fail "WindowsProjectRoot is empty."
    }

    $root = [System.IO.Path]::GetFullPath($WindowsProjectRoot)

    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Fail ("Windows project root not found: " + $root)
    }

    $versionProps = Join-Path $root "Version.props"
    $controller   = Join-Path $root "SimVoiceEfbLocalController.cs"

    if (-not (Test-Path -LiteralPath $versionProps -PathType Leaf)) {
        Fail ("Version.props not found: " + $versionProps)
    }

    if (-not (Test-Path -LiteralPath $controller -PathType Leaf)) {
        Fail ("SimVoiceEfbLocalController.cs not found: " + $controller)
    }

    $versionText = [System.IO.File]::ReadAllText($versionProps)
    $source      = [System.IO.File]::ReadAllText($controller)

    # Version gate: R3 must remain Windows/MSIX 1.1.3.0.
    if ($versionText -notmatch '<SimVoiceVersion>\s*1\.1\.3\.0\s*</SimVoiceVersion>') {
        Fail "SimVoiceVersion is not 1.1.3.0 in Version.props."
    }

    if ($versionText -notmatch '<SimVoiceDisplayVersion>\s*1\.1\.3\.0\s*</SimVoiceDisplayVersion>') {
        Fail "SimVoiceDisplayVersion is not 1.1.3.0 in Version.props."
    }
    Pass "Version.props = 1.1.3.0"

    # Baseline markers that R3 depends on.
    $requiredMarkers = @(
        'SIMVOICE_1_1_3_0_R1_USER_CAMERA_NO_NATIVE_HELPER_DIRECT',
        'SIMVOICE_1_1_3_0_R2_FIRST_ITEM_CAMERA_SETTLE',
        'SIMVOICE_1_1_3_0_R3_SAME_CAMERA_RETAIN'
    )

    foreach ($marker in $requiredMarkers) {
        if ($source.IndexOf($marker, [System.StringComparison]::Ordinal) -lt 0) {
            Fail ("Missing marker: " + $marker)
        }
    }
    Pass "R1/R2/R3 markers present"

    # R3 policy contract.
    $requiredSourceTokens = @(
        'retainSameNativeNoHelperCamera',
        'forceUserCameraDispatch',
        'nativeUserCameraTarget',
        'nativeUserCameraDeferredToEfb',
        'CHECKLIST_USER_CAMERA_SAME_VIEW_RETAINED_R3'
    )

    foreach ($token in $requiredSourceTokens) {
        if ($source.IndexOf($token, [System.StringComparison]::Ordinal) -lt 0) {
            Fail ("Missing R3 token: " + $token)
        }
    }
    Pass "R3 same-camera retain policy tokens present"

    # Ensure the R3 decision really derives force from the no-helper retain decision.
    if ($source -notmatch 'bool\s+retainSameNativeNoHelperCamera\s*=\s*[\s\S]{0,300}?nativeUserCameraTarget\s*&&\s*[\s\S]{0,120}?!\s*nativeUserCameraDeferredToEfb\s*;') {
        Fail "R3 retainSameNativeNoHelperCamera expression not found."
    }

    if ($source -notmatch 'bool\s+forceUserCameraDispatch\s*=\s*!\s*retainSameNativeNoHelperCamera\s*;') {
        Fail "R3 forceUserCameraDispatch expression not found."
    }

    if ($source -notmatch 'ChecklistCameraBindingDispatcher\.TryDispatch\s*\([\s\S]{0,1400}?forceUserCameraDispatch') {
        Fail "TryDispatch does not appear to use forceUserCameraDispatch."
    }
    Pass "R3 force=false path is wired into TryDispatch"

    # R2 replay must remain present and forced independently of R3.
    if ($source.IndexOf('checklist-start-first-item-settled', [System.StringComparison]::Ordinal) -lt 0) {
        Fail "R2 settled replay reason is missing."
    }

    if ($source.IndexOf('CHECKLIST_USER_CAMERA_FIRST_ITEM_SETTLED_REPLAY', [System.StringComparison]::Ordinal) -lt 0) {
        Fail "R2 settled replay log category is missing."
    }
    Pass "R2 first-item settled replay preserved"

    Write-Host "QA STATIC/SOURCE: PASS - SVC 1.1.3.0 R3 SameCamera Retain"
    exit 0
}
catch {
    Write-Host ("QA STATIC/SOURCE: FAIL - " + $_.Exception.Message)
    exit 1
}
