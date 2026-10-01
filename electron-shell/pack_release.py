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
import re
import shutil
import subprocess
import sys
import time
import zipfile
import zlib
from pathlib import Path
from urllib.parse import urlparse, urlunparse
from urllib.request import Request, urlopen, build_opener, install_opener, ProxyHandler
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
    # Windows 凭据管理器 / macOS 钥匙串等由 git 凭据助手管理——走 git credential fill
    git = shutil.which("git") or shutil.which("git.exe")
    if git:
        try:
            out = subprocess.run(
                [git, "credential", "fill"],
                input="protocol=https\nhost=github.com\n\n",
                capture_output=True, text=True, timeout=15,
            ).stdout
            for line in out.splitlines():
                if line.startswith("password="):
                    tok = line[len("password="):].strip()
                    if tok:
                        return tok
        except Exception:
            pass
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
    # 去预览桥 / 去水印：只删标签本身，保留同行其余内容（bridge 的 <script> 常与 </head> 同行！）
    out = []
    for line in html.splitlines(True):
        if 'id="watermark-logo"' in line:
            continue
        if "__preview-bridge.js" in line:
            line = re.sub(r"<script[^>]*__preview-bridge\.js[^>]*></script>\s*", "", line)
            if not line.strip():
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
    # ---- 失配校验：手术任何一环没生效就直接报错（曾因静默失配产出坏包） ----
    problems = []
    if "终焉之门·单机版" not in html:
        problems.append("标题替换未生效（<title> 模板变了）")
    if "__preview-bridge" in html:
        problems.append("预览桥未移除")
    if "</head>" not in html:
        problems.append("</head> 丢失（去桥误删）")
    if "PatchedWS" not in html:
        problems.append("免登录 WS shim 未注入（</head> 锚失配）")
    if 'id="loading-logo" crossorigin' not in html:
        problems.append("loading-logo crossorigin 未加（模板变了）")
    if "https://tapcode-sce.spark.xd.com/src/web/src/index.min.js" in html:
        problems.append("index.min.js 仍指向 CDN（未本地化）")
    if problems:
        die("index.html 手术校验失败：\n  - " + "\n  - ".join(problems))
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


def dist_snapshot_name(ver: str) -> str:
    """dist-{ver}-{commit短hash}.zip——hash 进文件名，避免 CDN 同名缓存取到旧快照。"""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"], cwd=str(ROOT),
            capture_output=True, text=True, timeout=15,
        )
        h = out.stdout.strip()
        if h:
            return "dist-%s-%s.zip" % (ver, h)
    except Exception:
        pass
    return "dist-%s.zip" % ver


def pick_latest_snapshot_asset(assets: list, ver: str) -> str:
    """从 Release 资产里挑 dist-{ver}-* 系列最新的一个（按 updated_at）。"""
    import re as _re
    cands = []
    pat = _re.compile(r"^dist-%s-[0-9a-f]{7,}\.zip$" % _re.escape(ver))
    legacy = "dist-%s.zip" % ver
    for a in assets or []:
        name = a.get("name") or ""
        if pat.match(name):
            cands.append((a.get("updated_at") or "", name))
        elif name == legacy:
            cands.append((a.get("updated_at") or "", name))
    if not cands:
        return ""
    cands.sort()
    return cands[-1][1]


def list_release_assets():
    """匿名拉取 Release 资产列表；失败返回 []。"""
    api = "https://api.github.com/repos/%s/releases/tags/%s" % (git_remote_repo(), DIST_SNAPSHOT_TAG)
    try:
        with urlopen(Request(api, headers={"User-Agent": "zyjm-pack-release"}), timeout=60) as resp:
            return json.loads(resp.read().decode()).get("assets") or []
    except Exception:
        return []


