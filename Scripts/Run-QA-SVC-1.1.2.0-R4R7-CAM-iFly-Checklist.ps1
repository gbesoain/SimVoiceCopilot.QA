#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$WindowsProjectRoot,
    [Parameter(Mandatory=$true)][string]$EfbProjectRoot
)
$ErrorActionPreference = 'Stop'

function RF([string]$p) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing: $p" } }
function RT([string]$p) { RF $p; return [IO.File]::ReadAllText($p) }
function RC([string]$t,[string]$n,[string]$l) { if ($t.IndexOf($n,[StringComparison]::Ordinal) -lt 0) { throw "$l missing: $n" } }

Write-Host 'R4R7 QA started...'

[xml]$vx = Get-Content -LiteralPath (Join-Path $WindowsProjectRoot 'Version.props') -Raw
$v=$vx.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
$d=$vx.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion')
if ($null -eq $v -or $null -eq $d -or $v.InnerText.Trim() -ne '1.1.2.0' -or $d.InnerText.Trim() -ne '1.1.2.0') {
    throw 'Windows version must remain 1.1.2.0.'
}

$sdk=RT (Join-Path $WindowsProjectRoot 'Ifly737MaxSdk.cs')
$svc=RT (Join-Path $WindowsProjectRoot 'Ifly737MaxSystemCommandService.cs')
$vosk=RT (Join-Path $WindowsProjectRoot 'VoskRecognizer.cs')
$main=RT (Join-Path $WindowsProjectRoot 'MainForm.cs')
$ctl=RT (Join-Path $WindowsProjectRoot 'SimVoiceEfbLocalController.cs')
$cap=RT (Join-Path $WindowsProjectRoot 'ChecklistCameraBindingCaptureService.cs')
$store=RT (Join-Path $WindowsProjectRoot 'ChecklistCameraBindingStore.cs')

foreach($x in @(
 'CmdRunwayTurnoffLeftSet = 17','CmdRunwayTurnoffRightSet = 19','CmdTaxiLightSet = 21',
 'CmdEngine1StartSet = 705','CmdEngine2StartSet = 708','CmdApuSet = 725',
 'CmdBaroStdLeft = 868','CmdBaroStdRight = 903','CmdXpndrReplySelectorSet = 1119')) { RC $sdk $x 'iFly SDK constants' }

foreach($x in @(
 'SIMVOICE_1_1_2_0_R4R7_IFLY737MAX_SYSTEM_VOICE_COMMANDS',
 '"taxi lights"','"runway lights"','"engine start one"','"engine start two"',
 '"apu start"','"transponder standby"','"transponder on"','"baro std"',
 'Ifly737MaxSdk.TrySendCommand')) { RC $svc $x 'iFly service' }

foreach($x in @(
 'Ifly737MaxSystemCommandService.GetGrammarPhrases()',
 'Ifly737MaxSystemCommandService.TryResolvePhrase',
 'Ifly737MaxSystemCommandService.IsSupportedAction',
 'NotifySimulatorCommandExecuted(text, action)')) { RC $vosk $x 'Vosk iFly routing' }

foreach($x in @(
 'SIMVOICE_1_1_2_0_R4R7_NAMED_CHECKLIST_VOICE_START',
 'TryStartChecklistByVoiceName','GetNamedChecklistVoicePhrases',
 'StartEfbSelectionOption','recognizer.PriorityVoiceIntentHandler = text =>')) { RC $main $x 'Named checklist voice' }

foreach($x in @('userCameraBindingCaptureStatus','userCameraBindingCaptureMessage','"recording"','"saved"','"timeout"','Camera saved:')) { RC $ctl $x 'Camera UX' }
foreach($x in @('WhKeyboardLl = 13','SetWindowsHookEx','CallNextHookEx','CaptureTimeoutMilliseconds')) { RC $cap $x 'Camera capture' }
RC $store 'SimVoiceAhkInputBridge.TryQueue' 'Camera playback feeder'

$ui=RT (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\ui\SimVoiceLocalEfbApp.ts')
$pr=RT (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\core\protocol.ts')
$css=RT (Join-Path $EfbProjectRoot 'PackageSources\TemplateApp\src\SimVoiceCopilot\style.css')
foreach($x in @("const EFB_VERSION = '0.1.138';",'CAM: GRABANDO','GRABANDO CAMARA','userCameraBindingCaptureStatus','userCameraBindingCaptureMessage','Presiona AHORA')) { RC $ui $x 'R4R7 EFB camera UX' }
RC $pr 'userCameraBindingCaptureStatus?' 'R4R7 protocol'
RC $pr 'userCameraBindingCaptureMessage?' 'R4R7 protocol'
RC $css 'font-size: 11.5px;' 'R4R7 readable help'

Write-Host 'R4R7 SOURCE QA: PASS' -ForegroundColor Green
