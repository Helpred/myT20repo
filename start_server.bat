@echo off
cd /d "%~dp0server"
python server.py --host 0.0.0.0 --port 9100
pause
