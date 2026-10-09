# memory-index — 《终焉之门》项目现状索引

> 本文件描述**当前项目状态**：代码结构、系统清单、关键约束与待办。
> 不记录任何历史修改、分支、PR、日期或交接过程（见 `CLAUDE.md` 文档规范）。

## 1. 项目概览

- **终焉之门·单机版**：UrhoX Lua 卡牌放置 RPG，NanoVG 纯 2D，横屏三栏，暗黑魔塔画风。
- 运行形态单机：入口 `scripts/main.lua` → `boot/Standalone.lua`；规则层在 `rules/`，经 `runtime/LocalActionBridge.lua` 本地直调；存档单文件 `standalone_save.json`。
- 权威玩法文档：`docs/changeForJourney-gameplay.md`。

## 2. 代码结构（`scripts/`）

| 目录 | 职责 |
|---|---|
| `boot/` | `Standalone.lua`（启动/导航）、`StandaloneHorizon.lua`（横屏三栏渲染与输入总控）、`StandaloneSave.lua`（存档） |
| `config/` | 静态配置：英雄、职业、关卡（15 难度文件）、装备、套装、词缀、天赋、抽卡、副本、塔、引导、黑smith |
| `core/` | 引擎无关基础设施：`Viewport.lua`（三栏视口）、`DarkIcon.lua`（矢量 UI 绘制）、`I18n.lua` + `i18n/`（多语言）、`DrawUtil.lua` |
| `rules/` | 规则层：artifact / advancement / awakening / battle / blacksmith / character / currency / dungeon / equipment / gacha / gm / hero / loot / market / offline / redeem / signin / sweep / talent / task / tower |
| `runtime/` | `LocalActionBridge.lua`（动作直调）、`ClientMessageHandler.lua`（数据推送处理） |
| `shared/` | 数据 Schema 与纯数据：`schemas/`、`talent/`、`artifact/`、`equipment/`、`dungeon/`、`sweep/`、`heroes/`、`currency/`、`market/` 等 |
| `systems/` | 运行时系统：属性/派生、战斗公式、掉落、离线计算、天赋效果、神器桥接、套装运行时、护盾成长层、Boss 词缀、超时增伤、战斗统计 |
| `ui/` | 全部界面（见 §4） |
| `tests/` | 回归测试，独立进程 headless 运行 |
| `_proc/` | 离线工具与探针（不参与运行时） |

## 3. 玩法系统现状（要点）

完整数值与规则见 `docs/changeForJourney-gameplay.md`；此处仅列索引与关键事实。

- **英雄**：25 名（id 1–25）。品质普通/稀有/史诗/传说（机制值 1–4）。英雄与玩家等级上限 200。
- **六契职业**：`seal` 封门人 / `spoil` 拾骸者 / `rift` 裂隙使 / `echo` 回响客 / `mask` 换面人 / `debt` 司仪；每职业一个被动天赋 + 可用护甲类型限制。
- **编队**：3 队 × 最多 4 槽；队 1 开局解锁，队 2/队 3 分别通关普通 9-5 / 19-5 解锁；槽位按远征等级 Lv2/Lv6/Lv10 递增至 4。
- **战斗**：全自动放置，三行并行；无手动操作、无技能、无战斗倍速。首通限时 300 秒；狂暴与超时增伤见玩法文档 §3。
- **关卡**：15 难度 × 23 章 × 5 关 = 1725 关；终焉神殿 14 座（湮灭 V 无）。
- **装备**：6 槽位（主手/副手/护甲/头盔/鞋子/饰品），模板约 358 件；12 套装，2/4/6 件效果，4/6 件互斥、两套 2 件可同亮；双手武器 5 件按 6 件计。
- **锻造**：升阶（每 5 阶得随机词条，上限 4 条，满员后转栏位倍率）、洗练（固定单价 + 锁定阶梯倍率）、分解、腐化/魔化、神圣石净化。
- **神器**：16 种；每队 4 号位 × 2 子格；抽取/合成/置换/洗练；三行同时装配展示。
- **天赋**：209 节点星图，272 条无向邻接；入口为城镇"终焉古树"。
- **转职**：一转 12 支（Lv10 + 1 万金币）、二转 24 支（Lv30 + 10 万金币）；入口在角色详情页。
- **觉醒**：3 阶，碎片消耗 10/30/50。
- **副本**：黄金矿洞 / 装备宝库 / 黑钻矿洞（资源副本）+ 通天塔（112 层，每层 1 波，每 5 层 checkpoint）。
- **挂机与离线**：每 3 秒 1 只怪；前 24 小时满额、超出 50%、7 日硬顶。

