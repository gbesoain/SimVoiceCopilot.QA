#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp',
    [string]$EfbProjectRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file missing: $Path"
    }
}

function Read-Text([string]$Relative) {
    $path = Join-Path $WindowsProjectRoot $Relative
    Require-File $path
    return [IO.File]::ReadAllText($path)
}

function Require-Contains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[StringComparison]::Ordinal) -lt 0) {
        throw "$Label missing semantic: $Needle"
    }
}

function Require-ContainsIgnoreCase([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "$Label missing semantic: $Needle"
    }
}

function Require-NotContains([string]$Text,[string]$Needle,[string]$Label) {
    if ($Text.IndexOf($Needle,[StringComparison]::Ordinal) -ge 0) {
        throw "$Label contains rejected pattern: $Needle"
    }
}

try {
    Write-Host 'R4R4 QA started...' -ForegroundColor Cyan

    $versionPath = Join-Path $WindowsProjectRoot 'Version.props'
    Require-File $versionPath
    [xml]$versionXml = Get-Content -LiteralPath $versionPath -Raw
    $version = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
    if ($null -eq $version -or $version.InnerText.Trim() -ne '1.1.1.0') {
        throw 'Windows version must remain 1.1.1.0.'
    }

    $catalog = Read-Text 'MsfsSdkCatalogService.cs'
    $mapper = Read-Text 'CommandMapperForm.cs'
    $launcher = Read-Text 'AiCommandBuilderLauncher.cs'
    $ai = Read-Text 'LocalAiCommandInterpreter.cs'
    $iflySdk = Read-Text 'Ifly737MaxSdk.cs'
    $iflyMcp = Read-Text 'Ifly737MaxMcpCommandService.cs'
    $iflyAlt = Read-Text 'Ifly737MaxAltitudeAdapter.cs'
    $altService = Read-Text 'AutopilotAltitudeService.cs'
    $vosk = Read-Text 'VoskRecognizer.cs'
    $checklistPolicy = Read-Text 'ChecklistAircraftCapabilityPolicy.cs'
    $pmdg = Read-Text 'Pmdg737McpCommandService.cs'

    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R4_FAST_INPUT_EVENT_CACHE',
        'LoadInputEventTargetsFastAsync',
        'INPUT_EVENT_CATALOG_FAST_READY',
        'INPUT_EVENT_CATALOG_BACKGROUND_READY',
        'InputEventRefreshLifetime = TimeSpan.FromMinutes(2)'
    )) { Require-Contains $catalog $required 'R4R4 fast Input Event catalogue' }

    Require-Contains $mapper 'SIMVOICE_1_1_1_0_R4R4_COMMAND_UI_FAST_LOAD' 'R4R4 Voice Commands performance'
    Require-Contains $mapper 'LoadInputEventTargetsFastAsync' 'R4R4 Voice Commands performance'
    Require-Contains $mapper 'skipEventCatalogReloadOnce = true;' 'R4R4 Builder close performance'
    Require-NotContains $mapper 'MsfsSdkCatalogService.LoadInputEventTargetsAsync(' 'R4R4 Voice Commands performance'

    Require-Contains $launcher 'SIMVOICE_1_1_1_0_R4R4_AI_BUILDER_FAST_LOAD' 'R4R4 Builder performance'
    Require-Contains $launcher 'LoadInputEventTargetsFastAsync' 'R4R4 Builder performance'
    Require-NotContains $launcher 'MsfsSdkCatalogService.LoadInputEventTargetsAsync(' 'R4R4 Builder performance'

    Require-Contains $ai 'SIMVOICE_1_1_1_0_R4R4_SINGLE_LLM_PLANNER_CALL' 'R4R4 AI planner'
    Require-Contains $ai 'semanticSearchHint = proposalMode ? spokenText : null;' 'R4R4 AI planner'
    Require-NotContains $ai 'semanticSearchHint = await BuildSemanticSearchHintAsync(spokenText' 'R4R4 AI planner'

    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R4_IFLY737MAX_SDK_V15',
        'iFly737MAX_SDK_FileMappingObject',
        'iFly737MAX_SDK_Mutex',
        'iFly737MAX_MSG_GAU',
        'iFly Plugin - MSFS2024',
        'MutexModifyState = 0x0001',
        'OpenMutex(Synchronize | MutexModifyState',
        'CmdCourseLeftSet = 209',
        'CmdCourseRightSet = 212',
        'CmdIasMachSet = 215',
        'CmdHeadingSet = 223',
        'CmdAltitudeSet = 226',
        'CmdVerticalSpeedSet = 229',
        'CmdN1 = 232',
        'CmdSpeed = 233',
        'CmdVnav = 235',
        'CmdLevelChange = 236',
        'CmdApproach = 237',
        'CmdAltitudeHold = 238',
        'CmdVerticalSpeed = 239',
        'CmdLnav = 241',
        'CmdVorLoc = 242',
        'CmdHeadingSelect = 243',
        'OffsetAltitudeTenThousands = 275',
        'OffsetVsSymbol = 280',
        'OffsetCourseRightHundreds = 285',
        'cbData = wireSize'
    )) { Require-Contains $iflySdk $required 'R4R4 official iFly SDK transport' }

    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R4_IFLY737MAX_MCP_CORE',
        'IFLY737MAX_MCP_DIRECT_SET',
        'IFLY737MAX_MCP_READBACK',
        'IFLY737MAX_VS_WINDOW_READY',
        '"AP_ALT_VAR_SET_ENGLISH"',
        '"HEADING_BUG_SET"',
        '"AP_SPD_VAR_SET"',
        '"AP_MACH_VAR_SET"',
        '"AP_VS_VAR_SET_ENGLISH"',
        '"VOR1_SET"',
        '"VOR2_SET"',
        'Ifly737MaxSdk.CmdIasMachSet',
        'Ifly737MaxSdk.CmdVerticalSpeedSet',
        'Ifly737MaxSdk.CmdAltitudeSet'
    )) { Require-Contains $iflyMcp $required 'R4R4 iFly MCP core' }

    Require-Contains $iflyAlt 'Ifly737MaxMcpCommandService.SetAsync' 'R4R4 iFly altitude adapter'
    Require-Contains $altService 'new Ifly737MaxAltitudeAdapter()' 'R4R4 altitude adapter ordering'
    $iflyIndex = $altService.IndexOf('new Ifly737MaxAltitudeAdapter()', [StringComparison]::Ordinal)
    $genericMaxIndex = $altService.IndexOf('new B737MaxAltitudeAdapter()', [StringComparison]::Ordinal)
    if ($iflyIndex -lt 0 -or $genericMaxIndex -lt 0 -or $iflyIndex -gt $genericMaxIndex) {
        throw 'iFly altitude adapter must be ordered before the generic B737 MAX adapter.'
    }

    Require-Contains $vosk 'ExecuteIfly737MaxMcpCommandAsync' 'R4R4 iFly voice routing'
    Require-Contains $vosk 'ExecuteIfly737MaxMcpButtonCommandAsync' 'R4R4 iFly button routing'
    Require-Contains $vosk 'Ifly737MaxMcpCommandService.IsCandidateAircraft' 'R4R4 iFly voice routing'

    foreach ($required in @(
        'Ifly737MaxFamilyId = "ifly-737-max"',
        'BuildIfly737MaxProfile',
        'known-no-native-external-checklist',
        'NativeDiscoveryAllowed = false',
        'QuietNativeTransport = true',
        'BuiltInFallbackAllowed = false',
        'ifly-aircraft-737max'
    )) { Require-Contains $checklistPolicy $required 'R4R4 iFly checklist quiet path' }

    # PMDG R4R3 is frozen and must remain present.
    Require-Contains $pmdg 'SIMVOICE_1_1_1_0_R4R3_PMDG737_VS_HANDSHAKE_MACH' 'R4R3 PMDG frozen baseline'
    Require-Contains $pmdg 'PMDG737_VS_WINDOW_READY' 'R4R3 PMDG frozen baseline'
    Require-Contains $pmdg 'AP_MACH_VAR_SET' 'R4R3 PMDG frozen baseline'

    $efbSourcePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
    $efbBuildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'
    Require-File $efbSourcePath
    Require-File $efbBuildPath
    $efbSource = [IO.File]::ReadAllText($efbSourcePath)
    $efbBuild = [IO.File]::ReadAllText($efbBuildPath)
    Require-Contains $efbSource "const EFB_VERSION = '0.1.134';" 'R4R4 EFB version'
    Require-Contains $efbSource 'SIMVOICE_1_1_1_0_R4R2_EFB_EDGE_AND_SMALL_DOCK_FIT' 'R4R2 EFB layout frozen baseline'
    Require-Contains $efbBuild '$ExpectedEfbVersion = "0.1.134"' 'R4R4 EFB build version'
    Require-Contains $efbBuild 'R4R4 fast command/AI load + single-call planner + iFly SDK/checklist core semantics: PASS' 'R4R4 EFB build gate'

    Write-Host 'R4R4 SOURCE QA: PASS' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ('R4R4 SOURCE QA: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
