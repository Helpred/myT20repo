#!/usr/bin/env python3
"""Smoke test: a new client/scenes/maps/*.tscn becomes a server-selectable map automatically."""
from __future__ import annotations

import json
import secrets
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

project = Path(__file__).resolve().parents[2]
server_root = project / "server"
server = server_root / "server.py"
accounts = server_root / "data" / "accounts.json"
backup = accounts.with_suffix(".json.map_auto_backup")
map_root = project / "client" / "scenes" / "maps"
source_map = map_root / "arena_editable.tscn"
test_map = map_root / "auto_day_test.tscn"
port = 19130


def send(sock: socket.socket, msg: dict) -> None:
    sock.send(json.dumps(msg, ensure_ascii=False).encode("utf-8"))


def recv_type(sock: socket.socket, wanted: str, timeout: float = 4.0) -> dict:
    end = time.time() + timeout
    while time.time() < end:
        sock.settimeout(max(0.05, end - time.time()))
        msg = json.loads(sock.recv(65535).decode("utf-8"))
        if msg.get("type") == wanted:
            return msg
    raise AssertionError(f"did not receive {wanted}")


shutil.copy2(accounts, backup)
shutil.copy2(source_map, test_map)
text = test_map.read_text(encoding="utf-8")
root_line_end = text.find("\n", text.find("[node name="))
text = text[: root_line_end + 1] + 'metadata/tanki_map_name = "Авто-дневная карта"\n' + text[root_line_end + 1 :]
test_map.write_text(text, encoding="utf-8")

proc = subprocess.Popen(
    [sys.executable, str(server), "--host", "127.0.0.1", "--port", str(port), "--asset-port", str(port + 1)],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
time.sleep(0.9)
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.connect(("127.0.0.1", port))

try:
    send(sock, {"type": "hello", "protocol": 8, "client": "map-auto-test", "map": "lobby"})
    recv_type(sock, "welcome")
    send(sock, {"type": "register", "seq": 1, "login": "map" + secrets.token_hex(3), "password": "secret12"})
    auth = recv_type(sock, "auth_result")
    assert auth["ok"], auth

    send(sock, {
        "type": "create_battle", "seq": 2, "name": "Auto map room", "map": "auto_day_test",
        "kill_limit": 4, "max_players": 8,
    })
    created = recv_type(sock, "battle_created")
    assert created["ok"], created
    assert created["battle"]["map"] == "auto_day_test"
    assert created["battle"]["map_name"] == "Авто-дневная карта"

    send(sock, {"type": "join_battle", "seq": 3, "battle_id": created["battle"]["id"]})
    joined = recv_type(sock, "battle_joined")
    assert joined["ok"], joined
    assert joined["map_key"] == "auto_day_test"
    print("OK: .tscn map auto-discovery/create/join")
finally:
    sock.close()
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)
    if test_map.exists():
        test_map.unlink()
    if backup.exists():
        shutil.move(backup, accounts)
