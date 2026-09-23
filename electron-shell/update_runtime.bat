@echo off
REM 本机一键：拉最新 dist-snapshot → 打补丁 → 打 Windows 离线包
REM 前提：本机已 clone 仓库，有 Python3；无需 Maker 环境。
setlocal
cd /d "%~dp0"
where python >nul 2>&1
if %errorlevel%==0 (
  python pack_release.py --upload %*
  goto :done
)
where python3 >nul 2>&1
if %errorlevel%==0 (
  python3 pack_release.py --upload %*
  goto :done
)
echo 找不到 python。请先安装 Python 3 并勾选 Add to PATH。
pause
exit /b 1
:done
if errorlevel 1 pause
endlocal
