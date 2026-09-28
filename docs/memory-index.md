# memory-index — 《终焉之门》改造完整交接文档

> **最新（2026-09-27，`workspace926`）**：用户要求新建 `workspace926`，合入 `workspace925` 与全部 `feat926/`：`character-drag-save`、`cleanup-unused-panels`、`remove-unused-diary`、`artifact-audit`、`battle-lab`。只推 `workspace926`，不推 `workspace` / `workspace925`。
> **feat926/character-drag-save**：英雄名册数字键保留；右栏跨栏松手取消拖拽；跨队一次提交；离线经验不算空槽；存档写入失败重试。
> **feat926/cleanup-unused-panels / remove-unused-diary**：删除旧日志页及无入口的遗物洗练、签到、旧任务、公告面板和专属图。保留城镇功绩 `TaskPage`、签到及任务服务/协议/存档、GM 公告配置、遗物奖励图标。
> **最优先的用户流程**：不可自行取消/退出任务；每次完成或受阻都要先汇报，再使用 **AskUserQuestion（非纯文字）**提供明确的下一步选项并等待用户决定。不能在仓库/记忆保存访问令牌。本轮只推 `workspace926`。

> 本文档面向**下一个 agent**:零上下文接手,先通读本文件,再按「待办清单」执行。
> **配装布局（已合入 workspace925）**：属性页隐藏装备槽和一键按钮，保留切角；配装页批量按钮置顶，内容下移 160px 预留词条。拖拽穿戴以 925 为准。
>
> 更新时间:2026-09-28 | 版本:v2.64-workspace926-artifact-audit
>
> **当前基线 `workspace926`**：已合入 `origin/feat926/artifact-audit`（神器双格 30/60、礼拜堂 30 级、宝箱迁入教堂、铁匠铺锁标）。只推此分支。
>
> 更新时间:2026-09-28 | 版本:v2.63-smith-stage-lock-label
>
> **本轮（`feat926/artifact-audit` 铁匠铺锁标显示解锁条件）**：用户问铁匠铺锁标为何不显示几级解锁。诊断：`drawBuildingLockOverlay(vg,cx,cy,key,tutorialControlled,...)` 当 `tutorialControlled=true` 时只画锁图标不画文字；铁匠铺走**关卡门控**(`TutorialManager.BUILDING_UNLOCK_THRESHOLDS.smith=204` 即通关2-4)，不是等级门控，且不在 `ExpTable.levelUnlocks` 里(`getBuildingUnlockLevel` 只返回默认1)，故原本无文字可显示——设计使然非 bug，但玩家看不到解锁条件。
>   - **修复**：`drawBuildingLockOverlay` 新增第7参 `labelOverride`(优先于等级文字)；新增 `getStageUnlockLabel(key)` 从 `_TM.getBuildingUnlockStageId(key)` 换算 stageId→"通关 chapter-stage 解锁"；`TutorialManager` 暴露 `getBuildingUnlockStageId(buildingKey)`(返回 `BUILDING_UNLOCK_THRESHOLDS[key]`，church/tavern 等引导解锁返回 nil)。铁匠铺锁标改传 `getStageUnlockLabel('smith')` → 显示"通关 2-4 解锁"(与教堂"Lv.30 解锁"风格一致)。酒馆 tavern 仍引导门控无 override(只锁图标)。
>   - 验证：LSP 0 Error(264文件)、battle_stage_switch_test 54 PASS/ALL PASS、官方 Build 成功、dist 含 getStageUnlockLabel/getBuildingUnlockStageId。**锁标文字需实机验收**。
> **上轮（`feat926/artifact-audit` 神器改双格 30/60 + 礼拜堂30级开放 + 行高压缩找回背包）**：用户两项反馈：(1) 160px 子格够大了，但**别把队伍行撑太高**——每队行只要两层160格+10padding(=330px)，剩下留给背包；提示文字上移。(2) 把神器格从 3 个(1/40/80级)改为 **2 个(30/60级)**；礼拜堂 **30 级开放**。
>   - **ArtifactSchema**：`SUB_SLOT_COUNT` 3→**2**；解锁等级 `FIRST_SLOT_UNLOCK_LEVEL=30`/`SECOND_SLOT_UNLOCK_LEVEL=60`（删 `THIRD_SLOT_UNLOCK_LEVEL`）；`getUnlockedSubSlotCount` 改 0(<30)/1(30~59)/2(≥60)；`getSubSlotUnlockLevel` 返回 30/60。**旧档迁移**：normalizeModule/dehydrate 的子格循环都按 `SUB_SLOT_COUNT` 动态遍历，旧 3 格档第 3 格自动卸下，实例仍在 `data.bag`（不丢失）——已加测试断言验证。
>   - **TownScene**：新增 `CHURCH_UNLOCK_LEVEL=30` + `isChurchAccessible()`；教堂建筑绘制/点击门控 `= not _TM.isBuildingUnlocked('church') or not isChurchAccessible()`。**引导豁免**：`isChurchAccessible()` 在 `_TM.isActive()` 时直接放行（引导组5-7 低等级点教堂/古树推进不受等级限制）；引导链结束恢复等级门控。**终焉古树不门控**（与教堂共用 'church' key 但古树是独立天赋系统，仍只按引导解锁——tree gate 已回退，避免连带锁天赋）。锁图标 label 支持 `levelOverride` 传 30 显示 'Lv.30 解锁'。
>   - **ChurchArtifactPanel 重排**：TEAM_ROW `SUB_GAP` 4→**10**、`LABEL_H` 492→**330**、`ROW_CY={465,807,1149}`（行距342、行3底1314）；HINT.Y 235→**200**（上移）；LOWER_PANEL CY 2481→**2041**（面板顶1330）；TITLE DECO/TEXT_Y 1836→**1396**；GRID CLIP 1886/2110→**1446/2110**（背包可视 **224→664px≈3.5行**，可滚动）、FIRST_ROW_TOP=1446；飘字 1770/2000→1330/1700。子格栈 2×160+10=330 恰好收进 LABEL_H=330。
>   - **AssetManifest**：移除 `UI_JTSQ_BJ.png`(1945288字节)条目 + `git rm` 图文件与 .meta（AssetManifest 实为死配置，全仓无 require/dofile 加载它；Standalone 仅有一句 print 提及）。dist 已无该 png、lua 内仅剩注释提及、无 nvgCreateImage/GetResource 加载点。
>   - **公告清理**（commit 4347b48）：AnnouncementConfig V1.0.38 '神器栏位三80级解锁'→'礼拜堂30级开放'、V1.0.28 '40级解锁第2格'→'60级解锁第2格'；全仓 scripts 已无 40级/80级 神器子格残留（UI float 文本本就读 getSubSlotUnlockLevel 动态值；ArtifactService 错误提示同为动态拼接；docs gameplay §8 与升级粉尘曲线 20/40/80 为无关数值，保留）。
>   - 验证：LSP **0 Error**(264文件,warnings 4943→4940)、battle_stage_switch_test **54 PASS/ALL PASS**（含新增 30/60 解锁+旧档3格迁移断言）、官方 Build 成功、dist 含 `SUB_SLOT_COUNT=2`/`FIRST_SLOT_UNLOCK_LEVEL=30`/`ROW_CY={465,807,1149}`/`SUB_GAP=10`/`CHURCH_UNLOCK_LEVEL=30` 且无 UI_JTSQ_BJ 图。
>   - **待实机验收**：礼拜堂 Lv30 前锁定显示(引导期豁免)/Lv30 后可进；神器页每队行仅两格(30级/60级)、行高变矮、背包可视变大；旧 3 格存档进游戏第 3 格卸下且实例回背包；顶部背景图已消失。**UI 布局与门控不在测试覆盖，需实机核对**。
> **上轮（`feat926/artifact-audit` 删神器页背景图 + 40/80级子格放大到 160px）**：用户两点要求：(1) 删除神器页顶部背景图（含加载调用）；(2) 40/80 级栏位子格不够大，改成和下方背包格一样大。**背景删除**：`ChurchArtifactPanel` 移除 `TOP_BG` 常量表、`img.topBg` 句柄、`nvgCreateImage(...UI_JTSQ_BJ.png...)` 加载与 `img.topBg<0` 告警；`drawBg` 改为纯色暗底`nvgRect(0,0,DESIGN_W,lowerTop)` 填 (30,28,34,255) + 下面板 nine-slice。**子格放大**：SUB_SIZE 130→**160**（=背包 CELL_SIZE），行区随之扩展：HEADER_Y=252、ROW_CY={518,1016,1514}（行距 498、行板高 LABEL_H=492、行3底 1760）、CX_LIST={252,476,700,924}（列距 224、格 160 列间留 64）、SUB_GAP=4、CELL_LOCK_FONT=28；背包再下压：LOWER_PANEL CY→2481（面板顶 1770）、TITLE DECO_CY/TEXT_Y→1836、GRID CLIP_TOP/BOTTOM→1886/2110（可视 **224px≈1.2 行**，可滚动）、FIRST_ROW_TOP→1886，飘字 1770/2000。**关键取舍（待用户定夺）**：屏幕总高固定 2400，160px 子格使三队行区占 ~1476px，背包可视区从 130px 方案的 445px 缩到 **224px**；若用户觉得背包太小，可回退 130px(445px) 或折中 145px(~330px)。**AssetManifest.lua:658 仍列 UI_JTSQ_BJ.png 1945288 字节**（构建自动生成的资源清单，图文件仍在 assets，但已无任何加载调用；如需彻底移除资源需删图+重建 manifest）。验证：LSP 0 Error、battle_stage_switch_test 43 PASS/ALL PASS、官方 Build 成功、dist 含 SUB_SIZE=160 且无 UI_JTSQ_BJ 加载调用。**UI 布局不在测试覆盖范围，需实机验收背景已消失/子格 160px/背包可视高度**。
> **上轮（`feat926/artifact-audit` 页签切换改水平从左滑入）**：用户要求神器/宝箱切换"都从左边切进来"。`ChurchDraw` Tab 动画从垂直滑动改水平滑动：偏移计算 oldOY_tab/newOY_tab(纵向±DESIGN_H) → oldOX_tab/newOX_tab(横向，新页 -DESIGN_W→0 从左入、旧页 0→+DESIGN_W 向右出，方向固定与页签次序无关)；背景块+内容块的 scissor 由纵向(0,y,W,h)改横向(x,0,w,H)、translate 由(0,OY)改(OX,0)。顺带清理上半区 upperTabOY 的"转职"死代码(转职页早已迁出，引用已删变量会致 nil 错)：upperTabOY 恒 0，nvgTranslate(upperOX,0)。warnings 4945→4943。验证：LSP 0 Error、battle_stage_switch_test 43 PASS、官方 Build 成功。**UI 动画不在测试覆盖范围，需实机验收切换方向/流畅度**。
> **上轮（`feat926/artifact-audit` 130px 行区重排，找回背包空间）**：用户澄清——之前误解为整框放大，实际要的是 40/80 级栏位(子格)130px 且**重排整页别把背包挤太小**。上版背包可视区仅 279px(≈1.4行)确实太小。重排垂直预算(设计高2400、底Tab栏顶~2256)：表头286 → 三队行区中心 508/918/1328(行距410、行板高404、板间6px缝、行3底1530) → 背包面板顶1540(LOWER_PANEL CY 2251) → 标题1615 → 网格可视 **1665~2110=445px(≈2.3行，可滚动)** → 合成/置换按钮2174。子格 SUB_SIZE 保持130、SUB_GAP 4、栈高398收进404板内、号位列间距224。行底板仍不透明(未解锁26,24,30/已解锁40,36,46)、背景图底边(1349)到面板顶补暗色底(30,28,34)消除接缝。底部神器/宝箱页签上版已缩小(bg 600×112、滑块300×112、字号32、cx 390/690)保持不变。验证：LSP 0 Error、battle_stage_switch_test 43 PASS、官方 Build 成功、dist 含新布局。
> **上轮（`feat926/artifact-audit` 行式布局 130px + 底部页签缩小）**：用户反馈"一行能放下三个，改 130"。子格 SUB_SIZE 100→**130**（= 原单队布局尺寸），SUB_GAP 4、行中心 519/937/1355（行距 418、行板高 408、板间 10px 缝、行3底 1559 < 背包面板顶 1569），子格栈 3×130+2×4=398 收进 408 板内，号位列间距 224。背包再下压：LOWER_PANEL CY→2280（顶 1569）、TITLE→1709、GRID CLIP 1765~2044（可视高 279≈1.6 行，可滚动）、飘字跟随。**关键修复**：130px 使三队行区延伸到 y1559，超出顶部背景图 UI_JTSQ_BJ 底边(1349)——行底板改**不透明**(未解锁 26,24,30 / 已解锁 40,36,46, alpha255)，并在背景图底边到背包面板顶之间补暗色底(30,28,34)，消除行3跨越图片底边的明暗接缝（半透明底板会透出上下亮度差）。底部"神器/宝箱"页签缩小：ChurchPage TAB bg 810×143→**600×112**、滑块 405×143→300×112、字号 40→32、两页签 cx 390/690 cy 2312。验证：LSP 0 Error、battle_stage_switch_test 43 PASS、官方 Build 成功、dist 含 130px。
> **上轮（`feat926/artifact-audit` 行式布局 100px）**：用户反馈"感觉没放大"——80px 相对原单队布局的 130px 仍偏小、且 64→80 只 +25% 不明显。子格 SUB_SIZE 64→80→**100**（累计 +56%，接近原 130）。行中心 460/792/1124（行距 332、行板高 320、板间 12px 缝、行3底 1284 在顶部背景图 1349 内），子格栈 3×100+2×6=312 收进 320 板内。背包再下压：LOWER_PANEL CY→2025（顶 1314）、TITLE→1470、GRID CLIP 1530~2044（可视高 514≈2.7 行，可滚动）、洗练飘字→1620。⚠️ 沙箱 /tmp 会被清空，git 仓库放 /home/Maker/repos/，编辑后立刻 commit+push。
> **上轮（`feat926/artifact-audit` 行式布局放大 80px）**：用户反馈框太小、背包可下压。子格 64→80px，行中心 446/713/980（行距 267、行板高 256、板间 11px 缝、行3底 1108 距下方面板顶 1118 留 10px），号位列 x252/476/700/924（间距 224）。背包整体下压 140：LOWER_PANEL CY 1689→1829（底部溢出屏幕被裁剪）、TITLE 1135→1275、GRID CLIP 1340~2044（可视高 704）、合成/置换按钮 CY 2174（距底 Tab 栏 12px）、洗练飘字 1430→1570。⚠️ 沙箱 /tmp 会被清空（本轮编辑中途丢过一次工作副本），git 仓库一律放 /home/Maker/repos/，编辑后立刻 commit+push。
> **上轮（`feat926/artifact-audit` 神器三队行式布局）**：用户要求队伍1/2/3 按行同时显示而非页签切换。`ChurchArtifactPanel` 槽位区重构：删 TEAM_TAB 页签，改 TEAM_ROW 三行布局（行中心 415/640/865，行底板高 216 占 [307,973]，表头 292，子格 64px+5 间距，队标签 x76，4 号位列 x250/462/674/886，均在下方面板顶 978 之上不重叠）。state.teamIdx 移除、加 selectedTeam；getSlotCell/getEquippedArtifact/hasSameTypeInSlot 加 team 参；drawContent 画三行（未解锁行置灰）；handleTabInput 按 team×slot×sub 三层命中，Equip/Unequip 直接带所在行 teamIdx。背包可见性 isArtifactEquippedId 改为=AnyTeam（任一队已装即隐藏，与合成/置换守卫一致）。ArtifactDetailPanel.show 加第5参 teamIdx（"slot" 卸下回传所在队，"bag" 补 nil,nil,nil）。8 处 selectedSlot=nil 全部配对补 selectedTeam=nil。验证：LSP 0 Error(280文件)、battle_stage_switch_test 43 PASS、官方 Build 成功。**待实机验收**：三行渲染/格子点击安装卸下/未解锁行置灰/背包隐藏。
> **上轮（`feat926/artifact-audit` 神器宝箱迁移）**：用户拍板「教堂双页签：装配/宝箱」+「删除市场典藏 Tab」。新建 `ui/church/ChurchArtifactDrawPanel.lua`（自包含模块：宝箱展示/保底进度/单抽十连/钥匙补购弹窗，布局沿用市场典藏并下移 CONTENT_OY=300），教堂 TAB_ITEMS/TAB_KEYS/TAB_MAP 变 shenqi+baoxiang 双页签（滑块 810→405 宽），ChurchInit setContext+init、ChurchLifecycle open 时 reset、ChurchDraw 路由 drawBg/drawContent+顶层钥匙弹窗、ChurchInput baoxiang 页签委托（弹窗模态优先，非弹窗态放行 Tab 栏点击）、ChurchResults 接管 ARTIFACT_DRAW 结果（同步保底+RewardPopup）。市场侧：删除 `MarketCollection.lua`（git rm）+ ModuleMap 条目，MarketPage 的 TAB/COL/KEY_CF/QUALITY_COLORS/collection 包装函数全移除，MarketInput/MarketDraw/MarketResults/MarketInit 相应清理，MarketResults 不再处理 ARTIFACT_DRAW（避免与教堂双弹奖励）。验证：battle_stage_switch_test 43 PASS/0 FAIL；LSP 0 Error（280 文件）；官方 Build 成功；主入口 validate 60 帧 0 Lua 错（5 个既有剧情日记缺图仍 FAIL，基线问题）。**待实机验收**：教堂宝箱页签渲染/页签切换/钥匙补购弹窗/抽取弹奖励、市场单 Tab 布局。后续微调：宝箱页签放行返回键点击（原先消费所有点击导致无法关教堂）；宝箱页 drawBg 不显示神器页顶部背景图 UI_JTSQ_BJ，改纯暗色底板铺满内容区（用户要求），topBg 句柄已移除。
> **上轮（`feat926/artifact-audit` 神器三队适配）**：用户拍板「每队独立装配 + 实例可跨队复用」。`ArtifactSchema` 装配表改为 `equippedByTeam[team][slot][subSlot]`，存档键 `e`→`et`，旧档 `e` 自动迁移为队1；`getEquippedId/setEquippedId/findEquippedSlot` 加 `teamIdx`（缺省 1，旧调用兼容），新增 `findEquippedSlotAnyTeam/normalizeTeamIdx`。`ArtifactService.Equip/Unequip` + Handler + Protocol 透传 `teamIdx`；合成/置换守卫改为「任一队已装配即拒绝」（服务端+教堂 UI 一致）。`ArtifactBridge.applyToUnit` 加第 4 参 `teamIdx`；`getDeployedTeam(teamIdx)` 按本队装配构建并给单位打 `artifactTeamIdx`，BattleScene/BattleAllyReset 波次刷新回读；`calcHeroPower(heroId, slot, teamIdx)` + `refreshPowerCache` 按队算战力。教堂神器页顶部新增队伍 1/2/3 页签（等级 10/20 解锁，切换清空选择态）。`battle_stage_switch_test` 新增 testArtifactTeamSchema/testArtifactBridgeTeam 两组断言（旧档迁移、跨队复用、队内唯一、越界回落、roundtrip、桥接隔离）。文档 §8 已同步。**尚需**：runtime 跑测试 + 官方构建 + 实机 UI 验收。
> **上轮（`feat926/artifact-audit` 神器审查）**：文档 §8 已按实际 4×3 装配、品质池与保底规则更新。`ArtifactRuntime` 按单位重置/更新并清理临时效果，影羽斗篷按初始 +200% 的比例衰减，审判锤切目标清旧层；三行加入首次死亡拦截与亡魂计时，通天塔逐名阵亡拦截。原有 `battle_stage_switch_test` 增至 24 个断言，0 FAIL；LSP 0 Error，官方 Build 成功。主入口 60 帧 0 Lua 错，5 个既有剧情日记图片缺失仍使完整 validate FAIL，不能宣称主入口完全通过。抽取中途失败的非原子性仅在人为损坏定义时可达，留待专项审查。操作不要在仓库写凭证或把测试生成的存档提交。
> **流程硬性要求（当前授权）**：不能取消/退出任务，每次交付先汇报结果。本轮只 push `workspace926`。
>
> **上一轮（`workspace925` 装备详情）**：右栏点击详情在鼠标左侧、已装备比较卡更靠左；左栏反向。点击锚点用鼠标位置，悬停跟随、钉住不漂移；套装区排在全部词条后，独立描边底板、放大字体及换行，详情热区随内容高度变化。Lua LSP 0 Error，官方 Build 成功；本地 Runtime 安装超时，尚无实际页面截图验收。下一步用游戏预览点击左右栏带/不带已装备比较的详情，特别检查最长套装描述。
> **旧会话历史**：曾授权只 push `workspace925` 或某个 `feat926/`。这些授权已被本轮「新建并推送 workspace926」覆盖。访问令牌不写入仓库或记忆。
> 更新时间:2026-09-27 | 版本:v2.54-power-calibration-samples
>
> **扩样校准与历史更正（`feat926/battle-lab`）**：上一轮 `C10` / `C4` 在 Lv.1 对照低于模板最低掉落等级 28，不能作为正常装备平衡结论。现在 `Lab.prepare` 拒绝模板 `levelRange` 外的装备等级（非法 `C10` Lv.1 已被 Runtime 错误日志拒绝）；角色/战斗公式未改。以下为真实独立 Runtime、同关同种子、普通 Lv.1 的合法饰品：`C13` 海灵吊饰（+3.60 秘识）为 A，`C1` 蓝宝石戒（+3.60 力量）为 B，均可在 Lv.1 掉落；`timeLimit=90`，每组 40 局：
>
> | 英雄/关卡 | A/B 战力 | A 胜场 | B 胜场 | A/B 场均用时 | A/B 场均输出 | A/B 场均承伤 |
> | --- | --- | --- | --- | --- | --- | --- |
> | 大狗嚼 Lv1 / 101，种子 926–965 | 112/112 | 14/40 | 40/40 | 36.41/30.16 秒 | 479.55/500 | 384.85/290.23 |
> | 大狗嚼 Lv1 / 101，种子 3926–3965 | 112/112 | 10/40 | 40/40 | 36.35/30.16 秒 | 477.75/500 | 386.64/289.09 |
> | 大狗嚼 Lv1 / 102，种子 926–965 | 112/112 | 40/40 | 40/40 | 34.82/28.02 秒 | 420/420 | 338.71/239.19 |
> | 大狗嚼 Lv1 / 103，种子 926–965 | 112/112 | 22/40 | 40/40 | 38.33/31.47 秒 | 480.55/490 | 379.45/266.80 |
> | 黄桃龙 Lv1 / 101（A=C1，B=C13） | 112/112 | 0/40 | 0/40 | 14.62/16.27 秒 | 192.55/286.77 | 249.60/273.28 |
> | 黄桃龙 Lv1 / 102（A=C1，B=C13） | 112/112 | 0/40 | 0/40 | 15.70/18.23 秒 | 198.62/296.93 | 250.65/272.44 |
> | 叮咚鸡 Lv1 / 101（A=C13，B=C1） | 112/112 | 0/40 | 0/40 | 20.66/22.12 秒 | 200.65/261 | 221.74/202.07 |
> | 大狗嚼+黄桃龙 Lv1 / 101（只换大狗嚼饰品） | 218/218 | 40/40 | 40/40 | 22.04/21.30 秒 | 500/500 | 231.02/218.86 |
>
> 八组 × 40 局同种子 A/B，复跑大狗嚼 101 种子 926–965 胜场保持 14/40、40/40、战力均 112；所有组 `errors=0`。法师/游侠两方案皆全败是难度地板、双人皆全胜是胜率天花板；场均输出受战斗提前结束和溢出限制，不可直接当 DPS，承伤较低也可能只是更快结束。实测说明通用估值对职业不敏感：力量/秘识增加相同战力，但针对物理职业战果不同；法师反向装备只观察到输出提升，未能建立胜率对照。建议**先不要全局调低魔攻/秘识权重**；若要实战预估，先做按英雄主要攻击类别的分项计价并验证物理/魔法/治疗/特殊技能，再跨敌方配置、阵容、等级取样；正式战力公式尚未改。A/B 独立进程限制仍在。旧 20 局不合规样本已标注不得外推。
>
> **历史公式演示（不能外推正常掉落平衡）**：`tests/BattleLab.lua` 支持 `loadouts.A/B` 纯配置装备，英雄 ID 对应槽位（weapon/offhand/armor/helmet/shoes/accessory）对应 `{templateId,level,ascendLevel?}`；只支持普通品质且无随机词缀，合法模板/职业类型/双手占副手/模板等级范围校验。内存装备调用 EquipmentSystem 与 EquipmentSetSystem，战斗前按 CharacterPower 同一属性权重求和，不读任何存档/星图/觉醒/神器/遗物。独立 Runtime 中 A、B 每局同种子配对，JSON schemaVersion=2 含 A、B 全量报告、paired、delta 与配装快照；未传 loadouts 时旧单方案 schemaVersion=1。旧 101 关大狗嚼 Lv1 配 `C10` 魔攻戒与 `C4` 物攻戒的 20 局结果（0/20 vs 20/20）不符合两个模板的掉落等级下限 28；仅作为代码公式演示，不作为合法装备平衡证据。LSP 0 Error/官方构建成功/旧 3 局入口通过，切关回归日志 ALL PASS（测试脚本不自动退出，外部超时）。A/B 当前仅 CLI 单行 JSON，NanoVG 工作台尚无配装编辑。只推 `feat926/battle-lab`，不动 workspace。
>
> **本轮（`feat926/battle-lab` 独立战斗实验）**：基于 `origin/workspace925@aaa53e7` 建分支，只提交并 push `feat926/battle-lab`，绝不合并或推送 workspace。`scripts/tests/battle_lab_ui.lua` 是 NanoVG 模式 B (DPR 校正) 鼠标操作台；`tests/battle_lab.lua` 读取根目录单行 `battle_lab_config.json`，写出纯 JSON `battle_lab_report.json`（两文件被 .gitignore 忽略）；实验逻辑在 `tests/BattleLab.lua`，向 BattleTriDriver 注入无存档的模板英雄，固定 1/60 步长，多局分种子记录胜率/耗时/伤害/治疗/承伤/暴击。仅独立进程安全，不能在主游戏战斗中运行；模板英雄无装备/遗物/神器，首通未模拟完整 BattleScene 进度/奖励，挂机只测本关怪物。实测 20 局首通胜、4 局挂机败、20 局超时，固定种子两次逐局数据一致，原 `battle_stage_switch_test` ALL PASS，LSP 0 Error/官方构建成功/离屏 UI 可见；尚未真人鼠标交互验收。
> **当前硬性流程**：完成或受阻先报告，再调用 AskUserQuestion 提供下一步选项；不能取消/退出任务。本轮只 push `workspace926`。令牌不进仓库与记忆。
>
> **本轮（`workspace925` 装备详情）**：右栏点击详情在鼠标左侧、已装备比较卡更靠左；左栏反向。点击锚点用鼠标位置，悬停跟随、钉住不漂移；套装区排在全部词条后，独立描边底板、放大字体及换行，详情热区随内容高度变化。Lua LSP 0 Error，官方 Build 成功；本地 Runtime 安装超时，尚无实际页面截图验收。下一步用游戏预览点击左右栏带/不带已装备比较的详情，特别检查最长套装描述。
> **历史**：旧的「只推 workspace925 / 只推某个 feat926」已被本轮「推送 workspace926」覆盖。
>
> **本轮桌面试点（`feature/background-idle-924`）**：用户选择 Windows Electron 失焦挂机。`electron-shell/main.js:145` 的 BrowserWindow.webPreferences 设 `backgroundThrottling=false`，不改 Lua/网页版本。`node --check` 和 VM 模拟创建 BrowserWindow 的断言通过（同时确认 contextIsolation/nodeIntegration 安全设置保持不变）；LSP 0 Error、官方 build 通过。当前沙箱没有 Electron 可执行文件、node_modules、虚拟显示器或 Wine，因此**没有 Windows 最小化/失焦的实机验收**，也未生成新版 Windows 包；已有 `/workspace/dist` 网页预览不会体现这项桌面独占改动。下一步在 Windows 用仓库现有 `electron-shell/pack_release.py` / 一键脚本将最新 dist 打成 Electron 包，实际对比聚焦/失焦/最小化时三队金币、经验、掉落、存档及 CPU；关闭进程/系统休眠仍需另做离线补算。
>
> **本轮（2026-09-24 `feature/background-idle-924`）**：从 `workspace924` 克隆并新开独立分支；仅调研失焦挂机，未改战斗/收益玩法。当前可用预览通过官方 build 在 `/workspace` 项目根构建（`scripts/`、`assets/`、`.project/` 从克隆仓库同步至项目根），`/workspace/dist` 约 378 MB、1,254 个资源，入口已找到；初次在嵌套目录构建生成空壳，已纠正。LSP 0 Error。**尚未做真实失焦运行验收。**
>
> **调研依据与结论（实施前记录）**：`scripts/boot/Standalone.lua:421,709-767,866-882` 的战斗依赖 `Update` 事件每帧的 `dt`；`scripts/ui/battle/BattleTriPage.lua:130-147` 行2/3亦如此。浏览器隐藏页常暂停 `requestAnimationFrame` 并节流定时器，网页/手机切后台不可保证连续逐帧战斗；前台失焦但页面仍可见时或可继续，应实测。Windows Electron 原始代码 `electron-shell/main.js:147-165` 未设置 `webPreferences.backgroundThrottling`（默认 true），后续已在本分支加 false，仅桌面试点，代价是后台持续 CPU/电量占用，进程退出/系统休眠仍无效。`scripts/boot/StandaloneSave.lua:45-47,83-117,128-169` 保存 `savedAt=os.time()`，恢复时只打印，不做补算；`scripts/boot/Standalone.lua:450-476` 的离线奖励秒数与物品写死。可行的跨平台可靠方案是记录最后结算墙上时刻、恢复时按经过秒数计算并幂等发放，限定最长时长和奖励规则；须兼顾三队 `scripts/ui/battle/BattleTriDriver.lua:183-199` 与 `scripts/boot/StandaloneBoot.lua:149-183` 的经验/金币，以及掉落的独立回调。**不能用一次大 dt 强推战斗**：`scripts/ui/battle/BattleCombat.lua:729-769` 攻击每帧有限额，`BattleSceneTick.lua` 有按秒循环逻辑，易产生积压、漏算、卡顿及重复发奖。
>
> **流程硬性要求**：不能擅自取消/退出任务；每次交付后必须用 AskUserQuestion 提供选项问下一步，禁止纯文字中断。本轮只 push `feature/background-idle-924`，不要向 `workspace924` 或其他旧分支推送。
>
> **继续试验（2026-09-24）**：用户选“试验混淆”。新增 `electron-shell/obfuscation_trial.py`（只对 allowlist 中的 `scripts/shared/StageProvider.lua` 在外部副本生成保守混淆，保留原文件/外部 API）。官方 Build 成功，资源清单与处理输出相符；原版和试验版隔离 10 帧均 PASS/0 Error。整游戏 60 帧两版均被既有 `systems/StoryPlayer` 引用缺失 `network.ClientDispatcher` 阻断，旧 `tests/lootbox_page_test.lua:173` 存档断言也在基线上失败；未能验证 Windows 成品包/存档。试验结果不得直接发布，应先修复基线。预览已恢复原版并重新 Build。
>
> **本会话（2026-09-24 `feature/pc-release-obfuscation-review`）**：从 `workspace924` 新分支核查 Windows PC 代码保护。官方构建的 `dist/1.0.7/assets` 内 `main.lua` 和 `boot/Standalone.lua` 仍为明文源码，Electron `extraResources/game` 原样复制，未启用混淆/加密。预览需要先将项目脚本/资源/配置同步到 `/workspace`，官方 MCP 构建从该根目录读取，而不是只看 scriptsPath 校验；详见 `electron-shell/README.md`。只推本分支；后续必须以 AskUserQuestion 选项确认是否做安全混淆试验。
>
> **本会话（2026-09-24 `feat/equip-ascend-924`）**：只写规划，不改玩法。装备槽位强化改为装备自身升阶，见 `docs/装备升阶规划.md`。只 push 本分支，不推 `workspace924`。
>
> **本会话（2026-09-24 `feat/story-landscape-924`）**：开场为来信 → 门厅 → 三人入队。队1写入大狗嚼、黄桃龙、叮咚鸡。侧栏返回用逻辑坐标。索引见 `docs/剧情总表.md`。
>
> **本会话(2026-09-24 feat/ce-test-tools-20260924)**：左栏入口改为「功绩」。含通关指定关、远征等级、队员集结与觉醒，并显示奖励图标。只 push 本分支。
>
> **流程硬性要求**：不能取消/退出任务。每步完成后必须用 AskUserQuestion 给选项，禁止纯文字中断。
>
> **本会话(2026-09-24 workspace924)**：合入遗匣左栏地点与溢出完整保管，以及滚轮按鼠标所在区域滚动。
>
> **遗匣**：入匣时生成完整装备，领取不重骰。筛选为全部或 1..6 品质。待整理残留不可领取或回收。
>
> **本会话(2026-09-23)**：从 `workspace` 新开 `integrate/20260923`，合入今天三条功能线 + workspace923 的一键脚本修复。含滚轮/右键装备/五语/Noto 字体、四名玩梗角色与 SE 包、未解锁职业标。未推 workspace。

