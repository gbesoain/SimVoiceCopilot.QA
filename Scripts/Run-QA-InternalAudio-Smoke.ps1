[CmdletBinding()]
param(
    [string]$AppNamePattern = "*SimVoice*",
    [string]$SimConnectDll = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp\Microsoft.FlightSimulator.SimConnect.dll"
)

& (Join-Path $PSScriptRoot "Run-QA-Flight-InternalAudio.ps1") `
    -Suite SmokeInternalEN `
    -AppNamePattern $AppNamePattern `
    -SimConnectDll $SimConnectDll
exit $LASTEXITCODE
