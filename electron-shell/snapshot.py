# ============================================================================
# snapshot.py — dist 快照一键托管（云端会话专用）
# 用途: 把本仓库根的 dist/（Maker Build 产物）打包并分片上传到 GitHub Release
#       tag=dist-snapshot，供本机 pack_release.py 自动拉取（无 Maker 环境也能打包）。
#
# 用法:
#   python electron-shell/snapshot.py                      # 全流程: 压缩 → 分片上传 → 清旧片
#   python electron-shell/snapshot.py --max-seconds 80     # 限时分批（沙箱/弱网: 反复重跑即断点续传）
#   python electron-shell/snapshot.py --zip-only           # 只压缩
#   python electron-shell/snapshot.py --upload-only        # 只上传（复用已有 zip）
#   python electron-shell/snapshot.py --proxy http://127.0.0.1:7890
#
# 设计要点:
#   - 分片 16MB/片: 单连接大 POST 会被代理劣化卡死，16MB 实测稳定
#   - 幂等: 已存在且大小一致的片跳过 → 反复重跑即断点续传
#   - 传完自动删除其它 commit 的旧片（防下载端混片）
#   - 产物: dist-{version}-{commit7}.zip.part00..NN（下载端 pack_release 按 sorted 合并）
# ============================================================================
from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time
import zipfile
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

SHELL = Path(__file__).resolve().parent
ROOT = SHELL.parent
sys.path.insert(0, str(SHELL))
import pack_release as P  # noqa: E402  复用 log/die/github_token/git_remote_repo/Release 原语

CHUNK = 16 * 1024 * 1024
SEND_TIMEOUT = 25


def git_short_commit() -> str:
    out = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=str(ROOT),
                         capture_output=True, text=True, timeout=30).stdout.strip()
    if not out:
        P.die("拿不到 git commit（仓库根 %s）" % ROOT)
    return out


def make_zip(ver: str, commit: str) -> Path:
    name = "dist-%s-%s.zip" % (ver, commit)
    out = P.RELEASE / name
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        P.log("zip 已存在，跳过压缩: %s" % name)
        return out
    dist = ROOT / "dist"
    if not (dist / "index.html").exists():
        P.die("没有 dist/（先在 Maker 里 Build）")
    files = []
    for dirpath, _d, filenames in os.walk(str(dist)):
        for fn in filenames:
            fp = Path(dirpath) / fn
            files.append((fp, fp.relative_to(dist).as_posix()))
    P.log("压缩 %d 文件 → %s …" % (len(files), name))
    meta = {"commit": commit, "version": ver, "asset": name,
            "builtAt": time.strftime("%Y-%m-%dT%H:%M:%S")}
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        zf.writestr("snapshot-meta.json", json.dumps(meta, indent=2))
        for i, (fp, arc) in enumerate(files, 1):
            zf.write(fp, arcname=arc)
            if i % 300 == 0 or i == len(files):
                P.log("  zip %d/%d" % (i, len(files)))
    P.log("zip 完成 %.0f MB（含 meta）" % (out.stat().st_size / 1048576))
    return out


