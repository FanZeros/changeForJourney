#!/usr/bin/env bash
# 本机一键：更新 Maker MCP + 可选安装本地 Runtime
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if command -v python3 >/dev/null 2>&1; then
  exec python3 maker-mcp/update-maker-mcp.py "$@"
elif command -v python >/dev/null 2>&1; then
  exec python maker-mcp/update-maker-mcp.py "$@"
else
  echo "找不到 python3" >&2
  exit 1
fi
