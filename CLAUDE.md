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
- **开发基线分支**：`workspace925`。每轮按用户当前指令从基线创建新的任务分支；验收通过后推送任务分支，合并回 `workspace925` 并推送。不要推送 `workspace924` 或其他历史分支。

## 已合入备忘

- Electron 离线包在 `electron-shell/main.js` 关闭 `backgroundThrottling`，失焦时保持战斗帧更新。网页隐藏页仍需离线补算。Windows 失焦/最小化尚未实机验证。
- PC 包 Lua 仍是明文；`electron-shell/obfuscation_trial.py` 只是外部试点，未接入正式发布。
- 配装布局：属性页不显示装备槽和一键按钮，保留切角；配装页批量按钮置顶，内容下移约 160px 给词条留空。拖拽穿戴仍以 925 为准。

## 上次做了什么（2026-09-26）

- `workspace925`：装备详情按来源栏固定展开方向——右栏从鼠标左侧出现，已装备对比再向左；左栏从鼠标右侧出现，对比再向右。点击使用实际鼠标位置，悬停详情跟随鼠标，钉住后不再漂移。
- 套装效果改为独立描边区域，排在基础属性/词条下方，说明换行并放大文字；交互热区与增长后的卡片尺寸同步。
- Lua LSP 0 Error，官方 Build 成功；本地离屏 Runtime 安装超时，尚未拿到实际装备页截图，需要后续用户预览验收。

## 上次做了什么（2026-09-24）

- 遗匣打开即显示确定装备，支持全部和六档稀有度筛选；一键领取/回收只处理当前筛选。
- 遗匣改为城镇左栏地点。超出背包的奖励完整存入遗匣，领取只消费实际入包项。
- 滚轮按鼠标所在区域滚动，详情不再吃掉后面的列表。
- Windows `--start` 不再调用官方隐藏 PowerShell supervisor。`supervisor.log` 为 0 字节、`supervisor_pid` 为 0 时，改为项目目录前台启动已安装的 `UrhoXRuntime.exe`。不要重装 Node。

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

- 当前分支是 `workspace925`。做完必须以 AskUserQuestion 选项提问下一步，只 push 该分支。
- `workspace925` 装备详情定位及套装效果区已调整；需要在实际游戏预览中确认左/右栏比较卡与最长套装说明的视觉效果。
- Electron 已关后台节流，但未实机验证失焦/最小化。系统休眠仍需离线补算。
- 配装页已下移留出词条空位，词条内容本身还没画。

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

- **不能取消/退出任务**；无论任务完成或遇到阻碍，先汇报结果，再用 AskUserQuestion 提供下一步选项，禁止纯文字中断；用户选择后继续。不得据此擅自执行未授权操作，也不得在仓库或记忆中保存访问令牌。
- 分支操作以用户**当前轮次**授权为准：以 `workspace925` 为基线，在新任务分支开发，验证后推送该分支并合入、推送 `workspace925`；若远端发生并发更新或冲突，不覆盖他人工作，先确认。
- 只抽模块、不改玩法；对外 API 尽量保持

## 避雷清单（摘要）

- 抽取模块读 `TAL_BCS` 必须 `getTAL_BCS()`，bind 时快照会在 `TAL.mount` 后过期
- Church/大页 `_ENV = E` 会让 LSP 报满屏 undefined-global Error，挡 build；用 bind(deps) 具名注入
- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- Lua 5.4 字符串里不要写 `\!`
- 脏工作区会让 `git merge` 失败且不建 MERGE_HEAD
- 分支禁令以用户当前轮次授权为准；本轮只推任务分支和 `workspace925`，不碰其他分支。
- 遗匣 `seeds[].equip` 是原装备，种子合并和等级兼容绝不能改写或丢弃它。
- 不要开引擎 i18n `enabled=true`，用 `core/I18n.lua`
