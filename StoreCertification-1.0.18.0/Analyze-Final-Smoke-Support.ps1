param(
    [Parameter(Mandatory=$false)]
    [string]$SupportZip,

    [Parameter(Mandatory=$false)]
    [string]$AfterUtc,

    [string]$QaRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ExpectedVersion = "1.0.18.0"

$HarnessRoot = Split-Path -Parent $PSCommandPath
$Marker = Join-Path $HarnessRoot "LAST-AUTOMATED-PASS-UTC.txt"

if ([string]::IsNullOrWhiteSpace($AfterUtc)) {
    if (-not (Test-Path -LiteralPath $Marker)) {
        throw "No LAST-AUTOMATED-PASS-UTC.txt marker exists. Run automated certification QA first or pass -AfterUtc."
    }
    $AfterUtc = (Get-Content -LiteralPath $Marker -Raw).Trim()
}

$Cutoff = [datetimeoffset]::Parse($AfterUtc).UtcDateTime

if ([string]::IsNullOrWhiteSpace($SupportZip)) {
    $SupportZip = Get-ChildItem (Join-Path $env:USERPROFILE "Downloads") -Filter "SimVoiceCopilot-Support-*.zip" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 |
        ForEach-Object { $_.FullName }
}

if (-not $SupportZip -or -not (Test-Path -LiteralPath $SupportZip)) {
    throw "Support ZIP not found. Use -SupportZip <path>."
}

$runDir = Join-Path $QaRoot ("QA-Runs\Certification\FINAL-SMOKE-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$extract = Join-Path $runDir "support"
Expand-Archive -LiteralPath $SupportZip -DestinationPath $extract -Force

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$metrics = [ordered]@{}

$appJson = Join-Path $extract "diagnostics\application.json"
if (-not (Test-Path -LiteralPath $appJson)) {
    $failures.Add("diagnostics/application.json missing")
} else {
    $app = Get-Content -LiteralPath $appJson -Raw | ConvertFrom-Json
    if ([string]$app.appVersion -ne $ExpectedVersion) {
        $failures.Add("Support package appVersion is '$($app.appVersion)', expected $ExpectedVersion")
    }
    if (-not [bool]$app.packaged) {
        $failures.Add("Support package is not from a packaged/MSIX app")
    }
    $metrics["appVersion"] = [string]$app.appVersion
    $metrics["packaged"] = [bool]$app.packaged
}

$crashJson = Join-Path $extract "diagnostics\windows-crashes.json"
$newCrashes = New-Object System.Collections.ArrayList
if (Test-Path -LiteralPath $crashJson) {
    $crashes = Get-Content -LiteralPath $crashJson -Raw | ConvertFrom-Json
    foreach ($r in @($crashes.records)) {
        try {
            $t = [datetimeoffset]::Parse([string]$r.timeGeneratedLocal).UtcDateTime
            if ($t -ge $Cutoff -and [string]$r.message -match "(?i)SimVoiceCopilot|libvosk|AccessViolationException|c0000005") {
                $null = $newCrashes.Add($r)
            }
        } catch {}
    }
}
$metrics["newCrashRecords"] = $newCrashes.Count
if ($newCrashes.Count -gt 0) {
    $failures.Add("New SimVoice/Vosk Windows crash records exist after automated QA")
    $newCrashes | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDir "new-crashes.json") -Encoding UTF8
}

$counts = @{}
$langCounts = @{}
$fatalLines = New-Object System.Collections.ArrayList

$logFiles = @(Get-ChildItem (Join-Path $extract "logs") -Filter "feedback-*.jsonl" -File -ErrorAction SilentlyContinue)
foreach ($file in $logFiles) {
    foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8) {
        try {
            $o = $line | ConvertFrom-Json
            if (-not $o.timestampUtc) { continue }
            $t = [datetimeoffset]::Parse([string]$o.timestampUtc).UtcDateTime
            if ($t -lt $Cutoff) { continue }

            $cat = [string]$o.category
            if (-not $counts.ContainsKey($cat)) { $counts[$cat] = 0 }
            $counts[$cat]++

            if ($cat -eq "VOSK_HEARD_SUCCESS") {
                $lang = [string]$o.voiceLanguage
                if (-not [string]::IsNullOrWhiteSpace($lang)) {
                    if (-not $langCounts.ContainsKey($lang)) { $langCounts[$lang] = 0 }
                    $langCounts[$lang]++
                }
            }

            if ($cat -match "^(REGRESSION_TEST_FAILED|UNHANDLED_EXCEPTION|APPLICATION_FATAL)$") {
                $null = $fatalLines.Add($line)
            }
        } catch {}
    }
}

