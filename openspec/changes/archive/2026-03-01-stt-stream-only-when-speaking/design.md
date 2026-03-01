# Reduce STT Backend Work During Silence

## Context

The STT playground streams microphone audio from the browser to a Phoenix LiveView, which forwards audio chunks to a Python STT worker (`stt_port_worker.py`) via `SttPlayground.STT.PythonPort`.

Today, `SttPlaygroundWeb.SttLive` forwards every incoming `audio_chunk` to the STT backend, regardless of whether the user is speaking. In parallel, the UI’s On Air indicator already computes a deterministic `is_speaking` signal using `SttPlayground.STT.SpeechActivityState` (RMS energy + hysteresis/debounce).

This change reuses the existing speech-activity signal as the **single source of truth** to decide when audio should be forwarded to the STT backend, so we avoid paying backend cost for silence while preserving transcript quality.

## Diagram

![STT audio gating flow](./stt-audio-gating-flow.svg)

## Goals / Non-Goals

**Goals:**
- Avoid forwarding silent audio chunks to the STT backend while recording is enabled.
- Preserve transcription quality by preventing clipped leading speech (introduce a small pre-roll buffer).
- Keep the On Air indicator and backend gating decisions consistent (shared `SpeechActivityState`).
- Keep behavior deterministic and testable (server-side logic in LiveView / Elixir).
- Add basic observability to confirm chunks are being dropped/forwarded as intended.

**Non-Goals:**
- Implementing a high-accuracy VAD model.
- Moving speech activity detection to the browser (JS) in this change.
- Changing the STT worker protocol or chunk format.
- Re-architecting session lifecycle (start/stop semantics) beyond gating chunk forwarding.

## Decisions

### 1) Gate at the LiveView → STT backend boundary
**Decision:** Keep browser → LiveView audio streaming unchanged, but conditionally forward (or drop) chunks when sending to `SttPlayground.STT.PythonPort`.

**Rationale:**
- Minimal scope: leverages existing `SpeechActivityState` without duplicating logic in JS.
- Testability: gating decisions can be covered with ExUnit by driving LiveView events.
- Immediate backend cost reduction: Python worker receives fewer chunks and will not run partial/final transcribe work for silence.

**Alternatives considered:**
- **Browser-side gating** (compute energy in JS and only `pushEvent` when speaking). Rejected for now due to logic duplication/drift risk and reduced determinism under browser scheduling.
- **Python-side gating** (run VAD in the worker). Rejected because it still requires transmitting silent audio and increases worker complexity.

### 2) Add a bounded pre-roll buffer to avoid clipping speech onset
**Decision:** When `SpeechActivityState` transitions from not-speaking → speaking, flush a small, bounded buffer of the most recent audio chunks (pre-roll) to the STT backend before forwarding subsequent chunks.

**Rationale:**
- `SpeechActivityState` uses `min_speak_ms` (debounce) before turning ON. Without pre-roll, the first ~N ms of speech would be dropped and can clip words.

**Implementation sketch (conceptual):**
- Maintain a per-session ring buffer in LiveView assigns (e.g. list/queue of `{ts_ms, pcm_b64}`), bounded by `pre_roll_ms` or `pre_roll_max_chunks`.
- For every incoming chunk: always update `SpeechActivityState` from RMS.
- If `is_speaking` is false: enqueue chunk into pre-roll buffer, do not forward.
- If a transition to `is_speaking == true` occurs: flush the buffer in-order to the STT backend, then forward current chunk.
- While `is_speaking == true`: forward chunks as normal.

**Alternatives considered:**
- Forward chunks whenever energy is above a raw threshold, even if not yet “speaking”. Rejected because it partially re-implements speech detection and would forward more noise.

### 3) Let hysteresis/post-roll naturally include trailing speech and brief pauses
**Decision:** Do not introduce a separate post-roll. Continue forwarding while `SpeechActivityState.is_speaking == true`.

**Rationale:**
- The existing state machine already keeps `is_speaking` true across brief pauses and only turns off after sustained silence (`min_silence_ms`). That inherently provides a trailing buffer.

### 4) Keep STT session lifecycle stable; don’t restart sessions on each speech segment
**Decision:** Keep current session start/stop based on explicit Start/Stop actions. Gating only affects chunk forwarding during an active session.

**Rationale:**
- Minimizes risk of unintended interactions with transcript UI state and existing changes (e.g. silence-based auto-submit).
- The Python worker already does near-zero work if no chunks arrive (empty snapshot / empty final).

### 5) Add basic observability for forwarded vs dropped chunks
**Decision:** Emit telemetry (and/or lightweight logging) for:
- forwarded chunks
- dropped (silent) chunks
- pre-roll flush count on speech start

**Rationale:**
- Confirms the change actually reduces chunk throughput and allows tuning pre-roll size.

## Risks / Trade-offs

- **[Risk] Speech onset clipping if pre-roll too small** → **Mitigation:** pick a conservative default (e.g. 300–600ms) and make it configurable.
- **[Risk] False positives (background noise) trigger forwarding** → **Mitigation:** reuse existing `SpeechActivityState` thresholds/hysteresis; tune via config if needed.
- **[Risk] Pre-roll flush burst increases queue depth** → **Mitigation:** keep pre-roll bounded to a small number of chunks; rely on existing bounded queue/backpressure in `PythonPort`.
- **[Trade-off] Browser → server traffic remains unchanged** → acceptable for now; primary goal is avoiding STT backend resource consumption.

## Migration Plan

1. Add new LiveView assigns for pre-roll buffering and gating stats.
2. Update `handle_event("audio_chunk", ...)` to:
   - compute RMS + update `SpeechActivityState` first,
   - decide whether to forward/drop,
   - flush pre-roll on speaking transition.
3. Add tests covering:
   - silence chunks are not forwarded,
   - pre-roll is forwarded when speech starts,
   - forwarding stops after sustained silence.
4. Add telemetry assertions (optional) and ensure existing STT behavior remains stable.

## Open Questions

- Should `pre_roll_ms` be configured in app env (`:stt_playground, :stt_audio_gating`) and/or derived from existing `min_speak_ms`?
- Do we want to (later) also gate browser → LiveView streaming for additional bandwidth savings?
- How should this interact with `auto-submit-after-silence` timing expectations (transcript quiescence may occur sooner when silence chunks are dropped)?
