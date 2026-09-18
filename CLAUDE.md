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

## 上次做了什么（截至 2026-09-18）

1. 全员天赋改名对齐梗人设（希望之心→衔骨狂 等）
2. 5 个主技能加轻量机制：衔骨狂攻速 / 已读不回必暴 / 必杀光线 / 氮气贯穿 / 抄作业偷攻速
3. 通宵斩残血加伤、护盾说唱押韵伤一并落地

## likely_next_task

验收改名+机制手感；其余 16 人追加技仍可铺。

## 避雷清单（摘要）

- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- 追加技层数跟角色走（roster.extraTalent），竞技场对手 createHero(..., false) 不要套本地层
- 击杀认定用 `_killedBy`；弹射击杀用 `_killedByRicochet`
- `/workspace/assets/**/*.meta` 绝不动
