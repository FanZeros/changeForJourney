# -*- coding: utf-8 -*-
"""按 dark_edit_sheets/manifest.json 把改完的拼板裁回原路径。"""
import json
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
ROOT = REPO_ROOT / 'assets' / 'image'
MANIFEST = Path(__file__).resolve().parent / 'manifest.json'


def main():
    man = json.loads(MANIFEST.read_text(encoding='utf-8'))
    n_ok = 0
    n_skip = 0
    for sheet in man['sheets']:
        sp = ROOT / sheet['file']
        if not sp.exists():
            print('MISSING SHEET', sp)
            continue
        im = Image.open(sp).convert('RGBA')
        if im.size != (sheet['width'], sheet['height']):
            print('SIZE MISMATCH', sheet['file'], 'got', im.size,
                  'expect', sheet['width'], sheet['height'], '— skip (do not scale the sheet)')
            n_skip += 1
            continue
        for it in sheet['items']:
            box = (it['x'], it['y'], it['x'] + it['w'], it['y'] + it['h'])
            crop = im.crop(box)
            if crop.size != (it['w'], it['h']):
                print('CROP FAIL', it['src'], crop.size)
                continue
            dst = ROOT / it['src']
            dst.parent.mkdir(parents=True, exist_ok=True)
            crop.save(dst)
            n_ok += 1
            print('wrote', it['src'], crop.size)
    print('done ok=%d skip_sheets=%d' % (n_ok, n_skip))


if __name__ == '__main__':
    main()
