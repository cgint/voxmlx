# chat-conversation-ui Specification

## Purpose
TBD - created by archiving change chat-like-ui. Update Purpose after archive.
## Requirements
### Requirement: Chat timeline shows the full conversation history for the current session
The UI SHALL render a primary, scrollable chat timeline that displays all conversation messages for the current session in chronological order.

#### Scenario: No conversation yet
- **WHEN** the conversation history is empty
- **THEN** the UI renders an empty-state in the chat timeline indicating there are no messages yet

#### Scenario: Conversation contains multiple messages
- **WHEN** the conversation history contains multiple messages
- **THEN** the UI renders each message in chronological order (oldest to newest)

### Requirement: Each chat message clearly communicates the role (user vs assistant)
Each rendered chat message SHALL visibly and accessibly indicate the message role (at minimum: `user` and `assistant`).

#### Scenario: Rendering a user message
- **WHEN** a message with role `user` is rendered
- **THEN** it is visually distinct from assistant messages and includes an accessible role label identifying it as a user message

#### Scenario: Rendering an assistant message
- **WHEN** a message with role `assistant` is rendered
- **THEN** it is visually distinct from user messages and includes an accessible role label identifying it as an assistant message

### Requirement: The active turn is presented as a chat-style composer
The UI SHALL provide a persistent composer area for the active user turn where live transcription and typed edits appear as a draft.

#### Scenario: Live transcription updates the draft
- **WHEN** the active turn text changes due to transcription updates
- **THEN** the composer draft content updates to match the active turn text

#### Scenario: User edits the draft
- **WHEN** the user types into the composer
- **THEN** the active turn text is updated to reflect the user’s edits

### Requirement: Submitting a turn adds it to the timeline as a user message
When the active user turn is submitted, the UI SHALL add it to the chat timeline as a user message.

#### Scenario: Manual submit
- **WHEN** the user submits the active turn via the UI
- **THEN** the submitted text appears in the chat timeline as a new user message

#### Scenario: Auto-submit
- **WHEN** the system auto-submits the active turn
- **THEN** the submitted text appears in the chat timeline as a new user message

### Requirement: Assistant replies appear in the timeline as assistant messages
When an assistant reply is produced for the submitted user turn, the UI SHALL display the reply in the chat timeline as an assistant message.

#### Scenario: Reply produced
- **WHEN** an assistant reply is produced
- **THEN** the reply appears in the chat timeline as a new assistant message

### Requirement: Chat timeline supports “stay at bottom” behavior with an explicit jump-to-latest affordance
The UI SHALL keep the chat timeline scrolled to the most recent message when the user is already at (or near) the bottom.
If the user has scrolled up, the UI SHALL NOT force-scroll on new messages and SHALL provide a “Jump to latest” control.

#### Scenario: New message arrives while user is at bottom
- **WHEN** a new message is added and the user is at (or near) the bottom of the chat timeline
- **THEN** the chat timeline scroll position moves to show the newest message

#### Scenario: New message arrives while user is reading older messages
- **WHEN** a new message is added and the user is not at (or near) the bottom of the chat timeline
- **THEN** the chat timeline scroll position does not change and a “Jump to latest” control is made available

### Requirement: Conversation status indicators are visible in a chat-style header area
The UI SHALL display the runtime interaction indicators (on-air/recording, transcribing/finalizing, thinking, speaking reply) in a compact status area that is visually associated with the chat.

#### Scenario: Recording is active
- **WHEN** recording is enabled
- **THEN** the UI shows an on-air indicator in the chat status area

#### Scenario: Assistant is thinking
- **WHEN** an assistant response is in progress
- **THEN** the UI shows a thinking indicator in the chat status area with an accessible status label

### Requirement: Clearing resets the chat timeline and composer
The UI SHALL provide a clear action that resets the current conversation history and clears the active turn draft.

#### Scenario: Clear conversation
- **WHEN** the user activates the clear action
- **THEN** the chat timeline becomes empty and the composer draft is cleared

