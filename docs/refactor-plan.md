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
| 1 | 从 BattleScene 抽出终焉确认弹窗 + 长按怪物信息 | 低：纯 UI，对外 API 不变 | **本提交完成** |
| 2 | 继续拆 BattleScene：关卡加载 / 倍速 / 寻怪与战败 HUD | 中 | 待做 |
| 3 | 拆 BattleCombat（攻击结算 / 连击 / 飘字） | 中高：战斗手感 | 待做 |
| 4 | 按英雄拆 TalentManager（核心 API 留壳，角色天赋分文件） | 高：战斗正确性 | 待做 |
| 5 | Standalone `_bootWiring` / 横屏输入拆模块 | 中：入口接线 | 待做 |
| 6 | Client/Server 启动与 overlay 拆模块 | 中 | 待做 |
| 7 | 城镇页（铁匠/教堂/酒馆/市场/背包）抽共用页壳 | 中 | 待做 |
| 8 | 删死代码、统一重复九宫格/缓动 | 低 | 待做 |

## 第 1 步改动

- 新增 `scripts/ui/TerminalConfirmDialog.lua`
- 新增 `scripts/ui/MonsterInfoPopup.lua`
- `BattleScene` 只保留委托：`handlePressBegin/End` 签名不变（ClientInput 无需改）
- 行为保持：打开动画未完成不响应按钮、点窗外取消、长按 0.4s、松开关闭

## 验收

- 首通推进到终焉神殿弹出确认，进入/取消/点窗外与原来一致
- 战斗中长按敌方卡弹出属性，松开消失
- 倍速按钮在确认弹窗打开时仍隐藏