def download_asset_to(url: str, dest: Path, resume_hint: bool = True) -> None:
    """单个资产下载（断点续传 + 重试 + 大小校验），供完整包/分片共用。"""
    expected = None
    ok = False
    for attempt in range(1, 9):
        have = dest.stat().st_size if dest.exists() else 0
        headers = {"User-Agent": "zyjm-pack-release"}
        if have:
            headers["Range"] = "bytes=%d-" % have
            if expected and have < expected:
                log("  第 %d 次续传：从 %.0f/%.0f MB 继续…" % (attempt, have / 1048576, expected / 1048576))
        req = Request(url, headers=headers)
        try:
            with urlopen(req, timeout=120) as resp:
                status = getattr(resp, "status", 200)
                if expected is None:
                    cl = resp.headers.get("Content-Length")
                    if cl:
                        expected = have + int(cl) if status == 206 else int(cl)
                append = bool(headers.get("Range")) and status == 206
                with dest.open("ab" if append else "wb") as out:
                    while True:
                        chunk = resp.read(1 << 20)
                        if not chunk:
                            break
                        out.write(chunk)
        except HTTPError as e:
            if e.code == 404:
                raise FileNotFoundError(url)
            if e.code == 416:  # Range 越界：残档可能已完整或超界
                size = dest.stat().st_size if dest.exists() else 0
                if expected and size >= expected:
                    ok = True
                    break
                dest.unlink(missing_ok=True)  # 无法判定则删档重下
                expected = None
                continue
            log("  下载中断（HTTP %s），3s 后重试…" % e.code)
            time.sleep(3)
            continue
        except (URLError, OSError) as e:
            log("  下载中断（%s），3s 后重试…" % e)
            time.sleep(3)
            continue
        size = dest.stat().st_size if dest.exists() else 0
        if expected and size < expected:
            log("  下载不完整 %.0f/%.0f MB，重试…" % (size / 1048576, expected / 1048576))
            time.sleep(3)
            continue
        ok = True
        break
    if not ok:
        die("下载多次仍不完整：%s（已保留残档，重跑自动续传）" % dest.name)


