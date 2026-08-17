[CmdletBinding()]
param(
    [string]$QaRoot = "$env:USERPROFILE\Desktop\MSFS_App\SimVoiceCopilot.QA",
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedCatalogSha = "00e8e9937822e09f24c5a72a4b4a89f5a6d1dd71ecf6d878cfabe44eef2fdafb"
$ExpectedRunnerSha = "731fec166acafc17558ef5f423d69f6f37eb55d937923cb73b08fbcfbc779143"
$ExpectedWrapperSha = "5f28f1f0fa4ec132268dadf87438daa7a418e64e8f17d354668ce64eeb0dfda1"
$ExpectedTotalCases = 191

$Suites = @(
    [pscustomobject]@{ Name = "CoreInternalEN";                 Expected = 36; MaxAttempts = 2 },
    [pscustomobject]@{ Name = "NoConnectorInternalEN";         Expected = 30; MaxAttempts = 2 },
    [pscustomobject]@{ Name = "RecognitionStressInternalEN";   Expected = 5;  MaxAttempts = 2 },
    [pscustomobject]@{ Name = "ExtendedRadioInternalEN";       Expected = 12; MaxAttempts = 2 },
    [pscustomobject]@{ Name = "SyntaxVariantsInternalEN";      Expected = 26; MaxAttempts = 2 },
    [pscustomobject]@{ Name = "CoreInternalES";                 Expected = 50; MaxAttempts = 2 },
    [pscustomobject]@{ Name = "RadioRecognitionStressInternalES"; Expected = 32; MaxAttempts = 1 }
)

$wrapperPath = Join-Path $QaRoot "Scripts\Run-QA-Flight-Automated.ps1"
$runnerPath = Join-Path $QaRoot "Scripts\Run-QA-Flight-InternalAudio.ps1"
$catalogPath = Join-Path $QaRoot "FlightFunctional\internal-audio-test-cases.json"
$downloads = Join-Path $env:USERPROFILE "Downloads"

$runStart = Get-Date
$stamp = $runStart.ToString("yyyyMMdd-HHmmss")
$matrixName = "INTERNAL-{0}-ReleaseMatrix-1.0.20.0" -f $stamp
$workRoot = Join-Path $env:TEMP ("SimVoice-" + $matrixName + "-" + [guid]::NewGuid().ToString("N"))
$evidenceRoot = Join-Path $workRoot $matrixName
$finalZip = Join-Path $downloads ($matrixName + ".zip")
$matrixLog = Join-Path $evidenceRoot "release-matrix.log"
$matrixJson = Join-Path $evidenceRoot "release-matrix.json"
$matrixTxt = Join-Path $evidenceRoot "release-matrix.txt"

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-MatrixLog {
    param(
        [string]$Message,
        [string]$Color = "Gray"
    )

    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message
    Add-Content -LiteralPath $matrixLog -Value $line -Encoding UTF8
    Write-Host $Message -ForegroundColor $Color
}

function Get-NewestSuiteZip {
    param(
        [string]$Suite,
        [datetime]$NotBefore
    )

    $pattern = "INTERNAL-*-" + $Suite + ".zip"
    [object[]]$zipMatches = @(
        Get-ChildItem -LiteralPath $downloads -Filter $pattern -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $NotBefore.AddSeconds(-2) } |
        Sort-Object LastWriteTime -Descending
    )

    if ($zipMatches.Count -eq 0) {
        return $null
    }

    return $zipMatches[0]
}

