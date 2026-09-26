#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""一键更新 TapTap Maker MCP + 本机 Runtime（Windows / macOS / Linux）

官方口径（@taptap/maker 0.0.34）：
  - 客户端单机游戏：本机 Runtime 直读项目目录，不提交、不上传、不远端构建
  - 改了服务端：仍需远端构建
  - Agent 里说「更新 Maker MCP」= 跑本脚本

用法：
  python tools/update-maker-mcp.py              # 默认等于 --start：升级后开窗口，Windows 跳过扫码
  python tools/update-maker-mcp.py --preview    # 只装本地 Runtime，不开窗口
  python tools/update-maker-mcp.py --start      # 与不带参数相同
  python tools/update-maker-mcp.py --verify     # 只校验，不改配置
  python tools/update-maker-mcp.py --log        # 输出升级、npm 和 Runtime 日志（可与其他参数组合）

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
import threading
from pathlib import Path

MAKER_PKG = "@taptap/maker"
MAKER_VER = "0.0.34"
# 本文件在 <repo>/maker-mcp/，仓库根是上一级
ROOT = Path(__file__).resolve().parent.parent
SHOW_LOG = False


def log(msg: str) -> None:
    if SHOW_LOG:
        print(msg, flush=True)


def die(msg: str, code: int = 1) -> None:
    print("ERROR: " + msg, file=sys.stderr, flush=True)
    sys.exit(code)


def which_node() -> str:
    node = shutil.which("node")
    if not node:
        die("找不到 node。请先安装 Node.js >= 18：https://nodejs.org/")
    return node


def npx_js() -> str:
    """npx.cmd 会弹黑窗；直接用 node 跑 npm 自带的 npx-cli.js。"""
    node = Path(which_node()).resolve()
    candidates = [
        node.parent / "node_modules" / "npm" / "bin" / "npx-cli.js",
        node.parent.parent / "lib" / "node_modules" / "npm" / "bin" / "npx-cli.js",
        node.parent / "npx-cli.js",
    ]
    for p in candidates:
        if p.is_file():
            return str(p)
    npx = shutil.which("npx")
    if npx:
        return npx
    die("找不到 npx-cli.js / npx（应随 Node.js 安装）")


def check_node() -> None:
    node = which_node()
    out = subprocess.check_output(
        [node, "-v"], text=True, encoding="utf-8", errors="replace"
    ).strip().lstrip("v")
    major = int(out.split(".")[0])
    log("Node %s  (%s)" % (out, node))
    if major < 18:
        die("需要 Node.js >= 18，当前 %s" % out)
    log("npx-cli (%s)" % npx_js())


def maker_argv(args: list[str], json_out: bool) -> list[str]:
    npx = npx_js()
    inner = ["-y", "--package", "%s@%s" % (MAKER_PKG, MAKER_VER), "taptap-maker"]
    inner += list(args)
    if json_out and "--json" not in args:
        inner.append("--json")
    # Windows：优先 node + npx-cli.js，避免 cmd /c npx.cmd 弹四五个黑窗
    if npx.lower().endswith(".js"):
        return [which_node(), npx] + inner
    if sys.platform == "win32":
        return ["cmd", "/c", npx] + inner
    return [npx] + inner


def maker_cmd(args: list[str], json_out: bool = True, timeout: int = 180) -> subprocess.CompletedProcess:
    """Run taptap-maker, capturing output; stream it only with --log."""
    cmd = maker_argv(args, json_out)
    env = os.environ.copy()
    env.setdefault("npm_config_fetch_retries", "2")
    env.setdefault("npm_config_fund", "false")
    env.setdefault("npm_config_audit", "false")
    env.setdefault("npm_config_update_notifier", "false")
    env["CI"] = "1"
    shown = subprocess.list2cmdline(cmd) if sys.platform == "win32" else " ".join(cmd)
    log("$ " + shown)
    log("    本步最多 %s 秒，超时就停。" % timeout)
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=str(ROOT),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
    except OSError as exc:
        die("启动 npx 失败: %s\n命令: %s" % (exc, shown))

    chunks: list[str] = []

    def _read() -> None:
        if proc.stdout is None:
            return
        for line in proc.stdout:
            chunks.append(line)
            if SHOW_LOG:
                print(line, end="", flush=True)

    reader = threading.Thread(target=_read, daemon=True)
    reader.start()
    try:
        code = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        reader.join(2)
        log("TIMEOUT: 本步超过 %s 秒，已杀掉。多半是 npm 下载 @taptap/maker 卡住。" % timeout)
        return subprocess.CompletedProcess(cmd, 124, "".join(chunks), "TIMEOUT")
    reader.join(3)
    return subprocess.CompletedProcess(cmd, code, "".join(chunks), "")

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


