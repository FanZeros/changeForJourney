#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""终焉之门 · --protect 打包第一步：物化「混淆工作区」。

流程定位（详见 electron-shell/README.md §「--protect 受保护打包」）：

    protect_build.py            ← 本脚本：生成混淆工作区（仓库外，不改任何源文件）
      → taptap-maker preview prepare --target-dir <混淆工作区>
      → prepare_local_dist.py --scripts-root <混淆工作区>/scripts
      → pack_release.py --prepare-dist

为什么混淆必须发生在官方 Build **之前**：
  * `dist/assets/*.lua` 受 manifest hash/size 约束，事后替换会破坏资源校验；
  * `prepare_local_dist.verify_lua` 与 `pack_release.verify_prepare_dist` 都要求
    dist 中 Lua 与某棵源码树逐字节一致——本脚本产出的混淆工作区就是那棵树。

工作区内容：
  scripts/   361 个 .lua → L1 混淆产物（内置 5 项等价校验，任一失败即拒绝改写、
             原样复制并计入 rejected）；非 .lua（.meta/.py/.png/…）逐字节复制。
  .project/  逐字节复制（版本校验需要）。
  assets/    **真实复制**（默认且推荐）。实测官方 Build 对符号链接的 assets/
             不烘焙（dist manifest 只剩 361 lua + 4 json），换成真实复制后
             1226 个资源全部烘焙成功；故 --link-assets 仅作为磁盘紧张时的
             实验选项保留，且会在报告中打醒目警告。prepare_local_dist 侧有
             资产闸门兜底（manifest 缺图片/音频即拒包）。

安全承诺：
  * 绝不修改仓库源码 / 仓库根 dist / electron-shell/game；
  * 混淆失败的文件保持明文并在报告中显著列出（宁可漏保护，不可错保护）；
  * protect-report.json 记录每个文件的处置（changed/unchanged/rejected）与 SHA256。

用法：
  python3 protect_build.py --source-root . --workspace-root .tmp/protected-workspace
  python3 protect_build.py --source-root . --workspace-root ../protected --link-assets  # 实验:省磁盘但 Build 烘焙会失败
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

SHELL = Path(__file__).resolve().parent
sys.path.insert(0, str(SHELL))

try:
    from lua_obfuscator import obfuscate_file_safe  # noqa: E402
except ImportError as e:  # pragma: no cover
    raise SystemExit(
        "缺少依赖：%s\n请先安装：python3 -m venv ~/luaenv && "
        "~/luaenv/bin/pip install luaparser lupa" % e)


def log(msg: str) -> None:
    print("[protect] %s" % msg, flush=True)


def die(msg: str) -> None:
    print("[protect] ERROR: %s" % msg, file=sys.stderr)
    raise SystemExit(1)


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def link_or_copy_dir(src: Path, dst: Path, link: bool) -> str:
    """把 src 目录以复制(默认)或链接方式放到 dst。返回方式描述。"""
    if dst.exists() or dst.is_symlink():
        if dst.is_symlink() or dst.is_file():
            dst.unlink()
        else:
            shutil.rmtree(dst)
    if not link:
        shutil.copytree(src, dst)
        return "copied"
    if os.name == "nt":
        # junction 不需要管理员权限；symlink 需要
        subprocess.check_call(
            ["cmd", "/c", "mklink", "/J", str(dst), str(src)],
            stdout=subprocess.DEVNULL)
        return "junction"
    os.symlink(src.resolve(), dst, target_is_directory=True)
    return "symlink"


