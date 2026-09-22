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

- 合并 `origin/workspace` 进重构分支：`fa7a775`（已 push）
  - workspace 4 提交：中缝条 C 款 + ICON_UP、礼拜堂标签偏移、ZBBJ 暗黑框、791 资源 meta
  - 唯一冲突：`scripts/network/Standalone.lua`（重构已抽出 `StandaloneHorizon`）
  - 保留重构侧 `require("network.StandaloneHorizon")`，并把 workspace 的 `SEAMBAR_ASPECT` 补进 `StandaloneHorizon.seamBackList`
- LSP Error=0；build 成功；validate `lua_errors=0`（engine shader/spike 噪音忽略）
- TalentManager 仍 2691，是唯一 >2500 的脚本

## likely_next_task

- 继续压 TalentManager（唯一仍超 2500）
- 城镇页 Market / Church / Blacksmith 可继续抽玩法子页
- Client HandleUpdate（仍 ~1844）

## 用户硬性流程（必须遵守）

- **不能取消/退出任务**；每步完成后必须用 AskUserQuestion 给选项，禁止纯文字中断
- 以 `refactor/extract-battle-overlays` 继续开发，完成后每次 push 该分支，**禁止推 workspace**
- 只抽模块、不改玩法；对外 API 尽量保持

## 避雷清单（摘要）

- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- BattleResultPanel 的 arenaMode 是通用参数（Dungeon 传 false），别误删
- 追加技层数跟角色走（roster.extraTalent）；对手 createHero(..., false) 不要套本地层
- 击杀认定用 `_killedBy`；弹射击杀用 `_killedByRicochet`
- 本地不要再生成/提交额外 `assets/**/*.meta`（workspace 已入库 791 个；merge 前清掉未跟踪 meta）
- 脏工作区（`.agent` / `project.json` / 未跟踪 meta）会让 `git merge` 直接失败且不建 MERGE_HEAD
- Lua 5.4 字符串里不要写 `\!`（非法转义，启动即崩）
- 抽取英雄天赋模块必须 `require("systems.ExtraTalentSystem")`，悬空 `---@param` 会挡 LSP 构建
- LSP 冷启动会漏检：首次 build 放行、二次才报 Error
