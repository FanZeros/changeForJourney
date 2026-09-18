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
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile
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
    # 去预览桥
    out = []
    for line in html.splitlines(True):
        if "__preview-bridge.js" in line:
            continue
        if 'id="watermark-logo"' in line:
            continue
        out.append(line)
    html = "".join(out)
    if "fab-main" not in html:
        html = html.replace("  </style>", CSS_HIDE + "  </style>", 1)
    if "PatchedWS" not in html:
        html = html.replace("</head>", HEAD_SCRIPTS + "</head>", 1)
    html = html.replace(
        'src="https://tapcode-sce.spark.xd.com/src/web/src/index.min.js"',
        'src="https://tapcode-sce.spark.xd.com/src/web/src/index.min.js" crossorigin="anonymous"',
    )
    # 上面 replace 可能重复加 crossorigin
    html = html.replace(
        'crossorigin="anonymous" crossorigin="anonymous"',
        'crossorigin="anonymous"',
    )
    return html


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
    log("已打补丁：去桥 / 去水印 / 免登录 shim / 隐藏 eruda")


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
    return p.parse_args()


def main() -> int:
    args = parse_args()
    ver = read_version()
    log("version %s" % ver)
    log("shell %s" % SHELL)
    if args.upload_only:
        upload_release(ver)
        return 0
    if not args.skip_sync:
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