## 4. 界面结构（`ui/`）

- **横屏三栏**（base 1920×1080，左/中/右各 486）：左 = 城镇与二级页，中 = 战斗/副本，右 = 角色常驻。
- **左栏城镇建筑**：教堂（神器）、终焉古树（天赋）、酒馆（抽卡+商店）、市场（月蚀黑市）、铁匠铺（狱火锻炉）、仓库、遗匣、功绩。
- **中栏**：主线三行战斗、副本/通天塔全屏接管页、全局弹窗层。
- **右栏**：编队（3 队 × 4 槽）、名册、角色详情（属性/配装/转职/觉醒）。
- **HUD**：`TopBar`（头像/等级/经验/战力/货币）、`BottomNav`（纯状态模块，不绘制）。

## 5. 数据与存档

- 单文件 `standalone_save.json`，临时文件原子 Rename 提交；`version=1`，含 `savedAt/gameState/modules`。
- `gameState` 为单机货币/等级/经验真源；`modules` 按子系统存（player/currency/heroes/equipment/battle/lootbox/talents/artifact/dungeon/tower…）。
- 规则层数据经 PDM 模块读写，各模块有对应 `shared/*/…Schema.lua` 归一化。

## 6. 多语言与美术

- **多语言**：`core/I18n.lua` 运行时五语切换（简/繁/英/日/韩）；词表在 `core/i18n/`。引擎 i18n 保持关闭。
- **UI 绘制**：`core/DarkIcon.lua` 程序化矢量绘制面板/按钮/凹槽/品质框。
- **字体**：Noto Sans CJK KR Bold 为主字体。
- **美术资源**：`assets/image/` 分目录（城镇/战斗/弹窗/装备图标/套装图标/角色立绘/背景等）。

## 7. 当前待办与已知限制

- **遗物系统**：数据层与战斗层保留（`RelicBridge`、`rules/relic`、`Protocol` 的 RELIC_* 动作），玩家侧管理 UI 未重建；旧上古遗迹入口隐藏，仅保留既有粉尘存量兼容。
- **签到/公告/旧任务面板**：面板已移除，数据与服务层保留（存档兼容）；现行任务入口是功绩页 `TaskPage`。
- **存档可靠性**：直接覆盖主存档、损坏 JSON 按新档处理仍存在丢档风险，原子替换/备份恢复未实现。
- **战斗实验室**：`tests/battle_lab_ui.lua` / `tests/battle_lab.lua` 需独立进程运行，勿在游戏主进程并行（会污染共享战斗状态）。
- **角色/套装强度**：完整 25 角色 × 12 套的端到端强度矩阵与视觉操作验收未完成。
- **无头环境限制**：Linux UrhoXRuntime 不支持离屏截图，视觉效果需真人预览验收。

## 8. 相关文档

| 文档 | 内容 |
|---|---|
| `docs/README.md` | 文档索引与规范 |
| `docs/changeForJourney-gameplay.md` | 玩法权威文档 |
| `docs/剧情总表.md` | 剧情情景与触发 |
| `docs/versions.md` | 版本与发布状态 |
| `docs/装备套装效果规划.md` | 套装效果与归属 |
| `docs/护盾成长层设计.md` | 护盾成长层公式与调参 |
| `docs/统一角色框方案.md` | 角色头像框统一组件 |
| `docs/游戏背景画风与提示词规范.md` | 背景美术规范 |
| `docs/剧情背景规划与提示词.md` | 剧情背景与提示词 |
| `docs/角色CG制作规范.md` | 觉醒 CG 制作规范 |
| `docs/装备图片待办-20261008.md` | 装备图标现状与待办 |
| `docs/persona.md` | 协作者画像与协作偏好 |
| `docs/pc-protection-research-0927.md` | PC 包保护方案 |
| `docs/pc-obfuscation-similarity-0928.md` | 混淆效果实测 |
