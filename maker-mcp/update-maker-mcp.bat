@echo off
REM 本机一键：更新 Maker MCP + 可选安装本地 Runtime
REM 用法：
REM   双击本文件                     = 只升级 MCP
REM   update-maker-mcp.bat --preview  = 再装本地 Runtime
REM   update-maker-mcp.bat --start    = 升级后直接开预览窗口
setlocal
cd /d "%~dp0\.."
set PY=
where python >nul 2>&1
if %errorlevel%==0 set PY=python
if not defined PY (
  where python3 >nul 2>&1
  if %errorlevel%==0 set PY=python3
)
if not defined PY (
  echo 找不到 python。请先安装 Python 3 并勾选 Add to PATH。
  pause
  exit /b 1
)
%PY% maker-mcp\update-maker-mcp.py %*
set ERR=%errorlevel%
echo.
if %ERR%==0 (
  echo 完成。请把上面最后几行贴回 Agent。
) else (
  echo 失败 exit=%ERR%。请把从 ==> 开始的全文贴回 Agent。
)
pause
endlocal
exit /b %ERR%
