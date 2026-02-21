# Port-based Python STT Playground Integration

**Status:** done. The Playground app integrates LiveView with a supervised Elixir `GenServer` that communicates with a Python STT worker over an Erlang Port using packet-4 framed JSON.

## Diagram

![Port-based Python STT Playground Integration](./python_subprocess_playground_integration.svg)

## Overview

This Playground implementation wires the STT flow as:

`LiveView -> Demo.PythonPort (GenServer) -> Python subprocess (stt_port_worker.py) -> voxmlx`

Key points:
- Browser records mono audio and sends base64 PCM chunks to LiveView.
- LiveView forwards commands/chunks to `Demo.PythonPort`.
- `Demo.PythonPort` owns a single Port and sends packet-4 JSON messages.
- Python worker receives messages, keeps per-session chunk buffers, emits partial/final transcripts.
- Elixir routes worker events back to the owning LiveView process.

## Components

### 1) LiveView (`DemoLive` in `speech_to_text_port_playground.exs`)
Responsibilities:
- Starts/stops streaming session.
- Forwards incoming `audio_chunk` payloads.
- Receives `{:stt_event, msg}` from the GenServer.
- Updates assigns:
  - partial -> live transcript
  - final -> final transcript + done state

Main events:
- `"start_stream"`
- `"audio_chunk"`
- `"stop_stream"`

### 2) Elixir Port bridge (`Demo.PythonPort`)
Responsibilities:
- Starts Python worker via `uv run python stt_port_worker.py`.
- Opens Port with:
  - `:binary`
  - `{:packet, 4}`
  - `:exit_status`
- Tracks session ownership and monitors caller processes.
- Forwards commands to Python:
  - `start_session`
  - `audio_chunk`
  - `stop_session`
  - `shutdown` (on terminate)
- Decodes JSON messages from worker and forwards to LiveView owner.

Why this helps:
- Keeps Python interop isolated in one supervised process.
- Uses robust framing (packet-4) instead of newline parsing.
- Prevents LiveView from directly managing subprocess lifecycle.

### 3) Python worker (`stt_port_worker.py`)
Responsibilities:
- Implements packet-4 I/O (`recv_packet`, `send_packet`).
- Maintains in-memory session map with chunk buffers.
- Runs background partial loop per session.
- Performs transcription with voxmlx.

Transcription behavior:
- Lazy-loads model once (`load_model(...)`) and reuses it.
- Converts float32 PCM bytes to temp WAV.
- Calls `generate(...)` and decodes tokens to text.
- Emits:
  - `ready`
  - `session_started`
  - `partial`
  - `final`
  - `error`

## Protocol (JSON over packet-4)

### Elixir -> Python
- `{"cmd":"start_session","session_id":"..."}`
- `{"cmd":"audio_chunk","session_id":"...","pcm_b64":"..."}`
- `{"cmd":"stop_session","session_id":"..."}`
- `{"cmd":"shutdown","session_id":"_"}`

### Python -> Elixir
- `{"event":"ready","ts_ms":...}`
- `{"event":"session_started","session_id":"..."}`
- `{"event":"partial","session_id":"...","text":"...","chunk_count":N}`
- `{"event":"final","session_id":"...","text":"..."}`
- `{"event":"error","session_id":"...","message":"..."}`

## Session lifecycle

1. User clicks **Start**.
2. LiveView allocates `session_id` and calls `Demo.PythonPort.start_session/2`.
3. Browser streams PCM chunks; LiveView forwards each chunk.
4. Python accumulates chunks and periodically emits real partial text.
5. LiveView renders partial transcript in near realtime.
6. User clicks **Stop**.
7. Python transcribes full buffered audio and returns final text.
8. LiveView marks status done and shows final transcript.

## Runtime/config notes

- Worker is launched with `uv run python ...` (project has `uv.lock`).
- Port env includes `VOXMLX_ENABLE_FINAL_TRANSCRIBE=1`.
- Optional env knobs in worker:
  - `VOXMLX_MODEL`
  - `VOXMLX_TEMP`
  - `VOXMLX_PARTIAL_INTERVAL_SEC`
  - `VOXMLX_MIN_CHUNKS_FOR_PARTIAL`

## Files

- `./speech_to_text_port_playground.exs`
- `./stt_port_worker.py`
- `./python_subprocess_playground_integration.d2`
- `./python_subprocess_playground_integration.svg`
