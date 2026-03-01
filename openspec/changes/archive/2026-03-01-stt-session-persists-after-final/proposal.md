# Prevent Mid-Session Transcript Dropouts so Recording Continues Reliably

## Why

### Summary
While using the STT playground, transcript updates stop after a `final` STT event even though the user is still in the same recording flow. This creates a high-friction experience where users must manually stop and restart to resume transcription. We need the session lifecycle to remain active until the user explicitly stops (or an error occurs), so speech capture remains continuous.

### Original user request (verbatim)
I think we should create a separate openspec change for this.

## What Changes

- Define a clear session-lifecycle requirement: receiving an STT `final` event must not terminate an active recording session.
- Ensure transcript updates continue for subsequent `partial`/`final` events in the same session without requiring stop/start.
- Restrict session termination to explicit stop actions or error paths.
- Add regression coverage for the post-`final` continuation path.

## Capabilities

### New Capabilities
- `stt-session-continuity`: Ensures an active STT session continues processing transcript updates after `final` events until explicit stop/error.

### Modified Capabilities
- `on-air-indicator-ui`: Clarify that indicator/activity behavior is tied to active recording/session state and is not implicitly disabled by `final` alone.

## Impact

- Affected code:
  - `stt_playground/lib/stt_playground_web/live/stt_live.ex` (STT event/session lifecycle handling)
  - `stt_playground/test/...` LiveView or unit tests for regression coverage
- Affected behavior:
  - Continuous transcription reliability during long sessions with multiple finalizations
- Dependencies/APIs:
  - No new external dependencies expected
  - Uses existing STT/TTS worker event contracts