def download_dist_snapshot(ver: str) -> None:
    repo = git_remote_repo()
    # 匿名列 Release 资产，选 dist-{ver}-* 最新（带 commit hash 的文件名天然防旧缓存）
    assets = list_release_assets()
    snap_name, _remote = fetch_latest_snapshot_info(ver)
    if not snap_name:
        die("无法获取云端快照列表（api.github.com 与 github.com 均不可达）。\n"
            "  请检查本机网络（可先在浏览器打开 https://github.com/%s/releases/tag/%s 验证）后重跑。" % (repo, DIST_SNAPSHOT_TAG))
    name = snap_name
    url = "https://github.com/%s/releases/download/%s/%s" % (repo, DIST_SNAPSHOT_TAG, name)
    tmp = RELEASE / name
    tmp.parent.mkdir(parents=True, exist_ok=True)

    # 分片优先：云端可能只有 name.partNN 系列片（完整单连接传不完大包）
    part_names = sorted(a["name"] for a in assets
                        if a.get("name", "").startswith(name + ".part"))
    if part_names:  # 分片模式：下方逐片下载合并，跳过完整包下载
        log("云端为分片快照（%d 片），逐片下载合并…" % len(part_names))
        tmp.unlink(missing_ok=True)
        parts_dir = RELEASE / "snapshot_parts"
        parts_dir.mkdir(parents=True, exist_ok=True)
        with tmp.open("wb") as out:
            for pn in part_names:
                purl = "https://github.com/%s/releases/download/%s/%s" % (repo, DIST_SNAPSHOT_TAG, pn)
                pdest = parts_dir / pn  # 独立子目录：避免与云端切片工作文件(release/*.partNN)同名冲突
                log("  下载 %s" % pn)
                download_asset_to(purl, pdest)
                shutil.copyfileobj(pdest.open("rb"), out, 1 << 20)
        log("分片合并完成")

    if not part_names:
        try:
            download_asset_to(url, tmp)
        except FileNotFoundError:
            die("dist 快照不存在：%s\n"
                "  云端还没上传（tag=%s）。请让云端会话 Build 后执行\n"
                "  python pack_release.py --dist-only 上传，或核对 package.json version。" % (url, DIST_SNAPSHOT_TAG))
    # 完整性：zip 中心目录必须有效（截断的 zip 在此报错，删除残档让下次重下）
    try:
        with zipfile.ZipFile(tmp) as zf:
            n = len(zf.namelist())
    except zipfile.BadZipFile:
        tmp.unlink(missing_ok=True)
        die("下载内容不是有效 zip（可能截断/被网关污染），已删除，请重跑本脚本。")
    log("下载完成 %.0f MB（%d 条目），解压到 dist/ …" % (tmp.stat().st_size / 1048576, n))
    # 统一走 staging：无论 zip 布局（有/无单层根目录）都正确落到 dist/
    target = ROOT / "dist"
    stage = ROOT / ".tmp_dist_stage"
    shutil.rmtree(stage, ignore_errors=True)
    with zipfile.ZipFile(tmp) as zf:
        zf.extractall(stage)
    entries = [p for p in stage.iterdir()]
    src = entries[0] if (len(entries) == 1 and entries[0].is_dir()) else stage
    if target.exists():
        try:
            shutil.rmtree(target)
        except OSError:
            backup = ROOT / ("dist.old-%d" % int(time.time()))
            os.rename(str(target), str(backup))
            log("WARN 旧 dist/ 无法完全删除（权限/占用），已改名 %s（确认无用后可手动删）" % backup.name)
    shutil.move(str(src), str(target))
    shutil.rmtree(stage, ignore_errors=True)
    tmp.unlink(missing_ok=True)
    if not (target / "index.html").exists():
        die("dist 快照解压后没有 index.html，内容异常")
    # 写来源指纹（供 ensure_dist 下次比对云端是否更新）
    m = re.match(r"^dist-%s-([0-9a-f]{7,})\.zip$" % re.escape(ver), name)
    try:
        (target / "snapshot-meta.json").write_text(
            json.dumps({
                "commit": m.group(1) if m else "",
                "snapshot": name,
                "version": ver,
                "fetchedAt": time.strftime("%Y-%m-%dT%H:%M:%S"),
            }, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except Exception:
        pass
    log("dist/ 就绪（来自快照 %s）" % name)


def fetch_latest_snapshot_info(ver: str):
    """返回 (最新资产名, commit短hash|None)；两路都不可达返回 (None, None)。
    路径1: api.github.com 列资产（需可达）；路径2: github.com/expanded_assets HTML
    （国内对 api.github.com 常不可达而主站可达，作为回退）。
    两路都失败时自动探测本机常见代理端口（浏览器能开而脚本不通=没走代理），探测成功重试一轮。"""
    def from_api():
        api = "https://api.github.com/repos/%s/releases/tags/%s" % (git_remote_repo(), DIST_SNAPSHOT_TAG)
        with urlopen(Request(api, headers={"User-Agent": "zyjm-pack-release"}), timeout=45) as resp:
            rel = json.loads(resp.read().decode())
        return pick_latest_snapshot_asset(rel.get("assets"), ver)

    def from_expanded_assets():
        url = "https://github.com/%s/releases/expanded_assets/%s" % (git_remote_repo(), DIST_SNAPSHOT_TAG)
        with urlopen(Request(url, headers={"User-Agent": "zyjm-pack-release"}), timeout=45) as resp:
            html = resp.read().decode("utf-8", errors="replace")
        names = re.findall(r"dist-%s-[0-9a-f]{7,}\.zip" % re.escape(ver), html)
        # expanded_assets 列表最新在前（含重复引用），取第一个
        return names[0] if names else ""

    def try_both():
        """返回 (name, saw_list)：saw_list=至少一路网络可达（区别"网络不通"与"列表为空"）。"""
        saw_list = False
        for attempt, fetcher in enumerate((from_api, from_expanded_assets), 1):
            try:
                name = fetcher()
                saw_list = True
                if name:
                    return name, True
            except Exception as e:
                log("WARN 快照列表获取失败（路径%d: %s），尝试下一路径…" % (attempt, e))
        return "", saw_list

    name, saw_list = try_both()
    if not saw_list and probe_and_install_proxy():
        log("代理已启用，重试快照列表获取…")
        name, saw_list = try_both()
    if not name:
        if saw_list:
            die("云端 Release %s 可达，但没有任何 dist-%s-*.zip 快照资产。\n"
                "  请让云端会话执行 python pack_release.py --dist-only 上传最新快照。" % (DIST_SNAPSHOT_TAG, ver))
        die("无法获取云端快照列表（api.github.com 与 github.com 均不可达）。\n"
            "  浏览器能打开而本脚不行 → 你开着系统代理而脚本直连。\n"
            "  处理：python pack_release.py --proxy http://127.0.0.1:7890 （换成你的代理端口）\n"
            "  或先在浏览器打开 https://github.com/FanZeros/changeForJourney/releases/tag/dist-snapshot 验证网络。")
    m = re.match(r"^dist-%s-([0-9a-f]{7,})\.zip$" % re.escape(ver), name)
    return name, (m.group(1) if m else None)


PROXY_CLI = None  # --proxy 参数（main 设置）
PROXY_CANDIDATES = (
    "http://127.0.0.1:7890",   # Clash
    "http://127.0.0.1:7897",   # Clash Verge Rev
    "http://127.0.0.1:10809",  # v2rayN http
    "http://127.0.0.1:1080",   # 通用 socks/http
    "http://127.0.0.1:8118",   # privoxy
    "http://127.0.0.1:8888",   # mitm/fiddler 常用
)


def probe_and_install_proxy() -> bool:
    """直连失败后探测可用代理（--proxy > 环境变量 > 常见端口），成功则安装全局 opener。"""
    tried = []
    if PROXY_CLI:
        tried.append(PROXY_CLI)
    else:
        envp = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy") \
            or os.environ.get("HTTP_PROXY") or os.environ.get("http_proxy")
        if envp:
            tried.append(envp.strip())
        tried.extend(PROXY_CANDIDATES)
    for px in tried:
        try:
            op = build_opener(ProxyHandler({"http": px, "https": px}))
            with op.open(Request("https://github.com/", headers={"User-Agent": "zyjm-pack-release"}), timeout=6) as r:
                if r.status in (200, 301, 302):
                    install_opener(op)
                    log("检测到可用代理 %s，后续请求已切换走代理" % px)
                    return True
        except Exception:
            continue
    log("WARN 常见本地代理端口均不可用，仍为直连")
    return False


def read_local_snapshot_commit() -> "str | None":
    """本机 dist 的来源 commit（拉取成功时写入 dist/snapshot-meta.json）。"""
    p = ROOT / "dist" / "snapshot-meta.json"
    if not p.exists():
        return None
    try:
        return (json.loads(p.read_text(encoding="utf-8")).get("commit") or "").strip() or None
    except Exception:
        return None


def ensure_dist(ver: str) -> None:
    """保证本机 dist 与云端最新快照一致：
    - 本机无 dist → 拉
    - 有 dist 且带 meta：commit 与云端最新一致 → 跳过；不一致/云端不可达本地无指纹 → 重拉
    - 有 dist 但无 meta（旧版拉的/手动放的，来源不明）→ 重拉一次（拉取后写入 meta，此后可比对）
    """
    if not (ROOT / "dist" / "index.html").exists():
        download_dist_snapshot(ver)
        return
    snap_name, remote_commit = fetch_latest_snapshot_info(ver)  # 失败会 die（避免静默用过期 dist）
    local_commit = read_local_snapshot_commit()
    if local_commit and remote_commit and local_commit == remote_commit:
        log("dist/ 已是云端最新快照（commit %s）" % local_commit)
        return
    log("本机 dist 落后云端（本机 %s / 云端 %s）→ 重新拉取 %s" %
        (local_commit or "无指纹", remote_commit or snap_name, snap_name))
    download_dist_snapshot(ver)


# ---- 旧版解压 bug 的散落清理（幂等） ----
# 旧逻辑把无单层根的 zip extractall(ROOT)，产物散落到仓库根：
#   index.html / latest.json / 1.x.x.json / env.json、1.0.2/ 等版本目录、
#   assets/ 混入 hash 产物（如 Auvzyb9O1qsQ1hKZcs3Amp5Y-66e4c3d7.py）、project.json 被覆盖。
SPILL_TOP_FILES = ("index.html", "latest.json", "1.x.x.json", "env.json")
HASH_PRODUCT = re.compile(r"^.+-[0-9a-f]{8}\.[A-Za-z0-9]+$")


def clean_dist_spill() -> None:
    removed = 0
    for n in SPILL_TOP_FILES:
        p = ROOT / n
        if p.exists():
            p.unlink()
            removed += 1
    for p in ROOT.iterdir():
        if p.is_dir() and re.match(r"^\d+\.\d+\.\d+", p.name) \
                and ((p / "manifest-origin.json").exists() or (p / "version.json").exists()):
            shutil.rmtree(p)
            removed += 1
    assets = ROOT / "assets"
    if assets.is_dir():
        git = shutil.which("git") or shutil.which("git.exe")
        if git:
            out = subprocess.run(
                [git, "ls-files", "--others", "--exclude-standard", "--", "assets"],
                cwd=str(ROOT), capture_output=True, text=True, timeout=60,
            ).stdout
            for rel in out.splitlines():
                rel = rel.strip().replace("/", os.sep)
                if rel and HASH_PRODUCT.match(os.path.basename(rel)):
                    fp = ROOT / rel
                    if fp.exists():
                        fp.unlink()
                        removed += 1
    pj = ROOT / "project.json"
    git = shutil.which("git") or shutil.which("git.exe")
    if pj.exists() and git:
        out = subprocess.run(
            [git, "status", "--porcelain", "--", "project.json"],
            cwd=str(ROOT), capture_output=True, text=True, timeout=30,
        ).stdout
        tracked_modified = any(l[:2].strip() == "M" for l in out.splitlines())
        if tracked_modified:  # 仅 tracked 且被改动才还原（untracked 时 checkout 会报 pathspec 错）
            subprocess.run([git, "checkout", "--", "project.json"], cwd=str(ROOT), timeout=30)
            removed += 1
    if removed:
        log("清理旧版解压散落产物 %d 项（仓库根恢复干净）" % removed)


def upload_dist_snapshot(ver: str) -> None:
    """云端用：把 dist/ 打成 dist-{ver}.zip 上传到 Release dist-snapshot。"""
    dist = ROOT / "dist"
    if not (dist / "index.html").exists():
        die("没有 dist/，先 Build")
    token = github_token()
    if not token:
        die("找不到 GitHub token")
    repo = git_remote_repo()
    out = RELEASE / dist_snapshot_name(ver)
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
    # 清理本版本旧快照（保留刚上传的），避免 CDN 同名缓存与资产堆积
    prefix_new = out.name
    for a in rel.get("assets") or []:
        an = a.get("name") or ""
        if an != prefix_new and (an.startswith("dist-%s-" % ver) or an == "dist-%s.zip" % ver):
            delete_asset_if_exists(repo, token, rel, an)
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


def verify_local_dist() -> None:
    """仅本地模式：确认 dist 是当前项目源码的完整构建，而非旧快照。"""
    if not (DIST / "index.html").is_file():
        die("本地 dist/index.html 不存在；先在 Maker 中 Build 当前分支")
    project = json.loads((ROOT / ".project" / "project.json").read_text(encoding="utf-8"))
    version = str(project["version"])
    manifest_path = DIST / version / "manifest-origin.json"
    if not manifest_path.is_file():
        die("本地 dist 缺少 %s；先在 Maker 中 Build 当前分支" % manifest_path.relative_to(DIST))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    lua_files = [item for item in manifest["files"] if item.get("ext") == ".lua" and item.get("prefix") == "../scripts"]
    errors = []
    built_paths = set()
    for item in lua_files:
        path = item["fs_path"]
        built_paths.add(path)
        source = ROOT / "scripts" / path
        built = DIST / "assets" / (item["uuid"] + "-" + item["hash"] + ".lua")
        if not source.is_file() or not built.is_file() or source.read_bytes() != built.read_bytes():
            errors.append(path)
    source_paths = {p.relative_to(ROOT / "scripts").as_posix() for p in (ROOT / "scripts").rglob("*.lua")}
    errors.extend(sorted(source_paths - built_paths))
    if "main.lua" not in built_paths or errors:
        die("本地 dist 与当前源码不一致（%d 项，示例：%s）；请重新 Build，勿用旧快照" %
            (len(errors), ", ".join(errors[:5])))
    log("本地 dist 校验通过：项目 v%s、%d 个 Lua 文件与源码一致" % (version, len(lua_files)))


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
    p.add_argument("--local-dist", action="store_true",
                   help="仅用当前源码构建的本地 dist；校验全部 Lua，不拉快照、不清理仓库根、不上传")
    p.add_argument("--proxy", default=None, metavar="URL",
                   help="访问 GitHub 用的 HTTP 代理（如 http://127.0.0.1:7890）；"
                        "不指定时直连失败会自动探测常见本地代理端口（7890/7897/10809/1080…）")
    return p.parse_args()


def main() -> int:
    global PROXY_CLI
    args = parse_args()
    if args.local_dist and (args.upload or args.upload_only or args.dist_only or args.runtime_only or args.skip_sync or args.skip_build):
        die("--local-dist 不能与上传、跳过同步/构建或仅运行时模式组合")
    PROXY_CLI = (args.proxy or "").strip() or None
    ver = read_version()
    log("version %s" % ver)
    log("shell %s" % SHELL)
    if args.local_dist:
        verify_local_dist()
    else:
        clean_dist_spill()
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
        if not (args.no_fetch_dist or args.local_dist):
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
