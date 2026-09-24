#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
diff_matte_v5.py — 黑白抠图法（Diff Matte Cutout）V15 智能管线

原理:
    利用同一构图的 白底图 + 黑底图 像素差异提取精确 Alpha:
        alpha = 1 - max(W-B)/255        (max-channel, 最保守)
        C_fg  = C_black / alpha         (un-premultiply, 颜色取自黑底图)

V15 增强 (多阶段硬化 + 密度混合):
    1. 保守参数集(V14) 与 激进参数集(V14++) 各跑一次五阶段渐进硬化
       P0 种子 → P1 双信号 → P2 中值5x5 → P3 中值7x7 → P4 邻域拯救
    2. 密度混合: 15x15 窗口内半透明密度 < density_threshold 的孤立噪点
       跟随激进结果硬化; 大片半透明(光晕/纱裙/毛发渐变)保留保守结果
    3. 内部孔洞填补: 非 background 连通的 alpha=0 像素 → 255

用法:
    python3 diff_matte_v5.py <黑底图> <白底图> <输出.png> [density_threshold]

参数:
    黑底图            黑色背景源图 (必须由白底图 edit_image 生成, 构图一致!)
    白底图            白色背景源图
    输出.png          输出透明 PNG
    density_threshold 默认 0.30; 越小越保守(只硬化极孤立噪点), 越大越激进

