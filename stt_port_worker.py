#!/usr/bin/env python3
import base64
import json
import os
import struct
import sys
import tempfile
import threading
import time
import wave
from typing import Any

from mistral_common.tokens.tokenizers.base import SpecialTokenPolicy

from voxmlx import _build_prompt_tokens, load_model
from voxmlx.generate import generate

MODEL_PATH = os.environ.get("VOXMLX_MODEL", "mlx-community/Voxtral-Mini-4B-Realtime-6bit")
TEMPERATURE = float(os.environ.get("VOXMLX_TEMP", "0.0"))
PARTIAL_INTERVAL_SEC = float(os.environ.get("VOXMLX_PARTIAL_INTERVAL_SEC", "2.0"))
MIN_CHUNKS_FOR_PARTIAL = int(os.environ.get("VOXMLX_MIN_CHUNKS_FOR_PARTIAL", "10"))

_model_lock = threading.Lock()
_model_bundle: tuple[Any, Any, Any, list[int], int] | None = None


def recv_packet() -> bytes | None:
    header = sys.stdin.buffer.read(4)
    if not header or len(header) < 4:
        return None
    length = struct.unpack(">I", header)[0]
    if length == 0:
        return b""
    payload = sys.stdin.buffer.read(length)
    if len(payload) < length:
        return None
    return payload


def send_packet(message: dict[str, Any]) -> None:
    data = json.dumps(message).encode("utf-8")
    sys.stdout.buffer.write(struct.pack(">I", len(data)))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def get_model_bundle() -> tuple[Any, Any, Any, list[int], int]:
    global _model_bundle
    with _model_lock:
        if _model_bundle is None:
            model, sp, config = load_model(MODEL_PATH)
            prompt_tokens, n_delay_tokens = _build_prompt_tokens(sp)
            _model_bundle = (model, sp, config, prompt_tokens, n_delay_tokens)
    return _model_bundle


def pcm_f32le_to_wav_path(pcm_bytes: bytes) -> str:
    floats = struct.unpack("<" + "f" * (len(pcm_bytes) // 4), pcm_bytes)
    pcm16 = bytearray()
    for x in floats:
        v = max(-1.0, min(1.0, float(x)))
        s = int(v * 32767.0)
        pcm16.extend(struct.pack("<h", s))

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name

    with wave.open(wav_path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(16000)
        wf.writeframes(bytes(pcm16))

    return wav_path


def transcribe_pcm_bytes(pcm_bytes: bytes) -> str:
    if not pcm_bytes:
        return ""

    model, sp, _config, prompt_tokens, n_delay_tokens = get_model_bundle()
    wav_path = pcm_f32le_to_wav_path(pcm_bytes)
    try:
        output_tokens = generate(
            model,
            wav_path,
            prompt_tokens,
            n_delay_tokens=n_delay_tokens,
            temperature=TEMPERATURE,
            eos_token_id=sp.eos_id,
        )
        return sp.decode(output_tokens, special_token_policy=SpecialTokenPolicy.IGNORE).strip()
    finally:
        try:
            os.remove(wav_path)
        except OSError:
            pass


def partial_loop(session_id: str, sessions: dict[str, dict[str, Any]], sessions_lock: threading.Lock) -> None:
    last_seen_count = 0

    while True:
        with sessions_lock:
            session = sessions.get(session_id)
            if session is None:
                return

            with session["lock"]:
                if session["stop"]:
                    return
                chunk_count = session["chunk_count"]
                if chunk_count == last_seen_count or chunk_count < MIN_CHUNKS_FOR_PARTIAL:
                    snapshot = b""
                else:
                    snapshot = b"".join(session["chunks"])
                    last_seen_count = chunk_count

        if snapshot:
            try:
                text = transcribe_pcm_bytes(snapshot)
                if text:
                    send_packet(
                        {
                            "event": "partial",
                            "session_id": session_id,
                            "text": text,
                            "chunk_count": last_seen_count,
                        }
                    )
            except Exception as e:
                send_packet(
                    {
                        "event": "error",
                        "session_id": session_id,
                        "message": f"partial transcribe failed: {e}",
                    }
                )

        time.sleep(PARTIAL_INTERVAL_SEC)


def main() -> None:
    sessions: dict[str, dict[str, Any]] = {}
    sessions_lock = threading.Lock()

    send_packet({"event": "ready", "ts_ms": int(time.time() * 1000)})

    while True:
        payload = recv_packet()
        if payload is None:
            break

        try:
            msg = json.loads(payload.decode("utf-8"))
        except Exception as e:
            send_packet({"event": "error", "message": f"invalid json: {e}"})
            continue

        cmd = msg.get("cmd")
        session_id = str(msg.get("session_id", ""))

        if cmd == "shutdown":
            send_packet({"event": "bye"})
            break

        if not session_id:
            send_packet({"event": "error", "message": "missing session_id"})
            continue

        if cmd == "start_session":
            with sessions_lock:
                session = {
                    "chunks": [],
                    "chunk_count": 0,
                    "started_at_ms": int(time.time() * 1000),
                    "lock": threading.Lock(),
                    "stop": False,
                    "thread": None,
                }
                sessions[session_id] = session

                t = threading.Thread(
                    target=partial_loop, args=(session_id, sessions, sessions_lock), daemon=True
                )
                session["thread"] = t
                t.start()

            send_packet({"event": "session_started", "session_id": session_id})

        elif cmd == "audio_chunk":
            with sessions_lock:
                session = sessions.get(session_id)
            if session is None:
                send_packet({"event": "error", "session_id": session_id, "message": "unknown session"})
                continue

            pcm_b64 = msg.get("pcm_b64", "")
            try:
                pcm = base64.b64decode(pcm_b64)
            except Exception:
                send_packet({"event": "error", "session_id": session_id, "message": "invalid base64"})
                continue

            with session["lock"]:
                session["chunks"].append(pcm)
                session["chunk_count"] += 1

        elif cmd == "stop_session":
            with sessions_lock:
                session = sessions.get(session_id)
            if session is None:
                send_packet({"event": "error", "session_id": session_id, "message": "unknown session"})
                continue

            with session["lock"]:
                session["stop"] = True
                pcm_bytes = b"".join(session["chunks"])

            try:
                text = transcribe_pcm_bytes(pcm_bytes)
                send_packet({"event": "final", "session_id": session_id, "text": text})
            except Exception as e:
                send_packet(
                    {
                        "event": "error",
                        "session_id": session_id,
                        "message": f"final transcribe failed: {e}",
                    }
                )

            with sessions_lock:
                sessions.pop(session_id, None)

        else:
            send_packet({"event": "error", "session_id": session_id, "message": f"unknown cmd: {cmd}"})


if __name__ == "__main__":
    main()
