#!/usr/bin/env python3
"""Authoritative account/economy/combat server for the Godot Tanki 2.0 prototype.

Release 20 adds M0-M3 module progression and rank-limited battles on top of the physics-hosted bot architecture. The server owns accounts,
ownership/equipment, crystals/XP/ranks, round scoring/rewards, combat state and supply drops.
Server data files are the source of truth for economy, loadouts and balance.
"""
from __future__ import annotations

import argparse
import asyncio
from dataclasses import dataclass, field
import hashlib
import hmac
import json
import math
from pathlib import Path
import random
import re
import secrets
import shutil
import time
from urllib.parse import urlsplit
from collections import deque
from typing import Any

BATTLE_ROOM_PREFIX = "arena:"
SPAWN_COUNT = 9
SAFE_PAINT_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
SAFE_MAP_ID = re.compile(r"^[a-z0-9_-]{1,64}$")
SERVER_ROOT = Path(__file__).resolve().parent
COMBAT_PATH = SERVER_ROOT / "data" / "combat_stats.json"
LOADOUT_PATH = SERVER_ROOT / "data" / "loadout_catalog.json"
ECONOMY_PATH = SERVER_ROOT / "data" / "economy.json"
SUPPLY_ZONES_PATH = SERVER_ROOT / "data" / "supply_drop_zones.json"
SUPPLY_RULES_PATH = SERVER_ROOT / "data" / "supply_rules.json"
ACCOUNTS_PATH = SERVER_ROOT / "data" / "accounts.json"
PAINT_ROOT = SERVER_ROOT / "assets" / "paints"
PAINT_PREVIEW_ROOT = SERVER_ROOT / "assets" / "paint_previews"
PAINT_EXTENSIONS = {".png":"png", ".jpg":"jpg", ".jpeg":"jpeg", ".webp":"webp"}
PROJECT_MAP_ROOT = SERVER_ROOT.parent / "client" / "scenes" / "maps"
SERVER_MAP_ROOT = SERVER_ROOT / "maps"
MAX_MAP_SCENE_BYTES = 512 * 1024


def _map_key_from_stem(stem: str) -> str:
    clean = stem.strip().lower()
    return "arena" if clean == "arena_editable" else clean


def _humanize_map_key(map_key: str) -> str:
    if map_key == "arena":
        return "Арена"
    return " ".join(part.capitalize() for part in re.split(r"[_-]+", map_key) if part) or map_key


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _scene_marker_positions(text: str, prefix: str) -> list[list[float]]:
    out: list[tuple[int, list[float]]] = []
    blocks = re.split(r"(?=^\[node )", text, flags=re.MULTILINE)
    for block in blocks:
        header = re.match(r'^\[node name="([^"]+)"[^\]]*type="Marker3D"[^\]]*\]', block)
        if not header:
            continue
        name = header.group(1)
        if not name.startswith(prefix):
            continue
        suffix = name[len(prefix):]
        if not suffix.isdigit():
            continue
        position: list[float] | None = None
        transform = re.search(r'^transform\s*=\s*Transform3D\(([^)]*)\)', block, re.MULTILINE)
        if transform:
            try:
                values = [float(v.strip()) for v in transform.group(1).split(',')]
                if len(values) >= 12:
                    position = [values[-3], values[-2], values[-1]]
            except ValueError:
                position = None
        if position is None:
            pos = re.search(r'^position\s*=\s*Vector3\(([^)]*)\)', block, re.MULTILINE)
            if pos:
                try:
                    values = [float(v.strip()) for v in pos.group(1).split(',')]
                    if len(values) >= 3:
                        position = values[:3]
                except ValueError:
                    position = None
        if position is not None and all(math.isfinite(v) for v in position):
            out.append((int(suffix), position))
    out.sort(key=lambda item: item[0])
    return [p for _, p in out]


