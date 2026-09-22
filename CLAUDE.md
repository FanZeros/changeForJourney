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

- 已合并 `origin/workspace`（`fa7a775`）
- T23–T26 四块抽取（LSP 0 Error / build 过 / validate lua_errors=0）
- T27：Market/Blacksmith `drawPageImpl` → `MarketDraw` / `BlacksmithDraw`
- T28：Market 输入 → `MarketInput`（1402 行）
- T29：单机 `sendAction` 走 `network.GameAction` → LocalActionBridge；UI 不再加载 Client。联网仍转发 Client。不能删 Client.lua。

## likely_next_task

- ChurchPage 仍 1873，勿用 `_ENV`，可抽具名 bind 助手
- TalentManager 1728 可再拆 onBeforeAttack / onDamageTaken
- Blacksmith 输入可对称 MarketInput

## 用户硬性流程（必须遵守）

- **不能取消/退出任务**；每步完成后必须用 AskUserQuestion 给选项，禁止纯文字中断
- 以 `refactor/extract-battle-overlays` 继续开发，完成后每次 push 该分支，**禁止推 workspace**
- 只抽模块、不改玩法；对外 API 尽量保持

## 避雷清单（摘要）

- 抽取模块读 `TAL_BCS` 必须 `getTAL_BCS()`，bind 时快照会在 `TAL.mount` 后过期
- Church/大页 `_ENV = E` 会让 LSP 报满屏 undefined-global Error，挡 build；用 bind(deps) 具名注入
- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- Lua 5.4 字符串里不要写 `\!`
- 脏工作区会让 `git merge` 失败且不建 MERGE_HEAD
- 禁止推 `workspace`
