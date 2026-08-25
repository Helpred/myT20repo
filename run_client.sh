#!/usr/bin/env bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT_BIN="${GODOT_EXE:-}"
if [ -z "$GODOT_BIN" ]; then
  if command -v godot4 >/dev/null 2>&1; then GODOT_BIN=godot4; elif command -v godot >/dev/null 2>&1; then GODOT_BIN=godot; else
    echo "Godot 4 not found. Set GODOT_EXE or open client/project.godot manually." >&2; exit 1
  fi
fi
exec "$GODOT_BIN" --path "$ROOT/client" -- --server=127.0.0.1 --port=9100