---

## 1. 项目概况

- **引擎**:UrhoX(星火编辑器),Lua 5.4,单机模式(`.project/settings.json` multiplayer.enabled=false → 走 `network/Standalone.lua`,横屏 HORIZON_MODE=true)
- **原游戏**:《宿命旅途 Destiny Brigade》竖屏放置 RPG,20 个正经风冒险家角色
- **改造方向**(用户拍板):① 全角色玩梗化 ② 整体转**暗黑风格**(游戏名/标题/背景/人物图)③ 横屏标题页+背景视频化(视频未做)
- **新游戏名**:《终焉之门 Gate of Finality》
- **玩家称呼**:远征长(组织:远征队)
- **关键文件入口**:`scripts/config/HeroConfig.lua`(角色)、`scripts/ui/DarkTitleScreen.lua`(横屏标题)、`scripts/ui/story/gate/LetterIntro.lua`(外祖父遗产信)、`scripts/network/Standalone.lua`(单机主循环)、`scripts/config/DialogueConfig.lua`(战斗台词)、`scripts/config/ScenarioDialogueConfig.lua`(剧情对话)

## 2. 决策时间线(为什么做成这样)

| # | 决策 | 结果 |
|---|------|------|
| 1 | 20 角色匹配玩梗形象并改名(联网调研梗背景) | 全量替换完成,词表见 CLAUDE.md |
| 2 | 真人名全部谐音化(闪电麦昆→闪电卖鸡;避开真人) | 用户明确要求避开真名 |
| 3 | 台词梗味拉满+一次性全量 | 战斗台词 24 角色(补齐 16/20-23)+剧情 73 情景重写 |
| 4 | "汪"→"叫!"(大狗嚼专属) | 全局替换,零残留 |
| 5 | 名字二轮调整:黄桃龙/阿姨压/小黑子/真布诗人;(叉腰)→(捧腹大笑);20 称号玩梗化 | 全局替换,零残留 |
| 6 | 玩家称呼:团长→远征长;冒险团/旅团→远征队(86 处) | 完成 |
| 12 | 玩家可见「冒险*」统一为远征世界观：冒险等级→远征等级、冒险家→远征队员、冒险招募券→远征招募券、冒险日志/奖励→远征日志/奖励；冒险者公会显示名沿用亡誓公会。内部键名(`adventurer`/`recruitTicket`/`playerLevel`/`guild`)不变 | 完成，分支 `feat/rename-adventure-to-expedition` |
| 7 | 游戏名改暗黑风:《终焉之门》;标题背景横屏暗黑;后续视频化 | 背景图已出,视频未做 |
| 8 | 标题页:发现现成 `DarkTitleScreen.lua`(HORIZON 横屏标题载体),只换素材/配色 | 上线,游戏内实拍验收通过 |
| 9 | 图片实装:A 方案先 3 张(#9/#11/#21)验证,再全量 20 张卡面+17 张立绘 | 实装完成,但用户验收未通过(见 §5) |
| 10 | 外祖父遗产信(LetterIntro):另一会话实现,本会话做世界观修正(远征长/火漆「终」) | 已实装,新玩家首登触发 |
| 11 | **验收未通过 → 生产管线升级**:三层参考(原版卡面+暗黑基准图+全队画风板)+强梗 prompt+暗黑背景 | 试点 #4/#5 通过,全量待做 |

## 3. 生产管线(照抄即可复现)

### 3.1 立绘生成(当前最新版管线)

```
generate_image:
  model = "gpt"(GPT Image 2)
  aspect_ratio = "2:3", target_size = "832x1248"
  reference_images(三层):
    [1] 该角色原版卡面:  /workspace/.tmp/cardref/old_{id}.png   ← 锁角色长相
    [2] 暗黑版基准构图图: /workspace/assets/image/edited_风格基准图_暗黑版_20260912224014.png ← 锁构图/背景/光线
    [3] 全队画风板:       /workspace/assets/image/全队画风板_原版卡面.png   ← 锁整体画风
  prompt 模板(替换 <梗装束> 段):
    "生成一张游戏角色卡面立绘。第一张参考图是角色原版卡面(角色长相基准):<外观描述>。
     第二张参考图是暗黑版构图规范基准图:裁切位置(七分身,头顶到大腿中部)、站姿、
     背景(深紫黑垂直渐变纯净暗幕)、光线(左上冷调主光+轮廓边缘光)必须与第二张完全一致。
     第三张参考图是全队画风板(整体画风统一参照)。
     将第一张参考图的角色 <梗装束描述,梗元素为画面主体>。
     画风与第三张参考图一致:anime game character illustration, soft cel shading。
     clean, smooth, no film grain, no noise。没有漂浮粒子、闪光点、镜头光晕。
     不添加文字、水印。"
```

- 发色**不锁**(用户明确"颜色不一定要遵循之前的,只是风格需要参考")
- 梗装束要写成**画面主体**,不能只是小配饰(验收教训)
- 20 个角色的梗装束方案见 §6 待办附表

### 3.2 卡面制作(从立绘)

```bash
# 脸部特写裁切 + 品质晕 + 紫框(⚠️ 裁切参数需逐张校准,见 §5 问题2)
convert 立绘.png -crop 362x800+235+40 +repage -resize 390x876! base.png
convert -size 390x484 xc:'gray(3%)' m1.png
convert -size 390x392 gradient:'gray(3%)-gray(90%)' m2.png
convert m1.png m2.png -append mask.png
convert -size 390x876 xc:'<品质晕色>' mask.png -alpha off -compose CopyOpacity -composite tint.png
convert base.png tint.png -compose Over -composite -bordercolor '#c35ae4' -border 10x10 KP_YX_{id}.png
```
品质晕色:R=`4a9d5c` SR=`a45fd0` SSR=`e8b83a` UR=`d0454a`(用户验收后可能要暗黑化这些晕色)
**已知问题**:统一裁切参数导致 12 张卡构图错误(脸切半/偏/空),见 §5 问题 2

### 3.3 黑白抠图法(透明 PNG,LOGO/立绘透明底用)

白底 generate_image → `edit_image(model="nanobanana")` 黑底(构图必须一致)→ ImageMagick 差分:
```bash
convert white.png black.png -compose difference -composite diff.png
convert diff.png -colorspace Gray -negate alpha.png
convert black.png alpha.png -alpha off -compose CopyOpacity -composite out.png
convert out.png -trim +repage out.png
```
产出:`assets/image/LOGO终焉之门_透明版.png`(TrueColorAlpha 已验证)

### 3.4 引擎渲染管线(资产导出/验收截图)

```bash
# 离屏截图(资产导出、UI 验收)
LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe EGL_PLATFORM=surfaceless \
timeout 280 ./.cli/UrhoXRuntime <script>.lua -tapcode_dir=/workspace -tool_mode \
  -graphicssurfaceless -screenshot=<abs path> -screenshot-frame=<N> -x <W> -y <H>
# ⚠️ timeout 给够(280s+),超时静默失败不落盘——完成后必须 stat 检查 mtime
# ⚠️ 脚本热加载正常,但 -tool_mode 资源从 pak 加载,assets 新文件需 build 后才进 pak?
#    实测 assets/image 下的图即时可见(资源目录挂载),scripts 的 .lua 实时读取
```
可复用脚本:`scripts/_proc/`(render_portrait.lua / cardref_render.lua / roster_board.lua / render_letter.lua / card_preview.lua / implement_check.lua)

### 3.5 参考图体系(重要教训)

| 参考图 | 路径 | 状态 |
|--------|------|------|
| 原版卡面(20,可靠) | `.tmp/cardref/ref_{id}.png` | ✅ 引擎渲染导出,**当前的正确参考** |
| 高清立绘 ref_1/2/3 | `.tmp/portraits_hd/ref_{1,2,3}.png` | ✅ 合格(与卡面一致) |
| 孤儿立绘 ref_5/9/10/11/13/20/21 | `.tmp/portraits_hd/` | ❌ **禁止用作角色参考**(内容与卡面角色不对应) |
| 暗黑版基准构图图 | `assets/image/edited_风格基准图_暗黑版_20260912224014.png` | ✅ |
| 全队画风板 | `assets/image/全队画风板_原版卡面.png` | ✅ 20 原卡 5x4 拼图 |
| 基准构图图(浅色版) | `assets/image/edited_风格基准图_构图规范_20260912111509.png` | 已被暗黑版取代 |

## 4. 资产与实装状态

### 4.1 已实装(游戏内生效)

| 资产 | 状态 |
|------|------|
| `assets/image/角色立绘/UI_DLH_{1..23}.png` | 20 张玩梗立绘(832x1248 PNG)全量 ✅ |
| `assets/image/角色卡牌/KP_YX_{1..23}.png` | 20 张玩梗卡面(410x896,第一版浅灰白背景)全量 ⚠️ 待重做 |
| `assets/image/UI_TITLE_BG_GATE.png` | 终焉之门标题背景 ✅ |
| `assets/image/UI_WORLD_BG.png` | 世界大背景(1920x1080 横屏空旷雾原)✅ |
| `assets/image/关卡地图/MAP_*.png`(27 张) | 统一大背景竖裁版 ✅ |
| 7 个页背景(`UI_CZ_BJ/UI_TJP_CH_1/UI_KCBJ_1/UI_KCBJ_2/UI_SCBJ/UI_JJC_BJ1/UI_JTZZBJ`) | 统一大背景竖裁版 ✅ |
| `scripts/ui/DarkTitleScreen.lua` | 终焉之门标题(紫辉粒子+新 LOGO)✅ |
| `scripts/ui/story/gate/LetterIntro.lua` | 外祖父遗产信(精修版)✅ |
| `assets/image/LOGO终焉之门_透明版.png` | 游戏标题 LOGO(黑白抠图法)✅ |
| 台词/对话/名字 | 全量 ✅ |

**备份**(回滚用):`.tmp/implement_backup2/{立绘,卡牌}/`(全量实装前)、`.tmp/implement_backup/`(A 方案前)、`.tmp/worldbg_backup/`(页背景/关卡图原 KTX)

### 4.2 已生成未实装/中间产物

- 20 张玩梗立绘源 PNG:`assets/image/*立绘*.png`(与实装版相同,源文件)
- 暗黑强梗版试点:`assets/image/接化发掌门_暗黑强梗版_20260912224219.png`、`叠甲怪_暗黑强梗版_20260912224336.png`(**待用户最终验收**)
- 20 张可靠卡面参考:`.tmp/cardref/ref_{id}.png`
- `.tmp/roster_export/cards/`(**部分噪声,不要用**)、`.tmp/portraits_hd/`(高清立绘,1/2/3 合格其余孤儿)

## 5. 用户验收结论(2026-09-13,当前卡面 v1 未通过)

1. **梗浓度不足**:部分角色只加小道具(阿姨压=小话筒、弹弹弹=细弹簧、愤怒的小雀=普通蓝帽),与原卡相似度高。修法:梗装束写成画面主体(试点 #4/#5 已验证可行)
2. **缺暗黑风格**:卡面背景浅灰白与游戏暗黑风不符。修法:三层参考管线(暗黑基准图),试点已验证
3. **裁切比例有误**(12 张):#1/#6 裁到只剩头发、#4 脸偏右、#11/#12/#13/#22 脸切半、#14 裁到袍子、#16 近全空、#20 切脸、#23 帽子挡脸。根因:统一裁切参数(362x800+235+40)不匹配各立绘脸部位置。修法:**逐张看立绘定 crop 参数**(校准底图:`assets/image/当前卡面_校准底图.png`),或重生成时用暗黑基准图锁定构图后统一参数
4. 合格 8 张可保留:#2/#3/#8/#9/#10/#15/#21(+#5/#4 已重做待验)

## 6. 待办清单(下一个 agent 按序执行)

1. **[P0] 试点 #4/#5 最终确认**(图:`assets/image/暗黑强梗版_试点预览.png`)→ 用户点头后:
2. **[P0] 全量 20 张立绘重做**(§3.1 管线,梗装束方案:
   大狗嚼=马犬拟人+叼骨+项圈 | 黄桃龙=恐龙连体帽+呆萌 | 叮咚鸡=鸡帽+门铃弓 | 接化发掌门=黑太极服+三段手印✅ | 叠甲怪=塔状层叠甲+盾帽✅ | 阿姨压=墨镜+巨型复古麦+音浪 | 信光机兵=红银紧身衣+计时器 | 愤怒的小雀=蓝羽卫衣+巨弹弓 | 卡皮巴拉=水豚头套+顶橘+抱水豚 | 铁憨憨=扛铁门+憨笑 | 熬夜冠军=黑眼圈+刀+咖啡+新月 | 雪皇=金冠+红斗篷+冰淇淋权杖 | 弹弹弹=巨弹弓+粗弹簧+卡通拳 | 内鬼=黑袍+墨镜+嘘手势 | 复活吧爱人=修女+复活光环 | 万剑归宗=白衣剑仙+万剑悬空 | 摘星星星人=白色飞天航天服+星星网兜+星门 | 闪电卖鸡=红赛车服95号+墨镜鸡 | 小黑子=中分白衬衫棕背带裤+篮球+白公鸡 | 真布诗人=绿羽帽+墨镜金链+复古麦)
3. **[P0] 卡面裁切逐张校准**(§5 问题 3)→ 品质晕暗黑化(深紫/暗金/暗红,用户暗示不要亮晕)→ 实装
4. **[P1] 图标 P3**:20 个 `UI_icon_hero_{id}.png` 从新卡面/立绘裁切
5. **[P1] 标题背景视频化**:以终焉之门图为首帧(紫光呼吸/云层流动),`create_video_task`
6. **[P1] 入队台词**(挂起):DialogueConfig 加 join 触发(24 角色)+ RecruitAnim 招募展示接入(调研到一半:`RecruitAnim.lua` 卡牌展示,`TavernPopups.lua` 15:11 后未被并行会话编辑)
7. **[P2] 牢大角色**:高风险(真人逝者梗),建议黑曼巴蛇拟人替代,用户未定;新角色槽位 17 或 24,需要 HeroConfig+TalentManager+素材三件套+GachaConfig+TavernConfig+ArenaAITemplates
8. **[P2] 竖屏 StartScreen fallback 的旧 LOGO**(横屏下已被跳过,代码保留)
9. **[观察] 人物图暗黑化**:用户说"或许还要影响到人物图"——立绘暗黑化试点未做,等用户拍板

## 7. 坑与抗体(全部实测踩过)

1. **并行 agent 会话互相覆盖文件**(已发生 2 次:LetterIntro 被覆盖回旧版、HorizonBg 中间态)。开工前 `stat` 关键文件;发现语义漂移立即和用户确认
2. **assets 的 .png=KTX 纹理**:ImageMagick 读不了(`improper image header`);`Texture2D:GetImage()` 压缩纹理出噪声;唯一可靠导出=surfaceless 渲染截图
3. **-screenshot 超时静默失败**:exit 0 但文件不落盘;必须 stat mtime 验证;软渲染预算:1600x900×240帧≈100s,1080x2400×60帧≈90-150s
4. **build LSP 挡类型标注**:`nvgCreateImage`→`integer?`;修法 `or -1`+`---@return integer`;行内 `---@diagnostic disable-line: xxx`
5. **nvgClip 不存在**;nvgScissor/nvgIntersectScissor 存在;ImagePattern+RoundedRect 填充自带裁切
6. **nvgImagePattern 映射**:pattern 尺寸与 nvgRect 尺寸必须一致,否则内容错位
7. **全角括号 sed 不稳定**:`sed 's/(叉腰)//'` 失败,用 python `'\uff08...\uff09'`
8. **generate_image 中文文件名输出**:带时间戳,引用时先 ls 确认全名
9. **真人梗高风险**:牢大(科比逝者梗)→ 建议"黑曼巴拟人"替代;ikun 梗用软化变体("只因你太美"原句可用但避免真名)
10. **多角色参考图实测**:`reference_images` 3 层(角色卡面+基准图+画风板)效果最好;20 张全塞不行(上限 13-14)

## 8. 对话系统结构(改台词时看)

- `DialogueConfig.lua`:LINES[heroId] = {entry/crit/kill/death/victory},`get(heroId, type)` 数组随机;24 角色全配
- `ScenarioDialogueConfig.lua`:SCENARIO_1~73(无 66),mode=large/small,steps[].characterId(1=大狗嚼 2=黄桃龙 3=叮咚鸡 4=??? 5=神秘少女 6/7/8=假角色 9=村长 10=铁匠 11=卫兵 13=老板娘 21=圣女),rewards(equip/hero/scroll);触发在 `network/ClientScenarioHelper` + `Client.lua`(playFirstVisit(id, branchTable, cb),branchTable 按 heroId 分支)
- 战斗台词触发:`DialogueConfig.get` 由战斗系统调用(entry/crit/kill/death/victory)

## 9. 用户画像(observed,待下一 agent 续充)

- 决策快,验收严:每轮交付都逐张看图挑毛病,不接受"差不多"
- 喜欢玩梗浓度拉满,但**避开真人真名**(自发提出谐音化)
- 会在多个 agent 会话并行推进同一项目(⚠️ 见抗体 1)
- 常用笔误:"例会"→立绘、"该名字"→改名字,理解意图勿纠结字面
- 倾向"先试点看效果,再全量"的节奏(A 方案、暗黑强梗试点均如此)
