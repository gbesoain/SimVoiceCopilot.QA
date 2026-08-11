[CmdletBinding()]
param(
    [ValidateSet("SmokeEN", "CoreEN", "SmokeES")]
    [string]$Suite = "SmokeEN",

    [string]$AppNamePattern = "*SimVoice*",
    [string]$ProcessName = "SimVoiceCopilotApp",
    [string]$SimConnectDll = "",
    [string]$OutputDirectory = "",

    [ValidateRange(10, 180)]
    [int]$ConnectionTimeoutSeconds = 60,

    [ValidateRange(1, 5)]
    [int]$MaxAttempts = 2,

    [switch]$SkipAppLaunch,
    [switch]$NoInteractiveRetry,
    [switch]$CloseAppAtEnd,
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$oracleScript = Join-Path $PSScriptRoot "Run-QA-SimConnect-Oracle.ps1"
$catalogPath = Join-Path $projectRoot "FlightFunctional\test-cases.json"
$runStarted = Get-Date
$runStamp = $runStarted.ToString("yyyyMMdd-HHmmss")

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot ("QA-Runs\FlightFunctional\FLIGHT-{0}-{1}" -f $runStamp, $Suite)
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$oracleRoot = Join-Path $OutputDirectory "oracle"
$feedbackOutput = Join-Path $OutputDirectory "app-feedback-logs"
New-Item -ItemType Directory -Path $oracleRoot -Force | Out-Null
New-Item -ItemType Directory -Path $feedbackOutput -Force | Out-Null
$runLog = Join-Path $OutputDirectory "functional-run.log"

function Write-RunLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff zzz"), $Level, $Message
    Add-Content -LiteralPath $runLog -Value $line -Encoding UTF8
    if ($Level -eq "ERROR") {
        Write-Host $line -ForegroundColor Red
    }
    elseif ($Level -eq "WARN") {
        Write-Host $line -ForegroundColor Yellow
    }
    else {
        Write-Host $line
    }
}

function Get-WindowsPowerShell {
    $candidate = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    $command = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    throw "Windows PowerShell 5.1 was not found."
}

function Get-OracleArguments {
    param(
        [string]$Mode,
        [string]$Directory,
        [string]$Variable = "",
        [string]$Expected = "",
        [double]$Tolerance = 0,
        [int]$TimeoutSeconds = 30,
        [int]$IntervalMs = 250,
        [switch]$UseNoBuild
    )

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $oracleScript,
        "-Mode", $Mode,
        "-OutputDirectory", $Directory,
        "-TimeoutSeconds", $TimeoutSeconds,
        "-IntervalMs", $IntervalMs
    )

    if (-not [string]::IsNullOrWhiteSpace($Variable)) {
        $arguments += @("-Variable", $Variable, "-Expected", $Expected, "-Tolerance", $Tolerance)
    }

    if (-not [string]::IsNullOrWhiteSpace($SimConnectDll)) {
        $arguments += @("-SimConnectDll", $SimConnectDll)
    }

    if ($UseNoBuild) { $arguments += "-NoBuild" }
    return $arguments
}

