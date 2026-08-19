[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Suite,

    [ValidateSet("Heading", "Altitude", "Airspeed", "VerticalSpeed", "Radio", "Transponder")]
    [string[]]$Category = @(),

    [ValidateRange(1, 5)]
    [int]$MaxAttempts = 2,

    [switch]$ContinueAfterFailure,
    [switch]$NoBuild,

    # QA14-R5 matrix-wide progress context.
    [ValidateRange(0, 10000)]
    [int]$GlobalCaseOffset = 0,

    [ValidateRange(0, 10000)]
    [int]$GlobalCaseTotal = 0,

    [string]$ProcessName = "SimVoiceCopilotApp"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $PSScriptRoot "Run-QA-Flight-InternalAudio.ps1"
$catalogPath = Join-Path $projectRoot "FlightFunctional\internal-audio-test-cases.json"
$runStamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$outputDirectory = Join-Path $projectRoot ("QA-Runs\FlightInternalAudio\INTERNAL-{0}-{1}" -f $runStamp, $Suite)
$downloadsDirectory = Join-Path $env:USERPROFILE "Downloads"
$zipPath = Join-Path $downloadsDirectory ("INTERNAL-{0}-{1}.zip" -f $runStamp, $Suite)

function Write-QaHost {
    param(
        [string]$Message,
        [string]$Color = "Gray"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Stop-SimVoiceQaProcess {
    $processes = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        try {
            if (-not $process.HasExited) {
                [void]$process.CloseMainWindow()
                if (-not $process.WaitForExit(5000)) {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    [void]$process.WaitForExit(5000)
                }
            }
        }
        catch {
            try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}

function Get-TargetForVariable {
    param([string]$Variable)

    switch ($Variable) {
        "HeadingBug"             { return "HEADING_BUG_SET" }
        "SelectedAltitude"       { return "AP_ALT_VAR_SET_ENGLISH" }
        "SelectedAirspeed"       { return "AP_SPD_VAR_SET" }
        "SelectedSpeed"          { return "AP_SPD_VAR_SET" }
        "SelectedVerticalSpeed"  { return "AP_VS_VAR_SET_ENGLISH" }
        "Transponder"            { return "XPNDR_SET" }
        "TransponderCode"        { return "XPNDR_SET" }
        "Com1Active"             { return "COM_RADIO_SET_HZ" }
        "Com1Standby"            { return "COM_STBY_RADIO_SET_HZ" }
        "Com2Active"             { return "COM2_RADIO_SET_HZ" }
        "Com2Standby"            { return "COM2_STBY_RADIO_SET_HZ" }
        "Nav1Active"             { return "NAV1_RADIO_SET_HZ" }
        "Nav1Standby"            { return "NAV1_STBY_SET_HZ" }
        "Nav2Active"             { return "NAV2_RADIO_SET_HZ" }
        "Nav2Standby"            { return "NAV2_STBY_SET_HZ" }
        default {
            throw ("No QA command-target mapping exists for variable '{0}'. Add it before running this suite." -f $Variable)
        }
    }
}

function Get-CanonicalProfilePhrase {
    param(
        [string]$Target,
        [string]$Language
    )

    $spanish = $Language.StartsWith("es", [System.StringComparison]::OrdinalIgnoreCase)

    if ($spanish) {
        switch ($Target) {
            "HEADING_BUG_SET"             { return "establecer rumbo" }
            "AP_ALT_VAR_SET_ENGLISH"      { return "establecer altitud" }
            "AP_SPD_VAR_SET"              { return "establecer velocidad" }
            "AP_VS_VAR_SET_ENGLISH"       { return "establecer velocidad vertical" }
            "XPNDR_SET"                   { return "establecer transpondedor" }
            "COM_RADIO_SET_HZ"            { return "establecer radio" }
            "COM_STBY_RADIO_SET_HZ"       { return "establecer com uno espera" }
            "COM2_RADIO_SET_HZ"           { return "establecer com dos" }
            "COM2_STBY_RADIO_SET_HZ"      { return "establecer com dos espera" }
            "NAV1_RADIO_SET_HZ"           { return "establecer frecuencia nav" }
            "NAV1_STBY_SET_HZ"            { return "establecer nav uno espera" }
            "NAV2_RADIO_SET_HZ"           { return "establecer nav dos" }
            "NAV2_STBY_SET_HZ"            { return "establecer nav dos espera" }
            default { throw ("No Spanish QA profile phrase exists for target '{0}'." -f $Target) }
        }
    }

    switch ($Target) {
        "HEADING_BUG_SET"             { return "set heading bug" }
        "AP_ALT_VAR_SET_ENGLISH"      { return "set altitude" }
        "AP_SPD_VAR_SET"              { return "set airspeed" }
        "AP_VS_VAR_SET_ENGLISH"       { return "set vertical speed" }
        "XPNDR_SET"                   { return "set transponder" }
        "COM_RADIO_SET_HZ"            { return "set radio" }
        "COM_STBY_RADIO_SET_HZ"       { return "set com one standby" }
        "COM2_RADIO_SET_HZ"           { return "set com two" }
        "COM2_STBY_RADIO_SET_HZ"      { return "set com two standby" }
        "NAV1_RADIO_SET_HZ"           { return "set nav frequency" }
        "NAV1_STBY_SET_HZ"            { return "set nav one standby" }
        "NAV2_RADIO_SET_HZ"           { return "set nav two" }
        "NAV2_STBY_SET_HZ"            { return "set nav two standby" }
        default { throw ("No English QA profile phrase exists for target '{0}'." -f $Target) }
    }
}

function Get-ProfileDirectory {
    param([string]$Language)

    $dataRoot = Join-Path $env:LOCALAPPDATA "SimVoiceCopilot"
    if ($Language.StartsWith("en", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $dataRoot "Profiles"
    }

    return Join-Path $dataRoot ("Languages\{0}\Profiles" -f $Language)
}

function Get-WindowsPowerShell {
    $candidate = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }

    $command = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    throw "Windows PowerShell 5.1 was not found."
}

function Write-WrapperManifest {
    param(
        [string]$Path,
        [string]$Language,
        [string]$TemporaryProfileFileName,
        [string[]]$Targets,
        [int]$ChildExitCode,
        [string]$RunError
    )

    $manifest = [ordered]@{
        SchemaVersion = 1
        Suite = $Suite
        Language = $Language
        StartedAtLocal = $script:wrapperStarted.ToString("o")
        FinishedAtLocal = (Get-Date).ToString("o")
        TemporaryProfile = $TemporaryProfileFileName
        RequiredTargets = @($Targets)
        PreviousActiveProfile = $script:previousActiveProfileText
        ChildExitCode = $ChildExitCode
        RunError = $RunError
        OutputDirectory = $outputDirectory
        ZipPath = $zipPath
        ProfileRestored = $script:profileRestored
    }

    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $runnerPath)) {
    throw ("QA runner not found: {0}" -f $runnerPath)
}
if (-not (Test-Path -LiteralPath $catalogPath)) {
    throw ("QA catalog not found: {0}" -f $catalogPath)
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$suiteProperty = $catalog.suites.PSObject.Properties[$Suite]
if ($null -eq $suiteProperty) {
    throw ("Suite '{0}' was not found in {1}." -f $Suite, $catalogPath)
}

$tests = @($suiteProperty.Value)
if ($Category.Count -gt 0) {
    $tests = @($tests | Where-Object {
        $categoryProperty = $_.PSObject.Properties["category"]
        $null -ne $categoryProperty -and $Category -contains [string]$categoryProperty.Value
    })
}
if ($tests.Count -eq 0) {
    throw ("Suite '{0}' contains no tests after applying the requested category filter." -f $Suite)
}

$language = [string]$tests[0].language
foreach ($test in $tests) {
    if (-not [string]::Equals([string]$test.language, $language, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "A single automated QA run cannot mix recognition languages."
    }
}

[string[]]$targets = @()
foreach ($test in $tests) {
    $variable = [string]$test.variable
    $target = Get-TargetForVariable -Variable $variable
    if ($targets -notcontains $target) {
        $targets += $target
    }
}

$tempProfile = [ordered]@{}
foreach ($target in $targets) {
    $phrase = Get-CanonicalProfilePhrase -Target $target -Language $language
    $tempProfile[$phrase] = [ordered]@{
        Target = $target
        Phases = @()
    }
}

$profileDirectory = Get-ProfileDirectory -Language $language
New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null

$tempProfileFileName = "qa_internal_{0}_{1}.json" -f ($Suite -replace '[^A-Za-z0-9_.-]', '_'), [guid]::NewGuid().ToString("N")
$tempProfilePath = Join-Path $profileDirectory $tempProfileFileName
$activeProfilePath = Join-Path $profileDirectory "active_profile.txt"

$script:wrapperStarted = Get-Date
$script:previousActiveProfileExists = Test-Path -LiteralPath $activeProfilePath
$script:previousActiveProfileBytes = $null
$script:previousActiveProfileText = ""
$script:profileRestored = $false

if ($script:previousActiveProfileExists) {
    $script:previousActiveProfileBytes = [System.IO.File]::ReadAllBytes($activeProfilePath)
    try {
        $script:previousActiveProfileText = [System.IO.File]::ReadAllText($activeProfilePath).Trim()
    }
    catch {
        $script:previousActiveProfileText = "<unreadable-as-text>"
    }
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$tempProfileJson = $tempProfile | ConvertTo-Json -Depth 6
$tempProfileJson | Set-Content -LiteralPath $tempProfilePath -Encoding UTF8
$tempProfileJson | Set-Content -LiteralPath (Join-Path $outputDirectory "qa-temporary-command-profile.json") -Encoding UTF8

$childExitCode = 1
$runError = ""
$profileActivated = $false

try {
    Write-QaHost "" "Gray"
    Write-QaHost "SimVoice Copilot — SELF-CONTAINED AUTOMATED QA" "Cyan"
    Write-QaHost ("Suite          : {0}" -f $Suite) "White"
    Write-QaHost ("Language       : {0}" -f $language) "White"
    Write-QaHost ("Temporary JSON : {0}" -f $tempProfilePath) "White"
    Write-QaHost ("Required events: {0}" -f (($targets | Sort-Object) -join ", ")) "White"
    Write-QaHost ""

    # The profile is read at application startup. Never reuse a running process
    # with an unknown/user profile for a self-contained QA run.
    Stop-SimVoiceQaProcess

    [System.IO.File]::WriteAllText($activeProfilePath, $tempProfileFileName, [System.Text.UTF8Encoding]::new($false))
    $profileActivated = $true
    Write-QaHost "[PASS] temporary QA command profile activated." "Green"

    $powershellExe = Get-WindowsPowerShell
    [string[]]$childArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $runnerPath,
        "-Suite", $Suite,
        "-OutputDirectory", $outputDirectory,
        "-MaxAttempts", [string]$MaxAttempts,
        "-GlobalCaseOffset", [string]$GlobalCaseOffset,
        "-GlobalCaseTotal", [string]$GlobalCaseTotal,
        "-CloseAppAtEnd"
    )

    if ($ContinueAfterFailure) {
        $childArgs += "-ContinueAfterFailure"
    }
    if ($NoBuild) {
        $childArgs += "-NoBuild"
    }
    if ($Category.Count -gt 0) {
        $childArgs += "-Category"
        foreach ($item in $Category) {
            $childArgs += [string]$item
        }
    }

    & $powershellExe @childArgs
    $childExitCode = $LASTEXITCODE
}
catch {
    $runError = $_.Exception.Message
    Write-QaHost ("[FAIL] automated QA wrapper: {0}" -f $runError) "Red"
    $childExitCode = 1
}
finally {
    # The application must not remain alive with the temporary QA profile loaded.
    Stop-SimVoiceQaProcess

    try {
        if ($script:previousActiveProfileExists) {
            [System.IO.File]::WriteAllBytes($activeProfilePath, $script:previousActiveProfileBytes)
        }
        else {
            Remove-Item -LiteralPath $activeProfilePath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $tempProfilePath) {
            Remove-Item -LiteralPath $tempProfilePath -Force -ErrorAction Stop
        }

        $script:profileRestored = $true
        Write-QaHost "[PASS] previous voice-command profile restored." "Green"
    }
    catch {
        $script:profileRestored = $false
        $restoreError = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($runError)) {
            $runError = "Profile restore failed: " + $restoreError
        }
        else {
            $runError = $runError + " | Profile restore failed: " + $restoreError
        }
        $childExitCode = 1
        Write-QaHost ("[FAIL] profile restore: {0}" -f $restoreError) "Red"
    }

    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

    $manifestPath = Join-Path $outputDirectory "qa-automated-wrapper.json"
    Write-WrapperManifest `
        -Path $manifestPath `
        -Language $language `
        -TemporaryProfileFileName $tempProfileFileName `
        -Targets @($targets) `
        -ChildExitCode $childExitCode `
        -RunError $runError

    try {
        New-Item -ItemType Directory -Path $downloadsDirectory -Force | Out-Null

        $zipStagingRoot = Join-Path $env:TEMP (
            "SimVoice-QA-Zip-{0}-{1}" -f $runStamp, [guid]::NewGuid().ToString("N"))
        $zipStagingDirectory = Join-Path $zipStagingRoot (
            "INTERNAL-{0}-{1}" -f $runStamp, $Suite)

        try {
            New-Item -ItemType Directory -Path $zipStagingDirectory -Force | Out-Null

            # Do not archive live Oracle files. First copy the completed run to an
            # isolated staging directory. Robocopy retries transient file locks.
            & robocopy.exe `
                $outputDirectory `
                $zipStagingDirectory `
                /E `
                /R:15 `
                /W:1 `
                /NFL `
                /NDL `
                /NJH `
                /NJS `
                /NP | Out-Null

            $robocopyCode = $LASTEXITCODE
            if ($robocopyCode -ge 8) {
                throw (
                    "QA result staging copy failed. Robocopy exit code: {0}" -f
                    $robocopyCode)
            }

            if (Test-Path -LiteralPath $zipPath) {
                Remove-Item -LiteralPath $zipPath -Force -ErrorAction Stop
            }

            # Staging has no Oracle/SimVoice process handles, so compression is deterministic.
            Compress-Archive `
                -LiteralPath $zipStagingDirectory `
                -DestinationPath $zipPath `
                -CompressionLevel Optimal `
                -Force `
                -ErrorAction Stop

            if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
                throw "ZIP creation completed without producing the Downloads artifact."
            }
        }
        finally {
            if (Test-Path -LiteralPath $zipStagingRoot) {
                Remove-Item -LiteralPath $zipStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Write-QaHost ("[PASS] QA result ZIP ready in Downloads: {0}" -f $zipPath) "Green"
    }
    catch {
        $zipError = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($runError)) {
            $runError = "Result ZIP creation failed: " + $zipError
        }
        else {
            $runError = $runError + " | Result ZIP creation failed: " + $zipError
        }
        $childExitCode = 1
        Write-QaHost ("[FAIL] result ZIP: {0}" -f $zipError) "Red"
    }
}

Write-QaHost ""
if ($childExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($runError)) {
    Write-QaHost "AUTOMATED QA RESULT: PASS" "Green"
}
else {
    Write-QaHost "AUTOMATED QA RESULT: FAIL" "Red"
}
Write-QaHost ("ZIP (Downloads): {0}" -f $zipPath) "Yellow"
Write-QaHost "Your original active voice-command profile has been restored." "Gray"

exit $childExitCode
