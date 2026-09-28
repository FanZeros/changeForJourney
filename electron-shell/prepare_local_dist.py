# local prepare script
# -*- coding: utf-8 -*-
# Prepare an Electron game directory from a local preview build.

# The repository dist directory is never read or overwritten, and nothing is uploaded.

from __future__ import annotations

import argparse
import importlib.util
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "electron-shell"
GAME = SHELL / "game"
# --protect 流程：Lua 校验基准源码树（混淆工作区的 scripts/）。默认仓库 scripts/。
SCRIPTS_ROOT = ROOT / "scripts"
TEMPLATE = SHELL / "index.template.html"
FORBIDDEN = ("__preview-bridge", "mac-token", "user_info", "login_token", "token", "secret")
ANCHORS = (
    "<title>TapTap Maker</title>",
    "id=\"watermark-logo\"",
    "https://tapcode-sce.spark.xd.com/src/web/src/index.min.js",
)


def fail(message: str) -> None:
    print("ERROR: " + message, file=sys.stderr)
    raise SystemExit(1)


def latest_prepare_source() -> Path:
    roots = list((Path.home() / ".taptap-maker" / "preview").glob("*/preparations/*/source"))
    if not roots:
        fail("preview prepare output not found")
    return max(roots, key=lambda path: path.stat().st_mtime)


def verify_lua(dist: Path, version: str) -> int:
    manifest_path = dist / version / "manifest-origin.json"
    if not manifest_path.is_file():
        fail("missing manifest-origin.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    items = [
        item for item in manifest["files"]
        if item.get("ext") == ".lua" and item.get("prefix") == "../scripts"
    ]
    built = {item["fs_path"] for item in items}
    source = {
        path.relative_to(SCRIPTS_ROOT).as_posix()
        for path in SCRIPTS_ROOT.rglob("*.lua")
    }
    errors = []
    for item in items:
        rel = item["fs_path"]
        built_file = dist / "assets" / (item["uuid"] + "-" + item["hash"] + ".lua")
        source_file = SCRIPTS_ROOT / rel
        same = source_file.is_file() and built_file.is_file() and source_file.read_bytes() == built_file.read_bytes()
        if not same:
            errors.append(rel)
    missing = sorted(source - built)
    extra = sorted(built - source)
    if errors or missing or extra or "main.lua" not in built:
        sample=errors[:5] or missing[:5] or extra[:5]
        fail("lua mismatch errors=%d missing=%d extra=%d missing_files=%s sample=%s dist=%s" % (len(errors), len(missing), len(extra), missing[:5], sample, dist))
    return len(items)


def verify_assets_present(dist: Path, version: str) -> None:
    """--protect 闸门：烘焙产物必须含图片与音频。工作区 assets/ 缺失或用符号链接
    （官方 Build 实测不烘焙 symlink assets）时，manifest 里非 Lua 资源会缺失，必须拒包。"""
    manifest = json.loads((dist / version / "manifest-origin.json").read_text(encoding="utf-8"))
    exts = {}
    for item in manifest["files"]:
        ext = item.get("ext")
        if ext and ext != ".lua":
            exts[ext] = exts.get(ext, 0) + 1
    missing = [e for e in (".png", ".ogg") if exts.get(e, 0) == 0]
    if missing:
        fail("manifest 缺少 %s 资源（实际非 Lua 分布：%s）：工作区 assets/ 缺失或为符号链接"
             "（官方 Build 不烘焙符号链接 assets）。--protect 流程请用 protect_build.py 默认的真实复制。"
             % (missing, exts))
    print("assets_gate_ok non_lua=%s" % exts)


def verify_build_files(dist: Path, version: str) -> None:
    required = [
        dist / "latest.json",
        dist / "project.json",
        dist / version / "manifest-origin.json",
        dist / version / "version.json",
    ]
    required.extend((dist / version).glob("engine-*.json"))
    missing = [path.name for path in required if not path.is_file()]
    if missing:
        fail("missing build files")


def load_patcher():
    spec = importlib.util.spec_from_file_location("pack_release", SHELL / "pack_release.py")
    if spec is None or spec.loader is None:
        fail("cannot load pack_release.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_index(dist: Path) -> int:
    if not TEMPLATE.is_file():
        fail("missing index.template.html")
    raw = TEMPLATE.read_text(encoding="utf-8")
    found = [item for item in FORBIDDEN if item in raw]
    if found:
        fail("template contains forbidden fields")
    for anchor in ANCHORS:
        if anchor not in raw:
            fail("template anchor missing")
    patched = load_patcher().patch_index_html(raw)
    ok = "__preview-bridge" not in patched and "PatchedWS" in patched and "终焉之门·单机版" in patched
    if not ok:
        fail("patched index failed checks")
    output = dist / "index.html"
    output.write_text(patched, encoding="utf-8")
    return output.stat().st_size


def sync_game(dist: Path) -> None:
    if GAME.exists():
        shutil.rmtree(GAME)
    shutil.copytree(dist, GAME)
    for name in ("mac-token.json", "user_info.json", "__preview-bridge.js"):
        target = GAME / name
        if target.exists():
            target.unlink()


def main() -> int:
    global SCRIPTS_ROOT
    parser = argparse.ArgumentParser(description="从最近一次 preview prepare 产物打补丁生成 game/")
    parser.add_argument("--scripts-root", type=Path, default=None,
                        help="Lua 校验基准源码树（--protect 混淆工作区的 scripts/）；默认仓库 scripts/")
    args = parser.parse_args()
    if args.scripts_root is not None:
        SCRIPTS_ROOT = args.scripts_root.resolve()
        if not (SCRIPTS_ROOT / "main.lua").is_file():
            fail("scripts-root 下没有 main.lua: %s" % SCRIPTS_ROOT)
        print("scripts_root", SCRIPTS_ROOT)
    source = latest_prepare_source()
    dist = source / "dist"
    latest = json.loads((dist / "latest.json").read_text(encoding="utf-8"))
    project = json.loads((ROOT / ".project" / "project.json").read_text(encoding="utf-8"))
    version = str(latest["version"])
    if not version == str(project["version"]):
        fail("version mismatch")
    verify_build_files(dist, version)
    verify_assets_present(dist, version)
    lua_count = verify_lua(dist, version)
    index_bytes = write_index(dist)
    sync_game(dist)
    print("ok", version, "lua", lua_count, "index_bytes", index_bytes)
    print("source_dist", dist)
    print("game", GAME)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
