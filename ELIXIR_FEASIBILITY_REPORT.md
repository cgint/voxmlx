# Elixir Feasibility Report for `voxmlx` (Python → Native Elixir)

1. Status / Conclusion

- **Overall:** A **functional Elixir-native STT system is feasible**, but **full 1:1 parity** with this repository’s current Python+MLX implementation is **not guaranteed out of the box**.
- **What is realistic now:** Rebuild user-facing behavior (file transcription + realtime streaming) in Elixir using Nx/Bumblebee/Serving-style pipelines.
- **What is risky:** Exact parity for Voxtral-Realtime internals (custom incremental decoding state, tokenizer specifics, conversion/remap/quantization pipeline, and MLX-specific execution behavior).
- **Recommendation:** Proceed with a staged feasibility spike in Elixir, validate backend/model support first, then implement feature parity incrementally.

---

## Scope of Analysis

This report answers:

1. What the Python repo does technically.
2. Whether those capabilities can be done natively in Elixir.
3. Where parity is straightforward vs uncertain.
4. A concrete follow-up plan to de-risk migration.

Research basis:

- Repository code inspection.
- External ecosystem checks using `webs.sh` and `asks.sh` (as requested).

---

## 1) What this repository currently does in Python

### 1.1 Entry points and workflows

- CLI app for transcription from:
  - **Audio file** (`voxmlx --audio ...`)
  - **Live microphone stream** (`voxmlx` with no file)
- Conversion tool:
  - `voxmlx-convert` converts model weights to local MLX format
  - Optional quantization
  - Optional upload to Hugging Face

Evidence:

- `README.md`
- `pyproject.toml` scripts:
  - `voxmlx = "voxmlx:main"`
  - `voxmlx-convert = "voxmlx.convert:main"`

### 1.2 Core model runtime

- Heavy dependency on **Apple MLX** (`mlx.core`, `mlx.nn`) across model, encoder, decoder, generation and conversion.
- Implements custom model components and inference path:
  - Audio encoder, language model, adapter, time conditioning
  - KV cache and rotating/sliding context cache
  - Autoregressive decode loop

Evidence:

- `voxmlx/model.py`
- `voxmlx/encoder.py`
- `voxmlx/language_model.py`
- `voxmlx/cache.py`
- `voxmlx/generate.py`

### 1.3 Realtime streaming implementation details

- Realtime audio capture via `sounddevice`
- Incremental mel feature extraction with overlap/tail buffers
- Incremental encoder state (`conv1_tail`, `conv2_tail`, `encoder_cache`, `ds_buf`)
- Sliding-window decode cache with periodic cache maintenance
- Prompt prefill + token-by-token decoding with EOS handling and state reset

Evidence:

- `voxmlx/stream.py`
- `voxmlx/audio.py`

### 1.4 Audio frontend

- Custom audio preprocessing stack:
  - Resampling
  - Padding logic aligned to token cadence
  - STFT + mel filterbank + normalization
  - Full and streaming mel paths

Evidence:

- `voxmlx/audio.py`

### 1.5 Model packaging + conversion + publishing

- Downloads original model artifacts from Hugging Face
- Remaps weight names and transposes convolution weights for runtime compatibility
- Supports quantization and sharded safetensors writing
- Optional Hugging Face model-card generation and upload

Evidence:

- `voxmlx/weights.py`
- `voxmlx/convert.py`

---

## 2) Elixir-native feasibility by capability

Legend:

- ✅ Feasible today (high confidence)
- ⚠️ Feasible with custom implementation / uncertain compatibility
- ❌ No clear native path yet

### 2.1 File-based transcription

- **Target parity:** `transcribe(audio_path, model, temp)`
- **Elixir feasibility:** ✅
- Typical path: Elixir ML stack (`Nx` + model serving libs) can do batch/file STT.
- Risk: exact output parity with Voxtral-specific tokenizer/prompting may differ.

### 2.2 Realtime streaming transcription

- **Target parity:** microphone → incremental decode → partial token output
- **Elixir feasibility:** ✅ for behavior, ⚠️ for exact internal parity
- Elixir is strong for streaming/concurrency orchestration.
- You can replicate pipeline behavior; exact identical token-timing/state behavior is harder.

### 2.3 Incremental decoder/cache semantics (exact)

- **Target parity:** same prefill, cache eviction, position handling, EOS/reset behavior as Python MLX code
- **Elixir feasibility:** ⚠️
- Requires explicit custom implementation and careful numerical/shape parity testing.

### 2.4 Model runtime on Apple Silicon (MLX-equivalent)

- **Target parity:** MLX-optimized execution characteristics
- **Elixir feasibility:** ⚠️
- Web research indicates MLX backend efforts in Elixir ecosystem, but maturity/version details need direct validation in your target environment.

### 2.5 Model conversion/remap/quantization/upload toolchain

- **Target parity:** same as `voxmlx-convert` feature set
- **Elixir feasibility:** ⚠️
- Parts are feasible (artifact handling, serialization, upload), but full parity (name remap rules, quantization compatibility, sharding behavior) needs custom tooling.

### 2.6 Tokenizer compatibility (Tekken/Mistral specifics)

- **Target parity:** exact tokenizer behavior + special token policy
- **Elixir feasibility:** ⚠️
- Likely possible but must validate exact tokenizer implementation and special-token semantics.

### 2.7 End-to-end 1:1 parity

- **Elixir feasibility:** ⚠️ to ❌ (depending on strictness)
- If strict means byte-level output and timing parity with current Python MLX runtime, expect significant engineering effort.

---

## 3) External research summary (`webs.sh`, `asks.sh`)

## 3.1 What came back consistently

