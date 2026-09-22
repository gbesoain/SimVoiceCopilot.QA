#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp",
    [string]$EfbProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS"
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Path, [string]$Needle, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw "$Label missing in ${Path}: $Needle"
    }
}

function Assert-PackageVersion {
    param([string]$PackageRoot, [string]$Label)
    $manifest = Join-Path $PackageRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "$Label manifest missing: $manifest" }
    $json = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $value = $null
    foreach ($name in @('package_version','packageVersion','version','Version')) {
        $p = $json.PSObject.Properties[$name]
        if ($null -ne $p -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)) { $value = ([string]$p.Value).Trim(); break }
    }
    if ($value -ne '0.1.104') { throw "$Label version mismatch. Expected 0.1.104, found '$value'." }
}

$controller = Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs'
$ui = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$protocol = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\core\protocol.ts'
$i18n = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\core\i18n.ts'
$css = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css'
$build = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

Assert-Contains $controller 'SIMVOICE_1_1_1_0_MARK_HIGHLIGHT_ONLY_R2' 'R2 Windows MARK marker'
Assert-Contains $controller '["canMarkCurrentItem"]' 'R2 MARK capability state'
Assert-Contains $controller '["markActive"]' 'R2 MARK active state'
Assert-Contains $controller 'ClearChecklistMark("marked-item-ended")' 'R2 one-item MARK lifetime'
Assert-Contains $controller 'A manual MARK intentionally overrides AUTO for this item only' 'R2 AUTO suspension policy'
Assert-Contains $controller 'false,' 'R2 FocusInstrumentAction camera=false call'
Assert-Contains $controller 'switch-mark-to-focus' 'R2 MARK to FOCUS ownership handoff'
Assert-Contains $controller 'switch-focus-to-mark' 'R2 FOCUS to MARK ownership handoff'

Assert-Contains $protocol 'canMarkCurrentItem?: boolean;' 'R2 EFB protocol capability'
Assert-Contains $protocol 'markActive?: boolean;' 'R2 EFB protocol state'
Assert-Contains $i18n "markCockpitItem: 'Mark'" 'R2 MARK EN label'
Assert-Contains $i18n "markCockpitItem: 'Marcar'" 'R2 MARK ES label'
Assert-Contains $ui "const EFB_VERSION = '0.1.104';" 'R2 EFB version'
Assert-Contains $ui "sendAction('checklist.mark')" 'R2 MARK UI action'
Assert-Contains $ui 'focusControls.append(autoButton, markButton, focusButton)' 'R2 AUTO/MARK/FOCUS ordering'
Assert-Contains $css '.sv-mark-button.on' 'R2 MARK active style'
Assert-Contains $build '$ExpectedEfbVersion = "0.1.104"' 'R2 EFB build version gate'

Assert-PackageVersion (Join-Path $EfbProjectRoot 'Packages\simtech-simvoice-efb') 'EFB package'
Assert-PackageVersion (Join-Path $WindowsProjectRoot 'MSFS\Packages\simtech-simvoice-efb') 'Windows bundled EFB'
Assert-PackageVersion (Join-Path $WindowsProjectRoot 'Store\Runtime\MSFS\Packages\simtech-simvoice-efb') 'Store Runtime EFB'

$packagedJs = Join-Path $EfbProjectRoot 'Packages\simtech-simvoice-efb\html_ui\efb_ui\efb_apps\SimVoiceCopilot\TemplateApp.js'
$packagedCss = Join-Path $EfbProjectRoot 'Packages\simtech-simvoice-efb\html_ui\efb_ui\efb_apps\SimVoiceCopilot\TemplateApp.css'
Assert-Contains $packagedJs 'SIMVOICE_1_1_1_0_MARK_HIGHLIGHT_ONLY_R2' 'R2 packaged MARK marker'
Assert-Contains $packagedJs 'checklist.mark' 'R2 packaged MARK action'
Assert-Contains $packagedCss '.sv-mark-button.on' 'R2 packaged MARK active style'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2 MARK SOURCE + PACKAGE QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
