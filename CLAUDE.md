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

## 上次做了什么（截至 2026-09-17）

1. 新工作区从 origin/workspace 落地
2. 修右侧栏重复返回按钮（H_SEAM_BACK）
3. **落地 4 个混合追加技试点**（粗暴永久层 + 机制进化）
   - #1 大狗嚼 衔骨图鉴：击杀 +1 生命上限，咬攻击类型，8 系齐全系撕咬
   - #12 雪皇 冰雕收藏：击杀 +0.2 魔攻/+0.05% 冰冻率，冰冻结杀留冰雕挡伤
   - #13 弹弹弹 分裂弹：击杀 +0.25 物攻，弹射击杀加弹射次数，40 次进化环绕
   - #15 复活吧爱人 预存复活：复活 +2 生命/+0.5% 率，发卡下场必死也活，自己死核爆
   - 核心：`scripts/systems/ExtraTalentSystem.lua`

## likely_next_task

验收 4 个试点手感；通过后再铺其余 16 人。

## 避雷清单（摘要）

- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- 追加技层数跟角色走（roster.extraTalent），竞技场对手 createHero(..., false) 不要套本地层
- 击杀认定用 `_killedBy`；弹射击杀用 `_killedByRicochet`
- `/workspace/assets/**/*.meta` 绝不动