- Elixir can support native ML inference workflows and STT-style serving patterns.
- Elixir is operationally strong for realtime orchestration, stream handling, and concurrent workloads.
- Elixir ML ecosystem likely supports required building blocks, but exact Voxtral+MLX equivalence is not guaranteed.

### 3.2 Where research quality was mixed

- `asks.sh` (local indexed docs) produced conservative/partly conflicting answers on Apple-Silicon-native ML maturity.
- `webs.sh` produced optimistic ecosystem summaries that require direct verification against official docs/repos.

### 3.3 Practical interpretation

- Treat external results as **directional**, not final proof.
- Do a short technical spike with measurable acceptance tests before committing to migration.

---

## 4) Gap analysis: Python implementation vs Elixir migration

### 4.1 Low-risk migration targets

1. CLI behavior replication (flags/options).
2. File transcription path.
3. Realtime session state machine and stream orchestration.
4. Hugging Face artifact download/upload wrappers.

### 4.2 Medium-risk targets

1. Streaming feature extraction parity.
2. Prompt/tokenization parity.
3. Throughput/latency comparable to current Python path.

### 4.3 High-risk targets

1. MLX-specific runtime behavior parity.
2. Full conversion/quantization semantics and compatibility guarantees.
3. Exact output/timing parity across diverse audio conditions.

---

## 5) Recommended follow-up plan (actionable)

## Phase A — Verify foundations (1–2 days)

1. Confirm Apple Silicon backend stack in your environment:
   - backend availability
   - model loading feasibility
   - inference on small known test audio
2. Validate tokenizer compatibility with target model artifacts.
3. Record benchmark baseline from current Python repo:
   - latency
   - throughput
   - word error proxies on sample set

Deliverable: `feasibility-foundation.md` with pass/fail table.

## Phase B — Minimal Elixir parity prototype (2–4 days)

1. Implement file transcription CLI command.
2. Implement mic streaming loop with partial outputs.
3. Reproduce prompt construction and decode loop skeleton.
4. Add regression fixtures (same short audio clips across Python vs Elixir).

Deliverable: runnable prototype + parity report.

## Phase C — Deep parity (as needed)

1. Implement/align incremental cache semantics.
2. Tune chunking and buffering for latency/accuracy tradeoff.
3. Add conversion/remap/quantization tooling if required by deployment.
4. Harden with soak tests and crash-recovery behavior.

Deliverable: go/no-go migration recommendation with engineering estimate.

---

## 6) Acceptance criteria for “migration is successful”

Define explicit thresholds before starting implementation:

1. **Functional parity:** all primary CLI workflows available.
2. **Quality parity:** transcription quality within agreed tolerance on fixed dataset.
3. **Latency parity:** realtime median/p95 latency within agreed range.
4. **Operational parity:** stable long-running stream sessions.
5. **Packaging parity:** model acquisition/deployment process acceptable for ops.

---

## 7) Suggested follow-up questions for decision meeting

1. Is “native Elixir” required for all ML compute, or can model compute remain in Python/MLX while Elixir owns orchestration?
2. Is strict output parity required, or is user-perceived quality/latency parity enough?
3. Do we need full model conversion/quantization in Elixir, or only inference/runtime parity?
4. Which hardware targets are mandatory (Apple Silicon only vs mixed infra)?

---

## 8) Comparable options already available in the Elixir ecosystem

This section maps `voxmlx` capabilities to likely Elixir ecosystem equivalents.

### 8.1 Inference/model execution layer

- **Nx**: core tensor/numerics foundation in Elixir.
- **Bumblebee**: pre-trained model integration and high-level task APIs (including STT patterns).
- **Nx.Serving**: production inference serving abstraction (batching/stream processing patterns).
- **Backend options (to verify per target machine):**
  - EXLA
  - Torchx
  - MLX-oriented backend efforts reported as `elixir_mlx` / EMLX in web research

**Comparable to in `voxmlx`:** `mlx.core`, `mlx.nn`, decode loop integration.

### 8.2 Realtime audio I/O and stream orchestration

- **Membrane framework (+ PortAudio plugin family, where applicable):** candidate for low-latency audio pipelines.
- **BEAM concurrency primitives:** GenServer/Task/Streams for robust session orchestration and backpressure.

**Comparable to in `voxmlx`:** `sounddevice` capture + realtime decode session state machine in `voxmlx/stream.py`.

### 8.3 Audio preprocessing / DSP

- **Nx-based tensor ops** and related signal-processing tooling can implement STFT/mel pipelines.
- May require custom implementation for strict parity (windowing/padding/normalization and streaming overlap logic).

**Comparable to in `voxmlx`:** `voxmlx/audio.py` full + incremental mel pipeline.

### 8.4 Model/artifact pipeline

- **Hugging Face download/upload equivalents** are feasible via Elixir HTTP/client tooling and ecosystem wrappers.
- **Safetensors + conversion/remap/quantization pipeline** may need custom Elixir code for exact parity with `voxmlx-convert`.

**Comparable to in `voxmlx`:** `voxmlx/weights.py`, `voxmlx/convert.py`.

### 8.5 Tokenization and model-specific compatibility

- Tokenizer support exists in ecosystem paths, but **exact Tekken/Mistral policy parity must be validated**.
- Special-token handling can be implemented, but behavior should be regression-tested against Python reference outputs.

---

## 9) Bottom line

- **Yes, Elixir can reproduce the product-level STT experience.**
- **There are comparable building blocks in the Elixir ecosystem today** (Nx/Bumblebee/Serving + BEAM streaming/audio pipeline options).
- **No, do not assume full plug-and-play parity with this exact Python MLX implementation.**
- The right next step is a **time-boxed technical spike** with explicit acceptance thresholds.
