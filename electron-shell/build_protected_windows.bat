@echo off
REM 终焉之门 · --protect 受保护打包（L1 混淆 → 官方 Build → Electron 打包）
REM 依赖：Python venv 里装好 luaparser（pip install luaparser）；npx 可用。
REM 详见 electron-shell/README.md §「--protect 受保护打包」。
setlocal
cd /d "%~dp0\.."
set PROTECT_WS=%CD%\.tmp\protected-workspace

echo [0/4] 依赖预检（luaparser/antlr4 必须装进下面这个解释器）...
python -c "import sys; print('  python =', sys.executable)"
python -c "import luaparser, antlr4" >nul 2>&1
if errorlevel 1 (
    echo.
    echo [预检失败] 上面的解释器缺 luaparser 或 antlr4。
    echo   常见原因：pip 与 python 不是同一个解释器（PATH 里有多个 Python）。
    echo   修复：python -m pip install luaparser lupa
    echo   （务必用 python -m pip，别直接敲 pip）
    goto :fail
)
echo   依赖 OK

echo [1/4] 物化混淆工作区 ...
python electron-shell\protect_build.py --source-root "%CD%" --workspace-root "%PROTECT_WS%"
if errorlevel 1 goto :fail

echo [2/4] 官方 preview prepare（Build 混淆工作区）...
call npx -y --package @taptap/maker@0.0.34 taptap-maker preview prepare --target-dir "%PROTECT_WS%" --json
if errorlevel 1 goto :fail

echo [3/4] 校验 + 打补丁生成 game/（基准=混淆工作区）...
python electron-shell\prepare_local_dist.py --scripts-root "%PROTECT_WS%\scripts"
if errorlevel 1 goto :fail

echo [4/4] Electron 打包 ...
python electron-shell\pack_release.py --prepare-dist --protect-scripts-root "%PROTECT_WS%\scripts"
if errorlevel 1 goto :fail

echo PROTECTED_BUILD_OK
goto :done
:fail
echo PROTECTED_BUILD_FAILED
pause
exit /b 1
:done
endlocal
