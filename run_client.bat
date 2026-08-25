@echo off
set ROOT=%~dp0
if not "%GODOT_EXE%"=="" goto run
where godot4 >nul 2>nul && set GODOT_EXE=godot4 && goto run
where godot >nul 2>nul && set GODOT_EXE=godot && goto run
echo Godot was not found. Set GODOT_EXE to your Godot 4 executable or open client\project.godot manually.
pause
exit /b 1
:run
"%GODOT_EXE%" --path "%ROOT%client" -- --server=127.0.0.1 --port=9100
