[CmdletBinding()]
param(
    [string]$WindowsRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp',
    [string]$EfbRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot-EFB-MSFS',
    [string]$QaRoot = 'C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA',
    [string]$WebRoot = 'C:\xampp\htdocs\simtechaviation\simvoicecopilot_com',
    [switch]$SkipDevMsix,
    [switch]$RunInteractiveRegression,
    [ValidateSet('English','Spanish','G2','All')]
    [string]$InteractivePhase = 'All'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Contract = 'SIMVOICE_1_1_PHASE_D_FINAL_CERTIFICATION_R1'
$ExpectedWindowsVersion = '1.1.0.0'
$ExpectedEfbVersion = '0.1.94'
$ExpectedWasmVersion = '1.0.1'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Downloads = Join-Path $env:USERPROFILE 'Downloads'
$LogPath = Join-Path $Downloads ('SimVoiceCopilot-1.1.0.0-PhaseD-FinalCertification-' + $Stamp + '.log')
$ResultPath = Join-Path $Downloads ('SimVoiceCopilot-1.1.0.0-PhaseD-FinalCertification-' + $Stamp + '.json')
$Steps = New-Object System.Collections.Generic.List[object]

function Write-Line {
    param([string]$Level,[string]$Text,[ConsoleColor]$Color = [ConsoleColor]::Gray)
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Level,$Text
    Write-Host $line -ForegroundColor $Color
    $line | Out-File -LiteralPath $LogPath -Append -Encoding utf8
}
function Step { param([string]$Text) Write-Line 'STAGE' $Text Cyan }
function Pass { param([string]$Text) Write-Line 'PASS' $Text Green }
function Info { param([string]$Text) Write-Line 'INFO' $Text Gray }
function Fail { param([string]$Text) throw $Text }

function Add-StepResult {
    param([string]$Name,[bool]$Success,[int]$ExitCode,[double]$DurationSeconds,[string]$Detail)
    $Steps.Add([pscustomobject][ordered]@{
        name = $Name
        success = $Success
        exitCode = $ExitCode
        durationSeconds = [Math]::Round($DurationSeconds,3)
        detail = $Detail
    })
}

function Quote-Argument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    if ($Value.IndexOf([char]34) -ge 0) { throw 'Embedded double quotes are not supported in certification process arguments.' }
    return ([string][char]34) + $Value + ([string][char]34)
}

function Invoke-ProcessChecked {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory = '',
        [int]$TimeoutSeconds = 1800
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Fail ('Required executable/script host not found for ' + $Name + ': ' + $FilePath)
    }

    $stdout = Join-Path $env:TEMP ('svc-phased-' + [Guid]::NewGuid().ToString('N') + '.out')
    $stderr = Join-Path $env:TEMP ('svc-phased-' + [Guid]::NewGuid().ToString('N') + '.err')
    $argumentString = ($Arguments | ForEach-Object { Quote-Argument ([string]$_) }) -join ' '
    $started = Get-Date
    try {
        Write-Line 'PROCESS' ($Name + ': ' + $FilePath + ' ' + $argumentString) DarkCyan
        $params = @{
            FilePath = $FilePath
            ArgumentList = $argumentString
            RedirectStandardOutput = $stdout
            RedirectStandardError = $stderr
            PassThru = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { $params.WorkingDirectory = $WorkingDirectory }
        $process = Start-Process @params
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            try { & taskkill.exe /PID $process.Id /T /F | Out-Null } catch { try { $process.Kill() } catch { } }
            $exitCode = 124
        }
        else { $exitCode = [int]$process.ExitCode }
        $process.Dispose()

        if (Test-Path -LiteralPath $stdout) {
            Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue | ForEach-Object { Write-Line 'CHILD' ([string]$_) DarkGray }
        }
        if (Test-Path -LiteralPath $stderr) {
            Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue | ForEach-Object { Write-Line 'CHILD' ([string]$_) DarkYellow }
        }

        $duration = ((Get-Date) - $started).TotalSeconds
        $detail = if ($exitCode -eq 0) { 'PASS' } else { 'FAILED' }
        Add-StepResult $Name ($exitCode -eq 0) $exitCode $duration $detail
        if ($exitCode -ne 0) { Fail ($Name + ' failed with ExitCode=' + $exitCode) }
        Pass ($Name + ' PASS')
    }
    finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

