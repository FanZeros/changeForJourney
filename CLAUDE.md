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
- **开发基线分支**：`workspace925`。当前轮次从 `origin/workspace925@aaa53e7` 建立 `feat926/battle-lab`；仅提交并推送该功能分支，**不合并、不推送任何 workspace 分支**。后续轮次按用户当轮指令判断。

## 已合入备忘

- Electron 离线包在 `electron-shell/main.js` 关闭 `backgroundThrottling`，失焦时保持战斗帧更新。网页隐藏页仍需离线补算。Windows 失焦/最小化尚未实机验证。
- PC 包 Lua 仍是明文；`electron-shell/obfuscation_trial.py` 只是外部试点，未接入正式发布。
- 配装布局：属性页不显示装备槽和一键按钮，保留切角；配装页批量按钮置顶，内容下移约 160px 给词条留空。拖拽穿戴仍以 925 为准。

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

## 最新：OFF_FACTOR 跨难度带验证（2026-09-28，v2.60）

- 采样：`tests/battle_lab_fit_expand.lua`（63 组：战士/法师/游侠 × L8@303、L16@1501、L24@2301 三带 × 武器等级扫描/本异系饰品/裸装，runs=8）→ `battle_lab_fit_expand_samples.json`（gitignore）。
- 回归：`fit_power_estimate.py --mode expand`（全量 + 按 band 分桶岭回归，汇总 R²≥0.3 可信桶的 off 系数波动）。
- 结论：①跨带混池回归不成立（ALL 桶 R²=-5.5，三带 DPS 量级差数倍互相吞系数）——**系数标定必须分带**；②magical 类三带全可信（R²=0.63/0.68/0.96），off[phys]=0.330/0.000/0.028、均值 0.119≈0.10 → **OFF_FACTOR=0.10 跨带稳定，维持不变**（L8 的 0.33 为 n=6 小样本波动）；③physical 类三带 R² 均低（0.18/0.20/0.32、攻击组负截断，战士 DPS 被衔骨狂天赋触发主导）——无法回归标定，职业适配方向性由同种子 A/B 实测对照保证；④L24 带 21 组 <5s 速死为弱样本仅作对照。
- 系数值零改动，仅补充验证依据（模块注释/antibodies/文档）。回归全绿（边界/切关/生产接线 9 断言/默认 lab 20/20 v1）。

## 最新：战力预估生产接线（2026-09-28，v2.59，玩家可见但默认关闭）

- **非破坏性接入**：官方 `calcHeroPower` 公式与数字完全不变；`ui/character/panel/CharacterPower.lua` 抽出共享 `buildHeroAttrs(heroId, partySlot)`（装备/遗物/神器/觉醒管线），战力与新增 `calcHeroEstimate` 共用，避免两条管线漂移。预估 = `CPE.estimate(attrs, attrs.atkType)` + 觉醒战力 + 神器加成（后两项沿用官方口径并入）。
- 接线链：`CharacterPanel.calcHeroEstimate` → `CharacterDetail.setContext` → `Draw.setContext`（存 `calcHeroEstimateFn`）。展示：`CharacterDetailDraw` 卡面战力下「预估 N」副行（y=powerY+26），`SHOW_ESTIMATE` 模块开关**默认 false**——系数未跨全阵容标定、本环境无法截图验收玩家 UI，真人验收后 `Draw.setEstimateVisible(true)` 开启。`_estimateCache` 与战力共用 `markPowerDirty` 脏标记，关闭时不计算。
- 验证：新增 `tests/character_power_estimate_test.lua`（真实模块+mock 存档）9 断言 ALL PASS：官方战力不回归（战士 Lv1=106、Lv50=479）、预估>0（战士75/法师74）、预估≤官方×1.5、未知英雄返回0不崩、重构后可重复；主入口 validate 30 帧 lua_errors=0；边界/切关/默认 lab 20/20 v1 全 ALL PASS。**当前玩家数值零变化**。
- ⚠️ 开启副行前必须真人预览验收：卡面副行与等级徽章/职业标是否重叠、字色是否可读；开启后预估数值口径（不含觉醒分项拆分）需在 UI 说明或气泡中注明，避免玩家误解为官方战力。

