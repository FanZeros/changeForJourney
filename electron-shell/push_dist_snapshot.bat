@echo off
REM 云端/本机：把仓库根 dist/ 分片上传到 GitHub Release tag=dist-snapshot
REM 沙箱弱网请反复双击（幂等断点续传，单次最多 80 秒）
setlocal
cd /d "%~dp0"
where python >nul 2>&1
if %errorlevel%==0 (
  python snapshot.py --max-seconds 80 --proxy http://127.0.0.1:1080 %*
  goto :done
)
where python3 >nul 2>&1
if %errorlevel%==0 (
  python3 snapshot.py --max-seconds 80 --proxy http://127.0.0.1:1080 %*
  goto :done
)
echo 找不到 python。
pause
exit /b 1
:done
if errorlevel 1 pause
endlocal
