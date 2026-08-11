# Phase 2.4 Extended Flight Functional QA

## v2.4.4 guided reconnection correction

The reconnect runner now creates each Oracle probe directory before redirecting the child PowerShell console stream. A failed Oracle connection is expected while MSFS is closed, so the child exit code is captured and returned as a normal probe result rather than aborting the parent test.

## v2.4.3 Spanish safe-rejection correction

The Spanish phrase `establecer transponder nueve` is intentionally not recovered as a transponder command when Vosk produces an acoustic alias such as `tres bajar nueve`. Spanish acoustic recovery is restricted to exactly four valid octal digits. The negative test now accepts a final safe rejection, waits for the asynchronous local AI fallback to become idle, and refuses to pass on the interim `AI fallback analyzing...` message alone.

# Phase 2.4 — Extended Flight Functional QA

Phase 2.4 extends the validated internal-audio and SimConnect Oracle path.

## Suites

- `StatesInternalEN` / `StatesInternalES`: autopilot, parking brake, landing lights, beacon lights and flaps.
- `CalloutsInternalEN` / `CalloutsInternalES`: altitude, heading, fuel, ground speed, actual vertical speed and combined wind. The final response spoken/shown by SimVoice is compared with an independent Oracle snapshot.
- `NegativeInternalEN` / `NegativeInternalES`: incomplete, invalid and unrelated phrases must not alter protected simulator states.
- `SessionInternalEN` / `SessionInternalES`: 50-command mixed sessions.
- Guided reconnection: closes/restarts MSFS with user confirmation, while all voice commands remain internally synthesized.

## Acceptance

A suite fails on a crash, hang, missing command, incorrect value, wrong call-out value, false positive or protected state change caused by a negative phrase. Memory remains informational only.


## v2.4.2 state restoration correction

Toggle cleanup waits for spoken feedback to finish and then waits four seconds before repeating the same command, respecting the application same-command cooldown. Cleanup failure is now a blocking test failure rather than an informational field.
