@echo off
start "Tanki2 Server" cmd /k "cd /d %~dp0server && python server.py --host 0.0.0.0 --port 9100"
timeout /t 1 /nobreak >nul
call "%~dp0run_client.bat"
