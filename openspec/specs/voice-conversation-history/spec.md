# voice-conversation-history Specification

## Purpose
TBD - created by archiving change auto-submit-after-silence. Update Purpose after archive.
## Requirements
### Requirement: System maintains a structured in-memory conversation history
The system SHALL maintain an in-memory conversation history as an ordered list of discrete messages.

Each message SHALL include a role (`user` or `assistant`) and message content.

#### Scenario: History starts empty for a new session
- **WHEN** a new STT/voice interaction session starts
- **THEN** conversation history is empty

#### Scenario: Manual clear resets history
- **WHEN** the user triggers a clear/reset action
- **THEN** conversation history is cleared and the active user turn is reset

### Requirement: Active user turn is separate from committed history
The system SHALL maintain a separate active user turn buffer that is updated by transcript events and only committed at turn submission.

The system SHALL treat each incoming transcript update (partial or final) as an authoritative update for the active user turn text for the current turn (i.e., update-by-replacement), not as text to be concatenated onto the existing active turn.

The system SHALL ensure that previously committed conversation history is not re-introduced into the active user turn as duplicated prefixes when an STT session continues across multiple turns.

#### Scenario: Transcript updates do not immediately create new history entries
- **WHEN** partial/final transcript updates arrive
- **THEN** the active user turn text is updated but no new history message is committed yet

#### Scenario: Partial/final updates replace (not append) active turn text
- **GIVEN** the active user turn text is `"Hello"`
- **WHEN** a new transcript update arrives with effective text `"Hello, sir"`
- **THEN** the active user turn text becomes `"Hello, sir"` (and does not become `"HelloHello, sir"`)

#### Scenario: New turn does not include previously committed text as a prefix
- **GIVEN** the most recently committed user message content is `"Hello, sir."`
- **AND** the next user turn begins
- **WHEN** an STT transcript update arrives that still contains the earlier session text as a prefix (e.g., `"Hello, sir. Can you please tell me what..."`)
- **THEN** the active user turn text reflects only the new turn content (e.g., `"Can you please tell me what..."`) and does not repeat `"Hello, sir."`

### Requirement: Submitting a turn commits user message then assistant message
When a user turn is submitted (auto-submit or manual), the system SHALL commit a new `user` message using the submitted turn text, then generate a response and commit a new `assistant` message.

#### Scenario: Auto-submit commit sequence
- **WHEN** auto-submit triggers on end-of-turn
- **THEN** the system appends a `user` message to history, generates an AI response, and appends an `assistant` message to history

#### Scenario: Manual submit commit sequence
- **WHEN** the user manually triggers "Run AI + Speak"
- **THEN** the system appends a `user` message to history, generates an AI response, and appends an `assistant` message to history

### Requirement: AI prompt is built from bounded conversation history
The system SHALL build AI input using discrete conversation history rather than resending the entire cumulative transcript.

#### Scenario: Prompt includes recent turns
- **GIVEN** conversation history contains multiple turns
- **WHEN** generating a new response
- **THEN** the prompt includes the most recent turns up to a defined limit (e.g., last N messages) plus the newly committed user turn

