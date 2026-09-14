# -*- coding: utf-8 -*-
"""
按暗黑改造规划把「还要改」的原图按 1:1 拼板，并写回拆清单。
改完后用 split_edit_sheets.py 按 manifest 裁回原路径。
"""
import json
import os
import struct
from pathlib import Path

from PIL import Image
import texture2ddecoder as t2d

# 仓库根 = tools/dark_edit_sheets/ 的上两级
REPO_ROOT = Path(__file__).resolve().parents[2]
ROOT = REPO_ROOT / 'assets' / 'image'
OUT_DIR = ROOT / 'dark_edit_sheets'
MANIFEST = Path(__file__).resolve().parent / 'manifest.json'
README = Path(__file__).resolve().parent / 'README.txt'

GL_COMPRESSED_RGBA_BPTC_UNORM = 0x8E8C
GL_COMPRESSED_RGBA_S3TC_DXT5_EXT = 0x83F3
GL_COMPRESSED_RGBA_S3TC_DXT3_EXT = 0x83F2
GL_COMPRESSED_RGB_S3TC_DXT1_EXT = 0x83F0
GL_COMPRESSED_RGBA_S3TC_DXT1_EXT = 0x83F1

def mag(path):
    with open(path, 'rb') as f:
        b = f.read(16)
    if b.startswith(b'\x89PNG'):
        return 'png'
    if b.startswith(b'\xabKTX'):
        return 'ktx'
    return 'other'


def ktx_decode(path):
    b = Path(path).read_bytes()
    if not b.startswith(b'\xabKTX 11'):
        raise ValueError('not ktx1')
    vals = struct.unpack_from('<12I', b, 16)
    glInternal = vals[3]
    w, h = vals[5], vals[6]
    kv = vals[11]
    off = 64 + kv
    image_size = struct.unpack_from('<I', b, off)[0]
    off += 4
    data = b[off:off + image_size]
    if glInternal == GL_COMPRESSED_RGBA_BPTC_UNORM:
        rgba = t2d.decode_bc7(data, w, h)
        return Image.frombytes('RGBA', (w, h), bytes(rgba), 'raw', 'BGRA')
    if glInternal in (GL_COMPRESSED_RGBA_S3TC_DXT5_EXT, GL_COMPRESSED_RGBA_S3TC_DXT3_EXT):
        rgba = t2d.decode_bc3(data, w, h)
        return Image.frombytes('RGBA', (w, h), bytes(rgba), 'raw', 'BGRA')
    if glInternal in (GL_COMPRESSED_RGB_S3TC_DXT1_EXT, GL_COMPRESSED_RGBA_S3TC_DXT1_EXT):
        rgba = t2d.decode_bc1(data, w, h)
        return Image.frombytes('RGBA', (w, h), bytes(rgba), 'raw', 'BGRA')
    if glInternal == 0x8058:
        return Image.frombytes('RGBA', (w, h), data, 'raw', 'RGBA')
    raise ValueError('unknown fmt 0x%X' % glInternal)


def load_img(rel):
    p = ROOT / rel
    if not p.exists():
        return None
    kind = mag(p)
    if kind == 'png':
        return Image.open(p).convert('RGBA')
    if kind == 'ktx':
        return ktx_decode(p)
    return Image.open(p).convert('RGBA')


def exists(rel):
    return (ROOT / rel).exists()


def list_dir(subdir, prefix=''):
    d = ROOT / subdir if subdir else ROOT
    out = []
    if not d.exists():
        return out
    for fn in sorted(os.listdir(d)):
        if not fn.endswith('.png'):
            continue
        if prefix and not fn.startswith(prefix):
            continue
        rel = fn if not subdir else '%s/%s' % (subdir, fn)
        out.append(rel)
    return out