def materialize(source_root: Path, ws: Path, link_assets: bool) -> dict:
    if not (source_root / "scripts").is_dir():
        die("source-root 下没有 scripts/：%s" % source_root)
    for required in (".project", "assets"):
        if not (source_root / required).is_dir():
            die("source-root 下缺少 %s/（官方 Build 需要）" % required)

    if ws.exists():
        # 防止误删用户目录：只接受含 protect-report.json 的旧工作区
        if not (ws / "protect-report.json").is_file():
            die("workspace-root 已存在但不是本工具生成的工作区：%s" % ws)
        log("清理旧工作区 %s" % ws)
        shutil.rmtree(ws)
    ws.mkdir(parents=True)

    # assets: 默认真实复制（官方 Build 对符号链接 assets 不烘焙，实测证实）
    mode = link_or_copy_dir(source_root / "assets", ws / "assets", link_assets)
    log("assets/ -> %s (%s)" % (mode, source_root / "assets"))
    if mode \!= "copied":
        log("⚠️⚠️ --link-assets：官方 Build 实测不烘焙符号链接 assets/，dist 将缺全部"
            "图片/音频，prepare_local_dist 资产闸门会拒包。仅供实验。")

    # .project: 复制（小且需要写权限）
    shutil.copytree(source_root / ".project", ws / ".project")
    log(".project/ -> copied")

    # scripts: 物化混淆产物
    files = sorted((source_root / "scripts").rglob("*"))
    report = {"changed": [], "unchanged": [], "rejected": [], "copied_non_lua": 0}
    for src in files:
        if src.is_dir():
            continue
        rel = src.relative_to(source_root)
        dst = ws / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        raw = src.read_bytes()
        if src.suffix == ".lua":
            text = raw.decode("utf-8")
            obf, status, detail = obfuscate_file_safe(text)
            out_bytes = obf.encode("utf-8")
            dst.write_bytes(out_bytes)
            report[status].append({
                "path": rel.as_posix(),
                "detail": detail,
                "src_sha256": sha256_bytes(raw),
                "out_sha256": sha256_bytes(out_bytes),
            })
            if status in ("unchanged", "rejected"):
                # 双重保险：未改写的文件必须与源逐字节一致
                if out_bytes != raw:
                    die("%s 标记 %s 但输出与源不一致（内部错误）" % (rel, status))
        else:
            dst.write_bytes(raw)
            report["copied_non_lua"] += 1

    n_lua = len(report["changed"]) + len(report["unchanged"]) + len(report["rejected"])
    log("lua files=%d changed=%d unchanged=%d rejected=%d non_lua_copied=%d" % (
        n_lua, len(report["changed"]), len(report["unchanged"]),
        len(report["rejected"]), report["copied_non_lua"]))
    if n_lua == 0:
        die("没有找到任何 .lua 文件")

    main_lua = ws / "scripts" / "main.lua"
    if not main_lua.is_file():
        die("混淆工作区缺少 scripts/main.lua（入口）")

    if report["rejected"]:
        log("⚠️ 以下文件被拒绝改写（保持明文，需要人工跟进）：")
        for item in report["rejected"]:
            log("   %s : %s" % (item["path"], item["detail"]))

    summary = {
        "lua_total": n_lua,
        "changed": len(report["changed"]),
        "unchanged": len(report["unchanged"]),
        "rejected": len(report["rejected"]),
        "copied_non_lua": report["copied_non_lua"],
        "assets_mode": mode,
        "files": report,
    }
    (ws / "protect-report.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=1), encoding="utf-8")
    log("report -> %s" % (ws / "protect-report.json"))
    return summary


def main() -> int:
    ap = argparse.ArgumentParser(description="物化 L1 混淆工作区（--protect 打包第一步）")
    ap.add_argument("--source-root", type=Path, required=True, help="仓库根（含 scripts/.project/assets）")
    ap.add_argument("--workspace-root", type=Path, required=True, help="混淆工作区输出目录（仓库外或 .tmp 下）")
    ap.add_argument("--link-assets", action="store_true",
                    help="实验：assets/ 用符号链接/junction 代替真实复制（省 ~400MB 磁盘，"
                         "但官方 Build 实测不烘焙，资产闸门会拒包）")
    args = ap.parse_args()

    source_root = args.source_root.resolve()
    ws = args.workspace_root.resolve()
    if ws == source_root or source_root in ws.parents or ws in source_root.parents:
        die("workspace-root 不能与 source-root 互为包含（%s vs %s）" % (ws, source_root))

    summary = materialize(source_root, ws, args.link_assets)
    log("完成。下一步：")
    log('  npx -y --package @taptap/maker@0.0.34 taptap-maker preview prepare --target-dir "%s" --json' % ws)
    log("  python electron-shell/prepare_local_dist.py --scripts-root %s" % (ws / "scripts"))
    log("  python electron-shell/pack_release.py --prepare-dist")
    return 0 if summary["lua_total"] > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
