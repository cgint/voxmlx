# Avoid Wasting STT Resources on Silent Audio

## Why

### Summary
The STT playground currently forwards microphone audio continuously to the speech-to-text (STT) backend while recording is enabled, even when the user is not speaking. This causes unnecessary backend work and resource consumption (and can produce no meaningful transcript output) during periods of silence. We should gate backend audio ingestion so that audio is only sent when speech activity indicates the user is speaking, while preserving transcription quality (no clipped leading words) and keeping the existing On Air indicator behavior coherent.

### Original user request (verbatim)
I'd like you to analyze a change where we would like to not stream audio all the time, but only when the user is speaking.  There is an on-air indicator that already has some detection when the user is speaking and when there is no audio. And in case there is no audio, we would actually not need to send information to the speech-to-text backend. Please prepare an openspec change for this and analyze the current situation. We need a smart way of integrating the on-air logic and sending stuff to the backend logic to avoid sending empty audio, which leads to resource consumption for no actual speech-to-text result that can be expected from empty audio or silent audio. To make it more clear

### Current situation (evidence)
- The browser captures microphone audio via an `AudioWorklet` and continuously pushes `audio_chunk` events to LiveView (`stt_playground/assets/js/app.js`).
- LiveView currently forwards every chunk to the Python STT worker regardless of speech activity:
  - `SttPlaygroundWeb.SttLive.handle_event("audio_chunk", ...)` calls `SttPlayground.STT.PythonPort.push_chunk(session_id, pcm_b64)` and only after that updates speaking state (`stt_playground/lib/stt_playground_web/live/stt_live.ex`, around the `audio_chunk` handler).
- The On Air indicator is driven by `SpeechActivityState` computed from the same PCM chunks using RMS energy + hysteresis/debounce (`stt_playground/lib/stt_playground/stt/speech_activity_state.ex`).

### Problem
- Silent audio still produces non-empty PCM chunks. Forwarding them to the STT backend causes avoidable queueing, base64 decoding, chunk accumulation, and (depending on the worker behavior) partial/final transcription work that is unlikely to yield useful text.
- Naively dropping chunks when `isSpeaking == false` can degrade UX by clipping the start of speech because `SpeechActivityState` requires sustained energy for `min_speak_ms` before switching to speaking.

## What Changes

- Gate audio forwarding to the STT backend so that **silent chunks are not sent** while recording is enabled but speech activity is inactive.
- Add a small **pre-roll buffer** so that when speech is detected, the backend still receives the initial audio leading into the speech start (avoiding clipped first words).
- Keep the existing On Air indicator behavior and speech-activity computation as the single source of truth for gating decisions.
- Add observability hooks (telemetry/logging) to measure forwarded vs. dropped chunks and validate that resource usage decreases without harming transcript quality.

## Capabilities

### New Capabilities
- `stt-audio-gating`: Define when microphone audio chunks MUST / MUST NOT be forwarded to the STT backend while recording is enabled, including required pre-roll behavior to preserve transcription quality.

### Modified Capabilities
- (none)

## Impact

- LiveView STT ingest path: `stt_playground/lib/stt_playground_web/live/stt_live.ex` (audio chunk handling + speaking state integration).
- STT port/telemetry: potentially `stt_playground/lib/stt_playground/stt/python_port.ex` (optional metrics for dropped/forwarded chunks) and tests.
- Potential interaction with existing changes that depend on silence (e.g. `openspec/changes/auto-submit-after-silence`) because transcript update cadence will change during long silences.
