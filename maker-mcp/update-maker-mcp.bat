@echo off
REM One-click: update Maker MCP (+ optional local Runtime)
REM   double-click              = --start, open window, skip Tap QR login
REM   update-maker-mcp.bat --preview   = install Runtime only
REM   update-maker-mcp.bat --verify    = check MCP only
REM   update-maker-mcp.bat --log       = show update and Runtime logs (also works with --preview / --start)
setlocal
echo Double-click opens the local window and skips Tap QR login. Not a cloud build.
echo Leave this window open. Pass --log to display detailed logs.
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
  echo DONE.
) else (
  echo FAILED exit=%ERR%. Run again with --log for details.
)
pause
endlocal
exit /b %ERR%
