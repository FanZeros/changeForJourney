#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""提交前完整性校验 v2（容错：无 hash 字段的特殊条目单独列出）"""
import sys, os, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patch_dist_rehash import load_all, audit

os.chdir(os.path.dirname(os.path.abspath(__file__)))
data = load_all()
stale, missing, new_scripts = audit(data)
print('剩余过期条目:', len(stale), '| 未收录新脚本:', sorted(new_scripts) if new_scripts else '无')

bad = 0
total = 0
special = {}
for rel, d in data.items():
    for f in d['files']:
        total += 1
        if 'hash' not in f or 'uuid' not in f:
            special.setdefault(rel, []).append(f)
            continue
        p = os.path.join('assets', '%s-%s%s' % (f['uuid'], f['hash'], f['ext']))
        if not os.path.exists(p):
            bad += 1
            if bad <= 5:
                print('缺失:', rel, f['fs_path'], p)
print('条目总数 %d, 常规缺失 %d' % (total, bad))
for rel, items in special.items():
    print('特殊条目(无uuid/hash) %s: %d 个, 示例: %s' % (rel, len(items), str(items[0])[:200]))

for fp in ('core/DarkIcon.lua', 'config/AssetManifest.lua'):
    cnt = sum(1 for d in data.values() if any(f['fs_path'] == fp for f in d['files']))
    print(fp, '覆盖 manifest 数:', cnt)

unref = 0
for p in glob.glob('assets/*.lua'):
    name = os.path.basename(p)[:-4]
    uuid, h = name.rsplit('-', 1)
    ok = any(any(f['uuid'] == uuid and f['hash'] == h for f in d['files']) for d in data.values())
    if not ok:
        unref += 1
        print('未被引用:', name)
print('未被引用的 lua 资产:', unref)
