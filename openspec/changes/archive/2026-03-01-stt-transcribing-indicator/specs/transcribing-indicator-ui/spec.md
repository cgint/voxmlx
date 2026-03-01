# transcribing-indicator-ui Specification

## ADDED Requirements

### Requirement: Transcribing indicator reflects transcription-processing state while recording is enabled
When STT recording is enabled, the UI SHALL display a transcribing indicator that reflects whether transcription is currently in progress.

For this codebase, **STT recording enabled** means `recording == true`.

#### Scenario: Recording enabled and transcribing
- **WHEN** recording is enabled and `isTranscribing` is `true`
- **THEN** the UI renders a visible indicator communicating “Transcribing…” (or equivalent)

#### Scenario: Recording enabled and not transcribing
- **WHEN** recording is enabled and `isTranscribing` is `false`
- **THEN** the UI does not render the transcribing indicator

#### Scenario: Recording disabled
- **WHEN** recording is disabled (`recording == false`)
- **THEN** the UI does not render the transcribing indicator

### Requirement: Transcribing indicator is accessible
The transcribing indicator SHALL provide an accessible label that communicates whether transcription is in progress.

#### Scenario: Screen reader announces state
- **WHEN** assistive technology announces the indicator
- **THEN** it includes a label that conveys transcription is in progress (e.g. “Transcribing”) when visible
