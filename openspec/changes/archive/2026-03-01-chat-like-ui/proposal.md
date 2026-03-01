# Make the STT playground feel like a familiar chat app (with readable conversation history)

## Why

### Summary
The current STT playground UI exposes the transcription turn as a textarea and shows only a small “Conversation” snippet, which makes it feel like a debugging tool rather than a chat experience. Users who are accustomed to chat interfaces expect a scrollable message history, clear “who said what”, and an obvious place to speak/type the next message.

### Original user request (verbatim)
I want the user interface to be more of a chat-like interface with conversation history, as it is known out there to users usually using chat interfaces. Please think about this, create an openspec change, and think from the user's perspective.

## What Changes

- Restructure the STT playground’s main screen into a chat-style layout:
  - A primary, scrollable conversation timeline (chat history) with clear visual separation between user and assistant turns.
  - A persistent “composer” area for the current user turn (voice transcription / typed text) positioned like a typical chat input.
- Improve conversation readability and scannability:
  - Message bubbles (or similarly distinct blocks), timestamps/sequence ordering, and consistent role labeling.
  - Better handling for long conversations (scrollback, optional auto-scroll to latest, and “jump to latest”).
- Make voice/STT status indicators feel like part of a chat product rather than raw telemetry:
  - Keep “on air”, “transcribing/finalizing”, “thinking…”, and “speaking reply…” visible but integrated into the chat header/status area.
- Keep existing functionality (start/stop mic, clear, run AI + speak) but present it in a chat-first way.

## Capabilities

### New Capabilities
- `chat-conversation-ui`: The STT playground UI presents the interaction as a chat conversation, with a usable conversation history and a chat-like composer for the active turn.

### Modified Capabilities
- (none)

## Impact

- UI code: `stt_playground/lib/stt_playground_web/live/stt_live.ex` (render/layout and event wiring).
- UI components: `stt_playground/lib/stt_playground_web/components/*` (new/updated components for message bubbles, history list, status header).
- Frontend behavior: possible small JS hook adjustments for auto-scroll / “jump to latest” behavior.
- Tests: LiveView tests (e.g. `stt_playground/test/stt_playground_web/live/stt_live_test.exs`) may need updates and new coverage for the chat layout and history behavior.
