@echo off
REM One-click: update Maker MCP (+ optional local Runtime)
REM   double-click              = upgrade MCP only
REM   update-maker-mcp.bat --preview
REM   update-maker-mcp.bat --start
setlocal
cd /d "%~dp0\.."
chcp 65001 >nul
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
set PY=
where python >nul 2>&1
if %errorlevel%==0 set PY=python
if not defined PY (
  where python3 >nul 2>&1
  if %errorlevel%==0 set PY=python3
)
if not defined PY (
  echo Python not found. Install Python 3 and check Add to PATH.
  pause
  exit /b 1
)
%PY% maker-mcp\update-maker-mcp.py %*
set ERR=%errorlevel%
echo.
if %ERR%==0 (
  echo DONE. Paste the last lines back to the Agent.
) else (
  echo FAILED exit=%ERR%. Paste from "==>" to the end back to the Agent.
)
pause
endlocal
exit /b %ERR%