def run_step(title: str, args: list[str], allow_fail: bool = False, timeout: int = 180) -> dict:
    log("")
    log("==> " + title)
    proc = maker_cmd(args, timeout=timeout)
    combined = ((proc.stdout or "") + "\n" + (proc.stderr or "")).strip()
    if combined and SHOW_LOG:
        log(combined[-4000:])
    data = parse_json_tail(combined)
    cli_failed = proc.returncode != 0 or (isinstance(data, dict) and data.get("ok") is False)
    if cli_failed:
        if allow_fail:
            log("WARN: %s 未完全成功（exit %s），继续" % (title, proc.returncode))
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


def maker_home() -> Path:
    override = os.environ.get("TAPTAP_MAKER_HOME")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".taptap-maker"


def find_windows_runtime() -> Path:
    """Installed UrhoXRuntime.exe. Do not suggest reinstalling Node."""
    root = maker_home() / "runtime"
    install = root / "installation.json"
    if install.is_file():
        try:
            data = json.loads(install.read_text(encoding="utf-8"))
            exe = data.get("executable")
            if isinstance(exe, str) and Path(exe).is_file():
                return Path(exe)
        except (OSError, json.JSONDecodeError):
            pass
    candidates: list[Path] = []
    if root.is_dir():
        for child in root.iterdir():
            exe = child / "UrhoXRuntime.exe"
            if child.is_dir() and child.name.startswith("runtime-") and exe.is_file():
                candidates.append(exe)
    if not candidates:
        die(
            "找不到 UrhoXRuntime.exe（应在 %s 下的 runtime-*）。先跑 maker-mcp\\update-maker-mcp.bat --preview，不要重装 Node。"
            % root
        )
    candidates.sort(key=lambda item: item.stat().st_mtime, reverse=True)
    return candidates[0]


def preview_entry(project: Path) -> str:
    entry = "main.lua"
    cfg = project / ".project" / "project.json"
    try:
        data = json.loads(cfg.read_text(encoding="utf-8"))
        raw = data.get("entry")
        if isinstance(raw, str) and raw.endswith(".lua") and not Path(raw).is_absolute():
            entry = raw
    except (OSError, json.JSONDecodeError):
        pass
    if not (project / "scripts" / entry).is_file():
        die("找不到入口 scripts/%s，Runtime 会报找不到 Start。" % entry)
    return entry


