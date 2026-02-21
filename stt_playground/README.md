# STT Playground (Minimal Mix App)

This is the Mix/Phoenix version of the port-based Python STT playground.

## Run

1. `cd stt_playground`
2. `mix setup`
3. `mix phx.server`
4. Open http://localhost:4000

## Notes

- Uses local Tailwind build output (`/assets/css/app.css`) via Phoenix assets pipeline.
- Python worker path defaults to `../stt_port_worker.py` (relative to `stt_playground/`).
- Override worker path if needed:
  - `STT_WORKER_PATH=/absolute/path/to/stt_port_worker.py mix phx.server`
- Requires `uv` in `PATH` because the worker is started via `uv run python ...`.
