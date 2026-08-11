# Phase 2.3 — Internal Audio End-to-End QA

This phase removes the human microphone from repeated functional tests while preserving the real recognition pipeline.

## Path under test

1. Windows SpeechSynthesizer generates 16 kHz mono PCM16 in memory.
2. The QA-only named-pipe bridge passes the phrase to the active recognizer.
3. `VoskRecognizerWrapper.ProcessAudioChunk` receives the PCM using the same parameterized, grammar and AI recognizers used by live audio.
4. Normal command parsing and SimConnect dispatch run unchanged.
5. The independent SimConnect Oracle validates the actual simulator value.

No recognized text is injected into the command parser.

## Security/build isolation

The bridge only compiles when MSBuild receives:

`/p:EnableQaInternalAudio=true`

Production builds do not define `SIMVOICE_QA_INTERNAL_AUDIO`.

## Pipe protocol

Name: `SimVoiceCopilot.QA.InternalAudio.v1`

One UTF-8 JSON request line and one UTF-8 JSON response line per connection.

Actions:

- `ping`
- `synthesize`

## Included suites

- `SmokeInternalEN`
- `CoreInternalEN`
- `SmokeInternalES`
- `CoreInternalES`

The Spanish phrases are taken from the app's `Languages\es-ES\parameterized_commands.json` aliases and existing regression cases.
