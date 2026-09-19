#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""终焉之门 · Windows 离线版一键打包 / 上传。

本机直接跑（不要走云端代理传 466MB zip，会被超时掐断）。

用法：
  python pack_release.py                 # 同步 dist → 打补丁 → 打包 zip
  python pack_release.py --upload        # 打包后上传 GitHub Release
  python pack_release.py --upload-only   # 只上传已有 zip（不重打）
  python pack_release.py --skip-sync     # 不拷 dist，用现有 game/
  python pack_release.py --skip-build    # 不跑 electron-builder，只打 zip

双击 Windows：pack_release.bat / pack_and_upload.bat
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile
import zlib
from pathlib import Path
from urllib.parse import urlparse, urlunparse
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

SHELL = Path(__file__).resolve().parent
ROOT = SHELL.parent
DIST = ROOT / "dist"
GAME = SHELL / "game"
RELEASE = SHELL / "release"
UNPACKED = RELEASE / "win-unpacked"
PKG = SHELL / "package.json"
REPO_DEFAULT = "FanZeros/changeForJourney"

# ---- 自带运行时（离线引擎） ----
# 引擎 wasm/js/data(约83MB) 从官方 CDN 镜像到本地，玩家首次启动零联网。
# loader 逻辑: engine-{ver}.json 的 base_url + tag → {base_url}stable.json
#   → {base_url}{version}/manifest-{client}.json → {base_url}assets/{uuid}-{hash}{ext}
# 离线包把 base_url 补丁成相对路径 "src/engine/"（相对页面 origin=本地 server），
# 并把 CDN 文件镜像进 game/src/engine/。index.min.js（web 入口 loader）同样本地化。
CDN_ORIGIN = "https://tapcode-sce.spark.xd.com"
ENGINE_BASE = CDN_ORIGIN + "/src/engine"
WEB_BASE = CDN_ORIGIN + "/src/web/src/index.min.js"
RUNTIME_DIR = SHELL / "game_engine"

DROP_FILES = ("mac-token.json", "user_info.json", "__preview-bridge.js")

CSS_HIDE = """    .fab-main, .fab-icon { display: none !important; }
    #eruda, .eruda-entry-btn, .eruda-icon-tool { display: none !important; }
"""

HEAD_SCRIPTS = """<script>
(function () {
  var obs = new MutationObserver(function (muts) {
    muts.forEach(function (m) {
      m.addedNodes.forEach(function (n) {
        if (!n) return;
        if (n.id === "eruda" || (n.classList && (n.classList.contains("eruda-entry-btn") || n.classList.contains("eruda-icon-tool")))) {
          n.remove();
        }
        if (n.querySelector) {
          var e = n.querySelector("#eruda, .eruda-entry-btn, .eruda-icon-tool");
          if (e) e.remove();
        }
      });
    });
  });
  obs.observe(document.documentElement, { childList: true, subtree: true });
})();
</script>
<script>
(function () {
  var OrigWS = window.WebSocket;
  function PatchedWS(url, protocols) {
    if (String(url).indexOf("entrance-new-pd.spark.xd.com") !== -1) {
      url = "ws://127.0.0.1:1/";
    }
    return protocols === undefined ? new OrigWS(url) : new OrigWS(url, protocols);
  }
  PatchedWS.prototype = OrigWS.prototype;
  window.WebSocket = PatchedWS;
})();
</script>
"""


