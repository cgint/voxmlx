# voice-turn-auto-submit Specification

## Purpose
TBD - created by archiving change auto-submit-after-silence. Update Purpose after archive.
## Requirements
### Requirement: End-of-turn detection is conservative and uses combined signals
The system SHALL detect end-of-user-turn conservatively using combined signals, not speech activity alone.

The system SHALL treat **3 seconds** as a minimum pause window before auto-submitting when a `final` segment has been observed.

If no `final` is observed, the system SHALL use a fallback minimum pause window of **3 seconds** (measured as transcript stability while speech is inactive).

Both pause windows SHALL be configurable (e.g., `min_pause_after_final_ms` default 3000 and `fallback_stable_without_final_ms` default 3000).

#### Scenario: On Air turns inactive but transcript is still changing
- **GIVEN** speech activity transitions to inactive
- **WHEN** transcript partial/final updates continue to change the active turn text
- **THEN** the end-of-turn countdown does not start

#### Scenario: Final segment is preferred as “text settled”
- **GIVEN** STT emits `final` events for segments while recording continues
- **WHEN** a `final` is received for the current utterance and speech remains inactive
- **THEN** the system considers the utterance eligible for end-of-turn countdown (subject to pause window)

#### Scenario: Fallback when final is delayed
- **GIVEN** speech activity is inactive and no `final` has been received for the current utterance
- **WHEN** the transcript has remained unchanged for at least **3 seconds**
- **THEN** the system treats the utterance as eligible and proceeds with auto-submit without waiting for `final`

#### Scenario: Countdown is measured from last transcript change
- **GIVEN** speech activity is inactive and the utterance is eligible for countdown
- **WHEN** the transcript stops changing
- **THEN** the system measures the minimum 3-second pause window from the timestamp of the last transcript change

#### Scenario: Transcript changes while countdown is pending
- **GIVEN** an end-of-turn countdown is pending
- **WHEN** transcript text changes due to new partial/final updates
- **THEN** the countdown is cancelled and may be re-armed only after transcript stability is reached again

#### Scenario: Speech resumes while countdown is pending
- **GIVEN** an end-of-turn countdown is pending
- **WHEN** speech activity becomes active
- **THEN** the countdown is cancelled

### Requirement: Auto-submit triggers exactly one turn commit and AI run
When end-of-turn conditions are satisfied, the system SHALL submit exactly one discrete user turn.

#### Scenario: End-of-turn triggers AI response
- **GIVEN** recording is active and the active user turn text is non-empty
- **WHEN** end-of-turn conditions remain satisfied for at least 3 seconds (or 6 seconds when `final` is missing and fallback applies)
- **THEN** the system commits the active user turn as a new user message and triggers the same AI+TTS response flow used by the manual "Run AI + Speak" action

### Requirement: Auto-submit uses guardrails to prevent invalid or duplicate runs
The system SHALL validate preconditions before executing auto-submit so that empty or repeated submissions are not processed.

#### Scenario: Empty active turn is not submitted
- **WHEN** end-of-turn conditions are satisfied but active user turn text is empty or whitespace only
- **THEN** the system does not trigger AI processing

#### Scenario: Duplicate user turn is not re-submitted
- **GIVEN** the most recent submission already committed user turn snapshot X
- **WHEN** end-of-turn detection would trigger again with the same effective snapshot X
- **THEN** the system does not trigger a second AI request for snapshot X

#### Scenario: In-flight processing blocks additional auto-submit
- **GIVEN** an AI+TTS run is already in progress
- **WHEN** end-of-turn conditions are satisfied again
- **THEN** the system avoids starting a concurrent duplicate run

### Requirement: Manual trigger remains available as fallback
The system SHALL keep the manual "Run AI + Speak" trigger available.

#### Scenario: User manually triggers immediate response
- **WHEN** the user clicks "Run AI + Speak" with non-empty active user turn text
- **THEN** the system triggers AI+TTS immediately without waiting for end-of-turn countdown

### Requirement: Conversation activity feedback shows overlapping states separately
The system SHALL provide clear UX feedback using **separate indicators** for overlapping states, so that “On Air / speaking” is never hidden by other phases (e.g., transcribing/finalizing).

At minimum, the UI SHOULD provide separate indicators for:
- **On Air** (speech activity)
- **Transcribing/Finalizing** (STT still catching up)
- **Auto-submit countdown** (time remaining; cancels/resets on speech resumption or transcript churn)
- **AI/TTS progress** (thinking / speaking reply)

#### Scenario: UI shows On Air even while finalizing previous audio
- **GIVEN** `is_transcribing` is true (previous audio is still being processed)
- **WHEN** speech activity becomes active again (`is_speaking` becomes true)
- **THEN** the UI shows the On Air indicator as active, without hiding the Transcribing/Finalizing indicator

#### Scenario: UI indicates finalizing vs countdown
- **WHEN** speaking has stopped but a final segment has not yet been observed and/or transcript updates are still arriving
- **THEN** UI feedback indicates the system is finalizing/settling input and countdown has not started

#### Scenario: UI indicates countdown in progress
- **WHEN** speech is inactive, transcript is stable, and countdown is pending
- **THEN** UI feedback indicates countdown is in progress

