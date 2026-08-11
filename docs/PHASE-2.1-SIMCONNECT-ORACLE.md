# Phase 2.1 — SimConnect Oracle

## Purpose

This phase adds an independent, read-only SimConnect client to the existing SimVoice Copilot QA project. It does not trust SimVoice Copilot feedback to determine whether a command worked. Instead, later phases will use the Oracle to read the real user-aircraft state directly from Microsoft Flight Simulator.

Phase 2.1 does **not** send simulator events, modify SimVars, inject voice, or launch SimVoice Copilot. It validates the observation layer required by Phase 2.2.

## Official paths

- SimVoice Copilot sources: `C:\Users\Gonzalo\Desktop\MSFS_App\MSFSVoiceMapperApp`
- QA sources: `C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA`
- Oracle results: `C:\Users\Gonzalo\Desktop\MSFS_App\SimVoiceCopilot.QA\QA-Runs\FlightOracle`

## Supported modes

- `Probe`: connect, confirm an active flight, and read one complete snapshot.
- `Snapshot`: export one complete snapshot.
- `Watch`: sample the simulator repeatedly for a configured duration.
- `Assert`: compare one observed variable against an expected value.
- `Wait`: poll until one variable reaches an expected value or times out.

## Supported Oracle variables

`Connected`, `FlightActive`, `DialogMode`, `SimulatorApplication`, `AircraftLoadedPath`, `FlightLoadedPath`, `AircraftTitle`, `AtcModel`, `OnGround`, `PlaneAltitude`, `IndicatedAltitude`, `PlaneHeading`, `AutopilotAvailable`, `AutopilotMaster`, `HeadingHold`, `HeadingBug`, `AltitudeHold`, `SelectedAltitude`, `VerticalSpeedHold`, `SelectedVerticalSpeed`, `Transponder`, `TransponderRawBcd16`, `ParkingBrake`, `GearHandle`, `FlapsHandleIndex`, `FuelGallons`, `WindDirection`, `WindSpeed`, `GroundSpeed`, `SimulationRate`.

Heading and wind-direction assertions use circular angular differences, so `360` and `0` are equivalent.

## Reports

Each execution writes:

- `oracle-run.log`
- `oracle-report.json`
- `oracle-report.html`
- `oracle-snapshots.csv`

## Build dependency

The package does not redistribute Microsoft SDK binaries. The PowerShell runner locates `Microsoft.FlightSimulator.SimConnect.dll` from the installed MSFS SDK or from the SimVoice Copilot source tree, then passes its path to MSBuild.

## Runtime loader fix in v2.1.1

The Oracle no longer creates a hidden WinForms `Form` containing a strongly typed SimConnect property. It now creates a message-only `NativeWindow` first, while the launcher deploys and preloads the exact managed SimConnect wrapper selected for the run. This prevents Windows Forms from converting an assembly-load failure into the misleading `Error creating window handle` exception.
