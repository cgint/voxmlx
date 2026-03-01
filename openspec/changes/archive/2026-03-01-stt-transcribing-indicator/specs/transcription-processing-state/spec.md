# transcription-processing-state Specification

## ADDED Requirements

### Requirement: Transcription-in-progress state is available while recording is enabled
When speech-to-text (STT) recording is enabled, the system SHALL compute and expose a boolean transcription-processing state (`isTranscribing`) for the active STT session.

For this codebase, **STT recording enabled** means `recording == true` in LiveView.

#### Scenario: Recording disabled
- **WHEN** STT recording is disabled (`recording == false`)
- **THEN** `isTranscribing` is `false`

#### Scenario: Recording enabled and no pending transcription
- **WHEN** STT recording is enabled and the system is not awaiting additional transcript output for previously-forwarded audio
- **THEN** `isTranscribing` is `false`

### Requirement: Speech end implies transcription may still be pending
The system SHALL set `isTranscribing` to `true` when speech activity transitions from active to inactive for the active recording session and additional transcript output may still arrive for already-forwarded audio.

#### Scenario: User stops speaking
- **WHEN** recording is enabled and speech activity transitions from `isSpeaking=true` to `isSpeaking=false`
- **THEN** `isTranscribing` becomes `true`

### Requirement: Transcript output clears transcription-in-progress state
The system SHALL clear `isTranscribing` when it receives an STT transcript update (`partial` or `final`) for the active session after speech has ended.

#### Scenario: Partial arrives after speech ends
- **WHEN** `isTranscribing` is `true` and the app receives a `partial` STT event for the active `session_id`
- **THEN** `isTranscribing` becomes `false`

#### Scenario: Final arrives after speech ends
- **WHEN** `isTranscribing` is `true` and the app receives a `final` STT event for the active `session_id`
- **THEN** `isTranscribing` becomes `false`

### Requirement: Transcribing state does not get stuck indefinitely
The system SHALL clear `isTranscribing` after a bounded fallback timeout if no transcript updates arrive.

#### Scenario: No transcript update arrives
- **WHEN** `isTranscribing` is `true` and no `partial` or `final` STT event arrives for the active `session_id` within the configured timeout
- **THEN** `isTranscribing` becomes `false`

### Requirement: Transcription-in-progress state is scoped to the active session
The system SHALL only update `isTranscribing` for STT events that match the currently active `session_id`.

#### Scenario: Event for old session is ignored
- **WHEN** the app receives a `final` or `partial` STT event with a `session_id` that does not match the active session
- **THEN** `isTranscribing` does not change
