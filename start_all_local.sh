#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
python3 "$ROOT/server/server.py" --host 0.0.0.0 --port 9100 &
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
sleep 0.6
"$ROOT/run_client.sh"