function Read-ZipJsonEntry {
    param(
        [string]$ZipPath,
        [string]$EntrySuffix
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $archive.Entries |
            Where-Object { $_.FullName.Replace("\","/").EndsWith($EntrySuffix,[System.StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1

        if ($null -eq $entry) {
            throw ("ZIP entry not found: " + $EntrySuffix)
        }

        $stream = $entry.Open()
        try {
            $reader = New-Object System.IO.StreamReader($stream,[System.Text.Encoding]::UTF8,$true)
            try {
                $jsonText = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }

        return ($jsonText | ConvertFrom-Json)
    }
    finally {
        $archive.Dispose()
    }
}

function Copy-ZipEvidenceEntry {
    param(
        [string]$ZipPath,
        [string]$EntrySuffix,
        [string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $archive.Entries |
            Where-Object { $_.FullName.Replace("\","/").EndsWith($EntrySuffix,[System.StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1

        if ($null -eq $entry) {
            throw ("ZIP evidence entry not found: " + $EntrySuffix)
        }

        $destDir = Split-Path -Parent $Destination
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null

        $src = $entry.Open()
        try {
            $dst = [System.IO.File]::Open(
                $Destination,
                [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None)
            try {
                $src.CopyTo($dst)
            }
            finally {
                $dst.Dispose()
            }
        }
        finally {
            $src.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }
}

New-Item -ItemType Directory -Path $downloads -Force | Out-Null
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
"SimVoice Copilot 1.0.20.0 Release Candidate Matrix" |
    Set-Content -LiteralPath $matrixLog -Encoding UTF8

$matrixExitCode = 1
$results = @()

try {
    Write-MatrixLog "SimVoice Copilot 1.0.20.0 — FINAL AUTOMATED RELEASE MATRIX" "Cyan"
    Write-MatrixLog "Product baseline expected: HF36-R29" "White"
    Write-MatrixLog ("Suites: {0}" -f (($Suites | ForEach-Object { $_.Name }) -join ", ")) "White"
    Write-MatrixLog ("Expected total cases: {0}" -f $ExpectedTotalCases) "White"
    Write-MatrixLog ""

    foreach ($required in @($wrapperPath,$runnerPath,$catalogPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw ("Required QA file missing: " + $required)
        }
    }

    if ((Get-Sha256 $catalogPath) -ne $ExpectedCatalogSha) {
        throw "QA catalog guard mismatch."
    }
    if ((Get-Sha256 $runnerPath) -ne $ExpectedRunnerSha) {
        throw "QA13-R1 runner guard mismatch."
    }
    if ((Get-Sha256 $wrapperPath) -ne $ExpectedWrapperSha) {
        throw "Automated wrapper guard mismatch."
    }

    Write-MatrixLog "[PASS] exact QA catalog / QA13-R1 runner / wrapper guards." "Green"

    $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json

    foreach ($spec in $Suites) {
        $suiteCases = @($catalog.suites.($spec.Name))
        if ($suiteCases.Count -ne [int]$spec.Expected) {
            throw (
                "Suite catalog count mismatch for " + $spec.Name +
                ": expected " + $spec.Expected +
                ", found " + $suiteCases.Count)
        }
    }

    $catalogTotal = ($Suites | ForEach-Object { [int]$_.Expected } | Measure-Object -Sum).Sum
    if ([int]$catalogTotal -ne $ExpectedTotalCases) {
        throw ("Release matrix total mismatch: " + $catalogTotal)
    }

    Write-MatrixLog "[PASS] matrix catalog counts validated: 191 cases." "Green"

    foreach ($spec in $Suites) {
        Write-MatrixLog ""
        Write-MatrixLog ("============================================================") "DarkCyan"
        Write-MatrixLog (
            "RUN SUITE: {0} | expected={1} | MaxAttempts={2}" -f
            $spec.Name, $spec.Expected, $spec.MaxAttempts) "Cyan"
        Write-MatrixLog ("============================================================") "DarkCyan"

        $suiteStart = Get-Date

        [string[]]$childArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $wrapperPath,
            "-Suite", [string]$spec.Name,
            "-MaxAttempts", [string]$spec.MaxAttempts,
            "-ContinueAfterFailure"
        )

        if ($NoBuild) {
            $childArgs += "-NoBuild"
        }

        & powershell.exe @childArgs
        $childCode = $LASTEXITCODE

        $suiteZip = Get-NewestSuiteZip -Suite ([string]$spec.Name) -NotBefore $suiteStart

        $record = [ordered]@{
            Suite = [string]$spec.Name
            ExpectedCases = [int]$spec.Expected
            RequiredMaxAttempts = [int]$spec.MaxAttempts
            ChildExitCode = [int]$childCode
            ZipPath = ""
            ZipSha256 = ""
            Passed = 0
            Failed = 0
            Success = $false
            ProfileRestored = $false
            RunError = ""
            AttemptsDistribution = @{}
            SpeechRateDistribution = @{}
            EvidenceError = ""
        }

        if ($null -eq $suiteZip) {
            $record.EvidenceError = "Suite ZIP not found in Downloads."
            Write-MatrixLog ("[FAIL] " + $spec.Name + ": result ZIP not found.") "Red"
            $results += [pscustomobject]$record
            continue
        }

        $record.ZipPath = $suiteZip.FullName
        $record.ZipSha256 = Get-Sha256 $suiteZip.FullName

        try {
            $functional = Read-ZipJsonEntry `
                -ZipPath $suiteZip.FullName `
                -EntrySuffix "functional-results.json"

            $wrapper = Read-ZipJsonEntry `
                -ZipPath $suiteZip.FullName `
                -EntrySuffix "qa-automated-wrapper.json"

            $record.Passed = [int]$functional.Passed
            $record.Failed = [int]$functional.Failed
            $record.Success = [bool]$functional.Success
            $record.ProfileRestored = [bool]$wrapper.ProfileRestored
            $record.RunError = [string]$wrapper.RunError

            $attemptDist = [ordered]@{}
            foreach ($group in @($functional.Results | Group-Object Attempts)) {
                $attemptDist[[string]$group.Name] = [int]$group.Count
            }
            $record.AttemptsDistribution = $attemptDist

            $rateDist = [ordered]@{}
            foreach ($group in @($functional.Results | Group-Object SpeechRate)) {
                $rateDist[[string]$group.Name] = [int]$group.Count
            }
            $record.SpeechRateDistribution = $rateDist

            $suiteEvidenceDir = Join-Path $evidenceRoot ("suite-" + $spec.Name)
            Copy-ZipEvidenceEntry `
                -ZipPath $suiteZip.FullName `
                -EntrySuffix "functional-results.json" `
                -Destination (Join-Path $suiteEvidenceDir "functional-results.json")
            Copy-ZipEvidenceEntry `
                -ZipPath $suiteZip.FullName `
                -EntrySuffix "qa-automated-wrapper.json" `
                -Destination (Join-Path $suiteEvidenceDir "qa-automated-wrapper.json")
            Copy-ZipEvidenceEntry `
                -ZipPath $suiteZip.FullName `
                -EntrySuffix "internal-audio-run.log" `
                -Destination (Join-Path $suiteEvidenceDir "internal-audio-run.log")

            $strictStressOk = $true
            if ($spec.Name -eq "RadioRecognitionStressInternalES") {
                $badAttempts = @($functional.Results | Where-Object { [int]$_.Attempts -ne 1 })
                if ($badAttempts.Count -gt 0) {
                    $strictStressOk = $false
                    $record.EvidenceError = (
                        "Strict stress suite contained " +
                        $badAttempts.Count +
                        " result(s) with Attempts != 1.")
                }
            }

            $suitePass =
                ($childCode -eq 0) -and
                $record.Success -and
                ($record.Passed -eq [int]$spec.Expected) -and
                ($record.Failed -eq 0) -and
                $record.ProfileRestored -and
                [string]::IsNullOrWhiteSpace($record.RunError) -and
                $strictStressOk

            if ($suitePass) {
                Write-MatrixLog (
                    "[PASS] {0}: {1}/{1}; profile restored; ZIP SHA={2}" -f
                    $spec.Name, $spec.Expected, $record.ZipSha256) "Green"
            }
            else {
                Write-MatrixLog (
                    "[FAIL] {0}: child={1}, pass={2}, fail={3}, success={4}, profileRestored={5}, error={6}" -f
                    $spec.Name,
                    $childCode,
                    $record.Passed,
                    $record.Failed,
                    $record.Success,
                    $record.ProfileRestored,
                    $record.EvidenceError) "Red"
            }
        }
        catch {
            $record.EvidenceError = $_.Exception.Message
            Write-MatrixLog (
                "[FAIL] " + $spec.Name +
                ": evidence parse failed: " +
                $record.EvidenceError) "Red"
        }

        $results += [pscustomobject]$record
    }

    $passedCases = ($results | Measure-Object Passed -Sum).Sum
    $failedCases = ($results | Measure-Object Failed -Sum).Sum
    $suiteFailures = @(
        $results |
        Where-Object {
            $_.ChildExitCode -ne 0 -or
            -not $_.Success -or
            $_.Passed -ne $_.ExpectedCases -or
            $_.Failed -ne 0 -or
            -not $_.ProfileRestored -or
            -not [string]::IsNullOrWhiteSpace($_.RunError) -or
            -not [string]::IsNullOrWhiteSpace($_.EvidenceError)
        })

    $allPass =
        ($suiteFailures.Count -eq 0) -and
        ([int]$passedCases -eq $ExpectedTotalCases) -and
        ([int]$failedCases -eq 0)

    $matrixObject = [ordered]@{
        SchemaVersion = 1
        Version = "1.0.20.0"
        ProductBaseline = "HF36-R29"
        MatrixRevision = "QA14-R1"
        StartedAtLocal = $runStart.ToString("o")
        FinishedAtLocal = (Get-Date).ToString("o")
        ExpectedTotalCases = $ExpectedTotalCases
        PassedCases = [int]$passedCases
        FailedCases = [int]$failedCases
        SuiteCount = $Suites.Count
        FailedSuiteCount = $suiteFailures.Count
        Success = [bool]$allPass
        Suites = @($results)
    }

    $matrixObject |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $matrixJson -Encoding UTF8

    [string[]]$textLines = @(
        "SimVoice Copilot 1.0.20.0 — FINAL AUTOMATED RELEASE MATRIX",
        ("Product baseline : HF36-R29"),
        ("Matrix revision  : QA14-R1"),
        ("Started          : " + $matrixObject.StartedAtLocal),
        ("Finished         : " + $matrixObject.FinishedAtLocal),
        ("Suites           : " + $matrixObject.SuiteCount),
        ("Cases            : {0}/{1} PASS" -f $matrixObject.PassedCases,$matrixObject.ExpectedTotalCases),
        ("Failed cases     : " + $matrixObject.FailedCases),
        ("Failed suites    : " + $matrixObject.FailedSuiteCount),
        ("SUCCESS          : " + $matrixObject.Success),
        "",
        "Per-suite:"
    )

    foreach ($r in $results) {
        $textLines += (
            "{0,-36} {1,3}/{2,3}  FAIL={3}  Exit={4}  ProfileRestored={5}" -f
            $r.Suite,
            $r.Passed,
            $r.ExpectedCases,
            $r.Failed,
            $r.ChildExitCode,
            $r.ProfileRestored)
    }

    $textLines |
        Set-Content -LiteralPath $matrixTxt -Encoding UTF8

    Write-MatrixLog ""
    if ($allPass) {
        Write-MatrixLog "============================================================" "Green"
        Write-MatrixLog "[PASS] FINAL RELEASE MATRIX: 191 / 191" "Green"
        Write-MatrixLog "============================================================" "Green"
        $matrixExitCode = 0
    }
    else {
        Write-MatrixLog "============================================================" "Red"
        Write-MatrixLog (
            "[FAIL] FINAL RELEASE MATRIX: {0}/{1}, failed suites={2}" -f
            $passedCases,$ExpectedTotalCases,$suiteFailures.Count) "Red"
        Write-MatrixLog "============================================================" "Red"
        $matrixExitCode = 1
    }
}
catch {
    Write-MatrixLog ("[FAIL] release matrix infrastructure: " + $_.Exception.Message) "Red"

    $failureObject = [ordered]@{
        SchemaVersion = 1
        Version = "1.0.20.0"
        ProductBaseline = "HF36-R29"
        MatrixRevision = "QA14-R1"
        StartedAtLocal = $runStart.ToString("o")
        FinishedAtLocal = (Get-Date).ToString("o")
        ExpectedTotalCases = $ExpectedTotalCases
        PassedCases = 0
        FailedCases = 0
        SuiteCount = $Suites.Count
        FailedSuiteCount = $Suites.Count
        Success = $false
        InfrastructureError = $_.Exception.Message
        Suites = @($results)
    }

    $failureObject |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $matrixJson -Encoding UTF8

    $matrixExitCode = 1
}
finally {
    try {
        if (Test-Path -LiteralPath $finalZip) {
            Remove-Item -LiteralPath $finalZip -Force -ErrorAction Stop
        }

        Compress-Archive `
            -LiteralPath $evidenceRoot `
            -DestinationPath $finalZip `
            -CompressionLevel Optimal `
            -Force `
            -ErrorAction Stop

        Write-Host ""
        Write-Host ("[PASS] Release matrix evidence ZIP: " + $finalZip) -ForegroundColor Green
    }
    catch {
        Write-Host ("[FAIL] Release matrix ZIP: " + $_.Exception.Message) -ForegroundColor Red
        $matrixExitCode = 1
    }

    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
if ($matrixExitCode -eq 0) {
    Write-Host "FINAL AUTOMATED RELEASE GATE: PASS" -ForegroundColor Green
    Write-Host "1.0.20.0 is eligible for the final manual smoke / RC2 promotion step." -ForegroundColor Yellow
}
else {
    Write-Host "FINAL AUTOMATED RELEASE GATE: FAIL" -ForegroundColor Red
    Write-Host "Do not create RC2." -ForegroundColor Yellow
}

Write-Host ("Matrix ZIP: " + $finalZip) -ForegroundColor Cyan
exit $matrixExitCode