def upload_parts(zip_path: Path, ver: str, commit: str, max_seconds: float) -> bool:
    """分片幂等上传。返回 True=全部完成（并已清旧片）。"""
    socket.setdefaulttimeout(SEND_TIMEOUT)
    base = zip_path.name
    repo = P.git_remote_repo()
    token = P.github_token()
    rel = P.get_or_create_release_tag(repo, token, P.DIST_SNAPSHOT_TAG,
                                      "dist 快照（供本机 pack_release 自动拉取）")
    rid = int(rel.get("id") or 0)

    # 切片（release/snapshot_parts_work/ 工作目录，幂等落盘）
    work = P.RELEASE / "snapshot_parts_work"
    work.mkdir(parents=True, exist_ok=True)
    parts = []
    with zip_path.open("rb") as f:
        idx = 0
        while True:
            chunk = f.read(CHUNK)
            if not chunk:
                break
            pn = "%s.part%02d" % (base, idx)
            pp = work / pn
            if not pp.exists() or pp.stat().st_size != len(chunk):
                pp.write_bytes(chunk)
            parts.append((pn, pp))
            idx += 1
    P.log("共 %d 片 × %d MB" % (len(parts), CHUNK // 1048576))
    have = dict((a["name"], a["size"]) for a in rel.get("assets", []))

    def upload_one(name: str, data: bytes) -> None:
        url = "https://uploads.github.com/repos/%s/releases/%s/assets?name=%s" % (repo, rid, name)
        req = Request(url, data=data, headers={
            "Authorization": "token " + token, "Accept": "application/vnd.github+json",
            "Content-Type": "application/octet-stream", "Content-Length": str(len(data)),
            "User-Agent": "zyjm-pack-release"}, method="POST")
        with urlopen(req, timeout=SEND_TIMEOUT) as resp:
            json.loads(resp.read().decode())

    t0 = time.time()
    for i, (pn, pp) in enumerate(parts):
        if have.get(pn) == pp.stat().st_size:
            continue  # 云端已有且大小一致 → 秒跳过（幂等续传核心）
        if time.time() - t0 > max_seconds:
            have_count = _cloud_part_count(base, repo, token)
            P.log("SNAPSHOT_PARTIAL: %d/%d（时限到）— 重跑本命令继续" % (have_count, len(parts)))
            return False
        ok = False
        for attempt in range(1, 4):
            try:
                upload_one(pn, pp.read_bytes())
                ok = True
                break
            except HTTPError as e:
                body = e.read().decode(errors="replace")[:200]
                if e.code == 422:  # 已存在
                    ok = True
                    break
                P.log("WARN 片 %d/%d HTTP %s（第 %d 次）: %s" % (i + 1, len(parts), e.code, attempt, body))
            except (URLError, OSError, TimeoutError) as e:
                P.log("WARN 片 %d/%d 超时/网络（第 %d 次）: %s" % (i + 1, len(parts), attempt, e))
            time.sleep(3)
        if not ok:
            have_count = _cloud_part_count(base, repo, token)
            P.log("SNAPSHOT_PARTIAL: %d/%d（片 %s 重试失败）— 重跑本命令继续" % (have_count, len(parts), pn))
            return False
        P.log("片 %d/%d OK (%.0fs)" % (i + 1, len(parts), time.time() - t0))
        time.sleep(1)

    _cleanup_other_commits(repo, token, rel, commit)
    P.log("SNAPSHOT_UPLOADED: %s（%d 片）" % (base, len(parts)))
    return True


def _cloud_part_count(base: str, repo: str, token: str) -> int:
    rel = _fetch_release(repo, token)
    if not rel:
        return -1
    return sum(1 for a in rel.get("assets", []) if a.get("name", "").startswith(base + ".part"))


def _fetch_release(repo: str, token: str) -> dict:
    url = "https://api.github.com/repos/%s/releases/tags/%s" % (repo, P.DIST_SNAPSHOT_TAG)
    try:
        with urlopen(Request(url, headers={
                "Authorization": "token " + token,
                "Accept": "application/vnd.github+json",
                "User-Agent": "zyjm-pack-release"}), timeout=60) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        P.log("WARN 列云端资产失败: %s" % e)
        return {}


def _cleanup_other_commits(repo: str, token: str, rel: dict, commit: str) -> None:
    """删除不属于当前 commit 的 dist-*.zip* 资产（旧快照/旧片），防下载端混片。"""
    assets = rel.get("assets", [])
    stale = [a["name"] for a in assets
             if a.get("name", "").startswith("dist-") and commit not in a["name"]]
    if not stale:
        return
    P.log("清理旧快照资产 %d 项（非 %s）…" % (len(stale), commit))
    for i, name in enumerate(stale, 1):
        P.delete_asset_if_exists(repo, token, rel, name)
        if i % 10 == 0:
            P.log("  已删 %d/%d" % (i, len(stale)))


def main() -> int:
    ap = argparse.ArgumentParser(description="dist 快照一键托管（压缩+分片上传+清旧）")
    ap.add_argument("--zip-only", action="store_true", help="只压缩")
    ap.add_argument("--upload-only", action="store_true", help="只上传（复用已有 zip）")
    ap.add_argument("--max-seconds", type=float, default=3600.0,
                    help="单次运行上传时限（秒）；到时打印进度退出，重跑续传。沙箱/弱网建议 80")
    ap.add_argument("--proxy", default=None, metavar="URL", help="HTTP 代理（弱网直连失败时）")
    args = ap.parse_args()

    if args.proxy and args.proxy.strip():
        global PROXY_CLI
        P.PROXY_CLI = args.proxy.strip()

    ver = P.read_version()
    commit = git_short_commit()
    P.log("version %s / commit %s" % (ver, commit))

    zip_path = None
    if not args.upload_only:
        zip_path = make_zip(ver, commit)
    if args.zip_only:
        return 0
    if zip_path is None:
        ver_commit = "dist-%s-%s.zip" % (ver, commit)
        zip_path = P.RELEASE / ver_commit
        if not zip_path.exists():
            P.die("找不到 %s（先跑一次不带 --upload-only）" % zip_path)
    upload_parts(zip_path, ver, commit, args.max_seconds)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
