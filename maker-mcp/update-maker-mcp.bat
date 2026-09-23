@echo off
REM 本机一键：更新 Maker MCP + 可选安装本地 Runtime
REM 用法：
REM   双击本文件                     = 只升级 MCP
REM   update-maker-mcp.bat --preview  = 再装本地 Runtime
REM   update-maker-mcp.bat --start    = 升级后直接开预览窗口
setlocal
cd /d "%~dp0\.."
where python >nul 2>&1
if %errorlevel%==0 (
  python maker-mcp\update-maker-mcp.py %*
  goto :done
)
where python3 >nul 2>&1
if %errorlevel%==0 (
  python3 maker-mcp\update-maker-mcp.py %*
  goto :done
)
echo 找不到 python。请先安装 Python 3 并勾选 Add to PATH。
pause
exit /b 1
:done
if errorlevel 1 pause
endlocal
