#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)]
    [string]$WindowsProjectRoot
)

$ErrorActionPreference = 'Stop'

function Require-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file missing: $Path"
    }
}

function Read-Text {
    param([string]$Path)
    Require-File $Path
    return [IO.File]::ReadAllText($Path)
}

function Require-Contains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Label
    )
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "$Label missing required semantic: $Needle"
    }
}

function Require-NotContains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Label
    )
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) {
        throw "$Label contains forbidden semantic: $Needle"
    }
}

Write-Host 'Freemium Telemetry R2 source QA started...'

$versionPath = Join-Path $WindowsProjectRoot 'Version.props'
[xml]$versionXml = Get-Content -LiteralPath $versionPath -Raw
$version = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceVersion')
$display = $versionXml.SelectSingleNode('/Project/PropertyGroup/SimVoiceDisplayVersion')
if ($null -eq $version -or $null -eq $display -or
    $version.InnerText.Trim() -ne '1.1.2.0' -or
    $display.InnerText.Trim() -ne '1.1.2.0') {
    throw 'Windows version must remain 1.1.2.0.'
}

$subscription = Read-Text (Join-Path $WindowsProjectRoot 'SubscriptionService.cs')
$service = Read-Text (Join-Path $WindowsProjectRoot 'FreemiumTelemetryMilestoneService.cs')
$tests = Read-Text (Join-Path $WindowsProjectRoot 'FreemiumTelemetryRegressionTests.cs')
$program = Read-Text (Join-Path $WindowsProjectRoot 'Program.cs')
$main = Read-Text (Join-Path $WindowsProjectRoot 'MainForm.cs')
$premium = Read-Text (Join-Path $WindowsProjectRoot 'PremiumUpgradeExperience.cs')
$vosk = Read-Text (Join-Path $WindowsProjectRoot 'VoskRecognizer.cs')
$sim = Read-Text (Join-Path $WindowsProjectRoot 'SimConnectBridge.cs')
$checklist = Read-Text (Join-Path $WindowsProjectRoot 'ChecklistSessionManager.cs')

foreach ($required in @(
    'TrackFunnelEventConfirmedAsync',
    'TrackFunnelEventCoreAsync',
    'action_type =',
    'client_event_id =',
    'flow_action = "funnel_event"',
    'ValidationEndpoint'
)) {
    Require-Contains $subscription $required 'SubscriptionService'
}

foreach ($required in @(
    'FreeAppActivatedEventName = "free_app_activated"',
    'FreeMeaningfulUsageEventName = "free_meaningful_usage"',
    'PremiumUpgradePromptShownEventName = "premium_upgrade_prompt_shown"',
    'client_event_id',
    'first_action_type',
    'AttemptCount',
    'File.Replace',
    'TrackFunnelEventConfirmedAsync',
    'SimVoiceEntitlementManager.IsVerifiedFree',
    'NotifyAppOperational',
    'NotifyMeaningfulUsage',
    'NotifyPremiumUpgradePromptShown'
)) {
    Require-Contains $service $required 'FreemiumTelemetryMilestoneService'
}

foreach ($forbidden in @(
    '"free_account_created"',
    '"premium_to_free"',
    '"entitlement_transition"'
)) {
    Require-NotContains $service $forbidden 'FreemiumTelemetryMilestoneService'
}

Require-Contains $main 'FreemiumTelemetryMilestoneService.NotifyAppOperational()' 'MainForm operational milestone'
Require-Contains $main 'protected override void OnShown(EventArgs e)' 'MainForm operational boundary'

Require-Contains $premium 'dialog.Shown +=' 'Premium prompt actual display boundary'
Require-Contains $premium 'FreemiumTelemetryMilestoneService.NotifyPremiumUpgradePromptShown(' 'Premium prompt remote telemetry'
Require-Contains $premium '"PREMIUM_UPGRADE_PROMPT_SHOWN"' 'Existing premium prompt local semantic'

Require-Contains $vosk 'FreemiumTelemetryMilestoneService.NotifyMeaningfulUsage("voice_command")' 'Successful voice command hook'
Require-Contains $vosk 'FreemiumTelemetryMilestoneService.NotifyMeaningfulUsage("keyboard")' 'Successful keyboard hook'
Require-Contains $vosk 'private bool NotifySimulatorCommandExecuted' 'Voice command success boundary'
Require-Contains $vosk 'File.WriteAllText(cmdFile, keyCombo);' 'Keyboard dispatch boundary'

Require-Contains $sim 'FreemiumTelemetryMilestoneService.NotifyMeaningfulUsage("callout")' 'Successful callout hook'
Require-Contains $sim 'PublishImmediateCalloutResponse(response, true)' 'Multi/wind successful callout boundary'
Require-Contains $sim 'PublishImmediateCalloutResponse(spokenResponse, true)' 'FPS successful callout boundary'

Require-Contains $checklist 'FreemiumTelemetryMilestoneService.NotifyMeaningfulUsage("checklist")' 'Checklist confirm hook'
Require-Contains $checklist 'if (confirmed)' 'Checklist successful interaction guard'

Require-Contains $program '--qa-freemium-telemetry-r2' 'CLI telemetry QA mode'
Require-Contains $program 'FreemiumTelemetryRegressionTests.RunOrThrow();' 'Telemetry regression suite invocation'

foreach ($required in @(
    'ShouldRecordFreeMilestone(true, false)',
    'ShouldRecordMeaningfulUsage(',
    'ShouldTrackPremiumPromptShown(',
    'retry must retain the same client_event_id',
    'Premium must never emit Free milestones'
)) {
    Require-Contains $tests $required 'Freemium telemetry regression tests'
}

Write-Host 'FREEMIUM TELEMETRY R2 SOURCE QA: PASS' -ForegroundColor Green
