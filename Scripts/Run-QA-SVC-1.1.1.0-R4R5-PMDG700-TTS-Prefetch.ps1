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

function Read-WindowsText([string]$Relative) {
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
    Write-Host 'R4R5 QA started...' -ForegroundColor Cyan

    $versionPath = Join-Path $WindowsProjectRoot 'Version.props'
    Require-File $versionPath
    [xml]$versionXml = Get-Content -LiteralPath $versionPath -Raw
    $version = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
    $display = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion')
    if ($null -eq $version -or $null -eq $display -or
        $version.InnerText.Trim() -ne '1.1.1.0' -or
        $display.InnerText.Trim() -ne '1.1.1.0') {
        throw 'Windows version must remain 1.1.1.0.'
    }

    $pmdgSdk = Read-WindowsText 'Pmdg737Ng3Sdk.cs'
    $pmdgMcp = Read-WindowsText 'Pmdg737McpCommandService.cs'
    $camera = Read-WindowsText 'Pmdg737ChecklistCameraAdapter.cs'
    $neural = Read-WindowsText 'NeuralVoiceClient.cs'
    $speech = Read-WindowsText 'SpeechManager.cs'
    $session = Read-WindowsText 'ChecklistSessionManager.cs'
    $main = Read-WindowsText 'MainForm.cs'

    # R4R5 PMDG family contract: title is only a candidate gate; live NG3
    # signature remains the actual authority. 737-700 and 737-800 share MCP,
    # while the certified 737-800 camera map stays isolated.
    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R5_PMDG737700_800_NG3_FAMILY',
        'IsPmdg737700CandidateTitle',
        'IsPmdg737800CandidateTitle',
        'IsPmdg737700Ng3Title',
        'IsPmdg737800Ng3Title',
        'return IsPmdg737700CandidateTitle(title) ||',
        'IsPmdg737800CandidateTitle(title);',
        'SIMVOICE_1_1_1_0_R4R2_PMDG737800_ASYNC_NG3_SIGNATURE',
        'BeginRuntimeSignatureProbe',
        'ExecuteRpnAndReadAsync'
    )) { Require-Contains $pmdgSdk $required 'R4R5 PMDG NG3 family' }
    Require-ContainsIgnoreCase $pmdgSdk '737-700' 'R4R5 PMDG 737-700 candidate'
    Require-ContainsIgnoreCase $pmdgSdk '737-800' 'R4R5 PMDG 737-800 candidate'
    Require-NotContains $pmdgSdk '.GetAwaiter().GetResult()' 'R4R5 PMDG NG3 async identity'

    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R3_PMDG737_VS_HANDSHAKE_MACH',
        'PMDG737_VS_WINDOW_READY',
        'AP_MACH_VAR_SET'
    )) { Require-Contains $pmdgMcp $required 'R4R3 PMDG MCP frozen baseline' }

    Require-Contains $camera 'IsPmdg737800Ng3Title' 'R4R5 PMDG camera-family isolation'
    Require-Contains $camera 'R4MCuratedTargetCount = 373' 'R4R5 PMDG 737-800 camera-map frozen baseline'

    # Neural TTS prefetch must reuse the exact production cache/backend contract.
    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R5_CHECKLIST_NEURAL_TTS_PREFETCH',
        'TryPrefetch(',
        'NeuralVoiceCache.BuildClientCacheKey',
        'NeuralVoiceCache.NormalizeText',
        'source = "windows-checklist-prefetch"',
        'NEURAL_TTS_PREFETCH_CACHE_HIT',
        'NEURAL_TTS_PREFETCH_START',
        'NEURAL_TTS_PREFETCH_READY',
        'NeuralVoiceCache.Store(cacheKey, bytes)',
        'NeuralVoiceCache.CompletionMarkerText'
    )) { Require-Contains $neural $required 'R4R5 Neural TTS prefetch transport/cache' }

    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R5_CHECKLIST_NEURAL_TTS_PREFETCH',
        'PrefetchNeuralVoiceAsync',
        'neuralPrefetchGate',
        'neuralPrefetchTasks',
        'NeuralVoiceCache.BuildClientCacheKey',
        'WaitForMatchingNeuralPrefetch',
        'NEURAL_TTS_PREFETCH_JOINED',
        'NeuralVoiceClient.TryPlay'
    )) { Require-Contains $speech $required 'R4R5 Neural TTS prefetch scheduler' }

    foreach ($required in @(
        'BuildFirstSpeechRequestForPrefetch',
        'BuildNextSpeechRequestForPrefetch',
        'BuildCurrentSpeechRequestLocked(true)',
        'BuildCurrentSpeechRequestLocked(false)'
    )) { Require-Contains $session $required 'R4R5 checklist exact-prompt prefetch' }

    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R5_CHECKLIST_NEURAL_TTS_PREFETCH',
        'BeginChecklistNeuralSelectionPrefetch',
        'BeginChecklistNeuralSelectionPrefetchForTranslatedDocument',
        'CHECKLIST_NEURAL_TTS_FIRST_ITEM_READY',
        'EnsureChecklistNeuralSessionPrefetch',
        'BuildNextSpeechRequestForPrefetch',
        'CancelChecklistNeuralSessionPrefetch',
        'Task.Delay(350, cancellation.Token)'
    )) { Require-Contains $main $required 'R4R5 checklist first/next Neural TTS prefetch' }

    # Preserve R4R4 performance + iFly beta baseline.
    $catalog = Read-WindowsText 'MsfsSdkCatalogService.cs'
    $mapper = Read-WindowsText 'CommandMapperForm.cs'
    $launcher = Read-WindowsText 'AiCommandBuilderLauncher.cs'
    $ai = Read-WindowsText 'LocalAiCommandInterpreter.cs'
    $iflySdk = Read-WindowsText 'Ifly737MaxSdk.cs'
    $iflyMcp = Read-WindowsText 'Ifly737MaxMcpCommandService.cs'
    foreach ($required in @(
        'SIMVOICE_1_1_1_0_R4R4_FAST_INPUT_EVENT_CACHE',
        'LoadInputEventTargetsFastAsync'
    )) { Require-Contains $catalog $required 'R4R4 performance frozen baseline' }
    Require-Contains $mapper 'SIMVOICE_1_1_1_0_R4R4_COMMAND_UI_FAST_LOAD' 'R4R4 command UI frozen baseline'
    Require-Contains $launcher 'SIMVOICE_1_1_1_0_R4R4_AI_BUILDER_FAST_LOAD' 'R4R4 AI Builder frozen baseline'
    Require-Contains $ai 'SIMVOICE_1_1_1_0_R4R4_SINGLE_LLM_PLANNER_CALL' 'R4R4 planner frozen baseline'
    Require-Contains $iflySdk 'SIMVOICE_1_1_1_0_R4R4_IFLY737MAX_SDK_V15' 'R4R4 iFly SDK frozen baseline'
    Require-Contains $iflyMcp 'SIMVOICE_1_1_1_0_R4R4_IFLY737MAX_MCP_CORE' 'R4R4 iFly MCP frozen baseline'

    $efbSourcePath = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
    $efbBuildPath = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'
    Require-File $efbSourcePath
    Require-File $efbBuildPath
    $efbSource = [IO.File]::ReadAllText($efbSourcePath)
    $efbBuild = [IO.File]::ReadAllText($efbBuildPath)

    Require-Contains $efbSource "const EFB_VERSION = '0.1.135';" 'R4R5 EFB version'
    Require-Contains $efbSource 'SIMVOICE_1_1_1_0_R4R2_EFB_EDGE_AND_SMALL_DOCK_FIT' 'R4R2 EFB layout frozen baseline'
    Require-Contains $efbBuild '$ExpectedEfbVersion = "0.1.135"' 'R4R5 EFB build version'
    Require-Contains $efbBuild 'R4R4 fast command/AI load + single-call planner + iFly SDK/checklist core semantics: PASS' 'R4R4 EFB build frozen gate'
    Require-Contains $efbBuild 'R4R5 PMDG 737-700 NG3 + checklist Neural TTS prefetch semantics: PASS' 'R4R5 EFB build gate'
    Require-NotContains $efbBuild 'Join-Path $SourceRoot' 'R4R5 EFB build contract'

    Write-Host 'R4R5 SOURCE QA: PASS' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ('R4R5 SOURCE QA: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
