#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WindowsProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Text {
    param([string]$Text,[string]$Needle,[string]$Label)
    if ($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing: {1}" -f $Label,$Needle)
    }
}

$mainPath = Join-Path $WindowsProjectRoot 'MainForm.cs'
$managerPath = Join-Path $WindowsProjectRoot 'ChecklistSessionManager.cs'
if (-not (Test-Path -LiteralPath $mainPath -PathType Leaf)) { throw "Missing MainForm.cs: $mainPath" }
if (-not (Test-Path -LiteralPath $managerPath -PathType Leaf)) { throw "Missing ChecklistSessionManager.cs: $managerPath" }

$main = [System.IO.File]::ReadAllText($mainPath)
$manager = [System.IO.File]::ReadAllText($managerPath)

Require-Text $main 'SIMVOICE_1_1_1_0_R2Q_RESTART_FOCUS_REHYDRATION' 'R2Q MainForm marker'
Require-Text $main 'CHECKLIST_RESTART_FOCUS_REHYDRATED' 'R2Q restart diagnostic'
Require-Text $main 'late-native-focus-after-command-builder-restart' 'R2Q late-native translation pass'
Require-Text $main '.RefreshPresentationAndFocusMetadataFromSource()' 'R2Q session metadata refresh call'
Require-Text $main 'CHECKLIST_SESSION_RESTORE_TRANSLATION_DEFERRED_FOR_FOCUS' 'R2Q translated-first focus guard'
Require-Text $main 'VisionJetG3000GuidedFocusBridge.HasNativeFocusOverlay(document)' 'R2Q focus-overlay guard'

$markerIndex = $main.IndexOf('// R2Q: the AI Command Builder restart restores the voice checklist',[System.StringComparison]::Ordinal)
if ($markerIndex -lt 0) { throw 'R2Q active-session branch marker not found.' }
$branchLength = [Math]::Min(9000,$main.Length-$markerIndex)
$branch = $main.Substring($markerIndex,$branchLength)
$applyIndex = $branch.IndexOf('VisionJetG3000GuidedFocusBridge.Apply(',[System.StringComparison]::Ordinal)
$translateIndex = $branch.IndexOf('late-native-focus-after-command-builder-restart',[System.StringComparison]::Ordinal)
$refreshIndex = $branch.IndexOf('.RefreshPresentationAndFocusMetadataFromSource()',[System.StringComparison]::Ordinal)
$publishIndex = $branch.IndexOf('simVoiceEfbLocalController.PublishNow()',[System.StringComparison]::Ordinal)
if ($applyIndex -lt 0 -or $translateIndex -lt 0 -or $refreshIndex -lt 0 -or $publishIndex -lt 0) {
    throw 'R2Q active-session rehydration branch is incomplete.'
}
if (-not ($applyIndex -lt $translateIndex -and $translateIndex -lt $refreshIndex -and $refreshIndex -lt $publishIndex)) {
    throw 'R2Q active-session rehydration ordering is invalid.'
}

Require-Text $manager 'public int RefreshPresentationAndFocusMetadataFromSource()' 'R2Q session refresh method'
$methodStart = $manager.IndexOf('public int RefreshPresentationAndFocusMetadataFromSource()',[System.StringComparison]::Ordinal)
$restoreStart = $manager.IndexOf('public bool Restore(',$methodStart,[System.StringComparison]::Ordinal)
if ($methodStart -lt 0 -or $restoreStart -le $methodStart) { throw 'Unable to isolate R2Q session refresh method.' }
$method = $manager.Substring($methodStart,$restoreStart-$methodStart)
foreach ($anchor in @(
    '.GroupBy(item => item.SourceIndex)',
    'sessionItem.LabelText = sourceItem.LabelText;',
    'sessionItem.ActionText = sourceItem.ActionText;',
    'sessionItem.Text = sourceItem.Text;',
    'sessionItem.NativeFocusTarget = sourceItem.NativeFocusTarget;',
    'sessionItem.NativeVisualHelperAvailable = sourceItem.NativeVisualHelperAvailable;',
    'sessionItem.VisualInstrumentPartIds.AddRange(sourceItem.VisualInstrumentPartIds);',
    'sessionItem.VisualInstrumentHtmlIds.AddRange(sourceItem.VisualInstrumentHtmlIds);',
    'RaiseStateChanged();'
)) {
    Require-Text $method $anchor 'R2Q session refresh method'
}
if ($method.IndexOf('sessionItem.Status =',[System.StringComparison]::Ordinal) -ge 0) {
    throw 'R2Q session refresh must not mutate checklist progress/status.'
}

Write-Host '============================================================'
Write-Host ' SVC 1.1.1.0 R2Q RESTART FOCUS REHYDRATE QA: PASS'
Write-Host '============================================================'
Write-Host 'Late native G3000 metadata is rehydrated into restored session clones without changing progress.'
exit 0
