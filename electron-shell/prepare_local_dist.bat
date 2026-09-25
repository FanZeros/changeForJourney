@echo off
setlocal
cd /d "%~dp0\.."
python electron-shell\prepare_local_dist.py
if errorlevel 1 pause
endlocal
