# 终焉之门 · 项目记忆快照

> 本文件由记忆系统维护（会话启动时先读本文件与 docs/memory-index.md）。

## 恢复指令

1. 读 `docs/memory-index.md`（项目详细上下文）
2. 读 `docs/refactor-plan.md` + `docs/refactor-tasks.md`（重构进度）
3. 自测：这是什么项目？上次做了什么？下一步做什么？
4. 告知用户记忆恢复状态，开始工作

## 项目是什么

- **终焉之门·单机版**：UrhoX Lua 卡牌放置 RPG，NanoVG 纯 2D，横屏三栏
- 入口 `scripts/main.lua` → 只加载 `network/Standalone.lua`（已无多人 Client/Server 入口）
- GitHub：`FanZeros/changeForJourney`
- **当前开发分支**：`feat/first-clear-reward-cascade`（只 push 本分支；旧 integrate 分支约定已过期）

## 本次完成（2026-09-24 遗匣地点与溢出保管）

- 首通成功仍进「首通奖励」，失败/离开关卡保留「战斗掉落」，挂机仍进遗匣；奖励页不恢复 6/6。
- 超出背包 200 件的奖励完整存入遗匣 `seeds[].equip`，保留模板/词条/等级，不转回随机种子；旧 9999 件种子截断取消。
- 遗匣是城镇下方中轴的独立地点，管理页在左栏；开闭动画/中缝返回/按栏滚轮/空态与城镇页一致。
- 领取仅消费实际入包项，余下保留；按组及全部分解保留，全部分解须二次确认。
- 修复持续掉落反复重置存档防抖导致不落盘。修复首次恢复遗匣摘要未同步。
- 验证：Lua5.4 12组奖励回归 + 页面交互/存档/横屏路由测试通过；LSP 0 Error；官方 build 成功。
- 实机截图尚未验收：当前 UrhoXRuntime 项目启动停在 engine-startup 资源加载，报告0帧；不能将此报告当成游戏运行通过。隔离验收入口 `scripts/tests/lootbox_preview.lua` 不读写玩家存档。


## 上次做了什么（截至 2026-09-23 今天提交整合）

- 从 `workspace` 新开 `integrate/20260923`，合入今天全部功能提交，未推 `workspace`
- workspace 在 23:44 撤回了左栏 2D 世界地图页（56cee55）。integrate/20260923 已合并该撤回，地图页不再存在
- 仍保留：装备详情小窗、暗黑化天赋底与恭喜获得弹窗；三行行内平涂是否还在以合并后 TownScene/BattleTriPage 为准
- 滚轮/右键装备/顶栏远征等级/运行时五语/Noto Sans CJK KR Bold
- 四名玩梗角色（老六/哈基米/加载中/高ping战士，立绘仍是替代图）+ RPG Maker SE 包 + 音量 5% + 按下即播/远程命中出声
- 未解锁角色职业标 + Maker MCP 一键脚本（含 workspace923 的 Windows/GBK 修复）
- **不要开** `.project/i18n.json enabled=true`

## 更早：截至 2026-09-22 晚 整合

- 已把今天三线合进 `workspace` 并推送：
  1. `docs/equip-set-and-class-migration`（套装 P1 + 六契 + 1.5 竖屏天赋树，此前已在 workspace）
  2. `refactor/extract-battle-overlays` 独有：星图视口剔除 + CharacterPower/Progress 抽取；套装加成补进 CharacterPower
  3. `feat/rename-adventure-to-expedition`：冒险等级→远征等级等玩家可见文案
- 冲突处理原则：保留 workspace 六契/套装玩法，只把「冒险*」改成「远征*」；内部键名不变

## 更早：截至 2026-09-22 古树天赋

