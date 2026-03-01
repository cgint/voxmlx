# voice-conversation-history Specification (Delta)

## MODIFIED Requirements

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
