#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp",
    [string]$EfbProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS",
    [switch]$SourceOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedVersion = '1.1.1.0'
$ExpectedEfbVersion = '0.1.115'
$R2LMarker = 'SIMVOICE_1_1_1_0_R2L_MARK_RUNTIME_SIDECAR_OBSERVER'

function Assert-File {
    param([string]$Path,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Missing {0}: {1}" -f $Label,$Path)
    }
}

function Assert-Contains {
    param([string]$Path,[string]$Needle,[string]$Label)
    Assert-File $Path $Label
    $text=[System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle,[System.StringComparison]::Ordinal)-lt 0) {
        throw ("{0} missing: {1}" -f $Label,$Needle)
    }
}

function Assert-NotContains {
    param([string]$Path,[string]$Needle,[string]$Label)
    Assert-File $Path $Label
    $text=[System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle,[System.StringComparison]::Ordinal)-ge 0) {
        throw ("{0} unexpectedly present: {1}" -f $Label,$Needle)
    }
}

function Assert-Sha256 {
    param([string]$Path,[string]$Expected,[string]$Label)
    Assert-File $Path $Label
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $Expected.ToUpperInvariant()) {
        throw ("{0} SHA256 mismatch. Expected {1}; actual {2}; path {3}" -f $Label,$Expected,$actual,$Path)
    }
}

function Get-ManifestPackageVersion {
    param([string]$PackageRoot)
    $manifestPath=Join-Path $PackageRoot 'manifest.json'
    Assert-File $manifestPath 'package manifest'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach($name in @('package_version','packageVersion','version','Version')) {
        $prop=$manifest.PSObject.Properties[$name]
        if($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            return ([string]$prop.Value).Trim()
        }
    }
    return ''
}

function Assert-Package {
    param([string]$PackageRoot,[string]$Label)
    if(-not (Test-Path -LiteralPath $PackageRoot -PathType Container)) {
        throw ("Missing {0}: {1}" -f $Label,$PackageRoot)
    }
    $version=Get-ManifestPackageVersion $PackageRoot
    if($version -ne $ExpectedEfbVersion) {
        throw ("{0} version mismatch. Expected {1}; actual {2}" -f $Label,$ExpectedEfbVersion,$version)
    }
    $js=Join-Path $PackageRoot 'html_ui\efb_ui\efb_apps\SimVoiceCopilot\TemplateApp.js'
    Assert-Contains $js $R2LMarker ($Label + ' R2L marker')
    Assert-Contains $js 'mark-sidecar-runtime-shape' ($Label + ' R2L diagnostic kind')
    Assert-Contains $js 'observational-only' ($Label + ' observational mode')
}

$versionProps=Join-Path $WindowsProjectRoot 'Version.props'
$parser2024=Join-Path $WindowsProjectRoot 'Msfs2024EfbChecklistParser.cs'
$resolver=Join-Path $WindowsProjectRoot 'ChecklistPackageVisualHelperResolver.cs'
$main=Join-Path $WindowsProjectRoot 'MainForm.cs'
$builder=Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs'
$models=Join-Path $WindowsProjectRoot 'ChecklistModels.cs'
$sessionService=Join-Path $WindowsProjectRoot 'ChecklistSessionPersistenceService.cs'
$sessionManager=Join-Path $WindowsProjectRoot 'ChecklistSessionManager.cs'
$catalogReceiver=Join-Path $WindowsProjectRoot 'NativeFs2024ChecklistCatalogReceiver.cs'
$learning=Join-Path $WindowsProjectRoot 'ChecklistProcedureLearningService.cs'
$focusBridge=Join-Path $WindowsProjectRoot 'Msfs2024FocusInstrumentBridge.cs'
$visionJetBridge=Join-Path $WindowsProjectRoot 'VisionJetG3000GuidedFocusBridge.cs'

$nativeProbe=Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\diagnostics\NativeChecklistProbe.ts'
$sidecar=Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\native\MarkRuntimeSidecarProbe.ts'
$bridge=Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\native\NativeChecklistBridge.ts'
$app=Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$build=Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

