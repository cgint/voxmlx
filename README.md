## Fork context (quick overview for this repository)

This fork started from the `voxmlx` core and adds a minimal end-to-end app path so we can validate how the model behaves in real user workflows, not only in isolated library usage.

### Intent

This fork exists to answer a practical question: **how do we move from a strong STT core library to a real user-facing application flow that is reliable and maintainable?**

The goal is not to replace `voxmlx`, but to validate productization decisions around it:

- browser microphone streaming in a live UI
- safe process boundary between web runtime and Python inference
- robust lifecycle handling between app process and worker process
- clear path for runtime hardening (stability, backpressure, observability)

### What was added in this repository

- `stt_playground/` — a minimal Phoenix/LiveView application that acts as the integration testbed
- `stt_port_worker.py` — Python subprocess worker that executes transcription and communicates over Port framing
- `PORT_BASED_PYTHON_STT_PLAYGROUND.md` — notes and rationale for the integration approach
- `python_subprocess_playground_integration.d2` + `.svg` — visual architecture of the full data flow
- `stt_playground/scripts/dspy_ollama_playground.exs` — tiny script to validate DSPy with local Ollama

If you are new here: think of this repo as **original `voxmlx` + an experimental app shell used to validate the path toward production-grade end-user usage**.

### Local Ollama defaults for AI response generation

The playground's DSPy response path is configured to use local Ollama by default:

- model: `ollama/llama3.2`
- base URL: `http://localhost:11434/v1` (override with `OLLAMA_BASE_URL`)
- API key: optional (`OLLAMA_API_KEY` may be empty for local setups)

Quick smoke test for the DSPy + Ollama path:

```bash
cd stt_playground
mix run scripts/dspy_ollama_playground.exs
```

You can override defaults when needed:

```bash
cd stt_playground
OLLAMA_MODEL=ollama/llama3.2 OLLAMA_BASE_URL=http://localhost:11434/v1 OLLAMA_API_KEY="" \
  mix run scripts/dspy_ollama_playground.exs
```

The original library content remains intact below.

# voxmlx

Realtime speech-to-text with
[Voxtral Mini Realtime](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602)
in [MLX](https://github.com/ml-explore/mlx).

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
