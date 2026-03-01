## 1. Identify integration points

- [x] 1.1 Locate where STT is enabled/disabled in the app and determine the best place to expose a shared `isSpeaking` state
- [x] 1.2 Document current STT worker events and confirm whether speech start/end (VAD) signals are available
- [x] 1.3 Define and document app-level mapping: STT enabled = `recording == true`

## 2. Implement speech activity state (server-testable)

- [x] 2.1 Create a framework-agnostic speech activity state machine/reducer that consumes events or samples and outputs `isSpeaking`
- [x] 2.2 Add hysteresis/debounce configuration (`minSpeakMs`, `minSilenceMs`, and if sample-based: `onThreshold`/`offThreshold`)
- [x] 2.3 Write server-side unit tests (ExUnit) covering: turns ON after sustained speech, stays ON during brief pauses, turns OFF after sustained silence, STT disabled forces OFF

## 3. Build the “On Air” indicator UI

- [x] 3.1 Create an `OnAirIndicator` component (div or SVG) with inactive (gray) and active (lit) states and text “On Air”
- [x] 3.2 Add accessibility attributes (label announces On Air + active/inactive)
- [x] 3.3 Add LiveView/component tests to verify rendering for: STT enabled+speaking, STT enabled+not speaking, STT disabled (inactive)

## 4. Wire it into STT and verify behavior

- [x] 4.1 Connect speech activity inputs to existing STT/audio pipeline (use engine speech events if present; otherwise use audio-energy sampling as default)
- [x] 4.2 Mount the On Air indicator in the STT UI while STT controls are visible
- [x] 4.3 Manual verification: confirm it lights up while speaking and returns to gray after stop/silence without flicker
