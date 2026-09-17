# 终焉之门 · 项目记忆快照

> 本文件由记忆系统维护（会话启动时先读本文件与 docs/memory-index.md）。

## 恢复指令

1. 读 `docs/memory-index.md`（项目详细上下文）
2. 读 `docs/山海经怪兽替换交接.md`（**当前进行中任务的完整交接**）
3. 自测：这是什么项目？上次做了什么？下一步做什么？
4. 告知用户记忆恢复状态，开始工作

## 项目是什么

- **终焉之门·单机版**（Gate of Finality，原《宿命旅途 Destiny Brigade》）：UrhoX Lua 卡牌放置 RPG，NanoVG 纯 2D 渲染
- 本工作区即 Maker 项目根：`/workspace`，entry `scripts/main.lua`，单机（`multiplayer.enabled=false` → `network/Standalone.lua`）
- GitHub：`https://github.com/FanZeros/changeForJourney`，当前检出 **`workspace` 分支**
- 线上 Pages：https://fanzeros.github.io/changeForJourney/
- Electron 离线壳：`electron-shell/`（Release: tag win64-v1.0.1）

## 上次做了什么（截至 2026-09-17）

1. 新工作区从 `origin/workspace@d790dc0` 落地并完成单机 build
2. **修复角色详情右侧栏重复返回按钮**：三行模式下页内 `drawBackChevron` 与中缝层返回键叠画。`H_SEAM_BACK=true` 时详情/铁匠/教堂/酒馆/竞技场/市场不再画页内返回，只保留中缝那一颗。已 build。

## Git 状态(2026-09-17)

- 分支：`workspace` tracking `origin/workspace`
- 远程 URL 不含 PAT
- 本环境 `project.json` 的 `project_id` 是 Maker 运行时 ID，勿提交回共享分支
- 用户曾在会话明文给出 PAT：**务必在 GitHub 撤销/轮换**

## likely_next_task

等用户验收右侧栏返回按钮修复；挂起方向仍是山海经立绘入包 / 暗黑强梗立绘重做。

## 避雷清单（摘要）

- 🔴 三行模式 `H_SEAM_BACK`：二级页返回键只由 Standalone 中缝层绘制；页内再画就会叠一颗
- 🔴 多 agent 并行：push 前必须 fetch
- 🔴 `/workspace/assets/**/*.meta` 承载 uuid，替换图片绝不动 .meta
- `git add` 只用显式路径；`dist/` 不手改
