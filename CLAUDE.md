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
- **当前基线**：`workspace926`。2026-09-27 用户要求新建此分支，合入 `workspace925` 与全部 `feat926/`（`character-drag-save`、`cleanup-unused-panels`、`remove-unused-diary`、`artifact-audit`、`battle-lab`），并只推 `workspace926`。不推 `workspace` / `workspace925`。

## 已合入备忘（feat926，2026-09-27）

- `character-drag-save`：右栏拖拽跨栏取消、英雄名册数字键保留、跨队一次提交、离线经验不算空槽、存档写入失败重试。
- `cleanup-unused-panels` / `remove-unused-diary`：删除无入口的旧日志、遗物洗练、签到、旧任务、公告面板及专属图。保留城镇 `TaskPage`、签到/任务服务与存档、GM `AnnouncementConfig`、遗物奖励图标。
- 神器审查来自 `feat926/artifact-audit`，已合入 `workspace926`。
- 战斗实验室来自 `feat926/battle-lab`，已合入 `workspace926`。

## 已合入备忘

- Electron 离线包在 `electron-shell/main.js` 关闭 `backgroundThrottling`，失焦时保持战斗帧更新。网页隐藏页仍需离线补算。Windows 失焦/最小化尚未实机验证。
- PC 包 Lua 仍是明文；`electron-shell/obfuscation_trial.py` 只是外部试点，未接入正式发布。
- 配装布局：属性页不显示装备槽和一键按钮，保留切角；配装页批量按钮置顶，内容下移约 160px 给词条留空。拖拽穿戴仍以 925 为准。

## 上次做了什么（2026-09-27，925 同步与存档再排查）

- 开始核对时 `workspace925@aaa53e7` 已是当前分支祖先，合并返回 `Already up to date`；提交前远端继续推进到 `c614ec0`，已在任务分支合并（含战斗通关、招募及右栏宽度改动），没有推送基线。合并后 LSP 0 Error、Build 成功，三项针对性引擎回归 PASS。
- 修复读档后队伍空槽 `0` 参与离线经验预览分母的问题：只计真实、已拥有且不重复的队员；领取回退名单也排除空槽。测试对 `{1,0,2,0}` 验证两名队员分别预览并实际领取 50 经验，未上阵队员不变。
- `StandaloneSave` 检查 `File:WriteString` 的布尔返回；写入失败或文件无法打开时不记成功快照，并安排防抖重试。内存文件替身先复现失败，再验证成功。三项引擎回归 PASS、LSP 0 Error、官方 Build 成功。
- 未改变直接覆盖主存档或损坏 JSON 按新档处理的旧行为；这两项仍有丢档风险，原子替换与备份恢复需先核实引擎存储语义和平台验证，不能宣称已修复。Web/WASM 本地存档刷新持久性也受引擎文档限制。
- 本轮仍只允许提交/推送 `feat926/character-drag-save`，绝不自动推送 `workspace925` 或 `workspace`。

## 上次做了什么（2026-09-27，`feat926/character-drag-save`）

- 修复角色存档恢复时两层 `onLoad` 连续规范化丢弃数字名册键：未编队英雄及等级、经验往返保留。
- 右栏拖拽跨栏/窗外松手立即取消，不再悬挂拖拽态导致头像视觉消失；未达阈值的按压也释放。
- 跨队交换与名册拖放改为一次提交双方编队；保留非连续英雄 ID、空槽位置及未上阵角色，失败时恢复面板状态。
- 存档、拖拽路由、编队事务三条引擎回归 PASS，LSP 0 Error，官方 Build 成功。主入口 60 帧无 Lua 错误，但已有 5 张剧情日记贴图缺失造成运行报告 FAIL，尚需资源修复及实际 UI 预览。
- 本轮只允许 push `feat926/character-drag-save`；不要推送基线或历史分支。
## 本轮进展（2026-09-27，`feat926/artifact-audit`）

- 规范化 `docs/changeForJourney-gameplay.md` §8：实际为 4 个出战位×每位 3 个神器子格，40/80 级解锁、抽取保底、置换/洗练及战斗桥接均按代码记录；部分旧文档其他章节仍待核对。
- 修复 `ArtifactRuntime` 独立战线状态互相清空、战斗重复初始化副作用、审判锤旧目标叠层和影羽斗篷衰减；三行战斗接入首次死亡拦截及亡魂计时；通天塔改为逐名阵亡时拦截。所有宿主均传本战线单位列表到 reset/update。
- `scripts/tests/battle_stage_switch_test.lua` 增加神器回归，离屏运行 24 PASS、0 FAIL；Lua LSP 0 Error，官方 Build 成功。整游戏启动 60 帧 Lua 错误 0，但报告有 5 张仓库本来缺失的剧情日记图片，不能宣称整游戏零资源错误；通天塔死亡路径还需实战验收。构建可能更新 `.project` 的本地生成配置，提交前应排除。
## 本轮进展（2026-09-27）

- `feat926/battle-lab`：新增独立进程战斗平衡工作台（`scripts/tests/battle_lab_ui.lua`）与无界面批量入口（`scripts/tests/battle_lab.lua`），`BattleLab.lua` 复用三行战斗驱动、技能与战斗统计。可配置关卡、首通/挂机、1–4 位模板英雄与等级、固定种子、局数和限时；输出胜负、平均时长/伤害/治疗、逐英雄数据和逐局 JSON。
- 测试入口不加载游戏主入口，不读玩家编队/存档，不发奖、不推进关卡；游戏内并行执行会污染共享战斗状态，必须以独立 Runtime 进程运行。默认无装备/遗物/神器；可选纯配置普通装备 A/B 校准；首通流程与完整 BattleScene 结算不同，挂机不包含前五关混合出怪。
- LSP 0 Error，官方构建成功；Runtime 验证首通胜利、单英雄挂机战败、1 秒超时、固定种子逐局复现，原切关/全灭回归通过。工作台离屏截图已检查；尚未通过真人鼠标交互验收。

