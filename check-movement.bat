@echo off
title Movement Shooter (Godot) - movement check
rem Replays movement recorded from the web game and checks the Godot port matches every tick.
set GODOT=%USERPROFILE%\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe
"%GODOT%" --headless --path "%~dp0." --script res://tests/compare.gd
pause
