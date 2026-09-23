@echo off
title Movement Shooter (Godot)
rem Runs the game with the Godot you downloaded. Edit GODOT below if you move it.
set GODOT=%USERPROFILE%\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%
  echo Open this folder in Godot 4.6 and press F5 instead, or fix the GODOT line in play.bat.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
