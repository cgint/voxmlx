## ADDED Requirements

### Requirement: Bounded audio ingest queue
The STT stream ingestion pipeline SHALL enforce a bounded per-session queue for microphone audio chunks so that memory usage does not grow without bound under sustained input.

#### Scenario: Queue accepts chunks below capacity
- **WHEN** a session is active and incoming chunk count is below the configured queue bound
- **THEN** the system enqueues and processes chunks without signaling overload

#### Scenario: Queue reaches capacity
- **WHEN** incoming chunks arrive while the session queue is at capacity
- **THEN** the system SHALL apply the configured overload policy and emit an overload signal/metric

### Requirement: Deterministic session cleanup on stop
The system SHALL release all session-associated server state and processing resources when a user explicitly stops recording.

#### Scenario: Explicit stop clears session state
- **WHEN** an active recording session receives a stop action from the user
- **THEN** the session state is removed and no further chunks for that session are processed

#### Scenario: Process termination fallback cleanup
- **WHEN** the associated LiveView process terminates unexpectedly
- **THEN** the system performs fallback cleanup to avoid leaked session state

### Requirement: Worker failure visibility and recovery behavior
The system SHALL detect Python worker exit/restart events and expose runtime state through logs and telemetry.

#### Scenario: Worker exits unexpectedly
- **WHEN** the Python worker process exits during or before a stream
- **THEN** the system records an error event and transitions to a recoverable state via supervision

#### Scenario: Worker restarts
- **WHEN** the supervised worker is restarted
- **THEN** the system emits a restart-related runtime signal and allows new sessions to initialize cleanly

### Requirement: Stream health telemetry
The system SHALL emit telemetry/log events for chunk ingest rate, queue depth, processing latency, and stream errors using Phoenix/Elixir telemetry conventions.

#### Scenario: Telemetry naming follows stack conventions
- **WHEN** runtime telemetry events are emitted
- **THEN** event names and metadata follow consistent, low-cardinality Phoenix/Elixir telemetry best practices

#### Scenario: Chunk processing emits metrics
- **WHEN** audio chunks are ingested and processed
- **THEN** telemetry includes queue/throughput/latency measurements for the session lifecycle

#### Scenario: Overload or processing error occurs
- **WHEN** chunk processing fails or overload policy is triggered
- **THEN** the system emits error telemetry/logging with reason and countable occurrence
