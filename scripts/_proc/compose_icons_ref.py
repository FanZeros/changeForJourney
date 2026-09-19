#!/usr/bin/env python3
"""头像规范化 · 参考图整合器
产出两张 5列x4行 参考大图(顺序一致, id 升序: 1..16,20,21,22,23):
  [1] ref_layout.png  : 20 张旧头像拼图 —— 给 GPT 定「大头构图规范」
  [2] ref_characters.png : 20 张透明立绘拼图(白底) —— 给 GPT 定「每个角色的实际形象」
可选参数 --split <大图路径> : 黑白差分抠图后按同一网格拆分归一化为 256x256 头像
"""
import os, sys
import numpy as np
from PIL import Image

ROOT = '/workspace'
ICON_DIR = os.path.join(ROOT, 'assets/image/角色图标')
LIHUI_DIR = os.path.join(ROOT, 'assets/image/角色立绘')
OUT_DIR = os.path.join(ROOT, '.tmp/icon_ref')

IDS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 21, 22, 23]

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

CELL = 256          # 每格边长
COLS, ROWS = 5, 4


def grid_canvas(bg=(255, 255, 255)):
    return Image.new('RGB', (CELL * COLS, CELL * ROWS), bg)


def solid_bbox(im, thr=128):
    a = np.asarray(im.split()[3]) >= thr
    if not a.any():
        return None
    ys, xs = np.where(a)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def build_layout_ref():
    """旧头像 5x4 拼图(构图规范)"""
    grid = grid_canvas(bg=(40, 40, 44))
    for i, hid in enumerate(IDS):
        p = os.path.join(ICON_DIR, f'UI_icon_hero_{hid}.png')
        im = Image.open(p).convert('RGBA').resize((CELL, CELL), Image.LANCZOS)
        cell = Image.new('RGBA', (CELL, CELL), (40, 40, 44, 255))
        cell.alpha_composite(im)
        grid.paste(cell.convert('RGB'), ((i % COLS) * CELL, (i // COLS) * CELL))
    out = os.path.join(OUT_DIR, 'ref_layout.png')
    grid.save(out, 'PNG')
    print('OK', out)


def build_character_ref():
    """立绘 5x4 拼图(角色形象, 白底, 等比缩放留边)"""
    grid = grid_canvas(bg=(255, 255, 255))
    pad = 10
    inner = CELL - pad * 2
    for i, hid in enumerate(IDS):
        p = os.path.join(LIHUI_DIR, HERO_SOURCES[hid])
        hero = Image.open(p).convert('RGBA')
        bb = solid_bbox(hero)
        if bb:
            hero = hero.crop(bb)
        hw, hh = hero.size
        s = inner / max(hw, hh)
        hero = hero.resize((max(1, int(hw * s)), max(1, int(hh * s))), Image.LANCZOS)
        cell = Image.new('RGBA', (CELL, CELL), (255, 255, 255, 255))
        cell.alpha_composite(hero, ((CELL - hero.size[0]) // 2, (CELL - hero.size[1]) // 2))
        grid.paste(cell.convert('RGB'), ((i % COLS) * CELL, (i // COLS) * CELL))
    out = os.path.join(OUT_DIR, 'ref_characters.png')
    grid.save(out, 'PNG')
    print('OK', out)


def flood_bg_mask(rgb, lo=230, spread=12):
    """从画面边界 flood fill 判定背景(浅色近白、且与外界连通)。
    rgb: HxWx3 int 数组。返回 HxW bool, True=背景。"""
    from collections import deque
    h, w, _ = rgb.shape
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mn = np.minimum(np.minimum(r, g), b)
    mx = np.maximum(np.maximum(r, g), b)
    light = (mn >= lo) & ((mx - mn) <= spread)
    mask = np.zeros((h, w), bool)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            if light[y, x] and not mask[y, x]:
                mask[y, x] = True
                dq.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if light[y, x] and not mask[y, x]:
                mask[y, x] = True
                dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and light[ny, nx] and not mask[ny, nx]:
                mask[ny, nx] = True
                dq.append((ny, nx))
    return mask


def make_black_from_white(white_path, black_path):
    """程序化黑底: flood fill 背景涂黑 —— 与白底像素级对齐, 供黑白差分。"""
    im = Image.open(white_path).convert('RGB')
    rgb = np.asarray(im).astype(int)
    bg = flood_bg_mask(rgb)
    black = np.asarray(im).copy()
    black[bg] = (0, 0, 0)
    Image.fromarray(black).save(black_path, 'PNG')
    print(f'OK {black_path} (bg {bg.mean() * 100:.1f}% px)')
    return black_path


def diff_matte(white_path, black_path, out_path):
    """黑白差分抠图: alpha = 255-(W-B), color 源用黑底(skill 规则 #2)。"""
    W = np.asarray(Image.open(white_path).convert('RGB')).astype(int)
    B = np.asarray(Image.open(black_path).convert('RGB')).astype(int)
    assert W.shape == B.shape, f'尺寸不一致: {W.shape} vs {B.shape}'
    alpha = np.clip(255 - (W - B).mean(axis=2), 0, 255).astype(np.uint8)
    alpha[alpha < 20] = 0
    color = np.clip(B, 0, 255).astype(np.uint8)
    rgba = np.dstack([color, alpha])
    Image.fromarray(rgba, 'RGBA').save(out_path, 'PNG')
    print('OK', out_path)
    return out_path


def label_components(mask):
    """4-连通域标记(免 scipy 手写两遍扫描)。返回 labels(HxW int), 数量。"""
    h, w = mask.shape
    labels = np.zeros((h, w), np.int32)
    parent = [0]  # union-find

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)

    nxt = 1
    for y in range(h):
        row = mask[y]
        for x in range(w):
            if not row[x]:
                continue
            up = labels[y - 1, x] if y > 0 else 0
            lf = labels[y, x - 1] if x > 0 else 0
            if up == 0 and lf == 0:
                labels[y, x] = nxt
                parent.append(nxt)
                nxt += 1
            elif up and lf:
                labels[y, x] = min(up, lf)
                union(up, lf)
            else:
                labels[y, x] = max(up, lf)
    # 第二遍: 归并
    root_area = {}
    for lb in range(1, nxt):
        root_area[find(lb)] = root_area.get(find(lb), 0)
    for y in range(h):
        row = labels[y]
        for x in range(w):
            if row[x]:
                row[x] = find(row[x])
    return labels, len(root_area)


def split_grid(grid_path, out_root=None):
    """透明大图 → 连通域匹配 5x4 格中心 → 实体居中归一化 256x256。"""
    out_dir = out_root or os.path.join(OUT_DIR, 'split')
    os.makedirs(out_dir, exist_ok=True)
    big = Image.open(grid_path).convert('RGBA')
    W, H = big.size
    arr = np.asarray(big)
    opaque = arr[..., 3] >= 100
    labels, n = label_components(opaque)
    # 域面积
    areas = {}
    ys, xs = np.nonzero(opaque)
    for y, x in zip(ys, xs):
        areas[labels[y, x]] = areas.get(labels[y, x], 0) + 1
    domains = [lb for lb, a in areas.items() if a >= 3000]
    # 每个域的 bbox
    boxes = {}
    for lb in domains:
        yy, xx = np.nonzero(labels == lb)
        boxes[lb] = (int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1)
    # 预期 20 格中心, 就近分配(一个域只能被一个格子认领)
    cw, ch = W / COLS, H / ROWS
    centers = [((i % COLS + 0.5) * cw, (i // COLS + 0.5) * ch) for i in range(COLS * ROWS)]
    assign = {}
    used = set()
    for i, (cx, cy) in enumerate(centers):
        best, bestd = None, 1e18
        for lb in domains:
            bx0, by0, bx1, by1 = boxes[lb]
            d = ((bx0 + bx1) / 2 - cx) ** 2 + ((by0 + by1) / 2 - cy) ** 2
            if d < bestd and lb not in used:
                best, bestd = lb, d
        assign[i] = best
        used.add(best)
    for i, hid in enumerate(IDS):
        lb = assign[i]
        cell = big.crop(boxes[lb]) if lb is not None else Image.new('RGBA', (CELL, CELL), (0, 0, 0, 0))
        hw, hh = cell.size
        s = min(CELL * 0.92 / hw, CELL * 0.92 / hh)
        cell = cell.resize((max(1, int(hw * s)), max(1, int(hh * s))), Image.LANCZOS)
        canvas = Image.new('RGBA', (CELL, CELL), (0, 0, 0, 0))
        canvas.alpha_composite(cell, ((CELL - cell.size[0]) // 2, (CELL - cell.size[1]) // 2))
        out = os.path.join(out_dir, f'UI_icon_hero_{hid}.png')
        canvas.save(out, 'PNG')
        print('OK', out)
    # 拼验收预览(深灰底)
    pv = Image.new('RGB', (CELL * COLS, CELL * ROWS), (60, 60, 64))
    for i, hid in enumerate(IDS):
        p = os.path.join(out_dir, f'UI_icon_hero_{hid}.png')
        cell = Image.open(p)
        bg = Image.new('RGBA', (CELL, CELL), (60, 60, 64, 255))
        bg.alpha_composite(cell)
        pv.paste(bg.convert('RGB'), ((i % COLS) * CELL, (i // COLS) * CELL))
    pv_path = os.path.join(OUT_DIR, 'split_preview.png')
    pv.save(pv_path, 'PNG')
    print('OK', pv_path)


if __name__ == '__main__':
    os.makedirs(OUT_DIR, exist_ok=True)
    if len(sys.argv) >= 3 and sys.argv[1] == '--matte':
        # 一条龙: flood 造黑底 → 黑白差分 → 连通域拆分归一化
        white = sys.argv[2]
        black = os.path.join(OUT_DIR, 'black_from_white.png')
        make_black_from_white(white, black)
        matte = os.path.join(OUT_DIR, 'matte.png')
        diff_matte(white, black, matte)
        split_grid(matte)
    elif len(sys.argv) >= 3 and sys.argv[1] == '--split':
        split_grid(sys.argv[2])
    else:
        build_layout_ref()
        build_character_ref()
