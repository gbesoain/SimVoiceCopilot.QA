#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp"
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Path, [string]$Needle, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ("Missing file: {0}" -f $Path) }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw ("{0} missing in {1}: {2}" -f $Label, $Path, $Needle)
    }
}

function Assert-NotContains {
    param([string]$Path, [string]$Needle, [string]$Label)
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) {
        throw ("{0} unexpectedly present in {1}: {2}" -f $Label, $Path, $Needle)
    }
}

$builder = Join-Path $WindowsProjectRoot 'AiCommandBuilderForm.cs'
$resolver = Join-Path $WindowsProjectRoot 'NaturalCommandResolver.cs'
$interpreter = Join-Path $WindowsProjectRoot 'LocalAiCommandInterpreter.cs'

# R1 generation lifecycle
Assert-Contains $builder 'CancellationTokenSource resolveCancellation' 'R1 cancellation ownership'
Assert-Contains $builder 'Interlocked.Increment(ref resolveGeneration)' 'R1 generation sequencing'
Assert-Contains $builder 'currentCancellation.CancelAfter(TimeSpan.FromSeconds(45))' 'R1 generation budget'
Assert-Contains $builder 'Build new plan' 'R1 replacement-generation UX EN'
Assert-Contains $builder 'Crear nuevo plan' 'R1 replacement-generation UX ES'

# R1B deferred restart/save-session UX
Assert-Contains $builder 'SIMVOICE_1_1_1_0_R1B_DEFERRED_GRAMMAR_RESTART' 'R1B marker'
Assert-Contains $builder 'Save Command' 'R1B save button EN'
Assert-Contains $builder 'Guardar comando' 'R1B save button ES'
Assert-Contains $builder 'Finish Edit / Restart' 'R1B finish button EN'
Assert-Contains $builder 'Finalizar edición / Reiniciar' 'R1B finish button ES'
Assert-Contains $builder 'restartPending = true;' 'R1B restart pending state'
Assert-Contains $builder 'btnFinishRestart.Enabled = restartPending;' 'R1B finish activation'
Assert-Contains $builder 'restartDeferred"] = true' 'R1B deferred restart diagnostic'
Assert-Contains $builder 'Saved changes are already on disk' 'R1B close protection EN'
Assert-Contains $builder 'Los cambios guardados ya están en disco' 'R1B close protection ES'
Assert-Contains $builder 'if (restartRequested)' 'R1B restart boundary'
Assert-NotContains $builder 'Save & restart' 'R1B old combined action'
Assert-NotContains $builder 'Guardar y reiniciar' 'R1B old combined action ES'
Assert-NotContains $builder 'EditableConfigurationHotReload.TryApply();' 'R1B in-process grammar hot reload'

# R1 resolver/interpreter safety remains present
Assert-Contains $resolver 'CancellationToken cancellationToken' 'R1 resolver cancellation overload'
Assert-Contains $interpreter 'CancellationTokenSource.CreateLinkedTokenSource' 'R1 linked cancellation'
Assert-Contains $interpreter 'AI_REQUEST_TIMEOUT' 'R1 timeout diagnostic'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R1B AI BUILDER SAVE SESSION QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
