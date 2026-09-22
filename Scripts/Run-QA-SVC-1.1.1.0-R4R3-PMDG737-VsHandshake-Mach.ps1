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
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) {
        throw "$Label missing semantic: $Needle"
    }
}

function Require-ContainsIgnoreCase([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "$Label missing semantic: $Needle"
    }
}

function Require-NotContains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -ge 0) {
        throw "$Label contains rejected pattern: $Needle"
    }
}

$versionPath = Join-Path $WindowsProjectRoot 'Version.props'
$sdkPath = Join-Path $WindowsProjectRoot 'Pmdg737Ng3Sdk.cs'
$mcpPath = Join-Path $WindowsProjectRoot 'Pmdg737McpCommandService.cs'
$parserPath = Join-Path $WindowsProjectRoot 'ParameterizedVoiceCommand.cs'
$voskPath = Join-Path $WindowsProjectRoot 'VoskRecognizer.cs'
$mapperPath = Join-Path $WindowsProjectRoot 'CommandMapperForm.cs'
$testsPath = Join-Path $WindowsProjectRoot 'ParameterizedCommandRegressionTests.cs'
$requiredEventsPath = Join-Path $WindowsProjectRoot 'ai_internal_catalog_required_events.json'
$enProfilePath = Join-Path $WindowsProjectRoot 'Languages\en-US\parameterized_commands.json'
$esProfilePath = Join-Path $WindowsProjectRoot 'Languages\es-ES\parameterized_commands.json'
$cameraPath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraAdapter.cs'
$storePath = Join-Path $WindowsProjectRoot 'Pmdg737ChecklistCameraCalibrationStore.cs'
$controllerPath = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$efbUiPath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$efbStylePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css'
$efbBuildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

@(
    $versionPath,$sdkPath,$mcpPath,$parserPath,$voskPath,$mapperPath,$testsPath,
    $requiredEventsPath,$enProfilePath,$esProfilePath,$cameraPath,$storePath,$controllerPath,
    $efbUiPath,$efbStylePath,$efbBuildPath
) | ForEach-Object { Require-File $_ }

# PowerShell source changed by R4R3 must parse under Windows PowerShell 5.1.
$t=$null; $e=$null
[System.Management.Automation.Language.Parser]::ParseFile($efbBuildPath,[ref]$t,[ref]$e) | Out-Null
if ($e -and $e.Count -gt 0) {
    throw ('R4R3 EFB build PowerShell parser failed: ' + (($e | ForEach-Object {$_.Message}) -join ' | '))
}

[xml]$version = Get-Content -LiteralPath $versionPath -Raw
$windowsVersion = $version.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
$displayVersion = $version.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion')
if ($null -eq $windowsVersion -or $null -eq $displayVersion -or
    $windowsVersion.InnerText.Trim() -ne '1.1.1.0' -or
    $displayVersion.InnerText.Trim() -ne '1.1.1.0') {
    throw 'Windows Version.props must remain exactly 1.1.1.0.'
}

$sdk = [IO.File]::ReadAllText($sdkPath)
$mcp = [IO.File]::ReadAllText($mcpPath)
$parser = [IO.File]::ReadAllText($parserPath)
$vosk = [IO.File]::ReadAllText($voskPath)
$mapper = [IO.File]::ReadAllText($mapperPath)
$tests = [IO.File]::ReadAllText($testsPath)
$camera = [IO.File]::ReadAllText($cameraPath)
$store = [IO.File]::ReadAllText($storePath)
$controller = [IO.File]::ReadAllText($controllerPath)
$efbUi = [IO.File]::ReadAllText($efbUiPath)
$efbStyle = [IO.File]::ReadAllText($efbStylePath)
$efbBuild = [IO.File]::ReadAllText($efbBuildPath)

