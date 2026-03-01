## 1. Baseline and test coverage (TDD)

- [x] 1.1 Review existing LiveView UI/tests for `SttPlaygroundWeb.SttLive` and identify what will break (TDD baseline)
- [x] 1.2 Add/adjust LiveView tests to cover the new chat timeline empty-state and role rendering (TDD)
- [x] 1.3 Add/adjust LiveView tests to cover composer behavior (draft reflects `active_turn_text`, edits update it) (TDD)

## 2. Chat-first layout and components

- [x] 2.1 Refactor `SttLive.render/1` into a chat layout (timeline + status header + composer) while keeping existing actions working
- [x] 2.2 Implement message rendering (bubble/block) for `user` and `assistant` with accessible role labels
- [x] 2.3 Implement an empty-state for the timeline when there are no messages
- [x] 2.4 Integrate the existing status indicators into a compact chat header/status area
- [x] 2.5 Ensure the clear action resets both timeline and composer UI (and remains obvious in the chat layout)

## 3. Chat scroll ergonomics

- [x] 3.1 Add a minimal JS hook for “stay at bottom” auto-scroll when new messages arrive
- [x] 3.2 Add “Jump to latest” behavior when the user has scrolled up (no forced scroll)
- [x] 3.3 Add/adjust tests or targeted assertions to ensure the DOM includes the required elements/ids for the scroll behavior

## 4. Verification

- [x] 4.1 Manual verification: start/stop mic still works and the composer draft updates during live transcription
- [x] 4.2 Manual verification: submitting a turn adds a user message; AI reply appears as an assistant message in the timeline
- [x] 4.3 Manual verification: auto-scroll works at bottom; scrolling up prevents forced scrolling; “Jump to latest” brings you back down
- [x] 4.4 Accessibility verification: role labels and status indicators have appropriate accessible text and sensible focus order

## 5. Final verification by the user

- [x] 5.1 Confirm the screen "feels like a chat": readable history, clear roles, and an obvious place to speak/type the next message
- [x] 5.2 Confirm the conversation history is usable for longer exchanges (scrollback + jump-to-latest) without losing where you were reading