function Invoke-OracleSync {
    param(
        [string]$Mode,
        [string]$Directory,
        [string]$Variable = "",
        [string]$Expected = "",
        [double]$Tolerance = 0,
        [int]$TimeoutSeconds = 30,
        [int]$IntervalMs = 250,
        [switch]$UseNoBuild
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $powershellExe = Get-WindowsPowerShell
    $arguments = Get-OracleArguments -Mode $Mode -Directory $Directory -Variable $Variable -Expected $Expected -Tolerance $Tolerance -TimeoutSeconds $TimeoutSeconds -IntervalMs $IntervalMs -UseNoBuild:$UseNoBuild

    # Capture the child PowerShell output so it does not become part of this
    # function's return pipeline. Without this, callers receive Object[]
    # (console lines + result object) and .ExitCode is unavailable under
    # Set-StrictMode.
    $consoleOutput = @(& $powershellExe @arguments 2>&1)
    $code = $LASTEXITCODE

    foreach ($line in $consoleOutput) {
        Write-Host ([string]$line)
    }

    if ($null -eq $code) {
        $code = 1
    }

    return [pscustomobject][ordered]@{
        ExitCode = [int]$code
        Directory = $Directory
        ReportPath = Join-Path $Directory "oracle-report.json"
    }
}

function Quote-ProcessArgument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-OracleWait {
    param(
        [string]$Directory,
        [string]$Variable,
        [string]$Expected,
        [double]$Tolerance,
        [int]$TimeoutSeconds
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $powershellExe = Get-WindowsPowerShell
    $arguments = Get-OracleArguments -Mode "Wait" -Directory $Directory -Variable $Variable -Expected $Expected -Tolerance $Tolerance -TimeoutSeconds $TimeoutSeconds -IntervalMs 250 -UseNoBuild
    $argumentString = ($arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "
    $stdout = Join-Path $Directory "oracle-console-out.log"
    $stderr = Join-Path $Directory "oracle-console-error.log"

    $process = Start-Process -FilePath $powershellExe `
        -ArgumentList $argumentString `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -WindowStyle Hidden `
        -PassThru

    return [pscustomobject]@{
        Process = $process
        Directory = $Directory
        ReportPath = Join-Path $Directory "oracle-report.json"
        StandardOutput = $stdout
        StandardError = $stderr
    }
}

function Read-OracleReport {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-SnapshotObservedValue {
    param(
        [object]$Snapshot,
        [string]$Variable
    )

    $propertyMap = @{
        "HeadingBug" = "HeadingBugDegrees"
        "SelectedAltitude" = "SelectedAltitudeFeet"
        "SelectedVerticalSpeed" = "SelectedVerticalSpeedFpm"
        "Transponder" = "TransponderCode"
        "AutopilotMaster" = "AutopilotMaster"
        "HeadingHold" = "HeadingHold"
        "AltitudeHold" = "AltitudeHold"
        "VerticalSpeedHold" = "VerticalSpeedHold"
        "ParkingBrake" = "ParkingBrake"
        "GearHandle" = "GearHandlePosition"
        "FlapsHandleIndex" = "FlapsHandleIndex"
    }

    if (-not $propertyMap.ContainsKey($Variable)) {
        throw "The functional runner does not have a snapshot property mapping for '$Variable'."
    }

    $propertyName = $propertyMap[$Variable]
    $property = $Snapshot.PSObject.Properties[$propertyName]
    if ($null -eq $property) {
        throw "Oracle snapshot property '$propertyName' was not found for variable '$Variable'."
    }

    return $property.Value
}

function Get-NumericDifference {
    param(
        [string]$Variable,
        [double]$Observed,
        [double]$Expected
    )

    if ($Variable -eq "HeadingBug") {
        $a = (($Observed % 360) + 360) % 360
        $b = (($Expected % 360) + 360) % 360
        $difference = [Math]::Abs($a - $b)
        return [Math]::Min($difference, 360 - $difference)
    }

    return [Math]::Abs($Observed - $Expected)
}

function Select-TestVariant {
    param(
        [object]$Test,
        [object]$Observed
    )

    foreach ($variant in @($Test.variants)) {
        $expected = [double]::Parse([string]$variant.expected, [Globalization.CultureInfo]::InvariantCulture)
        $observedNumber = [Convert]::ToDouble($Observed, [Globalization.CultureInfo]::InvariantCulture)
        $difference = Get-NumericDifference -Variable ([string]$Test.variable) -Observed $observedNumber -Expected $expected
        if ($difference -gt ([double]$Test.tolerance)) {
            return $variant
        }
    }

    return $null
}

function Find-SimVoiceApp {
    $apps = @(Get-StartApps | Where-Object { $_.Name -like $AppNamePattern })
    if ($apps.Count -eq 0) {
        throw "No installed Start app matched '$AppNamePattern'."
    }
    if ($apps.Count -gt 1) {
        $names = ($apps | ForEach-Object { "{0} [{1}]" -f $_.Name, $_.AppID }) -join "; "
        throw "More than one installed app matched '$AppNamePattern': $names. Use an exact -AppNamePattern."
    }
    return $apps[0]
}

function Wait-SimVoiceProcess {
    param([int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $process) {
            $process.Refresh()
            if ($process.MainWindowHandle -ne 0) { return $process }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    throw "The process '$ProcessName' did not expose a main window within $TimeoutSeconds seconds."
}

function Get-UiElementName {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$AutomationId
    )

    try {
        $Process.Refresh()
        if ($Process.MainWindowHandle -ne 0) {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
            if ($null -ne $root) {
                $condition = [System.Windows.Automation.PropertyCondition]::new(
                    [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
                    $AutomationId)
                $element = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
                if ($null -ne $element -and -not [string]::IsNullOrWhiteSpace([string]$element.Current.Name)) {
                    return [string]$element.Current.Name
                }
            }
        }

        # Packaged WinForms applications can expose a valid main HWND while UI Automation
        # does not return descendants from AutomationElement.FromHandle(). Search the
        # desktop tree by process id as a second UIA strategy.
        $processCondition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
            $Process.Id)
        $automationCondition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            $AutomationId)
        $combined = [System.Windows.Automation.AndCondition]::new($processCondition, $automationCondition)
        $desktopElement = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            $combined)
        if ($null -ne $desktopElement) {
            return [string]$desktopElement.Current.Name
        }
    }
    catch {
        return ""
    }

    return ""
}

function Get-NativeSimVoiceStatus {
    param([System.Diagnostics.Process]$Process)

    try {
        $Process.Refresh()
        if ($Process.MainWindowHandle -eq 0) { return "" }
        $texts = [SimVoiceQa.NativeWindowTextReader]::GetDescendantTexts($Process.MainWindowHandle)
        foreach ($text in $texts) {
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            if ($text -match '(?i)flight\s+simulator|simulador') {
                return [string]$text
            }
        }
    }
    catch {
        return ""
    }

    return ""
}

function Get-SimVoiceStatus {
    param([System.Diagnostics.Process]$Process)

    $uiaStatus = Get-UiElementName -Process $Process -AutomationId "lblSimConnectStatus"
    if (-not [string]::IsNullOrWhiteSpace($uiaStatus)) {
        return [pscustomobject]@{ Text = $uiaStatus; Source = "UIAutomation" }
    }

    $nativeStatus = Get-NativeSimVoiceStatus -Process $Process
    if (-not [string]::IsNullOrWhiteSpace($nativeStatus)) {
        return [pscustomobject]@{ Text = $nativeStatus; Source = "Win32" }
    }

    return [pscustomobject]@{ Text = ""; Source = "Unavailable" }
}

function Wait-SimVoiceConnected {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds
    )

    $started = Get-Date
    $deadline = $started.AddSeconds($TimeoutSeconds)
    $unavailableFallbackAt = $started.AddSeconds([Math]::Min(12, $TimeoutSeconds))
    $lastStatus = ""
    $lastSource = "Unavailable"
    $everReadStatus = $false

    do {
        $Process.Refresh()
        if ($Process.HasExited) { throw "SimVoice Copilot exited while waiting for SimConnect." }

        $status = Get-SimVoiceStatus -Process $Process
        $lastStatus = [string]$status.Text
        $lastSource = [string]$status.Source
        if (-not [string]::IsNullOrWhiteSpace($lastStatus)) {
            $everReadStatus = $true
            $isDisconnected = $lastStatus -match '(?i)not\s+connected|no\s+conectado|desconectado|connecting|conectando'
            $isConnected = $lastStatus -match '(?i)(flight\s+simulator|simulador).*(:|-)\s*(connected|conectado)(?:\s+to|\b)'
            if ($isConnected -and -not $isDisconnected) {
                return [pscustomobject]@{
                    Text = $lastStatus
                    Source = $lastSource
                    Verified = $true
                }
            }
        }
        elseif (-not $everReadStatus -and (Get-Date) -ge $unavailableFallbackAt) {
            # UI text is useful evidence but not the oracle of truth. Some MSIX/WinForms
            # combinations do not expose label text to an external process. Continue and
            # let the independent SimConnect Oracle plus the actual command result prove
            # end-to-end connectivity instead of producing a false infrastructure FAIL.
            return [pscustomobject]@{
                Text = "Status text unavailable; connectivity will be validated by the independent Oracle and command outcomes."
                Source = "OracleFallback"
                Verified = $false
            }
        }

        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)

    if (-not $everReadStatus) {
        return [pscustomobject]@{
            Text = "Status text unavailable; connectivity will be validated by the independent Oracle and command outcomes."
            Source = "OracleFallback"
            Verified = $false
        }
    }

    throw "SimVoice Copilot did not report a connected simulator within $TimeoutSeconds seconds. Last status from ${lastSource}: '$lastStatus'."
}

function Copy-FeedbackLogs {
    param([datetime]$Since)
    $logRoot = Join-Path $env:LOCALAPPDATA "SimVoiceCopilot\Logs"
    if (-not (Test-Path -LiteralPath $logRoot)) { return }

    Get-ChildItem -LiteralPath $logRoot -Filter "feedback-*.jsonl" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since.AddMinutes(-1) } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $feedbackOutput $_.Name) -Force
        }
}

function HtmlEncode {
    param([object]$Value)
    return [System.Net.WebUtility]::HtmlEncode([Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture))
}

function Write-FunctionalReports {
    param(
        [object[]]$Results,
        [bool]$Success,
        [string]$AppDisplayName,
        [string]$AppId,
        [string]$ConnectedStatus
    )

    $finished = Get-Date
    $report = [ordered]@{
        RunId = "FLIGHT-$runStamp-$Suite"
        Suite = $Suite
        StartedAtLocal = $runStarted.ToString("o")
        FinishedAtLocal = $finished.ToString("o")
        MachineName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        AppDisplayName = $AppDisplayName
        AppId = $AppId
        ProcessName = $ProcessName
        SimVoiceConnectedStatus = $ConnectedStatus
        Success = $Success
        Passed = @($Results | Where-Object { $_.Passed }).Count
        Failed = @($Results | Where-Object { -not $_.Passed }).Count
        Results = $Results
    }

    $jsonPath = Join-Path $OutputDirectory "functional-results.json"
    $csvPath = Join-Path $OutputDirectory "command-results.csv"
    $htmlPath = Join-Path $OutputDirectory "functional-report.html"

    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $Results | Select-Object TestId, Suite, Language, Phrase, Variable, Before, Expected, Observed, Tolerance, Attempts, LatencySeconds, Passed, Message, OracleDirectory |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    $resultClass = if ($Success) { "pass" } else { "fail" }
    $resultText = if ($Success) { "PASS" } else { "FAIL" }
    $rows = New-Object Text.StringBuilder
    foreach ($item in $Results) {
        $rowClass = if ($item.Passed) { "pass" } else { "fail" }
        [void]$rows.Append("<tr><td>").Append((HtmlEncode $item.TestId)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Phrase)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Variable)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Before)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Expected)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Observed)).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.LatencySeconds)).Append("</td><td class='").Append($rowClass).Append("'>")
        $itemResultText = if ($item.Passed) { "PASS" } else { "FAIL" }
        [void]$rows.Append($itemResultText).Append("</td><td>")
        [void]$rows.Append((HtmlEncode $item.Message)).Append("</td></tr>")
    }

    $html = @"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>SimVoice Copilot Flight Functional QA</title>
<style>
body{font-family:Segoe UI,Arial;margin:28px;color:#202124}h1{margin-bottom:4px}.pass{color:#187a2f;font-weight:700}.fail{color:#b42318;font-weight:700}table{border-collapse:collapse;width:100%;margin-top:18px}th,td{border:1px solid #d0d5dd;padding:7px 9px;text-align:left;vertical-align:top}th{background:#f2f4f7}code{background:#f2f4f7;padding:2px 4px}.meta{line-height:1.55}
</style>
</head>
<body>
<h1>SimVoice Copilot — Guided Flight Functional QA</h1>
<p class="$resultClass">$resultText</p>
<p class="meta">Suite: <code>$(HtmlEncode $Suite)</code><br>
App: <code>$(HtmlEncode $AppDisplayName)</code><br>
SimConnect status: <code>$(HtmlEncode $ConnectedStatus)</code><br>
Passed: $(@($Results | Where-Object { $_.Passed }).Count) &nbsp; Failed: $(@($Results | Where-Object { -not $_.Passed }).Count)</p>
<table>
<thead><tr><th>Test</th><th>Phrase</th><th>Variable</th><th>Before</th><th>Expected</th><th>Observed</th><th>Latency s</th><th>Result</th><th>Message</th></tr></thead>
<tbody>$($rows.ToString())</tbody>
</table>
</body>
</html>
"@
    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

    return [pscustomobject]@{
        Json = $jsonPath
        Csv = $csvPath
        Html = $htmlPath
    }
}

if (-not (Test-Path -LiteralPath $oracleScript)) {
    throw "Oracle launcher not found: $oracleScript"
}
if (-not (Test-Path -LiteralPath $catalogPath)) {
    throw "Functional test catalog not found: $catalogPath"
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

if (-not ("SimVoiceQa.NativeWindowTextReader" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace SimVoiceQa
{
    public static class NativeWindowTextReader
    {
        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int GetWindowTextLength(IntPtr hWnd);

        public static string[] GetDescendantTexts(IntPtr parent)
        {
            var values = new List<string>();
            if (parent == IntPtr.Zero)
                return values.ToArray();

            EnumChildWindows(parent, delegate(IntPtr hWnd, IntPtr lParam)
            {
                int length = GetWindowTextLength(hWnd);
                if (length > 0)
                {
                    var builder = new StringBuilder(length + 1);
                    GetWindowText(hWnd, builder, builder.Capacity);
                    string value = builder.ToString().Trim();
                    if (value.Length > 0)
                        values.Add(value);
                }
                return true;
            }, IntPtr.Zero);

            return values.ToArray();
        }
    }
}
"@ -Language CSharp
}

Write-RunLog "SimVoice Copilot QA Phase 2.2.3 — Guided End-to-End Flight Functional QA"
Write-RunLog ("Suite: {0}" -f $Suite)
Write-RunLog ("Output: {0}" -f $OutputDirectory)

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$suiteProperty = $catalog.suites.PSObject.Properties[$Suite]
if ($null -eq $suiteProperty) {
    throw "Suite '$Suite' was not found in $catalogPath."
}
$tests = @($suiteProperty.Value)
if ($tests.Count -eq 0) { throw "Suite '$Suite' contains no tests." }

$app = Find-SimVoiceApp
Write-RunLog ("Installed MSIX: {0} [{1}]" -f $app.Name, $app.AppID)

$simVoiceProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $simVoiceProcess -and -not $SkipAppLaunch) {
    Write-RunLog "Launching installed MSIX package."
    Start-Process "explorer.exe" ("shell:AppsFolder\{0}" -f $app.AppID)
}

$simVoiceProcess = Wait-SimVoiceProcess -TimeoutSeconds $ConnectionTimeoutSeconds
Write-RunLog ("SimVoice process ready: PID={0}, HWND=0x{1:X}" -f $simVoiceProcess.Id, $simVoiceProcess.MainWindowHandle.ToInt64())

# Establish the simulator truth first. UI Automation status text is secondary evidence
# and must never block a valid flight-functional run when the MSIX is visibly running.
$probeDirectory = Join-Path $oracleRoot "00-preflight-probe"
$probe = Invoke-OracleSync -Mode "Probe" -Directory $probeDirectory -TimeoutSeconds 30 -IntervalMs 500 -UseNoBuild:$NoBuild
if ($probe.ExitCode -ne 0) {
    throw "Independent SimConnect Oracle preflight failed. Review: $probeDirectory"
}
Write-RunLog "Independent Oracle preflight: PASS"

$connectedStatusResult = Wait-SimVoiceConnected -Process $simVoiceProcess -TimeoutSeconds $ConnectionTimeoutSeconds
$connectedStatus = [string]$connectedStatusResult.Text
if ([bool]$connectedStatusResult.Verified) {
    Write-RunLog ("SimVoice connected status ({0}): {1}" -f $connectedStatusResult.Source, $connectedStatus)
}
else {
    Write-RunLog ("SimVoice status text could not be read externally ({0}). Continuing because Oracle preflight passed; command outcomes remain authoritative." -f $connectedStatusResult.Source) "WARN"
}

$suiteLanguage = [string]$tests[0].language
Write-Host ""
Write-Host "FLIGHT FUNCTIONAL PRECHECK" -ForegroundColor Cyan
Write-Host ("  Voice profile/language : {0}" -f $suiteLanguage)
Write-Host "  Microphone             : selected and working in SimVoice Copilot"
Write-Host "  Listening mode         : continuous, or use the configured Push-to-Talk key after each beep"
Write-Host "  Simulator              : active flight; do not operate the tested controls manually"
Write-Host ""
[void](Read-Host "Confirm the setup above and press ENTER to begin")

$results = New-Object 'System.Collections.Generic.List[object]' 
$aborted = $false
$testNumber = 0

foreach ($test in $tests) {
    if ($aborted) { break }
    $testNumber++
    $testId = [string]$test.id
    $safeTestId = $testId -replace '[^A-Za-z0-9_.-]', '_'
    $testRoot = Join-Path $oracleRoot ("{0:00}-{1}" -f $testNumber, $safeTestId)
    $beforeDirectory = Join-Path $testRoot "before"

    Write-Host ""
    Write-Host ("[{0}/{1}] {2}" -f $testNumber, $tests.Count, $testId) -ForegroundColor Cyan

    $beforeRun = Invoke-OracleSync -Mode "Snapshot" -Directory $beforeDirectory -TimeoutSeconds 20 -IntervalMs 500 -UseNoBuild
    $beforeReport = Read-OracleReport -Path $beforeRun.ReportPath
    if ($beforeRun.ExitCode -ne 0 -or $null -eq $beforeReport -or @($beforeReport.Snapshots).Count -eq 0) {
        $results.Add([pscustomobject][ordered]@{
            TestId = $testId; Suite = $Suite; Language = [string]$test.language; Phrase = "";
            Variable = [string]$test.variable; Before = ""; Expected = ""; Observed = "";
            Tolerance = [double]$test.tolerance; Attempts = 0; LatencySeconds = 0; Passed = $false;
            Message = "Could not capture the pre-command Oracle snapshot."; OracleDirectory = $testRoot
        })
        Write-RunLog ("{0}: FAIL - pre-command snapshot unavailable" -f $testId) "ERROR"
        continue
    }

    $beforeSnapshot = @($beforeReport.Snapshots)[-1]
    $beforeObserved = Get-SnapshotObservedValue -Snapshot $beforeSnapshot -Variable ([string]$test.variable)
    $variant = Select-TestVariant -Test $test -Observed $beforeObserved

    if ($null -eq $variant) {
        $results.Add([pscustomobject][ordered]@{
            TestId = $testId; Suite = $Suite; Language = [string]$test.language; Phrase = "";
            Variable = [string]$test.variable; Before = [string]$beforeObserved; Expected = ""; Observed = [string]$beforeObserved;
            Tolerance = [double]$test.tolerance; Attempts = 0; LatencySeconds = 0; Passed = $false;
            Message = "All configured target variants already matched the current simulator value; no valid precondition was available."; OracleDirectory = $testRoot
        })
        Write-RunLog ("{0}: FAIL - no target differs from current value {1}" -f $testId, $beforeObserved) "ERROR"
        continue
    }

    $phrase = [string]$variant.phrase
    $expected = [string]$variant.expected
    $attempt = 0
    $passed = $false
    $observed = ""
    $message = ""
    $latency = 0.0
    $lastAttemptDirectory = ""

    while (-not $passed -and $attempt -lt $MaxAttempts) {
        $attempt++

        if ($attempt -gt 1) {
            $retryBeforeDirectory = Join-Path $testRoot ("before-retry-{0}" -f $attempt)
            $retryBeforeRun = Invoke-OracleSync -Mode "Snapshot" -Directory $retryBeforeDirectory -TimeoutSeconds 20 -IntervalMs 500 -UseNoBuild
            $retryBeforeReport = Read-OracleReport -Path $retryBeforeRun.ReportPath
            if ($retryBeforeRun.ExitCode -eq 0 -and $null -ne $retryBeforeReport -and @($retryBeforeReport.Snapshots).Count -gt 0) {
                $retrySnapshot = @($retryBeforeReport.Snapshots)[-1]
                $beforeObserved = Get-SnapshotObservedValue -Snapshot $retrySnapshot -Variable ([string]$test.variable)
                $retryVariant = Select-TestVariant -Test $test -Observed $beforeObserved
                if ($null -ne $retryVariant) {
                    $variant = $retryVariant
                    $phrase = [string]$variant.phrase
                    $expected = [string]$variant.expected
                }
            }
        }

        $attemptDirectory = Join-Path $testRoot ("attempt-{0}" -f $attempt)
        $lastAttemptDirectory = $attemptDirectory

        Write-Host ("Variable : {0}" -f $test.variable) -ForegroundColor DarkGray
        Write-Host ("Before   : {0}" -f $beforeObserved) -ForegroundColor DarkGray
        Write-Host ("Expected : {0} (tolerance {1})" -f $expected, $test.tolerance) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Prepare to say exactly:" -ForegroundColor Yellow
        Write-Host ("  {0}" -f $phrase) -ForegroundColor White
        Write-Host ""
        [void](Read-Host "Press ENTER when ready")

        $wait = Start-OracleWait -Directory $attemptDirectory -Variable ([string]$test.variable) -Expected $expected -Tolerance ([double]$test.tolerance) -TimeoutSeconds ([int]$test.timeoutSeconds)
        Start-Sleep -Milliseconds 1500
        try { [Console]::Beep(900, 180) } catch { }
        Write-Host "SAY THE COMMAND NOW" -ForegroundColor Green
        Write-Host "If Push-to-Talk is enabled, hold the configured key while speaking." -ForegroundColor DarkGray
        $spokenAt = Get-Date

        $hardDeadline = (Get-Date).AddSeconds(([int]$test.timeoutSeconds + 20))
        while (-not $wait.Process.HasExited -and (Get-Date) -lt $hardDeadline) {
            Start-Sleep -Milliseconds 350
            $wait.Process.Refresh()
            if ($simVoiceProcess.HasExited) {
                try { Stop-Process -Id $wait.Process.Id -Force -ErrorAction SilentlyContinue } catch { }
                break
            }
        }

        if (-not $wait.Process.HasExited) {
            try { Stop-Process -Id $wait.Process.Id -Force -ErrorAction SilentlyContinue } catch { }
            $message = "Oracle wait subprocess exceeded its hard timeout."
            $passed = $false
        }
        elseif ($simVoiceProcess.HasExited) {
            $message = "SimVoice Copilot exited during the command test."
            $passed = $false
        }
        else {
            $wait.Process.WaitForExit()
            $latency = [Math]::Round(((Get-Date) - $spokenAt).TotalSeconds, 3)
            $attemptReport = Read-OracleReport -Path $wait.ReportPath
            if ($null -ne $attemptReport -and $null -ne $attemptReport.Assertion) {
                $observed = [string]$attemptReport.Assertion.Observed
                $message = [string]$attemptReport.Message
                $passed = [bool]$attemptReport.Success
            }
            else {
                $message = "Oracle did not generate a valid assertion report."
                $passed = $false
            }
        }

        if ($passed) {
            Write-Host ("PASS: observed {0} in {1} seconds" -f $observed, $latency) -ForegroundColor Green
            Write-RunLog ("{0}: PASS phrase='{1}' before={2} expected={3} observed={4} latency={5}s attempt={6}" -f $testId, $phrase, $beforeObserved, $expected, $observed, $latency, $attempt)
        }
        else {
            Write-Host ("FAIL: {0}" -f $message) -ForegroundColor Red
            Write-RunLog ("{0}: FAIL phrase='{1}' before={2} expected={3} observed={4} attempt={5}: {6}" -f $testId, $phrase, $beforeObserved, $expected, $observed, $attempt, $message) "ERROR"

            if (-not $NoInteractiveRetry -and $attempt -lt $MaxAttempts) {
                $choice = Read-Host "Enter R to retry, S to skip this test, or A to abort the suite"
                if ($choice -match '^(?i)A$') {
                    $aborted = $true
                    break
                }
                if ($choice -match '^(?i)S$') {
                    break
                }
            }
        }
    }

    $results.Add([pscustomobject][ordered]@{
        TestId = $testId
        Suite = $Suite
        Language = [string]$test.language
        Phrase = $phrase
        Variable = [string]$test.variable
        Before = [string]$beforeObserved
        Expected = $expected
        Observed = $observed
        Tolerance = [double]$test.tolerance
        Attempts = $attempt
        LatencySeconds = $latency
        Passed = $passed
        Message = $message
        OracleDirectory = $lastAttemptDirectory
    })
}

Copy-FeedbackLogs -Since $runStarted

$overallSuccess = (-not $aborted) -and ($results.Count -eq $tests.Count) -and (@($results | Where-Object { -not $_.Passed }).Count -eq 0)
$resultArray = @($results | ForEach-Object { $_ })
$reports = Write-FunctionalReports -Results $resultArray -Success $overallSuccess -AppDisplayName ([string]$app.Name) -AppId ([string]$app.AppID) -ConnectedStatus $connectedStatus

if ($CloseAppAtEnd -and $null -ne $simVoiceProcess -and -not $simVoiceProcess.HasExited) {
    Write-RunLog "Closing SimVoice Copilot because -CloseAppAtEnd was specified."
    try {
        $simVoiceProcess.CloseMainWindow() | Out-Null
        if (-not $simVoiceProcess.WaitForExit(10000)) {
            Stop-Process -Id $simVoiceProcess.Id -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-RunLog ("Could not close SimVoice Copilot cleanly: {0}" -f $_.Exception.Message) "WARN"
    }
}

Write-Host ""
$overallText = if ($overallSuccess) { "FLIGHT FUNCTIONAL RESULT: PASS" } else { "FLIGHT FUNCTIONAL RESULT: FAIL" }
$overallColor = if ($overallSuccess) { "Green" } else { "Red" }
Write-Host $overallText -ForegroundColor $overallColor
Write-Host ("Results: {0}" -f $OutputDirectory)
Write-Host ("HTML   : {0}" -f $reports.Html)
Write-Host ("JSON   : {0}" -f $reports.Json)
Write-Host ("CSV    : {0}" -f $reports.Csv)

if ($overallSuccess) { exit 0 }
exit 1
