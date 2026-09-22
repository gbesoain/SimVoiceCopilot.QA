#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp',
    [string]$EfbProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file missing: $Path" }
}
function Require-Contains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) { throw "$Label missing semantic: $Needle" }
}
function Require-ContainsIgnoreCase([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "$Label missing semantic: $Needle" }
}
function Require-NotContains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -ge 0) { throw "$Label contains retired pattern: $Needle" }
}

$versionPath = Join-Path $WindowsProjectRoot 'Version.props'
$cameraPath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs'
$sdkPath = Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs'
$storePath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraCalibrationStore.cs'
$efbPath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$stylePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css'
$buildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'
$controllerPath = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
@($versionPath,$cameraPath,$sdkPath,$storePath,$controllerPath,$efbPath,$stylePath,$buildPath) | ForEach-Object { Require-File $_ }

$t=$null;$e=$null
[System.Management.Automation.Language.Parser]::ParseFile($buildPath,[ref]$t,[ref]$e) | Out-Null
if ($e -and $e.Count -gt 0) { throw ('R4P1 EFB PowerShell parser gate failed: ' + (($e | ForEach-Object {$_.Message}) -join ' | ')) }

[xml]$v = Get-Content -LiteralPath $versionPath -Raw
if ($v.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion').InnerText.Trim() -ne '1.1.1.0' -or
    $v.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion').InnerText.Trim() -ne '1.1.1.0') {
    throw 'Windows Version.props must remain exactly 1.1.1.0.'
}

$camera=[IO.File]::ReadAllText($cameraPath)
$sdk=[IO.File]::ReadAllText($sdkPath)
$store=[IO.File]::ReadAllText($storePath)
$efb=[IO.File]::ReadAllText($efbPath)
$style=[IO.File]::ReadAllText($stylePath)
$build=[IO.File]::ReadAllText($buildPath)

# Camera data is intentionally frozen: current support package is diagnosis only.
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4M_PMDG737_FACTORY_CURATED_CAMERA_MAP',
    'R4MCuratedTargetCount = 373',
    'Pmdg737ChecklistCameraCalibrationStore.TryGet',
    'pmdg-r4o-family-learned-exact-native-target-map',
    'pmdg-r4o-family-factory-pass3-exact-native-target-map',
    'pmdg-r4o-family-factory-curated-exact-native-target-map'
)) { Require-Contains $camera $required 'R4Q frozen/family camera resolver' }

# R4Q family identity must not whitelist individual PMDG 737-800 variants.
foreach ($required in @('IsPmdg737Ng3Title','IsPmdg737Ng3CandidateTitle','IndexOf("737-800"','ProbeLiveNg3RuntimeSignature')) {
    Require-ContainsIgnoreCase $sdk $required 'R4Q PMDG 737-800 variant-agnostic family identity'
}
foreach ($forbidden in @('saysKnown800Variant','saysKnownWinglet')) {
    if ($sdk.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "R4Q rejected stale variant whitelist semantic: $forbidden" }
}
foreach ($required in @(
    'private const string FamilyKey = "PMDG737-800";',
    'FamilyKey + "|" + target',
    'entry.UpdatedUtc >= existing.UpdatedUtc',
    'Version = 2'
)) { Require-Contains $store $required 'R4Q learned camera family store' }

# No-highlight PMDG items still own the stored camera; MARK/calibrator remain present.
foreach ($required in @(
    "const EFB_VERSION = '0.1.131';",
    'SIMVOICE_1_1_1_0_R4O_PMDG_CAMERA_WITHOUT_NATIVE_HIGHLIGHT',
    'pmdgCameraTarget',
    'pmdgCameraFocusable',
    'CÁMARA QA · Shift+',
    'checklist.camera.pmdg.calibrate',
    'MARCAR',
    'checklistMarkModeEnabled'
)) { Require-Contains $efb $required 'R4P PMDG camera/curation UI' }

# R4P: consecutive PMDG items never emit STOP_HELP before the next camera.
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4P_PMDG_CONSECUTIVE_ITEM_NO_STOP_HANDOFF',
    'abandonPmdgNativeChecklistHelperWithoutStop',
    'abandonPmdgNativeChecklistMarkHelperWithoutStop',
    "this.abandonPmdgNativeChecklistHelperWithoutStop('focus-chain-item-transition')",
    "this.abandonPmdgNativeChecklistHelperWithoutStop('pmdg-mark-enabled-no-camera-restore')",
    "this.setChecklistMarkMode(false, checklist, true)"
)) { Require-Contains $efb $required 'R4P PMDG no-STOP handoff' }

