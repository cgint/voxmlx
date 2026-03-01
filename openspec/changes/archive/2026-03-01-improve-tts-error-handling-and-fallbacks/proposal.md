# Ensure TTS responses reliably reach users even when AI output is malformed

## Why

### Summary
Sometimes TTS generation fails due to malformed JSON returned by DSPy, resulting in no answer being inserted into the text-to-speech area. This creates a visible dead-end in a core user flow (ask → get spoken answer) and degrades trust in the system. We need strict parsing, bounded retries, and clear user-facing error handling so transient model-output issues do not block the interaction.

### Original user request (verbatim)
"sometimes I get the following error and no answer is put into the text to speech text area.  I think we need some kind of free trial and error handling for such cases.

TTS status: error: DSPy failed: {:output_decode_failed, %Jason.DecodeError{position: 87, token: nil, data: \"{\"answer\": \"I recall a simple joke: What do you call a fake noodle? An impasta. I don\"}}\"}}"

## What Changes

- Add robust DSPy output handling for TTS answer generation so malformed/partial JSON does not silently drop responses.
- Introduce strict retry-only recovery for recoverable decode/schema failures (re-ask model with stricter formatting), with no raw-output fallback extraction.
- Ensure the UI always receives a deterministic outcome: valid answer text or an explicit, user-friendly error message.
- Improve observability around TTS generation failures with structured logging/telemetry fields for failure class, retry count, and final outcome.
- Define and test behavior for edge cases: truncated output, invalid JSON escaping, missing `answer` field, and repeated generation failures.

## Capabilities

### New Capabilities
- `tts-answer-resilience`: Guarantees robust answer delivery behavior for TTS generation through strict decode validation, bounded retries, and explicit failure surfacing.

### Modified Capabilities
- `transcription-processing-state`: Extend processing-state requirements to include TTS answer generation failure states and retry-driven recovery transitions exposed to UI status.

## Impact

- Affected areas: TTS request/response pipeline in the Phoenix playground app, DSPy integration layer, and LiveView state updates for the text area/status.
- User impact: fewer “no response” dead-ends, clearer status on failures, more consistent end-to-end interaction.
- Operational impact: additional logs/telemetry for debugging malformed model outputs and tuning retry policy.
- Risk: retry policy may increase latency; mitigated by bounded retry count, timeouts, and telemetry.