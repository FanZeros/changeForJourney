# 重构任务清单（自主执行）

> 分支：`refactor/extract-battle-overlays`（禁止推 `workspace`）
> 用户指示（2026-09-22）：列任务列表并上传；按步骤逐个完成；**全部完成前不得 AskUserQuestion**。
> 原则：只抽模块、不改玩法；每步可运行、可回滚；对外 API 尽量保持。

## 已完成

- [x] T1 抽出终焉确认弹窗 + 长按怪物信息（`TerminalConfirmDialog` / `MonsterInfoPopup`）`ab144f8`
- [x] T2 抽出倍速 / 出怪 / 过渡 HUD（`BattleSpeed` / `BattleEnemySpawn` / `BattleTransitionHud`）`ed50cd7`
- [x] 本文件落地并推送

## 待完成（按顺序）

- [x] **T3** BattleScene：抽出 `refillEnemies` / `startBattleTalents` / `setupBattleCombatContext` / `resetBattle` 到 `BattleStageFlow.lua`。`loadStage` 仍留在 BattleScene 作编排。
- [x] **T4** BattleScene：抽出属性快照与己方重置（`createSnapshot` / `restoreFromSnapshot` / `resetAllyUnit`）到 `BattleAllyReset.lua`。
- [x] **T5** BattleScene：抽出关卡名/前进后退导航绘制到 `BattleStageNav.lua`；清死代码。目标：BattleScene < 2200 行。
- [x] **T6** BattleCombat：抽出飘字 / 受击闪 / 连击队列到 `BattleCombatFx.lua`，BattleCombat 只保留攻击结算。目标：BattleCombat < 1800 行。
- [x] **T7** TalentManager：核心 API 留壳，按英雄把最长的本地函数块拆到 `systems/talents/`（至少拆 Melissa / Luoxing / Ayane 三块）。目标：TalentManager.lua < 3000 行。
- [x] **T8** Standalone：抽出 `_bootWiring` 到 `network/StandaloneBoot.lua`，抽出横屏输入到 `network/StandaloneHorizonInput.lua`。目标：Standalone.lua < 1600 行。
- [x] **T9** 死代码与重复清理：确认弹窗残留、重复九宫格/缓动、无引用 local。更新 `docs/refactor-plan.md` 进度。
- [x] **T10** 汇总：更新本清单全部勾选、最终行数统计、push。完成后才向用户 AskUserQuestion。

## 验收底线

- 不改战斗公式、掉落、关卡生成规则
- `BattleScene.handlePressBegin/End`、倍速 API、`Standalone.Start` 对外签名不变
- 每完成一项立即 commit + push 到 `refactor/extract-battle-overlays`


## 追加：城镇页共用壳（用户 2026-09-22 选项）

- [x] 新增 `scripts/ui/TownPageChrome.lua`：名称牌 / 返回 / 底栏 Tab / 开闭缓动
- [x] 铁匠铺、教堂、酒馆、市场、背包接入共用壳；玩法内容未改
