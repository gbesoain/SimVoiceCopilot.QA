[CmdletBinding()]
param(
    [string]$AppNamePattern = "*SimVoice*",
    [string]$ProcessName = "SimVoiceCopilotApp",
    [string]$SimConnectDll = "",
    [ValidateRange(1, 5)]
    [int]$MaxAttempts = 2,
    [switch]$SkipAppLaunch,
    [switch]$NoInteractiveRetry,
    [switch]$CloseAppAtEnd,
    [switch]$NoBuild
)

$runner = Join-Path $PSScriptRoot "Run-QA-Flight-Functional.ps1"
& $runner `
    -Suite SmokeEN `
    -AppNamePattern $AppNamePattern `
    -ProcessName $ProcessName `
    -SimConnectDll $SimConnectDll `
    -MaxAttempts $MaxAttempts `
    -SkipAppLaunch:$SkipAppLaunch `
    -NoInteractiveRetry:$NoInteractiveRetry `
    -CloseAppAtEnd:$CloseAppAtEnd `
    -NoBuild:$NoBuild

exit $LASTEXITCODE
