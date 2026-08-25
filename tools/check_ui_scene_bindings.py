#!/usr/bin/env python3
"""Lightweight consistency check for the editor-facing UI scene node paths."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "client" / "scenes" / "ui"

CHECKS = {
    "auth_screen.tscn": [
        "Center/Window/Margin/Box/Login", "Center/Window/Margin/Box/Password",
        "Center/Window/Margin/Box/Repeat", "Center/Window/Margin/Box/Endpoint/Host",
        "Center/Window/Margin/Box/Endpoint/Port", "Center/Window/Margin/Box/Status",
    ],
    "lobby_screen.tscn": [
        "Margin/Shell/Main/Left/LeftBox/BattleScroll/BattleList",
        "Margin/Shell/Main/Right/Info/JoinBattle", "Margin/Shell/Chat/ChatBox/ChatLog",
        "Margin/Shell/Chat/ChatBox/SendRow/ChatInput",
    ],
    "garage_screen.tscn": [
        "Margin/Shell/Main/PreviewPanel/PreviewContainer",
        "Margin/Shell/Main/InventoryPanel/Inventory/Scroll/GarageGrid",
    ],
    "battle_hud.tscn": [
        "HudCluster/TopRow/KillFrame/KillProgress", "HudCluster/FundPanel/Fund",
        "Supplies/Box/SuppliesText", "Hint",
    ],
    "profile_strip.tscn": [
        "Cluster/RankIcon", "Cluster/RankName", "Cluster/RankProgress",
        "Cluster/RankProgress/RankProgressText", "Cluster/CrystalPanel/Row/Amount",
    ],
}


def node_paths(path: Path) -> set[str]:
    result: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("[node "):
            continue
        name = re.search(r'name="([^"]+)"', line)
        parent = re.search(r'parent="([^"]+)"', line)
        if not name:
            continue
        if not parent or parent.group(1) == ".":
            result.add(name.group(1))
        else:
            result.add(parent.group(1) + "/" + name.group(1))
    return result


def main() -> int:
    errors: list[str] = []
    for filename, wanted in CHECKS.items():
        path = UI / filename
        if not path.is_file():
            errors.append(f"missing scene: {path}")
            continue
        available = node_paths(path)
        for node_path in wanted:
            if node_path not in available:
                errors.append(f"{filename}: missing {node_path}")
    if errors:
        print("UI scene binding check FAILED")
        for error in errors:
            print(" -", error)
        return 1
    print("OK: editor UI scenes and required runtime node paths are present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
