__version__ = "0.0.1"

import argparse
from pathlib import Path

from mistral_common.tokens.tokenizers.base import SpecialTokenPolicy
from mistral_common.tokens.tokenizers.tekken import Tekkenizer

from .generate import generate
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


def load_model(model_path: str = "mistralai/Voxtral-Mini-4B-Realtime-2602"):
    if not Path(model_path).exists():
        model_path = download_model(model_path)
    else:
        model_path = Path(model_path)

    model, config = _load_weights(model_path)
    sp = _load_tokenizer(model_path)
    return model, sp, config


def transcribe(
    audio_path: str,
    model_path: str = "mistralai/Voxtral-Mini-4B-Realtime-2602",
    language: str = "en",
    max_tokens: int = 4096,
    temperature: float = 0.0,
) -> str:
    model, sp, config = load_model(model_path)

    prompt_tokens, n_delay_tokens = _build_prompt_tokens(sp)

    output_tokens = generate(
        model,
        audio_path,
        prompt_tokens,
        n_delay_tokens=n_delay_tokens,
        temperature=temperature,
        eos_token_id=sp.eos_id,
    )

    return sp.decode(output_tokens, special_token_policy=SpecialTokenPolicy.IGNORE)


def main():
    parser = argparse.ArgumentParser(description="Voxtral Mini Realtime speech-to-text")
    parser.add_argument("--audio", default=None, help="Path to audio file (omit to stream from mic)")
    parser.add_argument("--model", default="mistralai/Voxtral-Mini-4B-Realtime-2602", help="Model path or HF model ID")
    parser.add_argument("--language", default="en", help="Language code (e.g. en, fr, de)")
    parser.add_argument("--max-tokens", type=int, default=4096, help="Maximum output tokens")
    parser.add_argument("--temperature", type=float, default=0.0, help="Sampling temperature (0 = greedy)")
    parser.add_argument("--duration", type=float, default=None, help="Max recording seconds (streaming only, default: until Ctrl+C)")
    args = parser.parse_args()

    if args.audio is not None:
        text = transcribe(
            args.audio,
            model_path=args.model,
            language=args.language,
            max_tokens=args.max_tokens,
            temperature=args.temperature,
        )
        print(text)
    else:
        from .stream import stream_transcribe

        stream_transcribe(
            model_path=args.model,
            temperature=args.temperature,
            duration=args.duration,
        )
