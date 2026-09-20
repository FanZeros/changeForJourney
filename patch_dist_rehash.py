#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
patch_dist_rehash.py — CRC32 重哈希部署管线（遵循 docs/COLLABORATION.md 约定）

流程：scripts-src/ 源码 → 重哈希（CRC32 前 8 位 hex = 文件名哈希）→ 8 个 manifest 同步 hash/size → 资产文件增删

用法：
  python3 patch_dist_rehash.py --audit   # 只审计，不修改
  python3 patch_dist_rehash.py --apply   # 执行重哈希并写盘
"""
import json, zlib, os, sys, argparse

REPO = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(REPO, 'scripts-src')
ASSETS = os.path.join(REPO, 'assets')

MANIFESTS = [
    '1.0.7/manifest-35b07c52.json',  # client 分发
    '1.0.7/manifest-9908d802.json',  # server 分发
    '1.0.7/manifest-origin.json',
    '1.0.7/manifest-origin.b1.json',
]

def crc8(content: bytes) -> str:
    return format(zlib.crc32(content) & 0xffffffff, '08x')

def load_all():
    data = {}
    for rel in MANIFESTS:
        with open(os.path.join(REPO, rel), 'rb') as fh:
            data[rel] = json.load(fh)
    return data

def audit(data):
    """返回 (stale, missing, new_scripts)
    stale: {(fs_path): {manifest: [entry_idx, ...]}}  内容与 manifest 不一致
    missing: [(manifest, fs_path)]  manifest 引用但 scripts-src 无源
    new_scripts: {fs_path: [content_bytes]}  scripts-src 有但任何 client/origin manifest 未收录
    """
    stale, missing, seen = {}, [], set()
    for rel, d in data.items():
        for idx, f in enumerate(d['files']):
            fp = f['fs_path']
            if f['ext'] == '.lua':
                seen.add(fp)
                src = os.path.join(SCRIPTS, fp)
                if not os.path.exists(src):
                    missing.append((rel, fp))
                    continue
                content = open(src, 'rb').read()
                if crc8(content) != f['hash'] or len(content) != f['size']:
                    stale.setdefault(fp, {}).setdefault(rel, []).append(idx)
    # scripts-src 中未被收录的 lua（相对任何 manifest）
    all_lua = set()
    for root, dirs, files in os.walk(SCRIPTS):
        for name in files:
            if name.endswith('.lua'):
                all_lua.add(os.path.relpath(os.path.join(root, name), SCRIPTS))
    new_scripts = {fp for fp in all_lua - seen}
    return stale, missing, new_scripts

def entry_uuid_for_new(data, maker_manifest=None):
    """为新增脚本自造 22 位 base64url uuid（COLLABORATION.md 约定四）"""
    import base64, secrets
    made = {}
    def gen(fp):
        if fp not in made:
            made[fp] = base64.urlsafe_b64encode(secrets.token_bytes(16)).decode().rstrip('=')
        return made[fp]
    return gen

def entry_style(d):
    """判断 manifest 条目风格：分发版(groups) vs origin 版(prefix)"""
    for f in d['files'][:200]:
        if 'prefix' in f:
            return 'prefix'
        if 'groups' in f:
            return 'groups'
    return 'groups'

def apply(data, new_uuid_of, new_scripts=frozenset()):
    changed_files = []   # (uuid, oldhash, newhash, ext, content, fs_path)
    added_entries = []   # (manifest, fs_path, uuid)
    removed_assets = set()

    for rel in MANIFESTS:
        d = data[rel]
        for idx, f in enumerate(d['files']):
            fp = f['fs_path']
            if f['ext'] != '.lua':
                continue
            src = os.path.join(SCRIPTS, fp)
            if not os.path.exists(src):
                continue
            content = open(src, 'rb').read()
            crc = crc8(content)
            if crc != f['hash'] or len(content) != f['size']:
                changed_files.append((f['uuid'], f['hash'], crc, f['ext'], content, fp))
                removed_assets.add((f['uuid'], f['hash'], f['ext']))
                f['hash'] = crc
                f['size'] = len(content)

    # 新增脚本条目：8 个 manifest 全部加入（与现有全量收录结构一致）
    if new_scripts:
        for rel in MANIFESTS:
            d = data[rel]
            have = {f['fs_path'] for f in d['files']}
            style = entry_style(d)
            for fp in sorted(new_scripts):
                if fp in have:
                    continue
                content = open(os.path.join(SCRIPTS, fp), 'rb').read()
                uuid = new_uuid_of(fp)
                if not uuid:
                    raise RuntimeError(f'无可用 uuid for {fp}')
                entry = {'uuid': uuid, 'ext': '.lua', 'hash': crc8(content), 'size': len(content)}
                if style == 'groups':
                    entry['groups'] = ['default', '#blocking']
                    entry['fs_path'] = fp
                else:
                    entry['fs_path'] = fp
                    entry['prefix'] = '../scripts'
                d['files'].append(entry)
                added_entries.append((rel, fp, uuid))
                changed_files.append((uuid, None, entry['hash'], '.lua', content, fp))

    # 写资产文件
    os.makedirs(ASSETS, exist_ok=True)
    for uuid, oldhash, newhash, ext, content, fp in changed_files:
        with open(os.path.join(ASSETS, f'{uuid}-{newhash}{ext}'), 'wb') as fh:
            fh.write(content)

    # 写 manifest：保持 1.0.7 现有 pretty-print（2 空格缩进）
    for rel, d in data.items():
        raw = json.dumps(d, ensure_ascii=False, indent=2).encode('utf-8') + b'\n'
        with open(os.path.join(REPO, rel), 'wb') as fh:
            fh.write(raw)

    # 删除被替换的旧资产文件（8 manifest 已全部更新，无引用才删）
    removed = []
    if removed_assets:
        for (uuid, oldhash, ext) in removed_assets:
            if oldhash is None:
                continue
            path = os.path.join(ASSETS, f'{uuid}-{oldhash}{ext}')
            if os.path.exists(path):
                os.remove(path)
                removed.append(f'{uuid}-{oldhash}{ext}')
    return changed_files, added_entries, removed

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--audit', action='store_true')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--maker-manifest', default='/workspace/dist/1.0.2/manifest-00de1e48.json')
    args = ap.parse_args()

    data = load_all()
    stale, missing, new_scripts = audit(data)

    print(f'== 审计 ==')
    print(f'过期 lua 条目覆盖的 fs_path: {len(stale)}')
    for fp in sorted(stale):
        mans = ', '.join(sorted(stale[fp]))
        print(f'  {fp}  [{mans}]')
    if missing:
        print(f'!! manifest 引用但源缺失: {len(missing)}')
        for rel, fp in missing[:10]:
            print(f'  {rel}: {fp}')
    print(f'scripts-src 未收录的新脚本: {sorted(new_scripts) if new_scripts else "无"}')

    if args.apply:
        get_uuid = entry_uuid_for_new(data, args.maker_manifest)
        changed, added, removed = apply(data, get_uuid, new_scripts)
        print(f'\n== 应用 ==')
        print(f'更新条目: {len(changed)}  新增条目: {len(added)}  删除旧资产: {len(removed)}')
        for rel, fp, uuid in added:
            print(f'  + {rel}: {fp} uuid={uuid}')
        for r in removed[:20]:
            print(f'  - {r}')
        if len(removed) > 20:
            print(f'  ... 等共 {len(removed)} 个')

if __name__ == '__main__':
    main()
