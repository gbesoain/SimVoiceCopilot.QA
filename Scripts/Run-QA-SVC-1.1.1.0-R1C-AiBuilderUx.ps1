#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WindowsProjectRoot = "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp"
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Path, [string]$Needle, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Missing file for {0}: {1}" -f $Label, $Path)
    }

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

# Deferred grammar activation remains the safety boundary.
Assert-Contains $builder 'SIMVOICE_1_1_1_0_R1B_DEFERRED_GRAMMAR_RESTART' 'deferred grammar marker'
Assert-Contains $builder 'Save Command' 'save-only button EN'
Assert-Contains $builder 'Guardar comando' 'save-only button ES'
Assert-Contains $builder 'Finish Edit / Restart' 'finish/restart button EN'
Assert-Contains $builder 'Finalizar edición / Reiniciar' 'finish/restart button ES'
Assert-Contains $builder 'SimVoice Copilot se reiniciará ahora para cargar la nueva gramática de voz de forma segura.' 'finish confirmation ES'
Assert-Contains $builder 'SimVoice Copilot will restart now to load the new voice grammar safely.' 'finish confirmation EN'
Assert-Contains $builder 'restartRequested = true;' 'restart request only at finish boundary'
Assert-Contains $builder 'ReiniciadorAplicacion.Reiniciar();' 'safe process restart'
Assert-NotContains $builder 'EditableConfigurationHotReload.TryApply();' 'no in-process Vosk hot reload'

# UX: explicit no-plan guidance and automatic-trigger semantics.
Assert-Contains $builder 'private string planEmptyStateMessage = string.Empty;' 'explicit plan empty state'
Assert-Contains $builder 'HasMeaningfulReviewedActionPlan()' 'blank grid row is not a reviewed plan'
Assert-Contains $builder 'NO SE PUDO CREAR UN PLAN SEGURO.' 'no-safe-plan guidance ES'
Assert-Contains $builder 'A SAFE PLAN COULD NOT BE CREATED.' 'no-safe-plan guidance EN'
Assert-Contains $builder 'Ese modo todavía no existe; las condiciones actuales se evalúan cuando dices la frase del comando.' 'automatic trigger clarification ES'
Assert-Contains $builder 'That mode does not exist yet; current conditions are evaluated when you say the command phrase.' 'automatic trigger clarification EN'
Assert-Contains $builder 'todavía no son disparadores automáticos' 'intent hint trigger semantics ES'
Assert-Contains $builder 'they are not automatic triggers yet' 'intent hint trigger semantics EN'
Assert-NotContains $builder 'Sin acciones todavía.' 'ambiguous empty-plan legacy text removed'

# UX: phrase label is a primary visual landmark like Describe your intent.
Assert-Contains $builder 'phraseLabel.ForeColor = ThemeManager.GetPrimaryColor();' 'phrase label primary color'
Assert-Contains $builder 'Font = new Font(SystemFonts.MessageBoxFont.FontFamily, 10F, FontStyle.Bold)' 'phrase/title strong visual style'

# Saved inventory: groups before simple commands, alphabetical inside each class.
Assert-Contains $builder 'string.Equals(choice.Kind, "group", StringComparison.OrdinalIgnoreCase)' 'group-first ordering'
Assert-Contains $builder '.ThenBy(display => display, StringComparer.CurrentCultureIgnoreCase)' 'stable alphabetical order'

# Finish button gets primary styling when restart is pending.
Assert-Contains $builder 'btnFinishRestart.Tag = restartPending' 'finish visual state switch'
Assert-Contains $builder '? EstiloFormulariosConfiguracion.BotonPrimario' 'finish pending primary style'
Assert-Contains $builder 'ThemeManager.Apply(btnFinishRestart);' 'finish re-theme'
Assert-Contains $builder 'pendingSavedChanges.ToString(CultureInfo.InvariantCulture)' 'finish pending count cue'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SVC 1.1.1.0 R1C AI BUILDER UX QA: PASS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
exit 0
