#!/usr/bin/env python3
import json
import os
import struct
import sys


def recv_packet():
    header = sys.stdin.buffer.read(4)
    if not header or len(header) < 4:
        return None
    length = struct.unpack(">I", header)[0]
    payload = sys.stdin.buffer.read(length)
    if len(payload) < length:
        return None
    return payload


def send_packet(message):
    data = json.dumps(message).encode("utf-8")
    try:
        sys.stdout.buffer.write(struct.pack(">I", len(data)))
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
        return True
    except BrokenPipeError:
        return False


def main():
    sessions = {}
    if not send_packet({"event": "ready"}):
        return

    while True:
        payload = recv_packet()
        if payload is None:
            break

        msg = json.loads(payload.decode("utf-8"))
        cmd = msg.get("cmd")
        sid = msg.get("session_id")

        if cmd == "shutdown":
            send_packet({"event": "bye"})
            break
        elif cmd == "start_session":
            sessions[sid] = []
            send_packet({"event": "session_started", "session_id": sid})
        elif cmd == "audio_chunk":
            sessions.setdefault(sid, []).append(msg.get("pcm_b64", ""))
        elif cmd == "stop_session":
            chunks = sessions.pop(sid, [])
            send_packet({"event": "final", "session_id": sid, "text": f"chunks={len(chunks)}"})


if __name__ == "__main__":
    try:
        main()
    finally:
        os._exit(0)
