[CmdletBinding()]
param(
    [string]$QaRoot = "$env:USERPROFILE\Desktop\MSFS_App\SimVoiceCopilot.QA",
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedCatalogSha = "00e8e9937822e09f24c5a72a4b4a89f5a6d1dd71ecf6d878cfabe44eef2fdafb"
$ExpectedRunnerSha = "7b3464df43c11d181beb8a7adc21febce568db0b6cca42ce0f725d7e7a4fdc6c"
$ExpectedWrapperSha = "122d75b651fc2e7aeb58281eaa3520be7c554ec4228db9ff19366aafc92967b1"
$ExpectedTotalCases = 191

$Suites = @(
    [pscustomobject]@{ Name = "CoreInternalEN";                    Language = "en-US"; Expected = 36; MaxAttempts = 2 },
    [pscustomobject]@{ Name = "NoConnectorInternalEN";            Language = "en-US"; Expected = 30; MaxAttempts = 2 },
    [pscustomobject]@{ Name = "RecognitionStressInternalEN";      Language = "en-US"; Expected = 5;  MaxAttempts = 2 },
    [pscustomobject]@{ Name = "ExtendedRadioInternalEN";          Language = "en-US"; Expected = 12; MaxAttempts = 2 },
    [pscustomobject]@{ Name = "SyntaxVariantsInternalEN";         Language = "en-US"; Expected = 26; MaxAttempts = 2 },
    [pscustomobject]@{ Name = "CoreInternalES";                    Language = "es-ES"; Expected = 50; MaxAttempts = 2 },
    [pscustomobject]@{ Name = "RadioRecognitionStressInternalES"; Language = "es-ES"; Expected = 32; MaxAttempts = 1 }
)

$wrapperPath = Join-Path $QaRoot "Scripts\Run-QA-Flight-Automated.ps1"
$runnerPath = Join-Path $QaRoot "Scripts\Run-QA-Flight-InternalAudio.ps1"
$catalogPath = Join-Path $QaRoot "FlightFunctional\internal-audio-test-cases.json"
$uiSettingsPath = Join-Path $env:LOCALAPPDATA "SimVoiceCopilot\ui_settings.json"
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

$script:originalSettingsExisted = $false
$script:originalSettingsBytes = $null
$script:settingsRestored = $false
$script:infrastructureError = ""
$script:results = @()

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

function Stop-SimVoiceProcess {
    foreach ($proc in @(Get-Process -Name "SimVoiceCopilotApp" -ErrorAction SilentlyContinue)) {
        try {
            $proc.Refresh()
            if (-not $proc.HasExited) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                [void]$proc.WaitForExit(5000)
            }
        }
        catch { }
        try { $proc.Dispose() } catch { }
    }
}

function Save-OriginalUiSettings {
    $script:originalSettingsExisted = Test-Path -LiteralPath $uiSettingsPath -PathType Leaf
    if ($script:originalSettingsExisted) {
        $script:originalSettingsBytes = [System.IO.File]::ReadAllBytes($uiSettingsPath)
    }
}

