## MODIFIED Requirements

### Requirement: Transcription-in-progress state is available while recording is enabled
When speech-to-text (STT) recording is enabled, the system SHALL compute and expose a boolean transcription-processing state (`isTranscribing`) for the active STT session.

For this codebase, **STT recording enabled** means `recording == true` in LiveView.

In addition, when a user-triggered AI+TTS response run occurs, the system SHALL expose a terminal TTS-answer processing status (`ttsAnswerStatus`) for the same interaction lifecycle with values `success`, `recovered_success`, or `error`.

#### Scenario: Recording disabled
- **WHEN** STT recording is disabled (`recording == false`)
- **THEN** `isTranscribing` is `false`

#### Scenario: Recording enabled and no pending transcription
- **WHEN** STT recording is enabled and the system is not awaiting additional transcript output for previously-forwarded audio
- **THEN** `isTranscribing` is `false`

#### Scenario: TTS answer generation ends in terminal success
- **WHEN** AI+TTS processing for a user turn produces a usable answer (directly or via recovery)
- **THEN** `ttsAnswerStatus` is set to `success` or `recovered_success` and exposed to the UI

#### Scenario: TTS answer generation ends in terminal error
- **WHEN** AI+TTS processing cannot produce a usable answer after configured recovery attempts
- **THEN** `ttsAnswerStatus` is set to `error` and exposed to the UI with an explicit failure state