## ADDED Requirements

### Requirement: On Air indicator reflects speech activity while STT is enabled
When STT is enabled, the UI SHALL display an “On Air” indicator that reflects the current speaking state.

For this codebase, **STT enabled** means `recording == true`.

#### Scenario: STT enabled and not speaking
- **WHEN** STT is enabled and `isSpeaking` is `false`
- **THEN** the indicator is rendered in an inactive/gray state with the text “On Air”

#### Scenario: STT enabled and speaking
- **WHEN** STT is enabled and `isSpeaking` is `true`
- **THEN** the indicator is rendered in an active/lit state with the text “On Air”

### Requirement: Indicator is not active when STT is disabled
When STT is disabled, the UI SHALL NOT show an active “On Air” state.

#### Scenario: STT disabled
- **WHEN** STT is disabled (`recording == false`)
- **THEN** the indicator is still rendered with text “On Air” and an inactive/gray visual state

### Requirement: Indicator is accessible
The indicator SHALL provide an accessible label that communicates whether it is active.

#### Scenario: Screen reader announces state
- **WHEN** the indicator is focused or announced by assistive technology
- **THEN** it includes a label that conveys “On Air” and whether speech is currently detected
