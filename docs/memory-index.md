# memory-index — 《终焉之门》改造完整交接文档

> **最新（2026-10-03，N03已实施）**：用户选择实现N03，分支`feat1003/samsara-n03-20261003`保留规划并同步已合PR45的剧情基线。新增“十二号箱”一旁白＋七句无奖切片、真实204与可信E02历史资格、旧44–46对应语境、手动历史补读、缺来源静态原文、第五记录入口；不重扫已捕获阴性、不改N12案件副本来源、不加N02/N12硬前置。官方build成功、8Lua与产物一致，N03专项62用例1574断言，N02兼容510、征用899、宿主1118及八套旧回归全过；最终独立复核未确认新增阻塞。实机排版/完整通关未验收，详情见memory/WORKFLOW_RULES.md。只push新分支、不推workspace或原剧情基线，完成后真正AskUserQuestion。

> **最新（2026-10-03，续作PR与下一批规划）**：N12–N14已创建[PR #45](https://github.com/FanZeros/changeForJourney/pull/45)，head=`feat1003/samsara-n12-n14-20261003`、base=`feat1003/samsara-story-wiring-plan`，创建时open/mergeable clean，收尾查询已由外部操作合并，本会话未执行合并。用户仅授权“PR并且规划下一批”；新纯规划分支`plan1003/samsara-next-slice-20261003`，推荐先补N03退回货单，不把N03强加为N12前置，也不改写已有案件副本来源。N15–N18因缺投影/救援经历/地狱批注和调查触发暂后置；详细计划追加在[接线方案](轮回剧情最小切片接线方案-1003.md)。本轮不改Lua/资源/存档，不重复build，完成后只push新规划分支并真正AskUserQuestion。

> **最新（2026-10-03，N12–N14续作）**：从用户指定 `feat1003/samsara-story-wiring-plan@35af331` 新建 `feat1003/samsara-n12-n14-20261003`，追加货牌核验／灰印征用令／人员卷三段无奖切片，独立cargoHistoryCaptured防N02旧标记漏迁移，严格raw204/4905与真实首通，三段串行、证据分层、四标签回看及原仲裁门禁保留。N02基线本轮官方build成功并复跑496/763通过；续作三套510＋880＋1108断言/0失败及八套旧回归全过，9Lua与部署产物一致。主入口限时只观察16/17，不称实机完整启动/新剧情视觉通过。具体状态见 `memory/WORKFLOW_RULES.md`；只推新分支，不混最新930功能、不推原基线或workspace系列，完成后真正AskUserQuestion，凭据与本地配置不提交。

> **最新（2026-10-03，N02已实施）**：用户明确继续当前 `feat1003/samsara-story-wiring-plan`，从 `b8645c20` 落地N02及功绩旁轻量“剧情记录”。独立无奖节点`samsara.log_leaf`、E01普通原件、待阅/已读/已跳过/回看、token+epoch中断恢复、严格104原始资格捕获、session双迁移与显式换表附着、真实Flush返回/节流重试均接通；旧正文/奖励/FIFO不改，N12–14仍未实施。新增专项1259断言/0失败，八套原回归通过；真实宿主开场→Boot首通回调→旧日志→N02跳过→下帧回看及记录页截图验收通过（战斗触发/文件为边界替身，不证明完整战斗胜利）。详细范围与已知旧battle getter缺口见 `memory/WORKFLOW_RULES.md` 本轮条目。仅推当前同名分支，不推workspace；完成后最后实际AskUserQuestion，凭据/本地身份/截图不提交。

> **最新（2026-10-03，切片接线方案）**：用户选择仅制定方案，由 `bc85ac6b` 新建 `feat1003/samsara-story-wiring-plan`。新增[最小剧情切片接线方案](轮回剧情最小切片接线方案-1003.md)：N02和N12–14独立无奖命名空间、唯一播放仲裁、token/epoch结束、严格通关资格、session迁移、旧档缺73补读政策、E02静态支持与验收矩阵。没有实施接口/模块/Lua，未改旧队列/奖励；提交只推新分支，之后AskUserQuestion继续。

> **最新（2026-10-03，正文精修）**：用户选择精修，由 `8f8d1e92` 新建 `feat1003/samsara-story-polish`，同一[剧情正文](未寄出的撤离令-剧情正文普通至炼狱-1003.md)升级v0.2。25场不扩展，减少前段制度说明、增强人物动作与“收到”悬疑，灰印/少女认责有交证行动；修罐头刻痕时序和原联保留，E04初次遮盖、N18再核验，不改旧对话/Lua/奖励，仍未接游戏。只push新分支，交付后AskUserQuestion继续。

> **最新（2026-10-03，正文扩写）**：用户选择“扩写剧情正文”，由 `faf5129d` 新建 `feat1003/samsara-story-script`。新增 [普通至炼狱剧情正文](未寄出的撤离令-剧情正文普通至炼狱-1003.md)：五幕25个新增场景、物证原文与核验批注、作者事件表。全部纯文档，不接游戏、不改旧对白/Lua/奖励；团灭双分支、灰印责任、资源来源与炼狱不提前结局均明确。完成后只push新分支，以AskUserQuestion继续；详情见项目工作铁律本轮条目。

> **最新（2026-10-03，轮回剧情）**：基于 `workspace930@b24cad7c` 在新分支 `feat1003/samsara-loop-story-plan` 保留全部现有情景/来信/战斗对话，退役旧 `IntroCutscene` 及专属素材。旧单场轮回改为Phases准备pending→宿主全部回灌→默认完成；三队共享池路径不改。新增 [轮回剧情核对与循环悬疑规划](轮回剧情核对与循环悬疑规划-1003.md)，暂定《未寄出的撤离令》，新因果/物证/结局仅为待确认策划，未上线。剧情总表82按现代码修正为10碎片，未改奖励。协作流程继续强化：仅push新分支，不push workspace系列；完成或需用户决定的阻塞后真正调用AskUserQuestion；凭据与本地构建身份不提交。实际验证结果见 `memory/WORKFLOW_RULES.md` 的本轮条目。

> **最新（2026-10-03，选择性迁移）**：用户经 AskUserQuestion 选择“UI＋轮回补图”，基于 `workspace930@eec2a976` 新建 `feat/workspace930-ui-reincarnation-20261003`。仅迁语言2+2+1三行与点击/兑换码/背景边界、玩家框增高130与“远征时间”、遗匣/功绩名牌对齐；补 `JQBJ_1/2.png` 及原meta（2,971,190字节，已核实入包）。不整支合并旧候选、不回退觉醒/CG/装备/剧情；73张已有CG/套装PNG哈希不变，套装开关字段保留。新增回归22用例/525断言全过，套装26/66、离线487、剧情82和装备冒烟回归全过；9组真实离屏（设置五语/玩家/城镇/轮回两阶段）均135帧原始PASS，临时验收入口已清理，官方最终Build成功。细节见 `memory/WORKFLOW_RULES.md`。前序审查存 `review/workspace930-local-art-audit-20261003@68e9a14`。**持续遵守：只push新分支，不push workspace/workspace930、不自动合并；完成后必须以AskUserQuestion选项继续；凭据、本地身份和截图不提交。**

> **本轮（2026-09-30，`feat930/equip-ascend-random-affixes` 装备升阶随机词条）**：用户拍板规则=**所有品质可参与；每跨过 +5 的倍数阶必得 1 条普通词条；普通词条上限 4；魔化词条不占普通上限**。基于 `workspace930` 新建分支。核心=`BlacksmithService.rollAscendAffixes(equip,from,to)`，单阶 `AscendEquip` 与一键 `AscendEquipToLevel` **共用逐阶抽取**（`level%ASCEND_AFFIX_INTERVAL==0` 判里程碑，复用 `EquipmentSystem.rollAffixes` 排除已有 key）；配置 `BlacksmithConfig.ASCEND_AFFIX_INTERVAL=5`/`ASCEND_NORMAL_AFFIX_LIMIT=4`。**腐化兼容（关键）**：腐化态升阶新词条插入 `corruptRevert.affixCount` 保留段内+平移 `"s"` patch 索引+`affixCount+1`→神圣石净化只删腐化新增、保留升阶词条；旧 `corruptOriginalAffixes` 先 `migrateLegacyCorruptSnapshot`；升阶清 `pendingRefines[uid][seq]` 防旧洗练预览覆盖。**洗练门槛放开**：`RefineEquip` 校验从「按品质 `qDef.affixCount`」改「按实际 `#equip.affixes`」→q1 升阶得词条后可洗练；点金石补条排除已有 key（原传空表会重复）；洗练石/普通洗练 `maxAffixQuality` 对 q1 用 `math.max(1,...)` 兜底。UI：`BlacksmithEnhance` 词条行距压缩+满员/规则提示+一键弹窗「将新增 N 条」+成功 toast；`BlacksmithRefine` 行 step 自适应+scissor 裁剪+锁定图标行距同步；文案「强化」→「升阶」。**验证全绿**：新增 `tests/equip_ascend_affix_test.lua` 48 断言 ALL PASS；既有 auto_decompose/lootbox_overflow(18)/battle_stage_switch/character_power_estimate 全 PASS；主入口 validate lua_errors=0、engine_errors=19、total=25 **与基线逐项一致**（首跑 22 为冷启动波动）；官方 Build 381 Lua；LSP 改动 6 文件 0 Error（全仓唯一 error=基线既有 `Standalone.lua:806` 跨文件全局，未动）。**环境**：headless 运行时 `python3 .cli/install-urhox-runtime.py --dest /workspace/.cli`（sh 无执行权限、py 默认 dest 推导到根 /.cli 无权限须显式 --dest）；测试 `cd /workspace && ./.cli/UrhoXRuntime tests/xxx.lua -tapcode_dir=. -tool_mode -graphicsheadless`（EXIT=124=测试不退出的已知行为，看 ALL PASS）。**待实机验收**（headless 测不了渲染）：升阶页 4 词条+提示排版、洗练页 5 词条不溢出、一键弹窗「将新增 N 条」、升阶 toast、q1 升阶后洗练入口。**本轮续（同日，满员改倍率升级）**：用户拍板「满了后改为词条倍率升级（栏位倍率，不随洗练丢失）」→装备实例新增 `affixMult`（nil=1），满 4 条后每个 +5 里程碑 `+= ASCEND_AFFIX_MULT_STEP(0.10)` 千分位取整防漂移；**倍率与词条 value 解耦**（value 恒为基础 roll 值，洗练/腐化/净化不碰倍率），生效值统一走 `EquipmentSystem.effectiveAffixValue(equip,affix)`（普通×倍率、魔化不乘），接入属性管线 computeModifierEntries+战力 calcEquipPower×2+显示 EquipmentDetail×2/CharacterDetailEquip/BlacksmithEnhance/BlacksmithRefine（腐化对比 before 同乘倍率保持口径；品质比例仍基于基础 value）；dehydrate/hydrate 持久化（=1 省略）；回包带 multUps/affixMult；UI 满员提示/一键预览「倍率 ×a→×b」/toast 合并。测试扩到 **74 断言 ALL PASS**（含洗练+洗练石+替换不丢倍率/JSON 往返/18层=2.8无漂移/腐化态累加+净化不丢）；既有回归全 PASS；validate lua_errors=0（engine_errors 19↔21 为 headless shader 非确定性波动，错误行两次相同均环境性）；Build 381 Lua。只 push `feat930/equip-ascend-random-affixes`，不推 workspace*。

> **本轮（2026-09-30，`audit929/dead-module-scan` 全游戏可疑模块审计+死代码清理+更新弹窗接线）**：任务=全仓排查可疑模块（无调用/无法进入）。**方法**：从 `main.lua` 建 require 依赖图 BFS（覆盖 `require`/`pcall(require,…)`/字符串常量/`ModuleMap.resolve` 四种引用形式；`LocalActionBridge.packs` 表用字符串常量动态加载全部 `rules/*Handler`，必须按字符串匹配否则 40 个 rules 模块全被误判死代码）。378 模块中正式代码不可达仅 4 个：`ui/battle/fx/DamageGlyph.lua`（孤立目录死代码）、`rules/SaveManager.lua`（单机 stub 死代码）、`shared/VersionConfig.lua`（死配置，"1.0.39" 与 project.json "1.0.7" 不一致证明无人读）、`config/AssetManifest.lua`（死配置；**关键澄清**：`.project/resources.json` 为全量引用模式 `groups.default=["**"]`，图片打包不依赖它，旧记忆"不能删 AssetManifest"的顾虑仅在增强引用模式下成立）。另 `UpdateNoticePopup` 仅挂 ModuleMap→dev 钩子 `H_AUTO_OPEN_PANEL`（Standalone.lua:1007），游戏内永远无法弹出。**处置**（用户选定删全部+接线）：①删 4 死模块 8 文件 -840 行（含 .meta，`git rm`）；②接线 UpdateNoticePopup：弹窗加 `notifyOnce()`（进程内仅弹一次）+init 幂等+draw 懒初始化；触发点=`SpinePowerUpEffect.ensureLoaded` 与 `SpineCardEffect` playAnim/draw 懒加载共 3 处，检测 `type(nvgSpineCreate)~="function"`（旧 TapTap 客户端缺 Spine 扩展）或创建失败；`SpineCardEffect` 改为 `nvgSpineCreate and nvgSpineCreate(vg) or nil` 防全局缺失直接报错；boot 队列注册 init；`StandaloneHorizon.finishFrame` 收尾统一 `drawUpdateNotice()`（1080×2400 letterbox 居中同 PlayerInfoPanel 模式，覆盖全部 early-return 路径），Down 吞按下/Up 最高优先级任意释放关闭（含 letterbox 逆变换）/Move+Wheel 屏蔽。验证：全仓 LSP 0 Error(287 文件)、官方 Build 成功、dist 核验 4 死模块 0 产物+notifyOnce 进 3 产物+drawUpdateNotice 进 Horizon 产物。⚠️ UrhoXRuntime 沙箱安装超时，battle_stage_switch_test 未跑（本次不触战斗逻辑，风险低）；弹窗展示/关闭为交互路径需实机验收（可临时 boot 后调 `notifyOnce()` 验证）。报告全文 `docs/可疑模块审计-0929.md`。**⚠️ 流程硬性规范（每轮强化，务必遵守）：绝不取消/退出任务；每轮任务完成或受阻后，必须以 AskUserQuestion 工具（非纯文字）提供下一步选项并等待用户决定，不得用任何非 AskUserQuestion 的形式中断对话。**
> **本轮（2026-09-29，`fix928/equip-drag-hidden-tab` 仓库拖装备到隐藏配装页的不可见穿装修复）**：用户反馈「不显示配装时，从左侧仓库装备栏拖动竟然还能拖到右侧原本的装备位置」。根因：`EquipCrossDrag.tryDrop/draw` 的门控只排除了觉醒页（`isAwakenTab`），未要求「必须是配装页」——属性页(tab=attr)/转职页(class)时装备槽不绘制（`CharacterDetailDraw.lua:789` 以 `tab=="equip"` 包住槽位绘制），但 `hitSlot` 仍按 `Draw.DT_SLOTS` 固定坐标命中并发 `EQUIP_ITEM` → 不可见穿装；`draw` 同样会在不可见槽位画金色高亮圈误导玩家。**修复**：①`CharacterDetail.lua` 新增 `isEquipTab()`（return `detailState.tab == "equip"`，与绘制门控同源，仿 `isAwakenTab` 先例）；②`EquipCrossDrag.tryDrop` 拆分 heroId 与 tab 两条拒绝，非配装页时 `reject("请先切到配装页")` 直接 return（不发协议）；③`EquipCrossDrag.draw` 高亮门控同步改为 `isEquipTab()`。投放判定现精确镜像槽位可见性，`tryDrop` 是唯一 `EQUIP_ITEM` 发送路径已堆住。验证：全仓 LSP severity=1 → 0 Error(276 文件)、battle_stage_switch_test ALL PASS、character_drag_horizon_test PASS(仅覆盖编队卡拖拽，未覆盖 EquipCrossDrag)、官方 Build 成功、dist 含「请先切到配装页」门控串与 3 处 isEquipTab。拖拽投放是交互逻辑，无头测试不覆盖，需实机验证：属性/转职页从左侧仓库拖装备到右栏原槽位 → 应弹「请先切到配装页」且不穿装；配装页拖装 → 正常穿装。
> **最新（2026-09-28，`workspace928`）三队并行·编队变更隔离修复**：用户问"队伍变化不影响三个战斗（对应列没变动就继续）做好了吗"。排查结论：**机制本已存在但有一个破坏隔离的 bug**。机制=`BattleTriDriver.update` 每 15 帧比对 `CharacterPanel.getTeamSignature(self.teamIdx)`（签名=4槽heroId序列，升级/装备不触发），变了才 `self:start()` 重启本行——每 driver 独立、天然按队隔离；`BattleTriPage.invalidateTeams(onlyTeams)` 支持选择性失效。双路触发：路径A `ClientMessageHandler.onHeroesDataUpdate`（deployed 快照变化）、路径B `CharacterHeroSync.setHeroesData`（prevLayout 精确对比→invalidateTeams(changed)）。**Bug**：路径A 原来调 `invalidateTeams()` **无参=三队签名全清 nil**，任一队变更（deployed=team1 变化即触发）会把三行战斗全部重启，路径B 的精确失效被抢先作废。**修复**：路径A 改 `invalidateTeams({ [1]=true })` 只失效 team1（deployed 仅代表 team1）；team2/3 由路径B 精确失效。现在：改队1→只行1重启；改队2→只行2重启；升级/装备/觉醒→三行都不重启（_pendingSnapshot 波次切换生效）。LSP 0 Error。
> **最新（2026-09-28，`workspace928`）战斗状态指示去 emoji 图标**：用户反馈"战斗中角色卡面左上角状态图标有些不显示"。根因=`BattleDraw.lua` §10 状态指示用 **emoji 文本**（VISUAL_MAP：🔥⚡❄️🎯💚💀🔮）经 drawTextStroke 绘制——⚡(文本呈现字符)/❄️(带VS16变体选择符)在引擎字体 fallback 缺字显示空白/豆腐块，且 8 方向描边给彩色 emoji 透脏黑边、状态色染色对彩色 emoji 无效。用户选定方案=**全部不显示 emoji，保留整卡状态色罩**（v1 色 alpha40 圆角罩）。只改 BattleDraw 一处；副本/通天塔/三行战斗均走 `BattleDraw.drawCardGroup`，全战斗类型生效。`SEM.getVisuals`/VISUAL_MAP 数据保留未动（色罩仍取 v1 颜色；未来若要恢复图标建议用汉字徽标或矢量图标，勿再用 emoji）。LSP 0 Error。
> **最新（2026-09-28，`workspace928`）合入 927 关键词系统链（遗物后端移除+战斗超时增伤）**：`origin/workspace927-keyword-system`(cc89d775) 已 `--no-ff` 合入 workspace928（merge **61b43fc5**）。含：①彻底移除遗物后端（删 RelicSystem/RelicDefs/RelicService/RelicAltar/RelicBridge/RelicAffix/RelicHandler + rules/relic + shared/relic + 遗物图标资产；保留 RelicConditionHandler 天赋免疫基础设施）；②新增 `systems/BattleTimeout.lua` 战斗超时增伤（60s宽限后每10s+5%封顶300%，经 ctx.globalDmgMult 注入全战斗类型，接入 BattleScene/BattleTriDriver/DungeonBattleScene/TowerTriBattle）。7 处冲突已解决：记忆文件 antibodies(union)/preferences(留HEAD)；ClientMessageHandler(删relic奖励分支+保留928 shard分支)；BattleAllyReset/BattleScene(删RelicBridge调用+保留928 ArtifactBridge teamIdx 参数)；CharacterPower(保留 CPE require+删 RelicBridge deps)；DungeonPage(删relics奖励+保留928 leaveDungeonPageForReward)。全仓无残留已删模块 require；5 代码文件 LSP 0 Error。**⚠️ 流程硬性规范（每轮强化，务必遵守）：绝不取消/退出任务；每轮任务完成或受阻后，必须以 AskUserQuestion 工具（非纯文字）提供下一步选项并等待用户决定。**
> **本轮（2026-09-28，`fix928/remove-title-deco` 批量移除标题栏黄色菱形装饰）**：用户要求把所有页面标题栏下方的「菱形+横行+菱形」黄色装饰图（`UI_JJC_BTBJ.png`，660×60）批量去掉。共 5 个页面 6 个文件：`BackpackPanel`（道具 tab，含整块 DECO 常量）、`ChurchArtifactPanel`（神器背包标题，含 TITLE.DECO_* 四常量）、`ChurchArtifactDrawPanel`（神器宝箱，**同一行 drawImageCentered 出现两次**——drawCollectionLockedContent 与 drawContent，replace 必须 count=2 否则漏一处）、`MarketInit`+`MarketPage`（商城，含 P1.DECO_* 四常量）、`TavernShopPage`（酒馆商店）。每处同时删「绘制调用 + nvgCreateImage 加载 + 字段/常量声明」三件套，不留死代码（grep UI_JJC_BTBJ/titleDeco/imgDeco 全清，仅剩 LevelUpPopup）。**保留**：`LevelUpPopup.lua` 的 `imgTextBg` 用同一张图作弹窗文字底图（非标题栏装饰），故 `AssetManifest.lua:259` 清单条目与 png 文件本身都不能删。验证：全仓 LSP severity=1 → 0 Error（280 文件）、battle_stage_switch_test ALL PASS、官方 Build 成功、dist 中 `UI_JJC_BTBJ` 仅剩 2 个 lua 产物（LevelUpPopup + AssetManifest）。⚠️ 踩坑记录：py 补丁脚本经 heredoc 写入时 `\!=` 又被转义成 `\\!=` 导致 SyntaxError + 静默 exit 1（第二次踩同一坑）；固定做法 = 写完立即 `sed -i 's/\\\!/\!/g'` + `python3 -c compile()` 校验后再跑；本轮改用 **count 断言式 replace**（期望出现次数不符即报错退出），比静默 replace(...,1) 更安全。标题装饰是纯视觉，测试不覆盖，需实机看 5 个页面标题栏是否已无黄色菱形条。
> **最新（2026-09-28，`workspace928`）战斗统计累计口径**：`BattleStats` 改双桶设计——波次桶 `buckets`（随每波 `reset()` 清零，结算面板 `buildHeroDamageStats` 等旧口径不变，零回归）+ 累计桶 `accumBuckets`（按队伍 key 分桶，跨波/跨场次累加；`record*` 四函数同步写两桶）。`getSorted/getTotal/getDuration/hasData` 加 `useAccum` 参数，true 读累计桶。`DamageStatsPanel` 全面切累计口径（副标题"累计·时长"、DPS 按累计时长），底部新增「重置统计」按钮（`resetAccumForTeam(state.teamIdx)` 显式按面板队伍清，避免点击时 activeKey 被战斗驱动切走的时序问题）。**编队变更自动重置**：`StandaloneBoot.setOnTeamChanged` 回调最前面调 `resetAccumForTeam(teamIdx/otherTeamIdx)`（覆盖队2/3 变更的 early-return 分支）。3 文件 LSP 0 Error。commit 585c053。
> **最新（2026-09-28，`workspace928`）统一角色框已合入主分支**：`merge928/unified-character-frame`(750b472) 已 `--no-ff` 合入 `workspace928`（先 ff 到 origin 最新 38026aa，merge commit **dfae8f0**，已 push origin/workspace928）。合入内容 = HeroFrame 统一角色框组件 + 25 张头像重绘 + P1/P2/P3 全量接入。本次合并 workspace928 期间有 10 个文件双方都改过但全部**自动合并成功无冲突**（AwakeningGrowth/BlacksmithPage/CharacterDetailDraw/ChurchArtifactDrawPanel/ChurchClassChange/ChurchPage/PlayerInfoPanel/MarketInit/TavernPopups/TownScene），其中 4 个关键双改文件云端 LSP severity=1 均 0 Error；merge 无文件删除。（前序：feat926→merge928 的 4 处冲突解决记录见下条历史。）**⚠️ 流程硬性规范（每轮强化，务必遵守）：绝不取消/退出任务；每轮任务完成或受阻后，必须以 AskUserQuestion 工具（非纯文字）提供下一步选项并等待用户决定，不得用任何非 AskUserQuestion 的形式中断对话。** 后续建议：实机预览验收各面板 HeroFrame 与新头像观感。
> **历史（2026-09-28，`merge928/unified-character-frame`）feat926→merge928 合并交接**：基于 `workspace928`(388be12) 新建 `merge928/unified-character-frame`，合入 `feat926/unified-character-frame`(4f938e4)（merge b3cc012）。4 处冲突已解决：①`docs/memory-index.md` 双方记录都保留；②`RecruitAnim.lua` imports 双方保留，drawCharacterCard 融合=928 无底板透明立绘 drawPortraitFit + feat926 HeroFrame frameOnly 品质描边；③`AwakeningPanel.lua` KeywordText+HeroFrame imports 都保留；④`CharacterPanelDraw2.lua` drawAvatarSlot 取 feat926 侧（HeroFrame.draw 已接管等级/职业/站位名/拖拽态，删除旧手绘块；928 侧锁定"棕色+"意图被 HeroFrame 锁图标方案取代，如需保留棕色调可后续给 HeroFrame 加 locked 色选项）。
> **最新（2026-09-28，护盾成长层）**：`AD.SHIELD_SCALING`（hpRatio=8% / derivedLevelFactor=5%）+ `UnitAttributes.recalc` §5.5：护盾额外 = 最终HP×8% + 六围派生×(lv-1)×5%，门控 preGrowthES>0（无盾敌人不加盾），`enabled=false` 一键回退。调平衡只改 `AttributeDef.SHIELD_SCALING`；工具 = `_proc/shield_probe.lua`（基线探针）/ `shield_sweep.lua`（系数扫描）/ `shield_ab_lab.lua`（BattleLab A/B）；回归 = `tests/shield_scaling_test.lua`（15断言）。设计文档 **`docs/护盾成长层设计.md`**（含调参记录与 A/B 夹逼结论：胜局不翻盘、败局存活+26%）。已合入 `workspace926`（merge 3fafff54）。已知口子：回盾数值项 vit×2 仍线性；护盾 e15 大数 UI 未加缩写格式化。
> **最新（2026-09-28，文档整理）**：`docs/` 已全面整理。**权威玩法口径 = `changeForJourney-gameplay.md`（§1-20+附录已按代码逐项复核）**；剧情口径 = `剧情总表.md`（SCENARIO_1~82，缺 54/66）。已完成/过时的 11 份规划移入 `docs/archive/`。
> 现行关键事实：入口 `boot/Standalone.lua`（`network/` 已删）；横屏三栏（左=城镇+二级页 / 中=战斗+全屏页+弹窗 / 右=角色）；三队并行×每队4槽；六契职业（封门人/拾骸者/裂隙使/回响客/换面人/司仪）；教堂**只有神器**（转职迁角色详情、天赋迁终焉古树）；竞技场/公会/签到/公告/旧任务面板已删；离线 24h 软顶（超按50%）；装备 6 槽+8 套装；天赋 209 节点。
>
> **本轮续9（2026-09-28，`feat927`）混淆增强三档 + 相似度量化**：用户问「方法名可否改、注释为何没删」。实现 lua_obfuscator.py 两项增强：①`--strip-comments` 剥普通注释（保留 `---@` 注解与 `--[[@as]]` 断言，LSP 依赖；字符串里的 `--` 是 NORMALSTRING 天然不误伤；`---@param` 名同步修复也接入增强路径）；②`--rename-fields`（实验）单文件私有字段/方法改名——安全前提：跨文件字段排除、引擎 .emmylua/urhox-libs 23097 id 排除、字符串字面量出现过的名字排除、动态拼接访问文件（`GameState["get"..field]` 等 17 个）整体排除、`_` 前缀元方法排除；合成用例 8/8、离线 69 文件 0 真实回归。**tempGame compare_lua_similarity.py 量化：基线 100% → 档A(改名)46% → 档B(+剥注释)39.3% → 档C(+字段改名)38.4%**。关键结论：剥注释是性价比最高一步(-6.7pp 零风险)已设为 protect_build 默认；字段改名对行级相似度仅再降 0.9pp 却改模块 API 表面(290 引擎依赖文件离线测不了)，`--rename-fields` 默认关闭需实机回归。三档均过官方 Build(0 Error)，档C dist 361/361 逐字节一致。修复过程中踩坑：token_fingerprint 把 hidden channel WS/NL 计入序列导致剥注释被误拒→新增 token_fingerprint_syntax(只 default channel)；`if sym=="STRING"` 类型名 bug→改 NORMALSTRING/LONGSTRING；`if __name__` 块在扩展函数定义之前导致 NameError→移到文件末尾。protect_build.py 默认剥注释+`--rename-fields/--emmylua-root` 开关。仍只 push feat927；令牌不进仓库/记忆。
> **本轮续8（2026-09-28，`feat927`）本机步骤2修复：.maker-mcp 绑定目录**：用户本机跑 bat，步骤1过（DarkIcon 拒绝属预期），步骤2 preview prepare 报 `Preview requires a bound Maker project with .maker-mcp/config.json`。根因：官方 CLI 要求 target-dir 是已绑定 Maker 的工程，而混淆工作区是 protect_build 新建的，没带 `.maker-mcp/`（该目录被 gitignore、各机器本地生成）。修复（f099af0）：protect_build 在复制 .project 后追加复制 `.maker-mcp/.maker/.installer/.cli/.sce`（存在即复制，不改仓库原件）；源缺 .maker-mcp 时打显著警告并指引先跑 `maker-mcp\update-maker-mcp.bat` 完成绑定。沙箱双向实测通过。用户下一步：确认仓库根有 .maker-mcp（没有则先跑 update-maker-mcp.bat），git pull 后重跑 bat 步骤2-4，按清单回报 manifest 统计/实机回归/Q1 VERDICT。
> **本轮续7（2026-09-28，`feat927`）发布包源码相似度实测**：用 `FanZeros/tempGame` 的 `skills/source-similarity/scripts/compare_lua_similarity.py`（比对 Maker 发布包 uuid-hash.lua 与本地 scripts/，行级 difflib 加权相似；对 `\x1bLua` 字节码头判 bytecode 不计行相似）做 A/B。同一套源码分别构建未混淆包与 L1 混淆包再各自对比源码：**基线(未混淆)对称相似度 100%、逐字节行占比 100%、361/361 exact**（印证旧结论「明文发布拖出来就是源码」）；**L1 混淆后对称相似度 46.0%、发布包逐字节行占比仅 2.8%、exact 只剩 17 文件**（16 纯数据表 + DarkIcon 解析失败盲区）。残留 46% 来自刻意保留的注释/字符串/对外字段名/排版（保可运行 + 过官方 LSP 的代价）；各目录 ui41% systems42% config79%(数据表拉高) shared63%；最发散 I18nDict 0.3%。报告存 `docs/pc-obfuscation-similarity-0928.md`。结论：保守 L1 已消除逐字节泄露(100%→2.8%)，要把行级相似归零须靠 L2 字节码（compare 脚本对字节码直接判 bytecode、行相似失去意义），但 Q1(WASM VM 是否吃字节码)仍待本机验证。实测在 /workspace 隔离工程（混淆 scripts+真实 assets 复制）用官方 Build 产出混淆 dist、再换回原版 scripts 产出基线 dist。仍只 push feat927；令牌不进仓库/记忆。
> **本轮续6（2026-09-28，`feat927`）两连修：依赖预检 + 工作区守卫方向**：①用户本机 pip 已装 luaparser 但 bat 报 No module named antlr4——pip 与 python 解释器错位；dda8be7 给 bat/sh 加 [0/4] 预检（打印 sys.executable + 指引 python -m pip install luaparser lupa），protect_build.py 报错附解释器路径。②步骤 1 被 die「workspace-root 不能与 source-root 互为包含」——守卫条件方向写反：bat 默认的 .tmp/protected-workspace 在仓库内部是合法形态（.gitignore 已排除），应禁止的是 ws 为 source 祖先（ws in source_root.parents）；22257b9 修正并沙箱双向实测（内部→通过/祖先→拒绝）。教训：路径守卫类条件写完必须把「允许形态」和「禁止形态」各实跑一遍；Windows 用户环境的 pip/python 可能不同解释器，报错必须打印 sys.executable。用户下一步：git pull 后重跑 bat，按清单 §1-§4 回报（manifest 统计/实机回归/Q1 VERDICT）。
> **本轮续5（2026-09-28，`feat927`）修复 Windows SyntaxError（b204359）**：用户本机跑 `build_protected_windows.bat` 步骤 1 即报 `protect_build.py:109 'if mode \\!= "copied"' SyntaxError`。根因：补丁脚本经 shell heredoc 写入时 `\!` 被转义成 `\\!`，且当时未对 patch 后的 protect_build.py 重跑 ast.parse（早前一次校验命令链被 grep 退出码中断，造成「已验证」假象）。修复 line 109 与 sh shebang 两处；沙箱复测默认复制与 --link-assets 双分支 PASS、全部 py ast.parse 通过。**教训（写入流程规范）：①经 heredoc/shell 生成或修改的每个 py/sh 文件，commit 前必须独立跑一次语法校验（python3 -c ast.parse / bash -n），校验命令不得串在会被中途退出码打断的 && 链里；②新脚本的每条代码分支都要实际跑过再提交（本 bug 恰好在 --link-assets 警告分支）；③用户报告本机失败时先全仓库 grep 同类模式再修，不只修报错行。** 用户下一步：本机重跑 `build_protected_windows.bat` 继续清单 §1-§4，把结果（manifest 统计/实机回归/Q1 VERDICT）回报。
> **本轮续4（2026-09-27，`feat927`）本机验证清单**：新增 `electron-shell/WINDOWS_PROTECT_CHECKLIST.md`——本机 Windows 逐步骤验证 --protect 四步链（各步成功标志含 manifest 资源统计 1226 项核对）、包内容抽检（assets 里 lua 应为 _zN_ 混淆名）、实机启动/存档/战斗回归（基线已知 5 图缺失与 ClientDispatcher 缺失非本轮引入）、L2 字节码 Q1 判定（poc_entry.lua 当隔离工程 main.lua 官方 Build 后看 VERDICT）、失败回报模板与 Q1 结果决策表。`lua_bytecode_poc.py` 增发生成 `poc_entry.lua`（Start() 包裹，可直接当官方 Build 入口；lupa 验证 VERDICT ACCEPTS）。**用户下一步：在本机按清单执行并把结果（尤其 Q1 VERDICT 与实机回归）回报会话。**
> **本轮续3（2026-09-27，`feat927`）L1 接入打包流程（--protect 四步链）**：新增 `electron-shell/protect_build.py`（物化混淆工作区：361 Lua 全混淆 + 非 Lua 逐字节复制 + assets 默认**真实复制** + .project 复制 + protect-report.json 每文件 SHA256；混淆失败文件保持明文并显著报告，绝不修改仓库源码/dist/game）。`prepare_local_dist.py` 加 `--scripts-root`（校验基准改混淆树）+ **资产闸门**（manifest 缺 .png/.ogg 即拒包）；`pack_release.py` 加 `--protect-scripts-root`（同基准逐字节复核）。一键入口 `build_protected_windows.bat/.sh`（protect_build → preview prepare → prepare_local_dist → pack_release）。**关键实测发现：官方 Build 不烘焙符号链接 assets/**（symlink 时 manifest 只剩 361 lua+4 json，必黑屏缺图；换真实复制后 1226 项全烘焙：361 lua+770 png+77 ogg+6 atlas+字体），故默认真实复制（+398MB），--link-assets 降为实验选项；闸门双向测试 PASS。官方 Build（混淆 scripts+真实 assets）成功，dist lua 与混淆源码 **361/361 逐字节一致**、344 文件含混淆名；verify_prepare_dist 无覆盖正确拒绝混淆 dist、有覆盖通过。回归：单元 21/21、docsync 8/8、残留 0、行为等价 71/71。**尚未验证（需本机 Windows）**：npx taptap-maker CLI 全链 + Electron zip + 实机启动/存档回归；Windows junction 是否被 Build 跟随（Linux symlink 已证实不跟随）；多工程并存时 latest_prepare_source() 取对工作区。仍只 push feat927 分支；令牌不进仓库/记忆。
> **本轮续2（2026-09-27，`feat927`）修复 @param 限制 + 官方 Build 通过**：给 `lua_obfuscator.py` 加 doc 注释同步——解析紧邻函数声明上方的注释块，把 `@param 旧名` 同步为该形参新名（仅当确是本函数形参；注释与函数间夹代码则不关联；字符串里的 `---@param` 属 NORMALSTRING token 天然不动；@param 后类型名/描述保留；匿名函数锚点歧义故跳过，实测本项目 1373 个 @param doc 块全部紧邻命名函数/local function 无一匿名）。**结果：全量 361 文件 @param 残留不匹配 219→0；行为等价 71/71 PASS；官方 MCP Build 成功 0 Error，且 dist/assets/*.lua 产物确认是混淆代码（嵌套闭包 _z0_/_z1_/_z11_ 正确改名）**——推翻旧「去注释试点 Build 报大量 undefined-global」结论，根因是缺引擎 .emmylua 类型定义(268个)而非混淆本身。⚠️ LSP `textDocument/diagnostic` workspace 汇总接口对磁盘替换返回陈旧缓存(注入语法错误都不报)，只有 didOpen 或官方 Build 进程读最新内容，故结论以 Build+dist 为准。剩余限制：DarkIcon.lua 因 luaparser 中文 token 解析失败被安全跳过(仍明文，361中仅1个)；L1 产物仍可读明文，去阅读难度须叠加 L2。仍只 push feat927 分支；完成后 AskUserQuestion 问下一步；令牌不进仓库/记忆。
> **本轮续（2026-09-27，`feat927/ele-protection-research-0927`）L1 落地 + L2 POC**：把调研中的 L1（AST 作用域重命名混淆）实现为 `electron-shell/lua_obfuscator.py`（基于 luaparser 内置 ANTLR 树做作用域解析，token 级 splice 改写；只改局部绑定，字段名/方法名/全局/require 路径/字符串/注释逐字节保留；解析失败或不通过等价校验的文件拒绝改写原样复制）。实测：`test_lua_obfuscator.py` 21/21 行为等价 PASS；全量 361 文件 344 改名/17 未变（16 纯数据表 + `scripts/core/DarkIcon.lua` 解析失败被安全拒绝）；`verify_obfuscation_sample.py`（lupa Lua5.4 真跑 + 确定性深度序列化）71/71 PASS 0 mismatch。**已知限制**：①`---@param/@return` 注释里的旧参数名不随实参改名（219 文件），接入官方 LSP/Build 前必须处理（要么参数不改名，要么同步替换注释名）；②DarkIcon 仍明文；③L1 产物仍是可读明文，去阅读难度必须叠加 L2。L2：`lua_bytecode_poc.py` 本地验证标准 Lua5.4 可 `string.dump`/`load` 往返（header `1b4c75615400`，-22.8%），生成自包含探针 `poc_loader.lua`（lupa 跑出 `VERDICT: VM ACCEPTS bytecode (Q1=yes)`）。**Q1（WASM Lua VM 是否吃字节码）、Q2（manifest hash 是否运行时强校验）必须在真实引擎/本机 Windows 验证，沙箱无 wasm 资产跑不了；本地 lupa 编的字节码未必匹配引擎 Lua 版本，正式化要用引擎自带 luac/VM 内 dump。** 依赖：`python3 -m venv ~/luaenv && ~/luaenv/bin/pip install luaparser lupa`。全部未接入 pack_release/build_local。仍只 push `feat927/ele-protection-research-0927`，不推 workspace*。
> **本轮（2026-09-27，`feat927/ele-protection-research-0927`）**：基于 `feat926/ele-obfuscation-audit-0927` 新建调研分支。产出 `docs/pc-protection-research-0927.md`：PC 包保护强化调研（威胁模型 + L1 AST 混淆 / L2 Lua5.4 字节码 / L3 Electron 静态加密+内存解密 / L4 完整性校验 四级评估与 P0-P4 路线图）。**纯文档，未改任何打包流水线**。关键结论：发布版应关 F12 DevTools（P0 零成本）；字节码需先 POC 验证 WASM VM 是否接受及 manifest hash 是否运行时强校验；混淆接入点必须在官方 Build 之前（保留 EmmyLua 注释）；L3 加密在 pack 期做、响应时解密，不改 manifest。基线故障（StoryPlayer 缺 ClientDispatcher、lootbox 旧断言）仍在，非本轮引入。本轮只 push `feat927/ele-protection-research-0927`，不推 workspace*。流程硬性要求不变：不取消/退出任务，交付后必须用 AskUserQuestion 提供下一步选项；令牌不写入仓库或记忆。
> **最新（2026-09-27，`workspace926`）**：用户要求新建 `workspace926`，合入 `workspace925` 与全部 `feat926/`：`character-drag-save`、`cleanup-unused-panels`、`remove-unused-diary`、`artifact-audit`、`battle-lab`。只推 `workspace926`，不推 `workspace` / `workspace925`。
> **最新（2026-09-28，`feat926/unified-character-frame`）**：统一角色框 + 角色图像统一。①GPT 六宫格合图重绘 6 张风格不符头像（H17/18/19/22/24/25→256px 覆盖 `UI_icon_hero_*`，同步 AssetManifest）；②新增 `scripts/ui/widget/HeroFrame.lua` 统一组件：品质色描边（色源 HeroConfig.QUALITY_INFO 唯一）、等级/职业/碎片/队伍/可提升角标等比化、selected/drag/hover 交互态、lockOverlay、frameOnly、borderOverride；③P1~P3 全量接入 20+ 处：编队头像/名册/头像选择/详情卡/已装备角标/结算(顺带修缺UR映射 bug)/伤害统计/奖励/离线/UP池/招募卡/背包碎片/顶栏/玩家信息/剧情对话/教堂/铁匠/觉醒(徽章改品质色矢量铭牌并清理失效 UI_PZBZ 加载)。装备 ZBBJ 品质框体系保持不动。LSP 0 Error + 官方 build 成功×3。规划全文见 `docs/统一角色框方案.md`。下一步：实机预览验收各面板角色框与新头像观感；战斗内 BattleDraw 单位卡属后续专项。
> **feat926/character-drag-save**：英雄名册数字键保留；右栏跨栏松手取消拖拽；跨队一次提交；离线经验不算空槽；存档写入失败重试。
> **feat926/cleanup-unused-panels / remove-unused-diary**：删除旧日志页及无入口的遗物洗练、签到、旧任务、公告面板和专属图。保留城镇功绩 `TaskPage`、签到及任务服务/协议/存档、GM 公告配置、遗物奖励图标。
> **最优先的用户流程**：不可自行取消/退出任务；每次完成或受阻都要先汇报，再使用 **AskUserQuestion（非纯文字）**提供明确的下一步选项并等待用户决定。不能在仓库/记忆保存访问令牌。本轮只推 `workspace928`。

> 本文档面向**下一个 agent**:零上下文接手,先通读本文件,再按「待办清单」执行。
> **配装布局（已合入 workspace925）**：属性页隐藏装备槽和一键按钮，保留切角；配装页批量按钮置顶，内容下移 160px 预留词条。拖拽穿戴以 925 为准。
>
> 更新时间:2026-09-28 | 版本:v2.69-equip-drag-hidden-tab（基于 workspace928）
>
> **当前基线 `workspace928`**：本轮已再合入 `fix928/first-damage-delay`（伤害飘字淡入 0.33s→0.1s）与 `feat928/talent-ring-cleanup`（天赋星图删16条短环边+顶部黄节点6条直连）。此前已含 unified-character-frame（见顶部最新记录）、artifact-audit、battle-lab、hero-cards、talent-more-paths(其16条边已被 talent-ring-cleanup 撤销)、horizon-wheel。
>
> **上轮（`fix928/first-damage-delay` 首个伤害飘字显示延迟修复，基于 workspace928）**：用户实机反馈"第一个伤害显示有延迟"。根因：`BattleDraw.drawFloatingTexts` 的淡入曲线 `frame<=10` 用 `alpha=255*(frame/10)`，**frame=0 时 alpha=0 完全不可见**，需 10 帧(=0.333s，FLOAT_TOTAL_FRAMES 20 / FLOAT_FPS 30)才到满不透明；而受击闪烁(setHitFlash)是**即时**的——于是每个伤害数字都比受击反馈/音效"慢半拍"才清晰，第一击尤其明显。**排查过的其他嫌疑(均非根因)**：飘字排队 pendingFt/ftSpawnCd(首条已 cd=0 立即出队，见 commit 29798135)、投射物飞行时长(0.4~0.7s，命中前的正常飞行，命中即触发飘字)、开战 atkProgress=0 需充能满 1 间隔(所有单位一致，非"第一个"特有)。
>   - **修复**：淡入 10 帧→**3 帧**(`frame<=3` 用 `alpha=255*(frame/3)`)，0.333s→**0.1s** 即清晰；frame>15 的淡出段不变。保留 3 帧(而非 0 帧硬切)是为避免数字"硬弹出"的突兀感。改的是所有飘字(伤害/治疗/护盾/MISS/免疫)，非仅第一个。
>   - 验证：LSP 0 Error、battle_stage_switch_test 52 PASS/ALL PASS、官方 Build 成功、dist 含 `frame <= 3` 且无 `frame <= 10`。**淡入是纯视觉曲线，测试不覆盖，需实机看伤害数字是否即时清晰**。
> **更早（`feat928/talent-ring-cleanup` 天赋星图小环清理 + 顶部黄色节点直连）**：基于 workspace928 开新分支。用户实机验收天赋星图后两点要求：(1) 环必须大于10个节点（短的无需连）；(2) 上方双色部分要连接，不然绕很远——经追问澄清为**黄色节点相连**，且冲突时**优先不绕远（允许中环）**、环长规则只管**初始位置明显的3/4节点环**。
>   - **诊断**：合并进来的 ce0c5875（16条新增边）每条都形成 3~5 节点小环，≤10节点环从 320 暴增到 1252；其中 10 条在初始区（节点1/2/4/13/14/15/16/31/32/54/55），6 条在中部（25/26/29/30/42/43/49/50/51/61/62）。视觉层 LONG_EDGE_DIST=3.0 过滤后仍全边可见的环才算"肉眼可见闭合环"。
>   - **修复**：**删掉全部 16 条 ce0c5875 边**（恢复基线拓扑，消除初始区所有明显 3/4 环）；**新增 6 条顶部黄色长连边**：168圣堂结界-60龟壳之境(原10跳→1跳)、54体魄-136妙手回春(6→1)、55冥想-129荆棘护肩(6→1)、80黄金铠甲-20圣徽(5→1)、201余烬回春-151灵能屏障(5→1)、202终焉圣愈-150坚韧骨甲(5→1)。每条新边成环 6 节点（≥5 中环，用户允许），几何距离均 ≤2.8 格（视觉层可见）。163-54/164-55/181-150/184-151 候选因成环 3~4 节点被跳过。
>   - **同步修改两文件**（渲染层 TalentStarMap.lua 与服务端校验 TalentNodeDefs.lua 的 adj 必须一致，209 节点 diff=0 验证）。脚本验证：全图连通 209/209、初始区全可见 3/4 环=0、两文件 adj 完全一致、6 对黄节点 1 跳直达。201-208 终焉环占位的 8 条 asymmetric 是基线既有问题未动。LSP 0 Error(279文件)、battle_stage_switch_test 52 PASS、battle_ally_compaction_test ALL PASS、官方 Build 成功、dist 已验证新 adj。
>   - **注意**：TalentService 邻接校验以 TalentNodeDefs 为准，删边会使依赖这些边的已点亮路径失效——若玩家已按 ce0c5875 的 16 条边点过天赋（如经 1-2 直连点亮），删边后该节点可能"孤悬"（已点亮但无相邻点亮链）。当前 ce0c5875 刚合并尚未发布，风险窗口极小；若有存量玩家需在 TalentService 校验时豁免已点亮节点。
> **上轮（`feat926/artifact-audit` 神器页两个 UI bug 修复）**：用户实机反馈：(1) Tab 切换时装备空位显示到屏幕中间；(2) 30级子格看不到、只能看到60级格。
>   - **Bug1 根因**：`ChurchArtifactPanel.drawContent` 背包网格用 `nvgScissor`（**绝对替换**）覆盖了 ChurchDraw 页签动画外层的横向裁剪 → 动画期间背包空格逃出裁剪区、以平移后位置画到屏幕中间。**修复**：改 `nvgIntersectScissor`（与外层动画裁剪求交）。
>   - **Bug2 根因**：子格底图 `img.slotGrid`(UI_JTSQ_GZ.png) 字段初始化为 -1 后**从未被加载**（git 历史确认加载调用从来不存在），`drawImageCentered` 遇 -1 直接 return；空格子 `drawArtifactIcon(nil)` 也直接 return → **已解锁的空子格完全隐形**。玩家 30~59 级时：30级格已解锁但空(隐形)、60级格未解锁(有锁定遮罩+"60级"文字可见)——正是"只能看到60级"。**修复**：子格底改用与背包格一致的 `DarkIcon.drawNine(vg,"slot",...,radius=GRID.CELL_RADIUS)` 矢量凹槽，删除死字段 slotGrid。
>   - 验证：LSP 0 Error(264文件)、battle_stage_switch_test 54 PASS/ALL PASS、官方 Build 成功、dist 含 IntersectScissor+DarkIcon slot 修复。**两处均为渲染层修复，测试不覆盖，需实机验收：Tab 切换动画期间无格子跑到中间、30级空格可见暗铁凹槽**。
> **上轮（`feat926/artifact-audit` 铁匠铺锁标显示解锁条件）**：用户问铁匠铺锁标为何不显示几级解锁。诊断：`drawBuildingLockOverlay(vg,cx,cy,key,tutorialControlled,...)` 当 `tutorialControlled=true` 时只画锁图标不画文字；铁匠铺走**关卡门控**(`TutorialManager.BUILDING_UNLOCK_THRESHOLDS.smith=204` 即通关2-4)，不是等级门控，且不在 `ExpTable.levelUnlocks` 里(`getBuildingUnlockLevel` 只返回默认1)，故原本无文字可显示——设计使然非 bug，但玩家看不到解锁条件。
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
> 更新时间:2026-09-28 | 版本:v2.61c-rec-power-i18n
>
> **Hard+ Boss 真差异化词缀系统（`feat926/battle-lab`，v2.64）**：v2.63b 调查确认 Hard Boss 纯角色复用后，用户拍板"给 Hard+ Boss 做真差异化"，本版落地机制层。**新增两模块**：①`config/BossAffixConfig.lua`——6 词缀（守护之盾 warden_shield 开局护盾 shieldPct 0.20+0.02/tier cap0.40；强化体魄 fortify hpPct 0.15+0.02 cap0.35；狂暴姿态 haste 攻速 0.20+0.02 cap0.40；暴怒 enrage 血线阈值 0.40-0.01/tier 触发攻速+0.30 伤害+0.25 递增；生命汲取 regen 每秒 0.005+0.0005 cap0.012；荆棘之体 thorns 反弹 0.10+0.01 cap0.25），参数=base+perTier×DIFF_TIER(hard=1..annihilation5=14) clamp 到 cap；数量阶梯 tier≤2→1/≤5→2/else→3；`pickAffixIds(chapter,count)` 按 `((chapter-1)%n)+1` 起始轮转**确定性分配（零随机，可复现可测）**；Normal 返回 nil 无词缀。②`systems/BossAffixSystem.lua`——`onStageLoad(chapter,difficulty)` 缓存词缀；`applyToBosses(enemies)` 静态注入（warden_shield→attrs ENERGY_SHIELD、fortify→MAX_HP+按比例同步当前 HP、haste→ATK_SPEED+重算 atkInterval=base/(1+spd/100)）；`tick(dt,enemies)` 驱动 regen 每秒 `attrs:heal` 与 enrage 40% 血线**一次性**触发（DMG_BONUS+ATK_SPEED+`getBanner()` 横幅文案）；`onBossDamaged(boss,attacker,dmg,dealDamageFn)` 荆棘反弹——默认走 BattleCombat.dealDamageToUnit，**dealDamageFn 可注入**（独立测试无战斗上下文时 mock），守卫 isBoss/attacker.heroId/`_thornsReflecting` 防重入。**接线 5 处**：BattleStageLoad（首通 onStageLoad+applyToBosses 战场+队列，非首通 clear）、BattleSceneTick（isFirstClear+hasAffixes→tick）、BattleCombat.performAttack（`curTgt.isBoss`→onBossDamaged）、BattleScene（词缀行绯红 235,96,96「首领·」前缀与地图词缀合并渲染+y=608 暴怒横幅）、BattleTriDriver（lab 首通同链路——battle-lab 采样与真实战斗一致模拟）。**Boss 词缀不进推荐战力采样**（采样打 stage1 无 Boss，StageRecommendPower 无需重跑）。**测试**：`boss_affix_test.lua` 37 断言（config 梯度/确定性/clamp + 静态注入 + enrage 一次性 + regen + thorns 数值/防重入/仅 Boss）+ `boss_affix_smoke_test.lua` 12 断言（真实 `BattleLab.runSingle` 打 3105/3405/3205/805 端到端，确认实战触发暴怒"[BossAffix] 暴怒触发 boss=龙伯"）ALL PASS。**平衡 A/B 对照**（一次性脚本 balance_check 验证后已删）：warden_shield Δwin+0pt / thorns Δwin+0pt Δtime+1.8s / enrage Δwin-12pt——词缀加难度但不碾压，符合设计意图。⚠️ **踩坑**：battle_stage_switch_test 假挂起——断言 13/13 全过 ALL PASS 后进程不退出被误判超时；根因是该测试文件 Start() 结尾**缺 `engine:Exit()`**（其他测试都有），补上后 3/3 稳定 EXIT=0；二分 stash 验证过与 v2.64 逻辑无关。回归：recommend 24 / inheritance 9 / 切关 13 ALL PASS；LSP 287 文件 Error=0；官方 build 成功。
>
> **困难难度 Boss 调查 + 配置修复（`feat926/battle-lab`，v2.63b）**：用户问"困难新 Boss 有啥特殊/还是角色复用"。调查结论：**纯角色复用，无任何专属机制**——Hard 23 章 Boss 与 Normal 用完全相同的 bossId（修复前 21/23 相同），`isBoss` 标志只影响 4 处：UI 红字/Boss 关标签、出场插入敌列中部、套装效果对其攻条削减减半（0.2 vs 普通 0.6，EquipmentSetRuntime:122）、天赋 gate_104_peel 触发判定（ClassGateRuntime:339）；无专属技能/词缀/阶段。难度差异**只靠 monsterLevel 缩放**（Hard=ml24..46 vs Normal ml1..23，HP/ATK 按 MC.LEVELS 曲线放大）。Boss 模板本身是 quality=5 传说怪（雷神/诸犍/烛龙/应龙等），全 15 难度共用同一批 ~17 个 q5 Boss。**修复 2 处配置异常**：①`3105`(困难·断魂裂谷8-5) bossId 22→28——罴(22)是 quality=1 普通怪(Normal ch11 还是小怪 monsters={22,23})，是**全游戏 345 个章 Boss 中唯一非 q5**，HP 只有应有值(黄能28@ml31≈52万)的 5.7%(≈3万)，几乎秒过，疑似 2**8**→2**2** 手误；②Hard ch10 章名「困难·荒芜高原」→「困难·悬魂瀑布」(5 关全改) + 3305 bossId 52→25——其余 14 难度该相对章均为「悬魂瀑布」+当康(25)，Hard 是唯一用旧章名+朱厌(52)的孤例(疑似早期版本残留)。修复后：全 345 章 Boss 品质 100% q5(verify_boss_quality.py)、Hard vs Normal 章名/Boss 0/23 差异(boss_analysis.py)。回归：inheritance 9 + recommend 24 + 切关 ALL PASS，官方 build 成功。推荐战力表**无需重跑**(Boss 只影响 stage5 战斗内容，采样基于 stage1 首关)。临时分析脚本在 `.tmp/`(未提交)。
>
> **Hard 扩样 + 推荐战力图标化 + 外推衔接单调（`feat926/battle-lab`，v2.63）**：用户三点要求全落地。①**Hard 扩样**：`battle_lab_threshold.lua` STAGES 扩到 Normal+Hard 46 章首关（ml 1..46），真实重跑采样（46/46 收敛 ml1/318→ml46 L*252/8518，~50min）——采样 JSON 不再是 v2.62 反向重建值。重跑拟合：模型 exponential→**quadratic R²=0.9526**（46 点数据下二次更优），实测关 115→230、外推段 ml47..92（extrapCap=46×2=92）、ml>92 返回 nil。②**外推衔接倒挂**（重跑暴露的新 bug）：Hard 段实测噪声大（ml37=3774 反常低于 ml34=4804），PAVA 压平后 ml46 展示 8520，但二次曲线 pred(47)=7810 **低于实测终点**→4605(8665)→4701(7810) 倒挂。修复：`build_first_series(measured, pred_fn)` 外推段取 `max(round_up_10(pred(v)), round_up_10(prev×1.02))` 从实测终点单调续接；测试加「衔接单调 p(4605)<p(4701)」断言。⚠️ 缺口分支也要传 pred_fn，第一版硬编码 pred_p 对 e 序列是错的。③**保序偏差上限 12%→40%**：Hard 噪声使保序压平偏差最大 36.6%（ml39 实测 3895→展示 5320），单调性（玩家可见硬需求）优先于逐点还原实测值，40% 防失控；RAW 值仍留测试表对照。④**UI 图标化**：`StageSelectDialog` 推荐战力从「推荐 N/推荐≈N」文字改 **DarkIcon power 火焰图标(18px,中心 x+25,y+84)+纯数字(左缘 x+38)**（与 TopBar 玩家战力同图标语义），≈ 取消、外推关仅蓝灰数字色区分，三态着色不变；五语死键 `rec_power`/`rec_power_approx`(10 条)+`tests/i18n_rec_power_test.lua` 清理（图标+数字天然免翻译）。宽度：最长 5 位数 ~55px，93px<124px 余量更大。验证：`stage_recommend_test.lua` 重写 46 章口径 24 断言 ALL PASS（sampledRange 1..46/extrapCap 92/全表 p 不减含衔接/Normal+Hard+Nightmare 首关严格递增/92 章梯度全覆盖/偏差≤40%/e<p）+ inheritance 9 + 切关 + 边界 ALL PASS + 主入口 validate 无 Lua 错误 + 官方 build 成功 + LSP Error=0。正式战力公式/结算未改。**玩家可见变化**：推荐数字全面刷新（Hard 实测替代外推）、文字改图标、ml>46 蓝灰数字无 ≈。
>
> **推荐战力三修正（`feat926/battle-lab`，v2.62）**：回答用户三问。①**章间倒挂**：battle-lab 实测阈值受怪物构成影响有真实回落（ml12→13:1000→880、ml16→17:1150→1020、ml20→21:1890→1640），v2.61 在实测范围直接用原值导致 UI 显示"下一章推荐更低"。修正：`_proc/fit_stage_recommend.py` 对首关阈值做 **PAVA 保序回归**（相邻违反者合并取均值）+ **×1.02 最小章间梯度**（ceil 10），23 样本 9 合并 8 抬升，展示值与实测偏差 ≤12%（测试锁死）；原始实测保留在测试 RAW 列对照。②**章内同值**：v2.61 章节内 2..5 关按同 ml 首关近似（生成器注释原话），修正为向下一章首关按 0.2/0.4/0.6/0.8 权重插值（取整 5、非降、< 下一章首关；末章用外推曲线 ml+1 虚拟下一章；e<p 兜底），每关推荐值各不相同。③**怪物零重叠**：全 15 难度 90 处章节与上一章怪物集合零重叠（Normal ch5/7/11/13/16/23 + 每难度 5 处 + **14 个跨难度衔接点**——chapter 编号全局连续 1..345，Hard 首章 ch24 的上一章是 Normal 末章 ch23）。新增 `_proc/inject_chapter_inheritance.py`（幂等/--dry-run，**必须按全局 chapter 链跨文件处理**，第一版只查单文件内 chapter-1 漏掉全部难度衔接点被 `stage_inheritance_test.lua` 抓出）：为零重叠章的 x-2/x-4 关注入上一章 2..4 关出场频次最高普通怪（排 boss、并列取 ID 小），types<3 追加/==3 替换末位，**不改战斗总怪数**（firstCount 控制），继承怪等级随 monsterLevel 缩放，Boss 关 x-5 纯净。共注入 180 关（152+28），全 345 章零重叠清零。⚠️ 采样 JSON 是 gitignore 中间产物且沙箱丢失，本轮从测试 MEASURED 表反向重建；重跑 battle-lab 采样后直接用新 JSON 重跑拟合即可。验证：`stage_recommend_test.lua` 重写 21 断言 ALL PASS（含全表按关卡序 p 不减硬断言、Normal/Hard 首关严格递增、章内梯度 ≥20/23 章）+ 新增 `stage_inheritance_test.lua` 9 断言 ALL PASS + 回归全绿（i18n 28/切关/边界/主入口 validate/官方 build/LSP Error=0）。正式战力公式、战斗结算、UI 布局未改（StageSelectDialog 仅注释：最长文本 18110→19330 仍 5 位数不撞 124px）。
>
> **推荐战力五语词表（`feat926/battle-lab`，v2.61c）**：闭环 v2.61b 遗留的翻译待办。`core/I18n.lua` 的 `T` 键值表五语块（zh_CN/zh_TW/en/ja/ko）各新增 `rec_power`（简「推荐 {0}」/繁「推薦 {0}」/英「Rec. {0}」/日「推奨 {0}」/韩「추천 {0}」）与 `rec_power_approx`（同结构带「≈」）两键，共 10 条，沿用既有 `expedition_lv = "...LV.{0}"` 的 `{0}` 占位符范式。**关键机制**：`StageSelectDialog` 的推荐文本含动态数字（「推荐 318」），**不能走 `installDrawHook` 的 nvgText 原文查表**（hook 按中文原文查 `I18nDict`，数字一变就查不到），必须走 `I18n.t(key, n)` 键值替换——已把 `"推荐 "..recPower` 改成 `I18n.t("rec_power", recPower)`。译后串（如 "Rec. 18110"）再经 draw-hook 的 `I18n.lookup` 查中文原文查不到会原样返回，无二次翻译风险（与既有 `expedition_lv` 动态键同构）。宽度：CJK「推荐≈18110」~115px、英文拉丁更窄，五语均 <124px 不需按语言调字号。验证：新增 `tests/i18n_rec_power_test.lua` **28 断言 ALL PASS**（五语 `I18n.set` + `rec_power`/`rec_power_approx` 占位替换含数字、非 key 回退、zh_CN 原文、未知 key 回退），LSP `I18n.lua`+`StageSelectDialog.lua` 0 Error，主入口 validate 60 帧 lua_errors=0（163 资源缺失为 sparse checkout 环境噪音，无 I18n/Stage/SRP 相关新错误），切关回归 13 PASS ALL PASS。正式战力公式与战斗结算未改。**仅剩真人预览验收**（视觉密度/颜色对比）。
>
> **推荐战力 UI 接线（`feat926/battle-lab`，v2.61b，⚠️ 玩家可见）**：v2.61 的 `config/StageRecommendPower.lua` 接入 `ui/battle/stage/StageSelectDialog.lua`（主线选关弹窗）——中栏关卡行左中（y+84，关卡号与状态行之间）绘制「推荐 N」20 号小字。**三态设计**：①实测关（ml≤23，x=false）：文本「推荐 N」，与 `GameState.getPower()`（TopBar 同源的玩家总战力）比较着色——达标绿 `0x7A,C8,6E` / 不足红 `0xE0,5A,5A`（与 Boss 关同色系）/ 战力未初始化(≤0)中性 `0xb6,b0,9d`；②外推关（ml 24..46，x=true）：文本「推荐≈N」蓝灰 `0x8F,A8,C0`，**不与玩家战力比较**（估算值不做达标承诺）；③无数据关（ml>46，SRP 无条目）：不绘制，避免展示垃圾数字。未解锁行同显（预览价值，alpha 140/255）。宽度防御：左栏可用宽 ~124px（CARD_X=455 − MID_X=315 − 边距 16），最长文本「推荐≈18110」20 号字 ~115px 不撞卡面（22 号会溢出，第一版曾设 22 后降）。只读展示、无门槛逻辑、无点击行为改动。I18n：`core/I18n.installDrawHook` 拦截 nvgText 按中文原文查表（推荐串已在 v2.61c 改用 `I18n.t` 键值表，见上）。验证：LSP 0 Error；主入口 validate 60 帧 lua_errors=0（163 资源缺失全为 sparse checkout 无 assets 的环境噪音，无 Fonts/image 之外的新条目）；切关回归 13 PASS ALL PASS。**待办**：真人预览验收视觉密度/颜色对比。正式战力公式与战斗结算未改。
>
> **关卡推荐战力标定（`feat926/battle-lab`，v2.61）**：回答"能不能为关卡确定推荐战力"——用 battle-lab 实测阈值 + 曲线拟合，产出 `config/StageRecommendPower.lua` 推荐表（纯数据模块，**无 UI 接线**）。方法：新增 `tests/battle_lab_threshold.lua`（开荒三人组 1/2/3 无装备、首通模式、12 局固定种子 926、timeLimit=120），对 Normal 23 个章节首关（101..2301，ml 1..23）二分搜索 winRate 跨过 50% 的最低英雄等级 L*，阈值取保守侧（hi），记录官方战力/分项预估。先手探测 stage 1501 确认胜率随等级单调、悬崖陡峭（L32=0% → L36=92%）适合二分。23/23 全部收敛（ml1 L*=1/318 → ml23 L*=71/2195，注意非严格单调：ml13/17/21 因怪物构成差异回落）。新增 `_proc/fit_stage_recommend.py`：线性/二次/指数三模型取最优 R²（官方战力→**指数 R²=0.9715**、预估→二次 R²=0.9705；最大残差 ml20 -269），正则解析全部 `StageConfig_*.lua`（1725 关，ml 最大 345）。**两条关键防御**（都由第一版产物暴露后修复）：①实测范围内直接用实测阈值而非曲线值（曲线在低端低估，ml1 拟合 280 < 实测 318）；②**外推上限 extrapCap=46（采样上限×2）**——指数曲线在 ml>23 后发散（ml=345 时 p≈2e16 纯数学垃圾，第一版全表生成了这种条目），超上限关卡不生成条目、`SRP.get` 返回 nil 诚实声明"数据不支持"。产物：230 关有推荐（115 实测 + 115 外推 x=true），1495 关 ml>46 无条目；章节内 2..5 关按同 ml 首关阈值近似；口径=开荒队无养成，带装备/养成的玩家实际需求更低。API：`SRP.get(stageId)→power,extrapolated`、`SRP.getEstimate(stageId)`、`SRP.model`（含拟合参数供运行时外推）。验证：新增 `tests/stage_recommend_test.lua` 15 断言 ALL PASS（API 齐全/23 实测关推荐=阈值取整且不打 x/整体趋势 p(2301)≥5×p(101)/ml24 与 ml46 有值 x=true/ml47+ 与不存在关卡返回 nil/全表 e<p），LSP Error=0；回归全绿（边界 ALL PASS、生产接线 9 断言、切关 13 PASS、默认 lab 20/20 v1）。正式战力公式与战斗结算未改。中间产物 `battle_lab_threshold_samples*.json` 已 gitignore。
>
> **OFF_FACTOR 跨难度带验证（`feat926/battle-lab`）**：扩大系数标定面，验证 v2.57 单带（L8/303）拟合的 `OFF_FACTOR=0.10` 是否跨场景稳定。新增 `tests/battle_lab_fit_expand.lua`（63 组采样：战士/法师/游侠 × L8@303、L16@1501、L24@2301 三难度带 × 武器等级扫描/本异系饰品对照/裸装，runs=8）与 `fit_power_estimate.py --mode expand`（全量+按 band 分桶岭回归，汇总 R²≥0.3 可信桶的 off 系数波动）。**关键结论**：①**跨带混池回归不成立**（ALL 桶 R²=-5.5，三带 DPS 量级差数倍互相吞系数），系数标定必须分带；②**magical 类三带全部可信**（L8/L16/L24 R²=0.63/0.68/0.96），off[phys]=0.330/0.000/0.028，**跨带均值 0.119 ≈ 0.10，确认 OFF_FACTOR 跨带稳定、维持 0.10 不变**（L8 桶 0.33 为 n=6 小样本波动，L16/L24 更大样本均≈0）；③**physical 类三带 R² 均低**（0.18/0.20/0.32，攻击组全被非负截断）——战士 DPS 受衔骨狂天赋触发主导、武器扫描方差不足，**无法回归标定**，其职业适配方向性只能由同种子 A/B 实测对照保证（v2.55 Lv8/303 3/40 vs 0/40、v2.57 战士 128>122）。L24 带 21 组为 <5s 速死弱样本（DPS 噪声大）仅作对照。系数值未改，只补充验证依据；CombatPowerEstimate OFF_FACTOR 注释、antibodies（新增"分带分桶不混池"避雷）、CLAUDE.md/versions/persona 已同步。回归全绿（边界/切关/生产接线 9 断言/默认 lab 20/20 v1），正式战力公式未改。
>
> **战力预估生产接线（`feat926/battle-lab`，⚠️ 玩家可见但默认关闭）**：把 battle-lab 验证过的分项计价原型接入正式角色页链路，**非破坏性**——官方战力 `calcHeroPower` 数字与公式完全不变，新增并列的实战预估。改动：`ui/character/panel/CharacterPower.lua` 抽出共享 `buildHeroAttrs(heroId, partySlot)`（构建已应用装备/遗物/神器/觉醒管线的英雄单位），`calcHeroPower` 与新增 `calcHeroEstimate` 共用它避免两条管线漂移；预估=`CPE.estimate(attrs, attrs.atkType)` 基础 + 觉醒战力 + 神器加成（觉醒/神器固定值沿用官方口径并入，原型不拆分其属性来源）。接线：`CharacterPanel.calcHeroEstimate`（local wrapper，经 `ensurePower()`）→ 注入 `CharacterDetail.setContext` → `Draw.setContext` 存 `calcHeroEstimateFn`。展示：`CharacterDetailDraw` 卡面战力下方新增「预估 N」副行，由模块级 `SHOW_ESTIMATE` 开关控制，**默认 false**（原型系数只做了方向性拟合，未跨全阵容标定；且本环境无法截图验证玩家 UI），需真人视觉验收后调 `Draw.setEstimateVisible(true)` 开启。新增缓存 `_estimateCache` 与战力共用 `markPowerDirty` 脏标记。**验证**：新增 `tests/character_power_estimate_test.lua`（真实模块 + mock 存档态）9 断言 ALL PASS——官方战力不回归（战士 Lv1=106、Lv50=479）、预估 >0（战士 75/法师 74）、预估 ≤ 官方×1.5、未知英雄返回 0 不崩、重构后战力可重复；主入口 validate 30 帧 lua_errors=0（require 链加载无错，字体/图片缺失为 sparse checkout 无 assets 的环境噪音）；边界测试/切关回归/默认 lab 入口 20/20 v1 全 ALL PASS。**状态**：代码接线完成且默认不可见，玩家数值零变化；开启副行前必须真人预览验收卡面布局（副行 y=powerY+26 是否与等级/职业标重叠）。
>
> **治疗系数拟合（`feat926/battle-lab`）**：补齐 v2.57 唯一未经数据验证的系数 `HEALER_ATK_FACTOR`。新增 `tests/battle_lab_fit_healer.lua`（22 组牧师采样：303 关超时稳定带 + 304/305 关阵亡带 × W67/W68 权杖等级扫描 × C2/C8/C14/C20/C27 饰品）与 `fit_power_estimate.py --mode healing`（因变量 HPS=avgHealing/avgSeconds，按 `healTakenRatio` 剔除需求截断饱和）。**关键发现**：治疗量=min(供给,需求)，与伤害饱和同理——304/305 阵亡带 14 组 heal/taken 全 ≥0.70 饱和（W68@17→32 HPS 仅 24.0→23.6，几乎不动即铁证），只有 303 关超时带 8 组 heal/taken<0.65 非饱和可拟合。**结果**：HPS 口径岭回归 R²=0.32，heal 组归一化基准 1.0、phys/mag 输出组系数 ≈0.48 → **确认初值 `HEALER_ATK_FACTOR=0.5` 与数据一致，保留 0.5**（R² 偏低、n=8、仅单关超时带，属方向性验证非精确标定）。回归全绿（边界 ALL PASS、fit 采样器 31 组可复现、默认入口 20/20 v1、两拟合确定性复现）。正式战力公式未改。至此 OFF_FACTOR/HEALER_ATK_FACTOR 两系数均有数据依据；healer 局在 303 关全部超时、在 304/305 全部阵亡（单人牧师无输出无法击杀），无「阵亡且非饱和」带，是其样本局限。
>
> **分项计价系数拟合（`feat926/battle-lab`）**：为 v2.56 原型做数据驱动系数拟合。新增 `tests/battle_lab_fit.lua`（31 组采样：战士/法师/游侠/牧师 × 武器 Lv1/8/14/16 × 力量/智力/vit+spi/裸装饰品，全部取 303 关败局带、runs=10，单方案走新 API `Lab.runSingle` 避免 A/B 双跑）与 `scripts/_proc/fit_power_estimate.py`（岭回归 λ=1、非负截断、只用非饱和样本 winRate<100）。**关键方法论**：败局总输出=存活时间×DPS，generic 组（生存属性）通过拉长存活时间吞掉攻击组信号（总输出口径 physical R²≈0.03、攻击组负系数），改 DPS 口径后 physical R²=0.43、magical R²=0.52。**拟合结论**：可信拟合中异系攻击组系数均被非负约束截为 0——异系攻击属性对 DPS 无可测贡献（其六围派生生存价值已由 generic 组承载）；据此 `OFF_FACTOR` 0.25→**0.10**（保留小正值防止显示归零），方向断言复验更清晰（战士力量 128>智力 122、法师智力 126>力量 119，实测输出方向不变）。排除项：physical off[heal]=0.87 为 C20(vit+spi) 单点共线噪声；healing 类 DPS 回归 R² 为负（healer 局全超时、结构受限），`HEALER_ATK_FACTOR=0.5` 保留初值未经数据验证，待牧师专属采样（短 timeLimit 制造非超时败局）再拟合。报告新增 `heroPowers[].groups`（phys/mag/heal/generic 四组分解，官方价值底座）供复算；`battle_lab_fit_samples.json` 已 gitignore。回归：边界测试（含第 9 节）ALL PASS、默认入口 20/20 v1 兼容、切关 ALL PASS。正式战力公式未改。
>
> **分项计价战力原型（`feat926/battle-lab`）**：新增 `scripts/systems/CombatPowerEstimate.lua`——「实战预估」原型，**仅 battle-lab 报告使用**，未接线角色页/队伍展示，正式战力公式与战斗结算未改。设计：与官方同一价值底座（`AD.META.valueModel`、pct/100、同一跳过表），属性分 phys/mag/heal/generic 四组，按英雄伤害大类 `AD.getAtkCategory(attrs.atkType)` 取系数——本系 1.0、异系输出 `OFF_FACTOR=0.25`、治疗系英雄对输出系 `HEALER_ATK_FACTOR=0.5`；通用攻防（攻速/暴击/命中/生命/护甲/闪避等）不乘系数。⚠️ 战斗单位本体没有 `unit.atkType`（只有 ClassGateRuntime 战中会设），必须读 `attrs.atkType`（UnitAttributes.create 从英雄配置写入，恒有值）。`tests/BattleLab.lua` 报告新增 `teamEstimate`、`heroPowers[].estimate/category`、`delta.teamEstimate`；CLI 摘要输出「预估」。方向验证（与 v2.54/v2.55 实测一致）：战士 Lv8/303 同官方战力 160 → 预估力量戒 133 > 智力戒 128（实测 3/40 vs 0/40、输出 2112 vs 1780）；法师 Lv1/101 同官方战力 112 → 预估智力戒 85 > 力量戒 83（实测输出 287 vs 193）。原型成功区分官方战力无法区分的职业适配方向。`battle_lab_boundary_test.lua` 第 9 节新增 8 断言（类别正确/同战力区分/法师方向反转/牧师 healing/atkType=nil 回落/estimateUnit 一致），ALL PASS；旧默认入口 20/20 胜 schemaVersion=1 兼容、切关回归 ALL PASS。系数未做跨阵容/关卡/层级拟合，仅方向性参考，不可当绝对强度承诺。
>
> **边界样本补齐（`feat926/battle-lab`）**：新增 `scripts/tests/battle_lab_boundary_test.lua`（纯 prepare 校验，不跑战斗，**自带 `engine:Exit()`，exit 0 即完成**），覆盖 `Lab.prepare` 全部拒绝分支与数值边界共 60+ 断言 ALL PASS：stageId 缺省/未知/终焉神殿 idle、英雄数 0/5、重复/不存在 ID、等级钳制（0→1、400→345、NaN/inf→缺省）、runs/seed/timeLimit 钳制上下界、loadouts 结构与非法槽位、模板与槽位不符、职业不可穿戴（战士穿魔杖）、双手武器+副手互斥、**levelRange 边界（C1{1,7}：Lv1/Lv7 合法，Lv0/Lv8/1.5/10000/非数字拒绝；C2{8,9999}：Lv7 拒绝、Lv8/Lv9999 合法）**、ascendLevel 0/100 合法 101/-1/1.5 拒绝、quality/affixes 出现即拒绝、mode 归一化，且历史反例 C10/C4 Lv1 确认被拒。真实边界校准（同种子 40 局、独立 Runtime、timeLimit=120、errors=0，复跑逐局一致）：
>
> | 边界样本 | A/B 饰品 | A/B 战力 | A 胜场 | B 胜场 | A/B 场均用时 | A/B 场均输出 | A/B 场均承伤 |
> | --- | --- | --- | --- | --- | --- | --- | --- |
> | 大狗嚼 Lv7 / 302（C1/C13 tier1 上边界 Lv7） | C1 力量 / C13 秘识 | 149/149 | 40/40 | 40/40 | 36.94/41.27 秒 | 1456/1456 | 832.9/989.7 |
> | 大狗嚼 Lv7 / 303（同上，难度+1） | C1 力量 / C13 秘识 | 149/149 | 0/40 | 0/40 | 43.5/44.1 秒 | 1658/1425 | 1098/1141 |
> | 大狗嚼 Lv8 / 303（C2/C8 tier2 下边界 Lv8），种子 926 | C2 力量 / C8 智力 | 160/160 | **3/40** | **0/40** | 49.61/49.33 秒 | 2112.4/1779.5 | 1217.8/1272.9 |
> | 大狗嚼 Lv8 / 303，种子 3926（跨种子窗口） | C2 力量 / C8 智力 | 160/160 | 1/40 | 0/40 | 48.95/49.25 秒 | 2091.1/1770.0 | 1212.6/1270.3 |
>
> 结论：单英雄难度悬崖在 302（全胜）↔303（全败）之间，饱和区间内胜率不可作 A/B 判据；唯一非饱和样本是 tier2 下边界 Lv8/303——同战力 160 下力量戒 3/40 vs 智力戒 0/40，且力量戒场均输出 +333、承伤 -55，与 v2.54 的 Lv1 样本方向一致（物理英雄带力量饰品优于同战力智力饰品），跨种子窗口（3926）仍保持 A≥B。探测记录：101/301/302 与双人队 303 均双侧全胜，701/401/304/305 均双侧全败；正式战力公式与战斗结算仍未改。
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

- **引擎**:UrhoX(星火编辑器),Lua 5.4,单机模式(`.project/settings.json` multiplayer.enabled=false → 走 `boot/Standalone.lua`,横屏 HORIZON_MODE=true)
- **原游戏**:《宿命旅途 Destiny Brigade》竖屏放置 RPG,20 个正经风冒险家角色
- **改造方向**(用户拍板):① 全角色玩梗化 ② 整体转**暗黑风格**(游戏名/标题/背景/人物图)③ 横屏标题页+背景视频化(视频未做)
- **新游戏名**:《终焉之门 Gate of Finality》
- **玩家称呼**:远征长(组织:远征队)
- **关键文件入口**:`scripts/config/HeroConfig.lua`(角色)、`scripts/ui/DarkTitleScreen.lua`(横屏标题)、`scripts/ui/story/gate/LetterIntro.lua`(外祖父遗产信)、`scripts/boot/Standalone.lua`(单机主循环)、`scripts/config/DialogueConfig.lua`(战斗台词)、`scripts/config/ScenarioDialogueConfig.lua`(剧情对话)、`scripts/systems/StoryPlayer.lua`(后续情景排队触发)

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
7. **[P2] 牢大角色**:高风险(真人逝者梗),建议黑曼巴蛇拟人替代,用户未定;新角色槽位 17 或 24,需要 HeroConfig+TalentManager+素材三件套+GachaConfig+TavernConfig(竞技场/ArenaAITemplates 已随多人壳删除)
8. **[P2] 竖屏 StartScreen 已删除**:横屏化后 `ui/StartScreen.lua` 不再存在,旧 LOGO fallback 一并移除;标题载体是 `ui/DarkTitleScreen.lua`
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
- `ScenarioDialogueConfig.lua`:SCENARIO_1~82(无 54、66),mode=large/small,steps[].characterId(1=大狗嚼 2=黄桃龙 3=叮咚鸡 4=??? 5=神秘少女 6/7/8=假角色 9=村长 10=铁匠 11=卫兵 13=老板娘 18=老六 19=哈基米 21=圣女 24=加载中 25=高ping战士),rewards(equip/hero/scroll/shard);触发排队在 `systems/StoryPlayer.lua`(STAGE_CLEAR/STAGE_ENTER/PLACE/FOLLOW/WIPE 表),播放在 `Standalone.tryPlayPendingStory_`,结束后 `claim_scenario_reward`;奖励发放在 `rules/battle/BattleService.lua` SCENARIO_REWARDS(82=大狗嚼碎片×60)
- 战斗台词触发:`DialogueConfig.get` 由战斗系统调用(entry/crit/kill/death/victory)

## 9. 用户画像(observed,待下一 agent 续充)

- 决策快,验收严:每轮交付都逐张看图挑毛病,不接受"差不多"
- 喜欢玩梗浓度拉满,但**避开真人真名**(自发提出谐音化)
- 会在多个 agent 会话并行推进同一项目(⚠️ 见抗体 1)
- 常用笔误:"例会"→立绘、"该名字"→改名字,理解意图勿纠结字面
- 倾向"先试点看效果,再全量"的节奏(A 方案、暗黑强梗试点均如此)