# Baseline identity from R4R2 remains mandatory. PMDG is never accepted by title alone.
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4R1_PMDG737800_NG3_RUNTIME_SIGNATURE',
    'SIMVOICE_1_1_1_0_R4R2_PMDG737800_ASYNC_NG3_SIGNATURE',
    'BeginRuntimeSignatureProbe',
    'ProbeLiveNg3RuntimeSignatureAsync',
    'runtimeSignatureProbeInFlight',
    'PositiveRuntimeSignatureRefreshLeadSeconds = 5',
    'await SimVoiceWasmBridgeClient.ExecuteRpnAndReadAsync',
    'IndexOf("737-800", StringComparison.OrdinalIgnoreCase)'
)) { Require-Contains $sdk $required 'R4R2 PMDG live identity' }
Require-NotContains $sdk '.GetAwaiter().GetResult()' 'R4R2 PMDG live identity'
foreach ($forbidden in @('saysKnown800Variant','saysKnownWinglet')) {
    if ($sdk.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "R4R2 rejected variant whitelist semantic reappeared: $forbidden"
    }
}

# R4R3 V/S: wait for the PMDG window to become live before #84138.
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4R3_PMDG737_VS_HANDSHAKE_MACH',
    'VerticalSpeedWindowReadyTimeoutMilliseconds = 2200',
    'VerticalSpeedWindowPollMilliseconds = 90',
    'EnsureVerticalSpeedModeActiveAsync',
    'PMDG737_VS_MODE_PREACTIVATION',
    'PMDG737_VS_WINDOW_READY',
    'PMDG737_VS_WINDOW_READY_TIMEOUT',
    'PMDG737_VS_PREACTIVATION_READ_UNAVAILABLE',
    'PMDG737_MCP_DIRECT_SET_RETRY',
    'PMDG737_MCP_LVAR_READBACK_RETRY',
    'EvtMcpVerticalSpeedSet',
    'value + 10000'
)) { Require-Contains $mcp $required 'R4R3 PMDG V/S handshake' }
Require-NotContains $mcp 'Task.Delay(220' 'R4R3 PMDG V/S handshake'

# R4R3 MACH: dedicated PMDG event, C/O mode transition, readback and verification.
foreach ($required in @(
    'EvtMcpMachSet = ThirdPartyEventIdMin + 14503',
    'EvtMcpCoSwitch = 70015'
)) { Require-Contains $sdk $required 'R4R3 PMDG MACH SDK constants' }
foreach ($required in @(
    'AP_MACH_VAR_SET',
    'EVT_MCP_MACH_SET',
    'Pmdg737Ng3Sdk.EvtMcpMachSet',
    'Pmdg737Ng3Sdk.EvtMcpCoSwitch',
    'EnsureSpeedWindowModeAsync',
    'PMDG737_SPEED_MODE_CHANGEOVER',
    'PMDG737_SPEED_MODE_READY',
    'VerifyMach',
    'Minimum = 60',
    'Maximum = 82'
)) { Require-Contains $mcp $required 'R4R3 PMDG MACH direct-set path' }

foreach ($required in @(
    'if (action == "AP_MACH_VAR_SET")',
    'TryParseMach',
    'Selected Mach must be between 0.60 and 0.82.',
    'SimConnectValue = hundredths',
    'NumericValue = mach'
)) { Require-Contains $parser $required 'R4R3 Mach parameter parser' }

foreach ($required in @(
    '"AP_MACH_VAR_SET"',
    'EnsureLocalCommandForAction("set mach", "AP_MACH_VAR_SET")',
    'EnsureLocalCommandForAction("establecer mach", "AP_MACH_VAR_SET")',
    'Selected Mach set and verified at',
    'Mach seleccionado establecido y verificado en'
)) { Require-Contains $vosk $required 'R4R3 Mach voice routing' }

foreach ($required in @(
    'AP_MACH_VAR_SET',
    '0.60–0.82',
    'set Mach point seven eight',
    'establecer Mach cero punto setenta y ocho'
)) { Require-ContainsIgnoreCase $mapper $required 'R4R3 Mach command help' }

foreach ($required in @(
    'set mach point seven eight',
    'set mach 0.78',
    'establecer mach cero punto setenta y ocho',
    'AssertMach',
    'point five nine',
    'point eight three'
)) { Require-ContainsIgnoreCase $tests $required 'R4R3 Mach regression tests' }

