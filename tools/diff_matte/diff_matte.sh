#!/bin/bash
# diff_matte.sh — 黑白抠图法 ImageMagick 基础管线（不修复内部噪点）
# 适用: Logo / 图标 / 简单图形; 复杂角色立绘请用 diff_matte_v5.py
# 用法: bash diff_matte.sh <白底图> <黑底图> <输出.png>

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

echo "[3/4] 合成透明 PNG（黑底图为颜色源）..."
convert "$BLACK" "$TMPDIR/alpha.png" -alpha off -compose CopyOpacity -composite "$TMPDIR/result.png"

echo "[4/4] 裁剪透明边距..."
convert "$TMPDIR/result.png" -trim +repage "$OUTPUT"

rm -rf "$TMPDIR"

echo "--- 结果验证 ---"
identify "$OUTPUT"
identify -verbose "$OUTPUT" 2>/dev/null | grep "Type:"
echo "完成: $OUTPUT"
