@echo off
rem Starts Earth Capture. Run install.ps1 once first.
cd /d "%~dp0"
if not exist ".venv\Scripts\pythonw.exe" (
  echo Earth Capture is not installed yet. Run:  powershell -ExecutionPolicy Bypass -File install.ps1
  pause
  exit /b 1
)
start "" ".venv\Scripts\pythonw.exe" -m terrabound_earth
