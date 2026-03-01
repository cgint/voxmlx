## Why

When speech-to-text is activated, users currently don’t have an immediate, glanceable signal that the system is actually detecting their voice activity. This creates uncertainty ("is it listening?" / "did it hear me?") and makes it harder to self-correct (mic muted, too quiet, etc.).

## What Changes

- Add a small “On Air” indicator UI element that is visibly **inactive/gray** by default and **lights up** while the user is detected as speaking.
- Introduce a minimal, testable “speech activity” state (speaking vs. not speaking) that is driven by the existing speech-to-text audio pipeline when STT is enabled.
- Ensure transitions are stable (avoid flicker) via simple debouncing / hysteresis.
- No API removals and no breaking changes expected.

## Capabilities

### New Capabilities
- `speech-activity-state`: Provide a single source of truth for whether the user is currently speaking (while STT is active), with stable transitions suitable for UI and tests.
- `on-air-indicator-ui`: Render an “On Air” indicator that reflects the speech activity state (active when speaking, inactive otherwise).

### Modified Capabilities
- (none)

## Impact

- Frontend UI: add a small component (div/SVG) and minimal styling.
- Audio/STT integration: tap into the existing STT audio stream or its callbacks to derive speaking/not-speaking.
- Testing: add unit tests for the speech activity state machine (server-side runnable) and component tests for UI state rendering.
