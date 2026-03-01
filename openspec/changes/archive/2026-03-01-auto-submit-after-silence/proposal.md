# Make Voice Conversations Natural with Turn-Based History and Conservative Auto-Submit

## Why

### Summary
The STT playground is evolving from a single-shot workflow (transcribe → click "Run AI + Speak") into a conversational voice interface. With auto-submit, users will naturally speak in turns and expect the system to respond after a pause. To make this feel natural and avoid repeatedly sending a growing transcript, we need explicit **turn boundaries** and a structured **conversation history**.

Recent code changes made this more important:
- STT sessions now continue after receiving a `final` segment ("final" no longer ends recording).
- Audio is gated: microphone chunks are forwarded to the STT backend only while speech activity is active (with pre-roll flush on speech start).

Because we want **less premature submits**, end-of-turn detection must be conservative and cannot rely only on speech activity (On Air). Transcription can still be settling after the user stops speaking.

### Original user request (verbatim)
I need us to find a way to make the whole process of speaking and answering more natural. Specifically, when the user makes some pause, let's say three seconds, without speaking any more, then the process of AI getting the input and answering it should be started automatically without the need for the user to click the button "Run AI + speak".

## What Changes

- Introduce a turn-based conversation model:
  - **Active turn buffer**: mutable text updated by partial/final STT segments.
  - **Conversation history**: committed sequence of discrete `user` and `assistant` messages.
- Auto-submit: trigger AI automatically when an end-of-turn is detected, without requiring the user to click "Run AI + Speak".
- Conservative end-of-turn detection:
  - start the 3-second countdown only when speech is inactive **and** transcript has settled,
  - use `final` segments as a strong signal that the current utterance has completed,
  - cancel/restart countdown on resumed speech or incoming transcript updates,
  - fallback: if `final` is delayed, submit after **3 seconds** of transcript stability while speech remains inactive.
- Prevent duplicate submissions: each auto-submit commits exactly one new user turn.
- Keep manual triggering as an explicit override for users who want an immediate response.
- Provide clear user feedback via **separate indicators** for overlapping states: On Air (speaking), transcribing/finalizing, auto-submit countdown, and AI/TTS progress.

## Capabilities

### New Capabilities
- `voice-turn-auto-submit`: Conservatively detect end-of-user-turn and auto-trigger AI response generation.
- `voice-conversation-history`: Maintain structured in-memory conversation history and build AI prompts from discrete turns.

### Modified Capabilities
- None.

## Impact

- LiveView state: new assigns for active turn, history, transcript timing, countdown timer, and dedupe/in-flight guards.
- AI invocation: prompt assembly changes to use bounded conversation history instead of a single cumulative transcript.
- UX: status/indicators should reflect conversation phases (speaking, transcribing/finalizing, waiting-to-send, thinking, speaking response).
- Tests: add coverage for conservative timer semantics (including `final`), turn commit behavior, and no duplicate submissions.