function Count([string]$Category) {
    if ($counts.ContainsKey($Category)) { return [int]$counts[$Category] }
    return 0
}

$required = [ordered]@{
    "PARAMETERIZED_REGRESSION_TESTS_PASS" = 1
    "CHECKLIST_REGRESSION_TESTS_PASS" = 1
    "VOSK_HEARD_SUCCESS" = 5
    "PRIORITY_VOICE_INTENT_HANDLED" = 3
    "CHECKLIST_ITEM_AUTO_COMPLETED" = 5
    "EFB_NATIVE_CHECKLIST_READY" = 1
    "SIMULATOR_COMMAND_EXECUTED" = 2
}

foreach ($kv in $required.GetEnumerator()) {
    $actual = Count $kv.Key
    $metrics[$kv.Key] = $actual
    if ($actual -lt [int]$kv.Value) {
        $failures.Add("$($kv.Key): observed $actual, required at least $($kv.Value)")
    }
}

$es = if ($langCounts.ContainsKey("es-ES")) { [int]$langCounts["es-ES"] } else { 0 }
$en = if ($langCounts.ContainsKey("en-US")) { [int]$langCounts["en-US"] } else { 0 }
$metrics["VOSK_es-ES"] = $es
$metrics["VOSK_en-US"] = $en
if ($es -eq 0) { $failures.Add("No Spanish Vosk recognition observed after automated QA") }
if ($en -eq 0) { $failures.Add("No English Vosk recognition observed after automated QA") }

if ($fatalLines.Count -gt 0) {
    $failures.Add("Fatal diagnostic categories were logged after automated QA")
    Set-Content -LiteralPath (Join-Path $runDir "fatal-diagnostics.jsonl") -Value @($fatalLines) -Encoding UTF8
}

$result = [pscustomobject]@{
    Product = "SimVoice Copilot"
    AppVersion = $ExpectedVersion
    SupportZip = $SupportZip
    CutoffUtc = $Cutoff.ToString("o")
    GeneratedUtc = (Get-Date).ToUniversalTime().ToString("o")
    Verdict = if ($failures.Count -eq 0) { "GO STORE" } else { "NO-GO" }
    Metrics = [pscustomobject]$metrics
    Failures = @($failures)
    Warnings = @($warnings)
}
$json = Join-Path $runDir "FINAL-SMOKE-RESULT.json"
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $json -Encoding UTF8

$txt = Join-Path $runDir "FINAL-SMOKE-RESULT.txt"
$lines = @()
$lines += "SimVoice Copilot $ExpectedVersion - FINAL SMOKE ANALYSIS"
$lines += "Cutoff UTC: $($Cutoff.ToString('o'))"
$lines += "Support ZIP: $SupportZip"
$lines += ""
$lines += "VERDICT: $($result.Verdict)"
$lines += ""
$lines += "Metrics:"
foreach ($kv in $metrics.GetEnumerator()) { $lines += ("  {0}: {1}" -f $kv.Key, $kv.Value) }
if ($failures.Count -gt 0) {
    $lines += ""
    $lines += "Failures:"
    foreach ($f in $failures) { $lines += ("  - " + $f) }
}
Set-Content -LiteralPath $txt -Value $lines -Encoding UTF8

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "GO STORE" -ForegroundColor Green
    Write-Host "Final smoke support package is clean and has the required ES/EN/checklist/command evidence." -ForegroundColor Green
    Write-Host "You can upload the exact production MSIX already validated by the automated QA." -ForegroundColor Green
    Write-Host ""
    Write-Host "Result: $txt"
    exit 0
} else {
    Write-Host "NO-GO" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host (" - " + $f) -ForegroundColor Red }
    Write-Host ""
    Write-Host "Result: $txt"
    exit 1
}