def _scene_metadata(scene_path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {"enabled": True}
    try:
        text = scene_path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return result
    name_match = re.search(r'^metadata/tanki_map_name\s*=\s*"(.*)"\s*$', text, re.MULTILINE)
    if name_match:
        result["name"] = name_match.group(1).replace(r'\"', '"').replace(r'\n', '\n')
    if re.search(r'^metadata/tanki_map_enabled\s*=\s*false\s*$', text, re.MULTILINE):
        result["enabled"] = False
    spawn_positions = _scene_marker_positions(text, "Spawn_")
    result["spawn_count"] = max(9, len(spawn_positions))
    result["supply_zones"] = _scene_marker_positions(text, "Supply_")
    result["arena_compatible"] = 'res://assets/maps/arena/arena_visual_editor.gltf' in text
    return result


def _seed_server_maps() -> None:
    SERVER_MAP_ROOT.mkdir(parents=True, exist_ok=True)
    if not PROJECT_MAP_ROOT.is_dir():
        return
    for source in PROJECT_MAP_ROOT.glob("*.tscn"):
        target = SERVER_MAP_ROOT / source.name
        if not target.exists():
            shutil.copy2(source, target)
    for source in PROJECT_MAP_ROOT.iterdir():
        if source.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp"}:
            continue
        target = SERVER_MAP_ROOT / source.name
        if not target.exists():
            shutil.copy2(source, target)


def _find_server_map_preview(scene_path: Path) -> Path | None:
    stem = scene_path.stem
    for ext in (".png", ".jpg", ".jpeg", ".webp"):
        candidate = scene_path.with_name(stem + ext)
        if candidate.is_file():
            return candidate
    return None


def discover_battle_maps() -> dict[str, dict[str, Any]]:
    _seed_server_maps()
    maps: dict[str, dict[str, Any]] = {}
    if SERVER_MAP_ROOT.is_dir():
        for scene_path in sorted(SERVER_MAP_ROOT.glob("*.tscn")):
            map_key = _map_key_from_stem(scene_path.stem)
            if not SAFE_MAP_ID.fullmatch(map_key):
                continue
            metadata = _scene_metadata(scene_path)
            if not metadata.get("enabled", True):
                continue
            preview = _find_server_map_preview(scene_path)
            info: dict[str, Any] = {
                "id": map_key,
                "name": str(metadata.get("name", _humanize_map_key(map_key))),
                "scene": scene_path.name,
                "path": scene_path,
                "sha256": _sha256_file(scene_path),
                "bytes": scene_path.stat().st_size,
                "spawn_count": max(1, int(metadata.get("spawn_count", 9))),
                "supply_zones": list(metadata.get("supply_zones", [])),
                "arena_compatible": bool(metadata.get("arena_compatible", False)),
            }
            if preview is not None:
                info.update({
                    "preview_path": preview,
                    "preview_format": preview.suffix.lower().lstrip('.').replace('jpeg', 'jpg'),
                    "preview_sha256": _sha256_file(preview),
                    "preview_bytes": preview.stat().st_size,
                })
            maps[map_key] = info
    if not maps:
        raise RuntimeError(f"no battle maps found in {SERVER_MAP_ROOT}")
    return maps


BATTLE_MAPS = discover_battle_maps()
BATTLE_MAP_IDS = tuple(BATTLE_MAPS.keys())
DEFAULT_BATTLE_MAP = "arena" if "arena" in BATTLE_MAPS else next(iter(BATTLE_MAPS))


def refresh_battle_maps() -> None:
    """Rescan server/maps; this is the authoritative multiplayer map repository."""
    global BATTLE_MAPS, BATTLE_MAP_IDS, DEFAULT_BATTLE_MAP
    BATTLE_MAPS = discover_battle_maps()
    BATTLE_MAP_IDS = tuple(BATTLE_MAPS.keys())
    DEFAULT_BATTLE_MAP = "arena" if "arena" in BATTLE_MAPS else next(iter(BATTLE_MAPS))


def _public_map_asset(map_key: str) -> dict[str, Any]:
    info = BATTLE_MAPS.get(map_key, {})
    result = {
        "id": map_key,
        "name": str(info.get("name", _humanize_map_key(map_key))),
        "scene": str(info.get("scene", f"{map_key}.tscn")),
        "sha256": str(info.get("sha256", "")),
        "bytes": int(info.get("bytes", 0)),
        "spawn_count": int(info.get("spawn_count", 9)),
        "supply_count": len(info.get("supply_zones", [])) if isinstance(info.get("supply_zones", []), list) else 0,
        "arena_compatible": bool(info.get("arena_compatible", False)),
    }
    if info.get("preview_path") is not None:
        result.update({
            "preview_format": str(info.get("preview_format", "png")),
            "preview_sha256": str(info.get("preview_sha256", "")),
            "preview_bytes": int(info.get("preview_bytes", 0)),
        })
    return result


def public_maps() -> list[dict[str, Any]]:
    items = [_public_map_asset(key) for key in BATTLE_MAPS]
    items.sort(key=lambda item: (0 if item.get("id") == "arena" else 1, str(item.get("name", "")).casefold()))
    return items


def _validate_uploaded_map(map_key: str, body: bytes) -> tuple[bool, str]:
    if not SAFE_MAP_ID.fullmatch(map_key) or map_key == "arena":
        return False, "invalid or reserved map id"
    if not body or len(body) > MAX_MAP_SCENE_BYTES:
        return False, "map scene is empty or too large"
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        return False, "map scene must be UTF-8 text"
    if not text.lstrip().startswith("[gd_scene"):
        return False, "not a Godot .tscn scene"
    if not re.search(r'^\[node name="[^"]+" type="Node3D"', text, re.MULTILINE):
        return False, "map root must be Node3D"
    if not re.search(r'^\[node name="Spawn_0" type="Marker3D"', text, re.MULTILINE):
        return False, "map must contain Spawn_0 Marker3D"
    if 'res://assets/maps/arena/arena_visual_editor.gltf' not in text:
        return False, "only Arena-derived maps are allowed in branch 18"
    for resource_type, resource_path in re.findall(r'\[ext_resource type="([^"]+)"[^\]]*path="([^"]+)"', text):
        if resource_type == "Script" and resource_path != "res://scripts/arena_editable_runtime.gd":
            return False, f"map script is not allowed: {resource_path}"
        if resource_path.startswith("res://scenes/maps/") and resource_path != "res://scenes/maps/arena_editable.lmbake":
            return False, f"map references a non-bundled scene resource: {resource_path}"
        if resource_path.startswith("res://assets/") and not resource_path.startswith("res://assets/maps/arena/"):
            return False, f"only bundled Arena map assets are allowed: {resource_path}"
    return True, ""


# Server-side forgiving hit volumes.  These are deliberately a little larger than
# the visible hulls so a shell grazing a track, turret edge, or a tank whose last
# replicated transform is a frame behind still counts.  The shot segment still has
# to reach the volume, so a wall hit in front of the tank continues to block it.
HULL_HIT_VOLUMES: dict[str, tuple[tuple[float, float, float], float]] = {
    "wasp": ((1.55, 1.45, 2.45), 1.02),
    "viking": ((2.10, 1.62, 3.08), 1.16),
    "mamont": ((2.40, 1.82, 3.62), 1.30),
}
WEAPON_HIT_PADDING: dict[str, tuple[float, float, float]] = {
    # Deliberately arcade-friendly capture. The visual impact is still placed on
    # the unpadded hull, so the larger volume does not make explosions float.
    "smoky": (0.72, 0.88, 0.82),
    "thunder": (1.38, 1.28, 1.50),
}
# A shot that visually clips the lip of cover immediately in front of a tank may
# still be intended as a hit. Search a short distance beyond the client ray end;
# Thunder receives more capture because its shell/blast reads much larger.
WEAPON_ENDPOINT_CAPTURE: dict[str, float] = {
    "smoky": 0.85,
    "thunder": 1.65,
}


def load_combat_stats() -> dict[str, Any]:
    with COMBAT_PATH.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise RuntimeError(f"invalid combat stats: {COMBAT_PATH}")
    return data


COMBAT = load_combat_stats()
PROTOCOL = 20
BOT_MAX_PER_BATTLE = 16
DISCRETE_WORLD_RAY_LIMIT = 4096.0
BOT_NICKNAMES = (
    "Raptor", "Vortex", "Nord", "Fenix", "Maverick", "Ghost", "Kasper", "Vector",
    "Storm", "Raven", "Titan", "Borey", "Comet", "Hunter", "Diesel", "Frost",
    "Falcon", "Wolf", "Quartz", "Pixel", "Ranger", "Meteor", "Orion", "Shadow",
    "Sparrow", "Rex", "Atlas", "Blitz", "Volt", "Steel", "Fox", "Cobra",
    "Phoenix", "Rocket", "Drift", "Astra", "Nomad", "Tornado", "Karma", "Onyx",
    "Mirage", "Scout", "Jager", "Turbo", "Nemo", "Viking", "Raccoon", "Zero",
)


def load_loadout_catalog() -> dict[str, Any]:
    with LOADOUT_PATH.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise RuntimeError(f"invalid loadout catalog: {LOADOUT_PATH}")
    return data


def _pretty_name(value: str) -> str:
    return " ".join(part.capitalize() for part in value.replace("-", "_").split("_") if part) or "Paint"


def load_paints() -> dict[str, dict[str, Any]]:
    PAINT_ROOT.mkdir(parents=True, exist_ok=True)
    PAINT_PREVIEW_ROOT.mkdir(parents=True, exist_ok=True)
    result: dict[str, dict[str, Any]] = {}
    for path in sorted(PAINT_ROOT.iterdir()):
        if not path.is_file() or path.suffix.lower() not in PAINT_EXTENSIONS:
            continue
        paint_id = path.stem
        if not SAFE_PAINT_ID.fullmatch(paint_id):
            print(f"[paint] ignored unsafe id: {paint_id!r}")
            continue
        meta_path = path.with_suffix(".json")
        meta: dict[str, Any] = {}
        if meta_path.exists():
            try:
                loaded = json.loads(meta_path.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    meta = loaded
            except Exception as exc:
                print(f"[paint] invalid metadata {meta_path.name}: {exc}")
        if bool(meta.get("hidden", False)):
            continue
        try:
            paint_price = max(0, int(meta.get("price", 10)))
        except (TypeError, ValueError):
            paint_price = 10
        try:
            paint_order = int(meta.get("order", 9999))
        except (TypeError, ValueError):
            paint_order = 9999
        raw = path.read_bytes()
        preview_path = PAINT_PREVIEW_ROOT / f"{paint_id}.png"
        preview_raw = preview_path.read_bytes() if preview_path.is_file() else b""
        result[paint_id] = {
            "id": paint_id,
            "name": str(meta.get("name", _pretty_name(paint_id))),
            "scale": float(meta.get("scale", 1.0)),
            "strength": float(meta.get("strength", 0.86)),
            "price": paint_price,
            "order": paint_order,
            "format": PAINT_EXTENSIONS[path.suffix.lower()],
            "sha256": hashlib.sha256(raw).hexdigest(),
            "bytes": len(raw),
            "path": path,
            "preview_format": "png" if preview_raw else "",
            "preview_sha256": hashlib.sha256(preview_raw).hexdigest() if preview_raw else "",
            "preview_bytes": len(preview_raw),
            "preview_path": preview_path if preview_raw else None,
        }
    return result


LOADOUT = load_loadout_catalog()
PAINTS = load_paints()
HULL_OPTIONS = [x for x in LOADOUT.get("hulls", []) if isinstance(x, dict)]
TURRET_OPTIONS = [x for x in LOADOUT.get("turrets", []) if isinstance(x, dict)]
HULL_IDS = tuple(str(x.get("id", "")) for x in HULL_OPTIONS)
TURRET_IDS = tuple(str(x.get("id", "")) for x in TURRET_OPTIONS)
ALLOWED_HULLS = {(str(x.get("id", "")), int(x.get("mod", 0))) for x in HULL_OPTIONS}
ALLOWED_TURRETS = {(str(x.get("id", "")), int(x.get("mod", 0))) for x in TURRET_OPTIONS}


def load_economy() -> dict[str, Any]:
    with ECONOMY_PATH.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise RuntimeError(f"invalid economy config: {ECONOMY_PATH}")
    return data


ECONOMY = load_economy()
ITEM_PRICE = max(0, int(ECONOMY.get("item_price", 10)))
KILL_LIMIT = max(1, int(ECONOMY.get("kill_limit", 15)))
INTERMISSION_SECONDS = max(1.0, float(ECONOMY.get("intermission_seconds", 10.0)))
XP_PER_KILL_MIN = max(0, int(ECONOMY.get("xp_per_kill_min", ECONOMY.get("xp_per_kill", 10))))
XP_PER_KILL_MAX = max(XP_PER_KILL_MIN, int(ECONOMY.get("xp_per_kill_max", 19)))
PASSWORD_ITERATIONS = 240_000


def load_supply_rules() -> dict[str, Any]:
    try:
        data = json.loads(SUPPLY_RULES_PATH.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError(f"cannot read supply rules {SUPPLY_RULES_PATH}: {exc}") from exc
    if not isinstance(data, dict):
        raise RuntimeError(f"invalid supply rules: {SUPPLY_RULES_PATH}")
    return data


SUPPLY_RULES = load_supply_rules()
SUPPLY_BUFF_SECONDS = max(1.0, float(SUPPLY_RULES.get("buff_seconds", 25.0)))
SUPPLY_DESCENT_SECONDS = max(0.5, float(SUPPLY_RULES.get("descent_seconds", 4.8)))
SUPPLY_GROUND_SECONDS = max(1.0, float(SUPPLY_RULES.get("ground_seconds", 30.0)))
SUPPLY_REGULAR_MIN_SECONDS = max(1.0, float(SUPPLY_RULES.get("regular_interval_min", 10.0)))
SUPPLY_REGULAR_MAX_SECONDS = max(SUPPLY_REGULAR_MIN_SECONDS, float(SUPPLY_RULES.get("regular_interval_max", 15.0)))
SUPPLY_PICKUP_RADIUS = max(1.0, float(SUPPLY_RULES.get("pickup_radius", 4.4)))
SUPPLY_PICKUP_VERTICAL = max(0.5, float(SUPPLY_RULES.get("pickup_vertical", 3.4)))
SUPPLY_DROP_HEIGHT = max(1.0, float(SUPPLY_RULES.get("drop_height", 28.0)))
SUPPLY_CRATE_HALF_HEIGHT = max(0.0, float(SUPPLY_RULES.get("crate_half_height", 0.72)))
SUPPLY_CRYSTAL_LIFETIME_MULTIPLIER = max(1.0, float(SUPPLY_RULES.get("crystal_lifetime_multiplier", 2.0)))
SUPPLY_MEDKIT_LIFETIME_MULTIPLIER = max(1.0, float(SUPPLY_RULES.get("medkit_lifetime_multiplier", 1.5)))
SUPPLY_PLAYER_AVOID_RADIUS = max(0.0, float(SUPPLY_RULES.get("avoid_player_radius", 7.5)))
SUPPLY_DROP_AVOID_RADIUS = max(0.0, float(SUPPLY_RULES.get("avoid_drop_radius", 6.0)))
NITRO_SPEED_MULTIPLIER = max(1.0, float(SUPPLY_RULES.get("nitro_speed_multiplier", 2.0)))
ARMOR_DAMAGE_MULTIPLIER = min(1.0, max(0.0, float(SUPPLY_RULES.get("armor_damage_multiplier", 0.5))))
DAMAGE_MULTIPLIER = max(1.0, float(SUPPLY_RULES.get("damage_multiplier", 2.0)))
HEAL_FRACTION = min(1.0, max(0.0, float(SUPPLY_RULES.get("heal_fraction_of_max_hp", 0.75))))
CRYSTAL_REWARD = max(0, int(SUPPLY_RULES.get("crystal_reward", 1)))
GOLD_REWARD = max(0, int(SUPPLY_RULES.get("gold_reward", 100)))
GOLD_FUND_STEP = max(1, int(SUPPLY_RULES.get("gold_fund_step", 20)))
_regular_raw = SUPPLY_RULES.get("regular_kinds", ["nitro", "armor", "damage", "medkit"])
REGULAR_SUPPLY_KINDS = tuple(
    str(kind) for kind in _regular_raw
    if str(kind) in {"nitro", "armor", "damage", "medkit"}
) or ("nitro", "armor", "damage", "medkit")


def _fund_thresholds_crossed(old_fund: int, new_fund: int, step: int = GOLD_FUND_STEP) -> list[int]:
    """Return every positive fund milestone crossed in (old_fund, new_fund]."""
    step = max(1, int(step))
    old_value = max(0, int(old_fund))
    new_value = max(0, int(new_fund))
    if new_value <= old_value:
        return []
    first_index = old_value // step + 1
    last_index = new_value // step
    if last_index < first_index:
        return []
    return [index * step for index in range(first_index, last_index + 1)]


def load_supply_zones() -> list[list[float]]:
    try:
        data = json.loads(SUPPLY_ZONES_PATH.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError(f"cannot read supply drop zones {SUPPLY_ZONES_PATH}: {exc}") from exc
    raw = data.get("zones", []) if isinstance(data, dict) else []
    zones: list[list[float]] = []
    if isinstance(raw, list):
        for item in raw:
            value = item.get("p") if isinstance(item, dict) else item
            if isinstance(value, (list, tuple)) and len(value) >= 3:
                try:
                    p = [float(value[0]), float(value[1]), float(value[2])]
                except (TypeError, ValueError):
                    continue
                if all(math.isfinite(v) for v in p):
                    zones.append(p)
    if not zones:
        raise RuntimeError(f"no usable supply drop zones in {SUPPLY_ZONES_PATH}")
    return zones


SUPPLY_ZONES = load_supply_zones()


def _load_accounts() -> dict[str, dict[str, Any]]:
    ACCOUNTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    if not ACCOUNTS_PATH.exists():
        ACCOUNTS_PATH.write_text('{"version":1,"accounts":{}}\n', encoding="utf-8")
    try:
        doc = json.loads(ACCOUNTS_PATH.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError(f"cannot read account database {ACCOUNTS_PATH}: {exc}") from exc
    raw = doc.get("accounts", {}) if isinstance(doc, dict) else {}
    if not isinstance(raw, dict):
        raise RuntimeError(f"invalid account database: {ACCOUNTS_PATH}")
    return {str(k): v for k, v in raw.items() if isinstance(v, dict)}


ACCOUNTS = _load_accounts()


def _save_accounts() -> None:
    ACCOUNTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = ACCOUNTS_PATH.with_suffix(".json.tmp")
    bak = ACCOUNTS_PATH.with_suffix(".json.bak")
    payload = json.dumps({"version": 1, "accounts": ACCOUNTS}, ensure_ascii=False, indent=2) + "\n"
    tmp.write_text(payload, encoding="utf-8")
    if ACCOUNTS_PATH.exists():
        try:
            shutil.copy2(ACCOUNTS_PATH, bak)
        except OSError:
            pass
    tmp.replace(ACCOUNTS_PATH)


def _login_key(login: str) -> str:
    return login.strip().casefold()


def _valid_login(login: str) -> bool:
    login = login.strip()
    if len(login) < 3 or len(login) > 20:
        return False
    return all(ch.isalnum() or ch in "_-" for ch in login)


def _password_hash(password: str, salt_hex: str) -> str:
    salt = bytes.fromhex(salt_hex)
    return hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PASSWORD_ITERATIONS).hex()


def _verify_password(account: dict[str, Any], password: str) -> bool:
    salt = str(account.get("salt", ""))
    expected = str(account.get("password_hash", ""))
    if not salt or not expected:
        return False
    try:
        actual = _password_hash(password, salt)
    except ValueError:
        return False
    return hmac.compare_digest(actual, expected)


def _rank_info(xp: int) -> dict[str, Any]:
    raw_ranks = ECONOMY.get("ranks", [])
    ranks = [r for r in raw_ranks if isinstance(r, dict)] if isinstance(raw_ranks, list) else []
    if not ranks:
        return {"index": 0, "name": "Новобранец", "xp": xp, "min_xp": 0, "next_xp": 0, "progress": 1.0}
    ranks.sort(key=lambda r: int(r.get("xp", 0)))
    index = 0
    for i, rank in enumerate(ranks):
        if xp >= int(rank.get("xp", 0)):
            index = i
        else:
            break
    current = ranks[index]
    min_xp = int(current.get("xp", 0))
    next_xp = int(ranks[index + 1].get("xp", min_xp)) if index + 1 < len(ranks) else min_xp
    progress = 1.0 if next_xp <= min_xp else max(0.0, min(1.0, (xp - min_xp) / float(next_xp - min_xp)))
    return {
        "index": index, "name": str(current.get("name", f"Ранг {index}")), "xp": xp,
        "min_xp": min_xp, "next_xp": next_xp, "progress": round(progress, 4),
    }


def _rank_info_by_index(index: int) -> dict[str, Any]:
    raw_ranks = ECONOMY.get("ranks", [])
    ranks = [dict(r) for r in raw_ranks if isinstance(r, dict)] if isinstance(raw_ranks, list) else []
    if not ranks:
        return {"index": 0, "name": "Новобранец", "xp": 0, "min_xp": 0, "next_xp": 0, "progress": 1.0}
    ranks.sort(key=lambda r: int(r.get("xp", 0)))
    index = max(0, min(len(ranks) - 1, int(index)))
    current = ranks[index]
    min_xp = int(current.get("xp", 0))
    next_xp = int(ranks[index + 1].get("xp", min_xp)) if index + 1 < len(ranks) else min_xp
    return {
        "index": index,
        "name": str(current.get("name", f"Ранг {index}")),
        "xp": min_xp,
        "min_xp": min_xp,
        "next_xp": next_xp,
        "progress": 0.0 if next_xp > min_xp else 1.0,
    }


def _client_rank_info(client: "Client" | None) -> dict[str, Any]:
    if client is None:
        return _rank_info_by_index(0)
    if client.is_bot:
        return _rank_info_by_index(client.bot_rank_index)
    account = ACCOUNTS.get(client.account_key) if client.account_key else None
    if isinstance(account, dict):
        return _rank_info(int(account.get("xp", 0)))
    return _rank_info_by_index(0)


def _item_rank_requirement(item: dict[str, Any] | None) -> int:
    if not isinstance(item, dict):
        return 0
    raw_ranks = ECONOMY.get("ranks", [])
    max_index = max(0, len(raw_ranks) - 1) if isinstance(raw_ranks, list) else 26
    return max(0, min(max_index, safe_int(item.get("min_rank"), 0)))


def _starter_hull() -> dict[str, Any]:
    for item in HULL_OPTIONS:
        if str(item.get("id", "")) == "wasp":
            return item
    return HULL_OPTIONS[0] if HULL_OPTIONS else {"id": "wasp", "mod": 0, "name": "WASP M0"}


def _starter_turret() -> dict[str, Any]:
    for item in TURRET_OPTIONS:
        if str(item.get("id", "")) == "smoky":
            return item
    return TURRET_OPTIONS[0] if TURRET_OPTIONS else {"id": "smoky", "mod": 0, "name": "SMOKY M0"}


def _starter_paint() -> str:
    # Classic starter coating from the old client. New accounts equip Green.
    # Existing accounts keep their chosen paint, but normalization grants Green.
    if "green" in PAINTS:
        return "green"
    if "flora" in PAINTS:
        return "flora"
    return sorted(PAINTS.keys())[0] if PAINTS else ""


def _item_key(item_id: str, mod: int) -> str:
    return f"{item_id}:{mod}"


def _new_account(login: str, password: str) -> dict[str, Any]:
    hull = _starter_hull()
    turret = _starter_turret()
    paint = _starter_paint()
    salt = secrets.token_hex(16)
    return {
        "login": login.strip(),
        "salt": salt,
        "password_hash": _password_hash(password, salt),
        "created_at": int(time.time()),
        "xp": 0,
        "crystals": max(0, int(ECONOMY.get("starting_crystals", 0))),
        "owned_hulls": [_item_key(str(hull.get("id", "wasp")), int(hull.get("mod", 0)))],
        "owned_turrets": [_item_key(str(turret.get("id", "smoky")), int(turret.get("mod", 0)))],
        "owned_paints": [paint] if paint else [],
        "equipped": {
            "hull": str(hull.get("id", "wasp")), "hull_mod": int(hull.get("mod", 0)),
            "turret": str(turret.get("id", "smoky")), "turret_mod": int(turret.get("mod", 0)),
            "paint": paint,
        },
        "stats": {"battles": 0, "wins": 0, "kills": 0},
    }


def _expand_owned_progression(values: Any, options: list[dict[str, Any]]) -> list[str]:
    # Release-20 migration: a legacy owned item such as wasp:2 means that the
    # player already progressed through M0/M1/M2. Lower steps are granted without
    # charging crystals so existing accounts never lose their old equipment.
    valid = {(str(item.get("id", "")), safe_int(item.get("mod"), 0)) for item in options}
    highest: dict[str, int] = {}
    if isinstance(values, list):
        for raw in values:
            text = str(raw)
            if ":" not in text:
                continue
            item_id, mod_text = text.rsplit(":", 1)
            try:
                mod = int(mod_text)
            except ValueError:
                continue
            if (item_id, mod) in valid:
                highest[item_id] = max(highest.get(item_id, -1), mod)
    out: list[str] = []
    for item_id, max_mod in highest.items():
        for mod in range(0, max_mod + 1):
            if (item_id, mod) in valid:
                out.append(_item_key(item_id, mod))
    return sorted(set(out))


def _sanitize_account(account: dict[str, Any]) -> None:
    account["xp"] = max(0, safe_int(account.get("xp"), 0))
    account["crystals"] = max(0, safe_int(account.get("crystals"), 0))
    if not isinstance(account.get("owned_hulls"), list):
        account["owned_hulls"] = []
    if not isinstance(account.get("owned_turrets"), list):
        account["owned_turrets"] = []
    if not isinstance(account.get("owned_paints"), list):
        account["owned_paints"] = []
    account["owned_hulls"] = _expand_owned_progression(account.get("owned_hulls", []), HULL_OPTIONS)
    account["owned_turrets"] = _expand_owned_progression(account.get("owned_turrets", []), TURRET_OPTIONS)
    # v18.7 migration: accounts that still have only the old automatic Flora
    # starter are treated as untouched starter accounts and move to Green once.
    legacy_starter_flora_only = set(str(item) for item in account["owned_paints"]) <= {"flora"}
    if not isinstance(account.get("stats"), dict):
        account["stats"] = {"battles": 0, "wins": 0, "kills": 0}
    hull = _starter_hull()
    turret = _starter_turret()
    starter_hull_key = _item_key(str(hull.get("id", "wasp")), int(hull.get("mod", 0)))
    starter_turret_key = _item_key(str(turret.get("id", "smoky")), int(turret.get("mod", 0)))
    if starter_hull_key not in account["owned_hulls"]:
        account["owned_hulls"].append(starter_hull_key)
    if starter_turret_key not in account["owned_turrets"]:
        account["owned_turrets"].append(starter_turret_key)
    starter_paint = _starter_paint()
    if starter_paint and starter_paint not in account["owned_paints"]:
        account["owned_paints"].append(starter_paint)
    equipped = account.get("equipped")
    if not isinstance(equipped, dict):
        equipped = {}
        account["equipped"] = equipped
    hull_id = str(equipped.get("hull", hull.get("id", "wasp")))
    hull_mod = safe_int(equipped.get("hull_mod"), int(hull.get("mod", 0)))
    turret_id = str(equipped.get("turret", turret.get("id", "smoky")))
    turret_mod = safe_int(equipped.get("turret_mod"), int(turret.get("mod", 0)))
    paint_id = str(equipped.get("paint", starter_paint))
    if legacy_starter_flora_only and paint_id == "flora" and starter_paint == "green":
        paint_id = starter_paint
    if _item_key(hull_id, hull_mod) not in account["owned_hulls"] or (hull_id, hull_mod) not in ALLOWED_HULLS:
        hull_id, hull_mod = str(hull.get("id", "wasp")), int(hull.get("mod", 0))
    if _item_key(turret_id, turret_mod) not in account["owned_turrets"] or (turret_id, turret_mod) not in ALLOWED_TURRETS:
        turret_id, turret_mod = str(turret.get("id", "smoky")), int(turret.get("mod", 0))
    if paint_id not in account["owned_paints"] or paint_id not in PAINTS:
        paint_id = starter_paint
    account["equipped"] = {"hull": hull_id, "hull_mod": hull_mod, "turret": turret_id, "turret_mod": turret_mod, "paint": paint_id}


def _public_profile(account: dict[str, Any]) -> dict[str, Any]:
    _sanitize_account(account)
    stats = account.get("stats", {})
    return {
        "login": str(account.get("login", "Player")),
        "xp": int(account.get("xp", 0)),
        "crystals": int(account.get("crystals", 0)),
        "rank": _rank_info(int(account.get("xp", 0))),
        "owned_hulls": list(account.get("owned_hulls", [])),
        "owned_turrets": list(account.get("owned_turrets", [])),
        "owned_paints": list(account.get("owned_paints", [])),
        "equipped": dict(account.get("equipped", {})),
        "stats": dict(stats) if isinstance(stats, dict) else {},
    }


def public_catalog() -> dict[str, Any]:
    refresh_battle_maps()
    paints = []
    for paint in PAINTS.values():
        item = {key: paint[key] for key in (
            "id", "name", "scale", "strength", "price", "order",
            "format", "sha256", "bytes",
            "preview_format", "preview_sha256", "preview_bytes",
        )}
        paints.append(item)
    paints.sort(key=lambda item: (int(item.get("order", 9999)), str(item["name"]).casefold()))
    hulls = [dict(item) for item in HULL_OPTIONS]
    turrets = [dict(item) for item in TURRET_OPTIONS]
    for item in hulls + turrets:
        item["price"] = max(0, safe_int(item.get("price"), ITEM_PRICE))
        item["upgrade_price"] = max(0, safe_int(item.get("upgrade_price"), 0))
        item["min_rank"] = _item_rank_requirement(item)
    ranks = ECONOMY.get("ranks", [])
    return {
        "protocol": PROTOCOL,
        "hulls": hulls,
        "turrets": turrets,
        "paints": paints,
        "combat": COMBAT,
        "maps": public_maps(),
        "economy": {
            "item_price": ITEM_PRICE, "kill_limit": KILL_LIMIT,
            "intermission_seconds": INTERMISSION_SECONDS,
            "ranks": ranks if isinstance(ranks, list) else [],
        },
    }


def is_battle_map(value: Any) -> bool:
    text = str(value or "").strip().lower()
    if text in BATTLE_MAP_IDS:
        return True
    if text.startswith(BATTLE_ROOM_PREFIX):
        suffix = text[len(BATTLE_ROOM_PREFIX):]
        return suffix.isdigit() and int(suffix) > 0
    return False


def normalize_map(value: Any) -> str:
    value = str(value or DEFAULT_BATTLE_MAP).strip().lower()
    return value if is_battle_map(value) else DEFAULT_BATTLE_MAP


def battle_map_id(battle_id: int) -> str:
    return f"{BATTLE_ROOM_PREFIX}{int(battle_id)}"


def safe_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def finite_number(value: Any) -> float | None:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return None
    return out if math.isfinite(out) else None


def vec3(value: Any) -> list[float] | None:
    if not isinstance(value, list) or len(value) < 3:
        return None
    out: list[float] = []
    for item in value[:3]:
        number = finite_number(item)
        if number is None:
            return None
        out.append(round(number, 4))
    return out


def vec4(value: Any) -> list[float] | None:
    if not isinstance(value, list) or len(value) < 4:
        return None
    out: list[float] = []
    for item in value[:4]:
        number = finite_number(item)
        if number is None:
            return None
        out.append(round(number, 5))
    return out


def _root_dict(key: str) -> dict[str, Any]:
    value = COMBAT.get(key, {})
    return value if isinstance(value, dict) else {}


def modifier(mod: int) -> dict[str, float]:
    value = _root_dict("modifiers").get(str(max(0, min(3, mod))), {})
    return value if isinstance(value, dict) else {}


def hull_spec(build: dict[str, Any]) -> dict[str, float]:
    base = _root_dict("hulls").get(build["hull"], {})
    if not isinstance(base, dict):
        return {"max_hp": 1.0, "hit_radius": 2.0}
    mult = modifier(int(build["hull_mod"]))
    return {
        **base,
        "max_hp": float(base.get("base_hp", 1.0)) * float(mult.get("hp", 1.0)),
    }


def weapon_spec(build: dict[str, Any]) -> dict[str, float | str]:
    base = _root_dict("weapons").get(build["turret"], {})
    if not isinstance(base, dict):
        return {}
    mult = modifier(int(build["turret_mod"]))
    out: dict[str, float | str] = dict(base)
    if "base_damage" in base:
        out["damage"] = float(base["base_damage"]) * float(mult.get("damage", 1.0))
    if "base_dps" in base:
        out["dps"] = float(base["base_dps"]) * float(mult.get("damage", 1.0))
    if "base_reload" in base:
        out["reload"] = float(base["base_reload"]) * float(mult.get("reload", 1.0))
    if "fuel_capacity" in base:
        out["fuel_max"] = float(base["fuel_capacity"]) * float(mult.get("fuel", 1.0))
    return out


def normalize_build(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    hull = str(value.get("hull", "")).strip().lower()
    turret = str(value.get("turret", "")).strip().lower()
    paint = str(value.get("paint", "")).strip()
    if hull not in HULL_IDS or turret not in TURRET_IDS or paint not in PAINTS:
        return None
    hull_base = _root_dict("hulls").get(hull, {})
    turret_base = _root_dict("weapons").get(turret, {})
    if not isinstance(hull_base, dict) or not isinstance(turret_base, dict):
        return None
    hull_mod = safe_int(value.get("hull_mod"), int(hull_base.get("default_mod", 0)))
    turret_mod = safe_int(value.get("turret_mod"), int(turret_base.get("default_mod", 0)))
    if (hull, hull_mod) not in ALLOWED_HULLS or (turret, turret_mod) not in ALLOWED_TURRETS:
        return None
    return {
        "hull": hull,
        "hull_mod": hull_mod,
        "turret": turret,
        "turret_mod": turret_mod,
        "paint": paint,
    }


def normalized(v: list[float]) -> list[float] | None:
    length = math.sqrt(sum(x * x for x in v))
    if length <= 1e-6:
        return None
    return [x / length for x in v]


def dot(a: list[float], b: list[float]) -> float:
    return sum(a[i] * b[i] for i in range(3))


def distance(a: list[float], b: list[float]) -> float:
    return math.dist(a, b)


def segment_point_distance(a: list[float], b: list[float], p: list[float]) -> tuple[float, float]:
    ab = [b[i] - a[i] for i in range(3)]
    ap = [p[i] - a[i] for i in range(3)]
    denom = dot(ab, ab)
    if denom <= 1e-9:
        return distance(a, p), 0.0
    t = max(0.0, min(1.0, dot(ap, ab) / denom))
    closest = [a[i] + ab[i] * t for i in range(3)]
    return distance(closest, p), t


@dataclass
class SupplyDrop:
    supply_id: int
    kind: str
    position: list[float]
    spawned_at: float
    lands_at: float
    expires_at: float
    persistent: bool = False


@dataclass
class BattleRoom:
    battle_id: int
    name: str
    map_key: str
    kill_limit: int
    max_players: int
    owner_login: str
    created_at: float
    min_rank: int = 0
    max_rank: int = 26
    round_id: int = 1
    round_active: bool = True
    round_restart_at: float = 0.0
    battle_fund: int = 0
    supplies: dict[int, SupplyDrop] = field(default_factory=dict)
    next_supply_id: int = 1
    next_regular_supply_at: float = field(default_factory=lambda: time.monotonic() + random.uniform(SUPPLY_REGULAR_MIN_SECONDS, SUPPLY_REGULAR_MAX_SECONDS))

    @property
    def map_id(self) -> str:
        return battle_map_id(self.battle_id)


@dataclass
class Client:
    player_id: int
    addr: tuple[str, int]
    last_seen: float
    map_id: str = "arena"
    build: dict[str, Any] | None = None
    spawn_index: int = -1
    spawn_anchor_position: list[float] | None = None
    spawn_reserved_at: float = 0.0
    state: dict[str, Any] = field(default_factory=dict)
    last_position: list[float] | None = None
    last_position_time: float = 0.0
    reliable_seen: deque[int] = field(default_factory=lambda: deque(maxlen=128))
    hp: float = 1.0
    max_hp: float = 1.0
    alive: bool = True
    fuel: float = 0.0
    fuel_max: float = 0.0
    fire_requested: bool = False
    fire_targets: list[int] = field(default_factory=list)
    last_fire_active: float = 0.0
    last_shot_time: float = -1000.0
    burn_end: float = 0.0
    burn_duration: float = 0.0
    burn_dps: float = 0.0
    burn_source: int = -1
    nitro_end: float = 0.0
    armor_end: float = 0.0
    damage_end: float = 0.0
    respawn_at: float = 0.0
    authenticated: bool = False
    account_key: str = ""
    login: str = ""
    round_kills: int = 0
    round_score: int = 0
    round_damage: float = 0.0
    round_xp: int = 0
    chat_last_at: float = 0.0
    battle_id: int = -1
    reliable_cache: dict[int, dict[str, Any]] = field(default_factory=dict)
    reliable_order: deque[int] = field(default_factory=lambda: deque(maxlen=96))
    map_upload_token: str = field(default_factory=lambda: secrets.token_urlsafe(24))
    is_bot: bool = False
    bot_host_id: int = -1
    bot_rank_index: int = 0


class TankiProtocol(asyncio.DatagramProtocol):
    def __init__(self, timeout: float = 8.0, snapshot_hz: float = 20.0, asset_port: int = 9101):
        self.transport: asyncio.DatagramTransport | None = None
        self.clients_by_addr: dict[tuple[str, int], Client] = {}
        self.clients_by_id: dict[int, Client] = {}
        self.next_id = 1
        self.timeout = timeout
        self.snapshot_period = 1.0 / snapshot_hz
        self._task: asyncio.Task | None = None
        self._last_combat_time = time.monotonic()
        self.asset_port = asset_port
        self.active_accounts: dict[str, int] = {}
        self.chat_history: deque[dict[str, Any]] = deque(maxlen=60)
        self.battles: dict[int, BattleRoom] = {}
        self.next_battle_id = 1

    def connection_made(self, transport):
        self.transport = transport
        sock = transport.get_extra_info("sockname")
        print(f"[server] UDP listening on {sock[0]}:{sock[1]} protocol={PROTOCOL}")
        self._task = asyncio.create_task(self._ticker())

    def connection_lost(self, exc):
        if self._task:
            self._task.cancel()

    def datagram_received(self, data: bytes, addr):
        try:
            msg = json.loads(data.decode("utf-8"))
        except Exception:
            return
        if not isinstance(msg, dict):
            return
        kind = str(msg.get("type", ""))
        client = self.clients_by_addr.get(addr)
        if kind == "hello":
            if safe_int(msg.get("protocol"), -1) != PROTOCOL:
                self.send(addr, {"type": "protocol_error", "expected": PROTOCOL})
                return
            if client is None:
                client = Client(self.next_id, addr, time.monotonic(), map_id="lobby")
                self.next_id += 1
                self.clients_by_addr[addr] = client
                self.clients_by_id[client.player_id] = client
                print(f"[join] #{client.player_id} {addr[0]}:{addr[1]}")
            client.last_seen = time.monotonic()
            self.send(addr, {
                "type": "welcome", "player_id": client.player_id, "protocol": PROTOCOL,
                "map": client.map_id, "asset_port": self.asset_port,
                "map_upload_token": client.map_upload_token,
            })
            return
        if client is None:
            return
        client.last_seen = time.monotonic()
        if kind == "heartbeat":
            self.send(addr, {"type": "pong"})
            return
        if kind == "register":
            self.handle_register(client, msg)
            return
        if kind == "login":
            self.handle_login(client, msg)
            return
        if kind == "bye":
            self.drop(client, "client quit")
            return
        if not client.authenticated:
            return
        if kind == "chat":
            self.handle_chat(client, msg)
        elif kind == "purchase":
            self.handle_purchase(client, msg)
        elif kind == "upgrade":
            self.handle_upgrade(client, msg)
        elif kind == "equip":
            self.handle_equip(client, msg)
        elif kind == "list_battles":
            self.handle_list_battles(client, msg)
        elif kind == "get_profile":
            self.handle_get_profile(client, msg)
        elif kind == "create_battle":
            self.handle_create_battle(client, msg)
        elif kind == "join_battle":
            self.handle_join_battle(client, msg)
        elif kind == "leave_battle":
            self.handle_leave_battle(client, msg)
        elif kind == "add_bot":
            self.handle_add_bot(client, msg)
        elif kind == "remove_bot":
            self.handle_remove_bot(client, msg)
        elif kind == "bot_state" and is_battle_map(client.map_id):
            self.handle_bot_state(client, msg)
        elif kind == "bot_shot" and is_battle_map(client.map_id):
            self.handle_bot_shot(client, msg)
        elif kind == "bot_self_destruct" and is_battle_map(client.map_id):
            self.handle_bot_self_destruct(client, msg)
        elif kind == "state" and is_battle_map(client.map_id):
            self.handle_state(client, msg)
        elif kind == "shot" and is_battle_map(client.map_id):
            self.handle_shot(client, msg)
        elif kind == "self_destruct" and is_battle_map(client.map_id):
            self.handle_self_destruct(client, msg)
        elif kind == "pickup_supply" and is_battle_map(client.map_id):
            self.handle_supply_pickup(client, msg)

    def _account(self, client: Client) -> dict[str, Any] | None:
        if client.is_bot or not client.authenticated or not client.account_key:
            return None
        account = ACCOUNTS.get(client.account_key)
        return account if isinstance(account, dict) else None

    def _reliable_seq(self, client: Client, msg: dict[str, Any]) -> int | None:
        seq = safe_int(msg.get("seq"), -1)
        if seq < 0:
            return -1
        cached = client.reliable_cache.get(seq)
        if isinstance(cached, dict):
            self.send(client.addr, cached)
            return None
        return seq

    def _reliable_reply(self, client: Client, seq: int, payload: dict[str, Any]) -> None:
        if seq >= 0:
            payload = dict(payload)
            payload["seq"] = seq
            if len(client.reliable_order) >= client.reliable_order.maxlen:
                oldest = client.reliable_order.popleft()
                client.reliable_cache.pop(oldest, None)
            client.reliable_order.append(seq)
            client.reliable_cache[seq] = dict(payload)
        self.send(client.addr, payload)

    def _auth_success(self, client: Client, account_key: str) -> None:
        # A UDP endpoint may authenticate only one account at a time. Clean a stale
        # mapping defensively before binding the new session.
        if client.account_key and client.account_key != account_key:
            if self.active_accounts.get(client.account_key) == client.player_id:
                self.active_accounts.pop(client.account_key, None)
        previous_id = self.active_accounts.get(account_key)
        if previous_id is not None and previous_id != client.player_id:
            previous = self.clients_by_id.get(previous_id)
            if previous is not None:
                previous.authenticated = False
                previous.account_key = ""
                previous.login = ""
                self.send(previous.addr, {"type": "session_replaced"})
        client.authenticated = True
        client.account_key = account_key
        account = ACCOUNTS[account_key]
        _sanitize_account(account)
        client.login = str(account.get("login", "Player"))
        client.map_id = "lobby"
        client.build = None
        client.state.clear()
        client.last_position = None
        self.active_accounts[account_key] = client.player_id

    def handle_register(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        if client.authenticated:
            self._reliable_reply(client, seq, {"type": "auth_result", "ok": False, "reason": "Сначала выйдите из текущего аккаунта"})
            return
        login = str(msg.get("login", "")).strip()
        password = str(msg.get("password", ""))
        key = _login_key(login)
        if not _valid_login(login):
            self._reliable_reply(client, seq, {"type": "auth_result", "ok": False, "reason": "Логин: 3–20 букв/цифр, _ или -"})
            return
        if len(password) < 6 or len(password) > 64:
            self._reliable_reply(client, seq, {"type": "auth_result", "ok": False, "reason": "Пароль должен содержать 6–64 символа"})
            return
        if key in ACCOUNTS:
            self._reliable_reply(client, seq, {"type": "auth_result", "ok": False, "reason": "Такой логин уже занят"})
            return
        ACCOUNTS[key] = _new_account(login, password)
        _save_accounts()
        self._auth_success(client, key)
        profile = _public_profile(ACCOUNTS[key])
        self._reliable_reply(client, seq, {
            "type": "auth_result", "ok": True, "reason": "", "profile": profile,
            "catalog": public_catalog(), "chat_history": list(self.chat_history),
        })
        print(f"[register] #{client.player_id} login={client.login!r}")

    def handle_login(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        if client.authenticated:
            self._reliable_reply(client, seq, {"type": "auth_result", "ok": False, "reason": "Вы уже вошли в аккаунт"})
            return
        login = str(msg.get("login", "")).strip()
        password = str(msg.get("password", ""))
        key = _login_key(login)
        account = ACCOUNTS.get(key)
        if not isinstance(account, dict) or not _verify_password(account, password):
            self._reliable_reply(client, seq, {"type": "auth_result", "ok": False, "reason": "Неверный логин или пароль"})
            return
        active_id = self.active_accounts.get(key)
        if active_id is not None and active_id != client.player_id and active_id in self.clients_by_id:
            self._reliable_reply(client, seq, {"type": "auth_result", "ok": False, "reason": "Аккаунт уже в сети"})
            return
        self._auth_success(client, key)
        profile = _public_profile(account)
        self._reliable_reply(client, seq, {
            "type": "auth_result", "ok": True, "reason": "", "profile": profile,
            "catalog": public_catalog(), "chat_history": list(self.chat_history),
        })
        print(f"[login] #{client.player_id} login={client.login!r}")

    def _send_profile(self, client: Client) -> None:
        account = self._account(client)
        if account is not None:
            self.send(client.addr, {"type": "profile", "profile": _public_profile(account)})

    def handle_get_profile(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        account = self._account(client)
        if account is None:
            self._reliable_reply(client, seq, {"type": "profile", "profile": {}})
            return
        self._reliable_reply(client, seq, {"type": "profile", "profile": _public_profile(account)})

    def handle_chat(self, client: Client, msg: dict[str, Any]) -> None:
        now = time.monotonic()
        if now - client.chat_last_at < 0.65:
            return
        text = str(msg.get("text", "")).replace("\r", " ").replace("\n", " ").strip()
        text = "".join(ch for ch in text if ch.isprintable())[:160]
        if not text:
            return
        client.chat_last_at = now
        account = self._account(client)
        if account is None:
            return
        rank = _rank_info(int(account.get("xp", 0)))
        event = {"type": "chat", "login": client.login, "rank": str(rank.get("name", "")), "text": text, "ts": int(time.time())}
        self.chat_history.append(dict(event))
        self.broadcast_global(event)

    def _catalog_item(self, category: str, item_id: str, mod: int) -> dict[str, Any] | None:
        if category == "hull":
            for item in HULL_OPTIONS:
                if str(item.get("id", "")) == item_id and int(item.get("mod", 0)) == mod:
                    return item
        elif category == "turret":
            for item in TURRET_OPTIONS:
                if str(item.get("id", "")) == item_id and int(item.get("mod", 0)) == mod:
                    return item
        elif category == "paint" and item_id in PAINTS:
            return PAINTS[item_id]
        return None

    def _owns_item(self, account: dict[str, Any], category: str, item_id: str, mod: int) -> bool:
        if category == "hull":
            return _item_key(item_id, mod) in account.get("owned_hulls", [])
        if category == "turret":
            return _item_key(item_id, mod) in account.get("owned_turrets", [])
        if category == "paint":
            return item_id in account.get("owned_paints", [])
        return False

    def handle_purchase(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        account = self._account(client)
        if account is None or client.map_id != "lobby":
            self._reliable_reply(client, seq, {"type": "purchase_result", "ok": False, "reason": "Покупки доступны только в гараже"})
            return
        category = str(msg.get("category", ""))
        item_id = str(msg.get("id", "")).strip()
        mod = safe_int(msg.get("mod"), 0)
        catalog_item = self._catalog_item(category, item_id, mod)
        if catalog_item is None:
            self._reliable_reply(client, seq, {"type": "purchase_result", "ok": False, "reason": "Предмет не найден"})
            return
        if category in ("hull", "turret") and mod != 0:
            self._reliable_reply(client, seq, {"type": "purchase_result", "ok": False, "reason": "Модули покупаются только в M0. Используйте улучшение."})
            return
        _sanitize_account(account)
        if self._owns_item(account, category, item_id, mod):
            self._reliable_reply(client, seq, {"type": "purchase_result", "ok": False, "reason": "Предмет уже куплен", "profile": _public_profile(account)})
            return
        price = max(0, safe_int((catalog_item or {}).get("price"), ITEM_PRICE))
        if int(account.get("crystals", 0)) < price:
            self._reliable_reply(client, seq, {"type": "purchase_result", "ok": False, "reason": "Недостаточно кристаллов", "profile": _public_profile(account)})
            return
        account["crystals"] = int(account.get("crystals", 0)) - price
        if category == "hull":
            account["owned_hulls"].append(_item_key(item_id, mod))
        elif category == "turret":
            account["owned_turrets"].append(_item_key(item_id, mod))
        else:
            account["owned_paints"].append(item_id)
        _save_accounts()
        self._reliable_reply(client, seq, {"type": "purchase_result", "ok": True, "reason": "Куплено", "profile": _public_profile(account)})

    def handle_upgrade(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        account = self._account(client)
        if account is None or client.map_id != "lobby":
            self._reliable_reply(client, seq, {"type": "upgrade_result", "ok": False, "reason": "Улучшения доступны только в гараже"})
            return
        category = str(msg.get("category", ""))
        item_id = str(msg.get("id", "")).strip()
        target_mod = safe_int(msg.get("mod"), -1)
        if category not in ("hull", "turret") or target_mod < 1 or target_mod > 3:
            self._reliable_reply(client, seq, {"type": "upgrade_result", "ok": False, "reason": "Некорректное улучшение", "profile": _public_profile(account)})
            return
        _sanitize_account(account)
        target_item = self._catalog_item(category, item_id, target_mod)
        previous_item = self._catalog_item(category, item_id, target_mod - 1)
        if target_item is None or previous_item is None:
            self._reliable_reply(client, seq, {"type": "upgrade_result", "ok": False, "reason": "Модификация не найдена", "profile": _public_profile(account)})
            return
        if self._owns_item(account, category, item_id, target_mod):
            self._reliable_reply(client, seq, {"type": "upgrade_result", "ok": False, "reason": "Эта модификация уже открыта", "profile": _public_profile(account)})
            return
        if not self._owns_item(account, category, item_id, target_mod - 1):
            self._reliable_reply(client, seq, {"type": "upgrade_result", "ok": False, "reason": f"Сначала нужна M{target_mod - 1}", "profile": _public_profile(account)})
            return
        rank = _rank_info(int(account.get("xp", 0)))
        min_rank = _item_rank_requirement(target_item)
        if int(rank.get("index", 0)) < min_rank:
            req = _rank_info_by_index(min_rank)
            self._reliable_reply(client, seq, {"type": "upgrade_result", "ok": False, "reason": f"Нужно звание: {req.get('name', '')}", "profile": _public_profile(account)})
            return
        price = max(0, safe_int(target_item.get("upgrade_price"), 0))
        if int(account.get("crystals", 0)) < price:
            self._reliable_reply(client, seq, {"type": "upgrade_result", "ok": False, "reason": "Недостаточно кристаллов", "profile": _public_profile(account)})
            return
        account["crystals"] = int(account.get("crystals", 0)) - price
        owned_key = "owned_hulls" if category == "hull" else "owned_turrets"
        account[owned_key].append(_item_key(item_id, target_mod))
        equipped = account.get("equipped", {})
        if isinstance(equipped, dict):
            equipped_id_key = "hull" if category == "hull" else "turret"
            equipped_mod_key = "hull_mod" if category == "hull" else "turret_mod"
            if str(equipped.get(equipped_id_key, "")) == item_id:
                # An upgrade is a progression of the installed module, not a separate
                # inventory copy: if this module is mounted, mount the new M-level now.
                equipped[equipped_mod_key] = target_mod
                account["equipped"] = equipped
        _sanitize_account(account)
        _save_accounts()
        self._reliable_reply(client, seq, {"type": "upgrade_result", "ok": True, "reason": f"Улучшено до M{target_mod}", "profile": _public_profile(account)})

    def handle_equip(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        account = self._account(client)
        if account is None or client.map_id != "lobby":
            self._reliable_reply(client, seq, {"type": "equip_result", "ok": False, "reason": "Экипировка меняется только в гараже"})
            return
        category = str(msg.get("category", ""))
        item_id = str(msg.get("id", "")).strip()
        mod = safe_int(msg.get("mod"), 0)
        if self._catalog_item(category, item_id, mod) is None or not self._owns_item(account, category, item_id, mod):
            self._reliable_reply(client, seq, {"type": "equip_result", "ok": False, "reason": "Сначала купите предмет", "profile": _public_profile(account)})
            return
        equipped = account.get("equipped", {})
        if not isinstance(equipped, dict):
            equipped = {}
        if category == "hull":
            equipped["hull"], equipped["hull_mod"] = item_id, mod
        elif category == "turret":
            equipped["turret"], equipped["turret_mod"] = item_id, mod
        else:
            equipped["paint"] = item_id
        account["equipped"] = equipped
        _sanitize_account(account)
        _save_accounts()
        self._reliable_reply(client, seq, {"type": "equip_result", "ok": True, "reason": "Установлено", "profile": _public_profile(account)})

    def _room_for_client(self, client: Client) -> BattleRoom | None:
        if client.battle_id <= 0:
            return None
        room = self.battles.get(client.battle_id)
        if room is None or client.map_id != room.map_id:
            return None
        return room

    def _room_from_map(self, map_id: str) -> BattleRoom | None:
        text = str(map_id or "")
        if not text.startswith(BATTLE_ROOM_PREFIX):
            return None
        battle_id = safe_int(text[len(BATTLE_ROOM_PREFIX):], -1)
        return self.battles.get(battle_id)

    def _room_players(self, room: BattleRoom, *, require_build: bool = False) -> list[Client]:
        players = [
            c for c in self.clients_by_id.values()
            if c.authenticated and c.battle_id == room.battle_id and c.map_id == room.map_id
        ]
        if require_build:
            players = [c for c in players if c.build is not None]
        return players

    def _room_humans(self, room: BattleRoom) -> list[Client]:
        return [c for c in self._room_players(room) if not c.is_bot]

    def _room_bots(self, room: BattleRoom) -> list[Client]:
        return [c for c in self._room_players(room) if c.is_bot]

    def _random_bot_build(self, rank_index: int) -> dict[str, Any]:
        # A bot may only use an M-level whose min_rank is available to its generated
        # rank. M0 is configured with min_rank=0, so every legal battle has choices.
        allowed_hulls = [item for item in HULL_OPTIONS if _item_rank_requirement(item) <= rank_index]
        allowed_turrets = [item for item in TURRET_OPTIONS if _item_rank_requirement(item) <= rank_index]
        hull_item = random.choice(allowed_hulls) if allowed_hulls else _starter_hull()
        turret_item = random.choice(allowed_turrets) if allowed_turrets else _starter_turret()
        paint_id = random.choice(list(PAINTS.keys())) if PAINTS else "green"
        build = normalize_build({
            "hull": str(hull_item.get("id", "wasp")),
            "hull_mod": int(hull_item.get("mod", 0)),
            "turret": str(turret_item.get("id", "smoky")),
            "turret_mod": int(turret_item.get("mod", 0)),
            "paint": paint_id,
        })
        if build is not None:
            return build
        return {"hull": "wasp", "hull_mod": 0, "turret": "smoky", "turret_mod": 0, "paint": paint_id}

    def _bot_name(self, room: BattleRoom) -> str:
        used = {c.login.casefold() for c in self._room_players(room)}
        shuffled = list(BOT_NICKNAMES)
        random.shuffle(shuffled)
        for candidate in shuffled:
            if candidate.casefold() not in used:
                return candidate
        # A busy room can exhaust the base pool. Keep the name player-like instead
        # of revealing a BOT_XX sequence.
        for _ in range(200):
            candidate = f"{random.choice(BOT_NICKNAMES)}{random.randint(7, 999)}"
            if candidate.casefold() not in used:
                return candidate
        return f"Ranger{self.next_id}"

    def _preferred_bot_host(self, room: BattleRoom) -> Client | None:
        humans = self._room_humans(room)
        if not humans:
            return None
        for human in humans:
            if human.login == room.owner_login:
                return human
        humans.sort(key=lambda item: item.player_id)
        return humans[0]

    def _send_bot_control(self, bot: Client, event: str = "assign") -> None:
        if not bot.is_bot or bot.bot_host_id <= 0:
            return
        host = self.clients_by_id.get(bot.bot_host_id)
        if host is None or host.is_bot or host.map_id != bot.map_id:
            return
        self.send(host.addr, {
            "type": "bot_control",
            "event": event,
            "bot_id": bot.player_id,
            "login": bot.login,
            "rank_index": bot.bot_rank_index,
            "rank_name": str(_rank_info_by_index(bot.bot_rank_index).get("name", "")),
            "build": bot.build or {},
            "spawn_index": bot.spawn_index,
            "combat": self.combat_payload(bot, time.monotonic()),
            "state": dict(bot.state),
            "map": bot.map_id,
        })

    def _sync_bot_hosts(self, room: BattleRoom) -> None:
        host = self._preferred_bot_host(room)
        host_id = host.player_id if host is not None else -1
        for bot in self._room_bots(room):
            old_host_id = bot.bot_host_id
            if old_host_id == host_id:
                if host_id > 0 and "p" not in bot.state:
                    self._send_bot_control(bot, "assign")
                continue
            if old_host_id > 0:
                old_host = self.clients_by_id.get(old_host_id)
                if old_host is not None and not old_host.is_bot:
                    self.send(old_host.addr, {"type": "bot_control", "event": "release", "bot_id": bot.player_id})
            bot.bot_host_id = host_id
            bot.fire_requested = False
            bot.state["firing"] = False
            if host_id > 0:
                self._send_bot_control(bot, "assign")

    def _remove_bot_entity(self, room: BattleRoom, bot: Client, reason: str = "removed") -> None:
        if not bot.is_bot:
            return
        if bot.bot_host_id > 0:
            host = self.clients_by_id.get(bot.bot_host_id)
            if host is not None and not host.is_bot:
                self.send(host.addr, {"type": "bot_control", "event": "remove", "bot_id": bot.player_id})
        self.clients_by_id.pop(bot.player_id, None)
        self.broadcast({
            "type": "combat", "event": "player_left", "player": bot.player_id,
            "login": bot.login, "rank_index": bot.bot_rank_index,
            "rank_name": str(_rank_info_by_index(bot.bot_rank_index).get("name", "")), "map": room.map_id,
        }, room.map_id)
        print(f"[bot] battle={room.battle_id} removed #{bot.player_id} {bot.login!r} reason={reason}")

    def handle_add_bot(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        battle_id = safe_int(msg.get("battle_id"), -1)
        room = self.battles.get(battle_id)
        if room is None:
            self._reliable_reply(client, seq, {"type": "bot_result", "ok": False, "reason": "Битва не найдена"})
            return
        if client.login != room.owner_login:
            self._reliable_reply(client, seq, {"type": "bot_result", "ok": False, "reason": "Ботов меняет только создатель битвы"})
            return
        if len(self._room_bots(room)) >= BOT_MAX_PER_BATTLE:
            self._reliable_reply(client, seq, {"type": "bot_result", "ok": False, "reason": "Достигнут лимит ботов"})
            return
        # Keep one slot free so the owner cannot fill a lobby with bots and then
        # lock themselves out before joining it.
        if len(self._room_players(room)) >= max(1, room.max_players - 1):
            self._reliable_reply(client, seq, {"type": "bot_result", "ok": False, "reason": "Оставлено место для живого игрока"})
            return
        bot_rank_index = random.randint(room.min_rank, room.max_rank)
        bot = Client(
            player_id=self.next_id, addr=("0.0.0.0", 0), last_seen=time.monotonic(),
            map_id=room.map_id, build=self._random_bot_build(bot_rank_index), authenticated=True,
            login=self._bot_name(room), battle_id=room.battle_id, is_bot=True,
            bot_rank_index=bot_rank_index,
        )
        self.next_id += 1
        self.clients_by_id[bot.player_id] = bot
        self._reserve_spawn(bot, self._choose_spawn_index(bot))
        bot.state = {"turret": 0.0, "speed": 0.0, "left_track": 0.0, "right_track": 0.0, "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "firing": False}
        self._reset_combat(bot)
        self._sync_bot_hosts(room)
        self._reliable_reply(client, seq, {"type": "bot_result", "ok": True, "reason": f"Добавлен {bot.login}"})
        self.broadcast({
            "type": "combat", "event": "player_joined", "player": bot.player_id,
            "login": bot.login, "rank_index": bot.bot_rank_index,
            "rank_name": str(_rank_info_by_index(bot.bot_rank_index).get("name", "")), "map": room.map_id,
        }, room.map_id)
        self.broadcast_match(room)
        self.broadcast_battles()
        print(f"[bot] battle={room.battle_id} added #{bot.player_id} {bot.login!r} build={bot.build}")

    def handle_remove_bot(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        battle_id = safe_int(msg.get("battle_id"), -1)
        room = self.battles.get(battle_id)
        if room is None:
            self._reliable_reply(client, seq, {"type": "bot_result", "ok": False, "reason": "Битва не найдена"})
            return
        if client.login != room.owner_login:
            self._reliable_reply(client, seq, {"type": "bot_result", "ok": False, "reason": "Ботов меняет только создатель битвы"})
            return
        bots = self._room_bots(room)
        if not bots:
            self._reliable_reply(client, seq, {"type": "bot_result", "ok": False, "reason": "В битве нет ботов"})
            return
        bot = sorted(bots, key=lambda item: item.player_id)[-1]
        self._remove_bot_entity(room, bot)
        self._reliable_reply(client, seq, {"type": "bot_result", "ok": True, "reason": f"Удалён {bot.login}"})
        self.broadcast_match(room)
        self.broadcast_battles()

    def handle_bot_state(self, host: Client, msg: dict[str, Any]) -> None:
        bot_id = safe_int(msg.get("bot_id"), -1)
        bot = self.clients_by_id.get(bot_id)
        if bot is None or not bot.is_bot or bot.bot_host_id != host.player_id or bot.map_id != host.map_id:
            return
        bot.last_seen = time.monotonic()
        self.handle_state(bot, msg)

    def handle_bot_shot(self, host: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(host, msg)
        if seq is None:
            return
        bot_id = safe_int(msg.get("bot_id"), -1)
        bot = self.clients_by_id.get(bot_id)
        if bot is None or not bot.is_bot or bot.bot_host_id != host.player_id or bot.map_id != host.map_id:
            self._reliable_reply(host, seq, {"type": "ack"})
            return
        forwarded = dict(msg)
        forwarded["seq"] = -1
        self.handle_shot(bot, forwarded)
        self._reliable_reply(host, seq, {"type": "ack"})

    def _public_battle(self, room: BattleRoom) -> dict[str, Any]:
        active_players = len(self._room_players(room))
        bot_count = len(self._room_bots(room))
        map_info = BATTLE_MAPS.get(room.map_key, {"name": _humanize_map_key(room.map_key)})
        return {
            "id": room.battle_id,
            "name": room.name,
            "map": room.map_key,
            "map_name": str(map_info.get("name", room.map_key)),
            "kill_limit": room.kill_limit,
            "max_players": room.max_players,
            "min_rank": room.min_rank,
            "max_rank": room.max_rank,
            "min_rank_name": str(_rank_info_by_index(room.min_rank).get("name", "")),
            "max_rank_name": str(_rank_info_by_index(room.max_rank).get("name", "")),
            "players": active_players,
            "bots": bot_count,
            "owner": room.owner_login,
            "active": room.round_active,
        }

    def battles_payload(self) -> dict[str, Any]:
        rooms = [self._public_battle(room) for room in self.battles.values()]
        rooms.sort(key=lambda item: int(item.get("id", 0)))
        return {"type": "battles", "battles": rooms, "maps": public_maps()}

    def broadcast_battles(self) -> None:
        self.broadcast_global(self.battles_payload())

    def handle_list_battles(self, client: Client, msg: dict[str, Any]) -> None:
        refresh_battle_maps()
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        payload = self.battles_payload()
        self._reliable_reply(client, seq, payload)

    def handle_create_battle(self, client: Client, msg: dict[str, Any]) -> None:
        refresh_battle_maps()
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        if client.map_id != "lobby":
            self._reliable_reply(client, seq, {"type": "battle_created", "ok": False, "reason": "Создавать битвы можно только из лобби", "battle": {}})
            return
        name = " ".join(str(msg.get("name", "")).strip().split())[:36]
        if not name:
            name = f"Битва {client.login}"
        map_key = str(msg.get("map", DEFAULT_BATTLE_MAP)).strip().lower()
        if map_key not in BATTLE_MAPS:
            self._reliable_reply(client, seq, {"type": "battle_created", "ok": False, "reason": "Карта не найдена на сервере", "battle": {}})
            return
        requested_kill_limit = msg.get("kill_limit", KILL_LIMIT)
        kill_limit = max(1, min(999, safe_int(requested_kill_limit, KILL_LIMIT)))
        max_players = max(2, min(32, safe_int(msg.get("max_players"), 10)))
        rank_count = len(ECONOMY.get("ranks", [])) if isinstance(ECONOMY.get("ranks", []), list) else 27
        rank_last = max(0, rank_count - 1)
        min_rank = max(0, min(rank_last, safe_int(msg.get("min_rank"), 0)))
        max_rank = max(0, min(rank_last, safe_int(msg.get("max_rank"), rank_last)))
        if min_rank > max_rank:
            min_rank, max_rank = max_rank, min_rank
        creator_account = self._account(client)
        creator_rank = int(_rank_info(int(creator_account.get("xp", 0))).get("index", 0)) if creator_account is not None else 0
        if creator_rank < min_rank or creator_rank > max_rank:
            self._reliable_reply(client, seq, {"type": "battle_created", "ok": False, "reason": "Ваше звание не входит в выбранный диапазон", "battle": {}})
            return
        room = BattleRoom(
            battle_id=self.next_battle_id,
            name=name,
            map_key=map_key,
            kill_limit=kill_limit,
            max_players=max_players,
            owner_login=client.login,
            created_at=time.time(),
            min_rank=min_rank,
            max_rank=max_rank,
        )
        self.next_battle_id += 1
        self.battles[room.battle_id] = room
        self._reliable_reply(client, seq, {"type": "battle_created", "ok": True, "reason": "", "battle": self._public_battle(room)})
        self.broadcast_battles()
        print(f"[battle] created id={room.battle_id} map={room.map_key!r} name={room.name!r} owner={client.login!r} kills={room.kill_limit} max={room.max_players} ranks={room.min_rank}-{room.max_rank}")

    def _spawn_slot_occupied(self, spawn_index: int, map_id: str, exclude_id: int = -1) -> bool:
        """Keep a spawn reserved while a live tank is still near its spawn anchor."""
        now = time.monotonic()
        for other in self.clients_by_id.values():
            if other.player_id == exclude_id or other.map_id != map_id:
                continue
            if other.spawn_index != spawn_index:
                continue
            # v18.18.26: a dead client reserves its NEXT spawn during the whole
            # respawn countdown. This makes the camera target and actual respawn
            # deterministic and prevents two cinematic cameras from targeting the
            # same freshly reserved spawn.
            if not other.alive:
                if other.respawn_at > now and now - other.spawn_reserved_at < 8.0:
                    return True
                continue
            # Fresh spawns reserve their slot before the first state packet arrives.
            # This closes the race where two clients could be assigned the same
            # position during the same snapshot interval.
            if now - other.spawn_reserved_at < 2.5:
                return True
            if other.spawn_anchor_position is None or other.last_position is None:
                if now - other.spawn_reserved_at < 8.0:
                    return True
                continue
            if math.dist(other.last_position, other.spawn_anchor_position) < 8.0:
                return True
        return False

    def _choose_spawn_index(self, client: Client) -> int:
        room = self._room_for_client(client)
        spawn_count = SPAWN_COUNT
        if room is not None:
            spawn_count = max(1, int(BATTLE_MAPS.get(room.map_key, {}).get("spawn_count", SPAWN_COUNT)))
        candidates = list(range(spawn_count))
        random.shuffle(candidates)
        for spawn_index in candidates:
            if not self._spawn_slot_occupied(spawn_index, client.map_id, client.player_id):
                return spawn_index
        # With nine virtual slots this should only happen in a very crowded match.
        # Prefer the least recently reserved slot instead of stacking two fresh
        # respawns on top of one another.
        reserved: list[tuple[float, int]] = []
        for spawn_index in candidates:
            newest = 0.0
            for other in self.clients_by_id.values():
                if other.map_id == client.map_id and other.spawn_index == spawn_index:
                    newest = max(newest, other.spawn_reserved_at)
            reserved.append((newest, spawn_index))
        reserved.sort(key=lambda item: item[0])
        return reserved[0][1] if reserved else 0

    def _reserve_spawn(self, client: Client, spawn_index: int) -> None:
        client.spawn_index = spawn_index
        client.spawn_anchor_position = None
        client.spawn_reserved_at = time.monotonic()

    def handle_join_battle(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        account = self._account(client)
        if account is None:
            self._reliable_reply(client, seq, {"type": "battle_joined", "ok": False, "reason": "Требуется вход в аккаунт"})
            return
        if client.map_id != "lobby":
            self._reliable_reply(client, seq, {"type": "battle_joined", "ok": False, "reason": "Сначала выйдите из текущей битвы"})
            return
        battle_id = safe_int(msg.get("battle_id"), -1)
        room = self.battles.get(battle_id)
        if room is None:
            self._reliable_reply(client, seq, {"type": "battle_joined", "ok": False, "reason": "Битва не найдена"})
            return
        join_rank = int(_rank_info(int(account.get("xp", 0))).get("index", 0))
        if join_rank < room.min_rank or join_rank > room.max_rank:
            min_name = str(_rank_info_by_index(room.min_rank).get("name", ""))
            max_name = str(_rank_info_by_index(room.max_rank).get("name", ""))
            self._reliable_reply(client, seq, {"type": "battle_joined", "ok": False, "reason": f"Доступно для званий: {min_name} — {max_name}"})
            return
        if len(self._room_players(room)) >= room.max_players:
            self._reliable_reply(client, seq, {"type": "battle_joined", "ok": False, "reason": "Битва заполнена"})
            return
        _sanitize_account(account)
        build = normalize_build(account.get("equipped", {}))
        if build is None:
            self._reliable_reply(client, seq, {"type": "battle_joined", "ok": False, "reason": "Некорректная экипировка"})
            return
        client.battle_id = room.battle_id
        client.map_id = room.map_id
        client.build = build
        self._reserve_spawn(client, self._choose_spawn_index(client))
        client.state = {"turret": 0.0, "speed": 0.0, "left_track": 0.0, "right_track": 0.0, "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "firing": False}
        client.last_position = None
        client.last_position_time = 0.0
        client.round_kills = 0
        client.round_score = 0
        client.round_damage = 0.0
        client.round_xp = 0
        self._reset_combat(client)
        self._reliable_reply(client, seq, {
            "type": "battle_joined", "ok": True, "reason": "", "build": build,
            "spawn_index": client.spawn_index, "combat": self.combat_payload(client, time.monotonic()),
            "match": self.match_payload(room), "battle": self._public_battle(room), "map": room.map_id, "map_key": room.map_key,
            "map_asset": _public_map_asset(room.map_key),
        })
        join_rank = _rank_info(int(account.get("xp", 0)))
        self._sync_bot_hosts(room)
        self.broadcast({
            "type": "combat", "event": "player_joined", "player": client.player_id,
            "login": client.login, "rank_index": int(join_rank.get("index", 0)),
            "rank_name": str(join_rank.get("name", "")), "map": room.map_id,
        }, room.map_id)
        self.broadcast_match(room)
        self.broadcast_battles()
        print(f"[battle] {client.login} joined {room.name!r} id={room.battle_id}")

    def handle_leave_battle(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        old_map = client.map_id
        old_room = self._room_for_client(client)
        leave_account = self._account(client)
        leave_rank = _rank_info(int(leave_account.get("xp", 0))) if leave_account is not None else {"index": 0, "name": ""}
        client.map_id = "lobby"
        client.battle_id = -1
        client.build = None
        client.state.clear()
        client.last_position = None
        client.spawn_index = -1
        client.spawn_anchor_position = None
        client.spawn_reserved_at = 0.0
        client.fire_requested = False
        client.fire_targets.clear()
        self._reliable_reply(client, seq, {"type": "battle_left", "ok": True})
        if old_room is not None:
            self.broadcast({
                "type": "combat", "event": "player_left", "player": client.player_id,
                "login": client.login, "rank_index": int(leave_rank.get("index", 0)),
                "rank_name": str(leave_rank.get("name", "")), "map": old_map,
            }, old_map)
            self._sync_bot_hosts(old_room)
            self.broadcast_match(old_room)
            self.broadcast_battles()

    def match_payload(self, room: BattleRoom) -> dict[str, Any]:
        now = time.monotonic()
        players = []
        for client in self._room_players(room):
            rank = _client_rank_info(client)
            players.append({
                "id": client.player_id, "login": client.login, "rank": str(rank.get("name", "")),
                "rank_index": int(rank.get("index", 0)),
                "kills": client.round_kills, "score": client.round_score, "is_bot": client.is_bot,
            })
        players.sort(key=lambda item: (-int(item["kills"]), -int(item["score"]), str(item["login"]).casefold()))
        restart_in = max(0.0, room.round_restart_at - now) if not room.round_active else 0.0
        return {
            "type": "match_state", "round_id": room.round_id, "active": room.round_active,
            "fund": room.battle_fund, "kill_limit": room.kill_limit, "restart_in": round(restart_in, 2),
            "battle_id": room.battle_id, "battle_name": room.name, "players": players,
        }

    def broadcast_match(self, room: BattleRoom) -> None:
        self.broadcast(self.match_payload(room), room.map_id)

    def _reward_split(self, fund: int, count: int) -> list[int]:
        if count <= 0 or fund <= 0:
            return [0] * max(0, count)
        weights = list(range(count, 0, -1))
        total_weight = sum(weights)
        exact = [fund * weight / float(total_weight) for weight in weights]
        rewards = [int(math.floor(value)) for value in exact]
        remaining = fund - sum(rewards)
        order = sorted(range(count), key=lambda i: (-(exact[i] - rewards[i]), i))
        for i in order[:remaining]:
            rewards[i] += 1
        return rewards

    def _finish_round(self, winner: Client) -> None:
        room = self._room_for_client(winner)
        if room is None or not room.round_active:
            return
        room.round_active = False
        now = time.monotonic()
        room.round_restart_at = now + INTERMISSION_SECONDS
        participants = self._room_players(room)
        participants.sort(key=lambda c: (-c.round_kills, -c.round_score, c.login.casefold()))
        final_fund = room.battle_fund
        human_participants = [client for client in participants if not client.is_bot]
        human_rewards = self._reward_split(final_fund, len(human_participants))
        reward_by_id = {client.player_id: human_rewards[index] for index, client in enumerate(human_participants)}
        results = []
        for index, client in enumerate(participants):
            account = self._account(client)
            crystal_reward = int(reward_by_id.get(client.player_id, 0))
            xp_reward = client.round_xp
            if account is not None:
                account["crystals"] = int(account.get("crystals", 0)) + crystal_reward
                stats = account.get("stats", {})
                if not isinstance(stats, dict):
                    stats = {}
                stats["battles"] = int(stats.get("battles", 0)) + 1
                stats["kills"] = int(stats.get("kills", 0)) + max(0, client.round_kills)
                if index == 0:
                    stats["wins"] = int(stats.get("wins", 0)) + 1
                account["stats"] = stats
            results.append({
                "place": index + 1, "id": client.player_id, "login": client.login,
                "kills": client.round_kills, "score": client.round_score,
                "crystals": crystal_reward, "xp": xp_reward,
            })
            client.fire_requested = False
            client.state["firing"] = False
            client.respawn_at = 0.0
        self._clear_supplies(room, "round_end")
        room.battle_fund = 0
        _save_accounts()
        self.broadcast({
            "type": "round_end", "round_id": room.round_id, "winner": winner.login,
            "fund": final_fund, "restart_in": INTERMISSION_SECONDS, "results": results,
        }, room.map_id)
        for client in participants:
            if not client.is_bot:
                self._send_profile(client)
        self.broadcast_match(room)
        self.broadcast_battles()
        print(f"[round] battle={room.battle_id} #{room.round_id} winner={winner.login!r} fund={final_fund} players={len(participants)}")

    def _start_new_round(self, room: BattleRoom) -> None:
        room.round_id += 1
        room.round_active = True
        room.round_restart_at = 0.0
        room.battle_fund = 0
        self._clear_supplies(room, "round_start")
        room.next_regular_supply_at = time.monotonic() + random.uniform(SUPPLY_REGULAR_MIN_SECONDS, SUPPLY_REGULAR_MAX_SECONDS)
        participants = self._room_players(room, require_build=True)
        for client in participants:
            client.round_kills = 0
            client.round_score = 0
            client.round_damage = 0.0
            client.round_xp = 0
        self.broadcast({"type": "round_start", "round_id": room.round_id, "kill_limit": room.kill_limit}, room.map_id)
        for client in participants:
            self._respawn(client)
        self.broadcast_match(room)
        print(f"[round] battle={room.battle_id} #{room.round_id} started")

    def _reset_combat(self, client: Client) -> None:
        if client.build is None:
            return
        hs = hull_spec(client.build)
        ws = weapon_spec(client.build)
        client.max_hp = max(1.0, float(hs.get("max_hp", 1.0)))
        client.hp = client.max_hp
        client.alive = True
        client.fuel_max = max(0.0, float(ws.get("fuel_max", 0.0)))
        client.fuel = client.fuel_max
        client.fire_requested = False
        client.fire_targets.clear()
        client.last_fire_active = 0.0
        client.last_shot_time = -1000.0
        client.burn_end = 0.0
        client.burn_duration = 0.0
        client.burn_dps = 0.0
        client.burn_source = -1
        client.nitro_end = 0.0
        client.armor_end = 0.0
        client.damage_end = 0.0
        client.respawn_at = 0.0

    def handle_spawn(self, client: Client, msg: dict):
        seq = safe_int(msg.get("seq"), -1)
        build = normalize_build(msg.get("build"))
        if build is None:
            self.send(client.addr, {
                "type": "spawn_result", "seq": seq, "ok": False,
                "build": {}, "spawn_index": -1, "reason": "invalid loadout",
                "map": client.map_id,
            })
            return
        spawn_index = self._choose_spawn_index(client)
        client.build = build
        self._reserve_spawn(client, spawn_index)
        client.state = {
            "turret": 0.0,
            "speed": 0.0,
            "left_track": 0.0,
            "right_track": 0.0,
            "lin_vel": [0.0, 0.0, 0.0],
            "ang_vel": [0.0, 0.0, 0.0],
            "firing": False,
        }
        client.last_position = None
        client.last_position_time = 0.0
        self._reset_combat(client)
        self.send(client.addr, {
            "type": "spawn_result", "seq": seq, "ok": True,
            "build": build, "spawn_index": spawn_index, "reason": "",
            "combat": self.combat_payload(client, time.monotonic()),
            "map": client.map_id,
        })
        print(
            f"[spawn] room={client.map_id} #{client.player_id} zone={spawn_index} "
            f"{build['hull']} M{build['hull_mod']} + {build['turret']} M{build['turret_mod']} paint={build['paint']} "
            f"hp={client.max_hp:.0f}"
        )

    def handle_state(self, client: Client, msg: dict):
        if client.build is None:
            return
        now = time.monotonic()
        if client.alive:
            p = vec3(msg.get("p"))
            if p is not None:
                if client.last_position is None:
                    client.last_position = p
                    client.last_position_time = now
                    if client.spawn_anchor_position is None:
                        client.spawn_anchor_position = list(p)
                else:
                    dt = max(0.01, now - client.last_position_time)
                    dist = math.dist(p, client.last_position)
                    if dist <= 35.0 * dt + 3.5:
                        client.last_position = p
                        client.last_position_time = now
                    else:
                        p = client.last_position
                client.state["p"] = p
        for key, lo, hi in (
            ("yaw", -10000, 10000),
            ("turret", -10000, 10000),
            ("speed", -18, 18),
            ("left_track", -1.2, 1.2),
            ("right_track", -1.2, 1.2),
        ):
            value = finite_number(msg.get(key))
            if value is not None:
                client.state[key] = min(hi, max(lo, value))
        rot = vec4(msg.get("rot"))
        if rot is not None:
            norm = math.sqrt(sum(v * v for v in rot))
            if 0.25 <= norm <= 2.0:
                client.state["rot"] = [round(v / norm, 5) for v in rot]
        lin_vel = vec3(msg.get("lin_vel"))
        if lin_vel is not None:
            client.state["lin_vel"] = [min(60.0, max(-60.0, v)) for v in lin_vel]
        ang_vel = vec3(msg.get("ang_vel"))
        if ang_vel is not None:
            client.state["ang_vel"] = [min(20.0, max(-20.0, v)) for v in ang_vel]
        aim = vec3(msg.get("aim"))
        if aim is not None:
            unit = normalized(aim)
            if unit is not None:
                client.state["aim"] = [round(v, 5) for v in unit]
        weapon = str(weapon_spec(client.build).get("kind", ""))
        room = self._room_for_client(client)
        can_fire = self._client_can_fire(client)
        client.fire_requested = bool(msg.get("firing", False)) and weapon == "continuous" and client.alive and room is not None and room.round_active and can_fire
        raw_targets = msg.get("fire_targets", []) if can_fire else []
        targets: list[int] = []
        if isinstance(raw_targets, list):
            for item in raw_targets[:8]:
                target_id = safe_int(item, -1)
                if target_id >= 0 and target_id != client.player_id and target_id not in targets:
                    targets.append(target_id)
        client.fire_targets = targets

    @staticmethod
    def _rotation_basis(state: dict[str, Any]) -> list[list[float]]:
        raw = state.get("rot")
        if isinstance(raw, list) and len(raw) >= 4:
            vals = [finite_number(raw[i]) for i in range(4)]
            if all(v is not None for v in vals):
                x, y, z, w = (float(v) for v in vals)
                norm = math.sqrt(x*x + y*y + z*z + w*w)
                if norm > 1e-6:
                    x, y, z, w = x/norm, y/norm, z/norm, w/norm
                    return [
                        [1.0 - 2.0*(y*y + z*z), 2.0*(x*y - z*w), 2.0*(x*z + y*w)],
                        [2.0*(x*y + z*w), 1.0 - 2.0*(x*x + z*z), 2.0*(y*z - x*w)],
                        [2.0*(x*z - y*w), 2.0*(y*z + x*w), 1.0 - 2.0*(x*x + y*y)],
                    ]
        yaw = float(state.get("yaw", 0.0))
        c, sn = math.cos(yaw), math.sin(yaw)
        return [[c, 0.0, -sn], [0.0, 1.0, 0.0], [sn, 0.0, c]]

    @classmethod
    def _client_up_dot(cls, client: Client) -> float:
        basis = cls._rotation_basis(client.state)
        # Local +Y expressed in world space is column 1 of the rotation matrix;
        # dot(world_up) is its Y component.
        return float(basis[1][1])

    @classmethod
    def _client_can_fire(cls, client: Client) -> bool:
        return cls._client_up_dot(client) >= 0.18

    @staticmethod
    def _basis_mul(basis: list[list[float]], v: list[float]) -> list[float]:
        return [sum(basis[row][col] * v[col] for col in range(3)) for row in range(3)]

    @staticmethod
    def _basis_transpose_mul(basis: list[list[float]], v: list[float]) -> list[float]:
        return [sum(basis[row][col] * v[row] for row in range(3)) for col in range(3)]

    @staticmethod
    def _segment_aabb_interval(a: list[float], b: list[float], half: tuple[float, float, float]) -> tuple[float, float] | None:
        t_enter, t_exit = 0.0, 1.0
        for axis in range(3):
            delta = b[axis] - a[axis]
            extent = half[axis]
            if abs(delta) < 1e-8:
                if a[axis] < -extent or a[axis] > extent:
                    return None
                continue
            t0 = (-extent - a[axis]) / delta
            t1 = (extent - a[axis]) / delta
            if t0 > t1:
                t0, t1 = t1, t0
            t_enter = max(t_enter, t0)
            t_exit = min(t_exit, t1)
            if t_enter > t_exit:
                return None
        return t_enter, t_exit

    def _target_hit_volume(self, target: Client, start: list[float], end: list[float], weapon_id: str) -> tuple[float, list[float]] | None:
        if target.last_position is None or target.build is None:
            return None
        hull_id = str(target.build.get("hull", "wasp"))
        base_half, center_y = HULL_HIT_VOLUMES.get(hull_id, HULL_HIT_VOLUMES["wasp"])
        pad = WEAPON_HIT_PADDING.get(weapon_id, WEAPON_HIT_PADDING["smoky"])
        half = tuple(base_half[i] + pad[i] for i in range(3))
        basis = self._rotation_basis(target.state)
        center_offset = self._basis_mul(basis, [0.0, center_y, 0.0])
        center = [target.last_position[i] + center_offset[i] for i in range(3)]
        local_start = self._basis_transpose_mul(basis, [start[i] - center[i] for i in range(3)])
        local_end = self._basis_transpose_mul(basis, [end[i] - center[i] for i in range(3)])
        interval = self._segment_aabb_interval(local_start, local_end, half)
        if interval is None:
            return None
        t_enter, t_exit = interval
        inside = all(abs(local_start[i]) <= half[i] for i in range(3))
        # Capture and visual impact are intentionally separate.  At point-blank range
        # the muzzle can start inside the *forgiving* padded volume even though it is
        # still just outside the visible armor.  Counting that as a hit is correct,
        # but putting the FX on the far exit face makes the explosion appear behind
        # the tank.  Prefer the unpadded hull surface for the visual point.
        capture_t = 0.0 if inside else t_enter
        visual_t = t_enter
        base_interval = self._segment_aabb_interval(local_start, local_end, base_half)
        if base_interval is not None:
            base_enter, base_exit = base_interval
            base_inside = all(abs(local_start[i]) <= base_half[i] for i in range(3))
            if base_inside:
                segment_length = max(distance(start, end), 0.001)
                visual_t = min(base_exit, min(1.0, 0.32 / segment_length))
            else:
                visual_t = base_enter
        elif inside:
            segment_length = max(distance(start, end), 0.001)
            visual_t = min(t_exit, min(1.0, 0.28 / segment_length))
        visual_t = max(0.0, min(1.0, visual_t))
        impact = [start[i] + (end[i] - start[i]) * visual_t for i in range(3)]
        return capture_t, impact

    @staticmethod
    def _extended_capture_end(start: list[float], end: list[float], weapon_id: str) -> list[float]:
        extension = max(0.0, WEAPON_ENDPOINT_CAPTURE.get(weapon_id, 0.0))
        if extension <= 0.0:
            return list(end)
        direction = normalized([end[i] - start[i] for i in range(3)])
        if direction is None:
            return list(end)
        return [end[i] + direction[i] * extension for i in range(3)]

    def _line_target_hit(self, shooter: Client, start: list[float], end: list[float], weapon_id: str) -> tuple[Client | None, list[float]]:
        best: Client | None = None
        best_t = 2.0
        best_impact = list(end)
        for target in self.clients_by_id.values():
            if target.player_id == shooter.player_id or target.map_id != shooter.map_id or not target.alive:
                continue
            hit = self._target_hit_volume(target, start, end, weapon_id)
            if hit is None:
                continue
            t_hit, impact = hit
            if t_hit < best_t:
                best = target
                best_t = t_hit
                best_impact = impact
        return best, best_impact

    def _claimed_line_hit(self, shooter: Client, target_id: int, start: list[float], end: list[float], weapon_id: str) -> tuple[Client | None, list[float]]:
        if target_id < 0:
            return None, list(end)
        target = self.clients_by_id.get(target_id)
        if target is None or target.player_id == shooter.player_id or target.map_id != shooter.map_id or not target.alive:
            return None, list(end)
        hit = self._target_hit_volume(target, start, end, weapon_id)
        if hit is not None:
            _, impact = hit
            return target, impact

        # The client may have vertically auto-aimed at exposed armor while our
        # replicated target transform is a frame behind. Accept only a small
        # server-side miss around the claimed target; this is a lag allowance, not
        # client-authoritative damage.
        if target.last_position is None or target.build is None:
            return None, list(end)
        hull_id = str(target.build.get("hull", "wasp"))
        base_half, center_y = HULL_HIT_VOLUMES.get(hull_id, HULL_HIT_VOLUMES["wasp"])
        basis = self._rotation_basis(target.state)
        center_offset = self._basis_mul(basis, [0.0, center_y, 0.0])
        center = [target.last_position[i] + center_offset[i] for i in range(3)]
        miss, t_near = segment_point_distance(start, end, center)
        lag_radius = math.hypot(base_half[0], base_half[1]) + (1.35 if weapon_id == "smoky" else 2.05)
        if miss <= lag_radius and t_near >= 0.03:
            impact = [start[i] + (end[i] - start[i]) * t_near for i in range(3)]
            return target, impact

        # Stronger Tanki-style vertical capture for an explicitly claimed target.
        # The endpoint still has to be close to the replicated target and the yaw/
        # elevation angles remain bounded, so this is a platform-edge/lag allowance.
        shot_vec = [end[i] - start[i] for i in range(3)]
        shot_flat_len = math.hypot(shot_vec[0], shot_vec[2])
        target_vec = [center[i] - start[i] for i in range(3)]
        target_flat_len = math.hypot(target_vec[0], target_vec[2])
        if shot_flat_len < 0.05 or target_flat_len < 0.05:
            return None, list(end)
        shot_flat = [shot_vec[0] / shot_flat_len, shot_vec[2] / shot_flat_len]
        target_flat = [target_vec[0] / target_flat_len, target_vec[2] / target_flat_len]
        yaw_dot = max(-1.0, min(1.0, shot_flat[0] * target_flat[0] + shot_flat[1] * target_flat[1]))
        yaw_deg = math.degrees(math.acos(yaw_dot))
        yaw_limit = 11.5 if weapon_id == "smoky" else 16.5
        pitch_deg = abs(math.degrees(math.atan2(target_vec[1], max(target_flat_len, 0.001))))
        pitch_limit = 48.0 if weapon_id == "smoky" else 56.0
        endpoint_flat = math.hypot(end[0] - center[0], end[2] - center[2])
        endpoint_vertical = abs(end[1] - center[1])
        endpoint_allowance = base_half[2] * 0.90 + (1.4 if weapon_id == "smoky" else 2.2)
        if yaw_deg > yaw_limit or pitch_deg > pitch_limit:
            return None, list(end)
        if endpoint_flat > endpoint_allowance or endpoint_vertical > base_half[1] + (2.2 if weapon_id == "smoky" else 2.8):
            return None, list(end)
        impact = [center[0], center[1] + base_half[1] * 0.28, center[2]]
        return target, impact

    @staticmethod
    def _horizontal_distance(a: list[float], b: list[float]) -> float:
        return math.hypot(a[0] - b[0], a[2] - b[2])

    def _choose_supply_zone(self, room: BattleRoom) -> list[float] | None:
        map_info = BATTLE_MAPS.get(room.map_key, {})
        raw_zones = map_info.get("supply_zones", [])
        candidates = [list(zone) for zone in raw_zones if isinstance(zone, (list, tuple)) and len(zone) >= 3]
        # Backward compatibility for Arena-derived scenes made before Supply_N markers
        # existed. They share the original Arena geometry, so the curated legacy zones
        # are valid automatically.
        if not candidates and bool(map_info.get("arena_compatible", False)):
            candidates = [list(zone) for zone in SUPPLY_ZONES]
        random.shuffle(candidates)
        active_players = [
            c.last_position for c in self._room_players(room)
            if c.alive and c.last_position is not None
        ]
        active_drops = [drop.position for drop in room.supplies.values()]
        for zone in candidates:
            landing = [float(zone[0]), float(zone[1]), float(zone[2])]
            if any(self._horizontal_distance(landing, p) < SUPPLY_PLAYER_AVOID_RADIUS for p in active_players):
                continue
            if any(self._horizontal_distance(landing, p) < SUPPLY_DROP_AVOID_RADIUS for p in active_drops):
                continue
            return landing
        if candidates:
            zone = candidates[0]
            return [float(zone[0]), float(zone[1]), float(zone[2])]
        return None

    def _supply_ground_lifetime(self, kind: str) -> float:
        if kind == "crystal":
            return SUPPLY_GROUND_SECONDS * SUPPLY_CRYSTAL_LIFETIME_MULTIPLIER
        if kind == "medkit":
            return SUPPLY_GROUND_SECONDS * SUPPLY_MEDKIT_LIFETIME_MULTIPLIER
        return SUPPLY_GROUND_SECONDS

    def _spawn_supply(self, room: BattleRoom, kind: str, reason: str) -> SupplyDrop | None:
        if not room.round_active or not self._room_players(room):
            return None
        now = time.monotonic()
        landing = self._choose_supply_zone(room)
        if landing is None:
            print(f"[supply] battle={room.battle_id} map={room.map_key!r}: no Supply_N markers or Arena fallback zones")
            return None
        persistent = kind == "gold"
        ground_lifetime = self._supply_ground_lifetime(kind)
        drop = SupplyDrop(
            supply_id=room.next_supply_id,
            kind=kind,
            position=landing,
            spawned_at=now,
            lands_at=now + SUPPLY_DESCENT_SECONDS,
            expires_at=0.0 if persistent else now + SUPPLY_DESCENT_SECONDS + ground_lifetime,
            persistent=persistent,
        )
        room.next_supply_id += 1
        room.supplies[drop.supply_id] = drop
        self.broadcast({
            "type": "supply_event",
            "event": "spawn",
            "supply": self._supply_payload(drop, now),
            "reason": reason,
        }, room.map_id)
        print(f"[supply] battle={room.battle_id} spawn id={drop.supply_id} kind={kind} reason={reason} p={landing} persistent={persistent}")
        return drop

    def _supply_world_position(self, drop: SupplyDrop, now: float) -> list[float]:
        fall_remaining = max(0.0, drop.lands_at - now)
        ratio = max(0.0, min(1.0, fall_remaining / max(SUPPLY_DESCENT_SECONDS, 0.1)))
        eased = ratio * ratio * (3.0 - 2.0 * ratio)
        return [
            float(drop.position[0]),
            float(drop.position[1]) + SUPPLY_DROP_HEIGHT * eased + SUPPLY_CRATE_HALF_HEIGHT,
            float(drop.position[2]),
        ]

    def _supply_payload(self, drop: SupplyDrop, now: float) -> dict[str, Any]:
        ground_remaining = -1.0 if drop.persistent else max(0.0, drop.expires_at - max(now, drop.lands_at))
        return {
            "id": drop.supply_id,
            "kind": drop.kind,
            "p": [round(v, 3) for v in drop.position],
            "descent": SUPPLY_DESCENT_SECONDS,
            "fall_remaining": round(max(0.0, drop.lands_at - now), 3),
            "ground_remaining": round(ground_remaining, 3),
            "persistent": drop.persistent,
        }

    def _supply_snapshot(self, room: BattleRoom, now: float) -> list[dict[str, Any]]:
        return [
            self._supply_payload(drop, now)
            for drop in room.supplies.values()
            if drop.persistent or now < drop.expires_at
        ]

    def _clear_supplies(self, room: BattleRoom, reason: str) -> None:
        if not room.supplies:
            return
        room.supplies.clear()
        self.broadcast({"type": "supply_event", "event": "reset", "reason": reason}, room.map_id)

    def _buff_remaining(self, client: Client, now: float) -> dict[str, float]:
        return {
            "nitro": round(max(0.0, client.nitro_end - now), 2),
            "armor": round(max(0.0, client.armor_end - now), 2),
            "damage": round(max(0.0, client.damage_end - now), 2),
            "nitro_speed_multiplier": NITRO_SPEED_MULTIPLIER,
        }

    @staticmethod
    def _damage_multiplier(client: Client | None, now: float) -> float:
        return DAMAGE_MULTIPLIER if client is not None and client.damage_end > now else 1.0

    def _can_collect_supply(self, client: Client, drop: SupplyDrop, now: float) -> bool:
        if not client.alive or client.last_position is None:
            return False
        if client.is_bot and drop.kind in {"gold", "crystal"}:
            return False
        if not drop.persistent and now >= drop.expires_at:
            return False
        crate_position = self._supply_world_position(drop, now)
        if self._horizontal_distance(client.last_position, crate_position) > SUPPLY_PICKUP_RADIUS:
            return False
        if abs(client.last_position[1] - crate_position[1]) > SUPPLY_PICKUP_VERTICAL:
            return False
        return True

    def _collect_supply(self, room: BattleRoom, client: Client, drop: SupplyDrop, now: float) -> bool:
        if room.supplies.get(drop.supply_id) is not drop or not self._can_collect_supply(client, drop, now):
            return False
        account = self._account(client)
        if drop.kind == "nitro":
            client.nitro_end = now + SUPPLY_BUFF_SECONDS
        elif drop.kind == "armor":
            client.armor_end = now + SUPPLY_BUFF_SECONDS
        elif drop.kind == "damage":
            client.damage_end = now + SUPPLY_BUFF_SECONDS
        elif drop.kind == "medkit":
            client.hp = min(client.max_hp, client.hp + client.max_hp * HEAL_FRACTION)
        elif drop.kind == "crystal":
            if account is None:
                return False
            account["crystals"] = int(account.get("crystals", 0)) + CRYSTAL_REWARD
            _save_accounts()
            self._send_profile(client)
        elif drop.kind == "gold":
            if account is None:
                return False
            account["crystals"] = int(account.get("crystals", 0)) + GOLD_REWARD
            _save_accounts()
            self._send_profile(client)
        else:
            return False

        room.supplies.pop(drop.supply_id, None)
        crate_position = self._supply_world_position(drop, now)
        self.broadcast({
            "type": "supply_event",
            "event": "pickup",
            "id": drop.supply_id,
            "kind": drop.kind,
            "player": client.player_id,
            "login": client.login,
            "p": [round(v, 3) for v in crate_position],
            "combat": self.combat_payload(client, now),
        }, room.map_id)
        print(f"[supply] battle={room.battle_id} pickup id={drop.supply_id} kind={drop.kind} player={client.login!r} airborne={now < drop.lands_at}")
        return True

    def handle_supply_pickup(self, client: Client, msg: dict[str, Any]) -> None:
        room = self._room_for_client(client)
        if room is None or not room.round_active:
            return
        supply_id = safe_int(msg.get("id"), -1)
        drop = room.supplies.get(supply_id)
        if drop is None:
            return
        self._collect_supply(room, client, drop, time.monotonic())

    def _auto_collect_supplies(self, room: BattleRoom, now: float) -> None:
        # Server-side proximity collection is what lets physics-hosted bots use
        # supplies and also makes catching a parachuting crate reliable for humans.
        players = [c for c in self._room_players(room) if c.alive and c.last_position is not None]
        if not players:
            return
        for drop in list(room.supplies.values()):
            if room.supplies.get(drop.supply_id) is not drop:
                continue
            nearest: list[tuple[float, Client]] = []
            crate_position = self._supply_world_position(drop, now)
            for client in players:
                if client.is_bot and drop.kind in {"gold", "crystal"}:
                    continue
                planar = self._horizontal_distance(client.last_position, crate_position)
                if planar <= SUPPLY_PICKUP_RADIUS and abs(client.last_position[1] - crate_position[1]) <= SUPPLY_PICKUP_VERTICAL:
                    nearest.append((planar, client))
            if nearest:
                nearest.sort(key=lambda item: (item[0], item[1].player_id))
                self._collect_supply(room, nearest[0][1], drop, now)

    def _supply_tick(self, room: BattleRoom, now: float) -> None:
        expired = [
            supply_id for supply_id, drop in room.supplies.items()
            if not drop.persistent and now >= drop.expires_at
        ]
        for supply_id in expired:
            room.supplies.pop(supply_id, None)
        if room.round_active:
            self._auto_collect_supplies(room, now)
        # Bots are simulated by one real client. With no humans in the room there
        # is no physics host, so pause timed supply spawning as well.
        has_players = bool(self._room_humans(room))
        if not room.round_active or not has_players:
            if not has_players:
                room.next_regular_supply_at = now + random.uniform(SUPPLY_REGULAR_MIN_SECONDS, SUPPLY_REGULAR_MAX_SECONDS)
            return
        if now >= room.next_regular_supply_at:
            self._spawn_supply(room, random.choice(REGULAR_SUPPLY_KINDS), "timer")
            room.next_regular_supply_at = now + random.uniform(SUPPLY_REGULAR_MIN_SECONDS, SUPPLY_REGULAR_MAX_SECONDS)

    def _perform_self_destruct(self, client: Client) -> None:
        room = self._room_for_client(client)
        if client.build is None or not client.alive or room is None or not room.round_active:
            return
        impact = list(client.last_position) if client.last_position is not None else None
        origin = None
        if impact is not None:
            origin = [impact[0], impact[1] - 2.0, impact[2]]
        self.apply_damage(
            client,
            max(client.hp, client.max_hp) + 1.0,
            client.player_id,
            "self_destruct",
            "suicide",
            origin,
            impact,
        )

    def handle_self_destruct(self, client: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(client, msg)
        if seq is None:
            return
        self._perform_self_destruct(client)
        self._reliable_reply(client, seq, {"type": "ack"})

    def handle_bot_self_destruct(self, host: Client, msg: dict[str, Any]) -> None:
        seq = self._reliable_seq(host, msg)
        if seq is None:
            return
        bot_id = safe_int(msg.get("bot_id"), -1)
        bot = self.clients_by_id.get(bot_id)
        if bot is not None and bot.is_bot and bot.bot_host_id == host.player_id and bot.map_id == host.map_id:
            self._perform_self_destruct(bot)
        self._reliable_reply(host, seq, {"type": "ack"})

    def handle_shot(self, client: Client, msg: dict):
        seq = safe_int(msg.get("seq"), -1)
        if seq >= 0:
            self.send(client.addr, {"type": "ack", "seq": seq})
            if seq in client.reliable_seen:
                return
            client.reliable_seen.append(seq)
        if client.build is None or not client.alive or self._room_for_client(client) is None or not self._room_for_client(client).round_active:
            return
        # Server-side safety: an overturned/sideways tank cannot use any weapon even
        # if a modified client attempts to send shot packets while its muzzle is in terrain.
        if not self._client_can_fire(client):
            return
        ws = weapon_spec(client.build)
        kind = str(ws.get("kind", ""))
        if kind not in ("hitscan", "splash"):
            return
        now = time.monotonic()
        reload_time = max(0.05, float(ws.get("reload", 1.0)))
        if now - client.last_shot_time < reload_time * 0.94:
            return
        origin = vec3(msg.get("origin"))
        end = vec3(msg.get("end"))
        if origin is None or end is None:
            return
        if client.last_position is not None and distance(origin, client.last_position) > 8.5:
            return
        configured_range = float(ws.get("range", 0.0))
        max_range = DISCRETE_WORLD_RAY_LIMIT if configured_range <= 0.0 else max(1.0, configured_range)
        dx, dy, dz = (end[i] - origin[i] for i in range(3))
        length = math.sqrt(dx * dx + dy * dy + dz * dz)
        if length > max_range and length > 0:
            scale = max_range / length
            end = [origin[0] + dx * scale, origin[1] + dy * scale, origin[2] + dz * scale]
        client.last_shot_time = now
        weapon_id = client.build["turret"]
        shot_end = list(end)
        world_blocked = bool(msg.get("world_blocked", False))
        # Never extend a segment that the physics client says ended on WORLD geometry.
        # The old endpoint capture could reach a padded tank volume just behind a wall.
        capture_end = shot_end if world_blocked else self._extended_capture_end(origin, shot_end, weapon_id)
        claimed_target_id = safe_int(msg.get("target_id"), -1)
        direct: Client | None = None
        confirmed_end = list(shot_end)
        if claimed_target_id >= 0:
            direct, confirmed_end = self._claimed_line_hit(client, claimed_target_id, origin, capture_end, weapon_id)
        if direct is None and not world_blocked:
            direct, confirmed_end = self._line_target_hit(client, origin, capture_end, weapon_id)
        if direct is None:
            confirmed_end = shot_end

        self.broadcast({
            "type": "shot",
            "shooter": client.player_id,
            "event_seq": seq,
            "weapon": weapon_id,
            "origin": origin,
            "end": confirmed_end,
            "map": client.map_id,
        }, client.map_id)

        damage = max(0.0, float(ws.get("damage", 0.0))) * self._damage_multiplier(client, now)
        if kind == "hitscan":
            if direct is not None:
                self._broadcast_hit(direct, client, weapon_id, "direct", origin, confirmed_end, damage)
                self.apply_damage(direct, damage, client.player_id, weapon_id, "direct", origin, confirmed_end)
            return

        if direct is not None:
            self._broadcast_hit(direct, client, weapon_id, "direct", origin, confirmed_end, damage)
            self.apply_damage(direct, damage, client.player_id, weapon_id, "direct", origin, confirmed_end)
        radius = max(0.1, float(ws.get("splash_radius", 0.1)))
        splash_factor = max(0.0, float(ws.get("splash_factor", 0.0)))
        # Nearby non-shooter/non-direct targets still come from the physics client,
        # because it is the side that owns the actual map collision and can reject
        # blast paths through walls. Two targets are NEVER optional, however:
        #   1) the shooter (Thunder must be able to hurt itself at point blank);
        #   2) the directly-hit tank (direct impact ALSO creates radial blast damage).
        # v19.1.1 trusted the client list for both and then explicitly excluded the
        # direct victim, which is why self-damage/splash could appear to be absent.
        raw_splash = msg.get("splash_targets", [])
        splash_ids: set[int] = {client.player_id}
        if direct is not None:
            splash_ids.add(direct.player_id)
        if isinstance(raw_splash, list):
            for value in raw_splash[:24]:
                target_id = safe_int(value, -1)
                if target_id > 0:
                    splash_ids.add(target_id)

        for target_id in splash_ids:
            target = self.clients_by_id.get(target_id)
            if target is None:
                continue
            if target.map_id != client.map_id or not target.alive or target.last_position is None:
                continue
            # Distance is measured to the actual oriented hull surface, not the tank
            # pivot. This makes a shell exploding against a nearby wall reliably hurt
            # the shooter and gives a direct victim full-strength center splash.
            dist = self._point_to_hull_distance(target, confirmed_end)
            if dist >= radius:
                continue
            falloff = max(0.0, 1.0 - dist / radius)
            if falloff <= 0.0:
                continue
            splash_damage = damage * splash_factor * falloff
            self._broadcast_hit(target, client, weapon_id, "splash", confirmed_end, target.last_position, splash_damage)
            self.apply_damage(target, splash_damage, client.player_id, weapon_id, "splash", confirmed_end, target.last_position)

    def _ignite(self, target: Client, source: Client, ws: dict[str, float | str], now: float) -> None:
        if not target.alive:
            return
        duration = max(0.1, float(ws.get("afterburn_duration", 0.0)))
        dps = max(0.0, float(ws.get("dps", 0.0)) * float(ws.get("afterburn_dps_factor", 0.0)))
        target.burn_duration = duration
        target.burn_end = now + duration
        target.burn_dps = max(target.burn_dps, dps)
        target.burn_source = source.player_id

    @staticmethod
    def _hull_planar_radius(client: Client) -> float:
        hull_id = str((client.build or {}).get("hull", "wasp"))
        half, _ = HULL_HIT_VOLUMES.get(hull_id, HULL_HIT_VOLUMES["wasp"])
        return math.hypot(half[0], half[2]) * 0.72

    def _point_to_hull_distance(self, target: Client, point: list[float]) -> float:
        """Shortest distance from a world point to the target's oriented hull box.

        Using center-to-center distance made Thunder self-damage unreliable: the
        explosion can be only a metre from the armor while the tank pivot is several
        metres away. This OBB distance also stays correct when the victim is flipped.
        """
        if target.last_position is None or target.build is None:
            return float("inf")
        hull_id = str(target.build.get("hull", "wasp"))
        half, center_y = HULL_HIT_VOLUMES.get(hull_id, HULL_HIT_VOLUMES["wasp"])
        basis = self._rotation_basis(target.state)
        center_offset = self._basis_mul(basis, [0.0, center_y, 0.0])
        center = [target.last_position[i] + center_offset[i] for i in range(3)]
        local = self._basis_transpose_mul(basis, [point[i] - center[i] for i in range(3)])
        outside = [max(abs(local[i]) - half[i], 0.0) for i in range(3)]
        return math.sqrt(sum(v * v for v in outside))

    def _firebird_point_blank_candidate(self, shooter: Client, target: Client, ws: dict[str, float | str]) -> bool:
        if shooter.last_position is None or target.last_position is None or not target.alive:
            return False
        if target.player_id == shooter.player_id or target.map_id != shooter.map_id:
            return False
        contact = self._hull_planar_radius(shooter) + self._hull_planar_radius(target) + 0.80
        if distance(shooter.last_position, target.last_position) > contact:
            return False
        return self._valid_firebird_target(shooter, target, ws, point_blank=True)

    def _valid_firebird_target(self, shooter: Client, target: Client, ws: dict[str, float | str], point_blank: bool = False) -> bool:
        if shooter.last_position is None or target.last_position is None or not target.alive:
            return False
        max_range = max(0.1, float(ws.get("range", 18.0)))
        target_radius = self._hull_planar_radius(target)
        center_distance = distance(shooter.last_position, target.last_position)
        if center_distance > max_range + target_radius:
            return False
        aim_raw = shooter.state.get("aim")
        if not isinstance(aim_raw, list) or len(aim_raw) < 3:
            return False
        aim = normalized([float(aim_raw[i]) for i in range(3)])
        if aim is None:
            return False
        to_target = [target.last_position[i] - shooter.last_position[i] for i in range(3)]
        unit = normalized(to_target)
        if unit is None:
            return False

        # At short range the target occupies a very large angular area. Expand the
        # cone by that apparent radius instead of testing only its center point.
        base_cone = float(ws.get("cone_deg", 26.0)) + 5.0
        apparent = math.degrees(math.asin(min(0.82, target_radius / max(center_distance, 0.25))))
        bonus = apparent + (12.0 if point_blank else 4.0)
        cone = math.radians(min(82.0, base_cone + bonus))
        return dot(aim, unit) >= math.cos(cone)

    def _broadcast_hit(self, target: Client, source: Client, weapon: str, kind: str, origin: list[float], impact: list[float], damage: float) -> None:
        self.broadcast({
            "type": "combat",
            "event": "hit",
            "victim": target.player_id,
            "attacker": source.player_id,
            "weapon": weapon,
            "damage_kind": kind,
            "origin": origin,
            "impact": impact,
            "damage": max(0.0, float(damage)),
            "map": target.map_id,
        }, target.map_id)

    def apply_damage(self, target: Client, amount: float, source_id: int, weapon: str, kind: str, hit_origin: list[float] | None = None, hit_impact: list[float] | None = None) -> None:
        room = self._room_for_client(target)
        if room is None or not room.round_active or not target.alive or amount <= 0.0:
            return
        now = time.monotonic()
        if kind != "suicide" and target.armor_end > now:
            amount *= ARMOR_DAMAGE_MULTIPLIER
        old_hp = target.hp
        actual_damage = min(old_hp, max(0.0, amount))
        target.hp = max(0.0, old_hp - actual_damage)
        source = self.clients_by_id.get(source_id)
        if source is not None and source.player_id != target.player_id and source.map_id == target.map_id and source.authenticated:
            source.round_damage += actual_damage
            source.round_score += max(1, int(round(actual_damage)))
        if target.hp > 0.0:
            return
        target.alive = False
        target.fire_requested = False
        target.state["firing"] = False
        target.burn_end = 0.0
        target.burn_dps = 0.0
        target.burn_source = -1
        delay = max(0.5, float(COMBAT.get("respawn_delay", 3.0)))
        target.respawn_at = time.monotonic() + delay
        # Choose and reserve the next spawn NOW, not at the end of the timer.
        # The client can therefore fly its death camera to exactly the same
        # place where the authoritative respawn will happen.
        self._reserve_spawn(target, self._choose_spawn_index(target))
        suicide = kind == "suicide" and source is not None and source.player_id == target.player_id
        if suicide:
            # Tanki-style self-destruction penalty: remove one kill from the CURRENT
            # battle table. Negative round values are allowed/visible, but lifetime
            # account totals are protected at round settlement below.
            target.round_kills -= 1
        killer = source if source is not None and source.player_id != target.player_id and source.map_id == target.map_id else None
        victim_account = self._account(target)
        victim_rank = _client_rank_info(target)
        killer_account = self._account(killer) if killer is not None else None
        killer_rank = _client_rank_info(killer)
        if killer is not None:
            killer.round_kills += 1
            killer.round_score += 100
            # Rank progression is live and action-based. Each confirmed kill grants
            # a small random score immediately; no round-end wait is involved.
            if killer_account is not None and XP_PER_KILL_MAX > 0:
                xp_gain = random.randint(XP_PER_KILL_MIN, XP_PER_KILL_MAX)
                killer_account["xp"] = int(killer_account.get("xp", 0)) + xp_gain
                killer.round_xp += xp_gain
                _save_accounts()
                self._send_profile(killer)
                killer_rank = _rank_info(int(killer_account.get("xp", 0)))
            # The battle fund grows in small random packets. Gold is tied to crossing
            # EVERY multiple of GOLD_FUND_STEP, not to equality with 20 and not to a
            # one-shot boolean. This also handles jumps such as 19 -> 21 or 39 -> 42.
            old_fund = room.battle_fund
            room.battle_fund = old_fund + random.randint(1, 3)
            self._spawn_supply(room, "crystal", "battle_fund")
            for gold_threshold in _fund_thresholds_crossed(old_fund, room.battle_fund):
                self._spawn_supply(room, "gold", f"gold_fund_threshold_{gold_threshold}")
        self.broadcast({
            "type": "combat", "event": "destroyed", "victim": target.player_id,
            "victim_login": target.login, "victim_rank_index": int(victim_rank.get("index", 0)),
            "victim_rank_name": str(victim_rank.get("name", "")),
            "killer": source_id,
            "killer_login": killer.login if killer is not None else "",
            "killer_rank_index": int(killer_rank.get("index", 0)),
            "killer_rank_name": str(killer_rank.get("name", "")),
            "weapon": weapon, "damage_kind": kind,
            "origin": hit_origin if hit_origin is not None else (source.last_position if source is not None else None),
            "impact": hit_impact if hit_impact is not None else target.last_position,
            "respawn_delay": delay, "respawn_spawn_index": target.spawn_index, "map": target.map_id,
        }, target.map_id)
        self.broadcast_match(room)
        print(f"[destroyed] room={target.map_id} victim=#{target.player_id} killer=#{source_id} weapon={weapon} kind={kind}")
        if killer is not None and killer.round_kills >= room.kill_limit:
            self._finish_round(killer)

    def _combat_tick(self, now: float, dt: float) -> None:
        for client in list(self.clients_by_id.values()):
            if client.build is None:
                continue
            room = self._room_for_client(client)
            if room is None or not room.round_active:
                client.fire_requested = False
                client.state["firing"] = False
                continue
            if not client.alive:
                if client.respawn_at > 0.0 and now >= client.respawn_at:
                    self._respawn(client)
                continue

            ws = weapon_spec(client.build)
            if str(ws.get("kind", "")) == "continuous":
                actual_firing = client.fire_requested and client.fuel > 0.01 and client.last_position is not None
                if actual_firing:
                    client.fuel = max(0.0, client.fuel - float(ws.get("fuel_burn_per_sec", 0.0)) * dt)
                    client.last_fire_active = now
                    client.state["firing"] = client.fuel > 0.0
                    dps = max(0.0, float(ws.get("dps", 0.0))) * self._damage_multiplier(client, now)
                    # Static map collision exists on the physics client, not in this
                    # lightweight Python server. Therefore ONLY the client's LOS-tested
                    # target set is eligible; inventing point-blank candidates here could
                    # burn a tank through a thin wall. Range/cone are still revalidated.
                    candidate_ids = set(client.fire_targets)
                    for target_id in candidate_ids:
                        target = self.clients_by_id.get(target_id)
                        if target is None or target.map_id != client.map_id:
                            continue
                        point_blank = self._firebird_point_blank_candidate(client, target, ws)
                        if not self._valid_firebird_target(client, target, ws, point_blank=point_blank):
                            continue
                        self.apply_damage(target, dps * dt, client.player_id, client.build["turret"], "firebird")
                        if target.alive:
                            self._ignite(target, client, ws, now)
                else:
                    client.state["firing"] = False
                    regen_delay = max(0.0, float(ws.get("fuel_regen_delay", 0.0)))
                    if not client.fire_requested and now - client.last_fire_active >= regen_delay:
                        client.fuel = min(client.fuel_max, client.fuel + float(ws.get("fuel_regen_per_sec", 0.0)) * dt)
            else:
                client.state["firing"] = False

            if client.alive and client.burn_end > now and client.burn_duration > 0.0 and client.burn_dps > 0.0:
                remaining = max(0.0, client.burn_end - now)
                intensity = min(1.0, remaining / client.burn_duration)
                burn_source = self.clients_by_id.get(client.burn_source)
                burn_multiplier = self._damage_multiplier(burn_source, now)
                self.apply_damage(client, client.burn_dps * burn_multiplier * intensity * dt, client.burn_source, "firebird", "afterburn")
            elif client.burn_end <= now:
                client.burn_end = 0.0
                client.burn_dps = 0.0
                client.burn_source = -1

    def _respawn(self, client: Client) -> None:
        if client.build is None:
            return
        # Normal death respawns already have a server-reserved spawn chosen at the
        # moment of destruction. Round-start/manual respawns still choose a fresh one.
        planned_spawn = client.spawn_index if client.respawn_at > 0.0 and client.spawn_index >= 0 else self._choose_spawn_index(client)
        self._reserve_spawn(client, planned_spawn)
        client.state = {
            "turret": 0.0,
            "speed": 0.0,
            "left_track": 0.0,
            "right_track": 0.0,
            "lin_vel": [0.0, 0.0, 0.0],
            "ang_vel": [0.0, 0.0, 0.0],
            "firing": False,
        }
        client.last_position = None
        client.last_position_time = 0.0
        self._reset_combat(client)
        if client.is_bot:
            self._send_bot_control(client, "respawn")
        else:
            self.send(client.addr, {
                "type": "respawn",
                "spawn_index": client.spawn_index,
                "combat": self.combat_payload(client, time.monotonic()),
                "map": client.map_id,
            })
        print(f"[respawn] room={client.map_id} #{client.player_id} zone={client.spawn_index}")

    def combat_payload(self, client: Client, now: float) -> dict[str, Any]:
        burn_time = max(0.0, client.burn_end - now) if client.alive else 0.0
        burn = min(1.0, burn_time / client.burn_duration) if client.burn_duration > 0.0 else 0.0
        return {
            "hp": round(client.hp, 2),
            "max_hp": round(client.max_hp, 2),
            "alive": client.alive,
            "fuel": round(client.fuel, 2),
            "fuel_max": round(client.fuel_max, 2),
            "burn": round(burn, 3),
            "burn_time": round(burn_time, 2),
            "buffs": self._buff_remaining(client, now),
        }

    def snapshot_payload(self, map_id: str):
        map_id = str(map_id or "arena")
        room = self._room_from_map(map_id)
        now = time.monotonic()
        players = []
        for client in self.clients_by_id.values():
            if client.map_id != map_id or client.build is None:
                continue
            state = client.state
            if "p" not in state:
                continue
            players.append({
                "id": client.player_id,
                "login": client.login,
                "is_bot": client.is_bot,
                "bot_host_id": client.bot_host_id,
                "spawn_index": client.spawn_index,
                "kills": client.round_kills,
                "score": client.round_score,
                "build": client.build,
                "p": state["p"],
                "yaw": state.get("yaw", 0.0),
                "rot": state.get("rot"),
                "lin_vel": state.get("lin_vel", [0.0, 0.0, 0.0]),
                "ang_vel": state.get("ang_vel", [0.0, 0.0, 0.0]),
                "turret": state.get("turret", 0.0),
                "speed": state.get("speed", 0.0),
                "left_track": state.get("left_track", state.get("speed", 0.0) / 8.0),
                "right_track": state.get("right_track", state.get("speed", 0.0) / 8.0),
                "firing": state.get("firing", False),
                **self.combat_payload(client, now),
            })
        return {
            "type": "snapshot",
            "server_time": round(now, 3),
            "map": map_id,
            "players": players,
            "supplies": self._supply_snapshot(room, now) if room is not None else [],
        }

    def send_snapshot(self, client: Client):
        self.send(client.addr, self.snapshot_payload(client.map_id))

    def send(self, addr, payload):
        if not self.transport:
            return
        try:
            self.transport.sendto(json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8"), addr)
        except OSError:
            pass

    def broadcast(self, payload, map_id: str | None = None):
        if not self.transport:
            return
        blob = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        for client in list(self.clients_by_id.values()):
            if client.is_bot:
                continue
            if map_id is not None and client.map_id != map_id:
                continue
            try:
                self.transport.sendto(blob, client.addr)
            except OSError:
                pass

    def broadcast_global(self, payload: dict[str, Any]) -> None:
        if not self.transport:
            return
        blob = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        for client in list(self.clients_by_id.values()):
            if client.is_bot or not client.authenticated:
                continue
            try:
                self.transport.sendto(blob, client.addr)
            except OSError:
                pass

    def drop(self, client: Client, reason: str):
        old_map = client.map_id
        old_room = self._room_for_client(client)
        drop_account = self._account(client)
        drop_rank = _rank_info(int(drop_account.get("xp", 0))) if drop_account is not None else {"index": 0, "name": ""}
        self.clients_by_addr.pop(client.addr, None)
        self.clients_by_id.pop(client.player_id, None)
        if client.account_key and self.active_accounts.get(client.account_key) == client.player_id:
            self.active_accounts.pop(client.account_key, None)
        print(f"[leave] room={old_map} #{client.player_id} {client.login!r}: {reason}")
        if old_room is not None:
            self.broadcast({
                "type": "combat", "event": "player_left", "player": client.player_id,
                "login": client.login, "rank_index": int(drop_rank.get("index", 0)),
                "rank_name": str(drop_rank.get("name", "")), "map": old_map,
            }, old_map)
            self._sync_bot_hosts(old_room)
            self.broadcast_match(old_room)
            self.broadcast_battles()

    async def _ticker(self):
        last_snapshot = 0.0
        while True:
            await asyncio.sleep(0.02)
            now = time.monotonic()
            dt = min(0.10, max(0.001, now - self._last_combat_time))
            self._last_combat_time = now
            for client in list(self.clients_by_id.values()):
                if client.is_bot:
                    continue
                if now - client.last_seen > self.timeout:
                    self.drop(client, "timeout")
            for room in list(self.battles.values()):
                if not room.round_active and room.round_restart_at > 0.0 and now >= room.round_restart_at:
                    self._start_new_round(room)
            self._combat_tick(now, dt)
            for room in list(self.battles.values()):
                self._supply_tick(room, now)
            if now - last_snapshot >= self.snapshot_period:
                last_snapshot = now
                for room in list(self.battles.values()):
                    # Re-assert bot authority until the physics host has sent at least
                    # one state packet. This makes a lost UDP bot_control assignment
                    # self-healing without continuously spamming established bots.
                    self._sync_bot_hosts(room)
                    if self._room_players(room):
                        self.broadcast(self.snapshot_payload(room.map_id), room.map_id)


async def handle_asset_http(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, protocol: TankiProtocol) -> None:
    try:
        first = await asyncio.wait_for(reader.readline(), timeout=3.0)
        line = first.decode("latin-1", "replace").strip()
        parts = line.split()
        if len(parts) != 3 or parts[0] not in {"GET", "POST"}:
            await _http_reply(writer, 405, b"method not allowed", "text/plain; charset=utf-8")
            return
        method = parts[0]
        headers: dict[str, str] = {}
        while True:
            header = await asyncio.wait_for(reader.readline(), timeout=3.0)
            if header in (b"\r\n", b"\n", b""):
                break
            decoded = header.decode("latin-1", "replace").strip()
            if ":" in decoded:
                key, value = decoded.split(":", 1)
                headers[key.strip().lower()] = value.strip()
        path = urlsplit(parts[1]).path

        if method == "POST":
            if not path.startswith("/maps/"):
                await _http_reply(writer, 404, b"not found", "text/plain; charset=utf-8")
                return
            map_key = path[len("/maps/"):].strip().lower()
            if not SAFE_MAP_ID.fullmatch(map_key):
                await _http_reply(writer, 400, b"invalid map id", "text/plain; charset=utf-8")
                return
            token = headers.get("x-tanki-upload-token", "")
            uploader = next((
                client for client in protocol.clients_by_id.values()
                if client.authenticated and token and hmac.compare_digest(client.map_upload_token, token)
            ), None)
            if uploader is None:
                await _http_reply(writer, 403, b"invalid upload token", "text/plain; charset=utf-8")
                return
            try:
                content_length = int(headers.get("content-length", "0"))
            except ValueError:
                content_length = 0
            if content_length <= 0 or content_length > MAX_MAP_SCENE_BYTES:
                await _http_reply(writer, 413, b"invalid map size", "text/plain; charset=utf-8")
                return
            body = await asyncio.wait_for(reader.readexactly(content_length), timeout=8.0)
            ok, reason = _validate_uploaded_map(map_key, body)
            if not ok:
                await _http_reply(writer, 400, reason.encode("utf-8", "replace"), "text/plain; charset=utf-8")
                return
            SERVER_MAP_ROOT.mkdir(parents=True, exist_ok=True)
            target = SERVER_MAP_ROOT / f"{map_key}.tscn"
            temp = target.with_suffix(".tscn.tmp")
            temp.write_bytes(body)
            temp.replace(target)
            refresh_battle_maps()
            protocol.broadcast_battles()
            payload = json.dumps({
                "ok": True,
                "map": _public_map_asset(map_key),
                "uploader": uploader.login,
            }, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            print(f"[maps] uploaded id={map_key!r} by={uploader.login!r} bytes={len(body)}")
            await _http_reply(writer, 200, payload, "application/json; charset=utf-8", extra={"Cache-Control": "no-store"})
            return

        if path == "/catalog.json":
            payload = json.dumps(public_catalog(), ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            await _http_reply(writer, 200, payload, "application/json; charset=utf-8")
            return
        if path.startswith("/maps/"):
            map_key = path[len("/maps/"):].strip().lower()
            refresh_battle_maps()
            info = BATTLE_MAPS.get(map_key)
            if not SAFE_MAP_ID.fullmatch(map_key) or not isinstance(info, dict):
                await _http_reply(writer, 404, b"map not found", "text/plain; charset=utf-8")
                return
            scene_path = info.get("path")
            if not isinstance(scene_path, Path) or not scene_path.is_file():
                await _http_reply(writer, 404, b"map scene not found", "text/plain; charset=utf-8")
                return
            body = scene_path.read_bytes()
            await _http_reply(writer, 200, body, "application/x-godot-scene; charset=utf-8", extra={"ETag": str(info.get("sha256", ""))})
            return
        if path.startswith("/map-previews/"):
            map_key = path[len("/map-previews/"):].strip().lower()
            info = BATTLE_MAPS.get(map_key)
            preview_path = info.get("preview_path") if isinstance(info, dict) else None
            if not SAFE_MAP_ID.fullmatch(map_key) or not isinstance(preview_path, Path) or not preview_path.is_file():
                await _http_reply(writer, 404, b"map preview not found", "text/plain; charset=utf-8")
                return
            body = preview_path.read_bytes()
            fmt = str(info.get("preview_format", "png"))
            mime = {"png":"image/png", "jpg":"image/jpeg", "jpeg":"image/jpeg", "webp":"image/webp"}.get(fmt, "application/octet-stream")
            await _http_reply(writer, 200, body, mime, extra={"ETag": str(info.get("preview_sha256", ""))})
            return
        if path.startswith("/paints/"):
            paint_id = path[len("/paints/"):]
            if not SAFE_PAINT_ID.fullmatch(paint_id) or paint_id not in PAINTS:
                await _http_reply(writer, 404, b"paint not found", "text/plain; charset=utf-8")
                return
            paint = PAINTS[paint_id]
            body = Path(paint["path"]).read_bytes()
            mime = {
                "png":"image/png", "jpg":"image/jpeg", "jpeg":"image/jpeg", "webp":"image/webp"
            }.get(str(paint["format"]), "application/octet-stream")
            await _http_reply(writer, 200, body, mime, extra={"ETag": str(paint["sha256"])})
            return
        if path.startswith("/paint-previews/"):
            paint_id = path[len("/paint-previews/"):]
            if not SAFE_PAINT_ID.fullmatch(paint_id) or paint_id not in PAINTS:
                await _http_reply(writer, 404, b"paint preview not found", "text/plain; charset=utf-8")
                return
            paint = PAINTS[paint_id]
            preview_path = paint.get("preview_path")
            if preview_path is None or not Path(preview_path).is_file():
                await _http_reply(writer, 404, b"paint preview not found", "text/plain; charset=utf-8")
                return
            body = Path(preview_path).read_bytes()
            await _http_reply(writer, 200, body, "image/png", extra={"ETag": str(paint.get("preview_sha256", ""))})
            return
        await _http_reply(writer, 404, b"not found", "text/plain; charset=utf-8")
    except asyncio.IncompleteReadError:
        try:
            await _http_reply(writer, 400, b"incomplete request body", "text/plain; charset=utf-8")
        except Exception:
            pass
    except Exception as exc:
        try:
            await _http_reply(writer, 500, str(exc).encode("utf-8", "replace"), "text/plain; charset=utf-8")
        except Exception:
            pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def _http_reply(writer: asyncio.StreamWriter, status: int, body: bytes, content_type: str, extra: dict[str, str] | None = None) -> None:
    reason = {200:"OK", 400:"Bad Request", 403:"Forbidden", 404:"Not Found", 405:"Method Not Allowed", 413:"Payload Too Large", 500:"Internal Server Error"}.get(status, "OK")
    headers = {
        "Content-Type": content_type,
        "Content-Length": str(len(body)),
        "Connection": "close",
        "Cache-Control": "public, max-age=3600",
    }
    if extra:
        headers.update(extra)
    head = f"HTTP/1.1 {status} {reason}\r\n" + "".join(f"{k}: {v}\r\n" for k, v in headers.items()) + "\r\n"
    writer.write(head.encode("latin-1") + body)
    await writer.drain()


async def amain(args):
    loop = asyncio.get_running_loop()
    transport, protocol = await loop.create_datagram_endpoint(
        lambda: TankiProtocol(args.timeout, args.snapshot_hz, args.asset_port),
        local_addr=(args.host, args.port),
    )
    http_server = await asyncio.start_server(lambda r, w: handle_asset_http(r, w, protocol), host=args.host, port=args.asset_port)
    print(f"[assets] HTTP listening on {args.host}:{args.asset_port} paints={len(PAINTS)} maps={len(BATTLE_MAPS)}")
    try:
        await asyncio.Future()
    finally:
        http_server.close()
        await http_server.wait_closed()
        transport.close()


def main():
    parser = argparse.ArgumentParser(description="Tanki 2.0 Godot authoritative account/economy/combat server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=9100)
    parser.add_argument("--timeout", type=float, default=8.0)
    parser.add_argument("--snapshot-hz", type=float, default=20.0)
    parser.add_argument("--asset-port", type=int, default=9101, help="TCP HTTP port used to distribute server-authoritative paints")
    args = parser.parse_args()
    try:
        asyncio.run(amain(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
