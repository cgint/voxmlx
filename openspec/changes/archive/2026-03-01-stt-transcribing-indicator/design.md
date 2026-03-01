# Make transcription progress legible while audio is being processed

## Diagram

![Transcribing state flow](./transcribing-state-flow.svg)

## Context

The playground UI already exposes a speaking-related “On Air” indicator (driven by `isSpeaking`). In practice, STT results (partial/final) can arrive with noticeable and variable latency after a user finishes an utterance. During that time, the transcript may still change, but the UI does not communicate whether the system is still processing audio or is already caught up.

We want a second indicator that answers a simple user question: “Is the app still transcribing something I already said?”

Constraints / current architecture (relevant parts):
- Audio chunks come from the browser via the `MicStreamer` hook and are delivered to `SttLive` as `"audio_chunk"` events.
- The app forwards audio to a Python STT worker via `SttPlayground.STT.PythonPort`.
- The worker sends transcript updates back as `{:stt_event, %{"event" => "partial"|"final", ...}}`.
- Speech activity (`isSpeaking`) is derived server-side from audio RMS (with hysteresis/debounce).

## Goals / Non-Goals

**Goals:**
- Add an explicit “Transcribing…” (or equivalent) indicator in the LiveView UI.
- Define a deterministic rule for computing a boolean transcription-processing state (e.g. `isTranscribing`) that is meaningful to users.
- Keep the “Transcribing…” indicator semantically distinct from “On Air”:
  - “On Air” = user is currently speaking (capture)
  - “Transcribing…” = user is not speaking, but the system is still expected to emit transcript updates for already-forwarded audio
- Ensure accessible labeling so screen readers can announce whether transcription is in progress.

**Non-Goals:**
- Introducing a new STT backend protocol (e.g. explicit “processing_started/processing_done” events) unless strictly necessary.
- Building a full per-utterance queue/acknowledgement system for audio chunks.
- Changing STT accuracy or model behavior.

## Decisions

### Decision: Drive “transcribing” primarily from speech-end → final behavior
We will treat transcription as “in progress” mainly in the common user-observable window:
- user finishes speaking (speech activity turns OFF), and
- a final transcript update has not been received yet.

This matches the user’s mental model (“I already said it; is it still being turned into text?”) and avoids flicker during continuous speaking.

**Proposed state model (high level):**
- Add assigns/state:
  - `awaiting_final?` (or `is_transcribing`) boolean
  - `had_audio_forwarded_since_last_final?` boolean (or equivalent)
- Transition rules (session-scoped):
  - When speech becomes active (`isSpeaking` transitions `false -> true`): clear `isTranscribing` (indicator not shown while speaking)
  - When speech becomes inactive (`true -> false`) AND we have forwarded audio for this utterance: set `isTranscribing=true`
  - When STT `final` is received for the active session: set `isTranscribing=false`
  - When recording stops or errors: set `isTranscribing=false`

**Alternatives considered:**
1) **Pure time-based heuristic** (`last_audio_sent_at` vs `last_transcript_at`):
   - Pros: no need to reason about “utterances”
   - Cons: can flicker on/off with every chunk and transcript update; user-unfriendly
2) **Backend-driven explicit processing events**:
   - Pros: most accurate signal
   - Cons: requires protocol changes in the Python worker; larger scope

We choose the speech-end-driven model as the best effort/lowest-scope approach that still matches user expectation.

### Decision: Keep computation server-side and unit-testable
To keep behavior deterministic and testable, the transcription-processing logic should be implemented as a small state machine (similar in spirit to `SpeechActivityState`) and driven by discrete events (speech transitions, forwarded audio, partial/final).

This can initially live as:
- a tiny module under `SttPlayground.STT.*` (preferred), or
- directly inside `SttLive` with a follow-up refactor if it grows.

### Decision: UI placement and copy
- Place the new indicator near the existing On Air indicator.
- Copy: default to `Transcribing…`.
- The indicator should be visually “secondary” to On Air (e.g. neutral/spinner) to avoid implying recording.

## Risks / Trade-offs

- **Risk: indicator gets stuck ON if `final` never arrives** → Mitigation: clear `isTranscribing` when recording stops; optionally add a conservative timeout (e.g. clear after N seconds without any STT events) and surface an error/status.
- **Risk: ambiguity between partial vs final semantics** → Mitigation: define the indicator strictly in terms of “awaiting final after speech end”; do not toggle based on partials.
- **Trade-off: best-effort signal**: Without backend acknowledgements, “transcribing” is derived from observable UI/STT events; it may not represent exact backend compute state, but it is still useful for user expectations.
