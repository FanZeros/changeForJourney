#!/usr/bin/env python3
"""天赋星图连线编辑器。

读取 TalentStarMap.lua 的节点，浏览器里点两个节点加边或删边。
保存时只改两处 adj，并要求改完后仍是双向、无自环、全图连通。

用法（在 /workspace 下）:
    python3 tools/talent-editor/server.py
然后打开 http://127.0.0.1:8765
"""

import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STAR = ROOT / "scripts/ui/church/talent/TalentStarMap.lua"
DEFS = ROOT / "scripts/shared/talent/TalentNodeDefs.lua"
HTML = Path(__file__).with_name("index.html")

NODE_RE = re.compile(
    r'^(\s*)\[(\d+)\]\s*=\s*\{(.*?)adj\s*=\s*\{([^}]*)\}(.*)$'
)


def parse_star(text):
    nodes = []
    for line in text.splitlines():
        m = NODE_RE.match(line)
        if not m:
            continue
        body = m.group(3) + m.group(5)
        name = re.search(r'name="([^"]*)"', body)
        gx = re.search(r'gx=(-?[\d.]+)', body)
        gy = re.search(r'gy=(-?[\d.]+)', body)
        st = re.search(r'st="([^"]+)"', body)
        color = re.search(r'color="([^"]+)"', body)
        if not (name and gx and gy):
            continue
        adj = [int(x) for x in m.group(4).split(",") if x.strip()]
        nodes.append({
            "id": int(m.group(2)),
            "name": name.group(1),
            "gx": float(gx.group(1)),
            "gy": float(gy.group(1)),
            "st": st.group(1) if st else "small",
            "color": color.group(1) if color else "无",
            "adj": adj,
        })
    return nodes


def replace_adj(text, adj_by_id, spaced):
    """只替换每个节点行里的 adj={...}，其余字节不动。"""
    out = []
    seen = set()
    for line in text.splitlines(keepends=True):
        raw = line[:-1] if line.endswith("\n") else line
        nl = line[len(raw):]
        m = NODE_RE.match(raw)
        if not m:
            out.append(line)
            continue
        nid = int(m.group(2))
        if nid not in adj_by_id:
            raise ValueError(f"文件里有节点 {nid}，但保存数据没有它")
        old_ids = [int(x) for x in m.group(4).split(",") if x.strip()]
        new_ids = list(adj_by_id[nid])
        # 邻居集合没变就保留原来的书写顺序和空格，避免无意义 diff
        same = old_ids == new_ids or (sorted(old_ids) == sorted(new_ids) and len(old_ids) == len(set(new_ids)))
        if same:
            out.append(line)
            seen.add(nid)
            continue
        ids = ", ".join(str(x) for x in new_ids) if spaced else ",".join(str(x) for x in new_ids)
        raw = raw[:m.start(4)] + ids + raw[m.end(4):]
        out.append(raw + nl)
        seen.add(nid)
    missing = sorted(set(adj_by_id) - seen)
    if missing:
        raise ValueError("这些节点在文件里找不到: " + ", ".join(map(str, missing[:12])))
    return "".join(out), seen


def validate(adj_by_id):
    ids = set(adj_by_id)
    if 0 not in ids:
        return "缺少起始点 0"
    for nid, nbs in adj_by_id.items():
        if len(nbs) != len(set(nbs)):
            return f"节点 {nid} 有重复邻居"
        for nb in nbs:
            if nb == nid:
                return f"节点 {nid} 连到了自己"
            if nb not in ids:
                return f"节点 {nid} 连到不存在的 {nb}"
            if nid not in adj_by_id[nb]:
                adj_by_id[nb].append(nid)
                adj_by_id[nb].sort()
    seen = set()
    stack = [0]
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        stack.extend(adj_by_id[cur])
    if seen != ids:
        lost = sorted(ids - seen)
        return f"全图不连通，断开 {len(lost)} 个，例如 {lost[:8]}"
    return None


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, content_type):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.split("?", 1)[0] == "/api/graph":
            nodes = parse_star(STAR.read_text(encoding="utf-8"))
            self._send(200, json.dumps({"nodes": nodes}, ensure_ascii=False), "application/json")
            return
        if self.path.split("?", 1)[0] in ("/", "/index.html"):
            self._send(200, HTML.read_bytes(), "text/html; charset=utf-8")
            return
        self._send(404, "not found", "text/plain")

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/api/save":
            self._send(404, "not found", "text/plain")
            return
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        raw = payload.get("adj") or {}
        adj = {int(k): [int(x) for x in v] for k, v in raw.items()}
        for nbs in adj.values():
            nbs.sort()
        err = validate(adj)
        if err:
            self._send(400, json.dumps({"error": err}, ensure_ascii=False), "application/json")
            return
        try:
            star_txt, star_ids = replace_adj(STAR.read_text(encoding="utf-8"), adj, False)
            defs_txt, defs_ids = replace_adj(DEFS.read_text(encoding="utf-8"), adj, True)
        except ValueError as exc:
            self._send(400, json.dumps({"error": str(exc)}, ensure_ascii=False), "application/json")
            return
        if star_ids != defs_ids:
            self._send(400, json.dumps({
                "error": "两个文件的节点集合不一致，已拒绝写入"
            }, ensure_ascii=False), "application/json")
            return
        STAR.write_text(star_txt, encoding="utf-8")
        DEFS.write_text(defs_txt, encoding="utf-8")
        self._send(200, json.dumps({
            "ok": True,
            "files": [str(STAR.relative_to(ROOT)), str(DEFS.relative_to(ROOT))],
            "nodes": len(adj),
        }, ensure_ascii=False), "application/json")

    def log_message(self, fmt, *args):
        print("[talent-editor]", fmt % args)


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 8765), Handler)
    print("天赋连线编辑器: http://127.0.0.1:8765")
    server.serve_forever()


if __name__ == "__main__":
    main()
