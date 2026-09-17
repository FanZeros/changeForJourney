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

1. 落地 4 个混合追加技试点（衔骨/冰雕/分裂弹/预存复活）
2. **构筑 Electron Windows 离线包**（h5-pages-deploy §8）
   - 壳：`electron-shell/`（main.js 内置 http 发 COOP/COEP）
   - 产物：`electron-shell/release/ZhongYanZhiMen-win64-unpacked.zip`（461MB，不解压不入库）
   - 解压后运行 `win-unpacked/ZhongYanZhiMen.exe`；首次需联网拉引擎 WASM

## likely_next_task

验收 4 个试点手感；或把 zip 发给用户测 Windows 双击即玩。

## 避雷清单（摘要）

- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- 追加技层数跟角色走（roster.extraTalent），竞技场对手 createHero(..., false) 不要套本地层
- 击杀认定用 `_killedBy`；弹射击杀用 `_killedByRicochet`
- `/workspace/assets/**/*.meta` 绝不动
