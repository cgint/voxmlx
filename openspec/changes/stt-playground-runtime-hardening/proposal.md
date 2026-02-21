## Why

The STT playground already works as a Phoenix app foundation, but runtime behavior is still prototype-grade in several critical areas (flow control, lifecycle cleanup, aging browser audio API usage, and visibility into failures). Hardening now reduces instability before additional features are layered on top and aligns the implementation with Phoenix/LiveView/OTP and modern browser best practices.

## What Changes

- Add bounded backpressure for microphone chunk flow between LiveView and Python port to prevent unbounded mailbox/queue growth.
- Make STT session lifecycle deterministic on both explicit stop and process termination, including resource cleanup and state removal.
- Modernize browser audio capture by replacing `ScriptProcessorNode` with an `AudioWorklet` path.
- Improve Python port supervision behavior and restart handling in the app runtime.
- Add telemetry/logging around chunk rates, queue depth, latency, and error cases to support debugging and validation.
- Apply stack-native best practices (OTP supervision patterns, LiveView event handling conventions, Telemetry naming discipline, modern web audio APIs) across the hardening work.

## Capabilities

### New Capabilities
- `stt-runtime-hardening`: Reliable runtime behavior for STT streaming, including backpressure, cleanup, supervision resilience, and operational visibility.
- `stt-audio-capture-modernization`: Browser-side microphone capture using `AudioWorklet` with parity to current transcript behavior.

### Modified Capabilities
- None.

## Impact

- Affected code: `stt_playground/lib/stt_playground/stt/python_port.ex`, `stt_playground/lib/stt_playground_web/live/stt_live.ex`, `stt_playground/assets/js/app.js`, supervision wiring in `stt_playground/lib/stt_playground/application.ex`.
- APIs/events: LiveView event and push-event audio streaming contract may gain flow-control semantics (acknowledgement/queue feedback).
- Runtime: Python port process handling and restart behavior under error/reload scenarios.
- Observability: new telemetry events and structured logs for stream health metrics.
