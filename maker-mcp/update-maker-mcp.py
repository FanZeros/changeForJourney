#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""一键更新 TapTap Maker MCP + 本机 Runtime（Windows / macOS / Linux）

官方口径（@taptap/maker 0.0.34）：
  - 客户端单机游戏：本机 Runtime 直读项目目录，不提交、不上传、不远端构建
  - 改了服务端：仍需远端构建
  - Agent 里说「更新 Maker MCP」= 跑本脚本

用法：
  python tools/update-maker-mcp.py              # 升级 MCP 并写入本机 IDE 配置
  python tools/update-maker-mcp.py --preview    # 再装本地 Runtime（需已绑定 Maker 项目）
  python tools/update-maker-mcp.py --start      # 升级后启动本地预览窗口
  python tools/update-maker-mcp.py --verify     # 只校验，不改配置

双击：
  Windows: tools/update-maker-mcp.bat
  macOS/Linux: tools/update-maker-mcp.sh
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

MAKER_PKG = "@taptap/maker"
MAKER_VER = "0.0.34"
# 本文件在 <repo>/maker-mcp/，仓库根是上一级
ROOT = Path(__file__).resolve().parent.parent


def log(msg: str) -> None:
    print(msg, flush=True)


def die(msg: str, code: int = 1) -> None:
    print("ERROR: " + msg, file=sys.stderr, flush=True)
    sys.exit(code)


def which_node() -> str:
    node = shutil.which("node")
    if not node:
        die("找不到 node。请先安装 Node.js >= 18：https://nodejs.org/")
    return node


def which_npx() -> str:
    npx = shutil.which("npx")
    if not npx:
        die("找不到 npx（应随 Node.js 安装，并加入 PATH）")
    return npx


def check_node() -> None:
    node = which_node()
    out = subprocess.check_output(
        [node, "-v"], text=True, encoding="utf-8", errors="replace"
    ).strip().lstrip("v")
    major = int(out.split(".")[0])
    log("Node %s  (%s)" % (out, node))
    if major < 18:
        die("需要 Node.js >= 18，当前 %s" % out)
    log("npx     (%s)" % which_npx())


def maker_argv(args: list[str], json_out: bool) -> list[str]:
    inner = [
        which_npx(), "-y", "--package", "%s@%s" % (MAKER_PKG, MAKER_VER),
        "taptap-maker",
    ] + list(args)
    if json_out and "--json" not in args:
        inner.append("--json")
    # Windows 上 npx 是 npx.cmd，CreateProcess 不能直接起 .cmd
    if sys.platform == "win32":
        return ["cmd", "/c"] + inner
    return inner


def maker_cmd(args: list[str], json_out: bool = True) -> subprocess.CompletedProcess:
    cmd = maker_argv(args, json_out)
    env = os.environ.copy()
    env.setdefault("npm_config_fetch_retries", "3")
    log("$ " + " ".join(cmd))
    try:
        return subprocess.run(
            cmd,
            cwd=str(ROOT),
            env=env,
            text=True,
            encoding="utf-8",
            errors="replace",
            capture_output=True,
        )
    except OSError as exc:
        die("启动 npx 失败: %s\n命令: %s" % (exc, " ".join(cmd)))


def parse_json_tail(text: str):
    text = (text or "").strip()
    if not text:
        return None
    # CLI 有时在 JSON 前打日志，取最后一段 { ... }
    start = text.rfind("{")
    if start < 0:
        return None
    try:
        return json.loads(text[start:])
    except json.JSONDecodeError:
        return None


def run_step(title: str, args: list[str], allow_fail: bool = False) -> dict:
    log("")
    log("==> " + title)
    proc = maker_cmd(args)
    combined = ((proc.stdout or "") + "\n" + (proc.stderr or "")).strip()
    if combined:
        log(combined[-4000:])
    data = parse_json_tail(combined)
    if proc.returncode != 0:
        if allow_fail:
            log("WARN: %s 失败（exit %s），继续" % (title, proc.returncode))
            return data or {"ok": False, "exit": proc.returncode}
        die("%s 失败（exit %s）" % (title, proc.returncode))
    if data:
        log(json.dumps(data, ensure_ascii=False, indent=2)[:2000])
    return data or {"ok": True}


def find_project_dir(explicit: str | None) -> Path:
    if explicit:
        p = Path(explicit).expanduser().resolve()
        if not p.is_dir():
            die("target-dir 不存在: %s" % p)
        return p
    return ROOT


def is_bound(project: Path) -> bool:
    cur = project
    for _ in range(8):
        if (cur / ".maker-mcp" / "config.json").is_file():
            return True
        if cur.parent == cur:
            break
        cur = cur.parent
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description="一键更新 Maker MCP / 本地 Runtime")
    parser.add_argument("--target-dir", default=str(ROOT), help="Maker 项目目录（默认仓库根）")
    parser.add_argument("--verify", action="store_true", help="只校验 MCP，不升级")
    parser.add_argument("--preview", action="store_true", help="同时安装本机游戏 Runtime")
    parser.add_argument("--start", action="store_true", help="升级后启动本地预览窗口")
    parser.add_argument("--ide", choices=["codex", "cursor", "claude"], help="只更新某一个 IDE")
    args = parser.parse_args()

    project = find_project_dir(args.target_dir)
    log("项目目录: %s" % project)
    log("Maker 包: %s@%s" % (MAKER_PKG, MAKER_VER))
    check_node()

    if args.verify:
        run_step("校验 MCP self runtime", ["mcp", "verify"])
        run_step("doctor", ["doctor", "--target-dir", str(project)], allow_fail=True)
        log("\n校验完成。")
        return 0

    # 1) 升级本机 MCP（写入 ~/.claude.json / Cursor / Codex，不含项目 cwd）
    upgrade = ["upgrade", "--target-dir", str(project)]
    if args.ide:
        upgrade.extend(["--ide", args.ide])
    result = run_step("升级 Maker MCP", upgrade)

    # 2) 再跑一次 install，确保 self runtime 落地
    run_step("安装 MCP self runtime", ["mcp", "install"], allow_fail=True)
    run_step("校验 MCP", ["mcp", "verify"], allow_fail=True)

    bound = is_bound(project)
    log("")
    if bound:
        log("已绑定 Maker 项目（.maker-mcp/config.json 存在）")
    else:
        log("未绑定 Maker 项目：本地预览窗口需要先在本机跑一次 `npx -y @taptap/maker init`")
        log("云端/无窗口环境可以只完成 MCP 升级，预览请在 Windows/Mac 本机执行。")

    if args.preview or args.start:
        if not bound:
            die("preview/start 需要已绑定的 Maker 项目。请先在本机执行 taptap-maker init")
        run_step(
            "安装本机游戏 Runtime（~/.taptap-maker/runtime）",
            ["preview", "install", "--target-dir", str(project)],
        )

    if args.start:
        run_step(
            "启动本地预览窗口（不远端构建）",
            ["preview", "start", "--target-dir", str(project)],
        )
        log("\n窗口已拉起。改完 scripts/ 后执行：")
        log("  npx -y --package %s@%s taptap-maker preview refresh --target-dir %s --json"
            % (MAKER_PKG, MAKER_VER, project))

    log("")
    log("完成。当前 MCP 会话仍用旧进程；要让新 MCP 生效：在 IDE 里 Reconnect / 重开 Agent。")
    log("本项目是单机客户端，本机预览不需要远端 Build。")
    if result and result.get("mcp_install"):
        for row in result["mcp_install"]:
            log("  - %s: %s" % (row.get("ide"), row.get("path")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        die("interrupted", 130)