# ---------- groups (priority order) ----------
def build_groups():
    g = []

    # P0 货币道具大图 160
    p0_big = [
        'UI_icon_JB.png', 'UI_icon_SJ.png', 'UI_icon_JC.png',
        'UI_icon_TQD.png', 'UI_icon_JJB.png', 'UI_icon_JJCQ.png',
        'UI_icon_QH_1.png', 'UI_icon_QH_2.png', 'UI_icon_QH_3.png',
        'UI_icon_JZ_WQ.png', 'UI_icon_JZ_FS.png', 'UI_icon_JZ_HJ.png',
        'UI_icon_JZ_SP.png', 'UI_icon_JZ_SJ.png',
        'UI_icon_ZMQ_1.png', 'UI_icon_ZMQ_2.png',
        'UI_icon_SDQ.png', 'UI_icon_ASFC.png', 'UI_icon_JSK.png',
        'UI_icon_HJYS.png', 'UI_icon_FHS.png', 'UI_icon_SSS.png',
        'ICON_SJYW.png', 'ICON_SP.png',
        'UI_icon_GOU.png', 'UI_icon_TS.png',
        'UI_icon_NZ.png', 'UI_icon_FBBX.png',
    ]
    g.append(('P0_货币道具', p0_big))

    p0_small = [
        'UI_icon_JB_X.png', 'UI_icon_SJ_X.png', 'UI_icon_TQD_X.png',
        'UI_icon_JJB_X.png', 'UI_icon_JJCQ_X.png', 'UI_icon_JJCFS_X.png',
        'UI_icon_JGB_X.png', 'UI_icon_SDQ_X.png', 'UI_icon_ASFC_X.png',
        'UI_icon_ZMQ_X.png', 'UI_icon_ZMQ2_X.png', 'UI_icon_KGG_X.png',
        'UI_ICON_SUO.png', 'ICON_UP.png', 'ICON_UP_big.png',
        'ICON_ZDL.png', 'ICON_HD.png',
        'ICON_ZY_1.png', 'ICON_ZY_2.png', 'ICON_ZY_3.png',
        'ICON_ZY_4.png', 'ICON_ZY_5.png', 'ICON_ZY_6.png', 'ICON_ZY_XG.png',
    ]
    g.append(('P0_小图标角标', p0_small))

    p1_nav = [
        'UI_YWJM_DB.png', 'UI_YWJM_DBAN1.png', 'UI_YWJM_DBAN2.png', 'UI_YWJM_DBAN3.png',
        'UI_YWJM_HS.png', 'UI_YWJM_XYG.png', 'UI_YWJM_XYG2.png',
        'UI_YWJM_XYGA.png', 'UI_YWJM_XYGB.png', 'UI_YWJM_MAPYY.png',
        'UI_GG_1.png',
    ]
    g.append(('P1_底栏导航', p1_nav))

    p1_bar_h = [
        'UI_JYT_1.png', 'UI_JYT_2.png',
        'UI_WJXX_JDT.png', 'UI_WJXX_JDT1.png',
        'UI_JSMB_JYT1.png', 'UI_JSMB_JYT2.png',
        'UI_RW_JDT1.png', 'UI_RW_JDT2.png',
        'UI_LXSYJDT_1.png', 'UI_LXSYJDT_2.png', 'UI_XDZJDT.png',
        'UI_ZRJM_JDT1.png', 'UI_ZRJM_JDT2.png',
    ]
    g.append(('P1_进度条横', p1_bar_h))
    g.append(('P1_进度条竖', ['UI_TQ_JDY1.png', 'UI_TQ_JDY2.png']))

    p1_shop = [
        'UI_SDICONBJ_1.png', 'UI_SDICONBJ_2.png', 'UI_SDICONBJ_3.png',
        'UI_SDICONBJ_4.png', 'UI_SDICONBJ_5.png', 'UI_SDICONBJ_6.png',
        'UI_SD_AN.png',
    ]
    g.append(('P1_商店卡槽', p1_shop))

    p1_btn = [
        'UI_AN_1.png', 'UI_AN_2.png', 'UI_AN_DA.png',
        'UI_AN_LV.png', 'UI_AN_HUANG.png', 'UI_AN_HONG.png',
        'UI_AN_FH.png', 'UI_AN_FANG.png', 'UI_AN_FANG_hong.png',
        'UI_AN_FANG_huang.png', 'UI_AN_FANG_lv.png',
        'UI_AN_JIA.png', 'UI_AN_JIAN.png', 'UI_AN_SZ.png',
    ]
    g.append(('P1_按钮条', p1_btn))

    g.append(('P2_装备图标', list_dir('装备图标', 'UI_icon_ZB_')))
    g.append(('P2_神器图标', list_dir('神器图标', 'UI_icon_SQ_')))
    g.append(('P2_职业大图标', list_dir('职业图标', 'UI_icon_ZY_')))
    g.append(('P2_角色头像', list_dir('角色图标', 'UI_icon_hero_')))

    p2_relic = [
        'ICON_YW_GUI.png', 'ICON_YW_LANG.png', 'ICON_YW_LU.png',
        'ICON_YW_SHE.png', 'ICON_YW_YING.png',
        'ICON_YWX_GUI.png', 'ICON_YWX_LANG.png', 'ICON_YWX_LU.png',
        'ICON_YWX_SHE.png', 'ICON_YWX_YING.png',
    ]
    g.append(('P2_遗物', p2_relic))

    p2_rank = ['ICON_DW_%d.png' % i for i in range(1, 9)]
    g.append(('P2_段位', p2_rank))

    g.append(('P2_品质角标', [
        'UI_PZBZ_R.png', 'UI_PZBZ_SR.png', 'UI_PZBZ_SSR.png', 'UI_PZBZ_UR.png',
    ]))
    g.append(('P2_品质立绘框', [
        'UI_PZG_SR.png', 'UI_PZG_SSR.png', 'UI_PZG_UR.png',
    ]))
    g.append(('P2_头像框', [
        'UI_icon_TXK_1.png', 'UI_icon_TXK_2.png', 'UI_icon_TXK_3.png',
        'UI_icon_TXK_4.png', 'UI_icon_TXK_5.png', 'UI_icon_TXK_6.png',
    ]))

    return g