function Get-MSBuildPath {
    $candidates = @(
        'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
    )
    foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate } }
    return $null
}

function Get-PHPPath {
    foreach ($candidate in @('C:\xampp\php\php.exe','C:\Program Files\PHP\php.exe')) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    $command = Get-Command php.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Get-PackageVersion {
    param([string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return '' }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    foreach ($name in @('package_version','packageVersion','version','Version')) {
        $property = $manifest.PSObject.Properties[$name]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return ([string]$property.Value).Trim()
        }
    }
    return ''
}

try {
    '' | Out-File -LiteralPath $LogPath -Encoding utf8
    Write-Line 'VERSION' ('Contract=' + $Contract) Cyan
    Write-Line 'VERSION' ('Windows=' + $ExpectedWindowsVersion + ' EFB=' + $ExpectedEfbVersion + ' WASM=' + $ExpectedWasmVersion) Cyan

    Step 'SOURCE_PREFLIGHT'
    foreach ($path in @($WindowsRoot,$EfbRoot,$QaRoot,$WebRoot)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { Fail ('Source Truth path missing: ' + $path) }
    }
    if (Get-Process -Name 'SimVoiceCopilotApp' -ErrorAction SilentlyContinue) {
        Fail 'Close SimVoice Copilot before final certification.'
    }
    $neuralClient = Join-Path $WindowsRoot 'NeuralVoiceClient.cs'
    $clientText = [IO.File]::ReadAllText($neuralClient)
    if ($clientText.IndexOf('SIMVOICE_1_1_PHASE_D_RELEASE_UX_R2_VOICE_SELECTOR_HF2_AUDIO',[StringComparison]::Ordinal) -lt 0) { Fail 'Phase D/HF2 Neural Voice client marker missing.' }
    $catalogPath = Join-Path $WindowsRoot 'NeuralVoiceCatalog.cs'
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { Fail 'NeuralVoiceCatalog.cs missing.' }
    $catalogText = [IO.File]::ReadAllText($catalogPath)
    if ($catalogText.IndexOf('SIMVOICE_1_1_PHASE_D_NEURAL_VOICE_SELECTOR_R2',[StringComparison]::Ordinal) -lt 0 -or $catalogText.IndexOf('marin',[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $catalogText.IndexOf('cedar',[StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail 'Neural Voice selector catalog contract missing.' }
    if ($clientText.IndexOf('StreamingPrebufferMilliseconds = 300',[StringComparison]::Ordinal) -lt 0) { Fail 'HF2 300 ms prebuffer contract missing.' }
    if ([IO.File]::ReadAllText((Join-Path $WindowsRoot 'SimVoiceEfbOutOfProcessStatePublisher.cs')).IndexOf('SIMVOICE_1_1_RC1_R12_EFB_STATE_WASM_RELAY',[StringComparison]::Ordinal) -lt 0) { Fail 'Frozen R12 transport marker missing.' }
    Pass 'Source preflight PASS. Git/branch/HEAD/hash parity is intentionally not consulted.'

    Step 'EFB_BUILD_AND_SYNC'
    $efbBuild = Join-Path $EfbRoot 'scripts\Build-SimVoiceEfb.ps1'
    Invoke-ProcessChecked 'EFB build/typecheck/package + Windows sync' 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$efbBuild,'-WindowsProjectRoot',$WindowsRoot) $EfbRoot 1800

    $windowsEfbManifest = Join-Path $WindowsRoot 'Store\Runtime\MSFS\Packages\simtech-simvoice-efb\manifest.json'
    $efbVersion = Get-PackageVersion $windowsEfbManifest
    if ($efbVersion -ne $ExpectedEfbVersion) { Fail ('Store Runtime EFB version mismatch. Expected=' + $ExpectedEfbVersion + ' Actual=' + $efbVersion) }
    Pass ('Store Runtime EFB version ' + $efbVersion + ' PASS')

    $wasmManifest = Join-Path $WindowsRoot 'Store\Runtime\MSFS\Packages\simtech-simvoice-wasm-bridge\manifest.json'
    $wasmVersion = Get-PackageVersion $wasmManifest
    if ($wasmVersion -ne $ExpectedWasmVersion) { Fail ('WASM version changed unexpectedly. Expected=' + $ExpectedWasmVersion + ' Actual=' + $wasmVersion) }
    Pass ('Frozen WASM version ' + $wasmVersion + ' PASS')

    Step 'NET48_BUILD'
    $msbuild = Get-MSBuildPath
    if ([string]::IsNullOrWhiteSpace([string]$msbuild)) { Fail 'MSBuild.exe for Visual Studio 2022 was not found.' }
    $project = Join-Path $WindowsRoot 'SimVoiceCopilotApp.csproj'
    Invoke-ProcessChecked 'MSBuild net48 Release x64' $msbuild @($project,'/restore','/t:Rebuild','/p:Configuration=Release','/p:Platform=x64','/m','/nologo') $WindowsRoot 1800

    $appExe = Join-Path $WindowsRoot 'bin\x64\Release\net48\SimVoiceCopilotApp.exe'
    Step 'HEADLESS_RELEASE_REGRESSION'
    foreach ($qaArg in @('--qa-entitlements-lifetime-r1','--qa-neural-voice-core','--qa-release-ux-r2','--qa-aircraft-compatibility')) {
        Invoke-ProcessChecked ('Windows ' + $qaArg) $appExe @($qaArg) (Split-Path -Parent $appExe) 180
    }

    Step 'LOCAL_BACKEND_REGRESSION'
    $php = Get-PHPPath
    if ([string]::IsNullOrWhiteSpace([string]$php)) { Fail 'Local PHP executable not found.' }
    foreach ($command in @('simvoice:commercial-foundation-smoke','simvoice:neural-voice-smoke','simvoice:voice-economics-smoke')) {
        Invoke-ProcessChecked ('Laravel ' + $command) $php @('artisan',$command) $WebRoot 300
    }
    Invoke-ProcessChecked 'Laravel Blade compile' $php @('artisan','view:cache') $WebRoot 300

    if (-not $SkipDevMsix) {
        Step 'DEV_MSIX'
        $storeBuild = Join-Path $WindowsRoot 'Store\Build-StoreMSIX.ps1'
        Invoke-ProcessChecked 'DEV MSIX build/sign/install' 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$storeBuild,'-Version',$ExpectedWindowsVersion,'-SignAndInstall') (Split-Path -Parent $storeBuild) 2400
        Pass 'DEV MSIX PASS. Final Microsoft Store MSIX remains a manual user build.'
    }
    else { Info 'DEV MSIX skipped by request.' }

    if ($RunInteractiveRegression) {
        Step 'INTERACTIVE_FINAL_REGRESSION'
        $interactive = Join-Path $QaRoot 'Scripts\Run-QA-Final-Regression.ps1'
        Invoke-ProcessChecked ('Interactive final regression ' + $InteractivePhase) 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$interactive,'-Phase',$InteractivePhase,'-NoBuild') $QaRoot 7200
    }
    else {
        Info 'Interactive full regression was not run. Re-run this script with -RunInteractiveRegression before final Store submission.'
    }

    $result = [ordered]@{
        contract = $Contract
        timestamp = (Get-Date).ToString('o')
        success = $true
        windowsVersion = $ExpectedWindowsVersion
        efbVersion = $ExpectedEfbVersion
        wasmVersion = $ExpectedWasmVersion
        interactiveRegressionRequested = [bool]$RunInteractiveRegression
        interactivePhase = $InteractivePhase
        steps = @($Steps)
        logPath = $LogPath
    }
    $result | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $ResultPath -Encoding utf8
    Write-Line 'RESULT' 'PHASE D FINAL CERTIFICATION GATES: PASS' Green
    Write-Line 'RESULT' ('Result=' + $ResultPath) Green
    exit 0
}
catch {
    $message = $_.Exception.Message
    Write-Line 'RESULT' ('PHASE D FINAL CERTIFICATION GATES: FAIL - ' + $message) Red
    $result = [ordered]@{
        contract = $Contract
        timestamp = (Get-Date).ToString('o')
        success = $false
        error = $message
        steps = @($Steps)
        logPath = $LogPath
    }
    $result | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $ResultPath -Encoding utf8
    exit 1
}
