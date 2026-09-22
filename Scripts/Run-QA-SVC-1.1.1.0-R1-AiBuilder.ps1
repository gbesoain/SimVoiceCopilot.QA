#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp"
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Path, [string]$Needle, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw "$Label missing in ${Path}: $Needle"
    }
}

function Assert-NotContains {
    param([string]$Path, [string]$Needle, [string]$Label)
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) {
        throw "$Label unexpectedly present in ${Path}: $Needle"
    }
}

$builder = Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs'
$resolver = Join-Path $WindowsProjectRoot 'NaturalCommandResolver.cs'
$interpreter = Join-Path $WindowsProjectRoot 'LocalAiCommandInterpreter.cs'

Assert-Contains $builder 'CancellationTokenSource resolveCancellation' 'R1 cancellation ownership'
Assert-Contains $builder 'Interlocked.Increment(ref resolveGeneration)' 'R1 generation sequencing'
Assert-Contains $builder 'currentCancellation.CancelAfter(TimeSpan.FromSeconds(45))' 'R1 total generation budget'
Assert-Contains $builder 'currentCancellation.Token);' 'R1 resolver cancellation propagation'
Assert-Contains $builder 'if (IsCurrentResolveGeneration(generation, currentCancellation))' 'R1 stale runtime status guard'
Assert-Contains $builder 'HasReviewedActionPlan()' 'R1 previous-plan preservation'
Assert-Contains $builder 'Crear nuevo plan' 'R1 replacement-generation UX ES'
Assert-Contains $builder 'Build new plan' 'R1 replacement-generation UX EN'
Assert-Contains $builder 'Guardar y reiniciar' 'R1 save/restart UX ES'
Assert-Contains $builder 'Save & restart' 'R1 save/restart UX EN'
Assert-Contains $builder 'restartRequired"] = true' 'R1 safe restart diagnostic'
Assert-Contains $builder 'ReiniciadorAplicacion.Reiniciar();' 'R1 safe grammar restart boundary'
Assert-NotContains $builder 'if (busy)' 'R1 old ignored-click gate'

Assert-Contains $resolver 'CancellationToken cancellationToken' 'R1 resolver cancellation overload'
Assert-Contains $resolver 'additionalCatalog,' 'R1 resolver catalog preservation'
Assert-Contains $interpreter 'CancellationToken cancellationToken' 'R1 interpreter cancellation overload'
Assert-Contains $interpreter 'CancellationTokenSource.CreateLinkedTokenSource' 'R1 linked timeout/caller cancellation'
Assert-Contains $interpreter 'AI_REQUEST_CANCELLED' 'R1 cancellation diagnostic'
Assert-Contains $interpreter 'AI_REQUEST_TIMEOUT' 'R1 timeout diagnostic'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R1 AI COMMAND BUILDER SOURCE QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
