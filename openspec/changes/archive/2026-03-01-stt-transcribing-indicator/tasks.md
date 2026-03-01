## 1. Baseline + TDD

- [x] 1.1 Review existing LiveView/UI components and tests for STT indicator rendering (TDD: identify best place to add new failing tests)
- [x] 1.2 Add failing LiveView test coverage for a “Transcribing…” indicator driven by `isTranscribing` (TDD)

## 2. Transcription-processing state (`isTranscribing`)

- [x] 2.1 Introduce LiveView state/assign(s) needed to track transcription-in-progress for the active `session_id` (e.g. `:is_transcribing` plus minimal supporting fields)
- [x] 2.2 Update speech-activity / audio-chunk handling to set `isTranscribing=true` on the speech-active → speech-inactive transition when an utterance has been forwarded
- [x] 2.3 Update STT event handling to clear `isTranscribing` on `final` (active `session_id` only) and to clear on stop/error paths

## 3. UI indicator

- [x] 3.1 Implement a `TranscribingIndicator` UI component (visual + accessible label) that renders only when `isTranscribing=true`
- [x] 3.2 Integrate the new indicator into the `SttLive` UI near the existing On Air indicator without changing On Air semantics

## 4. Verification

- [x] 4.1 Run the automated test suite and ensure the new tests pass
- [x] 4.2 Manually verify in the browser: speak a short utterance, stop speaking, confirm “Transcribing…” shows until the transcript updates/final arrives, then disappears

## 5. Final verification by the user

- [x] 5.1 User verifies the indicator meaning is intuitive: “On Air” reflects speaking; “Transcribing…” reflects pending transcript work after speaking stops
- [x] 5.2 User verifies accessibility expectations: the transcribing indicator is announced meaningfully by screen reader tooling (or at minimum has an appropriate aria-label)
