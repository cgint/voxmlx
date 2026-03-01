## 1. Baseline and TDD Guardrails

- [x] 1.1 Identify current AI+TTS flow modules and existing tests that cover DSPy response parsing, LiveView text-area updates, and status handling (TDD baseline).
- [x] 1.2 Add or update failing tests (TDD) for malformed/truncated JSON, missing `answer`, strict retry behavior, and deterministic terminal outcomes (`success`, `recovered_success`, `error`).

## 2. Strict DSPy Parsing and Retry Logic

- [x] 2.1 Implement failure classification for DSPy answer generation (`output_decode_failed`, `missing_answer_field`, `empty_answer`, `provider_error`, `timeout`).
- [x] 2.2 Implement one bounded retry with stricter response-format constraints for recoverable parse/schema failures.
- [x] 2.3 Enforce no-fallback behavior: if retries fail strict validation, return terminal error without raw-output extraction.

## 3. UI State and Observability Integration

- [x] 3.1 Update LiveView/server state transitions so each AI+TTS request always publishes a terminal `ttsAnswerStatus` and updates text area or explicit error message.
- [x] 3.2 Emit structured logs/telemetry for attempt count, failure class, retry path, and final outcome.
- [x] 3.3 Extend/adjust tests for processing-state semantics and terminal-state delivery to UI.

## 4. Verification and User Confirmation

- [x] 4.1 Verification: run targeted automated tests for DSPy parsing/retry and LiveView state transitions, then run relevant project checks to confirm no regressions.
- [x] 4.2 Verification: manually reproduce the reported malformed JSON case and confirm the UI no longer ends in a silent no-answer state.
- [x] 4.3 Final verification by the user: trigger several AI+TTS runs (normal + malformed-output conditions if possible) and confirm the text area always shows either a usable answer or a clear error state.