# Version authority remains Windows 1.1.1.0.
Assert-Contains $versionProps '<SimVoiceVersion>1.1.1.0</SimVoiceVersion>' 'Version.props'
Assert-Contains $versionProps '<AssemblyVersion>$(SimVoiceVersion)</AssemblyVersion>' 'AssemblyVersion authority'

# Frozen R1G + R3D + R2K files must be byte-identical to the 2026-09-09 11:53 SourceTruth.
Assert-Sha256 $builder 'DE89B291A8BF2A7F5830D509E724536099A6548EC353505E40AEEA79AA9CDEF8' 'R1G AiCommandBuilderForm.cs'
Assert-Sha256 $main '2411833C6DACF217CE9DBE9B8F676093A71048E9CE5F69540283C48B4B32B52A' 'R3D/R2K MainForm.cs'
Assert-Sha256 $parser2024 'A872C7B61113CCE1A0AC0BB02A5573EAD6509F85A70478CB170BB8A0E58FEEAB' 'R2K Msfs2024EfbChecklistParser.cs'
Assert-Sha256 $sessionService 'A64E4940DA41241D5F883595AA4429F5481D7A4AE1C34CD6814341972EADD57D' 'R3D ChecklistSessionPersistenceService.cs'
Assert-Sha256 $sessionManager 'D0749E05F268FF627A6F226A0507CB214247A17299EEED4D4325098D9794CF77' 'R3D ChecklistSessionManager.cs'
Assert-Sha256 $models '85C2D84A319D0E4EAA56B4BC5EB3D426C419741A4FFE83824DB5AF1C6424E996' 'ChecklistModels.cs'
Assert-Sha256 $catalogReceiver '49D535D163864089D66A5C616DC15F330B941CB913F11FFADD496740F8FC66DC' 'NativeFs2024ChecklistCatalogReceiver.cs'
Assert-Sha256 $learning 'ADB572C2BDE9314E4DBB123D7AD9CD516FD1C13D4E90AF2A7D9443CDB25A678D' 'ChecklistProcedureLearningService.cs'
Assert-Sha256 $resolver '0FF3040C0A2D8489B1351DF236F780397DD985E6B31066562785ED6938F6FA7A' 'ChecklistPackageVisualHelperResolver.cs'
Assert-Sha256 $focusBridge 'BB5E0EDDEB366756D30ADB88F3874DD6E7BC1B2DEC584D914F562956C81D6245' 'Msfs2024FocusInstrumentBridge.cs'
Assert-Sha256 $visionJetBridge '1BD59105ED218B5154BE59EB2123B2A724B49F545A386674F769FA506C86D053' 'VisionJetG3000GuidedFocusBridge.cs'
Assert-Sha256 $nativeProbe 'FEE5B6D526B3385656F9272C02C9274E9C908E30021CC8C9C1CC5EB9E992151F' 'NativeChecklistProbe.ts'

# R2J stays rejected.
Assert-NotContains $parser2024 'SIMVOICE_1_1_1_0_R2J_MSFS2024_VISUAL_METADATA' 'R2J parser instrumentation'
Assert-NotContains $resolver 'SIMVOICE_1_1_1_0_R2J_MSFS2024_ITEM_LOOKUP' 'R2J item lookup'
Assert-Contains $resolver 'SIMVOICE_1_1_1_0_R2I_TT_CHECKPOINT_LOOKUP' 'R2I resolver baseline'
Assert-Contains $main 'SIMVOICE_1_1_1_0_R3D_RESTORE_LANGUAGE_PRESERVATION' 'R3D Spanish resume'
Assert-Contains $builder 'dgvActions.MinimumSize = new Size(0, 0);' 'R1G Builder layout'

