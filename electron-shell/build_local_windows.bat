@echo off
setlocal
cd /d "%~dp0\.."
call npx -y --package @taptap/maker@0.0.34 taptap-maker preview prepare --target-dir "%CD%" --json
if errorlevel 1 goto :fail
python electron-shell\prepare_local_dist.py
if errorlevel 1 goto :fail
python electron-shell\pack_release.py --prepare-dist
if errorlevel 1 goto :fail
echo LOCAL_BUILD_OK
goto :done
:fail
echo LOCAL_BUILD_FAILED
pause
exit /b 1
:done
endlocal
