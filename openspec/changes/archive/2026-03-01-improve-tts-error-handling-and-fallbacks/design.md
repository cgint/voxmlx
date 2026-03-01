# Keep TTS answer flow reliable when model output is malformed

## Context
The current TTS answer generation path expects DSPy to return valid JSON containing an `answer` field. In practice, model output can be malformed or truncated (for example invalid escaping or incomplete JSON), which leads to decode failure (`Jason.DecodeError`) and no text being written to the TTS input area.

This is a high-friction failure in a core interaction path. The design needs to preserve deterministic UI behavior and avoid silent drop-offs while keeping implementation changes local to the existing Elixir + DSPy integration in `stt_playground`.

## Goals / Non-Goals

**Goals:**
- Ensure each TTS answer request resolves deterministically to either:
  - usable answer text, or
  - explicit user-visible error state/message.
- Recover automatically from common malformed-output classes (decode failure, missing `answer`, truncated payload) using bounded retries only.
- Enforce strict schema validation so only valid structured DSPy output is accepted.
- Add structured observability to distinguish primary success, retry success, and unrecoverable failure.
- Align processing-state semantics so UI can represent TTS generation progress/failure clearly.

**Non-Goals:**
- Redesigning prompt strategy across all model interactions.
- Introducing new external AI providers or infrastructure.
- Parsing or salvaging malformed raw model output as fallback content.
- Solving all model hallucination/quality issues beyond parseability and delivery reliability.

## Decisions

1. **Classify failures explicitly before retry decisions**
   - Introduce normalized failure classes in the DSPy/TTS boundary (`output_decode_failed`, `missing_answer_field`, `empty_answer`, `provider_error`, `timeout`).
   - Rationale: deterministic branching and measurable outcomes.
   - Alternative considered: generic `{:error, reason}` passthrough. Rejected because UI and telemetry cannot distinguish recoverable from terminal paths.

2. **Use bounded retry with stricter format instruction for recoverable parse failures**
   - On recoverable parse/schema failures, perform one retry with a stricter “JSON-only answer schema” request.
   - Rationale: captures transient generation variance with limited latency impact.
   - Alternative considered: infinite/multi-step retries. Rejected due to latency and unpredictable user experience.

3. **Reject fallback extraction of malformed raw output**
   - If retry still fails strict parsing/validation, resolve as terminal error rather than extracting free-form text.
   - Rationale: keeps behavior explicit, avoids masking DSPy formatting failures, and preserves contract correctness.
   - Alternative considered: best-effort raw-text extraction. Rejected per product requirement to avoid fallback behavior.

4. **Guarantee a terminal UI update on all paths**
   - Ensure LiveView state transitions always emit a terminal TTS status (`success`, `recovered_success`, or `error`) and set the text area accordingly.
   - Rationale: avoids stuck/invisible failure states.
   - Alternative considered: rely only on logs for failure handling. Rejected because user still experiences dead-end.

5. **Instrument outcome path with structured telemetry/logging**
   - Record attempt count, failure class, retry path, and final outcome.
   - Rationale: enables operational debugging and future tuning of retry policy.

## Risks / Trade-offs
- **[Risk] Retry increases response latency** → Mitigation: single bounded retry only, with clear timeout and telemetry to validate overhead.
- **[Risk] Strict no-fallback policy produces more explicit user errors under persistent malformed output** → Mitigation: user-facing error messaging + telemetry to prioritize DSPy prompt/format fixes.
- **[Risk] Added state transitions can regress UI behavior** → Mitigation: add focused tests for status transitions and terminal-state guarantees.
- **[Risk] Retry settings may be too strict or too lenient initially** → Mitigation: monitor success-after-retry rate and tune within bounded limits.