# R2L sidecar is isolated and observational.
Assert-Contains $sidecar $R2LMarker 'R2L sidecar marker'
Assert-Contains $sidecar 'Object.getOwnPropertyNames' 'R2L own-property inspection'
Assert-Contains $sidecar 'Object.getOwnPropertyDescriptor' 'R2L descriptor inspection'
Assert-Contains $sidecar 'descriptor.get.call(receiver)' 'R2L bounded safe getter read'
Assert-Contains $sidecar "this.normalizeKey(entry.key) !== 'bhasinstruments'" 'R2L instrument anchor key detection'
Assert-Contains $sidecar 'read.value === true' 'R2L instrument anchor truth gate'
Assert-Contains $bridge 'source.bHasInstruments === true' 'R2L raw runtime instrument candidate anchor'
Assert-Contains $sidecar "mode: 'observational-only'" 'R2L observational payload'
Assert-NotContains $sidecar 'START_HELP' 'R2L sidecar START_HELP ban'
Assert-NotContains $sidecar 'CHECKLIST_START_HELP' 'R2L sidecar checklist helper ban'
Assert-NotContains $sidecar 'FocusInstrumentAction' 'R2L sidecar FocusInstrumentAction ban'
Assert-NotContains $sidecar 'NativeFocusTarget' 'R2L sidecar catalog target mutation ban'
Assert-NotContains $sidecar 'VisualInstrumentPartIds' 'R2L sidecar PartID mutation ban'
Assert-NotContains $sidecar 'VisualInstrumentHtmlIds' 'R2L sidecar HtmlID mutation ban'
Assert-NotContains $sidecar 'SetCamera' 'R2L sidecar camera ban'

Assert-Contains $bridge "from './MarkRuntimeSidecarProbe'" 'R2L bridge import'
Assert-Contains $bridge 'this.markRuntimeSidecarProbe.observePage(' 'R2L raw runtime observation'
Assert-Contains $bridge "this.safeSend('diagnostic.nativechecklist.probe', markRuntimeProbePayload)" 'R2L diagnostic transport'
$bridgeText=[System.IO.File]::ReadAllText($bridge)
$observeIndex=$bridgeText.IndexOf('this.markRuntimeSidecarProbe.observePage(',[System.StringComparison]::Ordinal)
$enrichIndex=$bridgeText.IndexOf('this.enrichNativeChecklistPageForVisualHelpers(page)',[System.StringComparison]::Ordinal)
if($observeIndex -lt 0 -or $enrichIndex -lt 0 -or $observeIndex -ge $enrichIndex) {
    throw 'R2L must observe raw GET_CHECKLIST_PAGE before legacy enrichment.'
}

Assert-Contains $app "const EFB_VERSION = '0.1.115';" 'EFB 0.1.115'
Assert-Contains $build '$ExpectedEfbVersion = "0.1.115"' 'EFB build 0.1.115'
Assert-Contains $build $R2LMarker 'R2L build marker gate'

# Generated package and both Windows copies must carry 0.1.115 + R2L.
if (-not $SourceOnly) {
    Assert-Package (Join-Path $EfbProjectRoot 'Packages\simtech-simvoice-efb') 'Generated EFB package'
    Assert-Package (Join-Path $WindowsProjectRoot 'MSFS\Packages\simtech-simvoice-efb') 'Windows bundled EFB'
    Assert-Package (Join-Path $WindowsProjectRoot 'Store\Runtime\MSFS\Packages\simtech-simvoice-efb') 'Store Runtime EFB'
}

Write-Host '============================================================' -ForegroundColor Cyan
if ($SourceOnly) {
    Write-Host ' SVC 1.1.1.0 R2L MARK RUNTIME SIDECAR SOURCE QA: PASS' -ForegroundColor Green
}
else {
    Write-Host ' SVC 1.1.1.0 R2L MARK RUNTIME SIDECAR SOURCE/PACKAGE QA: PASS' -ForegroundColor Green
}
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'R2L is discovery-only. MARK is NOT declared solved until runtime IDs are proven and visual QA passes.' -ForegroundColor Yellow
exit 0
