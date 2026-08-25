#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/server"
exec python3 server.py --host 0.0.0.0 --port 9100
