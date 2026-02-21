# voxmlx

Realtime speech-to-text with
[Voxtral Mini Realtime](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602)
in [MLX](https://github.com/ml-explore/mlx).

## Why this fork / what was added

Besides the original Python package, this repo now also includes a minimal Phoenix/LiveView playground to validate and iterate on a **port-based STT architecture**:

- Browser mic capture (LiveView hook)
- Elixir GenServer using Erlang `Port` (`{:packet, 4}` framing)
- Python worker process (`stt_port_worker.py`) executing `voxmlx`

This was added to test integration quality and production-direction architecture (supervision, lifecycle, transport boundaries), while keeping the core `voxmlx` package unchanged.

## Repository layout

- `voxmlx/` — core Python library
- `stt_playground/` — minimal Mix/Phoenix app with local Tailwind assets
- `stt_port_worker.py` — Python subprocess worker used by the Elixir Port
- `PORT_BASED_PYTHON_STT_PLAYGROUND.md` — integration notes
- `python_subprocess_playground_integration.d2` / `.svg` — architecture diagram

## Run the STT playground

```bash
cd stt_playground
mix setup
mix phx.server
```

Open http://localhost:4000

Notes:
- Worker path defaults to `../stt_port_worker.py`.
- Override with `STT_WORKER_PATH=/abs/path/stt_port_worker.py mix phx.server`.
- `uv` must be available in `PATH`.

## Install

```bash
pip install voxmlx
```

## Usage

### `voxmlx`

Transcribe audio from a file or stream from the microphone in real-time.

**Stream from microphone:**

```bash
voxmlx
```

**Transcribe a file:**

```bash
voxmlx --audio audio.flac
```

**Options:**

| Flag | Description | Default |
|------|-------------|---------|
| `--audio` | Path to audio file (omit to stream from mic) | None |
| `--model` | Model path or HuggingFace model ID | `mlx-community/Voxtral-Mini-4B-Realtime-6bit` |
| `--temp` | Sampling temperature (`0` = greedy) | `0.0` |

### `voxmlx-convert`

Convert Voxtral weights to voxmlx/MLX format with optional quantization.

**Basic conversion:**

```bash
voxmlx-convert --mlx-path voxtral-mlx
```

**4-bit quantized conversion:**

```bash
voxmlx-convert -q --mlx-path voxtral-mlx-4bit
```

**Convert and upload to HuggingFace:**

```bash
voxmlx-convert -q --mlx-path voxtral-mlx-4bit --upload-repo username/voxtral-mlx-4bit
```

**Options:**

| Flag | Description | Default |
|------|-------------|---------|
| `--hf-path` | HuggingFace model ID or local path | `mistralai/Voxtral-Mini-4B-Realtime-2602` |
| `--mlx-path` | Output directory | `mlx_model` |
| `-q`, `--quantize` | Quantize the model | Off |
| `--group-size` | Quantization group size | `64` |
| `--bits` | Bits per weight | `4` |
| `--dtype` | Cast weights (`float16`, `bfloat16`, `float32`) | None |
| `--upload-repo` | HuggingFace repo to upload converted model | None |

### Python API

```python
from voxmlx import transcribe

text = transcribe("audio.flac")
print(text)
```
