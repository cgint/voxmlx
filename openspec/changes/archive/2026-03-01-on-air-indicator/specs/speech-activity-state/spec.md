## ADDED Requirements

### Requirement: Speaking state is available while STT is enabled
When speech-to-text (STT) is enabled, the system SHALL compute and expose a boolean speaking state (`isSpeaking`) for the current user.

For this codebase, **STT enabled** means the active recording/streaming state is `true` (currently `recording == true` in LiveView).

#### Scenario: STT enabled and user starts speaking
- **WHEN** STT is enabled and speech activity is detected
- **THEN** `isSpeaking` becomes `true`

#### Scenario: STT disabled
- **WHEN** STT is disabled (`recording == false`)
- **THEN** `isSpeaking` is `false`

### Requirement: Speech activity signal source has deterministic priority
The system SHALL use speech-activity inputs in this priority order:
1) engine-provided speech start/end events (if available),
2) otherwise a simple audio-energy heuristic on existing STT audio chunks.

#### Scenario: Engine events unavailable
- **GIVEN** the STT worker does not provide speech start/end events
- **WHEN** STT is enabled
- **THEN** speech activity is derived from audio-energy samples

### Requirement: Speaking state changes are stable (no flicker)
The system SHALL apply hysteresis/debouncing so that brief noise/silence does not cause rapid toggling of `isSpeaking`.

#### Scenario: Brief pause does not immediately turn OFF
- **WHEN** `isSpeaking` is `true` and a short silence shorter than the configured minimum silence duration occurs
- **THEN** `isSpeaking` remains `true`

#### Scenario: Sustained silence turns OFF
- **WHEN** `isSpeaking` is `true` and sustained silence longer than the configured minimum silence duration occurs
- **THEN** `isSpeaking` becomes `false`

#### Scenario: Stop request forces OFF
- **WHEN** STT transitions from enabled to disabled
- **THEN** `isSpeaking` becomes `false` immediately or within the configured OFF debounce window

### Requirement: Speech activity logic is unit-testable without browser APIs
The speech activity logic SHALL be implementable as a deterministic, side-effect free unit (e.g., reducer/state machine) that can be tested in a server-side test runner (e.g., ExUnit) by providing a sequence of input samples/events and timestamps.

#### Scenario: Deterministic output for the same inputs
- **WHEN** the speech activity unit is driven by the same ordered inputs (events/samples + timestamps)
- **THEN** it produces the same sequence of `isSpeaking` state changes
