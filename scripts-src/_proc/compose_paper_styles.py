#!/usr/bin/env python3
"""纸质边框的 4 种风格（无金属）
E1 底板B去金属角: 用边框中段纸纹补丁覆盖四角铜钉, 保留羊皮纸+回纹+印章
E2 双层卡纸框: 宽卡纸边 + 内缘压印双线(装裱画式)
E3 撕纸外缘+纸框内衬: 外缘撕裂毛边, 内衬羊皮纸框线
E4 窄纸框压印线: 极简窄纸框 + 单压印线
共同: 暗紫夜内框(乘法压暗) + 完整立绘(大狗嚼透明版) + 暗雾 + vignette
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = '/workspace'
W, H = 572, 1024
LIHUI = os.path.join(ROOT, 'assets/image/角色立绘/大狗嚼_透明立绘.png')
BASE_B = Image.open(os.path.join(ROOT, 'assets/image/底板B_深褐古卷_20260912223431.png')).convert('RGBA')
RNG = np.random.default_rng(11)

def night_inner(card, ix0, iy0, ix1, iy1):
    """内框乘法压暗成暗紫夜(羽化边缘)"""
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

def hero_layer(scale_rel=0.98):
    hero = Image.open(LIHUI).convert('RGBA')
    hero = ImageEnhance.Brightness(hero).enhance(1.14)
    hero = ImageEnhance.Contrast(hero).enhance(1.08)
    hero = ImageEnhance.Color(hero).enhance(1.10)
    binm = np.asarray(hero.split()[3]) >= 128
    rowhit = binm.sum(axis=1) / binm.shape[1] > 0.02   # 行密度>2%才算实体(滤除角落残渣)
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

def baseB_no_metal():
    """底板B + 四角铜钉用边框中段纸纹补丁覆盖"""
    card = BASE_B.copy()
    # 补丁源: 上边框中段无铜钉的纸纹区 (206,0)-(366,150)
    patch = card.crop((206, 0, 366, 150))
    pw, ph = patch.size  # 160x150
    # 四角覆盖(镜像保证纸纹方向自然): 补丁略放大确保盖住金属角
    corners = [
        ((0, 0), None),                    # 左上: 原样
        ((W - pw, 0), 'mirror_x'),         # 右上
        ((0, H - ph), 'mirror_y'),         # 左下
        ((W - pw, H - ph), 'mirror_xy'),   # 右下
    ]
    for (px, py), mir in corners:
        p = patch
        if mir in ('mirror_x', 'mirror_xy'):
            p = p.transpose(Image.FLIP_LEFT_RIGHT)
        if mir in ('mirror_y', 'mirror_xy'):
            p = p.transpose(Image.FLIP_TOP_BOTTOM)
        # 补丁边缘 alpha 渐变(融合, 避免生硬接缝)
        pa = np.asarray(p).astype(np.float32)
        h, w = pa.shape[:2]
        ex = np.minimum(np.arange(w) / 14.0, (w - 1 - np.arange(w)) / 14.0)
        ey = np.minimum(np.arange(h) / 14.0, (h - 1 - np.arange(h)) / 14.0)
        a = np.clip(np.minimum.outer(ey, ex), 0, 1) * 255
        pa[..., 3] = np.minimum(pa[..., 3], a).astype(np.float32)
        card.alpha_composite(Image.fromarray(pa.astype('uint8'), 'RGBA'), (px, py))
    return card

def style_E1():
    """E1 底板B去金属角"""
    card = baseB_no_metal()
    ix0, iy0, ix1, iy1 = int(W * 0.135), int(H * 0.065), int(W * 0.865), int(H * 0.935)
    card = night_inner(card, ix0, iy0, ix1, iy1)
    hero, px, py = hero_layer(0.94)
    card.alpha_composite(hero, (px, py))
    return fog_vignette(card)

def paper_frame(card, fw, double=False, tear=False):
    """程序化纸质边框: fw=边框宽; double=内缘压印双线; tear=外缘撕裂"""
    if tear:
        seg = 42
        pts_top, pts_right, pts_bot, pts_left = [], [], [], []
        for i in range(seg + 1):
            t = i / seg
            j = (RNG.random() - 0.5) * 12
            pts_top.append((8 + t * (W - 16), 8 + j))
            pts_right.append((W - 8 + j, 8 + t * (H - 16)))
            pts_bot.append((8 + t * (W - 16), H - 8 + j))
            pts_left.append((8 + j, 8 + t * (H - 16)))
        poly = pts_top + pts_right + pts_bot + pts_left
        mask = Image.new('L', (W, H), 0)
        ImageDraw.Draw(mask).polygon(poly, fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(1.5))
    else:
        mask = Image.new('L', (W, H), 255)
    # 纸框层: 边框区域填暗纸色渐变 + 噪点
    frame = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    for y in range(0, H, 4):
        t = y / H
        c = (int(66 - 24 * t), int(52 - 20 * t), int(58 - 22 * t))
        fd.rectangle([0, y, W, y + 4], fill=c + (255,))
    pn = (RNG.random((H, W, 1)) * 13 - 6).astype(np.int16)
    fa = np.asarray(frame).astype(np.int16)
    fa[..., :3] = np.clip(fa[..., :3] + pn, 0, 255)
    frame = Image.fromarray(fa.astype('uint8'), 'RGBA')
    # 边框区域 = 全图 - 内区; 内区挖空(内缘羽化 4px)
    hole = Image.new('L', (W, H), 0)
    hd = ImageDraw.Draw(hole)
    hd.rectangle([fw, fw, W - fw, H - fw], fill=255)
    hole = hole.filter(ImageFilter.GaussianBlur(2))
    fa = np.asarray(frame).copy()
    ha = np.asarray(hole)
    fa[..., 3] = np.clip(fa[..., 3].astype(np.int16) * (1 - ha / 255.0), 0, 255).astype('uint8')
    # 外缘用 mask 裁(撕裂时)
    if tear:
        fa[..., 3] = np.clip(fa[..., 3].astype(np.int16) * (np.asarray(mask) / 255.0), 0, 255).astype('uint8')
    frame = Image.fromarray(fa, 'RGBA')
    card.alpha_composite(frame)
    # 内缘压印线: 深线+相邻亮线(凹陷感)
    d = ImageDraw.Draw(card)
    if double:
        d.rectangle([fw - 3, fw - 3, W - fw + 2, H - fw + 2], outline=(24, 15, 12, 200), width=2)
        d.rectangle([fw, fw, W - fw - 1, H - fw - 1], outline=(150, 124, 96, 130), width=1)
    else:
        d.rectangle([fw - 2, fw - 2, W - fw + 1, H - fw + 1], outline=(26, 16, 13, 190), width=2)
        d.rectangle([fw + 1, fw + 1, W - fw - 2, H - fw - 2], outline=(146, 120, 92, 110), width=1)
    return card

def style_E2():
    """E2 双层卡纸框(装裱式)"""
    card = night_base_paper()
    ix0, iy0 = 78, 78
    card = night_inner(card, ix0, iy0, W - ix0, H - iy0)
    card = paper_frame(card, 64, double=True)
    hero, px, py = hero_layer(0.90)
    card.alpha_composite(hero, (px, py))
    return fog_vignette(card, fog_a=75)

def style_E3():
    """E3 撕纸外缘 + 纸框内衬"""
    card = night_base_paper()
    ix0, iy0 = 70, 70
    card = night_inner(card, ix0, iy0, W - ix0, H - iy0)
    card = paper_frame(card, 52, double=False, tear=True)
    hero, px, py = hero_layer(0.92)
    card.alpha_composite(hero, (px, py))
    return fog_vignette(card, fog_a=80)

def style_E4():
    """E4 窄纸框压印线(极简)"""
    card = night_base_paper()
    ix0, iy0 = 44, 44
    card = night_inner(card, ix0, iy0, W - ix0, H - iy0)
    card = paper_frame(card, 30, double=False)
    hero, px, py = hero_layer(0.94)
    card.alpha_composite(hero, (px, py))
    return fog_vignette(card, fog_a=80)

def night_base_paper():
    """与 compose_styles.night_base 相同的暗紫夜底"""
    top = np.array([46, 33, 62], dtype=np.float32)
    bot = np.array([18, 12, 26], dtype=np.float32)
    rows = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
    base = top[None, None] + (bot - top)[None, None] * rows
    base = np.repeat(base, W, axis=1)
    noise = RNG.normal(0, 7, (H, W, 1))
    grain = RNG.random((H, W, 1)) * 10
    base = np.clip(base + noise + grain - 8, 0, 255)
    img = Image.fromarray(base.astype('uint8'), 'RGB').convert('RGBA')
    cx, cy = W * 0.5, H * 0.42
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xx - cx) / (W * 0.75)) ** 2 + ((yy - cy) / (H * 0.75)) ** 2)
    glow = np.clip(1 - d, 0, 1) ** 2 * 26
    arr = np.asarray(img).astype(np.float32)
    arr[..., :3] = np.clip(arr[..., :3] + glow[..., None], 0, 255)
    return Image.fromarray(arr.astype('uint8'), 'RGBA')

STYLES = {'E1_底板B去金属': style_E1, 'E2_双层卡纸': style_E2, 'E3_撕纸内衬': style_E3, 'E4_窄压线': style_E4}

if __name__ == '__main__':
    outs = []
    for name, fn in STYLES.items():
        p = os.path.join(ROOT, 'assets/image', f'样张_纸框{name}.png')
        fn().convert('RGB').save(p, 'PNG')
        outs.append(p)
        print('OK', os.path.basename(p), flush=True)
    grid = Image.new('RGB', (W * 2 + 12, H * 2 + 12), (10, 10, 10))
    for i, p in enumerate(outs):
        img = Image.open(p).resize((W, H))
        grid.paste(img, ((i % 2) * (W + 8) + 2, (i // 2) * (H + 8) + 2))
    grid.save(os.path.join(ROOT, 'assets/image', '样张_纸质框4风格对比.png'), 'PNG')
    print('OK 对比图', flush=True)
