## ADDED Requirements

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

#### Scenario: Transcript updates do not immediately create new history entries
- **WHEN** partial/final transcript updates arrive
- **THEN** the active user turn text is updated but no new history message is committed yet

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
