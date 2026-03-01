from ._version import __version__

import argparse
import time
from collections.abc import Callable
from pathlib import Path

import mlx.core as mx
import numpy as np

from mistral_common.tokens.tokenizers.base import SpecialTokenPolicy
from mistral_common.tokens.tokenizers.tekken import Tekkenizer

from .audio import SAMPLES_PER_TOKEN, load_audio, log_mel_spectrogram_step
from .cache import RotatingKVCache
from .generate import generate, generate_from_audio
from .weights import download_model, load_model as _load_weights


def _load_tokenizer(model_path: Path) -> Tekkenizer:
    tekken_path = model_path / "tekken.json"
    return Tekkenizer.from_file(str(tekken_path))


def _build_prompt_tokens(
    sp: Tekkenizer,
    n_left_pad_tokens: int = 32,
    num_delay_tokens: int = 6,
) -> tuple[list[int], int]:
    streaming_pad = sp.get_special_token("[STREAMING_PAD]")
    prefix_len = n_left_pad_tokens + num_delay_tokens  # 38 STREAMING_PAD tokens
    tokens = [sp.bos_id] + [streaming_pad] * prefix_len
    return tokens, num_delay_tokens


def load_model(model_path: str = "mlx-community/Voxtral-Mini-4B-Realtime-6bit"):
    if not Path(model_path).exists():
        model_path = download_model(model_path)
    else:
        model_path = Path(model_path)

    model, config = _load_weights(model_path)
    sp = _load_tokenizer(model_path)
    return model, sp, config


