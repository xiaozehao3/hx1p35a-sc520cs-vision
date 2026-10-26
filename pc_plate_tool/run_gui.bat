@echo off
rem Plate recognition GUI launcher (uses bundled venv)
setlocal
"%~dp0.venv\Scripts\pythonw.exe" "%~dp0plate_gui.py"
endlocal