# JSON profiles/catalog must be valid and include Mach in both languages.
$enProfile = Get-Content -LiteralPath $enProfilePath -Raw | ConvertFrom-Json
$esProfile = Get-Content -LiteralPath $esProfilePath -Raw | ConvertFrom-Json
$requiredEvents = Get-Content -LiteralPath $requiredEventsPath -Raw | ConvertFrom-Json
$enMach = @($enProfile.eventAliases.AP_MACH_VAR_SET)
$esMach = @($esProfile.eventAliases.AP_MACH_VAR_SET)
if ($enMach.Count -lt 2 -or -not ($enMach -contains 'set mach') -or -not ($enMach -contains 'select mach')) {
    throw 'R4R3 English parameterized profile is missing deterministic Mach aliases.'
}
if ($esMach.Count -lt 2 -or -not ($esMach -contains 'establecer mach') -or -not ($esMach -contains 'seleccionar mach')) {
    throw 'R4R3 Spanish parameterized profile is missing deterministic Mach aliases.'
}
if ($null -eq $requiredEvents.PSObject.Properties['AP_MACH_VAR_SET']) {
    throw 'R4R3 AI/internal required-event catalog is missing AP_MACH_VAR_SET.'
}

# Frozen PMDG checklist/camera baseline: R4R3 must not alter the established 373-target map.
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4M_PMDG737_FACTORY_CURATED_CAMERA_MAP',
    'R4MCuratedTargetCount = 373',
    'Pmdg737ChecklistCameraCalibrationStore.TryGet',
    'pmdg-r4o-family-factory-curated-exact-native-target-map'
)) { Require-Contains $camera $required 'R4R3 frozen camera baseline' }
foreach ($required in @(
    'private const string FamilyKey = "PMDG737-800";',
    'Version = 2'
)) { Require-Contains $store $required 'R4R3 PMDG family calibration store' }
Require-Contains $controller '["pmdg737Ng3Confirmed"] = Pmdg737ChecklistCameraAdapter.IsCurrentAircraftPmdg737()' 'R4R3 controller identity publication'

# R4R2 EFB layout remains frozen; R4R3 only advances package/UI version to 0.1.133.
foreach ($required in @(
    "const EFB_VERSION = '0.1.133';",
    'SIMVOICE_1_1_1_0_R4R2_EFB_EDGE_AND_SMALL_DOCK_FIT',
    'actionsOuterHeight',
    'preferredReaderMin',
    'periodicGeometryPoll=false',
    'MARCAR',
    'CÁMARA QA · Shift+'
)) { Require-ContainsIgnoreCase $efbUi $required 'R4R3 EFB inherited R4R2 layout' }
foreach ($required in @(
    'SIMVOICE_1_1_1_0_R4R2_EFB_EDGE_AND_SMALL_DOCK_FIT',
    'padding-left: 0 !important;',
    'padding-right: 0 !important;',
    'column-gap: 2px',
    'row-gap: 2px'
)) { Require-Contains $efbStyle $required 'R4R3 EFB inherited R4R2 CSS' }
Require-NotContains $efbStyle '\n' 'R4R3 EFB CSS delivery'
foreach ($required in @(
    '$ExpectedEfbVersion = "0.1.133"',
    'R4R2 async PMDG signature + exact tab edges + SMALL action-dock containment source semantics: PASS',
    'R4R3 PMDG V/S ready-handshake + MACH voice/direct-set source semantics: PASS',
    'SIMVOICE_1_1_1_0_R4Q2_BUILD_SOURCE_ROOT_NULL_FIX'
)) { Require-Contains $efbBuild $required 'R4R3 EFB build contract' }
Require-NotContains $efbBuild 'Join-Path $SourceRoot' 'R4R3 EFB build contract'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R4R3 PMDG V/S HANDSHAKE + MACH QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'Windows remains 1.1.1.0; EFB source/build target is 0.1.133.'
Write-Host 'V/S now waits for ngx_VSwindow to leave the inactive -20000 sentinel before #84138 and has one idempotent setter retry without re-pressing V/S.'
Write-Host 'MACH accepts 0.60-0.82, uses PMDG #84135, changes IAS/MACH mode through C/O only when required, and verifies ngx_SPDwindow.'
Write-Host 'R4R2 async PMDG identity, checklist/camera family behavior, MARK/camera QA controls and the frozen 373-target map remain intact.'
exit 0
