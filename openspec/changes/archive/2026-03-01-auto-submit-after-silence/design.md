## Context

The STT playground currently supports continuous recording and streaming transcription, with:
- an On Air indicator driven by server-side speech activity (`is_speaking`),
- transcript updates via STT events (`partial` and `final`),
- a manual button that triggers transcript → AI → TTS.

Recent behavior changes make auto-submit a conversation problem, not a single-shot trigger:
- STT sessions continue after `final` segments ("final" is now a segment boundary, not "stop recording").
- Microphone chunks are gated: audio is forwarded to STT backend only while `isSpeaking==true` (plus pre-roll flush when speech starts).

From a user perspective, auto-submit will cause a back-and-forth interaction style:
- user speaks a turn,
- pauses,
- system answers,
- user speaks again.

To avoid repeatedly submitting the same growing transcript, the system needs explicit **turn commit semantics** and **conversation history**.

Because we want **less premature submits**, end-of-turn detection must be conservative and cannot use On Air alone. Transcription can still settle briefly after speech stops (e.g., trailing partial/final updates).

## Diagram

![Turn-based voice conversation flow](./voice-turn-auto-submit-flow.svg)

## Goals / Non-Goals

**Goals:**
- Maintain an **active user turn buffer** updated by transcript events.
- Maintain an in-memory **conversation history** of discrete `user` and `assistant` messages.
- Auto-submit a turn only when end-of-turn conditions are conservatively satisfied:
  - speech inactive,
  - transcript stable (no changes),
  - `final` for the current segment observed (preferred) OR a clearly-defined fallback for cases where `final` is delayed.
- Commit exactly one user turn per auto-submit; do not repeatedly resend older text as the current input.
- Use bounded history when generating AI prompts.
- Provide clear user feedback via **separate indicators** (chips) for overlapping states (On Air, finalizing/transcribing, auto-submit countdown, AI/TTS).

**Non-Goals:**
- Persistent storage of history.
- Full-feature chat UI.
- Perfect, universal VAD.
- Barge-in (interrupting TTS by speaking) as a hard requirement (can be a follow-up enhancement).

## Decisions

1) **Turn buffers and history are server-side LiveView state**
- Decision: store `active_turn_text` and `conversation_history` in LiveView assigns.
- Rationale: source of truth is centralized and testable; avoids browser/server divergence.

2) **Use `final` segments as a primary “turn text settled” signal**
- Decision: treat STT `final` as the preferred signal that the backend has finalized the current segment.
- Rationale: with session continuity, `final` is the natural segment boundary to avoid submitting mid-chunk.
- Note: `final` alone is not enough; the user might resume speaking immediately. We still require a pause window.

3) **Conservative countdown starts from the last transcript change after `final`**
- Decision: start the end-of-turn countdown only when:
  - speech is inactive,
  - transcript has not changed since the last observed update,
  - and a `final` has been received for the current segment.
  Countdown duration is >= 3 seconds and is measured from the last transcript change timestamp.
- Rationale: reduces premature submits and accounts for post-speech settling.
- Config: expose this as `min_pause_after_final_ms` (default: 3000).

4) **Fallback when `final` is delayed**
- Decision: define an explicit fallback path (to prevent “never respond”): if speech is inactive and the transcript has been stable for **3 seconds** (default) without receiving `final`, the system SHALL proceed with auto-submit.
- Rationale: conservatism must not block responses entirely.
- Config: expose this as `fallback_stable_without_final_ms` (default: 3000).

5) **Commit semantics: active turn → history once per submit**
- Decision: on manual or auto submit, commit the current active turn as a new `user` message, then generate AI response, commit it as an `assistant` message, then reset the active turn.
- Add dedupe guard keyed by last-committed user snapshot to avoid repeated submits.

6) **Prompt assembly uses bounded history**
- Decision: build AI input from system instructions + last N history messages + latest committed user turn.
- Rationale: stable conversational behavior and bounded prompt growth.

7) **Separate activity indicators (overlapping states)**
- Decision: show separate indicators (chips) for:
  - **On Air** (speech activity; whether the user is currently speaking),
  - **Transcribing/Finalizing** (backend still processing forwarded speech into text),
  - **Auto-submit countdown** (time remaining until auto-submit; cancels/resets on speech or transcript churn),
  - **Thinking / Speaking reply** (AI and TTS pipeline progress).
- Rationale: these states can overlap (e.g., user starts speaking again while the previous turn is still finalizing). Separate indicators prevent hiding critical feedback like “you are speaking now”.

## Risks / Trade-offs

- **[Risk] Premature submits on mid-thought pauses** → **Mitigation:** conservative countdown start (after `final` + stability) and longer fallback; keep manual override.
- **[Risk] No response if `final` never arrives** → **Mitigation:** explicit fallback rule.
- **[Risk] History grows unbounded** → **Mitigation:** cap history length (last N); summarization later if needed.
- **[Risk] State complexity** → **Mitigation:** centralize in a small set of assigns and test state transitions.