# R4P: repeated transport/status heartbeat cannot trigger a visual render loop.
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4O_ACTIVE_CHECKLIST_HEARTBEAT_RENDER_SUPPRESSION',
    'SIMVOICE_1_1_1_0_R4P_TRANSPORT_STATUS_RENDER_SUPPRESSION',
    'previousActiveRenderSignature === nextActiveRenderSignature',
    'this.transportStatus === status && this.transportDetail === nextDetail'
)) { Require-Contains $efb $required 'R4P heartbeat/status render stability' }

# Width is CSS-owned and vertical JS measurements must not become horizontal flex basis.
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4O_ACTIVE_CHECKLIST_FLEX_AXIS_WIDTH_FIX',
    "card.style.setProperty('flex', '1 1 auto', 'important');",
    "card.style.removeProperty('flex-basis');"
)) { Require-Contains $efb $required 'R4P flex-axis fix' }
Require-NotContains $efb "const contentWidth = Math.max(180, Math.floor(contentRect.width));" 'R4P active checklist fitter'

foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4O_ACTIVE_CHECKLIST_FLEX_AXIS_WIDTH_FIX',
    '.sv-shell > .sv-content.sv-content-checklist-active-safe',
    'flex-direction: column !important;',
    'margin-left: 12px !important;',
    'margin-right: 12px !important;',
    'margin-left: 7px !important;',
    'margin-right: 7px !important;',
    'grid-template-columns: repeat(3, minmax(0, 1fr)) !important;',
    'SIMVOICE_1_1_1_0_R4P_ACTIVE_CHECKLIST_EDGE_CONTAINMENT'
)) { Require-Contains $style $required 'R4P full-width/action containment CSS' }

Require-Contains $build '$ExpectedEfbVersion = "0.1.131"' 'R4P EFB build version'
Require-Contains $build 'R4P1 full-width + heartbeat/status stability + PMDG family/no-stop camera source semantics: PASS' 'R4Q inherited R4P1 build semantic gate'
Require-Contains $build 'R4Q PMDG 737-800 variant-agnostic family identity source semantics: PASS' 'R4Q build family gate'
Require-NotContains $build '"737-800 pax bw sc"' 'R4P1 stale EFB title-literal gate'
Require-NotContains $build '"737-800 pax ssw sc"' 'R4P1 stale EFB title-literal gate'
Require-Contains $build 'SIMVOICE_1_1_1_0_R4Q2_BUILD_SOURCE_ROOT_NULL_FIX' 'R4Q2 build-script null-path fix marker'
Require-Contains $build '$r4qUiSource = $r4gUiSource' 'R4Q2 build-script source reuse'
Require-Contains $build '$r4qStyleSource = $r4gStyleSource' 'R4Q2 build-script source reuse'
Require-NotContains $build 'Join-Path $SourceRoot' 'R4Q2 undefined SourceRoot dependency'

