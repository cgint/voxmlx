## 1. Stream flow control and session lifecycle

- [x] 1.1 Add bounded per-session audio queue configuration and enforce capacity checks in `stt_playground/lib/stt_playground/stt/python_port.ex`.
- [x] 1.2 Implement overload handling policy (drop/reject semantics) and surface overload state to the LiveView stream contract.
- [x] 1.3 Add deterministic cleanup on explicit stop in `stt_playground/lib/stt_playground_web/live/stt_live.ex` and keep `:DOWN` fallback cleanup.
- [x] 1.4 Add/adjust tests for repeated start/stop loops to confirm no leaked session state.

## 2. Worker resilience and observability

- [x] 2.1 Harden worker supervision/error paths in `stt_playground/lib/stt_playground/application.ex` and `python_port.ex` for exit/restart handling.
- [x] 2.2 Emit telemetry/log events for queue depth, chunk ingest/processing rate, processing latency, and stream/worker errors.
- [x] 2.3 Add tests or instrumentation verification hooks for worker failure and restart scenarios.

## 3. Browser audio modernization

- [x] 3.1 Implement `AudioWorklet`-based microphone capture in `stt_playground/assets/js/app.js` (and supporting worklet module file if needed).
- [x] 3.2 Preserve current start/stop and transcript message flow contract between JS and LiveView.
- [x] 3.3 Add error handling for AudioWorklet initialization failures and expose actionable UI feedback state.

## 4. Verification and quality gates

- [x] 4.1 Run formatting and tests for `stt_playground` (`mix format`, `mix test`) and fix regressions.
- [x] 4.2 Run `./precommit.sh` in `stt_playground/` and resolve any reported issues.
- [x] 4.3 Perform manual validation: no Tailwind CDN usage, stable repeated start/stop, and transcript parity after AudioWorklet migration.
- [x] 4.4 Run a best-practices review pass to confirm Phoenix/LiveView/OTP conventions, telemetry naming discipline, and modern Web Audio patterns are followed in `stt_playground/`.
