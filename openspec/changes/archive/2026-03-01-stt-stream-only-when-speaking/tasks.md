## 1. Baseline + TDD setup

- [x] 1.1 Review current audio pipeline in `SttLive` (`handle_event("audio_chunk")`) and confirm where speech activity (`SpeechActivityState`) is computed (TDD: identify/extend the most appropriate existing test module(s) before changing code).
- [x] 1.2 Extend the existing `FakeSttPort` in `stt_playground/test/stt_playground_web/live/stt_live_test.exs` to record forwarded `:audio_chunk` casts so tests can assert which chunks were forwarded vs dropped.

## 2. Implement STT audio gating with pre-roll

- [x] 2.1 Add LiveView assigns and configuration for audio gating (e.g. `pre_roll_ms` or `pre_roll_max_chunks`) with safe defaults.
- [x] 2.2 Refactor `handle_event("audio_chunk")` to compute RMS + update `SpeechActivityState` first, then apply gating rules:
  - drop backend forwarding while not speaking
  - buffer chunks into pre-roll while not speaking
  - flush pre-roll (in order) on not-speaking → speaking transition
  - forward chunks while speaking
- [x] 2.3 Ensure stop/error paths clear gating/pre-roll state and keep On Air indicator behavior consistent.

## 3. Observability

- [x] 3.1 Add telemetry/metrics for forwarded chunks, dropped chunks, and pre-roll flushes (minimal counters suitable for local inspection).

## 4. Automated verification

- [x] 4.1 Add ExUnit coverage for `stt-audio-gating` scenarios:
  - silence chunks are not forwarded while recording is enabled and not speaking
  - speech start causes pre-roll flush + forwarding begins
  - sustained silence ends forwarding after `SpeechActivityState` turns OFF
- [x] 4.2 Add a small test helper to generate base64 PCM float32 chunks with “silent” vs “loud” RMS to deterministically drive `SpeechActivityState` transitions.

## 5. Verification + user validation

- [x] 5.1 Verification: run the full automated test suite for the STT playground and ensure no regressions in existing session/indicator behavior.
- [x] 5.2 Verification: manually use the STT playground UI and confirm:
  - On Air indicator still tracks speaking vs silence
  - transcript quality is not clipped at the start of speech
  - backend load/throughput decreases during long silences (via logs/telemetry)
- [x] 5.3 Final verification by the user: speak in short bursts with pauses and confirm that silence does not consume noticeable STT resources while transcripts still include the first words of each burst.
