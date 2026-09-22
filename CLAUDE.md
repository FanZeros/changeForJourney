# 终焉之门 · 项目记忆快照

> 本文件由记忆系统维护（会话启动时先读本文件与 docs/memory-index.md）。

## 恢复指令

1. 读 `docs/memory-index.md`（项目详细上下文）
2. 读 `docs/refactor-plan.md` + `docs/refactor-tasks.md`（重构进度）
3. 自测：这是什么项目？上次做了什么？下一步做什么？
4. 告知用户记忆恢复状态，开始工作

## 项目是什么

- **终焉之门·单机版**：UrhoX Lua 卡牌放置 RPG，NanoVG 纯 2D，横屏三栏
- 入口 `scripts/main.lua`，单机 `network/Standalone.lua`
- GitHub：`FanZeros/changeForJourney`
- **当前开发分支**：`refactor/extract-battle-overlays`（禁止推 `workspace`）

## 上次做了什么（截至 2026-09-22）

- 部署该重构分支并预览；修了 Lua 5.4 `\!` 启动崩溃 + TalentMelissa/Luoxing 丢失 ETS 依赖（`d4914f8`）
- T11：从 BattleCombat 抽出卡牌动画状态机到 `scripts/ui/BattleCombatAnim.lua`（`a3f6930` 已 push）
- BattleCombat 2101 → 1822 行；对外 API（`updateCardAnims` / `playEnterAnims` / `setCardAnim` 等）保持委托
- T12：TalentManager 再拆 Alex/Elwyn/Sera/Suhua 到 `systems/talents/`（`3e9920f` 已 push）；3570 → 3276 行
- T13：Client 抽出启动接线到 `network/ClientBoot.lua`（`a9c2566` 已 push）；2487 → 2143 行
- T14：BattleScene 抽出死亡补位/胜负判定到 `BattleCasualty.lua`（`ebc1db4`）
- T15–T18（`88ccd19`）：连击 Combo、loadStage、TAL.update、ClientRender 均已 push

当前行数：TalentManager 2838 / BattleScene 1890 / Client 1844 / Blacksmith 1780 / Server 1693 / BattleCombat 1637

T19–T21 已 push：`e16c12c` ServerEnterGame / `f6689b0` BattleSceneTick / `24eb755` 城镇页 DrawUtil 委托

## likely_next_task

- TalentManager 仍 2838（唯一仍超 2500）
- 城镇页 Market 1853 / Church 1873 / Blacksmith 1780 可继续抽玩法子页
- Client HandleUpdate（仍 1844）

## 用户硬性流程（必须遵守）

- **不能取消/退出任务**；每步完成后必须用 AskUserQuestion 给选项，禁止纯文字中断
- 以 `refactor/extract-battle-overlays` 继续开发，完成后每次 push 该分支，**禁止推 workspace**
- 只抽模块、不改玩法；对外 API 尽量保持

## 避雷清单（摘要）

- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- BattleResultPanel 的 arenaMode 是通用参数（Dungeon 传 false），别误删
- 追加技层数跟角色走（roster.extraTalent）；对手 createHero(..., false) 不要套本地层
- 击杀认定用 `_killedBy`；弹射击杀用 `_killedByRicochet`
- `/workspace/assets/**/*.meta` 绝不动
- Lua 5.4 字符串里不要写 `\!`（非法转义，启动即崩）
- 抽取英雄天赋模块必须 `require("systems.ExtraTalentSystem")`，悬空 `---@param` 会挡 LSP 构建
- LSP 冷启动会漏检：首次 build 放行、二次才报 Error
