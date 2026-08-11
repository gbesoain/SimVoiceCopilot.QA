[CmdletBinding()]
param(
    [string]$QaTarget = "C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptPath = Join-Path $QaTarget "Scripts\Run-QA-Flight-Extended.ps1"
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "QA script not found: $scriptPath"
}
$text = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
$checks = [ordered]@{
    ExpectedNoMatchFlag = $text.Contains('$expectedDeterministicNoMatch')
    ExactArbitrationPattern = $text.Contains('deterministic command arbitration rejected every candidate')
    DoesNotRelaxOtherFailures = $text.Contains('if (-not [bool]$injection.Success -and -not $expectedDeterministicNoMatch)')
    Version274 = (Get-Content -LiteralPath (Join-Path $QaTarget "VERSION.txt") -Raw -Encoding UTF8) -match '2\.7\.4'
}
$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
$checks.GetEnumerator() | ForEach-Object {
    Write-Host ("{0}: {1}" -f $_.Key, $(if ($_.Value) { "PASS" } else { "FAIL" })) -ForegroundColor $(if ($_.Value) { "Green" } else { "Red" })
}
if ($failed.Count -gt 0) { exit 1 }
Write-Host "QA v2.7.5 no-match classification patch: PASS" -ForegroundColor Green
exit 0
