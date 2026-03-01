# stt-audio-gating Specification (Delta)

## ADDED Requirements

### Requirement: Silent audio chunks are not forwarded to the STT backend
When STT recording is enabled, the system SHALL NOT forward microphone audio chunks to the STT backend while speech activity is inactive.

#### Scenario: Recording enabled and user is not speaking
- **WHEN** recording is enabled and `isSpeaking` is `false`
- **THEN** incoming microphone audio chunks are processed for speech-activity detection but are not forwarded to the STT backend

### Requirement: Speech start triggers pre-roll flush to preserve leading audio
To avoid clipping the beginning of speech, the system SHALL maintain a bounded pre-roll buffer of recent microphone audio chunks while speech activity is inactive, and SHALL flush that buffer to the STT backend when speech activity transitions to active.

#### Scenario: Transition from not speaking to speaking
- **WHEN** recording is enabled and speech activity transitions from `isSpeaking=false` to `isSpeaking=true`
- **THEN** the system forwards the buffered pre-roll chunks to the STT backend in chronological order before forwarding subsequent chunks

### Requirement: Speech end stops forwarding after sustained silence
The system SHALL continue forwarding microphone audio chunks to the STT backend while speech activity is active, and SHALL stop forwarding only after speech activity becomes inactive (including any debounce/hysteresis behavior).

#### Scenario: Brief pause during speech
- **WHEN** recording is enabled and the user pauses briefly but `isSpeaking` remains `true` due to configured hysteresis
- **THEN** microphone audio chunks continue to be forwarded to the STT backend during that pause

#### Scenario: Sustained silence ends forwarding
- **WHEN** recording is enabled and sustained silence causes `isSpeaking` to become `false`
- **THEN** microphone audio chunks stop being forwarded to the STT backend

### Requirement: Audio gating uses the existing speech-activity signal as the source of truth
The system SHALL base backend audio forwarding decisions on the same speech-activity state that drives the On Air indicator.

#### Scenario: Indicator and gating remain consistent
- **WHEN** the On Air indicator is active because `isSpeaking` is `true`
- **THEN** microphone audio chunks are eligible to be forwarded to the STT backend (including any required pre-roll behavior)

### Requirement: Gating behavior is observable
The system SHALL expose metrics (e.g. telemetry counters) for forwarded chunks, dropped (non-forwarded) chunks, and pre-roll flushes.

#### Scenario: Operator inspects chunk forwarding behavior
- **WHEN** a recording session runs with alternating speech and silence
- **THEN** metrics allow distinguishing forwarded chunks from dropped chunks and counting pre-roll flushes
