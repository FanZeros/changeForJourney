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

1. **本会话**：从 `FanZeros/changeForJourney` 的 `workspace` 分支拉取并落到 `/workspace`
   - HEAD：`d790dc0`（`fix: 角色/敌人立绘等比裁切不拉伸`）
   - 已构建，入口 `main.lua`，单机模式
   - 本环境 `project_id` 被 build 写成 `m_2h73`（相对仓库里的 `m_bk73`，**不提交回共享分支**）
2. 历史：横屏暗黑标题、先祖来信、山海经怪兽第一期改名、底板 B 定稿、暗黑强梗试点

## Git 状态(2026-09-17)

- 分支：`workspace` tracking `origin/workspace`
- HEAD：`d790dc0`
- 远程 URL 不含 PAT（credential.helper=store）
- 用户曾在会话明文给出 PAT：**务必在 GitHub 撤销/轮换**

## likely_next_task

**等用户下指令。** 记忆里挂起的方向仍是：

1. 山海经替换第二期：63 张水墨立绘合成入包（见 `docs/山海经怪兽替换交接.md`）
2. 全量 20 张暗黑强梗立绘/卡面重做（见 `docs/memory-index.md` §6）

## 避雷清单（摘要）

- 🔴 多 agent 并行：push 前必须 fetch；不要覆盖另一会话未提交改动
- 🔴 `/workspace/assets/**/*.meta` 承载 uuid，替换图片**绝不动 .meta**
- `git add` 只用显式路径；`dist/` 不手改
- 用户 PAT 曾明文出现，已提醒撤销
- 本环境 `project.json` 的 `project_id` 是 Maker 运行时 ID，勿当玩法改动提交