def launch_windows_runtime(project: Path) -> None:
    """Foreground-launch Runtime with the same args as official preview.

    Official preview start on Windows uses a hidden PowerShell process created
    via Win32_Process.Create. That child often never runs. Launch the exe
    directly, but keep the official argument list: entry, tapcode_dir, and
    -skip_login. Entry is required so the Runtime loads scripts/main.lua and
    finds Start(). -skip_login skips the Tap QR screen.
    """
    exe = find_windows_runtime()
    entry = preview_entry(project)
    cmd = [
        str(exe),
        entry,
        "-tapcode_dir=" + str(project),
        "-skip_login",
        "-p=Res",
        "-w",
        "-width=1920",
        "-height=1080",
    ]
    shown = subprocess.list2cmdline(cmd)
    log("")
    log("==> 前台启动 Runtime（不跑 preview start，也不走隐藏 PowerShell）")
    log("只传 -skip_login 时 Runtime 可能找不到入口，从而提示 Start。")
    log("现在带上入口 %s 和 -tapcode_dir，并跳过 Tap 扫码。" % entry)
    log("Runtime: %s" % exe)
    log("工作目录: %s" % project)
    log("等价命令:")
    log('  cd /d "%s"' % project)
    log("  " + shown)
    log("游戏窗口关掉之前，这个黑窗会停在这里。不要关黑窗。")
    code = subprocess.call(
        cmd,
        cwd=str(project),
        stdout=None if SHOW_LOG else subprocess.DEVNULL,
        stderr=None if SHOW_LOG else subprocess.DEVNULL,
    )
    log("Runtime 已退出，exit=%s" % code)
    if code != 0:
        die("Runtime 退出码 %s。使用 --log 重试查看详细日志。" % code)

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
    global SHOW_LOG
    parser = argparse.ArgumentParser(description="一键更新 Maker MCP / 本地 Runtime")
    parser.add_argument("--log", action="store_true", help="输出升级、npm 和 Runtime 的详细日志（默认静默）")
    parser.add_argument("--target-dir", default=str(ROOT), help="Maker 项目目录（默认仓库根）")
    parser.add_argument("--verify", action="store_true", help="只校验 MCP，不升级")
    parser.add_argument("--preview", action="store_true", help="同时安装本机游戏 Runtime")
    parser.add_argument("--start", action="store_true", help="升级后启动本地预览窗口。不带参数时默认开启")
    parser.add_argument("--ide", choices=["codex", "cursor", "claude"], help="只更新某一个 IDE")
    args = parser.parse_args()
    SHOW_LOG = args.log

    if not (args.verify or args.preview or args.start or args.ide):
        args.start = True
        log("未带参数，按 --start 处理：升级后开本地窗口。Windows 前台启动并跳过 Tap 扫码。")

    project = find_project_dir(args.target_dir)
    log("项目目录: %s" % project)
    log("Maker 包: %s@%s" % (MAKER_PKG, MAKER_VER))
    log("本机预览，不走云端 Build。npm 下载时日志会往下刷，不会再停在 $ 那一行没动静。")
    check_node()
    if args.preview or args.start:
        if not is_bound(project):
            die(
                "找不到 .maker-mcp/config.json，本地窗口开不了。"
                "先在项目根绑定一次（要登录），再重跑 --start：\n"
                "  npx -y --package %s@%s taptap-maker init --target-dir \"%s\""
                % (MAKER_PKG, MAKER_VER, project)
            )
        log("已绑定 Maker 项目，--start 会在升级后安装 Runtime 并开窗口。")

    if args.verify:
        run_step("校验 MCP self runtime", ["mcp", "verify"])
        run_step("doctor", ["doctor", "--target-dir", str(project)], allow_fail=True)
        log("\n校验完成。")
        return 0

    # 1) 按 IDE 分别升级。官方 CLI 给已存在的 ~/.codex 做 mkdir 会 EEXIST，
    #    一次 upgrade 全 IDE 会整步失败；分开跑，失败的跳过。
    ides = [args.ide] if args.ide else ["claude", "cursor", "codex"]
    result = {"ok": True, "mcp_install": []}
    any_ok = False
    for ide in ides:
        row = run_step(
            "升级 Maker MCP (%s)" % ide,
            ["upgrade", "--ide", ide, "--target-dir", str(project)],
            allow_fail=True,
            timeout=120,
        )
        installs = (row or {}).get("mcp_install") or []
        result["mcp_install"].extend(installs)
        if (row or {}).get("ok") or any(x.get("ok") for x in installs):
            any_ok = True
        elif not installs:
            msg = ""
            if isinstance(row, dict):
                msg = str(row.get("message") or row.get("error") or "")
            if "EEXIST" in msg or "mkdir" in msg:
                log("WARN: %s 配置目录已存在，官方 CLI mkdir 撞 EEXIST，跳过该 IDE" % ide)
    result["ok"] = any_ok
    if not any_ok:
        log("WARN: 所有 IDE 的 upgrade 都失败了，继续走 mcp install / verify")

    # 2) 再跑一次 install，确保 self runtime 落地
    run_step("安装 MCP self runtime", ["mcp", "install"], allow_fail=True, timeout=180)
    run_step("校验 MCP", ["mcp", "verify"], allow_fail=True, timeout=90)

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
            timeout=600,
        )

    if args.start:
        if sys.platform == "win32":
            launch_windows_runtime(project)
            log("")
            log("改完 scripts/ 后重新双击本脚本即可。不要用官方 preview refresh。")
            log("官方 refresh 仍走没起来的隐藏 PowerShell supervisor。")
        else:
            run_step(
                "启动本地预览窗口（不远端构建）",
                ["preview", "start", "--target-dir", str(project)],
                timeout=180,
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
