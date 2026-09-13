# ImageMagick 命令参考

## 环境要求

- ImageMagick 6.x 或 7.x（`convert` 命令可用）
- 沙箱环境中通常已预装

## 完整脚本（可直接复用）

```bash
#!/bin/bash
# diff_matte.sh — 黑白抠图法完整脚本
# 用法: bash diff_matte.sh <白底图> <黑底图> <输出文件>

WHITE="$1"
BLACK="$2"
OUTPUT="$3"
TMPDIR=$(mktemp -d)

if [ -z "$WHITE" ] || [ -z "$BLACK" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: bash diff_matte.sh <white_bg.png> <black_bg.png> <output.png>"
    exit 1
fi

echo "[1/4] 计算像素差异..."
convert "$WHITE" "$BLACK" -compose difference -composite "$TMPDIR/diff.png"

echo "[2/4] 生成 Alpha 遮罩..."
convert "$TMPDIR/diff.png" -colorspace Gray -negate "$TMPDIR/alpha.png"

echo "[3/4] 合成透明 PNG..."
convert "$BLACK" "$TMPDIR/alpha.png" -alpha off -compose CopyOpacity -composite "$TMPDIR/result.png"

echo "[4/4] 裁剪透明边距..."
convert "$TMPDIR/result.png" -trim +repage "$OUTPUT"

# 清理
rm -rf "$TMPDIR"

# 验证
echo "--- 结果验证 ---"
identify "$OUTPUT"
identify -verbose "$OUTPUT" 2>/dev/null | grep "Type:"
echo "完成: $OUTPUT"
```

## 单步命令详解

### 1. difference 合成

```bash
convert white.png black.png -compose difference -composite diff.png
```

- 逐像素计算 `|R_white - R_black|`
- 纯背景区域：`|255 - 0| = 255`（白色）
- 前景区域：`|same - same| = 0`（黑色）

### 2. 取反得 Alpha

```bash
convert diff.png -colorspace Gray -negate alpha.png
```

- 先转灰度（如果差异图是彩色的）
- 取反：前景区域变白（不透明），背景变黑（透明）

### 3. 合成透明 PNG

```bash
convert black.png alpha.png -alpha off -compose CopyOpacity -composite output.png
```

- `-alpha off`：先关闭黑底图的 alpha
- `-compose CopyOpacity`：将 alpha.png 作为透明度通道
- 使用黑底图的 RGB 值（颜色更准确）

### 4. 裁剪透明边距

```bash
convert output.png -trim +repage output.png
```

- `-trim`：自动检测并裁剪周围的透明像素
- `+repage`：重置画布大小信息

## 验证命令

```bash
# 检查是否有 Alpha 通道
identify -verbose output.png | grep "Type:"
# 期望输出: Type: TrueColorAlpha

# 检查尺寸
identify output.png
# 期望输出: output.png PNG 宽x高+0+0 ...

# 查看 Alpha 通道统计
identify -verbose output.png | grep -A5 "Alpha:"
```

## 批量处理

```bash
# 批量处理多组白底/黑底图
for WHITE in *_white.png; do
    BASE=$(echo "$WHITE" | sed 's/_white\.png//')
    BLACK="${BASE}_black.png"
    OUTPUT="${BASE}_transparent.png"
    
    if [ -f "$BLACK" ]; then
        bash diff_matte.sh "$WHITE" "$BLACK" "$OUTPUT"
    fi
done
```

## 调试技巧

### 查看中间步骤的 diff.png

如果抠图效果不好，先检查 diff.png：
- 如果 diff.png 全白或全黑 → 白底和黑底图不匹配（可能独立生成了）
- 如果 diff.png 中前景区域不是纯黑 → edit_image 改变了主体内容

### 对比白底和黑底图尺寸

```bash
identify white.png black.png
# 两张图的尺寸必须完全一致
```
