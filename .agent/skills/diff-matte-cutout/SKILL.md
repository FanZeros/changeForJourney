---
name: diff-matte-cutout
description: |
  黑白抠图法（Diff Matte Cutout）—— 利用白底+黑底两张图的像素差异提取精确 Alpha 通道，生成透明背景 PNG。
  适用于 AI 生成图像的透明背景提取，比直接使用 transparent 参数效果更干净。
  Use when: (1) 需要从 AI 生成图中提取透明背景, (2) 生成透明立绘/Logo/图标, (3) 用户说"抠图"/"透明背景"/"去背景", (4) 角色立绘需要透明底, (5) 标题 Logo 需要透明底。
---

# 黑白抠图法（Diff Matte Cutout）

## 原理

通过对比同一图像在**白色背景**和**黑色背景**下的像素差异，精确计算 Alpha 通道。

```
Alpha = 1 - (R_white - R_black) / 255
Color = R_black / Alpha
```

- 前景不透明区域：白底和黑底颜色相同 → Alpha = 1
- 纯背景区域：白底=255, 黑底=0 → Alpha = 0
- 半透明边缘：按差值线性插值 → 自然过渡

## 核心规则

### 规则 #1: 黑底必须从白底生成 (绝对不可违反)

```
✅ 正确流程:
  generate_image → 白底图
  edit_image(白底图) → 黑底图    ← 保证构图完全一致

❌ 错误流程:
  generate_image → 白底图
  generate_image → 黑底图        ← 两次独立生成，构图不同，抠图失败！
```

**为什么**: AI 每次生成都有随机性，两次独立生成的构图、角色姿态、细节都会不同，
导致像素差异计算完全错误。必须用 `edit_image` 在白底图基础上替换背景色。

### 规则 #2: 使用黑底图作为颜色源

最终合成时用**黑底图**作为 RGB 颜色源（不是白底图），因为黑底版本的前景颜色更准确，
不会混入白色背景的颜色溢出。

### 规则 #3: 最后执行 trim

抠图完成后用 `convert -trim +repage` 去除多余透明边距。

## 完整工作流

### Step 1: 生成白底图

```
MCP: generate_image
  prompt: "...内容描述...，纯白色背景"
  transparent: false (默认)
  其他参数按需设置
```

### Step 2: 用户确认白底图

确认构图、内容、质量满意后继续。

### Step 3: 从白底图生成黑底图

```
MCP: edit_image
  image: <Step 1 的白底图路径>
  prompt: "将背景替换为纯黑色，保持主体完全不变"
  target_size: <与白底图相同>
  其他参数与白底图一致
```

### Step 4: ImageMagick 差分抠图

```bash
WHITE="<白底图路径>"
BLACK="<黑底图路径>"
OUTPUT="<输出透明PNG路径>"

# 4.1 计算差异
convert "$WHITE" "$BLACK" -compose difference -composite diff.png

# 4.2 取反得到 Alpha（前景=白，背景=黑）
convert diff.png -colorspace Gray -negate alpha_mask.png

# 4.3 用黑底图 + Alpha 合成透明 PNG
convert "$BLACK" alpha_mask.png -alpha off -compose CopyOpacity -composite "$OUTPUT"

# 4.4 裁剪透明边距
convert "$OUTPUT" -trim +repage "$OUTPUT"

# 4.5 清理中间文件
rm -f diff.png alpha_mask.png
```

### Step 5: 验证结果

```bash
identify -verbose "$OUTPUT" | grep -E "Type:|Geometry:"
# 应显示 Type: TrueColorAlpha (证明有 Alpha 通道)
```

## 应用场景

| 场景 | 白底 Prompt 后缀 | edit_image Prompt |
|------|-----------------|-------------------|
| 角色立绘 | `纯白色背景，全身站立` | `将背景替换为纯黑色，保持角色完全不变` |
| 标题 Logo | `纯白色背景` | `将背景替换为纯黑色，保持文字和图案完全不变` |
| 道具图标 | `纯白色背景，居中` | `将背景替换为纯黑色，保持物品完全不变` |
| UI 元素 | `纯白色背景` | `将背景替换为纯黑色，保持元素完全不变` |

## 与 transparent 参数的对比

| 方法 | 优点 | 缺点 |
|------|------|------|
| `transparent: true` | 一步到位 | 边缘常有残留、锯齿明显 |
| **黑白抠图法** | 边缘干净、半透明过渡自然 | 需要两步生成 + ImageMagick |

**推荐**: 对质量要求高的场景（立绘、Logo）优先使用黑白抠图法。

## 常见问题

### Q: 抠图后有白边/黑边？
A: 检查黑底图是否从白底图 `edit_image` 生成（而非独立生成）。

### Q: 抠图后主体颜色偏暗？
A: 确认 Step 4.3 使用的是黑底图（`$BLACK`），不是白底图。

### Q: 半透明区域（头发丝、烟雾）效果差？
A: 这是正常的，极细半透明元素的差分精度有限。可尝试提高生成分辨率。

详细 ImageMagick 命令参考见 [references/imagemagick-commands.md](references/imagemagick-commands.md)。
