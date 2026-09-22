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

$native = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\native\NativeChecklistBridge.ts'
$app = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$build = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

Assert-Contains $native 'SIMVOICE_1_1_1_0_R2E_HIDDEN_PARTID_RESOLVER' 'hidden PartID resolver marker'
Assert-Contains $native 'Object.getOwnPropertyNames' 'non-enumerable runtime inspection'
Assert-Contains $native 'Object.getPrototypeOf' 'prototype runtime inspection'
Assert-Contains $native 'page: enrichedPage.page' 'enriched native checklist catalog page'
Assert-Contains $native 'hiddenPartIdCount' 'hidden PartID diagnostics'
Assert-Contains $native 'hiddenHtmlIdCount' 'hidden HtmlID diagnostics'

Assert-Contains $app 'SIMVOICE_1_1_1_0_R2E_FLAT_MARK_NO_CAMERA' 'flat-screen MARK safety marker'
Assert-Contains $app 'r2e-flat-mark-native-helper-suppressed' 'native helper cleanup before suppression'
Assert-Contains $app "const EFB_VERSION = '0.1.108';" 'EFB 0.1.108'
Assert-Contains $build '$ExpectedEfbVersion = "0.1.108"' 'EFB build version 0.1.108'
Assert-Contains $build 'R2E safe MARK / hidden PartID resolver markers are missing' 'compiled JS R2E gate'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2E SAFE MARK / HIDDEN PARTID QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
