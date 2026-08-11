[CmdletBinding()]
param(
    [ValidateSet("Auto", "SmokeEN", "CoreEN", "SmokeES", "CoreES")]
    [string]$Suite = "Auto",

    [string]$AppNamePattern = "*SimVoice Copilot*",
    [string]$AppIdPattern = "SimTechAviation.SimVoiceCopilot.Dev_*",
    [string]$ProcessName = "SimVoiceCopilotApp",
    [string]$OutputDirectory = "",
    [switch]$NoClose
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$runner = Join-Path $PSScriptRoot "Run-QA-MSIX.ps1"
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "Run-QA-MSIX.ps1 was not found: $runner"
}

$params = @{
    AppNamePattern = $AppNamePattern
    AppIdPattern = $AppIdPattern
    ProcessName = $ProcessName
    Scenario = "VoiceChecklists"
    ChecklistSuite = $Suite
    Cycles = 1
}
if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $params.OutputDirectory = $OutputDirectory
}
if ($NoClose) {
    $params.NoClose = $true
}

& $runner @params
exit $LASTEXITCODE
