#!/usr/bin/env python3
"""End-to-end smoke test for user-created Arena battle rooms."""
import json
import secrets
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
server = root / "server.py"
accounts = root / "data" / "accounts.json"
backup = accounts.with_suffix(".json.smoke_backup")
port = 19100


def client() -> socket.socket:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.connect(("127.0.0.1", port))
    return sock


def send(sock: socket.socket, msg: dict) -> None:
    sock.send(json.dumps(msg, ensure_ascii=False).encode("utf-8"))


def recv_type(sock: socket.socket, wanted: str, timeout: float = 3.0, predicate=None) -> dict:
    end = time.time() + timeout
    while time.time() < end:
        sock.settimeout(max(0.05, end - time.time()))
        msg = json.loads(sock.recv(65535).decode("utf-8"))
        if msg.get("type") == wanted and (predicate is None or predicate(msg)):
            return msg
    raise AssertionError(f"did not receive {wanted}")


def register(sock: socket.socket, login: str) -> int:
    send(sock, {"type": "hello", "protocol": 8, "client": "smoke", "map": "lobby"})
    welcome = recv_type(sock, "welcome")
    assert welcome["map"] == "lobby"
    send(sock, {"type": "register", "seq": 1, "login": login, "password": "secret12"})
    auth = recv_type(sock, "auth_result")
    assert auth["ok"], auth
    return int(welcome["player_id"])


shutil.copy2(accounts, backup)
proc = subprocess.Popen(
    [sys.executable, str(server), "--host", "127.0.0.1", "--port", str(port), "--asset-port", str(port + 1)],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
time.sleep(0.8)

sockets: list[socket.socket] = []
try:
    suffix = secrets.token_hex(3)
    a, b, c = client(), client(), client()
    sockets.extend((a, b, c))
    id_a = register(a, "smA" + suffix)
    id_b = register(b, "smB" + suffix)
    id_c = register(c, "smC" + suffix)

    # Every user-created battle is Arena, but has independent settings/state.
    send(a, {"type": "create_battle", "seq": 2, "name": "Room A", "kill_limit": 3, "max_players": 8, "map": "arena"})
    created_a = recv_type(a, "battle_created")
    assert created_a["ok"]
    room_a = int(created_a["battle"]["id"])
    assert created_a["battle"]["map"] == "arena"
    assert int(created_a["battle"]["kill_limit"]) == 3

    send(b, {"type": "create_battle", "seq": 2, "name": "Room B", "kill_limit": 7, "max_players": 8, "map": "arena"})
    created_b = recv_type(b, "battle_created")
    assert created_b["ok"]
    room_b = int(created_b["battle"]["id"])
    assert room_a != room_b
    assert created_b["battle"]["map"] == "arena"
    assert int(created_b["battle"]["kill_limit"]) == 7

    # Battle browser exposes both rooms and their independent victory limits.
    send(c, {"type": "list_battles", "seq": 2})
    listing = recv_type(c, "battles", predicate=lambda m: "seq" in m)
    by_id = {int(item["id"]): item for item in listing["battles"]}
    assert by_id[room_a]["name"] == "Room A"
    assert int(by_id[room_a]["kill_limit"]) == 3
    assert int(by_id[room_b]["kill_limit"]) == 7

    # Join separate battle instances of the same Arena.
    send(a, {"type": "join_battle", "seq": 3, "battle_id": room_a})
    joined_a = recv_type(a, "battle_joined")
    assert joined_a["ok"] and int(joined_a["match"]["kill_limit"]) == 3

    send(c, {"type": "join_battle", "seq": 3, "battle_id": room_a})
    joined_c = recv_type(c, "battle_joined")
    assert joined_c["ok"]

    send(b, {"type": "join_battle", "seq": 3, "battle_id": room_b})
    joined_b = recv_type(b, "battle_joined")
    assert joined_b["ok"] and int(joined_b["match"]["kill_limit"]) == 7

    # Room snapshots cannot leak between two Arena battle IDs.
    send(a, {"type": "state", "p": [0, 5, 0], "yaw": 0, "turret": 0, "speed": 0, "left_track": 0, "right_track": 0, "firing": False})
    send(c, {"type": "state", "p": [3, 5, 0], "yaw": 0, "turret": 0, "speed": 0, "left_track": 0, "right_track": 0, "firing": False})
    send(b, {"type": "state", "p": [20, 5, 0], "yaw": 0, "turret": 0, "speed": 0, "left_track": 0, "right_track": 0, "firing": False})
    snap_a = recv_type(a, "snapshot", predicate=lambda m: m.get("map") == joined_a["map"])
    snap_b = recv_type(b, "snapshot", predicate=lambda m: m.get("map") == joined_b["map"])
    ids_a = {int(player["id"]) for player in snap_a["players"]}
    ids_b = {int(player["id"]) for player in snap_b["players"]}
    assert id_a in ids_a and id_c in ids_a and id_b not in ids_a
    assert id_b in ids_b and id_a not in ids_b and id_c not in ids_b

    print("OK: Arena battle creation/list/join, per-room kill limits, isolated snapshots")
finally:
    for sock in sockets:
        sock.close()
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)
    if backup.exists():
        shutil.move(backup, accounts)
