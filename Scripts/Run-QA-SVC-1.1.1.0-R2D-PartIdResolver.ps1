#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp",
    [string]$EfbProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Path, [string]$Needle, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Missing file for {0}: {1}" -f $Label, $Path)
    }

    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing in {1}: {2}" -f $Label, $Path, $Needle)
    }
}

$parser = Join-Path $WindowsProjectRoot 'Msfs2020LegacyChecklistParser.cs'
$bridge = Join-Path $WindowsProjectRoot 'VisionJetG3000GuidedFocusBridge.cs'
$controller = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$app = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$build = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

Assert-Contains $parser 'ExtractXmlVisualHelperIds(checkpoint, definition, item);' 'package XML visual helper extraction'
Assert-Contains $parser '.Where(IsElement("Instrument"))' 'Instrument Id extraction'
Assert-Contains $parser '"HTML:"' 'HTML checklist helper classification'

Assert-Contains $bridge 'SIMVOICE_1_1_1_0_R2D_PACKAGE_PARTID_RESOLVER' 'R2D resolver marker'
Assert-Contains $bridge 'FocusTarget.FromNative(best, legacyItem)' 'package identifier donor mapping'
Assert-Contains $bridge 'packageIdentifierDonor.VisualInstrumentPartIds' 'PartID donor merge'
Assert-Contains $bridge 'packageIdentifierDonor.VisualInstrumentHtmlIds' 'HtmlID donor merge'
Assert-Contains $bridge 'resolvedIdentifierItems' 'support package resolver evidence'

Assert-Contains $controller 'partIdResolverMarker' 'Windows direct MARK resolver evidence'

Assert-Contains $app 'const directMarkerAvailable =' 'persistent MARK direct branch'
Assert-Contains $app 'Number(checklist?.focusPartCount ?? 0) > 0' 'resolved identifier availability'
Assert-Contains $app "resolver: 'package-partid-r2d'" 'R2D direct MARK action'
Assert-Contains $app "const EFB_VERSION = '0.1.107';" 'EFB 0.1.107'

Assert-Contains $build '$ExpectedEfbVersion = "0.1.107"' 'EFB build version 0.1.107'
Assert-Contains $build 'R2D package PartID resolver marker is missing' 'compiled JS resolver gate'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2D PARTID RESOLVER SOURCE QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
