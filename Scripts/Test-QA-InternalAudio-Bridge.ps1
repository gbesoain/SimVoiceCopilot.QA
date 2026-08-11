[CmdletBinding()]
param(
    [string]$PipeName = "SimVoiceCopilot.QA.InternalAudio.v1",
    [int]$TimeoutMs = 10000
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$pipe = $null
$reader = $null
$writer = $null
try {
    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
        ".",
        $PipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::Asynchronous)
    $pipe.Connect($TimeoutMs)
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $reader = [System.IO.StreamReader]::new($pipe, $utf8, $false, 65536, $true)
    $writer = [System.IO.StreamWriter]::new($pipe, $utf8, 65536, $true)
    $writer.AutoFlush = $true

    $request = [ordered]@{
        ProtocolVersion = 1
        Action = "ping"
        CorrelationId = [guid]::NewGuid().ToString("N")
        TimeoutMs = $TimeoutMs
    }
    $writer.WriteLine(($request | ConvertTo-Json -Compress))
    $line = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw "Bridge returned an empty response."
    }

    $response = $line | ConvertFrom-Json
    $response | Format-List
    if (-not [bool]$response.Success) { exit 1 }
    exit 0
}
finally {
    if ($writer) { try { $writer.Dispose() } catch { } }
    if ($reader) { try { $reader.Dispose() } catch { } }
    if ($pipe) { try { $pipe.Dispose() } catch { } }
}