- 已合并 `origin/workspace`（`fa7a775`）
- T23–T26 四块抽取（LSP 0 Error / build 过 / validate lua_errors=0）
- T27：Market/Blacksmith `drawPageImpl` → `MarketDraw` / `BlacksmithDraw`
- T28：Market 输入 → `MarketInput`（1402 行）
- T29：单机 `sendAction` 走 `network.GameAction` → LocalActionBridge
- T30：去掉多人入口。已删 Client/Server 联网壳
- T31：删除 GuildPage / CharacterSelect / LoadingScreen；消息处理器与 Debug 解绑
- T32：卸掉 StartScreen 选服并删除 ServerSelectPanel；点击直接进游戏。横屏仍 DarkTitleScreen
- T33：删除 VersionMismatchPopup、GuildHandler/GuildService；城镇卸空公会回调。GuildConfig 排行保留
- T34：ChurchPage `drawPageImpl` → ChurchDraw（bind 具名注入）。ChurchPage 1416
- T35：Church 输入/名单 + Talent 攻前/受伤 + Blacksmith 输入。Church 1060 / Talent 1315 / Blacksmith 1384
- T36：Talent 减伤/复活 + Church 槽位动画 + Blacksmith 结果转发。Talent 1116 / Church 1004 / Blacksmith 1337
- hotfix：敌人死亡误变墓碑。根因 BattleCasualty 写 `stageKillCount_`，BattleScene 注入 `stageKillCount`。`8a41499`
- T37：ChurchPage.init → ChurchInit；Talent onEnemyDeath/checkMarkTarget → TalentEnemyDeath。Church 918 / Talent 1032
- T38：ChurchBadge + TalentComboAttack + BlacksmithEnhanceCache + MarketCollection。Church 893 / Talent 1030 / Blacksmith 1244 / Market 1173
- T39：BattleScene 导航/轮回 → BattleStageNavLogic；setBattleData → BattleDataRestore。BattleScene 1605
- T40：ChurchResults + MarketResults。Church 812 / Market 1045
- T41：ChurchLifecycle + MarketInit。Church 790 / Market 1008
- T42：CharacterDeploy + BackpackDialogs。Character 1733 / Backpack 1737
- 天赋从教堂拆出：城镇中轴新建筑「终焉古树」打开 `TalentPage`；教堂只留转职/神器两 Tab
- 星图视口改为 1:1（1080×1080 居中）；滚轮带鼠标坐标直接缩放

## likely_next_task

- 优先预览遗匣地点、左栏页、满包「已入遗匣」、领取与分解；恢复运行时资源后执行隔离截图入口。

- 预览验收：滚轮、右键装备、顶栏远征等级、五语、四人战斗、新 SE、未解锁职业标、左栏世界地图
- 四人入队/闲聊已接：情景 74–81。首次获得或第一次打开详情播放；闲聊每局每个角色一次
- 四人立绘仍是替代图，正稿未做
- 73 情景长剧情未进五语词表；全量暗黑立绘/卡面裁切/标题视频仍未做
- BattleScene 1605，可再抽 init/draw/handleInput
- ChurchPage 790，主壳已较瘦
- MarketPage 1008，可再抽商店道具网格
- CharacterPanel 1733 / BackpackPanel 1737 仍是最大页，可再抽详情绘制/输入
- BlacksmithPage 1244 上半绘制依赖局部图太多，勿盲目抽 init
- ServerListConfig / GuildConfig 仍被存档与云排行使用，勿当死代码删

## 用户硬性流程（必须遵守）

- **不能自行取消/退出任务**；每次交付后必须调用 AskUserQuestion 给下一步选项，禁止纯文字收尾。遇阻碍如实说明并用选项继续；尊重用户后续停止指令。
- 以当前功能分支继续开发；完成后每次提交并 push **该分支**。当前是 `feat/first-clear-reward-cascade`，不要推 `integrate/20260923`、`workspace` 或其他分支，不强推。
- 按当前用户授权范围改动；重构不夹带无关玩法修改。

## 避雷清单（摘要）

- 抽取模块读 `TAL_BCS` 必须 `getTAL_BCS()`，bind 时快照会在 `TAL.mount` 后过期
- Church/大页 `_ENV = E` 会让 LSP 报满屏 undefined-global Error，挡 build；用 bind(deps) 具名注入
- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- Lua 5.4 字符串里不要写 `\!`
- 脏工作区会让 `git merge` 失败且不建 MERGE_HEAD
- 禁止推其他分支（当前只推 `feat/first-clear-reward-cascade`）
- 遗匣 `seeds[].equip` 是原装备，种子合并和等级兼容绝不能改写或丢弃它。
- 不要开引擎 i18n `enabled=true`，用 `core/I18n.lua`