## 最新：治疗系数拟合（2026-09-27，v2.58）

- 采样：`tests/battle_lab_fit_healer.lua`（22 组牧师：303 超时稳定带 + 304/305 阵亡带 × W67/W68 权杖等级 × C2/C8/C14/C20/C27 饰品）→ `battle_lab_fit_healer_samples.json`（gitignore）。
- 回归：`fit_power_estimate.py --mode healing`（因变量 HPS，按 `healTakenRatio≥0.65` 剔除需求截断饱和样本）。关键发现：**治疗量=min(供给,需求)**——304/305 阵亡带 14 组全饱和（W68@17→32 HPS 仅 24.0→23.6），仅 303 关超时带 8 组非饱和可拟合。
- 结果：HPS 岭回归 R²=0.32，phys/mag 输出组归一化系数 ≈0.48 → **确认初值 `HEALER_ATK_FACTOR=0.5` 与数据一致，保留 0.5**（方向性验证非精确标定，n=8 单关带）。至此 OFF_FACTOR(0.10)/HEALER_ATK_FACTOR(0.5) 两系数均有数据依据。
- 样本局限：单人牧师无输出无法击杀，303 关全超时、304/305 全阵亡，不存在「阵亡且非饱和」带。回归全绿（边界/fit 采样复现/默认入口 20/20），正式公式未改。

## 最新：分项计价系数拟合（2026-09-27，v2.57）

- 采样：`tests/battle_lab_fit.lua`（31 组，四职业 × 武器等级 × 饰品，全取 303 关败局带，runs=10，走新 API `Lab.runSingle`）→ `battle_lab_fit_samples.json`（gitignore）。
- 回归：`scripts/_proc/fit_power_estimate.py`（岭回归 λ=1、非负截断、剔除 winRate=100 饱和样本、DPS 与总输出双口径对照）。方法论要点：**败局总输出=存活时间×DPS，直接回归总输出会被 generic 生存组吞掉攻击信号**（physical 总输出 R²≈0.03、攻击组负系数）；DPS 口径 physical R²=0.43、magical R²=0.52。
- 结论：可信拟合的异系攻击组系数均=0（异系攻击属性对 DPS 无可测贡献，其派生生存价值由 generic 组承载）→ `OFF_FACTOR` 0.25→**0.10**（保留小正值防止显示战力对异系装备归零）；方向断言复验更清晰（战士力量 128>智力 122、法师智力 126>力量 119）。healing 类 R² 为负（healer 局全超时）模型不成立，`HEALER_ATK_FACTOR=0.5` 保留初值，待牧师专属采样（短 timeLimit 制造非超时败局）再拟合。physical off[heal]=0.87 判为 C20(vit+spi) 单点共线噪声，已排除。
- 报告新增 `heroPowers[].groups`（phys/mag/heal/generic 四组分解）；`CombatPowerEstimate.breakdown()` 为公开 API。回归全绿（边界/默认入口/切关），正式战力公式未改。

## 最新：分项计价战力原型（2026-09-27，v2.56）

- 新增 `scripts/systems/CombatPowerEstimate.lua`（原型，**仅 battle-lab 报告使用**，不接线角色页/队伍展示，正式战力公式未改）：与官方同一价值底座（AD.META.valueModel + pct/100），把属性分为 phys/mag/heal/generic 四组，按英雄伤害大类（`AD.getAtkCategory(attrs.atkType)`）给本系 1.0、异系输出 0.25（治疗系英雄对输出系 0.5）。
- `tests/BattleLab.lua` 报告新增 `teamEstimate`、`heroPowers[].estimate/category`、`delta.teamEstimate`；CLI 摘要同步输出「预估」。schemaVersion 1/2 兼容，旧默认入口 20/20 胜回归通过。
- 方向验证（与既有实测样本一致）：战士 Lv8/303 同官方战力 160，预估力量戒 133 > 智力戒 128（实测 3/40 vs 0/40、输出 2112 vs 1780）；法师 Lv1/101 同官方战力 112，预估智力戒 85 > 力量戒 83（实测输出 287 vs 193）。**原型能区分官方战力无法区分的职业适配方向。**
- `tests/battle_lab_boundary_test.lua` 增加第 9 节：战士/法师/牧师类别、同战力区分、方向反转、atkType=nil 回落、estimateUnit 一致性，ALL PASS（自带退出 exit 0）。
- ⚠️ 系数（0.25/0.5）未做跨阵容/关卡/层级回归拟合，只作方向性判断；后续如需精确「实战预估」口径，应按 v2.54 建议做分项计价拟合并验证治疗者独立口径。

