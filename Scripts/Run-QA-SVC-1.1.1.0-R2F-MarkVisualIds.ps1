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
        throw ("Missing {0}: {1}" -f $Label, $Path)
    }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing in {1}: {2}" -f $Label, $Path, $Needle)
    }
}

$parser = Join-Path $WindowsProjectRoot 'Msfs2020LegacyChecklistParser.cs'
$learning = Join-Path $WindowsProjectRoot 'ChecklistProcedureLearningService.cs'
$app = Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts'
$build = Join-Path $EfbProjectRoot 'scripts\Build-SimVoiceEfb.ps1'

Assert-Contains $parser 'NormalizeVisualIdPropertyName' 'broadened package visual-ID parser'
Assert-Contains $parser 'visualhelperpartid' 'PartID attribute variants'
Assert-Contains $learning 'SIMVOICE_1_1_1_0_R2F_LEARNED_VISUAL_ID_OVERLAY' 'learned visual overlay marker'
Assert-Contains $learning 'OverlayObservedVisualHelpersIntoLearnedRuntime' 'physical-to-learned runtime overlay'
Assert-Contains $learning 'visualInstrumentPartIds' 'learned PartID persistence'
Assert-Contains $learning 'visualInstrumentHtmlIds' 'learned HtmlID persistence'
Assert-Contains $learning 'CHECKLIST_LEARNED_VISUAL_HELPER_OVERLAY' 'overlay support diagnostic'
Assert-Contains $app "const EFB_VERSION = '0.1.109';" 'EFB 0.1.109'
Assert-Contains $build '$ExpectedEfbVersion = "0.1.109"' 'EFB build 0.1.109'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R2F MARK VISUAL-ID OVERLAY QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
