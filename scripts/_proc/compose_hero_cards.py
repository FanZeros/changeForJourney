#!/usr/bin/env python3
"""角色卡暗黑古卷批量合成器（最终版 · E1 纸框参数）
框  : 底板B去金属角 —— 羊皮纸+回纹+印章保留, 四角铜钉用边框中段纸纹补丁覆盖
角色: 角色立绘/<英雄>_透明立绘.png -> 提亮 -> 实体bbox裁剪(行/列密度2%滤残渣)
      -> 等比缩放至卡高98% -> 头压上框/脚贴卡底(完整不截断)
氛围: 暗紫夜内框(乘法压暗, 羽化边缘) + 弱化下方暗雾 + 四角vignette
输出: 覆盖 assets/image/角色卡牌/KP_YX_<id>.png (.meta 不动, uuid 不变)
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = '/workspace'
BASE_PATH = os.path.join(ROOT, 'assets/image/底板B_深褐古卷_20260912223431.png')
LIHUI_DIR = os.path.join(ROOT, 'assets/image/角色立绘')
OUT_DIR = os.path.join(ROOT, 'assets/image/角色卡牌')

# 20 英雄 id -> 完整透明立绘
HERO_SOURCES = {
    1:  '大狗嚼_透明立绘.png',
    2:  '黄桃龙_透明立绘.png',
    3:  '叮咚鸡_透明立绘.png',
    4:  '接化发掌门_透明立绘.png',
    5:  '叠甲怪_透明立绘.png',
    6:  '阿姨压_透明立绘.png',
    7:  '信光机兵_透明立绘.png',
    8:  '愤怒的小雀_透明立绘.png',
    9:  '卡皮巴拉_透明立绘.png',
    10: '铁憨憨_透明立绘.png',
    11: '熬夜冠军_透明立绘.png',
    12: '雪皇_透明立绘.png',
    13: '弹弹弹_透明立绘.png',
    14: '内鬼_透明立绘.png',
    15: '复活吧爱人_透明立绘.png',
    16: '万剑归宗_透明立绘.png',
    20: '摘星星星人_透明立绘.png',
    21: '闪电卖鸡_透明立绘.png',
    22: '小黑子_透明立绘.png',
    23: '真布诗人_透明立绘.png',
}

BASE_B = Image.open(BASE_PATH).convert('RGBA')  # 572x1024
BASE = BASE_B
W, H = BASE_B.size
INSET_X, INSET_TOP, INSET_BOTTOM = 0.135, 0.065, 0.065

def baseB_no_metal():
    """底板B + 四角铜钉用边框中段纸纹补丁覆盖(边缘14px渐变融合)"""
    card = BASE_B.copy()
    patch = card.crop((206, 0, 366, 150))  # 上边框中段无铜钉纸纹
    pw, ph = patch.size
    corners = [
        ((0, 0), None),
        ((W - pw, 0), 'mirror_x'),
        ((0, H - ph), 'mirror_y'),
        ((W - pw, H - ph), 'mirror_xy'),
    ]
    for (px, py), mir in corners:
        p = patch
        if mir in ('mirror_x', 'mirror_xy'):
            p = p.transpose(Image.FLIP_LEFT_RIGHT)
        if mir in ('mirror_y', 'mirror_xy'):
            p = p.transpose(Image.FLIP_TOP_BOTTOM)
        pa = np.asarray(p).astype(np.float32)
        h, w = pa.shape[:2]
        ex = np.minimum(np.arange(w) / 14.0, (w - 1 - np.arange(w)) / 14.0)
        ey = np.minimum(np.arange(h) / 14.0, (h - 1 - np.arange(h)) / 14.0)
        a = np.clip(np.minimum.outer(ey, ex), 0, 1) * 255
        pa[..., 3] = np.minimum(pa[..., 3], a).astype(np.float32)
        card.alpha_composite(Image.fromarray(pa.astype('uint8'), 'RGBA'), (px, py))
    return card

def night_inner(card, ix0, iy0, ix1, iy1):
    """内框乘法压暗成暗紫夜(保留纸纹, 羽化边缘)"""
    arr = np.asarray(card).astype(np.float32)
    m = np.zeros((H, W), dtype=np.float32)
    m[iy0:iy1, ix0:ix1] = 1.0
    m_img = Image.fromarray((m * 255).astype('uint8'), 'L').filter(ImageFilter.GaussianBlur(14))
    mm = np.asarray(m_img).astype(np.float32)[..., None] / 255.0
    top_t = np.array([0.40, 0.30, 0.52], dtype=np.float32)
    bot_t = np.array([0.20, 0.14, 0.30], dtype=np.float32)
    rows = np.linspace(0.0, 1.0, H, dtype=np.float32)[:, None]
    tint = top_t[None, :] + (bot_t - top_t)[None, :] * rows
    mult = 1.0 - mm + mm * tint[:, None, :]
    arr[..., :3] = np.clip(arr[..., :3] * mult, 0, 255)
    return Image.fromarray(arr.astype('uint8'), 'RGBA')

def hero_layer(hero_path, scale_rel=0.98):
    """完整立绘: 提亮 -> 实体bbox裁剪 -> 等比缩放(不截断)"""
    hero = Image.open(hero_path).convert('RGBA')
    hero = ImageEnhance.Brightness(hero).enhance(1.14)
    hero = ImageEnhance.Contrast(hero).enhance(1.08)
    hero = ImageEnhance.Color(hero).enhance(1.10)
    binm = np.asarray(hero.split()[3]) >= 128
    rowhit = binm.sum(axis=1) / binm.shape[1] > 0.02
    colhit = binm.sum(axis=0) / binm.shape[0] > 0.02
    ys, xs = np.where(rowhit)[0], np.where(colhit)[0]
    bbox = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    hero = hero.crop(bbox)
    hw, hh = hero.size
    s = (H * scale_rel) / hh
    nw, nh = int(hw * s), int(hh * s)
    if nw > W * 0.92:
        s = (W * 0.92) / hw
        nw, nh = int(hw * s), int(hh * s)
    return hero.resize((nw, nh), Image.LANCZOS), (W - nw) // 2, H - nh

def fog_vignette(card, fog_a=85):
    """下方暗雾(62%起, 不吞脚) + 四角vignette"""
    grad = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    gy0 = int(H * 0.62)
    for y in range(gy0, H):
        t = (y - gy0) / max(1, H - gy0)
        gd.line([(0, y), (W, y)], fill=(12, 7, 20, int(fog_a * (t ** 1.3))))
    card.alpha_composite(grad)
    vig = Image.new('L', (W, H), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-int(W * 0.35), -int(H * 0.18), int(W * 1.35), int(H * 1.18)], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(90))
    dark = Image.new('RGBA', (W, H), (8, 4, 14, 255))
    dark.putalpha(Image.eval(vig, lambda v: int((255 - v) * 0.25)))
    card.alpha_composite(dark)
    return card

def compose(hero_path):
    card = baseB_no_metal()
    ix0 = int(W * INSET_X); ix1 = W - ix0
    iy0 = int(H * INSET_TOP); iy1 = H - int(H * INSET_BOTTOM)
    card = night_inner(card, ix0, iy0, ix1, iy1)
    hero, px, py = hero_layer(hero_path, 0.98)
    card.alpha_composite(hero, (px, py))
    return fog_vignette(card)

def main():
    only = sys.argv[1:] if len(sys.argv) > 1 else None
    for hid, name in HERO_SOURCES.items():
        if only and str(hid) not in only:
            continue
        src = os.path.join(LIHUI_DIR, name)
        out = os.path.join(OUT_DIR, f'KP_YX_{hid}.png')
        compose(src).convert('RGB').save(out, 'PNG')
        print('OK', f'KP_YX_{hid}.png <-', name, flush=True)

if __name__ == '__main__':
    main()
