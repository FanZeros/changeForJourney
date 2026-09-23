# 终焉之门 · 项目记忆快照

> 本文件由记忆系统维护（会话启动时先读本文件与 docs/memory-index.md）。

## 恢复指令

1. 读 `docs/memory-index.md`（项目详细上下文）
2. 读 `docs/refactor-plan.md` + `docs/refactor-tasks.md`（重构进度）
3. 自测：这是什么项目？上次做了什么？下一步做什么？
4. 告知用户记忆恢复状态，开始工作

## 项目是什么

- **终焉之门·单机版**：UrhoX Lua 卡牌放置 RPG，NanoVG 纯 2D，横屏三栏
- 入口 `scripts/main.lua` → 只加载 `network/Standalone.lua`（已无多人 Client/Server 入口）
- GitHub：`FanZeros/changeForJourney`
- **当前开发分支**：`feat/four-meme-heroes`（从 workspace 拉出；四人新角色已接入；SE 已换 RPG Maker 包）

## 上次做了什么（截至 2026-09-23 SE 替换）

- 用户上传 `assets/video/se.mp4`（实为 ZIP，RPG Maker VX Ace 风格 SE 包）
- 已用包内 ogg 覆盖全部现有 UI/战斗 SE（键名路径不变）
- 新角色 #18/#19/#24/#25 补独立攻击 SE + 投射物配置（图复用相近特效）
  - 老六 Darkness4 / 哈基米 Cat / 加载中 Load / 高ping Transceiver
- 未改 BGM；未合入 workspace
- 用户反馈新 SE 太大：Effect 通道乘 `SFX_PACK_GAIN=0.10` 试听（设置滑条仍相对调节）

## 更早：截至 2026-09-23 四人新角色

- 拍板并实装四名玩梗角色（替代立绘）：
  - #18 R 换面 **老六**（蹲人：开战 4 秒 0 仇恨，第一击必暴）
  - #19 R 司仪 **哈基米 / 南北路多**（功德+1，满 5 清心减伤，不改死亡）
  - #24 SSR 封门 **加载中**（受击写入缓冲条，满条/超时吐出粉碎伤）
  - #25 UR 回响 **高ping战士**（普攻后再延迟 1.5s 打 45% 额外穿刺伤，10% 仇恨）
- 卡池/酒馆碎片/觉醒/台词/天赋均已接；图像为替代物，后续可换正稿
- 已 push `origin/feat/four-meme-heroes`
- 二次核对补漏：酒馆碎片映射 20/21/22/104、星辉池补 #17、ETS 名称+粗暴叠层、AssetManifest 新图、玩法文档 25 人、图鉴 UR 色

## 更早：截至 2026-09-22 晚 整合

- 已把今天三线合进 `workspace` 并推送：
  1. `docs/equip-set-and-class-migration`（套装 P1 + 六契 + 1.5 竖屏天赋树，此前已在 workspace）
  2. `refactor/extract-battle-overlays` 独有：星图视口剔除 + CharacterPower/Progress 抽取；套装加成补进 CharacterPower
  3. `feat/rename-adventure-to-expedition`：冒险等级→远征等级等玩家可见文案
- 冲突处理原则：保留 workspace 六契/套装玩法，只把「冒险*」改成「远征*」；内部键名不变

## 更早：截至 2026-09-22 古树天赋

- 已合并 `origin/workspace`（`fa7a775`）
- T23–T26 四块抽取（LSP 0 Error / build 过 / validate lua_errors=0）
- T27：Market/Blacksmith `drawPageImpl` → `MarketDraw` / `BlacksmithDraw`
- T28：Market 输入 → `MarketInput`（1402 行）
- T29：单机 `sendAction` 走 `network.GameAction` → LocalActionBridge
- T30：去掉多人入口。已删 Client/Server 联网壳
- T31：删除 GuildPage / CharacterSelect / LoadingScreen；消息处理器与 Debug 解绑
- T32：卸掉 StartScreen 选服并删除 ServerSelectPanel；点击直接进游戏。横屏仍 DarkTitleScreen
- T33：删除 VersionMismatchPopup、GuildHandler/GuildService；城镇卸空公会回调。GuildConfig 排行保留
- T34：ChurchPage `drawPageImpl` → ChurchDraw（bind 具名注入）。ChurchPage 1416
- T35：Church 输入/名单 + Talent 攻前/受伤 + Blacksmith 输入。Church 1060 / Talent 1315 / Blacksmith 1384
- T36：Talent 减伤/复活 + Church 槽位动画 + Blacksmith 结果转发。Talent 1116 / Church 1004 / Blacksmith 1337
- hotfix：敌人死亡误变墓碑。根因 BattleCasualty 写 `stageKillCount_`，BattleScene 注入 `stageKillCount`。`8a41499`
- T37：ChurchPage.init → ChurchInit；Talent onEnemyDeath/checkMarkTarget → TalentEnemyDeath。Church 918 / Talent 1032
- T38：ChurchBadge + TalentComboAttack + BlacksmithEnhanceCache + MarketCollection。Church 893 / Talent 1030 / Blacksmith 1244 / Market 1173
- T39：BattleScene 导航/轮回 → BattleStageNavLogic；setBattleData → BattleDataRestore。BattleScene 1605
- T40：ChurchResults + MarketResults。Church 812 / Market 1045
- T41：ChurchLifecycle + MarketInit。Church 790 / Market 1008
- T42：CharacterDeploy + BackpackDialogs。Character 1733 / Backpack 1737
- 天赋从教堂拆出：城镇中轴新建筑「终焉古树」打开 `TalentPage`；教堂只留转职/神器两 Tab
- 星图视口改为 1:1（1080×1080 居中）；滚轮带鼠标坐标直接缩放

## likely_next_task

- 试听新 SE / 四人战斗音效是否合适
- 四人立绘正稿（当前仍是替代图）
- 合入 workspace（需用户本轮明确要求）
- BattleScene 1605，可再抽 init/draw/handleInput
- ChurchPage 790，主壳已较瘦
- MarketPage 1008，可再抽商店道具网格
- CharacterPanel 1733 / BackpackPanel 1737 仍是最大页，可再抽详情绘制/输入
- BlacksmithPage 1244 上半绘制依赖局部图太多，勿盲目抽 init
- ServerListConfig / GuildConfig 仍被存档与云排行使用，勿当死代码删

## 用户硬性流程（必须遵守）

- **不能取消/退出任务**；每步完成后必须用 AskUserQuestion 给选项，禁止纯文字中断
- 以当前功能分支继续开发；完成后每次 push **该分支**。本次用户明确要求合入并推送 `workspace`。
- 只抽模块、不改玩法；对外 API 尽量保持

## 避雷清单（摘要）

- 抽取模块读 `TAL_BCS` 必须 `getTAL_BCS()`，bind 时快照会在 `TAL.mount` 后过期
- Church/大页 `_ENV = E` 会让 LSP 报满屏 undefined-global Error，挡 build；用 bind(deps) 具名注入
- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- Lua 5.4 字符串里不要写 `\!`
- 脏工作区会让 `git merge` 失败且不建 MERGE_HEAD
- 禁止推 `workspace`
