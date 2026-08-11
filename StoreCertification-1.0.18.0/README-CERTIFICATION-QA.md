# SimVoice Copilot 1.0.18.0 — Store Certification QA v3.0.1

Este paquete NO modifica fuentes de SimVoice Copilot.
Se instala separado dentro de:

C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA\StoreCertification-1.0.18.0

## Correcciones v3.0.1

Esta revisión corrige únicamente el harness. **No cambia fuentes de producción de SimVoice Copilot.**

El primer run v3.0.0 demostró PASS en source truth, regresiones, Internal Audio QA, 25 ciclos del MSIX instalado y build/install del MSIX final. Los cuatro FAIL restantes eran defectos del harness:

- cero eventos de Windows ya no se interpreta como error;
- se corrige el manejo de colecciones `.Count`;
- EN/ES se valida desde `AppxManifest.xml` y PRI existentes, sin exigir un PRI inglés separado;
- `appcert reset` no aborta el QA: se continúa al WACK `test`;
- la elevación UAC ocurre una sola vez al principio.

## Objetivo

Dar una decisión simple y reproducible antes de Microsoft Store:

- NO-GO: algo obligatorio falló. No subir al Store.
- AUTOMATED PASS: todo el QA automático pasó. Ejecutar solo los 2 smoke tests finales.
- GO STORE: el paquete de soporte posterior a los smoke tests también pasó el analizador.

## Qué prueba automáticamente

1. Git branch exacta 1.0.18.0 y working tree limpio.
2. Guardas semánticas de los fixes RC/HF32H.
3. Rebuild Debug .NET Framework 4.8.
4. Regresiones determinísticas:
   - PARAMETERIZED_REGRESSION_TESTS_PASS
   - CHECKLIST_REGRESSION_TESTS_PASS
5. Build + instalación del MSIX privado Internal Audio QA.
6. QA del MSIX instalado con el runner existente, 25 ciclos.
7. Stress de lifecycle Vosk/nativo, 30 ciclos.
8. Cualquier nuevo crash de SimVoice/libvosk/AccessViolation => NO-GO.
9. Build + instalación del MSIX FINAL de producción.
10. Preflight del MSIX final:
    - versión 1.0.18.0
    - protocolo simvoicecopilot
    - URI EFB -> Windows
    - WASM bridge completo
    - recursos EN/ES
    - sin marker QA Internal Audio
    - sin GGUF de 2.3 GB dentro del MSIX
11. Windows App Certification Kit (WACK) sobre el MSIX final.
12. Gate final de Windows Event Log y diagnósticos.

## PASO 1 — instalar

Dejar en Downloads:

- SimVoiceCopilot-1.0.18.0-StoreCertificationQA-v3.0.1-PAYLOAD.zip
- Install-SimVoiceCopilot-1.0.18.0-StoreCertificationQA-v3.0.1.ps1

Ejecutar:

cd $env:USERPROFILE\Downloads
powershell -ExecutionPolicy Bypass -File ".\Install-SimVoiceCopilot-1.0.18.0-StoreCertificationQA-v3.0.1.ps1"

## PASO 2 — ejecutar todo el QA automático

Idealmente cerrar MSFS primero.

cd C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA\StoreCertification-1.0.18.0
powershell -ExecutionPolicy Bypass -File ".\Run-Certification-QA.ps1"

Si WACK necesita elevación, el script abre automáticamente UAC y continúa.

No reconstruir ni modificar fuentes después de un AUTOMATED PASS.

El reporte queda en:

C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA\QA-Runs\Certification\CERT-YYYYMMDD-HHMMSS\CERTIFICATION-REPORT.html

## PASO 3 — SOLO si dice AUTOMATED PASS

Hacer 2 smoke tests cortos sobre el MSIX de producción que el QA dejó instalado.

### Smoke A — MSFS 2024 / C172 G1000 / ES / Continuous

Duración objetivo: 10–15 min.

- Abrir SimVoice desde EFB si estaba cerrado.
- Confirmar conexión local.
- Abrir checklist nativa.
- Completar al menos 15 ítems por voz.
- Incluir un ítem ON -> decir "encendido".
- Incluir un ítem OFF -> decir "apagado".
- Probar "siguiente lista".
- Cancelar una checklist y confirmar que los selectores siguen disponibles.
- Ejecutar al menos 2 comandos normales de simulador.
- No debe cerrarse/crashear.

### Smoke B — EN / PTT

Preferencia: MSFS 2020. Si no, segundo avión en MSFS 2024.

Duración objetivo: ~10 min.

- Idioma de voz English.
- Push-to-Talk habilitado.
- Reconocer varios comandos.
- Ejecutar al menos 2 comandos reales.
- Confirmar Feedback/Results.
- No debe cerrarse/crashear.

Al terminar AMBOS smoke tests, generar UN paquete de soporte desde SimVoice Copilot.

## PASO 4 — decisión final automática

Copiar/usar el Support ZIP en Downloads y ejecutar:

cd C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA\StoreCertification-1.0.18.0
powershell -ExecutionPolicy Bypass -File ".\Analyze-Final-Smoke-Support.ps1"

El script toma automáticamente el Support ZIP más reciente de Downloads y solo considera crashes/logs POSTERIORES al AUTOMATED PASS.

Salida:

- GO STORE = subir el mismo MSIX validado.
- NO-GO = no subir; revisar el reporte.

## Regla de certificación

NO reconstruir, no aplicar hotfix y no cambiar fuentes entre AUTOMATED PASS y la subida al Store.
Si cambia una sola línea de código/fuente relevante, repetir el QA desde PASO 2.
