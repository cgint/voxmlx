## ADDED Requirements

### Requirement: TTS answer generation resolves with deterministic terminal outcome
For every TTS answer generation request, the system SHALL produce exactly one terminal outcome: `success`, `recovered_success`, or `error`.

#### Scenario: Primary generation succeeds
- **WHEN** DSPy returns valid JSON containing a non-empty `answer`
- **THEN** the system sets terminal outcome to `success` and writes the answer to the TTS text area

#### Scenario: Retry path succeeds
- **WHEN** primary generation fails with a recoverable parse/schema error and retry yields a valid non-empty `answer`
- **THEN** the system sets terminal outcome to `recovered_success` and writes the recovered answer to the TTS text area

#### Scenario: Retry path fails
- **WHEN** primary generation fails and all configured retry attempts fail to produce a valid non-empty `answer`
- **THEN** the system sets terminal outcome to `error` and surfaces a user-friendly error message

### Requirement: Recoverable DSPy output failures trigger bounded retries
The system SHALL classify TTS generation failures and execute bounded retries for recoverable classes.

#### Scenario: Decode failure triggers retry
- **WHEN** primary attempt fails with malformed JSON decode failure
- **THEN** the system performs one bounded retry using stricter format constraints

#### Scenario: Missing answer field is recoverable
- **WHEN** primary attempt returns parseable JSON without a non-empty `answer` field
- **THEN** the system treats the result as recoverable and runs configured retry logic

#### Scenario: Non-recoverable provider failure
- **WHEN** generation fails due to non-recoverable provider/runtime failure
- **THEN** the system skips retry attempts and resolves directly with terminal `error`

### Requirement: No raw-output fallback extraction is used
If strict parsing and retries fail, the system SHALL NOT extract or synthesize answer text from malformed raw output.

#### Scenario: Retry exhausted with malformed output
- **WHEN** retry attempts are exhausted and no valid structured `answer` is available
- **THEN** the system resolves with terminal `error` and does not populate the TTS text area with fallback text

### Requirement: TTS answer pipeline emits structured observability signals
The system SHALL emit structured logs or telemetry for each TTS answer request, including failure class, attempt count, retry path, and final terminal outcome.

#### Scenario: Successful first attempt telemetry
- **WHEN** a request succeeds without retry
- **THEN** observability events include attempt count `1` and final outcome `success`

#### Scenario: Recovered request telemetry
- **WHEN** a request succeeds through retry
- **THEN** observability events include failure class, retry path identifier, and final outcome `recovered_success`

#### Scenario: Terminal error telemetry
- **WHEN** a request ends in `error`
- **THEN** observability events include terminal failure class and all attempted retry steps