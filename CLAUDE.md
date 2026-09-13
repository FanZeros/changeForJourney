# 宿命旅途 · 项目记忆快照

> 本文件由记忆系统维护（会话启动时先读本文件与 docs/memory-index.md）。

## 恢复指令

1. 读 `docs/memory-index.md`（项目详细上下文）
2. 读 `docs/山海经怪兽替换交接.md`（**当前进行中任务的完整交接**）
3. 读 `/workspace/changeForJourney/docs/COLLABORATION.md`（多 agent 协作约定，必读）
4. 自测：这是什么项目？上次做了什么？下一步做什么？
5. 告知用户记忆恢复状态，开始工作

## 项目是什么

- **宿命旅途·单机版**（Destiny Brigade）：UrhoX Lua 卡牌放置 RPG，NanoVG 纯 2D 渲染
- 双工作区：`/workspace`（Maker 开发项目 m_vvp3，entry main.lua）+ `/workspace/changeForJourney`（GitHub Pages 自部署仓库 github.com/FanZeros/changeForJourney）
- 线上：https://fanzeros.github.io/changeForJourney/ （Pages 服务 main 根目录，引导器 + CRC32 内容寻址资产）
- 另有 Electron Windows 离线壳：`/workspace/electron-shell`（Release: tag win64-v1.0.1）

## 上次做了什么（截至 2026-09-13）

1. 横屏暗黑标题 DarkTitleScreen（已上线）
2. 先祖来信首登剧情 LetterIntro（已上线）
3. sw-coop 引擎静态资源本地缓存（CDN max-age=5 对策，已上线）
4. **山海经怪兽替换第一期**：64 怪攻击保真改名（已上线 main@1d7f70d）
5. 底板 B「深褐古卷」定稿 + 底板+提示词一体合成工作流验证（天狗样张通过）

## Git 状态(2026-09-13)

本地分支 workspace2(注意:本地旧 workspace 分支仍在,勿混淆),已 rebase 到 origin/workspace 最新并推送:**6521132 → origin/workspace**(含终焉之门 v2.1 全部恢复+另一会话市场/盾条 6 提交)。PAT 已使用,**建议用户在 GitHub 撤销/轮换该 token**(曾在会话中明文出现)。另:本地还存在一个旧名 workspace 分支,与远端 workspace 同名但不同步,忽略即可。

## likely_next_task

**山海经替换第二期：63 张水墨立绘合成入包**。完整映射表、合成提示词模板、
部署管线、避雷清单 → **`docs/山海经怪兽替换交接.md`（先读它）**。

## 避雷清单（摘要，详单见交接文档 §八）

- 🔴 多 agent 并行：另一协作会话持续推 feat/main，**push 前必须 fetch**；dist 层只准 CRC32 管线生成（仓库 docs/COLLABORATION.md）
- 🔴 `/workspace/assets/**/*.meta` 承载 uuid，替换图片**绝不动 .meta**
- `git add` 只用显式路径（assets-restored/ 506M 垃圾、__pycache__/ 严禁入库）
- GitHub Release 资产名只能 ASCII；Pages/Fastly 缓存 max-age=600
- 用户 PAT 曾在会话明文出现，已提醒撤销；push 无凭证时向用户索要新 PAT
