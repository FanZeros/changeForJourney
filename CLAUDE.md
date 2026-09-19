# 终焉之门 · 项目记忆快照

> 本文件由记忆系统维护（会话启动时先读本文件与 docs/memory-index.md）。

## 恢复指令

1. 读 `docs/memory-index.md`（项目详细上下文）
2. 读 `docs/山海经怪兽替换交接.md`（挂起任务交接）
3. 自测：这是什么项目？上次做了什么？下一步做什么？
4. 告知用户记忆恢复状态，开始工作

## 项目是什么

- **终焉之门·单机版**：UrhoX Lua 卡牌放置 RPG，NanoVG 纯 2D，横屏三栏
- 入口 `scripts/main.lua`，单机 `network/Standalone.lua`
- GitHub：`FanZeros/changeForJourney` 分支 `workspace`

## 上次做了什么（截至 2026-09-19）

竞技场功能彻底删除（d1d36e5）：13 个 Arena 文件删净，Standalone/Client/LocalActionBridge/TownScene/任务/引导/剧情(情景54)/货币(竞技券/币)/Protocol 全链清理。特权点保留现状（无获取渠道，洗练/UR恢复锁死，用户已拍板不动）。

## likely_next_task

- 素材清理二轮：竞技场图（竞技场排行/ 目录、UI_CZ_JJC、ICON_CZ_JJC、UI_icon_JJCQ/JJB）现已无引用，可删（UI_JJC_BTBJ 仍被 TaskPanel/TavernShopPage 共用需保留）
- 特权点后续：若做获取渠道或改计价再动 ArtifactService/HeroService

## 避雷清单（摘要）

- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- ~~竞技场~~已删除；BattleResultPanel 的 arenaMode 是通用参数（Dungeon 传 false），别误删
- 追加技层数跟角色走（roster.extraTalent），对手 createHero(..., false) 不要套本地层
- 击杀认定用 `_killedBy`；弹射击杀用 `_killedByRicochet`
- `/workspace/assets/**/*.meta` 绝不动
