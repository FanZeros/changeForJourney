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

## 追加：继续拆 BattleCombat（用户 2026-09-22）

- [x] **T11** 抽出卡牌动画状态机到 `BattleCombatAnim.lua`（攻击前摇/受击/入场/死亡/补位）。`BattleCombat` 对外 API 不变。目标：BattleCombat < 1850 行。
- [x] **T12** TalentManager 再拆英雄：Alex / Elwyn / Sera / Suhua 到 `systems/talents/`。目标：TalentManager < 3300 行。
- [x] **T13** Client：抽出启动接线到 `network/ClientBoot.lua`（击杀缓冲/城镇情景/轮回关卡/阵亡/阵容）。对外 `Client.Start` 签名不变。
- [x] **T14** BattleScene：抽出死亡补位/阵亡紧凑/胜负判定到 `BattleCasualty.lua`。目标：BattleScene < 2200 行。
- [x] **T15** BattleCombat：抽出连击结算到 `BattleCombatCombo.lua`。
- [x] **T16** BattleScene：抽出 `loadStage` 到 `BattleStageLoad.lua`。
- [x] **T17** TalentManager：抽出 `TAL.update` 到 `systems/talents/TalentUpdate.lua`。目标：TalentManager < 3000。
- [x] **T18** Client：抽出主渲染到 `network/ClientRender.lua`。
- [x] **T19** Server：抽出进服全量推送到 `network/ServerEnterGame.lua`。
- [x] **T20** BattleScene：抽出攻击进度/tick 到 `BattleSceneTick.lua`。
- [x] **T21** 城镇页：Blacksmith/Market/TavernShop 九宫格绘制委托 `DrawUtil`。
- [x] **T22** TalentManager：抽出弹射(#13 Rosa)与信光机兵(#7 Xin) after-attack。2691 行。
- [x] **T23** TalentManager：抽出 `TAL.onAfterAttack` 到 `systems/talents/TalentAfterAttack.lua`（`getTAL_BCS()` 避免 mount 过期）。1728 行。
- [x] **T24** Client：抽出 `HandleUpdate_Client` 到 `network/ClientUpdate.lua`。1348 行。
- [x] **T25** BattleScene：抽出暂停/失败延迟/轮回/寻怪到 `BattleScenePhases.lua`。1765 行。
- [x] **T26** 城镇页：Market 商品卡 → `MarketShopCard.lua`；Blacksmith 装备槽 → `BlacksmithEquipSlots.lua`。Church `drawPageImpl` 因 LSP `_ENV` undefined-global 回退。
- [x] **T27** Market/Blacksmith `drawPageImpl` → `MarketDraw.lua` / `BlacksmithDraw.lua`（bind 具名注入；铁匠开关回调用 getter/setter 写回）。Market 1589 / Blacksmith 1533。
- [x] **T28** Market 点击/拖拽/滚轮 → `MarketInput.lua`。Market 1402。
- [x] **T29** 单机 `sendAction` 改走 `network.GameAction` 门面（本地 LocalActionBridge）；UI 不再 `require("network.Client")`。联网仍转发 Client。validate 确认未加载 Client 模块。
- [x] **T30** 去掉多人入口：`main.lua` 只加载 Standalone；删除 Client/ClientBoot/ClientRender/ClientUpdate/ClientInput/ClientScenarioHelper/Server/ServerEnterGame。`server/` Handler 与 ClientDispatcher 保留（单机本地桥仍用）。
- [x] **T31** 清仅多人 UI 残留：删除 GuildPage / CharacterSelect / LoadingScreen；ClientMessageHandler 与 Debug 面板解绑。选服面板仍挂在 StartScreen，本轮未动标题流程。
