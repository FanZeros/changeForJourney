# memory-index — 《终焉之门》改造完整交接文档

> 本文档面向**下一个 agent**:零上下文接手,先通读本文件,再按「待办清单」执行。
> 更新时间:2026-09-24 | 版本:v2.45-story-landscape
>
> **本会话（2026-09-24 `feat/story-landscape-924`）**：开场为来信 → 门厅 → 三人入队。队1写入大狗嚼、黄桃龙、叮咚鸡。剧情点击不再依赖滑动距离。索引见 `docs/剧情总表.md`。只 push 本功能分支。
>
> **本会话(2026-09-24 workspace924)**：遗匣分支已全部合入。打开即显示确定装备，支持六档稀有度筛选与范围内领取/回收。只 push `workspace924`。
>
> **本会话(2026-09-24 workspace924)**：合入遗匣左栏地点与溢出完整保管，以及滚轮按鼠标所在区域滚动。
>
> **遗匣**：入匣时生成完整装备，领取不重骰。筛选为全部或 1..6 品质。待整理残留不可领取或回收。
>
> **本会话(2026-09-23)**：从 `workspace` 新开 `integrate/20260923`，合入今天三条功能线 + workspace923 的一键脚本修复。含滚轮/右键装备/五语/Noto 字体、四名玩梗角色与 SE 包、未解锁职业标。未推 workspace。

---

## 1. 项目概况

- **引擎**:UrhoX(星火编辑器),Lua 5.4,单机模式(`.project/settings.json` multiplayer.enabled=false → 走 `network/Standalone.lua`,横屏 HORIZON_MODE=true)
- **原游戏**:《宿命旅途 Destiny Brigade》竖屏放置 RPG,20 个正经风冒险家角色
- **改造方向**(用户拍板):① 全角色玩梗化 ② 整体转**暗黑风格**(游戏名/标题/背景/人物图)③ 横屏标题页+背景视频化(视频未做)
- **新游戏名**:《终焉之门 Gate of Finality》
- **玩家称呼**:远征长(组织:远征队)
- **关键文件入口**:`scripts/config/HeroConfig.lua`(角色)、`scripts/ui/DarkTitleScreen.lua`(横屏标题)、`scripts/ui/LetterIntro.lua`(外祖父遗产信)、`scripts/network/Standalone.lua`(单机主循环)、`scripts/config/DialogueConfig.lua`(战斗台词)、`scripts/config/ScenarioDialogueConfig.lua`(剧情对话)

## 2. 决策时间线(为什么做成这样)

