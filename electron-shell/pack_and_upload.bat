@echo off
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
