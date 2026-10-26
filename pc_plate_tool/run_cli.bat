@echo off
rem Plate recognition CLI launcher (uses bundled venv)
setlocal
"%~dp0.venv\Scripts\python.exe" "%~dp0plate_cli.py" %*
endlocal
