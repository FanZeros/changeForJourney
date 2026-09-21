# 终焉之门 · 代码重构规划

> 分支：`refactor/slim-modules`（禁止推 `workspace`）
> 原则：**行为不变**、**小步拆分**、**每步可运行可回滚**、**先抽入口/UI 壳，后动战斗公式**

## 现状（截至 workspace@78e24ef）

- Lua 约 **307 文件 / 14 万行**
- 单文件超 1500 行（必须拆）的热点：

| 文件 | 行数 | 问题 |
|------|------|------|
| `systems/TalentManager.lua` | 4197 | 20+ 角色天赋全堆一个文件 |
| `ui/BattleScene.lua` | 3435 | 关卡/绘制/更新/快照/外部 API 混杂 |
| `network/Client.lua` | 2478 | 联网入口 + 横屏绘制 |
| `ui/BattleCombat.lua` | 2203 | 战斗结算 |
| `network/Standalone.lua` | 原 2130 | 启动 + 横屏循环 + 输入 |
| `network/Server.lua` | 2068 | 会话/选服/推状态 |
| `ui/MarketPage.lua` 等建筑页 | ~1900 | 页模板重复 |
| `config/IdleIncomeConfig.lua` | 1782 | 纯数据可拆表 |
| `server/character/PlayerDataManager.lua` | 1633 | 玩家数据聚合过重 |

## 阶段划分

### P0 入口瘦身（本步已开始）

1. **Standalone 横屏循环拆出** → `network/StandaloneHorizon.lua`
   - 绘制 / 命中 / 中缝返回 / 滚轮路由
   - Standalone 只保留 Start/Stop/boot/Update
2. 下一步候选：`Standalone._bootWiring` 接线表化；`HandleUpdate` 场景状态机化

### P1 战斗场景分层

- `BattleScene` 拆：`BattleStage`（关卡队列）/ `BattleLoop`（update）/ 保留 Scene 外壳
- **不改** `TalentManager` 公式，直到 P2

### P2 天赋按角色拆

- `TalentManager` 保留钩子（onBeforeAttack 等）
- `systems/talents/<hero>.lua` 注册表
- 每个角色一次搬迁，配回归清单

### P3 UI 页模板

- 教堂/铁匠/酒馆/市场/背包 左栏页已有共同模式（Viewport left + 中缝返回）
- 抽 `ui/layout/LeftPage.lua` 去重复绘制/输入链

### P4 数据与配置

- 关卡/挂机表保持独立文件，不进逻辑
- 超大 Challenger 配置维持现状（数据不是冗杂逻辑）

## 禁止事项

- 不改玩法数值、掉落、保底
- 不推 `workspace`
- 不碰 `/workspace/assets/**/*.meta`
- 不把 GitHub PAT 写入文件/提交
