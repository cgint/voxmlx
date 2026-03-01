# Deliver a chat-first STT playground UI with a readable conversation timeline

## Context

The current `stt_playground` UI (`SttPlaygroundWeb.SttLive`) already maintains turn-based state (`active_turn_text`, `conversation_history`) but presents it primarily as a “Transcript” textarea with a small conversation snippet below it. This makes the primary workflow (talk → see text → get an AI reply) feel unlike the chat interfaces users are familiar with.

Constraints / notes:
- This is a Phoenix LiveView app; the UI should be implemented primarily in server-rendered HEEx with minimal JS.
- Existing status indicators/components (on-air, transcribing, thinking, speaking) should remain accessible and visible.
- This change should focus on presentation + interaction ergonomics, not on changing STT/AI semantics.

## Goals / Non-Goals

**Goals:**
- Present the interaction as a familiar chat UI:
  - a primary scrollable message timeline
  - distinct styling for user vs assistant messages
  - clear ordering and role labeling
- Make the “active turn” feel like a chat composer:
  - the current transcription/typed text sits at the bottom as the next message draft
  - existing actions (mic start/stop, clear, “Run AI + Speak”) are placed in expected locations
- Improve long-conversation usability:
  - auto-scroll to latest by default
  - provide an explicit “Jump to latest” affordance when the user scrolls up
- Preserve accessibility (ARIA labels on indicators, readable focus order).

**Non-Goals:**
- Persisting conversation history across page reloads or browser sessions.
- Multi-user chat, accounts, or sharing.
- Changing the STT/AI pipeline behavior, segmentation, or timing.
- Full mobile-responsive polish (we can keep reasonable responsiveness, but it’s not the primary deliverable).

## Decisions

### Use existing conversation state; optionally move rendering to LiveView streams for performance
- **Decision:** Keep `conversation_history` as the source of truth initially; if rendering becomes expensive, migrate to `Phoenix.LiveView.stream/3` for message append operations.
- **Rationale:** The feature is UI-first; minimizing state refactors reduces risk. LiveView streams remain available if we see performance issues with long histories.
- **Alternatives considered:**
  - Switch immediately to streams: better scalability, but adds complexity and requires more changes in tests and event handlers.

### Build a dedicated chat layout with composable components
- **Decision:** Extract chat presentation into components (e.g. message bubble, timeline, composer) under `stt_playground_web/components/`.
- **Rationale:** Keeps `SttLive` readable and encourages consistent styling and accessibility.
- **Alternatives considered:**
  - Keep all HEEx in `SttLive.render/1`: fastest short-term, but harder to maintain as the UI grows.

### Auto-scroll behavior is handled via a small LiveView hook
- **Decision:** Implement a JS hook that:
  - auto-scrolls the timeline to bottom when new messages arrive and the user is already at/near the bottom
  - detects when the user scrolls up and reveals a “Jump to latest” button
- **Rationale:** This is a common chat pattern and difficult to achieve purely in server-rendered HTML without JS.
- **Alternatives considered:**
  - No auto-scroll: simpler but frustrating during live transcription and reply streaming.

### Integrate status indicators into a chat header/status bar
- **Decision:** Move the on-air/transcribing/thinking/speaking indicators into a compact header area above the chat timeline (or pinned at top of the chat card).
- **Rationale:** Keeps critical runtime state visible without competing with message content.

## Risks / Trade-offs

- **[Risk] Auto-scroll interrupts reading older messages** → **Mitigation:** only auto-scroll when user is near bottom; show “Jump to latest” when they scroll up.
- **[Risk] Long conversation re-render cost** → **Mitigation:** cap rendered messages (with a “load more” later) or migrate to LiveView streams if needed.
- **[Risk] Visual polish takes too long** → **Mitigation:** prioritize functional chat affordances (timeline + composer + scroll behavior) over perfect styling.

## Migration Plan

- Implement new chat layout behind the existing root route (`/`) by refactoring `render/1` and extracting components.
- Update/extend LiveView tests to assert the presence of chat timeline, message roles, and composer behavior.
- Validate manually in the browser that:
  - mic start/stop still works
  - transcript updates appear in the composer
  - submitted turns appear as user messages and AI replies appear as assistant messages
  - scrolling/auto-scroll behavior is sane

## Open Questions

- Do we want to render the in-progress transcript as a “draft bubble” in the timeline (last item) or only in the composer?
- Should we show timestamps (local time) or just message ordering for now?
- How many historical messages should be rendered by default before we need pagination/virtualization?
