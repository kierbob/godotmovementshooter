@echo off
title Movement Shooter (Godot)
rem Runs the game with the Godot you downloaded. Edit GODOT below if you move it.
rem In a git clone (GitHub Desktop or git clone), it pulls the latest version first: only the
rem changed files come down, and Godot only re-imports those.
set GODOT=%USERPROFILE%\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe
if exist "%~dp0.git" (
  where git >nul 2>nul
  if not errorlevel 1 (
    echo Getting the latest version...
    git -C "%~dp0." pull --ff-only
    if errorlevel 1 echo Couldn't update ^(no internet, or local changes in the way^). Starting the version you have.
  )
)
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%
  echo Open this folder in Godot 4.6 and press F5 instead, or fix the GODOT line in play.bat.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