## 边界样本补齐（2026-09-27，v2.55）

- 新增 `scripts/tests/battle_lab_boundary_test.lua`：只测 `Lab.prepare` 校验层（不跑战斗），覆盖 stageId/英雄列表/runs/seed/timeLimit 钳制、loadouts 结构、模板槽位与职业穿戴、双手+副手互斥、levelRange 边界（C1{1,7} Lv1/Lv7 合法、Lv0/Lv8/非整数/10000 拒绝；C2{8,9999} Lv7 拒绝、Lv8/Lv9999 合法）、ascendLevel 0/100 边界、quality/affixes 拒绝、历史反例 C10/C4 Lv1 必须被拒。headless 运行 ALL PASS（自带 `engine:Exit()`，exit 0，与旧测试的外层 timeout 124 不同）。
- 真实边界校准（40 局/组，timeLimit=120，errors=0，复跑一致）：Lv7 大狗嚼 + C1/C13（tier1 上边界 Lv7）在 302 双侧全胜、303 双侧全败——单英雄难度悬崖在 302↔303 之间，饱和区胜率不可作判据；Lv8 + C2/C8（tier2 下边界 Lv8）在 303 得到唯一非饱和样本：同战力 160，力量戒 A 3/40 胜 vs 智力戒 B 0/40（种子 3926 复验 1/40 vs 0/40），A 场均输出 +333、承伤 -55，与 v2.54 Lv1 样本方向一致。探测：101/301/302/双人303 全胜，304/305/401/701 全败。
- 正式战力公式、战斗结算未改；仅推 `feat926/battle-lab`。

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

- 当前任务分支 `feat926/battle-lab`：仅 push 此分支，不合并、不推送 `workspace925` 或其他 workspace 分支。交付后必须以 AskUserQuestion 选项提问下一步。
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

- **不能取消/退出任务**；无论任务完成或遇到阻碍，先汇报结果，再用 AskUserQuestion 提供下一步选项，禁止纯文字中断；用户选择后继续。不得据此擅自执行未授权操作，也不得在仓库或记忆中保存访问令牌。
- 分支操作以用户**当前轮次**授权为准：本轮从最新 `origin/workspace925` 建 `feat926/battle-lab`，仅提交并推送该任务分支，禁止合并或推送 workspace；远端并发更新/冲突时不得覆盖他人工作。
- 只抽模块、不改玩法；对外 API 尽量保持

## 避雷清单（摘要）

- 抽取模块读 `TAL_BCS` 必须 `getTAL_BCS()`，bind 时快照会在 `TAL.mount` 后过期
- Church/大页 `_ENV = E` 会让 LSP 报满屏 undefined-global Error，挡 build；用 bind(deps) 具名注入
- 三行模式 `H_SEAM_BACK`：二级页返回只由中缝层画
- Lua 5.4 字符串里不要写 `\!`
- 脏工作区会让 `git merge` 失败且不建 MERGE_HEAD
- 分支禁令以用户当前轮次授权为准；本轮只推 `feat926/battle-lab`，不碰任何 workspace 分支。
- 遗匣 `seeds[].equip` 是原装备，种子合并和等级兼容绝不能改写或丢弃它。
- 不要开引擎 i18n `enabled=true`，用 `core/I18n.lua`
