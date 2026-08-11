[CmdletBinding()]
param(
    [string]$AppNamePattern = "*SimVoice Copilot*",
    [string]$AppIdPattern = "*",
    [string]$ProcessName = "SimVoiceCopilotApp",
    [ValidateRange(1, 10000)]
    [int]$Cycles = 25,
    [ValidateSet("All", "VoiceCommands", "SimVarCallouts", "Settings", "KeyboardSettings", "Checklist", "VoiceChecklists", "TabsOnly")]
    [string]$Scenario = "All",
    [ValidateSet("Auto", "SmokeEN", "CoreEN", "SmokeES", "CoreES")]
    [string]$ChecklistSuite = "Auto",
    [ValidateRange(1, 10000)]
    [double]$MaxWorkingSetGrowthMb = 150,
    [string]$OutputDirectory = "",
    [switch]$DiagnoseUi,
    [switch]$NoClose,
    [switch]$ListApps
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$baseConfig = Join-Path $projectRoot "qa.config.xml"

function Set-XmlElementText {
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Document,

        [Parameter(Mandatory = $true)]
        [string]$XPath,

        [AllowEmptyString()]
        [string]$Value
    )

    $node = $Document.SelectSingleNode($XPath)
    if ($null -eq $node) {
        $separator = $XPath.LastIndexOf('/')
        if ($separator -le 0 -or $separator -ge ($XPath.Length - 1)) {
            throw "Invalid XML path: $XPath"
        }

        $parentPath = $XPath.Substring(0, $separator)
        $elementName = $XPath.Substring($separator + 1)
        $parent = $Document.SelectSingleNode($parentPath)
        if ($null -eq $parent) {
            throw "XML parent node was not found: $parentPath"
        }

        $node = $Document.CreateElement($elementName)
        $null = $parent.AppendChild($node)
    }

    $node.InnerText = [string]$Value
}

$candidates = @(Get-StartApps |
    Where-Object { $_.Name -like $AppNamePattern -and $_.AppID -like $AppIdPattern } |
    Sort-Object Name, AppID)

if ($ListApps) {
    if ($candidates.Count -eq 0) {
        Write-Host "No installed Start menu apps matched '$AppNamePattern'." -ForegroundColor Yellow
        exit 1
    }

    $candidates | Format-Table Name, AppID -AutoSize
    exit 0
}

if ($candidates.Count -eq 0) {
    throw "No installed MSIX/Store app matched name '$AppNamePattern' and AppID '$AppIdPattern'. Run: .\Scripts\Run-QA-MSIX.ps1 -ListApps"
}

if ($candidates.Count -gt 1) {
    $detail = ($candidates | ForEach-Object { "  $($_.Name) -> $($_.AppID)" }) -join [Environment]::NewLine
    throw "More than one installed app matched name '$AppNamePattern' and AppID '$AppIdPattern'. Use -AppNamePattern or -AppIdPattern with a more specific value.$([Environment]::NewLine)$detail"
}

$app = $candidates[0]
$runtimeConfig = Join-Path $env:TEMP "simvoice-qa-msix-$([guid]::NewGuid().ToString('N')).config.xml"

if (-not (Test-Path -LiteralPath $baseConfig)) {
    throw "Base QA configuration was not found: $baseConfig"
}

[xml]$xml = Get-Content -LiteralPath $baseConfig -Raw
Set-XmlElementText -Document $xml -XPath "/QaConfiguration/Application/LaunchMode" -Value "PackagedApp"
Set-XmlElementText -Document $xml -XPath "/QaConfiguration/Application/ExecutablePath" -Value ""
Set-XmlElementText -Document $xml -XPath "/QaConfiguration/Application/PackagedAppId" -Value ([string]$app.AppID)
Set-XmlElementText -Document $xml -XPath "/QaConfiguration/Application/ProcessName" -Value $ProcessName
Set-XmlElementText -Document $xml -XPath "/QaConfiguration/Execution/MaxWorkingSetGrowthMb" -Value ($MaxWorkingSetGrowthMb.ToString([System.Globalization.CultureInfo]::InvariantCulture))