依赖: numpy, Pillow, scipy
"""

import sys
import numpy as np
from PIL import Image
from scipy import ndimage

# 双参数集 (来自 diff-matte-cutout skill 规格表)
V14 = dict(  # 保守: 保护大片半透明
    p0=dict(min_ch=250, md=15, dist=2),
    p1=dict(minch_a=245, md_a=25, dist=3),
    p2=dict(alpha=240, med=250, md_factor=0.6, dist=3),
    p3=dict(alpha=225, med=245, md_factor=0.8, dist=5),
    p4=dict(opr=0.7, md=65, alpha=180, dist=8, iters=3),
)
V14PP = dict(  # 激进: 找出可额外硬化的像素
    p0=dict(min_ch=240, md=25, dist=1),
    p1=dict(minch_a=235, md_a=35, dist=1),
    p2=dict(alpha=220, med=240, md_factor=0.9, dist=1),
    p3=dict(alpha=195, med=235, md_factor=1.2, dist=2),
    p4=dict(opr=0.4, md=100, alpha=130, dist=3, iters=8),
)


def load_pair(black_path, white_path):
    black = np.array(Image.open(black_path).convert("RGB")).astype(np.float32)
    white_img = Image.open(white_path).convert("RGB")
    if white_img.size != (black.shape[1], black.shape[0]):
        print(f"警告: 白底图尺寸 {white_img.size} 与黑底图 "
              f"{(black.shape[1], black.shape[0])} 不一致, 自动缩放白底图")
        white_img = white_img.resize((black.shape[1], black.shape[0]), Image.LANCZOS)
    white = np.array(white_img).astype(np.float32)
    return black, white


def compute_signals(black, white):
    """计算所有硬化判定信号"""
    wb = white - black
    # raw_alpha / min_ch_alpha: 1 - max(W-B)/255 (数学上等价, 最保守)
    alpha = np.clip(1.0 - np.max(wb, axis=2) / 255.0, 0.0, 1.0)
    alpha255 = (alpha * 255).astype(np.uint8)
    # max_ch_diff: 三通道最大差异 (噪点/信号强度)
    md = np.max(np.abs(wb), axis=2)
    # 亮度 → 自适应阈值: 暗区宽松 / 亮区严格
    bright = 0.299 * black[:, :, 0] + 0.587 * black[:, :, 1] + 0.114 * black[:, :, 2]
    adaptive_t = np.clip(25.0 + (200.0 - bright) * 0.15, 15.0, 50.0)
    return dict(alpha=alpha, alpha255=alpha255, md=md, adaptive_t=adaptive_t)


def find_true_background(alpha_uint8, threshold=15):
    """真背景 = 与图片四边连通的 alpha 近 0 区域 (防止体内孔洞误判)"""
    is_bg = alpha_uint8 < threshold
    seed = np.zeros_like(is_bg)
    seed[0, :] = is_bg[0, :]
    seed[-1, :] = is_bg[-1, :]
    seed[:, 0] = is_bg[:, 0]
    seed[:, -1] = is_bg[:, -1]
    labeled, _ = ndimage.label(is_bg)
    edge_labels = set(labeled[seed].flatten()) - {0}
    if not edge_labels:
        return np.zeros_like(is_bg)
    return np.isin(labeled, list(edge_labels))


def grow(cand, seed, iters=10):
    """从种子区域向外生长 (3x3 连通, 限制在候选集内)"""
    cur = seed.copy()
    for _ in range(iters):
        d = ndimage.binary_dilation(cur, structure=np.ones((3, 3), dtype=bool))
        new = d & cand & ~cur
        if not new.any():
            break
        cur |= new
    return cur


def run_stages(sig, true_bg, params):
    """五阶段渐进硬化, 返回硬化后的 alpha (uint8)"""
    a = sig["alpha255"].copy()
    hardened = np.zeros(a.shape, dtype=bool)

    # P0 种子: 最安全的不透明核心
    p0 = params["p0"]
    hardened |= ((sig["alpha255"] >= p0["min_ch"]) & (sig["md"] < p0["md"])
                 & (sig["dist"] > p0["dist"]))

    # P1 双信号: (min_ch 高 + md 低) OR (md 极低 + min_ch 中)
    p1 = params["p1"]
    c_a = (sig["alpha255"] >= p1["minch_a"]) & (sig["md"] < p1["md_a"])
    c_b = (sig["md"] < p1["md_a"] * 0.4) & (sig["alpha255"] >= p1["minch_a"] - 10)
    hardened |= (c_a | c_b) & (sig["dist"] > p1["dist"])

    # P2 中值 5x5: 从种子向外扩展
    p2 = params["p2"]
    cand2 = ((sig["alpha255"] >= p2["alpha"]) & (sig["med5"] >= p2["med"])
             & (sig["md"] < sig["adaptive_t"] * p2["md_factor"])
             & (sig["dist"] > p2["dist"]))
    hardened |= grow(cand2, hardened)

    # P3 中值 7x7: 更宽松, 继续扩展
    p3 = params["p3"]
    cand3 = ((sig["alpha255"] >= p3["alpha"]) & (sig["med7"] >= p3["med"])
             & (sig["md"] < sig["adaptive_t"] * p3["md_factor"])
             & (sig["dist"] > p3["dist"]))
    hardened |= grow(cand3, hardened)

    # P4 邻域拯救: 暗纹理区域, 迭代更新邻域不透明度
    p4 = params["p4"]
    for _ in range(p4["iters"]):
        opr = ndimage.uniform_filter((a >= 255).astype(np.float32), 11)
        m = ((opr > p4["opr"]) & (sig["md"] < p4["md"]) & (a >= p4["alpha"])
             & (sig["dist"] > p4["dist"]) & ~hardened)
        if not m.any():
            break
        hardened |= m
        a[hardened] = 255

    a[hardened] = 255
    return a


def diff_matte(black, white, density_threshold=0.30):
    """V15 完整流程: 基础 matte → 双参数硬化 → 密度混合 → 孔洞填补"""
    sig = compute_signals(black, white)
    alpha255 = sig["alpha255"]
    semi_before = int(np.sum((alpha255 > 0) & (alpha255 < 255)))
    print(f"原始 alpha: full=255:{int(np.sum(alpha255 == 255))}, "
          f"semi:{semi_before}, zero:{int(np.sum(alpha255 == 0))}")

    true_bg = find_true_background(alpha255)
    print(f"真背景像素: {int(np.sum(true_bg))}")

    if not true_bg.any():
        print("警告: 未找到外部背景(整图不透明?), 跳过硬化, 直接输出基础 matte")
        final = alpha255.copy()
    else:
        sig["dist"] = ndimage.distance_transform_edt(~true_bg)
        sig["med5"] = ndimage.median_filter(alpha255, size=5)
        sig["med7"] = ndimage.median_filter(alpha255, size=7)

        alpha_v14 = run_stages(sig, true_bg, V14)
        alpha_v14pp = run_stages(sig, true_bg, V14PP)

        # V15 密度混合: 孤立噪点跟随激进结果, 大片半透明保留保守结果
        semi_map = (alpha_v14 > 10) & (alpha_v14 < 245)
        density = ndimage.uniform_filter(semi_map.astype(np.float32), 15)
        diff_mask = (alpha_v14 < 255) & (alpha_v14pp == 255)
        harden = diff_mask & (density < density_threshold)
        final = alpha_v14.copy()
        final[harden] = 255
        print(f"密度混合硬化: {int(np.sum(harden))} 像素 "
              f"(density < {density_threshold})")

    # 内部孔洞填补: 非真背景的 alpha=0 像素 → 255
    holes = (final == 0) & (~true_bg) if true_bg.any() else (final == 0)
    final[holes] = 255

    semi_after = int(np.sum((final > 0) & (final < 255)))
    print(f"修复: 内部孔洞->255: {int(np.sum(holes))}")
    print(f"最终 alpha: full=255:{int(np.sum(final == 255))}, "
          f"semi:{semi_after}, zero:{int(np.sum(final == 0))}")
    return final


def unpremultiply_rgb(black_src, alpha_uint8):
    """从黑底源图还原真实 RGB: C_fg = C_black / alpha"""
    alpha = alpha_uint8.astype(np.float32) / 255.0
    a_safe = np.where(alpha > 0.01, alpha, 1.0)
    return np.clip(black_src / a_safe[:, :, None], 0, 255).astype(np.uint8)


def trim_rgba(rgba):
    """按 alpha 包围盒裁剪透明边距 (等同 convert -trim +repage)"""
    bbox = Image.fromarray(rgba).getchannel("A").getbbox()
    if bbox:
        rgba = rgba[bbox[1]:bbox[3], bbox[0]:bbox[2]]
    return rgba


def process(black_path, white_path, output_path, density_threshold=0.30,
            do_trim=True):
    print(f"输入: black={black_path}, white={white_path}")
    black, white = load_pair(black_path, white_path)
    final_alpha = diff_matte(black, white, density_threshold)
    rgba = np.zeros((final_alpha.shape[0], final_alpha.shape[1], 4),
                    dtype=np.uint8)
    rgba[:, :, :3] = unpremultiply_rgb(black, final_alpha)
    rgba[:, :, 3] = final_alpha
    if do_trim:
        rgba = trim_rgba(rgba)
    Image.fromarray(rgba).save(output_path)
    print(f"输出: {output_path} ({rgba.shape[1]}x{rgba.shape[0]})")
    return final_alpha


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 diff_matte_v5.py <black.png> <white.png> "
              "<output.png> [density_threshold] [--no-trim]")
        sys.exit(1)
    black_path, white_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]
    density = 0.30
    trim = True
    for arg in sys.argv[4:]:
        if arg == "--no-trim":
            trim = False
        else:
            density = float(arg)
    process(black_path, white_path, output_path, density, trim)