def log(msg: str) -> None:
    print("[%s] %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


def die(msg: str, code: int = 1) -> None:
    log("ERROR: " + msg)
    raise SystemExit(code)


def read_version() -> str:
    data = json.loads(PKG.read_text(encoding="utf-8"))
    ver = str(data.get("version") or "").strip()
    if not ver:
        die("package.json 没有 version")
    return ver


def zip_name(ver: str) -> str:
    return "ZhongYanZhiMen-win64-offline-%s.zip" % ver


def zip_path(ver: str) -> Path:
    return RELEASE / zip_name(ver)


def which_npm() -> str:
    for name in ("npm.cmd", "npm.exe", "npm"):
        p = shutil.which(name)
        if p:
            return p
    die("找不到 npm，请先安装 Node.js")
    return ""


def which_python() -> str:
    return sys.executable


def git_remote_repo() -> str:
    try:
        out = subprocess.check_output(
            ["git", "remote", "get-url", "origin"],
            cwd=str(ROOT),
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return REPO_DEFAULT
    # git@github.com:owner/repo.git  or  https://github.com/owner/repo.git
    s = out
    if s.endswith(".git"):
        s = s[:-4]
    if "github.com" in s:
        part = s.split("github.com", 1)[1].lstrip("/:")
        if part.count("/") >= 1:
            return part.split("?")[0]
    return REPO_DEFAULT


def token_from_git_credentials() -> str:
    home = Path.home()
    for p in (home / ".git-credentials", ROOT / ".git-credentials"):
        if not p.exists():
            continue
        for raw in p.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw.strip()
            if not line or "github.com" not in line:
                continue
            u = urlparse(line)
            tok = u.password or u.username or ""
            if tok and tok not in ("x-oauth-basic", "git"):
                return tok
    return ""


def github_token() -> str:
    for k in ("GITHUB_TOKEN", "GH_TOKEN"):
        v = (os.environ.get(k) or "").strip()
        if v:
            return v
    gh = shutil.which("gh") or shutil.which("gh.exe")
    if gh:
        try:
            out = subprocess.check_output(
                [gh, "auth", "token"], text=True, stderr=subprocess.DEVNULL
            ).strip()
            if out:
                return out
        except Exception:
            pass
    return token_from_git_credentials()


def patch_index_html(html: str) -> str:
    html = html.replace("\\!", "!")
    # 窗口标题（否则显示 TapTap Maker）
    html = html.replace("<title>TapTap Maker</title>", "<title>终焉之门·单机版</title>")
    # 去预览桥
    out = []
    for line in html.splitlines(True):
        if "__preview-bridge.js" in line:
            continue
        if 'id="watermark-logo"' in line:
            continue
        out.append(line)
    html = "".join(out)
    # loading-logo 走 CDN，COEP credentialless 下必须带 crossorigin 才能加载
    html = html.replace(
        '<img id="loading-logo" src=',
        '<img id="loading-logo" crossorigin="anonymous" src=',
    )
    if "fab-main" not in html:
        html = html.replace("  </style>", CSS_HIDE + "  </style>", 1)
    if "PatchedWS" not in html:
        html = html.replace("</head>", HEAD_SCRIPTS + "</head>", 1)
    html = html.replace(
        'src="https://tapcode-sce.spark.xd.com/src/web/src/index.min.js"',
        'src="src/web/src/index.min.js"',
    )
    # 上面 replace 可能重复加 crossorigin
    html = html.replace(
        'crossorigin="anonymous" crossorigin="anonymous"',
        'crossorigin="anonymous"',
    )
    return html


def patch_engine_json(game_dir: Path) -> None:
    """engine-*.json 的 base_url 改相对路径 → 引擎从本地 server 拉取。"""
    import glob
    for p in glob.glob(str(game_dir / "1.*" / "engine-*.json")):
        fp = Path(p)
        try:
            data = json.loads(fp.read_text(encoding="utf-8"))
        except Exception as e:
            log("WARN engine json 解析失败 %s: %s" % (fp.name, e))
            continue
        if data.get("base_url") == "src/engine/":
            continue
        data["base_url"] = "src/engine/"
        fp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        log("已本地化 %s → base_url=src/engine/" % fp.name)


def fetch_json(url: str, timeout: int = 60):
    req = Request(url, headers={"User-Agent": "zyjm-pack-release"})
    with urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


# ---- dist 快照托管（本机无 Maker 时自动拉取） ----
# dist/ 是 Maker 构建产物（gitignore，不入库）。云端会话在 Build 后把 dist 打成
# dist-{version}.zip 上传到 Release tag=dist-snapshot；本机脚本缺 dist 时自动下载解压。
DIST_SNAPSHOT_TAG = "dist-snapshot"


def download_dist_snapshot(ver: str) -> None:
    repo = git_remote_repo()
    token = github_token()
    if not token:
        die("本机没有 dist/ 且找不到 GitHub token（拉取 dist 快照需要）。\n"
            "  任选：gh auth login / setx GITHUB_TOKEN <PAT> / git 已存凭据")
    name = "dist-%s.zip" % ver
    url = "https://github.com/%s/releases/download/%s/%s" % (repo, DIST_SNAPSHOT_TAG, name)
    log("本机无 dist/，从 Release %s 拉取 %s …" % (DIST_SNAPSHOT_TAG, name))
    tmp = RELEASE / name
    tmp.parent.mkdir(parents=True, exist_ok=True)
    req = Request(url, headers={"User-Agent": "zyjm-pack-release"})
    try:
        with urlopen(req, timeout=3600) as resp, tmp.open("wb") as out:
            total = 0
            while True:
                chunk = resp.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
                total += len(chunk)
                if total % (16 << 20) < (1 << 20):
                    log("  downloaded %.0f MB" % (total / 1048576))
    except HTTPError as e:
        die("拉取 dist 快照失败 HTTP %s：%s\n"
            "  请让云端会话在 Build 后上传 dist-%s.zip（tag=%s）。" % (e.code, e.read().decode(errors="replace")[:300], ver, DIST_SNAPSHOT_TAG))
    except URLError as e:
        die("拉取 dist 快照网络错误: %s" % e)
    log("下载完成 %.0f MB，解压到 dist/ …" % (tmp.stat().st_size / 1048576))
    target = ROOT / "dist"
    if target.exists():
        shutil.rmtree(target)
    with zipfile.ZipFile(tmp) as zf:
        names = zf.namelist()
        root_prefix = ""
        first = names[0].split("/", 1)
        if len(first) == 2 and all(n.split("/", 1)[0] == first[0] for n in names[:20]):
            root_prefix = first[0] + "/"  # zip 内有单层根目录则剥掉
        zf.extractall(ROOT)
    if root_prefix and (ROOT / root_prefix.rstrip("/")).is_dir():
        if target.exists():
            shutil.rmtree(target)
        (ROOT / root_prefix.rstrip("/")).rename(target)
    tmp.unlink()
    if not (target / "index.html").exists():
        die("dist 快照解压后没有 index.html，内容异常")
    log("dist/ 就绪（来自快照 %s）" % name)


def ensure_dist(ver: str) -> None:
    if (ROOT / "dist" / "index.html").exists():
        return
    download_dist_snapshot(ver)


def upload_dist_snapshot(ver: str) -> None:
    """云端用：把 dist/ 打成 dist-{ver}.zip 上传到 Release dist-snapshot。"""
    dist = ROOT / "dist"
    if not (dist / "index.html").exists():
        die("没有 dist/，先 Build")
    token = github_token()
    if not token:
        die("找不到 GitHub token")
    repo = git_remote_repo()
    out = RELEASE / ("dist-%s.zip" % ver)
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    log("压缩 dist → %s …" % out.name)
    files = []
    for dirpath, _d, filenames in os.walk(dist):
        for fn in filenames:
            fp = Path(dirpath) / fn
            files.append((fp, fp.relative_to(dist).as_posix()))
    n = len(files)
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for i, (fp, arc) in enumerate(files, 1):
            zf.write(fp, arcname=arc)
            if i % 200 == 0 or i == n:
                log("  zip %d/%d" % (i, n))
    log("dist 快照 %.0f MB" % (out.stat().st_size / 1048576))
    rel = get_or_create_release_tag(repo, token, DIST_SNAPSHOT_TAG,
                                    "dist 快照（供本机 pack_release 自动拉取）")
    rid = int(rel.get("id") or 0)
    delete_asset_if_exists(repo, token, rel, out.name)
    upload_file(repo, token, rid, out, "application/zip")
    log("dist 快照已上传：Release %s / %s" % (DIST_SNAPSHOT_TAG, out.name))


def get_or_create_release_tag(repo: str, token: str, tag: str, desc: str) -> dict:
    status_url = "https://api.github.com/repos/%s/releases/tags/%s" % (repo, tag)
    req = Request(status_url, headers={
        "Authorization": "token " + token,
        "Accept": "application/vnd.github+json",
        "User-Agent": "zyjm-pack-release",
    })
    try:
        with urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode())
    except HTTPError as e:
        if e.code != 404:
            body = e.read().decode(errors="replace")[:800]
            die("GET release 失败 %s %s" % (e.code, body))
    log("创建 Release %s …" % tag)
    payload = json.dumps({
        "tag_name": tag,
        "name": tag,
        "body": desc,
        "draft": False,
        "prerelease": False,
    }).encode("utf-8")
    _st, rel = api_request(
        "POST",
        "https://api.github.com/repos/%s/releases" % repo,
        token,
        data=payload,
        content_type="application/json",
    )
    return rel or {}


def runtime_files(stable: dict, manifest: dict) -> list:
    """返回 [(relpath, url, size, crc32)]：引擎 stable.json + assets + index.min.js。"""
    version = stable["version"]
    items = [
        ("src/engine/stable.json", ENGINE_BASE + "/stable.json", 0, None),
        ("src/engine/%s/manifest-%s.json" % (version, stable["client"]),
         "%s/%s/manifest-%s.json" % (ENGINE_BASE, version, stable["client"]), 0, None),
    ]
    for f in manifest.get("files") or []:
        crc = None
        try:
            crc = int(f.get("hash") or "", 16)
        except ValueError:
            pass
        items.append(("src/engine/assets/" + "%s-%s%s" % (f["uuid"], f["hash"], f["ext"]),
                      ENGINE_BASE + "/assets/" + f["uuid"] + "-" + f["hash"] + f["ext"],
                      int(f.get("size") or 0), crc))
    return items


def runtime_ready(items: list) -> bool:
    for rel, _url, size, _crc in items:
        fp = RUNTIME_DIR / rel
        if not fp.exists():
            return False
        if size and fp.stat().st_size != size:
            return False
    idx = RUNTIME_DIR / "src/web/src/index.min.js"
    return idx.exists() and idx.stat().st_size > 10000


def fetch_binary(url: str, fp: Path, want_size: int, want_crc: int | None) -> None:
    """下载并落盘。CDN 对二进制返回 content-encoding: gzip（压缩流），
    urllib 不会自动解压——按响应头手工解压，再按 size/CRC32 校验。"""
    req = Request(url, headers={"User-Agent": "zyjm-pack-release"})
    with urlopen(req, timeout=1800) as resp:
        data = resp.read()
        if (resp.headers.get("Content-Encoding") or "").lower() == "gzip":
            data = gzip.decompress(data)
    if want_size and len(data) != want_size:
        die("%s size 不匹配：got %s want %s" % (fp, len(data), want_size))
    if want_crc is not None:
        actual = zlib.crc32(data) & 0xFFFFFFFF
        if actual != want_crc:
            die("%s crc32 不匹配：got %08x want %08x" % (fp, actual, want_crc))
    fp.parent.mkdir(parents=True, exist_ok=True)
    fp.write_bytes(data)


def download_runtime() -> None:
    """镜像引擎运行时到 game_engine/（幂等；已有且完整则跳过）。"""
    log("检查离线运行时镜像 game_engine/ …")
    stable = fetch_json(ENGINE_BASE + "/stable.json")
    version = stable["version"]
    manifest = fetch_json("%s/%s/manifest-%s.json" % (ENGINE_BASE, version, stable["client"]))
    items = runtime_files(stable, manifest)
    if runtime_ready(items):
        log("运行时镜像已就绪（v%s，%d 个文件）" % (version, len(items)))
    else:
        total = sum(s for _, _, s, _ in items) / 1048576
        log("下载引擎运行时 v%s（约 %.0f MB，含 wasm/data）…" % (version, total))
        for rel, url, size, crc in items:
            fp = RUNTIME_DIR / rel
            if fp.exists() and size and fp.stat().st_size == size:
                continue
            log("  下载 %s" % rel)
            fetch_binary(url, fp, size, crc)
    idx = RUNTIME_DIR / "src/web/src/index.min.js"
    if not (idx.exists() and idx.stat().st_size > 10000):
        idx.parent.mkdir(parents=True, exist_ok=True)
        log("  下载 index.min.js（web 入口 loader）")
        fetch_binary(WEB_BASE, idx, 0, None)
    # web libs：loader 动态 import 的调试器/视频 muxer，一并本地化避免离线报错
    for lib in ("eruda.min.js", "mp4-muxer.mjs"):
        fp = RUNTIME_DIR / "src/web/libs" / lib
        if not fp.exists():
            fp.parent.mkdir(parents=True, exist_ok=True)
            log("  下载 libs/%s" % lib)
            fetch_binary(CDN_ORIGIN + "/src/web/libs/" + lib, fp, 0, None)
    log("离线运行时镜像就绪：%s" % RUNTIME_DIR)


def sync_dist() -> None:
    if not DIST.exists():
        die("找不到 dist/。先在 Maker 里 Build，或把产物拷到仓库根目录 dist/")
    log("同步 dist → electron-shell/game/ …")
    if GAME.exists():
        shutil.rmtree(GAME)
    shutil.copytree(DIST, GAME, dirs_exist_ok=False)
    for name in DROP_FILES:
        p = GAME / name
        if p.exists():
            p.unlink()
            log("删除 " + name)
    idx = GAME / "index.html"
    if not idx.exists():
        die("dist/index.html 不存在")
    patched = patch_index_html(idx.read_text(encoding="utf-8", errors="replace"))
    idx.write_text(patched, encoding="utf-8")
    log("已打补丁：去桥 / 去水印 / 免登录 shim / 隐藏 eruda / loader 与引擎本地化")
    # 自带运行时：镜像 → game/，engine json base_url 改相对路径
    if RUNTIME_DIR.exists():
        for item in RUNTIME_DIR.glob("*"):
            dst = GAME / item.name
            if item.is_dir():
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(item, dst)
            else:
                shutil.copy2(item, dst)
        patch_engine_json(GAME)
        n_files = sum(1 for _ in GAME.rglob("*") if _.is_file())
        log("自带运行时已并入 game/（src/engine + src/web），总计 %d 文件" % n_files)
    else:
        log("WARN 无 game_engine/ 镜像，包内不自带运行时（玩家首启需联网拉 WASM）")


def ensure_npm_install() -> None:
    if (SHELL / "node_modules" / "electron-builder").exists():
        return
    log("npm install（首次会下 Electron 二进制，可能较慢）…")
    subprocess.check_call([which_npm(), "install"], cwd=str(SHELL))


def run_builder() -> None:
    ensure_npm_install()
    log("electron-builder --win --dir --x64 …")
    env = os.environ.copy()
    proxy = env.get("HTTPS_PROXY") or env.get("https_proxy") or env.get("HTTP_PROXY")
    if proxy:
        env.setdefault("ELECTRON_GET_USE_PROXY", "true")
        env.setdefault("GLOBAL_AGENT_HTTPS_PROXY", proxy)
        env.setdefault("GLOBAL_AGENT_HTTP_PROXY", proxy)
    subprocess.check_call([which_npm(), "run", "dir"], cwd=str(SHELL), env=env)
    exe = UNPACKED / "ZhongYanZhiMen.exe"
    if not exe.exists():
        die("构筑失败：找不到 %s" % exe)


def make_zip(ver: str) -> Path:
    if not UNPACKED.exists():
        die("找不到 release/win-unpacked，先打包")
    RELEASE.mkdir(parents=True, exist_ok=True)
    out = zip_path(ver)
    if out.exists():
        out.unlink()
    log("压缩 %s …" % out.name)
    files = []
    for dirpath, _dirnames, filenames in os.walk(UNPACKED):
        for fn in filenames:
            files.append(Path(dirpath) / fn)
    n = len(files)
    t0 = time.time()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for i, fp in enumerate(files, 1):
            arc = fp.relative_to(UNPACKED).as_posix()
            zf.write(fp, arcname=arc)
            if i % 80 == 0 or i == n:
                log("  zip %d/%d" % (i, n))
    sha = hashlib.sha256(out.read_bytes()).hexdigest()
    sha_path = Path(str(out) + ".sha256")
    sha_path.write_text("%s  %s\n" % (sha, out.name), encoding="utf-8")
    mb = out.stat().st_size / (1024 * 1024)
    log("zip 完成 %.1f MB  耗时 %.0fs" % (mb, time.time() - t0))
    log("sha256 %s" % sha)
    log("产物: %s" % out)
    return out


def api_request(method: str, url: str, token: str, data: bytes | None = None, content_type: str | None = None, timeout: int = 60):
    headers = {
        "Authorization": "token " + token,
        "Accept": "application/vnd.github+json",
        "User-Agent": "zyjm-pack-release",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if content_type:
        headers["Content-Type"] = content_type
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw.decode() or "null") if raw else None
    except HTTPError as e:
        body = e.read().decode(errors="replace")[:800]
        die("GitHub API %s %s → %s %s" % (method, url, e.code, body))
        return e.code, None


def get_or_create_release(repo: str, token: str, ver: str) -> dict:
    tag = "win64-v%s" % ver
    status_url = "https://api.github.com/repos/%s/releases/tags/%s" % (repo, tag)
    req = Request(status_url, headers={
        "Authorization": "token " + token,
        "Accept": "application/vnd.github+json",
        "User-Agent": "zyjm-pack-release",
    })
    try:
        with urlopen(req, timeout=60) as resp:
            rel = json.loads(resp.read().decode())
            log("已有 Release %s id=%s" % (tag, rel.get("id")))
            return rel
    except HTTPError as e:
        if e.code != 404:
            body = e.read().decode(errors="replace")[:800]
            die("GET release 失败 %s %s" % (e.code, body))
    log("创建 Release %s …" % tag)
    payload = json.dumps({
        "tag_name": tag,
        "name": "Windows 离线版 v%s" % ver,
        "body": "终焉之门·单机版 Windows 离线包（解压后运行 ZhongYanZhiMen.exe）。\n首次启动需联网拉引擎 WASM（约 70MB）。",
        "draft": False,
        "prerelease": False,
    }).encode("utf-8")
    _st, rel = api_request(
        "POST",
        "https://api.github.com/repos/%s/releases" % repo,
        token,
        data=payload,
        content_type="application/json",
    )
    return rel or {}


def delete_asset_if_exists(repo: str, token: str, rel: dict, name: str) -> None:
    for a in rel.get("assets") or []:
        if a.get("name") == name:
            aid = a.get("id")
            log("删除旧资产 %s id=%s" % (name, aid))
            url = "https://api.github.com/repos/%s/releases/assets/%s" % (repo, aid)
            req = Request(url, headers={
                "Authorization": "token " + token,
                "Accept": "application/vnd.github+json",
                "User-Agent": "zyjm-pack-release",
            }, method="DELETE")
            try:
                with urlopen(req, timeout=60) as resp:
                    resp.read()
            except HTTPError as e:
                if e.code not in (204, 200):
                    log("删除旧资产失败 %s（继续）" % e.code)


def upload_file(repo: str, token: str, release_id: int, path: Path, content_type: str) -> None:
    url = "https://uploads.github.com/repos/%s/releases/%s/assets?name=%s" % (
        repo, release_id, path.name
    )
    size = path.stat().st_size
    log("上传 %s (%.1f MB) …" % (path.name, size / 1048576))
    t0 = time.time()
    sent_holder = {"n": 0}

    class ProgressFile:
        def __init__(self, fp, total):
            self.fp = fp
            self.total = total
            self.sent = 0
            self.last = 0

        def read(self, n: int = -1):
            chunk = self.fp.read(n)
            if chunk:
                self.sent += len(chunk)
                sent_holder["n"] = self.sent
                if self.sent - self.last >= 8 * 1024 * 1024 or self.sent == self.total:
                    self.last = self.sent
                    log("  sent %.1f / %.1f MB (%.0fs)" % (
                        self.sent / 1048576, self.total / 1048576, time.time() - t0
                    ))
            return chunk

        def __len__(self):
            return self.total

    headers = {
        "Authorization": "token " + token,
        "Accept": "application/vnd.github+json",
        "Content-Type": content_type,
        "Content-Length": str(size),
        "User-Agent": "zyjm-pack-release",
    }
    with path.open("rb") as raw:
        body = ProgressFile(raw, size)
        req = Request(url, data=body, headers=headers, method="POST")
        try:
            with urlopen(req, timeout=1800) as resp:
                info = json.loads(resp.read().decode())
        except HTTPError as e:
            body_txt = e.read().decode(errors="replace")[:800]
            die("上传失败 HTTP %s %s" % (e.code, body_txt))
        except URLError as e:
            die("上传网络错误: %s" % e)
    log("上传完成 id=%s size=%s state=%s 耗时 %.0fs" % (
        info.get("id"), info.get("size"), info.get("state"), time.time() - t0
    ))
    if int(info.get("size") or 0) != size:
        die("远端 size 不匹配：本地 %s 远端 %s" % (size, info.get("size")))
    if info.get("state") != "uploaded":
        die("远端 state=%s，未完成" % info.get("state"))


def upload_release(ver: str) -> None:
    zp = zip_path(ver)
    if not zp.exists():
        die("没有 zip：%s" % zp)
    token = github_token()
    if not token:
        die(
            "找不到 GitHub token。任选其一：\n"
            "  1) 安装 GitHub CLI 后执行 gh auth login\n"
            "  2) setx GITHUB_TOKEN <你的 PAT>\n"
            "  3) git 已保存 github.com 凭据（credential.helper=store）"
        )
    repo = git_remote_repo()
    log("仓库 %s  tag win64-v%s" % (repo, ver))
    rel = get_or_create_release(repo, token, ver)
    rid = int(rel.get("id") or 0)
    if not rid:
        die("拿不到 release id")
    sha = Path(str(zp) + ".sha256")
    if not sha.exists():
        digest = hashlib.sha256(zp.read_bytes()).hexdigest()
        sha.write_text("%s  %s\n" % (digest, zp.name), encoding="utf-8")
    delete_asset_if_exists(repo, token, rel, zp.name)
    delete_asset_if_exists(repo, token, rel, sha.name)
    # DELETE 后 rel.assets 已过期，但按名字删即可
    upload_file(repo, token, rid, sha, "text/plain")
    # 刷新 assets 再传 zip（避免重名）
    rel = get_or_create_release(repo, token, ver)
    delete_asset_if_exists(repo, token, rel, zp.name)
    upload_file(repo, token, rid, zp, "application/zip")
    log("Release 页: https://github.com/%s/releases/tag/win64-v%s" % (repo, ver))


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="终焉之门 Windows 离线版一键打包")
    p.add_argument("--upload", action="store_true", help="打包后上传 GitHub Release")
    p.add_argument("--upload-only", action="store_true", help="只上传已有 zip")
    p.add_argument("--skip-sync", action="store_true", help="不从 dist 同步 game/")
    p.add_argument("--skip-build", action="store_true", help="不跑 electron-builder")
    p.add_argument("--skip-runtime", action="store_true",
                   help="不下载/不并入自带运行时（玩家首启需联网拉引擎 WASM）")
    p.add_argument("--runtime-only", action="store_true",
                   help="只下载离线运行时镜像到 game_engine/，不打包")
    p.add_argument("--dist-only", action="store_true",
                   help="云端用：把 dist/ 打成快照上传 Release dist-snapshot（供本机自动拉取）")
    p.add_argument("--no-fetch-dist", action="store_true",
                   help="本机缺 dist/ 时不自动从 Release 拉快照（直接报错）")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    ver = read_version()
    log("version %s" % ver)
    log("shell %s" % SHELL)
    if args.upload_only:
        upload_release(ver)
        return 0
    if args.runtime_only:
        download_runtime()
        return 0
    if args.dist_only:
        upload_dist_snapshot(ver)
        return 0
    if not args.skip_runtime:
        download_runtime()
    else:
        log("跳过离线运行时（--skip-runtime）")
    if not args.skip_sync:
        if not args.no_fetch_dist:
            ensure_dist(ver)
        sync_dist()
    else:
        if not (GAME / "index.html").exists():
            die("game/index.html 不存在，不能 --skip-sync")
        log("跳过 dist 同步")
    if not args.skip_build:
        run_builder()
    else:
        log("跳过 electron-builder")
    make_zip(ver)
    if args.upload:
        upload_release(ver)
    else:
        log("本地打包完成。上传请加 --upload，或双击 pack_and_upload.bat")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        die("已取消", 130)