$scenarioIds = @{
    VoiceCommands    = @("btnConfigurar")
    SimVarCallouts   = @("btnEditCallouts")
    Settings         = @("btnVoiceSettings")
    KeyboardSettings = @("btnKeyboardSettings")
    Checklist        = @("btnPestanaChecklist")
    VoiceChecklists  = @("btnPestanaChecklist")
    TabsOnly         = @("btnPestanaChecklist", "btnPestanaFeedback", "btnPestanaComandos")
}

if ($Scenario -ne "All") {
    $allowedIds = @($scenarioIds[$Scenario])
    $panelNodes = @($xml.SelectNodes("/QaConfiguration/Navigation/Panel"))

    foreach ($panelNode in $panelNodes) {
        $automationId = [string]$panelNode.GetAttribute("AutomationId")
        if ($allowedIds -notcontains $automationId) {
            $null = $panelNode.ParentNode.RemoveChild($panelNode)
        }
    }

    $remainingPanels = @($xml.SelectNodes("/QaConfiguration/Navigation/Panel"))
    if ($remainingPanels.Count -eq 0) {
        throw "Scenario '$Scenario' did not leave any configured navigation action."
    }
}


if ($Scenario -eq "VoiceChecklists") {
    $fixture = Join-Path $projectRoot "VoiceChecklists\Fixtures\SimVoice-QA-Voice-Checklist.xml"
    if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) {
        throw "Voice Checklist QA fixture was not found: $fixture"
    }

    Set-XmlElementText -Document $xml -XPath "/QaConfiguration/VoiceChecklists/Enabled" -Value "true"
    Set-XmlElementText -Document $xml -XPath "/QaConfiguration/VoiceChecklists/Suite" -Value $ChecklistSuite
    Set-XmlElementText -Document $xml -XPath "/QaConfiguration/VoiceChecklists/FixtureFile" -Value ([System.IO.Path]::GetFullPath($fixture))
    Set-XmlElementText -Document $xml -XPath "/QaConfiguration/Execution/TestSingleInstanceRestore" -Value "false"
    $Cycles = 1
}
else {
    Set-XmlElementText -Document $xml -XPath "/QaConfiguration/VoiceChecklists/Enabled" -Value "false"
}

$xml.Save($runtimeConfig)

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputDirectory = Join-Path $projectRoot "QA-Runs\QA-$runStamp-$Scenario"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Write-Host "MSIX app : $($app.Name)" -ForegroundColor Cyan
Write-Host "AppID    : $($app.AppID)" -ForegroundColor DarkGray
Write-Host "Process  : $ProcessName" -ForegroundColor DarkGray
Write-Host "Scenario : $Scenario" -ForegroundColor DarkGray
if ($Scenario -eq "VoiceChecklists") {
    Write-Host "VC suite : $ChecklistSuite" -ForegroundColor DarkGray
}
Write-Host "Cycles   : $Cycles" -ForegroundColor DarkGray
Write-Host "WS limit : $MaxWorkingSetGrowthMb MB" -ForegroundColor DarkGray
Write-Host "Results  : $OutputDirectory" -ForegroundColor DarkGray

$runScript = Join-Path $PSScriptRoot "Run-QA.ps1"
$params = @{
    Configuration = "Release"
    ConfigFile = $runtimeConfig
    Cycles = $Cycles
    OutputDirectory = $OutputDirectory
}
if ($DiagnoseUi) { $params.DiagnoseUi = $true }
if ($NoClose) { $params.NoClose = $true }

try {
    & $runScript @params
    exit $LASTEXITCODE
}
finally {
    if (Test-Path -LiteralPath $runtimeConfig) {
        Remove-Item -LiteralPath $runtimeConfig -Force
    }
}
