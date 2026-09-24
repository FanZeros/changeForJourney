# GPT 角色美术出图管线

> 源自项目实战沉淀（docs/memory-index.md §3 + docs/角色CG制作规范.md）。
> 适用于：角色立绘生成/重绘、卡面、觉醒 CG、图标等角色美术出图。

## 铁律

1. **必须 `model = "gpt"`**（GPT Image 2）——项目验收确认的出图后端，不要用默认模型
2. **立绘规格**：`aspect_ratio = "2:3"`，`target_size = "832x1248"`
3. **必须挂参考图**（reference_images，上限 13-14，**3 层结构效果最好**，20 张全塞不行）
4. **梗装束/梗元素必须写成画面主体**，不能只是小配饰（验收教训 #1）
5. **负面约束必须写明**：`clean, smooth, no film grain, no noise。没有漂浮粒子、闪光点、镜头光晕。不添加文字、水印。`
6. **发色不锁**（用户明确"颜色不一定要遵循之前的，只是风格需要参考"）；角色设计需锁时以参考图为准

## 参考图三层结构

| 层 | 作用 | 首选来源 |
|----|------|---------|
| [1] 角色原版卡面/立绘 | 锁角色长相 | `assets/image/角色立绘/{角色名}_透明立绘.png` 或 `assets/image/角色卡牌/KP_YX_{id}.png` |
| [2] 构图/背景/光线基准 | 锁构图取景与光影 | 项目基准图（如 `edited_风格基准图_暗黑版_*.png`）；缺失时用该角色当前最合格立绘替代 |
| [3] 全队画风板 | 锁整体画风 | 画风板拼图；缺失时用 1-2 张已验收立绘替代（如卡皮巴拉） |

> ⚠️ 新沙箱/新 clone 中 `.tmp/cardref/`、画风板等中间产物不存在，按上表"缺失替代"策略取仓库内现有资产。

## Prompt 模板

### A. 暗黑风立绘/卡面（黑底满幅，替换 `<...>` 即可复用）

```
重绘/生成一张游戏角色卡面立绘。第一张参考图是角色当前立绘（角色长相、构图、色调基准）：
<角色外观与姿态描述，梗元素写成画面主体>。
保持角色设计与构图一致，重绘为更高细节的正稿品质：<要强化的梗点/质感>。
画风统一：anime game character illustration, soft cel shading with strong rim light。
clean, smooth, no film grain, no noise。没有漂浮粒子、镜头光晕。
深紫黑垂直渐变纯净暗幕背景（或纯黑色背景）。不添加文字、水印。
```

### B. 透明底立绘（白底出图 → 黑白抠图）

```
生成一张游戏角色立绘。第一张参考图是该角色当前立绘（配色与气质参考）。
全身站立构图，头顶到大腿上方七分身取景。角色设计：<完整外观描述，梗元素为主体>。
画风与第二张参考图一致：anime game character illustration, soft cel shading。
clean, smooth, no film grain, no noise。没有漂浮粒子、闪光点、镜头光晕。
纯白色背景。不添加文字、水印。
```

### C. 觉醒页 CG（暗黑意象影画，详见 docs/角色CG制作规范.md）

近景特写 + 近黑暖调纯色背景（#0D0B09）+ 暗金大字母排版，一次 4 张候选构图。

## 透明底后续：黑白抠图法

白底 `generate_image`(model=gpt) → 用户确认 → `edit_image(model="nanobanana")`
"将背景替换为纯黑色，保持主体完全不变"（构图必须一致，禁止独立生成黑底）
→ `python3 tools/diff_matte/diff_matte_v5.py <黑底> <白底> <输出.png> [density_threshold]`

## 卡面制作（从立绘裁切）

```bash
convert 立绘.png -crop 362x800+235+40 +repage -resize 390x876! base.png  # ⚠️ 裁切参数逐张校准
# + 品质晕(CopyOpacity) + #c35ae4 紫框 → KP_YX_{id}.png
```

## 踩坑抗体

- 中文文件名输出带时间戳，引用前先 `ls` 确认全名
- 黑底图必须从白底 `edit_image` 生成，两次独立生成构图不同 → 抠图必败
- 立绘黑底满幅版与透明版两种格式并存：`UI_DLH_*` 为暗黑满幅、`*_透明立绘.png` 为透明版，
  重绘前先确认目标格式（`python3 -c` 查 alpha opaque% 即可判别）
- assets 里 `.png` 可能是 KTX 纹理（ImageMagick 读不了）；`assets/image` 下源 PNG 正常
- 真人梗高风险：避开真人真名，用谐音/拟人替代
