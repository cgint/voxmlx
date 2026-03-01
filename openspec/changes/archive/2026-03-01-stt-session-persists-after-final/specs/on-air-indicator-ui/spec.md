## MODIFIED Requirements

### Requirement: On Air indicator reflects speech activity while STT is enabled
When STT is enabled, the UI SHALL display an “On Air” indicator that reflects the current speaking state.

For this codebase, **STT enabled** means `recording == true`.

A `final` STT event SHALL NOT, by itself, disable STT indicator enablement while the same recording session remains active.

#### Scenario: STT enabled and not speaking
- **WHEN** STT is enabled and `isSpeaking` is `false`
- **THEN** the indicator is rendered in an inactive/gray state with the text “On Air”

#### Scenario: STT enabled and speaking
- **WHEN** STT is enabled and `isSpeaking` is `true`
- **THEN** the indicator is rendered in an active/lit state with the text “On Air”

#### Scenario: Final event does not disable indicator enablement
- **WHEN** STT is enabled and the app receives a `final` event for the active session
- **THEN** indicator enablement remains tied to `recording == true` rather than being implicitly disabled by `final`