| # | 决策 | 结果 |
|---|------|------|
| 1 | 20 角色匹配玩梗形象并改名(联网调研梗背景) | 全量替换完成,词表见 CLAUDE.md |
| 2 | 真人名全部谐音化(闪电麦昆→闪电卖鸡;避开真人) | 用户明确要求避开真名 |
| 3 | 台词梗味拉满+一次性全量 | 战斗台词 24 角色(补齐 16/20-23)+剧情 73 情景重写 |
| 4 | "汪"→"叫!"(大狗嚼专属) | 全局替换,零残留 |
| 5 | 名字二轮调整:黄桃龙/阿姨压/小黑子/真布诗人;(叉腰)→(捧腹大笑);20 称号玩梗化 | 全局替换,零残留 |
| 6 | 玩家称呼:团长→远征长;冒险团/旅团→远征队(86 处) | 完成 |
| 12 | 玩家可见「冒险*」统一为远征世界观：冒险等级→远征等级、冒险家→远征队员、冒险招募券→远征招募券、冒险日志/奖励→远征日志/奖励；冒险者公会显示名沿用亡誓公会。内部键名(`adventurer`/`recruitTicket`/`playerLevel`/`guild`)不变 | 完成，分支 `feat/rename-adventure-to-expedition` |
| 7 | 游戏名改暗黑风:《终焉之门》;标题背景横屏暗黑;后续视频化 | 背景图已出,视频未做 |
| 8 | 标题页:发现现成 `DarkTitleScreen.lua`(HORIZON 横屏标题载体),只换素材/配色 | 上线,游戏内实拍验收通过 |
| 9 | 图片实装:A 方案先 3 张(#9/#11/#21)验证,再全量 20 张卡面+17 张立绘 | 实装完成,但用户验收未通过(见 §5) |
| 10 | 外祖父遗产信(LetterIntro):另一会话实现,本会话做世界观修正(远征长/火漆「终」) | 已实装,新玩家首登触发 |
| 11 | **验收未通过 → 生产管线升级**:三层参考(原版卡面+暗黑基准图+全队画风板)+强梗 prompt+暗黑背景 | 试点 #4/#5 通过,全量待做 |

## 3. 生产管线(照抄即可复现)

### 3.1 立绘生成(当前最新版管线)

```
generate_image:
  model = "gpt"(GPT Image 2)
  aspect_ratio = "2:3", target_size = "832x1248"
  reference_images(三层):
    [1] 该角色原版卡面:  /workspace/.tmp/cardref/old_{id}.png   ← 锁角色长相
    [2] 暗黑版基准构图图: /workspace/assets/image/edited_风格基准图_暗黑版_20260912224014.png ← 锁构图/背景/光线
    [3] 全队画风板:       /workspace/assets/image/全队画风板_原版卡面.png   ← 锁整体画风
  prompt 模板(替换 <梗装束> 段):
    "生成一张游戏角色卡面立绘。第一张参考图是角色原版卡面(角色长相基准):<外观描述>。
     第二张参考图是暗黑版构图规范基准图:裁切位置(七分身,头顶到大腿中部)、站姿、
     背景(深紫黑垂直渐变纯净暗幕)、光线(左上冷调主光+轮廓边缘光)必须与第二张完全一致。
     第三张参考图是全队画风板(整体画风统一参照)。
     将第一张参考图的角色 <梗装束描述,梗元素为画面主体>。
     画风与第三张参考图一致:anime game character illustration, soft cel shading。
     clean, smooth, no film grain, no noise。没有漂浮粒子、闪光点、镜头光晕。
     不添加文字、水印。"
```

- 发色**不锁**(用户明确"颜色不一定要遵循之前的,只是风格需要参考")
- 梗装束要写成**画面主体**,不能只是小配饰(验收教训)
- 20 个角色的梗装束方案见 §6 待办附表

### 3.2 卡面制作(从立绘)

```bash
# 脸部特写裁切 + 品质晕 + 紫框(⚠️ 裁切参数需逐张校准,见 §5 问题2)
convert 立绘.png -crop 362x800+235+40 +repage -resize 390x876! base.png
convert -size 390x484 xc:'gray(3%)' m1.png
convert -size 390x392 gradient:'gray(3%)-gray(90%)' m2.png
convert m1.png m2.png -append mask.png
convert -size 390x876 xc:'<品质晕色>' mask.png -alpha off -compose CopyOpacity -composite tint.png
convert base.png tint.png -compose Over -composite -bordercolor '#c35ae4' -border 10x10 KP_YX_{id}.png
```
品质晕色:R=`4a9d5c` SR=`a45fd0` SSR=`e8b83a` UR=`d0454a`(用户验收后可能要暗黑化这些晕色)
**已知问题**:统一裁切参数导致 12 张卡构图错误(脸切半/偏/空),见 §5 问题 2

### 3.3 黑白抠图法(透明 PNG,LOGO/立绘透明底用)

白底 generate_image → `edit_image(model="nanobanana")` 黑底(构图必须一致)→ ImageMagick 差分:
```bash
convert white.png black.png -compose difference -composite diff.png
convert diff.png -colorspace Gray -negate alpha.png
convert black.png alpha.png -alpha off -compose CopyOpacity -composite out.png
convert out.png -trim +repage out.png
```
产出:`assets/image/LOGO终焉之门_透明版.png`(TrueColorAlpha 已验证)

### 3.4 引擎渲染管线(资产导出/验收截图)

```bash
# 离屏截图(资产导出、UI 验收)
LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe EGL_PLATFORM=surfaceless \
timeout 280 ./.cli/UrhoXRuntime <script>.lua -tapcode_dir=/workspace -tool_mode \
  -graphicssurfaceless -screenshot=<abs path> -screenshot-frame=<N> -x <W> -y <H>
# ⚠️ timeout 给够(280s+),超时静默失败不落盘——完成后必须 stat 检查 mtime
# ⚠️ 脚本热加载正常,但 -tool_mode 资源从 pak 加载,assets 新文件需 build 后才进 pak?
#    实测 assets/image 下的图即时可见(资源目录挂载),scripts 的 .lua 实时读取
```
可复用脚本:`scripts/_proc/`(render_portrait.lua / cardref_render.lua / roster_board.lua / render_letter.lua / card_preview.lua / implement_check.lua)

### 3.5 参考图体系(重要教训)

| 参考图 | 路径 | 状态 |
|--------|------|------|
| 原版卡面(20,可靠) | `.tmp/cardref/ref_{id}.png` | ✅ 引擎渲染导出,**当前的正确参考** |
| 高清立绘 ref_1/2/3 | `.tmp/portraits_hd/ref_{1,2,3}.png` | ✅ 合格(与卡面一致) |
| 孤儿立绘 ref_5/9/10/11/13/20/21 | `.tmp/portraits_hd/` | ❌ **禁止用作角色参考**(内容与卡面角色不对应) |
| 暗黑版基准构图图 | `assets/image/edited_风格基准图_暗黑版_20260912224014.png` | ✅ |
| 全队画风板 | `assets/image/全队画风板_原版卡面.png` | ✅ 20 原卡 5x4 拼图 |
| 基准构图图(浅色版) | `assets/image/edited_风格基准图_构图规范_20260912111509.png` | 已被暗黑版取代 |

## 4. 资产与实装状态

### 4.1 已实装(游戏内生效)

| 资产 | 状态 |
|------|------|
| `assets/image/角色立绘/UI_DLH_{1..23}.png` | 20 张玩梗立绘(832x1248 PNG)全量 ✅ |
| `assets/image/角色卡牌/KP_YX_{1..23}.png` | 20 张玩梗卡面(410x896,第一版浅灰白背景)全量 ⚠️ 待重做 |
| `assets/image/UI_TITLE_BG_GATE.png` | 终焉之门标题背景 ✅ |
| `assets/image/UI_WORLD_BG.png` | 世界大背景(1920x1080 横屏空旷雾原)✅ |
| `assets/image/关卡地图/MAP_*.png`(27 张) | 统一大背景竖裁版 ✅ |
| 7 个页背景(`UI_CZ_BJ/UI_TJP_CH_1/UI_KCBJ_1/UI_KCBJ_2/UI_SCBJ/UI_JJC_BJ1/UI_JTZZBJ`) | 统一大背景竖裁版 ✅ |
| `scripts/ui/DarkTitleScreen.lua` | 终焉之门标题(紫辉粒子+新 LOGO)✅ |
| `scripts/ui/LetterIntro.lua` | 外祖父遗产信(精修版)✅ |
| `assets/image/LOGO终焉之门_透明版.png` | 游戏标题 LOGO(黑白抠图法)✅ |
| 台词/对话/名字 | 全量 ✅ |

**备份**(回滚用):`.tmp/implement_backup2/{立绘,卡牌}/`(全量实装前)、`.tmp/implement_backup/`(A 方案前)、`.tmp/worldbg_backup/`(页背景/关卡图原 KTX)

### 4.2 已生成未实装/中间产物

- 20 张玩梗立绘源 PNG:`assets/image/*立绘*.png`(与实装版相同,源文件)
- 暗黑强梗版试点:`assets/image/接化发掌门_暗黑强梗版_20260912224219.png`、`叠甲怪_暗黑强梗版_20260912224336.png`(**待用户最终验收**)
- 20 张可靠卡面参考:`.tmp/cardref/ref_{id}.png`
- `.tmp/roster_export/cards/`(**部分噪声,不要用**)、`.tmp/portraits_hd/`(高清立绘,1/2/3 合格其余孤儿)

## 5. 用户验收结论(2026-09-13,当前卡面 v1 未通过)

1. **梗浓度不足**:部分角色只加小道具(阿姨压=小话筒、弹弹弹=细弹簧、愤怒的小雀=普通蓝帽),与原卡相似度高。修法:梗装束写成画面主体(试点 #4/#5 已验证可行)
2. **缺暗黑风格**:卡面背景浅灰白与游戏暗黑风不符。修法:三层参考管线(暗黑基准图),试点已验证
3. **裁切比例有误**(12 张):#1/#6 裁到只剩头发、#4 脸偏右、#11/#12/#13/#22 脸切半、#14 裁到袍子、#16 近全空、#20 切脸、#23 帽子挡脸。根因:统一裁切参数(362x800+235+40)不匹配各立绘脸部位置。修法:**逐张看立绘定 crop 参数**(校准底图:`assets/image/当前卡面_校准底图.png`),或重生成时用暗黑基准图锁定构图后统一参数
4. 合格 8 张可保留:#2/#3/#8/#9/#10/#15/#21(+#5/#4 已重做待验)

## 6. 待办清单(下一个 agent 按序执行)

1. **[P0] 试点 #4/#5 最终确认**(图:`assets/image/暗黑强梗版_试点预览.png`)→ 用户点头后:
2. **[P0] 全量 20 张立绘重做**(§3.1 管线,梗装束方案:
   大狗嚼=马犬拟人+叼骨+项圈 | 黄桃龙=恐龙连体帽+呆萌 | 叮咚鸡=鸡帽+门铃弓 | 接化发掌门=黑太极服+三段手印✅ | 叠甲怪=塔状层叠甲+盾帽✅ | 阿姨压=墨镜+巨型复古麦+音浪 | 信光机兵=红银紧身衣+计时器 | 愤怒的小雀=蓝羽卫衣+巨弹弓 | 卡皮巴拉=水豚头套+顶橘+抱水豚 | 铁憨憨=扛铁门+憨笑 | 熬夜冠军=黑眼圈+刀+咖啡+新月 | 雪皇=金冠+红斗篷+冰淇淋权杖 | 弹弹弹=巨弹弓+粗弹簧+卡通拳 | 内鬼=黑袍+墨镜+嘘手势 | 复活吧爱人=修女+复活光环 | 万剑归宗=白衣剑仙+万剑悬空 | 摘星星星人=白色飞天航天服+星星网兜+星门 | 闪电卖鸡=红赛车服95号+墨镜鸡 | 小黑子=中分白衬衫棕背带裤+篮球+白公鸡 | 真布诗人=绿羽帽+墨镜金链+复古麦)
3. **[P0] 卡面裁切逐张校准**(§5 问题 3)→ 品质晕暗黑化(深紫/暗金/暗红,用户暗示不要亮晕)→ 实装
4. **[P1] 图标 P3**:20 个 `UI_icon_hero_{id}.png` 从新卡面/立绘裁切
5. **[P1] 标题背景视频化**:以终焉之门图为首帧(紫光呼吸/云层流动),`create_video_task`
6. **[P1] 入队台词**(挂起):DialogueConfig 加 join 触发(24 角色)+ RecruitAnim 招募展示接入(调研到一半:`RecruitAnim.lua` 卡牌展示,`TavernPopups.lua` 15:11 后未被并行会话编辑)
7. **[P2] 牢大角色**:高风险(真人逝者梗),建议黑曼巴蛇拟人替代,用户未定;新角色槽位 17 或 24,需要 HeroConfig+TalentManager+素材三件套+GachaConfig+TavernConfig+ArenaAITemplates
8. **[P2] 竖屏 StartScreen fallback 的旧 LOGO**(横屏下已被跳过,代码保留)
9. **[观察] 人物图暗黑化**:用户说"或许还要影响到人物图"——立绘暗黑化试点未做,等用户拍板

## 7. 坑与抗体(全部实测踩过)

1. **并行 agent 会话互相覆盖文件**(已发生 2 次:LetterIntro 被覆盖回旧版、HorizonBg 中间态)。开工前 `stat` 关键文件;发现语义漂移立即和用户确认
2. **assets 的 .png=KTX 纹理**:ImageMagick 读不了(`improper image header`);`Texture2D:GetImage()` 压缩纹理出噪声;唯一可靠导出=surfaceless 渲染截图
3. **-screenshot 超时静默失败**:exit 0 但文件不落盘;必须 stat mtime 验证;软渲染预算:1600x900×240帧≈100s,1080x2400×60帧≈90-150s
4. **build LSP 挡类型标注**:`nvgCreateImage`→`integer?`;修法 `or -1`+`---@return integer`;行内 `---@diagnostic disable-line: xxx`
5. **nvgClip 不存在**;nvgScissor/nvgIntersectScissor 存在;ImagePattern+RoundedRect 填充自带裁切
6. **nvgImagePattern 映射**:pattern 尺寸与 nvgRect 尺寸必须一致,否则内容错位
7. **全角括号 sed 不稳定**:`sed 's/(叉腰)//'` 失败,用 python `'\uff08...\uff09'`
8. **generate_image 中文文件名输出**:带时间戳,引用时先 ls 确认全名
9. **真人梗高风险**:牢大(科比逝者梗)→ 建议"黑曼巴拟人"替代;ikun 梗用软化变体("只因你太美"原句可用但避免真名)
10. **多角色参考图实测**:`reference_images` 3 层(角色卡面+基准图+画风板)效果最好;20 张全塞不行(上限 13-14)

## 8. 对话系统结构(改台词时看)

- `DialogueConfig.lua`:LINES[heroId] = {entry/crit/kill/death/victory},`get(heroId, type)` 数组随机;24 角色全配
- `ScenarioDialogueConfig.lua`:SCENARIO_1~73(无 66),mode=large/small,steps[].characterId(1=大狗嚼 2=黄桃龙 3=叮咚鸡 4=??? 5=神秘少女 6/7/8=假角色 9=村长 10=铁匠 11=卫兵 13=老板娘 21=圣女),rewards(equip/hero/scroll);触发在 `network/ClientScenarioHelper` + `Client.lua`(playFirstVisit(id, branchTable, cb),branchTable 按 heroId 分支)
- 战斗台词触发:`DialogueConfig.get` 由战斗系统调用(entry/crit/kill/death/victory)

## 9. 用户画像(observed,待下一 agent 续充)

- 决策快,验收严:每轮交付都逐张看图挑毛病,不接受"差不多"
- 喜欢玩梗浓度拉满,但**避开真人真名**(自发提出谐音化)
- 会在多个 agent 会话并行推进同一项目(⚠️ 见抗体 1)
- 常用笔误:"例会"→立绘、"该名字"→改名字,理解意图勿纠结字面
- 倾向"先试点看效果,再全量"的节奏(A 方案、暗黑强梗试点均如此)