def _transcribe_file_streaming(
    *,
    model,
    sp: Tekkenizer,
    audio: np.ndarray,
    temperature: float,
    stop_on_eos: bool,
    segment_separator: str,
    on_text: Callable[[str], None] | None,
) -> str:
    """Transcribe a *file* by simulating the streaming pipeline.

    This matches `voxmlx/stream.py` semantics more closely than the offline
    `generate()` path because it uses the incremental mel encoder
    (`log_mel_spectrogram_step`) + `model.encode_step()`.

    This matters because the full-spectrogram path and incremental path differ
    numerically, and the realtime model is tuned for the streaming path.
    """

    if on_text is None:
        chunks: list[str] = []

        def on_text_local(s: str) -> None:
            chunks.append(s)

        on_text = on_text_local
    else:
        chunks = []

    prompt_tokens, n_delay_tokens = _build_prompt_tokens(sp)
    prefix_len = len(prompt_tokens)
    eos_token_id = sp.eos_id

    # Precompute constant embeddings
    t_cond = model.time_embedding(mx.array([n_delay_tokens], dtype=mx.float32))
    mx.eval(t_cond)

    prompt_ids = mx.array([prompt_tokens])
    text_embeds = model.language_model.embed(prompt_ids)[0]  # [prefix_len, 3072]
    mx.eval(text_embeds)

    n_layers = len(model.language_model.layers)
    sliding_window = 8192

    def sample(logits):
        if temperature <= 0:
            return mx.argmax(logits[0, -1:], axis=-1).squeeze()
        return mx.random.categorical(logits[0, -1:] / temperature).squeeze()

    # Decoder state
    cache: list[RotatingKVCache] | None = None
    y: mx.array | None = None

    def decode_steps(embeds: mx.array, n_to_decode: int) -> tuple[int, bool]:
        """Decode up to n_to_decode audio-positions from embeds.

        Returns (n_consumed, hit_eos). On EOS, cache and y are reset.
        """
        nonlocal cache, y

        assert cache is not None
        assert y is not None

        for i in range(n_to_decode):
            token_embed = model.language_model.embed(y.reshape(1, 1))[0, 0]
            step_embed = (embeds[i] + token_embed)[None, None, :]
            logits = model.decode(step_embed, t_cond, mask=None, cache=cache)
            next_y = sample(logits)
            mx.async_eval(next_y)

            token_id = y.item()
            if token_id == eos_token_id:
                if stop_on_eos:
                    return i, True

                if segment_separator:
                    on_text(segment_separator)

                cache = None
                y = None
                return i, True

            text = sp.decode([token_id], special_token_policy=SpecialTokenPolicy.IGNORE)
            if text:
                on_text(text)

            if i > 0 and i % 256 == 0:
                mx.clear_cache()

            y = next_y

        return n_to_decode, False

    # Encoder state
    audio_tail = None
    conv1_tail = None
    conv2_tail = None
    encoder_cache = None
    ds_buf = None

    # Bounded buffers and counters
    pending_audio = np.zeros(0, dtype=np.float32)
    audio_embeds: mx.array | None = None
    n_audio_samples_fed = 0
    n_total_decoded = 0
    first_cycle = True
    prefilled = False

    # We'll feed audio in moderately sized blocks to avoid encoding far past EOS.
    FEED_BLOCK_SAMPLES = 50 * SAMPLES_PER_TOKEN  # ~4s at 16kHz

    # When we hit EOS (segment boundary), restart slightly before the computed boundary.
    OVERLAP_TOKENS = 12  # ~1s

    segment_start = 0
    idx = 0

    def reset_segment_state() -> None:
        nonlocal audio_tail, conv1_tail, conv2_tail, encoder_cache, ds_buf
        nonlocal pending_audio, audio_embeds, n_audio_samples_fed
        nonlocal n_total_decoded, first_cycle, prefilled
        nonlocal cache, y

        audio_tail = None
        conv1_tail = None
        conv2_tail = None
        encoder_cache = None
        ds_buf = None

        pending_audio = np.zeros(0, dtype=np.float32)
        audio_embeds = None
        n_audio_samples_fed = 0
        n_total_decoded = 0
        first_cycle = True
        prefilled = False

        cache = None
        y = None

    while True:
        # Feed more audio into pending buffer
        if idx < len(audio):
            new = audio[idx : idx + FEED_BLOCK_SAMPLES]
            idx += len(new)
            if len(new) > 0:
                pending_audio = np.append(pending_audio, new)

        # Encode as much as we can, token-aligned
        if first_cycle and len(pending_audio) >= SAMPLES_PER_TOKEN:
            left_pad = np.zeros(32 * SAMPLES_PER_TOKEN, dtype=np.float32)
            n_feed = (len(pending_audio) // SAMPLES_PER_TOKEN) * SAMPLES_PER_TOKEN
            chunk = np.concatenate([left_pad, pending_audio[:n_feed]])
            pending_audio = pending_audio[n_feed:]
            n_audio_samples_fed += n_feed

            mel, audio_tail = log_mel_spectrogram_step(chunk, audio_tail)
            new_embeds, conv1_tail, conv2_tail, encoder_cache, ds_buf = model.encode_step(
                mel, conv1_tail, conv2_tail, encoder_cache, ds_buf
            )
            if new_embeds is not None:
                mx.eval(new_embeds)
                audio_embeds = new_embeds
            first_cycle = False

        elif (not first_cycle) and len(pending_audio) >= SAMPLES_PER_TOKEN:
            n_feed = (len(pending_audio) // SAMPLES_PER_TOKEN) * SAMPLES_PER_TOKEN
            chunk = pending_audio[:n_feed]
            pending_audio = pending_audio[n_feed:]
            n_audio_samples_fed += n_feed

            mel, audio_tail = log_mel_spectrogram_step(chunk, audio_tail)
            new_embeds, conv1_tail, conv2_tail, encoder_cache, ds_buf = model.encode_step(
                mel, conv1_tail, conv2_tail, encoder_cache, ds_buf
            )
            if new_embeds is not None:
                mx.eval(new_embeds)
                audio_embeds = (
                    mx.concatenate([audio_embeds, new_embeds])
                    if audio_embeds is not None
                    else new_embeds
                )

        # Decode whatever is available
        if audio_embeds is not None:
            safe_total = 32 + n_audio_samples_fed // SAMPLES_PER_TOKEN
            n_decodable = min(audio_embeds.shape[0], safe_total - n_total_decoded)

            if n_decodable > 0:
                if not prefilled:
                    if n_total_decoded + audio_embeds.shape[0] < prefix_len:
                        # need more audio for prefix
                        pass
                    else:
                        cache = [RotatingKVCache(sliding_window) for _ in range(n_layers)]
                        prefix_embeds = text_embeds + audio_embeds[:prefix_len]
                        prefix_embeds = prefix_embeds[None, :, :]
                        logits = model.decode(prefix_embeds, t_cond, "causal", cache)
                        mx.eval(logits, *[x for c in cache for x in (c.keys, c.values)])
                        y = sample(logits)
                        mx.async_eval(y)

                        audio_embeds = audio_embeds[prefix_len:]
                        n_total_decoded = prefix_len
                        prefilled = True

                        n_decodable = min(audio_embeds.shape[0], safe_total - n_total_decoded) if audio_embeds is not None else 0

                if prefilled and n_decodable > 0 and audio_embeds is not None and cache is not None and y is not None:
                    n_consumed, hit_eos = decode_steps(audio_embeds, n_decodable)
                    n_total_decoded += n_consumed

                    # Trim consumed embeds
                    if audio_embeds.shape[0] > n_consumed:
                        audio_embeds = audio_embeds[n_consumed:]
                    else:
                        audio_embeds = None

                    if hit_eos:
                        if stop_on_eos:
                            break

                        # Start a new segment. We compute an approximate audio boundary
                        # from how many audio-positions we decoded, and restart a bit
                        # before that boundary to avoid losing words.
                        consumed_tokens = max(0, n_total_decoded - 32)
                        restart_tokens = max(0, consumed_tokens - OVERLAP_TOKENS)
                        new_start = segment_start + restart_tokens * SAMPLES_PER_TOKEN

                        # Ensure forward progress.
                        min_advance = SAMPLES_PER_TOKEN
                        if new_start <= segment_start:
                            new_start = segment_start + min_advance

                        segment_start = min(new_start, len(audio))
                        idx = segment_start
                        reset_segment_state()
                        continue

        # Exit condition: no more input audio to feed, and we can't encode/decode more
        if idx >= len(audio) and len(pending_audio) < SAMPLES_PER_TOKEN:
            break

    # Final flush: feed remaining audio + right pad through incremental pipeline.
    if not first_cycle:
        right_pad = np.zeros(17 * SAMPLES_PER_TOKEN, dtype=np.float32)
        flush_chunk = np.concatenate([pending_audio, right_pad])

        mel, audio_tail = log_mel_spectrogram_step(flush_chunk, audio_tail)
        new_embeds, conv1_tail, conv2_tail, encoder_cache, ds_buf = model.encode_step(
            mel, conv1_tail, conv2_tail, encoder_cache, ds_buf
        )
        if new_embeds is not None:
            mx.eval(new_embeds)
            audio_embeds = (
                mx.concatenate([audio_embeds, new_embeds])
                if audio_embeds is not None
                else new_embeds
            )

        if prefilled and audio_embeds is not None and cache is not None and y is not None:
            decode_steps(audio_embeds, audio_embeds.shape[0])

        # Flush last pending token
        if y is not None:
            token_id = y.item()
            if token_id != eos_token_id:
                text = sp.decode([token_id], special_token_policy=SpecialTokenPolicy.IGNORE)
                if text:
                    on_text(text)

    return "".join(chunks) if chunks else ""


def transcribe(
    audio_path: str,
    model_path: str = "mlx-community/Voxtral-Mini-4B-Realtime-6bit",
    temperature: float = 0.0,
    *,
    stop_on_eos: bool = False,
    segment_separator: str = "\n",
    chunk_seconds: float | None = None,
    chunk_overlap_seconds: float = 2.0,
    on_text: Callable[[str], None] | None = None,
) -> str:
    model, sp, config = load_model(model_path)

    transcription_format = (
        config.get("multimodal", {})
        .get("whisper_model_args", {})
        .get("encoder_args", {})
        .get("audio_encoding_args", {})
        .get("transcription_format")
    )

    audio = load_audio(audio_path)

    # For the realtime models, chunking is the most reliable way to process long files.
    # Rationale: these models emit lots of streaming control tokens; running them over
    # very long audio in one go can yield unexpectedly short output.
    if transcription_format == "streaming":
        # Default chunk size for streaming models, unless explicitly overridden.
        eff_chunk_seconds = 120.0 if chunk_seconds is None else float(chunk_seconds)
        if eff_chunk_seconds <= 0:
            eff_chunk_seconds = 120.0

        parts: list[str] = []

        def emit(s: str) -> None:
            parts.append(s)
            if on_text is not None:
                on_text(s)

        prompt_tokens, n_delay_tokens = _build_prompt_tokens(sp)

        sr = 16000
        chunk_len = int(eff_chunk_seconds * sr)
        overlap_len = int(max(0.0, chunk_overlap_seconds) * sr)
        if overlap_len >= chunk_len:
            overlap_len = max(0, chunk_len // 10)

        start = 0
        first = True
        while start < len(audio):
            end = min(len(audio), start + chunk_len)

            if not first and segment_separator:
                emit(segment_separator)
            first = False

            chunk_audio = audio[start:end]

            def on_token(token_id: int) -> None:
                piece = sp.decode(
                    [token_id], special_token_policy=SpecialTokenPolicy.IGNORE
                )
                if piece:
                    emit(piece)

            generate_from_audio(
                model,
                chunk_audio,
                prompt_tokens,
                n_delay_tokens,
                temperature=temperature,
                eos_token_id=sp.eos_id,
                stop_on_eos=stop_on_eos,
                on_token=on_token,
            )

            if end >= len(audio):
                break

            # Advance, keeping overlap
            start = max(0, end - overlap_len)
            if start >= end:
                start = end

        return "".join(parts)

    # Fallback: offline encode + decode
    prompt_tokens, n_delay_tokens = _build_prompt_tokens(sp)

    output_tokens = generate(
        model,
        audio_path,
        prompt_tokens,
        n_delay_tokens=n_delay_tokens,
        temperature=temperature,
        eos_token_id=sp.eos_id,
        stop_on_eos=stop_on_eos,
    )

    text = sp.decode(output_tokens, special_token_policy=SpecialTokenPolicy.IGNORE)
    if on_text is not None:
        on_text(text)
    return text


def main():
    parser = argparse.ArgumentParser(description="Voxtral Mini Realtime speech-to-text")
    parser.add_argument("--audio", default=None, help="Path to audio file (omit to stream from mic)")
    parser.add_argument("--model", default="mlx-community/Voxtral-Mini-4B-Realtime-6bit", help="Model path or HF model ID")
    parser.add_argument("--temp", type=float, default=0.0, help="Sampling temperature (0 = greedy)")
    parser.add_argument(
        "--chunk-seconds",
        type=float,
        default=None,
        help="Chunk size in seconds for file transcription (streaming models default to 120s)",
    )
    parser.add_argument(
        "--chunk-overlap-seconds",
        type=float,
        default=2.0,
        help="Chunk overlap in seconds for file transcription",
    )
    parser.add_argument("--output", default=None, help="Write transcript to file")
    parser.add_argument(
        "--stream-output",
        action="store_true",
        help="Stream transcript to --output while decoding",
    )
    parser.add_argument(
        "--no-stdout",
        action="store_true",
        help="Do not print transcript to stdout",
    )
    parser.add_argument(
        "--stop-on-eos",
        action="store_true",
        help="Stop decoding at the first EOS token (legacy behavior)",
    )
    parser.add_argument(
        "--list-input-devices",
        action="store_true",
        help="List available input devices and exit",
    )
    parser.add_argument(
        "-s",
        "--input-device",
        nargs="?",
        const="__PROMPT__",
        default=None,
        help="Input device index/name; pass -s alone to select interactively",
    )
    args = parser.parse_args()

    if args.stream_output and args.output is None:
        parser.error("--stream-output requires --output")

    if args.list_input_devices:
        from .stream import list_input_devices
        list_input_devices()
        return

    if args.audio is not None:
        text: str

        if args.output is not None:
            out_path = Path(args.output)
            out_path.parent.mkdir(parents=True, exist_ok=True)

            with open(out_path, "w", encoding="utf-8") as f:
                if args.stream_output:
                    buffered_chars = 0
                    last_flush = time.monotonic()

                    def on_text(chunk: str) -> None:
                        nonlocal buffered_chars, last_flush
                        f.write(chunk)
                        buffered_chars += len(chunk)
                        now = time.monotonic()
                        if buffered_chars >= 4096 or (now - last_flush) >= 1.0:
                            f.flush()
                            buffered_chars = 0
                            last_flush = now

                    text = transcribe(
                        args.audio,
                        model_path=args.model,
                        temperature=args.temp,
                        stop_on_eos=args.stop_on_eos,
                        chunk_seconds=args.chunk_seconds,
                        chunk_overlap_seconds=args.chunk_overlap_seconds,
                        on_text=on_text,
                    )
                    f.flush()
                else:
                    text = transcribe(
                        args.audio,
                        model_path=args.model,
                        temperature=args.temp,
                        stop_on_eos=args.stop_on_eos,
                        chunk_seconds=args.chunk_seconds,
                        chunk_overlap_seconds=args.chunk_overlap_seconds,
                    )
                    f.write(text)
                    f.flush()
        else:
            text = transcribe(
                args.audio,
                model_path=args.model,
                temperature=args.temp,
                stop_on_eos=args.stop_on_eos,
                chunk_seconds=args.chunk_seconds,
                chunk_overlap_seconds=args.chunk_overlap_seconds,
            )

        if not args.no_stdout:
            print(text)
    else:
        from .stream import prompt_for_input_device, stream_transcribe
        selected = (
            prompt_for_input_device()
            if args.input_device == "__PROMPT__"
            else args.input_device
        )

        stream_transcribe(
            model_path=args.model,
            temperature=args.temp,
            input_device=selected,
        )
