# Phase 2.2 — Guided End-to-End Flight Functional QA

## Purpose

This phase validates the primary SimVoice Copilot product path against a real active Microsoft Flight Simulator flight:

1. The tester speaks the displayed phrase into the configured microphone.
2. SimVoice Copilot performs its real Vosk recognition, normalization, command resolution and SimConnect execution.
3. The independent Phase 2.1 SimConnect Oracle observes the real aircraft value.
4. PASS is granted only when MSFS reaches the expected value within the configured tolerance.

The application feedback is collected as evidence, but it is not trusted as the source of truth.

## Current scope

- Installed SimVoice Copilot MSIX only.
- Active MSFS 2020 or MSFS 2024 flight.
- Recommended initial aircraft: stock Cessna 172 G1000.
- English smoke suite:
  - heading bug;
  - selected altitude;
  - selected vertical speed;
  - transponder.
- English core suite with regression values 110, 210, 310, 360, 800, 8000, 12000, positive and negative vertical speed and transponder codes.
- Spanish smoke suite is included and its phrases are editable in `FlightFunctional\test-cases.json` to match the active Spanish command profile exactly.

## Why this phase is guided

It intentionally uses the real microphone and the real Vosk path. No hidden command injection or direct SimConnect write is used. This immediately tests the functionality that matters to users while the deterministic command bridge remains a later automation enhancement.

## Execution

```powershell
.\Scripts\Run-QA-Flight-Functional.ps1 `
    -Suite SmokeEN `
    -AppNamePattern "*SimVoice*" `
    -SimConnectDll "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp\Microsoft.FlightSimulator.SimConnect.dll"
```

For the complete English numeric regression suite:

```powershell
.\Scripts\Run-QA-Flight-Functional.ps1 `
    -Suite CoreEN `
    -AppNamePattern "*SimVoice*" `
    -SimConnectDll "C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp\Microsoft.FlightSimulator.SimConnect.dll"
```

## Interaction

For every test the runner:

1. Captures the current simulator value.
2. Selects a target that differs from the current value, preventing false PASS results.
3. Displays the exact phrase.
4. Waits for ENTER.
5. Starts the independent Oracle wait.
6. Beeps and displays `SAY THE COMMAND NOW`.
7. Reports PASS or FAIL from the real MSFS value.

On failure the default behavior allows one retry. Before retrying, a new Oracle snapshot is captured and a different target is selected when necessary.

## Evidence

Each run creates:

- `functional-report.html`
- `functional-results.json`
- `command-results.csv`
- `functional-run.log`
- `oracle\` with the before and wait reports for every test
- `app-feedback-logs\` with feedback JSONL files modified during the run

Default location:

```text
C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA\QA-Runs\FlightFunctional\FLIGHT-yyyyMMdd-HHmmss-Suite
```

## Acceptance

A command passes only when:

- SimVoice Copilot remains running;
- MSFS remains in an active flight;
- the independently observed SimVar reaches the expected value;
- the result is within tolerance before timeout.

Memory growth is informational and is not part of this phase's PASS/FAIL decision.

## Initial execution conditions

For the first `SmokeEN` run:

- use the installed MSIX, not a local executable;
- keep the stock Cessna 172 G1000 loaded in an active flight;
- select the English voice profile in SimVoice Copilot;
- use continuous listening for the cleanest first baseline;
- if Push-to-Talk remains enabled, hold its configured key only after the runner beeps;
- do not manually move heading, altitude, vertical-speed or transponder controls while the Oracle is waiting.

The runner confirms the setup once before beginning the suite.
