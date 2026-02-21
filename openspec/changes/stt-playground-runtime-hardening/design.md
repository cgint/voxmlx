## Context

`stt_playground` is now a minimal Phoenix LiveView app and currently preserves the original STT demo behavior. The remaining work is runtime hardening for stream reliability and maintainability: prevent unbounded ingest, clean up session state deterministically, modernize browser audio capture APIs, and expose operational signals.

Constraints:
- Keep behavior parity for users (`start`/`stop` recording and transcript updates at `/`).
- Keep scope isolated to `stt_playground/`.
- Preserve compatibility with the existing Python worker protocol unless explicitly versioned.
- Follow tech-stack best practices (Phoenix/LiveView conventions, OTP supervision principles, Telemetry standards, and modern Web Audio APIs).

## Goals / Non-Goals

**Goals:**
- Enforce bounded flow for incoming audio chunks under normal and bursty load.
- Ensure explicit stop always releases server-side session state and associated resources.
- Use `AudioWorklet` for browser capture while preserving transcript UX.
- Improve robustness when Python worker exits/restarts.
- Emit telemetry/log signals for throughput, queue pressure, latency, and errors.
- Implement changes using established best practices for Phoenix/LiveView/OTP and browser APIs, not ad-hoc workarounds.

**Non-Goals:**
- Rewriting the Python STT implementation.
- Introducing distributed/multi-node stream coordination.
- Adding persistence, auth, or product-level UI redesign.

## Decisions

1. **Bounded queue with explicit flow-control feedback**
   - Decision: Introduce per-session bounded buffering (fixed max) and explicit handling when at capacity (drop-with-signal or reject-with-ack semantics).
   - Rationale: Prevent mailbox/heap growth and make overload visible.
   - Alternatives considered:
     - Unbounded queue: simplest, but unsafe.
     - Fully synchronous per-chunk round-trip: safest but high latency/choppy UX.

2. **Deterministic session cleanup on stop + fallback cleanup on process down**
   - Decision: Execute cleanup on explicit `stop_recording` event and retain `:DOWN` handling as safety net.
   - Rationale: Users expect immediate resource release; relying only on process exits leaks state during normal operation.
   - Alternatives considered:
     - Timeout-only cleanup: delayed and nondeterministic.

3. **AudioWorklet migration with compatibility-preserving chunk format**
   - Decision: Replace `ScriptProcessorNode` path with `AudioWorkletNode`; keep payload shape and sample handling compatible with server expectations.
   - Rationale: `ScriptProcessorNode` is deprecated and less stable.
   - Alternatives considered:
     - Keep ScriptProcessor: lower effort, increasing browser risk.

4. **Port supervision and restart visibility**
   - Decision: Keep Python port as supervised app child, add structured error handling/telemetry around exits and restarts.
   - Rationale: Failures should be observable and recoverable without silent degradation.
   - Alternatives considered:
     - Ad hoc restart logic in LiveView: couples UI process to runtime lifecycle.

5. **Telemetry as first-class runtime signal**
   - Decision: Emit events for chunk ingest rate, queue depth, processing latency, dropped/rejected chunks, and port errors.
   - Rationale: Hardening work needs measurable outcomes.

## Risks / Trade-offs

- **[Risk] Added flow-control logic may drop chunks under pressure** → **Mitigation:** expose queue pressure + drop counters; tune bounds based on measured load.
- **[Risk] AudioWorklet integration differs across browsers/environments** → **Mitigation:** guard initialization errors, provide clear UI error state, verify on target browsers.
- **[Risk] Worker restart behavior may cause transient transcript gaps** → **Mitigation:** surface worker health state in LiveView and reinitialize session cleanly.
- **[Risk] Telemetry cardinality explosion if tagged poorly** → **Mitigation:** use bounded tag sets and avoid per-chunk high-cardinality labels.

## Migration Plan

1. Add bounded queue + flow-control handling in `python_port` and `stt_live` message contract.
2. Implement explicit stop cleanup and verify state map shrinking in repeated start/stop loops.
3. Add AudioWorklet module and wire hook in `assets/js/app.js`.
4. Add telemetry/log events around ingest, processing, and failures.
5. Validate with manual loops and test coverage; keep rollback by reverting to prior hook/path if needed.

## Open Questions

- Should overload behavior default to drop-oldest, drop-newest, or hard reject until ACK?
- Do we need a visible UI indicator for degraded mode (worker restarting/overloaded), or only logs/telemetry for now?
- Is protocol versioning needed between JS/Elixir/Python for future evolution, or can we preserve current payload contract unchanged?