function Set-MatrixSuiteLanguage {
    param([string]$Language)

    Stop-SimVoiceProcess

    $settingsDir = Split-Path -Parent $uiSettingsPath
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

    $settingsObject = $null
    if (Test-Path -LiteralPath $uiSettingsPath -PathType Leaf) {
        try {
            $rawSettings = [System.IO.File]::ReadAllText($uiSettingsPath)
            if (-not [string]::IsNullOrWhiteSpace($rawSettings)) {
                $settingsObject = $rawSettings | ConvertFrom-Json
            }
        }
        catch {
            throw ("Cannot parse ui_settings.json before setting QA suite language: " + $_.Exception.Message)
        }
    }

    if ($null -eq $settingsObject) {
        $settingsObject = [pscustomobject]@{}
    }

    foreach ($propertyName in @("ApplicationLanguage","VoiceRecognitionLanguage")) {
        $property = $settingsObject.PSObject.Properties[$propertyName]
        if ($null -eq $property) {
            $settingsObject | Add-Member -NotePropertyName $propertyName -NotePropertyValue $Language
        }
        else {
            $property.Value = $Language
        }
    }

    $tempJson = $settingsObject | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText(
        $uiSettingsPath,
        $tempJson,
        [System.Text.UTF8Encoding]::new($false))

    # QA14-R5 hard gate: a suite is never allowed to launch with an English
    # recognizer over a Spanish UI (or the inverse). Both values must match the
    # suite language before the app is launched by the child wrapper.
    $verify = [System.IO.File]::ReadAllText($uiSettingsPath) | ConvertFrom-Json
    if (-not [string]::Equals(
            [string]$verify.ApplicationLanguage,
            $Language,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals(
            [string]$verify.VoiceRecognitionLanguage,
            $Language,
            [System.StringComparison]::OrdinalIgnoreCase))
    {
        throw (
            "QA14-R5 language isolation gate failed. ApplicationLanguage='{0}', VoiceRecognitionLanguage='{1}', expected='{2}'." -f
            [string]$verify.ApplicationLanguage,
            [string]$verify.VoiceRecognitionLanguage,
            $Language)
    }

    Write-MatrixLog (
        "[QA14-R5] ApplicationLanguage + VoiceRecognitionLanguage temporarily set to {0}." -f
        $Language) "Yellow"
}

function Restore-OriginalUiSettings {
    Stop-SimVoiceProcess

    if ($script:settingsRestored) {
        return
    }

    if ($script:originalSettingsExisted) {
        [System.IO.File]::WriteAllBytes($uiSettingsPath, $script:originalSettingsBytes)
    }
    else {
        Remove-Item -LiteralPath $uiSettingsPath -Force -ErrorAction SilentlyContinue
    }

    $script:settingsRestored = $true
    Write-MatrixLog "[PASS] original ui_settings.json restored byte-for-byte." "Green"
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

function Find-ZipEntry {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$EntrySuffix
    )

    return $Archive.Entries |
        Where-Object {
            $_.FullName.Replace("\","/").EndsWith(
                $EntrySuffix,
                [System.StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1
}

function Read-ZipJsonEntry {
    param(
        [string]$ZipPath,
        [string]$EntrySuffix
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = Find-ZipEntry -Archive $archive -EntrySuffix $EntrySuffix
        if ($null -eq $entry) {
            throw ("ZIP entry not found: " + $EntrySuffix)
        }

        $stream = $entry.Open()
        try {
            $reader = New-Object System.IO.StreamReader($stream,[System.Text.Encoding]::UTF8,$true)
            try {
                return ($reader.ReadToEnd() | ConvertFrom-Json)
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Try-Copy-ZipEvidenceEntry {
    param(
        [string]$ZipPath,
        [string]$EntrySuffix,
        [string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = Find-ZipEntry -Archive $archive -EntrySuffix $EntrySuffix
        if ($null -eq $entry) {
            return $false
        }

        New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
        $srcStream = $entry.Open()
        try {
            $dstStream = [System.IO.File]::Open(
                $Destination,
                [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None)
            try {
                $srcStream.CopyTo($dstStream)
            }
            finally {
                $dstStream.Dispose()
            }
        }
        finally {
            $srcStream.Dispose()
        }

        return $true
    }
    finally {
        $archive.Dispose()
    }
}

New-Item -ItemType Directory -Path $downloads -Force | Out-Null
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
"SimVoice Copilot 1.0.20.0 Release Candidate Matrix QA14-R5" |
    Set-Content -LiteralPath $matrixLog -Encoding UTF8

$matrixExitCode = 1

try {
    Write-MatrixLog "SimVoice Copilot 1.0.20.0 — FINAL AUTOMATED RELEASE MATRIX QA14-R5" "Cyan"
    Write-MatrixLog "Product baseline expected: HF36-R47" "White"
    Write-MatrixLog "Matrix is bilingual/self-contained: ApplicationLanguage + VoiceRecognitionLanguage are isolated together EN -> ES." "White"
    Write-MatrixLog ("Expected total cases: {0}" -f $ExpectedTotalCases) "White"
    Write-MatrixLog ""

    foreach ($requiredPath in @($wrapperPath,$runnerPath,$catalogPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw ("Required QA file missing: " + $requiredPath)
        }
    }

    if ((Get-Sha256 $catalogPath) -ne $ExpectedCatalogSha) {
        throw "QA catalog guard mismatch."
    }
    if ((Get-Sha256 $runnerPath) -ne $ExpectedRunnerSha) {
        throw "QA14-R5 runner guard mismatch."
    }
    if ((Get-Sha256 $wrapperPath) -ne $ExpectedWrapperSha) {
        throw "Automated wrapper guard mismatch."
    }

    Write-MatrixLog "[PASS] exact QA catalog / QA14-R5 runner / wrapper guards." "Green"

    $catalogObject = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($spec in $Suites) {
        $suiteCases = @($catalogObject.suites.($spec.Name))
        if ($suiteCases.Count -ne [int]$spec.Expected) {
            throw (
                "Suite catalog count mismatch for " + $spec.Name +
                ": expected " + $spec.Expected +
                ", found " + $suiteCases.Count)
        }
    }

    Write-MatrixLog "[PASS] matrix catalog counts validated: 191 cases." "Green"

    Save-OriginalUiSettings

    $globalCaseOffset = 0
    foreach ($spec in $Suites) {
        Write-MatrixLog ""
        Write-MatrixLog "============================================================" "DarkCyan"
        $globalStart = $globalCaseOffset + 1
        $globalEnd = $globalCaseOffset + [int]$spec.Expected
        Write-MatrixLog (
            "RUN SUITE: {0} | language={1} | expected={2} | MaxAttempts={3} | TOTAL range={4}-{5}/{6}" -f
            $spec.Name,$spec.Language,$spec.Expected,$spec.MaxAttempts,$globalStart,$globalEnd,$ExpectedTotalCases) "Cyan"
        Write-MatrixLog "============================================================" "DarkCyan"

        Set-MatrixSuiteLanguage -Language ([string]$spec.Language)

        $suiteStart = Get-Date
        [string[]]$childArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $wrapperPath,
            "-Suite", [string]$spec.Name,
            "-MaxAttempts", [string]$spec.MaxAttempts,
            "-GlobalCaseOffset", [string]$globalCaseOffset,
            "-GlobalCaseTotal", [string]$ExpectedTotalCases,
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
            Language = [string]$spec.Language
            ApplicationLanguage = [string]$spec.Language
            VoiceRecognitionLanguage = [string]$spec.Language
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
            $script:results += [pscustomobject]$record
            continue
        }

        $record.ZipPath = $suiteZip.FullName
        $record.ZipSha256 = Get-Sha256 $suiteZip.FullName
        $suiteEvidenceDir = Join-Path $evidenceRoot ("suite-" + $spec.Name)

        # Always preserve whatever evidence exists, even if functional-results.json
        # is absent because the child failed before executing test cases.
        [void](Try-Copy-ZipEvidenceEntry -ZipPath $suiteZip.FullName -EntrySuffix "qa-automated-wrapper.json" -Destination (Join-Path $suiteEvidenceDir "qa-automated-wrapper.json"))
        [void](Try-Copy-ZipEvidenceEntry -ZipPath $suiteZip.FullName -EntrySuffix "internal-audio-run.log" -Destination (Join-Path $suiteEvidenceDir "internal-audio-run.log"))
        [void](Try-Copy-ZipEvidenceEntry -ZipPath $suiteZip.FullName -EntrySuffix "functional-results.json" -Destination (Join-Path $suiteEvidenceDir "functional-results.json"))

        try {
            $wrapperResult = Read-ZipJsonEntry -ZipPath $suiteZip.FullName -EntrySuffix "qa-automated-wrapper.json"
            $record.ProfileRestored = [bool]$wrapperResult.ProfileRestored
            $record.RunError = [string]$wrapperResult.RunError
        }
        catch {
            $record.EvidenceError = "Wrapper evidence: " + $_.Exception.Message
        }

        try {
            $functional = Read-ZipJsonEntry -ZipPath $suiteZip.FullName -EntrySuffix "functional-results.json"

            $record.Passed = [int]$functional.Passed
            $record.Failed = [int]$functional.Failed
            $record.Success = [bool]$functional.Success

            $attemptDist = [ordered]@{}
            foreach ($attemptGroup in @($functional.Results | Group-Object Attempts)) {
                $attemptDist[[string]$attemptGroup.Name] = [int]$attemptGroup.Count
            }
            $record.AttemptsDistribution = $attemptDist

            $rateDist = [ordered]@{}
            foreach ($rateGroup in @($functional.Results | Group-Object SpeechRate)) {
                $rateDist[[string]$rateGroup.Name] = [int]$rateGroup.Count
            }
            $record.SpeechRateDistribution = $rateDist

            if ($spec.Name -eq "RadioRecognitionStressInternalES") {
                $badAttemptResults = @($functional.Results | Where-Object { [int]$_.Attempts -ne 1 })
                if ($badAttemptResults.Count -gt 0) {
                    $record.EvidenceError = (
                        "Strict Spanish radio stress contained " +
                        $badAttemptResults.Count +
                        " result(s) with Attempts != 1.")
                }
            }
        }
        catch {
            if ([string]::IsNullOrWhiteSpace($record.EvidenceError)) {
                $record.EvidenceError = "Functional evidence: " + $_.Exception.Message
            }
            else {
                $record.EvidenceError += " | Functional evidence: " + $_.Exception.Message
            }
        }

        $suitePass =
            ($childCode -eq 0) -and
            $record.Success -and
            ($record.Passed -eq [int]$spec.Expected) -and
            ($record.Failed -eq 0) -and
            $record.ProfileRestored -and
            [string]::IsNullOrWhiteSpace($record.RunError) -and
            [string]::IsNullOrWhiteSpace($record.EvidenceError)

        if ($suitePass) {
            Write-MatrixLog (
                "[PASS] {0}: {1}/{1}; language={2}; profile restored." -f
                $spec.Name,$spec.Expected,$spec.Language) "Green"
        }
        else {
            Write-MatrixLog (
                "[FAIL] {0}: child={1}, pass={2}, fail={3}, success={4}, profileRestored={5}, runError='{6}', evidence='{7}'" -f
                $spec.Name,
                $childCode,
                $record.Passed,
                $record.Failed,
                $record.Success,
                $record.ProfileRestored,
                $record.RunError,
                $record.EvidenceError) "Red"
        }

        $script:results += [pscustomobject]$record
        $globalCaseOffset += [int]$spec.Expected
    }
}
catch {
    $script:infrastructureError = $_.Exception.Message
    Write-MatrixLog ("[FAIL] release matrix infrastructure: " + $script:infrastructureError) "Red"
}
finally {
    try {
        Restore-OriginalUiSettings
    }
    catch {
        $script:settingsRestored = $false
        $restoreMessage = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($script:infrastructureError)) {
            $script:infrastructureError = "ui_settings.json restore failed: " + $restoreMessage
        }
        else {
            $script:infrastructureError += " | ui_settings.json restore failed: " + $restoreMessage
        }
        Write-MatrixLog ("[FAIL] ui_settings.json restore: " + $restoreMessage) "Red"
    }

    $passedCases = ($script:results | Measure-Object Passed -Sum).Sum
    $failedCases = ($script:results | Measure-Object Failed -Sum).Sum

    if ($null -eq $passedCases) { $passedCases = 0 }
    if ($null -eq $failedCases) { $failedCases = 0 }

    $failedSuites = @(
        $script:results |
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
        [string]::IsNullOrWhiteSpace($script:infrastructureError) -and
        $script:settingsRestored -and
        ($script:results.Count -eq $Suites.Count) -and
        ($failedSuites.Count -eq 0) -and
        ([int]$passedCases -eq $ExpectedTotalCases) -and
        ([int]$failedCases -eq 0)

    $matrixObject = [ordered]@{
        SchemaVersion = 2
        Version = "1.0.20.0"
        ProductBaseline = "HF36-R47"
        MatrixRevision = "QA14-R5"
        StartedAtLocal = $runStart.ToString("o")
        FinishedAtLocal = (Get-Date).ToString("o")
        ExpectedTotalCases = $ExpectedTotalCases
        PassedCases = [int]$passedCases
        FailedCases = [int]$failedCases
        SuiteCount = $Suites.Count
        ExecutedSuiteCount = $script:results.Count
        FailedSuiteCount = $failedSuites.Count
        OriginalUiSettingsRestored = [bool]$script:settingsRestored
        InfrastructureError = [string]$script:infrastructureError
        Success = [bool]$allPass
        Suites = @($script:results)
    }

    $matrixObject |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $matrixJson -Encoding UTF8

    [string[]]$textLines = @(
        "SimVoice Copilot 1.0.20.0 — FINAL AUTOMATED RELEASE MATRIX",
        "Product baseline : HF36-R30",
        "Matrix revision  : QA14-R5",
        ("Started          : " + $matrixObject.StartedAtLocal),
        ("Finished         : " + $matrixObject.FinishedAtLocal),
        ("Suites           : {0}/{1}" -f $matrixObject.ExecutedSuiteCount,$matrixObject.SuiteCount),
        ("Cases            : {0}/{1} PASS" -f $matrixObject.PassedCases,$matrixObject.ExpectedTotalCases),
        ("Failed cases     : " + $matrixObject.FailedCases),
        ("Failed suites    : " + $matrixObject.FailedSuiteCount),
        ("UI settings restored: " + $matrixObject.OriginalUiSettingsRestored),
        ("Infrastructure error: " + $matrixObject.InfrastructureError),
        ("SUCCESS          : " + $matrixObject.Success),
        "",
        "Per-suite:"
    )

    foreach ($resultItem in $script:results) {
        $textLines += (
            "{0,-36} {1,3}/{2,3}  FAIL={3}  Exit={4}  Lang={5}  ProfileRestored={6}" -f
            $resultItem.Suite,
            $resultItem.Passed,
            $resultItem.ExpectedCases,
            $resultItem.Failed,
            $resultItem.ChildExitCode,
            $resultItem.Language,
            $resultItem.ProfileRestored)
    }

    $textLines | Set-Content -LiteralPath $matrixTxt -Encoding UTF8

    Write-MatrixLog ""
    if ($allPass) {
        Write-MatrixLog "============================================================" "Green"
        Write-MatrixLog "[PASS] FINAL RELEASE MATRIX: 191 / 191" "Green"
        Write-MatrixLog "[PASS] Original ui_settings.json restored." "Green"
        Write-MatrixLog "============================================================" "Green"
        $matrixExitCode = 0
    }
    else {
        Write-MatrixLog "============================================================" "Red"
        Write-MatrixLog (
            "[FAIL] FINAL RELEASE MATRIX: {0}/{1}, failed suites={2}" -f
            $passedCases,$ExpectedTotalCases,$failedSuites.Count) "Red"
        Write-MatrixLog "============================================================" "Red"
        $matrixExitCode = 1
    }

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
    Write-Host "1.0.20.0 is eligible for final manual smoke / RC2 promotion." -ForegroundColor Yellow
}
else {
    Write-Host "FINAL AUTOMATED RELEASE GATE: FAIL" -ForegroundColor Red
    Write-Host "Do not create RC2." -ForegroundColor Yellow
}

Write-Host ("Matrix ZIP: " + $finalZip) -ForegroundColor Cyan
exit $matrixExitCode