# R4Q direct semantics.
$sdk = Get-Content -LiteralPath (Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs') -Raw
$camera = Get-Content -LiteralPath (Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs') -Raw
$controller = Get-Content -LiteralPath (Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs') -Raw
$ui = Get-Content -LiteralPath (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts') -Raw
$css = Get-Content -LiteralPath (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css') -Raw
foreach ($test in @(
  @($sdk, 'value.IndexOf("737-800"'),
  @($camera, 'PMDG737_CAMERA_SAME_VIEW_RETAINED'),
  @($camera, 'TryPreviewCalibrationCamera'),
  @($controller, 'TryPreviewCalibrationCamera'),
  @($ui, 'periodicGeometryPoll=false'),
  @($css, 'SIMVOICE_1_1_1_0_R4Q_EFB_FULL_WIDTH_NO_PERIODIC_REFIT'),
  @($css, 'column-gap: 2px'),
  @($css, 'row-gap: 2px')
)) {
  if ($test[0].IndexOf($test[1],[StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "R4Q semantic missing: $($test[1])" }
}
# R4Q2 delivery gate: CSS must not contain literal escaped newlines from payload assembly.
if ($style.IndexOf('\n',[System.StringComparison]::Ordinal) -ge 0) { throw 'R4Q2 CSS delivery corruption: literal \n escape found in style.css.' }
Write-Host 'R4Q2 CSS delivery gate: PASS' -ForegroundColor Green
Write-Host 'R4Q direct semantic QA: PASS' -ForegroundColor Green

# R4R1: title is only a 737-800 candidate filter. Windows must confirm the
# live PMDG NG3 runtime using ngx LVars before EFB MARK/AUTO/FOCUS can use PMDG paths.
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4R1_PMDG737800_NG3_RUNTIME_SIGNATURE',
    'pmdg737Ng3Confirmed',
    'EfbChecklistState & { pmdg737Ng3Confirmed?: boolean }',
    'SIMVOICE_1_1_1_0_R4R_PMDG_RETURN_INITIAL_CAMERA',
    'checklist.camera.pmdg.restore_initial',
    'settleMs: 350',
    'settleMs: 450'
)) { Require-ContainsIgnoreCase $efb $required 'R4R1 EFB signature/restore contract' }
foreach ($forbidden in @(
    "title.startsWith('737-800')",
    "title.includes('pax')",
    "title.includes('bbj2')",
    "title.includes('bdsf')",
    "title.includes('bcf')"
)) {
    if ($efb.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "R4R1 rejected EFB title-only/variant-token PMDG identity: $forbidden" }
}

foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4R1_PMDG737800_NG3_RUNTIME_SIGNATURE',
    'IsPmdg737Ng3CandidateTitle',
    'ProbeLiveNg3RuntimeSignature',
    'SimVoiceWasmBridgeClient.IsRpnRoundTripAvailable',
    'ExecuteRpnAndReadAsync',
    'McpVerticalSpeedWindowLvar',
    'McpAltitudeWindowLvar',
    'McpSpeedWindowLvar',
    'McpHeadingWindowLvar'
)) { Require-Contains $sdk $required 'R4R1 PMDG NG3 runtime signature' }
Require-Contains $sdk 'IndexOf("737-800", StringComparison.OrdinalIgnoreCase)' 'R4R1 737-800 candidate filter'
Require-Contains $controller '["pmdg737Ng3Confirmed"] = Pmdg737ChecklistCameraAdapter.IsCurrentAircraftPmdg737()' 'R4R1 controller signature publication'

foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4R_PMDG_RETURN_INITIAL_CAMERA',
    'ScheduleInitialUserCameraRestore',
    'lastHotKey == Pmdg737Ng3Sdk.CameraHotKeyMcp ? 1 : 2',
    'pmdg-checklist-camera-return-initial-1',
    'pmdg-checklist-camera-return-initial-2',
    'System.Threading.Interlocked.Increment(ref initialUserCameraRestoreSerial)'
)) { Require-Contains $camera $required 'R4R1 PMDG initial-camera restore' }
Require-Contains $controller 'case "checklist.camera.pmdg.restore_initial":' 'R4R1 controller restore action'
Require-Contains $build 'R4R1 PMDG 737-800 candidate + live NG3 signature + initial-camera restore source semantics: PASS' 'R4R1 build semantic gate'
Write-Host 'R4R1 direct NG3 runtime-signature + initial-camera restore semantic QA: PASS' -ForegroundColor Green

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R4R1 NG3 SIGNATURE + RESTORE INITIAL CAMERA QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'EFB 0.1.131: active reader width follows tab gutters in portrait/landscape; action buttons remain contained.'
Write-Host 'Repeated state/status heartbeats do not rebuild an unchanged active checklist DOM.'
Write-Host 'Every PMDG 737-800 variant shares one learned/factory camera map only after Windows confirms the live NG3 runtime signature; title alone is never sufficient.'
Write-Host 'Consecutive PMDG AUTO/MARK item transitions invalidate old ownership without CHECKLIST_STOP_HELP, preventing late default-camera bounce.'
Write-Host 'PMDG items with no native highlight may still use their stored Shift+n camera.'
Write-Host 'MARK and camera selectors remain visible; R4M 373-target factory values are unchanged.'
Write-Host 'Explicit AUTO OFF and checklist completion restore the initial user camera: last Shift+1 => one Shift+1; any other last SVC camera => two Shift+1.'
exit 0
