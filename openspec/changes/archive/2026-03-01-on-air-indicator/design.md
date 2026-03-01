## Context

The app supports speech-to-text (STT). When STT is enabled, the user needs immediate feedback that voice activity is being detected.

We want an "On Air" indicator that reflects *speech activity* (speaking vs. not speaking) without requiring broad changes across the codebase.

Key constraints:
- Must be easy to integrate alongside existing STT activation/deactivation.
- Should avoid UI flicker and be understandable at a glance.
- The core "speech activity" logic should be testable in a server-side test runner (e.g., ExUnit), with no browser APIs required.

## Diagram

![Speech activity + On Air indicator flow](./speech-activity-flow.svg)

## Goals / Non-Goals

**Goals:**
- Provide a stable boolean state `isSpeaking` that is true only while the user is detected as speaking (and STT is active).
- Keep the detection logic isolated behind a small interface so UI and STT plumbing don't get tightly coupled.
- Make the detection logic deterministic and unit-testable (feed in samples/events → assert emitted speaking state changes).
- Add a small "On Air" UI component (div or SVG) that uses `isSpeaking` to render active/inactive styles.

**Non-Goals:**
- High-accuracy VAD across all microphones/environments (we only need a useful indicator).
- Replacing or deeply refactoring the existing STT implementation.
- Persisting speech activity state to backend or analytics (unless already present).

## Decisions

1) **Separate "speech activity state" from the UI component**

- Create a small, framework-agnostic module (e.g. a class or pure reducer) that consumes *either*:
  - semantic speech events (`speechStart`, `speechEnd`), **or**
  - numeric energy samples (`rms`, `db`, etc.) + timestamps.
- Output is a debounced/hysteresis-controlled boolean `isSpeaking` and optional events (`onChange`).

Rationale:
- Keeps the hard-to-test parts (audio events/timing) at the edge.
- The core state machine can be unit tested server-side by simulating event sequences.

Alternative considered:
- Let the UI component directly subscribe to STT/audio callbacks. Rejected because it couples UI to STT internals and makes unit testing harder.

2) **Prefer existing speech/VAD signals if available; fallback to a minimal energy-based heuristic**

- If the current STT layer already exposes "speech start/end" (some engines/WebSpeech implementations do), use it.
- In the current codebase, the Python STT worker does not expose speech start/end events, so the default path is to derive activity from audio-energy samples.
- Tap the existing audio stream used for STT and compute a simple signal (e.g. RMS energy over 10-20ms frames) and apply thresholding.

Rationale:
- Using native/engine-provided signals is simpler and usually more accurate.
- A lightweight energy heuristic is still sufficient for a UI indicator and avoids introducing heavy dependencies.

3) **Stability via hysteresis / debouncing**

- Use configurable timings to avoid flicker:
  - `minSpeakMs`: require speaking to be detected for N ms before turning ON.
  - `minSilenceMs`: require silence for N ms before turning OFF.
- If using energy samples, also use two thresholds:
  - `onThreshold` (higher)
  - `offThreshold` (lower)

Rationale:
- Prevents rapid toggling in noisy environments.
- Makes behavior predictable and testable.

4) **UI integration as a small, replaceable component**

- Implement `OnAirIndicator` as a component that receives `active: boolean` (or `isSpeaking`) and optionally `enabled: boolean` (STT enabled).
- Rendering:
  - when STT disabled: indicator is rendered in inactive/gray state
  - when STT enabled + not speaking: gray “On Air"
  - when STT enabled + speaking: lit “On Air”

Rationale:
- Keeps UI dead simple and avoids forcing state management decisions across the app.

## Risks / Trade-offs

- **[Risk] Flicker due to borderline noise / intermittent speech** → **Mitigation:** hysteresis + minimum durations (`minSpeakMs`, `minSilenceMs`).
- **[Risk] False positives in noisy environments** → **Mitigation:** conservative default thresholds, allow configuration, and prefer engine-provided speech events when possible.
- **[Risk] Extra CPU cost if sampling audio** → **Mitigation:** reuse existing STT audio processing path; keep window sizes small; only run while STT is enabled.
- **[Trade-off] "Simple" VAD may miss very quiet speech** → acceptable for a UI indicator; user still sees transcript output as primary signal.