## 最新：战力实测校准（2026-09-27）

- 在 `feat926/battle-lab` 扩展独立入口：单行 `battle_lab_config.json` 可填 `loadouts.A/B`（英雄 ID → 装备槽 → `{templateId,level,ascendLevel?}`），仅支持确定性普通无词缀装备；报告按角色页同一属性权重输出双方案战力、逐局同种子配对、胜率、耗时、输出、治疗、承伤及 B-A。仍无玩家存档/觉醒/神器/遗物/星图；不能在主游戏进程并行运行。
- 历史公式演示（不合规掉落样本，见下方更正）：第 101 关首通、大狗嚼 Lv.1、20 种子、80 秒上限，魔攻戒 `C10` 与物攻戒 `C4` 战力同为 116，胜率分别 0/20 与 20/20；后者场均输出 +89.55、承伤 -105.55、用时 -6.07 秒。重复运行相同；同配装 A/B 逐局完全相同。该例不得用于正常掉落平衡结论。
- LSP 0 Error、官方 Build 成功；无配装旧入口 3/3 胜且报告兼容，切关回归断言 ALL PASS（测试自身未退出进程导致外层 timeout 124，日志无 FAIL/Lua 错误）。图形工作台仍只支持原始无配装选项，配装对照通过 CLI JSON 入口。

## 扩样校准与更正（2026-09-27）

- 更正：上一轮 `C10`/`C4` 用在 Lv.1 的 20 局对照超出两件装备模板的掉落等级下限 28；只作为公式演示，不作为正常掉落平衡证据。`BattleLab.prepare` 现在拒绝装备等级不在模板 `levelRange` 内的样本。
- 合法样本：第 101 关首通，大狗嚼 Lv.1，均为普通 Lv.1 `C13`（秘识戒）A 与 `C1`（力量戒）B；显示战力同为 112。种子 926–965：A 14/40 胜、B 40/40；种子 3926–3965：A 10/40、B 40/40；第 103 关：A 22/40、B 40/40。第 102 关两者均 40/40，但平均耗时 A 34.82s、B 28.02s；队伍加黄桃龙后第 101 关均 40/40，A 22.04s、B 21.30s。不同职业的单人法师/游侠样本均 0/40，不可据它们的胜率比较适配，需看输出与生存；全量实测汇总在 `docs/memory-index.md` 顶部。
- 建议：不要全局削减魔攻权重（会误伤魔法职业）；显示战力如要反映角色适配，应以角色攻击类别区别计价物攻/魔攻及专属伤害、暴击、穿透，治疗者独立考虑治疗量。先保留原始属性战力供详情/队伍展示，对“实战预估”新口径跨阵容、关卡、层级验证，避免仅由胜率饱和场景定权重。正式战力公式和战斗结算尚未改。

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

- 当前基线 `workspace926`：已合入 925 与全部 feat926。需要在游戏里验收拖拽编队、存档读回、旧面板已消失。
- 神器审查已在 `workspace926`。每次交付前汇报结果，最后必须调用 AskUserQuestion 以选项提问下一步。
- 战斗实验室已在 `workspace926`。交付后必须以 AskUserQuestion 选项提问下一步。
- 战斗工作台需独立运行（`tests/battle_lab_ui.lua`），批量入口 `tests/battle_lab.lua`；在游戏主进程并行测试会污染共享战斗状态。下一步可验收鼠标操作与不同分辨率 UI，并按需增加玩家配装的隔离配置支持。
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

- **不能擅自取消/退出任务，也不能以纯文字结束交付**；每次完成或遇到阻碍，先汇报结果，再真正调用 `AskUserQuestion` 工具，以选项询问下一步并等待选择。记忆用于提醒，不等同于自动 hook；不得据此擅自执行未授权操作，也不得在仓库或记忆中保存访问令牌。
- 分支操作以用户**当前轮次**授权为准：本轮只推 `workspace926`。不推 `workspace`、`workspace925`。远端并发更新先核对，不覆盖他人工作、不强推。
- **不能取消/退出任务**；无论任务完成或遇到阻碍，先汇报结果，再用 AskUserQuestion 提供下一步选项，禁止纯文字中断；用户选择后继续。不得据此擅自执行未授权操作，也不得在仓库或记忆中保存访问令牌。


- 只抽模块、不改玩法；对外 API 尽量保持

## 避雷清单（摘要）

- 抽取模块读 `TAL_BCS` 必须 `getTAL_BCS()`，bind 时快照会在 `TAL.mount` 后过期
- Church/大页 `_ENV = E` 会让 LSP 报满屏 undefined-global Error，挡 build；用 bind(deps) 具名注入
- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- Lua 5.4 字符串里不要写 `\!`
- 脏工作区会让 `git merge` 失败且不建 MERGE_HEAD
- 分支禁令以用户当前轮次授权为准；本轮只推 `workspace926`，不推 `workspace` / `workspace925`。

- 遗匣 `seeds[].equip` 是原装备，种子合并和等级兼容绝不能改写或丢弃它。
- 神器独立战线的 `ART.reset`/`ART.update` 必须传本战线 allies；`initBattle` 不能清除其他战线；主线 60 帧验证有 5 张既有剧情日记图片缺失，不归咎于神器逻辑。
- 不要开引擎 i18n `enabled=true`，用 `core/I18n.lua`
