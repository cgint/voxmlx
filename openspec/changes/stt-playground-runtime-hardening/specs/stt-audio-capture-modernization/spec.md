## ADDED Requirements

### Requirement: AudioWorklet-based microphone capture
The browser client SHALL capture microphone audio using an `AudioWorklet`-based pipeline instead of `ScriptProcessorNode`.

#### Scenario: Recording starts with AudioWorklet pipeline
- **WHEN** the user starts recording in a compatible browser
- **THEN** the client initializes an AudioWorklet and streams audio chunks to the LiveView channel

#### Scenario: AudioWorklet initialization fails
- **WHEN** the AudioWorklet pipeline cannot be initialized
- **THEN** the client reports an actionable error state and does not continue silent capture attempts

### Requirement: Transcript behavior parity during migration
The modernization SHALL preserve existing transcript interaction behavior for start/stop and transcript update flow.

#### Scenario: Start/stop parity
- **WHEN** a user performs start and stop recording actions
- **THEN** the UI and server interaction semantics remain equivalent to the pre-migration flow

#### Scenario: Transcript update parity
- **WHEN** audio is captured and processed successfully
- **THEN** transcript updates continue to appear in the LiveView with no required user workflow change
