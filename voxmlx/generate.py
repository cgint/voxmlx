import mlx.core as mx

from collections.abc import Callable

import numpy as np

from .audio import SAMPLES_PER_TOKEN, load_audio, log_mel_spectrogram, pad_audio
from .cache import RotatingKVCache
from .model import VoxtralRealtime


def generate_from_audio(
    model: VoxtralRealtime,
    audio: np.ndarray,
    prompt_tokens: list[int],
    n_delay_tokens: int,
    temperature: float = 0.0,
    eos_token_id: int = 2,
    sliding_window: int = 8192,
    stop_on_eos: bool = True,
    on_token: Callable[[int], None] | None = None,
    on_eos: Callable[[], None] | None = None,
    *,
    n_left_pad_tokens: int = 32,
    restart_overlap_tokens: int = 12,
    max_segments: int = 10_000,
) -> list[int]:
    """Generate output token IDs for a given audio array.

    Notes:
    - `audio` must be mono float32 in range [-1, 1] at 16kHz.
    - Voxtral realtime models may emit EOS as a *segment boundary* (not end-of-file).
      If `stop_on_eos` is False, this function will restart decoding on the remaining
      audio after EOS, best-effort.

    Tradeoff:
    - Restarting after EOS re-encodes audio for subsequent segments (slower), but
      matches the model's intended streaming behavior more closely than trying to
      continue decoding past EOS with a single cache.
    """

    def sample(logits):
        if temperature <= 0:
            return mx.argmax(logits[0, -1:], axis=-1).squeeze()
        return mx.random.categorical(logits[0, -1:] / temperature).squeeze()

    def _generate_once(segment_audio: np.ndarray) -> tuple[list[int], int, bool]:
        """Generate a single segment.

        Returns: (tokens, stopped_pos, hit_eos)
        where stopped_pos is the current audio-embed position at stop.
        """
        # 1) Pad for streaming semantics + compute mel spectrogram
        padded = pad_audio(segment_audio, n_left_pad_tokens=n_left_pad_tokens)
        mel = log_mel_spectrogram(padded)  # [n_mels, T]

        # 2) Encode audio
        audio_embeds = model.encode(mel)  # [N_audio, 3072]
        N_audio = audio_embeds.shape[0]

        # 3) Time conditioning (uses delay tokens only, not left pad)
        t_cond = model.time_embedding(mx.array([n_delay_tokens], dtype=mx.float32))  # [1, dim]

        # 4) Build prefix embeddings
        prefix_len = len(prompt_tokens)
        prompt_ids = mx.array([prompt_tokens])  # [1, prefix_len]
        text_embeds = model.language_model.embed(prompt_ids)[0]  # [prefix_len, 3072]

        prefix_embeds = text_embeds + audio_embeds[:prefix_len]  # [prefix_len, 3072]
        prefix_embeds = prefix_embeds[None, :, :]  # [1, prefix_len, 3072]

        n_layers = len(model.language_model.layers)
        cache = [RotatingKVCache(sliding_window) for _ in range(n_layers)]

        def step(token, pos):
            token_embed = model.language_model.embed(token.reshape(1, 1))[0, 0]
            step_embed = (audio_embeds[pos] + token_embed)[None, None, :]
            logits = model.decode(step_embed, t_cond, mask=None, cache=cache)
            return sample(logits)

        # 5) Prefill
        logits = model.decode(prefix_embeds, t_cond, "causal", cache)
        mx.eval(logits, *[x for c in cache for x in (c.keys, c.values)])

        # 6) Decode
        y = sample(logits)
        mx.async_eval(y)

        output_tokens: list[int] = []
        pos = prefix_len
        hit_eos = False

        while pos < N_audio:
            next_y = step(y, pos)
            mx.async_eval(next_y)

            token_id = y.item()
            if token_id == eos_token_id:
                hit_eos = True
                break

            output_tokens.append(token_id)
            if on_token is not None:
                on_token(token_id)

            if pos % 256 == 0:
                mx.clear_cache()

            y = next_y
            pos += 1

        return output_tokens, pos, hit_eos

    # Multi-segment driver
    out: list[int] = []
    remaining = audio

    seg = 0
    while True:
        seg += 1
        if seg > max_segments:
            break

        tokens, stopped_pos, hit_eos = _generate_once(remaining)
        out.extend(tokens)

        if stop_on_eos or not hit_eos:
            break

        # EOS as segment boundary: restart on remaining audio.
        if on_eos is not None:
            on_eos()

        # Map stopped_pos (embed position) -> approximate sample offset into *unpadded* audio.
        # Each embed corresponds to one SAMPLES_PER_TOKEN audio span.
        # The first n_left_pad_tokens embeds correspond to left padding.
        consumed_tokens = max(0, stopped_pos - n_left_pad_tokens)
        # Back up slightly to reduce boundary loss.
        consumed_tokens = max(0, consumed_tokens - restart_overlap_tokens)
        consumed_samples = consumed_tokens * SAMPLES_PER_TOKEN

        if consumed_samples <= 0:
            # Safety: ensure forward progress.
            consumed_samples = min(len(remaining), SAMPLES_PER_TOKEN)

        if consumed_samples >= len(remaining):
            break

        remaining = remaining[consumed_samples:]

    return out


def generate(
    model: VoxtralRealtime,
    audio_path: str,
    prompt_tokens: list[int],
    n_delay_tokens: int,
    temperature: float = 0.0,
    eos_token_id: int = 2,
    sliding_window: int = 8192,
    stop_on_eos: bool = True,
    on_token: Callable[[int], None] | None = None,
    on_eos: Callable[[], None] | None = None,
) -> list[int]:
    audio = load_audio(audio_path)
    return generate_from_audio(
        model,
        audio,
        prompt_tokens,
        n_delay_tokens,
        temperature=temperature,
        eos_token_id=eos_token_id,
        sliding_window=sliding_window,
        stop_on_eos=stop_on_eos,
        on_token=on_token,
        on_eos=on_eos,
    )
