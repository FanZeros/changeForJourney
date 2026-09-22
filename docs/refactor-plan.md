# 代码重构规划（终焉之门）

> 分支策略：所有重构在 `refactor/*` 新分支进行，禁止推送到 `workspace`。
> 原则：先抽独立 UI/弹窗，再拆巨型战斗/天赋文件，最后压缩网络入口。每步可运行、可回滚。

## 现状（workspace @ 973f0ed）

- 约 14 万行 Lua，`scripts/ui` 87 个文件。
- 超 1500 行文件（引擎规则必须拆）：
  - `systems/TalentManager.lua` 4197
  - `ui/BattleScene.lua` 原 3435（本步后约 3008）
  - `network/Client.lua` 2487
  - `ui/BattleCombat.lua` 2203
  - `network/Standalone.lua` 2168
  - `network/Server.lua` 2068
  - 多个城镇页（Market/Church/Blacksmith/Backpack/Character）1900 上下

## 分步计划

| 步 | 目标 | 风险 | 状态 |
|----|------|------|------|
| 1 | 从 BattleScene 抽出终焉确认弹窗 + 长按怪物信息 | 低：纯 UI，对外 API 不变 | **已完成** |
| 2 | 继续拆 BattleScene：关卡加载 / 倍速 / 寻怪与战败 HUD | 中 | **已完成** |
| 3 | 拆 BattleCombat（攻击结算 / 连击 / 飘字） | 中高：战斗手感 | **飘字/闪烁/卡牌动画已完成；连击结算仍在 BattleCombat** |
| 4 | 按英雄拆 TalentManager（核心 API 留壳，角色天赋分文件） | 高：战斗正确性 | **Ayane/Luoxing/Melissa/Alex/Elwyn/Sera/Suhua 已完成** |
| 5 | Standalone `_bootWiring` / 横屏输入拆模块 | 中：入口接线 | **已完成** |
| 6 | Client/Server 启动与 overlay 拆模块 | 中 | **ClientBoot 已完成；Server/overlay 未拆** |
| 7 | 城镇页（铁匠/教堂/酒馆/市场/背包）抽共用页壳 | 中 | **本提交完成 TownPageChrome** |
| 8 | 删死代码、统一重复九宫格/缓动 | 低 | **部分完成（确认弹窗贴图/墓碑常量/重复 boot 回调）** |

## 第 1 步改动

- 新增 `scripts/ui/TerminalConfirmDialog.lua`
- 新增 `scripts/ui/MonsterInfoPopup.lua`
- `BattleScene` 只保留委托：`handlePressBegin/End` 签名不变（ClientInput 无需改）
- 行为保持：打开动画未完成不响应按钮、点窗外取消、长按 0.4s、松开关闭

## 验收

- 首通推进到终焉神殿弹出确认，进入/取消/点窗外与原来一致
- 战斗中长按敌方卡弹出属性，松开消失
- 倍速按钮在确认弹窗打开时仍隐藏


## 第 2 步改动

- 新增 `scripts/ui/BattleSpeed.lua`：倍速解锁 / 循环 / 绘制 / 点击判定
- 新增 `scripts/ui/BattleEnemySpawn.lua`：首通出怪、挂机混合出怪、上场分配
- 新增 `scripts/ui/BattleTransitionHud.lua`：寻怪 / 战败 / 轮回 / 胜利 HUD
- `BattleScene` 对外倍速 API 签名不变（`BattleTriPage` 仍走 BattleScene）
- 删除已无引用的终焉确认弹窗贴图加载（`imgConfirmBg` / `imgBtnGreen` / `imgBtnGray`）
- `BattleScene` 约 3435 → 3008 → 2722 行


## 本轮最终行数（相对 workspace @ 973f0ed）

| 文件 | 重构前 | 重构后 |
|------|--------|--------|
| ui/BattleScene.lua | 3435 | 2384 |
| ui/BattleCombat.lua | 2203 | 1821（卡牌动画抽出 BattleCombatAnim） |
| systems/TalentManager.lua | 4197 | 3276（再抽 Alex/Elwyn/Sera/Suhua） |
| network/Standalone.lua | 2168 | 841 |
| network/Client.lua | 2487 | ~2141（抽出 ClientBoot） |
| network/Server.lua | 2068 | 2068（未拆） |

分支：`refactor/extract-battle-overlays`。禁止推 `workspace`。
