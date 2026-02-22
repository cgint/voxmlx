#!/usr/bin/env python3
import base64
import json
import os
import struct
import sys
import threading
import time
from typing import Any


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


_model_lock = threading.Lock()
_model: Any = None


def get_model() -> Any:
    global _model
    with _model_lock:
        if _model is None:
            model_name = os.environ.get("KITTENTTS_MODEL", "KittenML/kitten-tts-mini-0.8")
            sys.path.append(os.environ.get("KITTENTTS_PATH", "../KittenTTS"))
            from kittentts import KittenTTS

            _model = KittenTTS(model_name)
    return _model


def main() -> None:
    sessions: dict[str, dict[str, Any]] = {}
    default_voice = os.environ.get("KITTENTTS_VOICE", "Hugo")
    default_speed = float(os.environ.get("KITTENTTS_SPEED", "1.0"))

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
            sessions[session_id] = {"created_at_ms": int(time.time() * 1000)}
            send_packet({"event": "session_started", "session_id": session_id})
            continue

        if cmd == "stop_session":
            sessions.pop(session_id, None)
            send_packet({"event": "session_stopped", "session_id": session_id})
            continue

        if cmd == "speak_text":
            if session_id not in sessions:
                send_packet({"event": "error", "session_id": session_id, "message": "unknown session"})
                continue

            text = str(msg.get("text", "")).strip()
            if not text:
                send_packet({"event": "session_done", "session_id": session_id})
                continue

            voice = str(msg.get("voice", default_voice))
            speed = float(msg.get("speed", default_speed))

            try:
                model = get_model()
                for seq, chunk in enumerate(model.generate_stream(text, voice=voice, speed=speed)):
                    chunk_f32 = chunk.squeeze().astype("float32")
                    pcm_b64 = base64.b64encode(chunk_f32.tobytes()).decode("ascii")
                    send_packet(
                        {
                            "event": "audio_chunk",
                            "session_id": session_id,
                            "seq": seq,
                            "pcm_b64": pcm_b64,
                            "sample_rate": 24000,
                            "channels": 1,
                            "format": "f32le",
                        }
                    )
                send_packet({"event": "session_done", "session_id": session_id})
            except Exception as e:
                send_packet({"event": "error", "session_id": session_id, "message": f"tts failed: {e}"})

            continue

        send_packet({"event": "error", "session_id": session_id, "message": f"unknown cmd: {cmd}"})


if __name__ == "__main__":
    main()
