# SimVoiceCopilot.QA Final Regression v2.7.5

Suite específica para SimVoice Copilot 1.0.17.0, compilada para `.NET Framework 4.8 / x64`.

## Ejecución focalizada

```powershell
.\Scripts\Run-QA-Voice-Checklists.ps1 -Suite Auto -NoClose
```

Suites admitidas:

- `SmokeEN`
- `CoreEN`
- `SmokeES`
- `CoreES`
- `Auto`, que selecciona Core según `VoiceLanguage`.

El runner exige el paquete privado cuyo AppID coincide con:

```text
SimTechAviation.SimVoiceCopilot.Dev_*
```

La aplicación debe haber sido compilada con:

```text
SIMVOICE_QA_INTERNAL_AUDIO
```

## Cobertura Core

- fixture local determinístico;
- selección e inicio por UI Automation;
- inyección de voz sintetizada por el pipeline Vosk real;
- Repeat, Pause, Resume, Skip, Previous, Next Checklist y Cancel;
- confirmaciones configuradas EN/ES;
- protección frente a confirmación durante pausa;
- comando normal de vuelo no consumido por la sesión;
- siguiente lista pendiente;
- cola TTS inactiva después de cancelar;
- snapshot de sincronización de checklist con aeronave.

## Prueba guiada Garmin

```powershell
.\Scripts\Run-QA-Voice-Checklists-G3000-Guided.ps1
```

Requiere MSFS 2024, Vision Jet G2 cargado y checklist G3000 visible.

## Build

El proyecto principal excluye:

```xml
<Compile Remove="SimConnectOracle\**\*.cs" />
```

`SimConnectOracle` sigue siendo un proyecto separado y solo se compila desde sus scripts dedicados, con la referencia administrada de SimConnect resuelta en tiempo de ejecución.

## v2.7.5

- Restaura los snapshots `checklist` y `checklistSync` del bridge privado.
- Reinicia la aplicación privada antes del bloque final de Voice Checklists.
- CoreEN valida respuestas impresas por ítem: `On`, `Set` y `Ready`.
- Mantiene las confirmaciones configurables y todas las regresiones anteriores.
- La inyección secuencial privada omite el gate VAD solamente durante `SIMVOICE_QA_INTERNAL_AUDIO`.
- El runner se detiene por defecto en el primer caso fallido; use `-ContinueAfterFailure` para una matriz completa.
