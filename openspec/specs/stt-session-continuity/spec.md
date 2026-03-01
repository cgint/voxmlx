# stt-session-continuity Specification

## Purpose
TBD - created by archiving change stt-session-persists-after-final. Update Purpose after archive.
## Requirements
### Requirement: Active STT session persists after interim final events
The system SHALL keep an active STT session open after receiving a `final` event for the current session while recording remains enabled.

#### Scenario: Final does not clear active session
- **WHEN** recording is active and the app receives a `final` STT event for the current `session_id`
- **THEN** the app keeps `recording == true` and retains the same `session_id`

### Requirement: Transcript updates continue after final in same session
The system SHALL continue applying subsequent `partial` and `final` transcript updates for the same active session after an earlier `final` event.

#### Scenario: Partial arrives after final
- **WHEN** a `partial` STT event for the active `session_id` arrives after a prior `final`
- **THEN** the transcript is updated without requiring a stop/start cycle

#### Scenario: Later final replaces transcript in same session
- **WHEN** another `final` STT event arrives for the same active `session_id`
- **THEN** the transcript is updated and the session remains active

### Requirement: Session termination remains explicit
The system SHALL terminate an active STT session only on explicit stop actions or error paths.

#### Scenario: Explicit stop ends session
- **WHEN** the user triggers stop
- **THEN** the app stops the STT session and marks recording inactive

#### Scenario: Error ends session
- **WHEN** audio or STT error occurs for the active session
- **THEN** the app marks recording inactive and does not continue forwarding audio chunks

