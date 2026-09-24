# 黑白抠图工具（Diff Matte Cutout）

利用 白底 + 黑底 两张同构图图像的像素差异提取精确 Alpha，生成透明背景 PNG。
比 `generate_image` 的 `transparent: true` 边缘更干净、半透明过渡更自然。

## 铁律（绝对不可违反）

1. **黑底图必须从白底图用 `edit_image` 生成**（"将背景替换为纯黑色，保持主体完全不变"）。
   两次独立生成的构图不同 → 像素差异计算完全错误 → 抠图失败。
2. **颜色源用黑底图**（前景颜色更准，不混入白色溢出）。
3. **最后 trim** 去掉透明边距（Python 管线已内置，`--no-trim` 关闭）。

## 工作流

```
Step 1  MCP generate_image:  "...内容描述...，纯白色背景" (transparent=false)
Step 2  确认白底图构图/质量满意
Step 3  MCP edit_image(白底图):  "将背景替换为纯黑色，保持主体完全不变"
Step 4  差分抠图（下方二选一）
Step 5  验证: identify -verbose out.png | grep Type:  → TrueColorAlpha
```

## 方法选择

| 场景 | 方法 |
|------|------|
| 角色立绘、复杂边缘、AI 内部噪点 | **方法 A**: `diff_matte_v5.py`（V15 智能管线） |
| Logo、图标、简单图形（快速） | 方法 B: `diff_matte.sh`（ImageMagick） |

## 方法 A: Python 智能管线（推荐）

```bash
python3 tools/diff_matte/diff_matte_v5.py <黑底图> <白底图> <输出.png> [density_threshold]
# density_threshold 默认 0.30:
#   调小 → 更保守（只硬化极孤立噪点，光晕/发光保留更多）
#   调大 → 更激进（硬化更多半透明区域）
# 可选 --no-trim 关闭裁边
```

依赖: `numpy Pillow scipy`（沙箱已预装）。

V15 特性：双参数集（保守 V14 / 激进 V14++）各跑五阶段渐进硬化（P0 种子 →
P1 双信号 → P2 中值5x5 → P3 中值7x7 → P4 邻域拯救），再按 15x15 局部半透明
密度混合——孤立噪点被清除，大片半透明（光晕/纱裙/毛发渐变）被保留；
并自动填补角色体内 alpha=0 孔洞。

## 方法 B: ImageMagick 基础管线

```bash
bash tools/diff_matte/diff_matte.sh <白底图> <黑底图> <输出.png>
```

不修复内部噪点。若立绘体内出现半透明条纹/斑点，改用方法 A。

## 常见问题

- **抠图后有白边/黑边** → 黑底图不是从白底图 edit_image 生成的。
- **主体颜色偏暗** → 确认颜色源是黑底图（两个管线均已如此）。
- **体内半透明条纹/斑点** → AI 内部噪点，用方法 A。
- **发光/光晕区域变暗** → 调小 density_threshold（如 0.20）。
- **debug**: ImageMagick 管线查看中间 `diff.png`——全白/全黑说明两图不匹配。
