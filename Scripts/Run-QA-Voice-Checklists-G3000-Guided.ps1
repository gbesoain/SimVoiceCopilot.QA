[CmdletBinding()]
param(
    [string]$AppIdPattern = "SimTechAviation.SimVoiceCopilot.Dev_*",
    [string]$PipeName = "SimVoiceCopilot.QA.InternalAudio.v1",
    [string]$ConfirmationPhrase = "",
    [ValidateRange(30, 300)]
    [int]$ReadyTimeoutSeconds = 150,
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputDirectory = Join-Path $projectRoot "QA-Runs\VoiceChecklistsG3000\G3000-$stamp"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Invoke-BridgeRequest {
    param(
        [string]$Action,
        [string]$Text = "",
        [string]$Language = "",
        [int]$TimeoutMs = 30000
    )

    $pipe = $null
    $reader = $null
    $writer = $null
    try {
        $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
            ".",
            $PipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            [System.IO.Pipes.PipeOptions]::Asynchronous)
        $pipe.Connect([Math]::Min(30000, [Math]::Max(1000, $TimeoutMs)))
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $reader = [System.IO.StreamReader]::new($pipe, $utf8, $false, 65536, $true)
        $writer = [System.IO.StreamWriter]::new($pipe, $utf8, 65536, $true)
        $writer.AutoFlush = $true

        $request = [ordered]@{
            ProtocolVersion = 1
            Action = $Action
            CorrelationId = [guid]::NewGuid().ToString("N")
            Text = $Text
            Language = $Language
            TimeoutMs = $TimeoutMs
            SpeechRate = 0
            PostCommandWaitMs = 700
        }
        $writer.WriteLine(($request | ConvertTo-Json -Compress))

        $task = $reader.ReadLineAsync()
        if (-not $task.Wait($TimeoutMs + 10000)) {
            throw "Timed out waiting for the Internal Audio QA bridge response."
        }
        if ([string]::IsNullOrWhiteSpace($task.Result)) {
            throw "Internal Audio QA bridge returned an empty response."
        }
        return $task.Result | ConvertFrom-Json
    }
    finally {
        if ($writer) { try { $writer.Dispose() } catch { } }
        if ($reader) { try { $reader.Dispose() } catch { } }
        if ($pipe) { try { $pipe.Dispose() } catch { } }
    }
}

$apps = @(Get-StartApps | Where-Object { $_.AppID -like $AppIdPattern })
if ($apps.Count -ne 1) {
    $detail = ($apps | ForEach-Object { "$($_.Name) -> $($_.AppID)" }) -join [Environment]::NewLine
    throw "Expected exactly one private QA app matching '$AppIdPattern'. Found $($apps.Count).$([Environment]::NewLine)$detail"
}

if (-not (Get-Process SimVoiceCopilotApp -ErrorAction SilentlyContinue)) {
    Start-Process "shell:AppsFolder\$($apps[0].AppID)"
}

$deadline = (Get-Date).AddSeconds(60)
$ping = $null
while ((Get-Date) -lt $deadline) {
    try {
        $ping = Invoke-BridgeRequest -Action "ping" -TimeoutMs 3000
        if ($ping.Success) { break }
    }
    catch { }
    Start-Sleep -Milliseconds 500
}
if ($null -eq $ping -or -not $ping.Success) {
    throw "Internal Audio QA bridge is not available. Confirm that the app title includes [QA Internal Audio]."
}

$language = [string]$ping.VoiceLanguage
if ([string]::IsNullOrWhiteSpace($ConfirmationPhrase)) {
    $ConfirmationPhrase = if ($language.StartsWith("es", [StringComparison]::OrdinalIgnoreCase)) { "hecho" } else { "checked" }
}

Write-Host ""
Write-Host "Guided G3000 / Vision Jet G2 checklist synchronization test" -ForegroundColor Cyan
Write-Host "1. Run Microsoft Flight Simulator 2024." -ForegroundColor Yellow
Write-Host "2. Load the Cirrus Vision Jet G2 and wait until the flight is active." -ForegroundColor Yellow
Write-Host "3. In SimVoice Copilot, open Checklist, select the real Vision Jet checklist and start it." -ForegroundColor Yellow
Read-Host "Press ENTER when the checklist is running"

$deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
$status = $null
while ((Get-Date) -lt $deadline) {
    $status = Invoke-BridgeRequest -Action "status" -TimeoutMs 5000
    $checklist = $status.Diagnostics.checklist
    $sync = $status.Diagnostics.checklistSync
    if ($status.Success -and
        $null -ne $checklist -and
        $null -ne $sync -and
        [string]$checklist.state -eq "Running" -and
        [bool]$sync.isReady) {
        break
    }
    Start-Sleep -Seconds 1
}

if ($null -eq $status -or
    [string]$status.Diagnostics.checklist.state -ne "Running" -or
    -not [bool]$status.Diagnostics.checklistSync.isReady) {
    $status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory "not-ready.json") -Encoding UTF8
    throw "G3000 checklist synchronization did not reach Ready. Review not-ready.json."
}

$before = $status.Diagnostics.checklist
Write-Host "Synchronization Ready: $($status.Diagnostics.checklistSync.adapterName)" -ForegroundColor Green
Write-Host "Aircraft: $($status.Diagnostics.checklistSync.aircraftTitle)" -ForegroundColor Green
Write-Host "Injecting voice confirmation: $ConfirmationPhrase" -ForegroundColor Cyan

$inject = Invoke-BridgeRequest `
    -Action "synthesize-and-inject" `
    -Text $ConfirmationPhrase `
    -Language $language `
    -TimeoutMs 40000

if (-not $inject.Success) {
    throw "Voice confirmation injection failed: $($inject.Error)"
}

Start-Sleep -Seconds 2
$afterStatus = Invoke-BridgeRequest -Action "status" -TimeoutMs 5000
$after = $afterStatus.Diagnostics.checklist
$localAdvanced = [int]$after.completedItems -eq ([int]$before.completedItems + 1)

Write-Host ""
Write-Host "Now verify the checklist displayed in the G3000." -ForegroundColor Cyan
$answer = Read-Host "Did the active G3000 checklist item advance? (Y/N)"
$g3000Advanced = $answer.Trim().StartsWith("Y", [StringComparison]::OrdinalIgnoreCase)

$report = [ordered]@{
    startedAt = (Get-Date).ToString("o")
    appId = $apps[0].AppID
    appVersion = [string]$ping.AppVersion
    voiceLanguage = $language
    confirmationPhrase = $ConfirmationPhrase
    before = $before
    after = $after
    sync = $afterStatus.Diagnostics.checklistSync
    localChecklistAdvanced = $localAdvanced
    g3000VisuallyAdvanced = $g3000Advanced
    success = ($localAdvanced -and $g3000Advanced -and [bool]$afterStatus.Diagnostics.checklistSync.isReady)
}
$reportPath = Join-Path $OutputDirectory "g3000-guided-result.json"
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ""
if ($report.success) {
    Write-Host "G3000 guided result: PASS" -ForegroundColor Green
    Write-Host "Report: $reportPath" -ForegroundColor DarkGray
    exit 0
}

Write-Host "G3000 guided result: FAIL" -ForegroundColor Red
Write-Host "Report: $reportPath" -ForegroundColor DarkGray
exit 1