def pack_group(name, rels, pad=16):
    """1:1 original size, white bg, no labels. Shelf-pack toward a square."""
    items = []
    missing = []
    for rel in rels:
        im = load_img(rel)
        if im is None:
            missing.append(rel)
            continue
        items.append({'rel': rel, 'w': im.width, 'h': im.height, 'im': im})
    if not items:
        return None, missing, []

    area = sum((it['w'] + pad) * (it['h'] + pad) for it in items)
    max_item_w = max(it['w'] for it in items)
    max_w = max(max_item_w + pad * 2, int(area ** 0.5))

    rows = []
    cur, cw, ch = [], pad, 0
    for it in items:
        need = it['w'] + pad
        if cur and cw + need + pad > max_w:
            rows.append((cur, cw, ch))
            cur, cw, ch = [], pad, 0
        cur.append(it)
        cw += need
        ch = max(ch, it['h'])
    if cur:
        rows.append((cur, cw, ch))

    sheet_w = max(r[1] for r in rows) + pad
    sheet_h = pad + sum(r[2] + pad for r in rows)
    canvas = Image.new('RGBA', (sheet_w, sheet_h), (255, 255, 255, 255))

    placements = []
    y = pad
    for row, rw, rh in rows:
        x = pad
        for it in row:
            canvas.paste(it['im'], (x, y), it['im'])
            placements.append({
                'src': it['rel'],
                'x': x,
                'y': y,
                'w': it['w'],
                'h': it['h'],
            })
            x += it['w'] + pad
        y += rh + pad

    return canvas, missing, placements


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob('*.png'):
        old.unlink()
    groups = build_groups()
    manifest = {
        'note': '按规划拼的 1:1 原图板。改完后运行 python tools/dark_edit_sheets/split_edit_sheets.py',
        'root': 'assets/image',
        'sheets': [],
        'missing': [],
        'total': 0,
    }
    for name, rels in groups:
        canvas, missing, placements = pack_group(name, rels)
        manifest['missing'].extend(missing)
        if canvas is None:
            print('SKIP empty', name, 'missing', missing)
            continue
        fn = name + '.png'
        out = OUT_DIR / fn
        canvas.save(out)
        manifest['sheets'].append({
            'file': 'dark_edit_sheets/' + fn,
            'group': name,
            'width': canvas.width,
            'height': canvas.height,
            'count': len(placements),
            'items': placements,
        })
        manifest['total'] += len(placements)
        print('wrote', fn, canvas.size, 'n=', len(placements), 'missing', missing)

    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')

    lines = [
        '暗黑改造 · 待改原图拼板（1:1，可回拆）',
        '',
        '目录: assets/image/dark_edit_sheets/',
        '清单: manifest.json  （每张图的 src / x / y / w / h）',
        '',
        '怎么改:',
        '  1. 直接在对应分组 PNG 上改像素（保持画布尺寸、每块位置不变）',
        '  2. 或按 manifest 把某一块抠出去单独改，再贴回同一 x,y',
        '  3. 改完后运行:  python tools/dark_edit_sheets/split_edit_sheets.py',
        '     会按坐标裁回 assets/image/<src>（覆盖原文件）',
        '',
        '注意:',
        '  - 原资源很多是 KTX（.png 扩展名），拼板已解码成真 PNG',
        '  - 回拆写出的是 PNG；引擎可直接读 PNG，无需再压 KTX',
        '  - 不要缩放整张拼板；缩放会导致回拆尺寸对不上',
        '',
        '分组:',
    ]
    for s in manifest['sheets']:
        lines.append('  %s  %dx%d  %d张' % (s['file'], s['width'], s['height'], s['count']))
    if manifest['missing']:
        lines.append('')
        lines.append('缺失（规划里有、资源目录没有）:')
        for m in manifest['missing']:
            lines.append('  ' + m)
    lines.append('')
    lines.append('合计 %d 张' % manifest['total'])
    README.write_text('\n'.join(lines), encoding='utf-8')
    print('TOTAL', manifest['total'], 'missing', manifest['missing'])
    print('manifest', MANIFEST)


if __name__ == '__main__':
    main()
