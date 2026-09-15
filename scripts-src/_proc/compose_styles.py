#!/usr/bin/env python3
"""无金属边框的 4 种暗黑古卷卡面风格（供选型研究）
共同基底: 暗紫夜渐变底 + 纸纹噪点 + 完整立绘(提亮) + 下方暗雾 + vignette
差异层:
  A none    无框·纯净氛围
  B thin    细金线双描边(1.5px 内线 + 6px 外暗金线, 四角菱形点)
  C ink     水墨晕染边缘(噪声墨晕四周, 国风过渡)
  D torn    撕纸毛边(纸缘撕裂+深色描痕, 古卷残页感)
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = '/workspace'
LIHUI = os.path.join(ROOT, 'assets/image/角色立绘')
OUT = os.path.join(ROOT, 'assets/image')
W, H = 572, 1024
RNG = np.random.default_rng(7)

def night_base():
    """暗紫夜渐变底 + 纸纹噪点"""
    top = np.array([46, 33, 62], dtype=np.float32)
    bot = np.array([18, 12, 26], dtype=np.float32)
    rows = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
    base = top[None, None] + (bot - top)[None, None] * rows
    base = np.repeat(base, W, axis=1)
    noise = RNG.normal(0, 7, (H, W, 1)).repeat(3, axis=2)
    grain = (RNG.random((H, W, 1)) * 10).repeat(3, axis=2)
    base = np.clip(base + noise + grain - 8, 0, 255)
    img = Image.fromarray(base.astype('uint8'), 'RGB').convert('RGBA')
    # 轻微径向亮心
    cx, cy = W * 0.5, H * 0.42
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xx - cx) / (W * 0.75)) ** 2 + ((yy - cy) / (H * 0.75)) ** 2)
    glow = np.clip(1 - d, 0, 1) ** 2 * 26
    arr = np.asarray(img).astype(np.float32)
    arr[..., :3] = np.clip(arr[..., :3] + glow[..., None], 0, 255)
    return Image.fromarray(arr.astype('uint8'), 'RGBA')

def load_hero():
    hero = Image.open(os.path.join(LIHUI, '大狗嚼_透明立绘.png')).convert('RGBA')
    hero = ImageEnhance.Brightness(hero).enhance(1.12)
    hero = ImageEnhance.Contrast(hero).enhance(1.08)
    hero = ImageEnhance.Color(hero).enhance(1.10)
    hw, hh = hero.size
    s = (H * 0.96) / hh
    nw, nh = int(hw * s), int(hh * s)
    if nw > W * 0.92:
        s = (W * 0.92) / hw
        nw, nh = int(hw * s), int(hh * s)
    return hero.resize((nw, nh), Image.LANCZOS), (W - nw) // 2, H - nh

def fog_and_vignette(card, fog_a=85):
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
    dark.putalpha(Image.eval(vig, lambda v: int((255 - v) * 0.28)))
    card.alpha_composite(dark)
    return card

def style_A():
    """A 无框: 纯净暗紫夜氛围"""
    card = night_base()
    hero, px, py = load_hero()
    card.alpha_composite(hero, (px, py))
    return fog_and_vignette(card, fog_a=95)

def style_B():
    """B 细金线双描边"""
    card = style_A()
    d = ImageDraw.Draw(card)
    g1, g2 = (200, 162, 92, 190), (120, 92, 52, 120)
    d.rectangle([22, 22, W - 23, H - 23], outline=g1, width=2)
    d.rectangle([30, 30, W - 31, H - 31], outline=g2, width=1)
    for cx, cy in [(22, 22), (W - 23, 22), (22, H - 23), (W - 23, H - 23)]:
        d.polygon([(cx, cy - 7), (cx + 7, cy), (cx, cy + 7), (cx - 7, cy)], fill=g1)
    return card

def style_C():
    """C 水墨晕染边缘: 噪声墨晕四周"""
    card = style_A()
    noise = RNG.random((H, W), dtype=np.float32)
    nimg = Image.fromarray((noise * 255).astype('uint8'), 'L').filter(ImageFilter.GaussianBlur(18))
    n = np.asarray(nimg).astype(np.float32) / 255.0
    yy, xx = np.mgrid[0:H, 0:W]
    ex = np.minimum(np.minimum(xx, W - 1 - xx) / (W * 0.30), 1.0)
    ey = np.minimum(np.minimum(yy, H - 1 - yy) / (H * 0.22), 1.0)
    edge = np.clip(np.minimum(ex, ey), 0, 1)
    ink_a = np.clip((1 - edge) * (0.55 + 0.75 * n) * 230, 0, 235).astype('uint8')
    ink = Image.new('RGBA', (W, H), (6, 3, 10, 255))
    ink.putalpha(Image.fromarray(ink_a, 'L'))
    card.alpha_composite(ink)
    # 墨点飞溅
    splat = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(splat)
    for _ in range(90):
        ex_, ey_ = RNG.integers(0, W), RNG.integers(0, H)
        ex_e = min(ex_, W - ex_, ey_, H - ey_)
        if ex_e > W * 0.16:
            continue
        r = int(RNG.integers(2, 9))
        sd.ellipse([ex_ - r, ey_ - r, ex_ + r, ey_ + r], fill=(8, 4, 12, int(RNG.integers(40, 120))))
    splat = splat.filter(ImageFilter.GaussianBlur(1.2))
    card.alpha_composite(splat)
    return card

def style_D():
    """D 撕纸毛边: 纸缘撕裂 + 深色描痕(省内存版)"""
    card = night_base()
    # 撕裂边 mask: 随机偏移的多边形路径
    import math
    seg = 42
    pts_top, pts_right, pts_bot, pts_left = [], [], [], []
    for i in range(seg + 1):
        t = i / seg
        j = (RNG.random() - 0.5) * 14
        pts_top.append((30 + t * (W - 60), 30 + j))
        pts_right.append((W - 30 + j, 30 + t * (H - 60)))
        pts_bot.append((30 + t * (W - 60), H - 30 + j))
        pts_left.append((30 + j, 30 + t * (H - 60)))
    poly = pts_top + pts_right + pts_bot + pts_left
    mask = Image.new('L', (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.polygon(poly, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.5))
    # 纸色内芯(暗纸色渐变 + 噪点纹理)
    paper = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    pd = ImageDraw.Draw(paper)
    for y in range(0, H, 4):
        t = y / H
        c = (int(56 - 18 * t), int(44 - 16 * t), int(50 - 18 * t))
        pd.rectangle([0, y, W, y + 4], fill=c + (255,))
    pn = (RNG.random((H, W, 1)) * 14 - 7).astype(np.int16)
    pa = np.asarray(paper).astype(np.int16)
    pa[..., :3] = np.clip(pa[..., :3] + pn, 0, 255)
    paper = Image.fromarray(pa.astype('uint8'), 'RGBA')
    paper.putalpha(mask)
    card.alpha_composite(paper)
    # 撕痕深色描边
    edge = mask.filter(ImageFilter.FIND_EDGES)
    ea = np.asarray(edge)
    ea = np.clip(ea.astype(np.float32) * 2.2, 0, 190).astype('uint8')
    edge_img = Image.new('RGBA', (W, H), (10, 5, 8, 255))
    edge_img.putalpha(Image.fromarray(ea, 'L'))
    card.alpha_composite(edge_img)
    hero, px, py = load_hero()
    card.alpha_composite(hero, (px, py))
    return fog_and_vignette(card, fog_a=80)

STYLES = {'A_无框': style_A, 'B_细金线': style_B, 'C_水墨晕': style_C, 'D_撕纸边': style_D}

if __name__ == '__main__':
    hero_src = os.path.join(LIHUI, '大狗嚼_透明立绘.png')
    outs = []
    for name, fn in STYLES.items():
        p = os.path.join(OUT, f'样张_风格{name}.png')
        fn().convert('RGB').save(p, 'PNG')
        outs.append(p)
        print('OK', p)
    # 4宫格对比
    grid = Image.new('RGB', (W * 2 + 12, H * 2 + 12), (10, 10, 10))
    for i, p in enumerate(outs):
        img = Image.open(p).resize((W, H))
        grid.paste(img, ((i % 2) * (W + 8) + 2, (i // 2) * (H + 8) + 2))
    grid.save(os.path.join(OUT, '样张_无金属框4风格对比.png'), 'PNG')
    print('OK 对比图')
