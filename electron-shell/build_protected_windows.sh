#!/usr/bin/env bash
# 终焉之门 · --protect 受保护打包（Linux/macOS 版，与 build_protected_windows.bat 等价）
# 依赖：luaparser（python venv）；npx。详见 electron-shell/README.md §「--protect 受保护打包」。
set -euo pipefail
cd "$(dirname "$0")/.."
PROTECT_WS="$PWD/.tmp/protected-workspace"
PY="${PYTHON:-python3}"

echo "[1/4] 物化混淆工作区 ..."
"$PY" electron-shell/protect_build.py --source-root "$PWD" --workspace-root "$PROTECT_WS"

echo "[2/4] 官方 preview prepare（Build 混淆工作区）..."
npx -y --package @taptap/maker@0.0.34 taptap-maker preview prepare --target-dir "$PROTECT_WS" --json

echo "[3/4] 校验 + 打补丁生成 game/（基准=混淆工作区）..."
"$PY" electron-shell/prepare_local_dist.py --scripts-root "$PROTECT_WS/scripts"

echo "[4/4] Electron 打包 ..."
"$PY" electron-shell/pack_release.py --prepare-dist --protect-scripts-root "$PROTECT_WS/scripts"

echo "PROTECTED_BUILD_OK"
