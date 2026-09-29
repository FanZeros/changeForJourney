# antibodies — 跨项目避雷清单(只增不减)

- [scope:project] 2026-09-28 护盾成长层（`AD.SHIELD_SCALING` + `UnitAttributes.recalc` §5.5）：护盾三来源全是线性而 HP/伤害指数爆炸，中后期护盾占比塌到≈0。修法=在 recalc 末尾加附加层：护盾 += 最终HP×hpRatio(5%) + 派生护盾×((1+(lv-1)×0.02)-1)；门控 preGrowthES>0（无盾敌人不凭空加盾）；附加层不被 esBonus/finalESBonus 二次放大。等级经 cfg.unitLevel → attrs.unitLevel（clone 保留）。调平衡只改 AttributeDef.SHIELD_SCALING。回归=tests/shield_scaling_test.lua（15断言）+ character_power_estimate_test（战力不回归）+ _proc/shield_probe.lua（before/after 对照探针）。改任何成长/属性公式先跑 probe 留基线再改。
- [通用] 2026-09-28 再次强化：不能取消/退出任务；每次交付或受阻必须先简报再**真正调用 AskUserQuestion**（选项形式）询问下一步并等待选择，禁止纯文字结尾或中断对话。clone 仓库后 remote URL 可能内嵌 PAT——推送用内联凭据 `git push https://<PAT>@...`，推完 `git remote set-url` 还原为干净 URL 并 `grep ghp_ .git/config` 验证 0 残留；提交前还原 build 自动改写的 `.project/project.json`（project_id 会变），meta 文件随代码一起提交。`git add` 未生成的 .meta 会 exit128 中断整条 `&&` 链——只 add 已存在文件。
- [scope:project] 护盾成长层 A/B 验证结论（`_proc/shield_ab_lab.lua`，E档8%/5%，种子926×20局）：裸装英雄约束下 BattleLab **无「不全胜不全败」临界带**（要么碾压要么全败），胜率维度只能靠夹逼——①饱和胜局带(S0105/S0205含盾关)B臂胜率仍100%、耗时仅+0.9~2.1s（敌人加盾不破坏过关）；②全败带(S2405-Lv36)B臂存活+26%/承伤+37%（护盾劣势局真发挥作用）。改生存属性平衡时若找不到非饱和带，用「胜局不翻盘+败局更耐打」两端夹逼做方向性结论，别硬套胜率差。
- [通用·强化] 2026-09-28 用户再次强调：**每次完成或遇阻都必须真正调用 AskUserQuestion 工具以选项形式询问下一步，等用户选择后再继续；严禁以纯文字结束/中断对话，严禁擅自取消或退出任务**。记忆只是提醒不是 hook，必须每轮显式执行。
- [scope:project] 2026-09-28 觉醒杠杆②（叠层口径多元化）已实施并 push 到 `feat926/awakening-skill-review`（commit 6968579）：#14内鬼/#18老六→暴击击杀×2、#11熬夜冠军→通宵斩击杀×2、#13弹弹弹→弹射击杀×2、#8愤怒的小雀→标记击杀×1提至×2。全部在 `AwakeningGrowth.RULES` 数据表配置，不改战斗代码。杠杆①（品质加权）杠杆③（软上限）用户未选，未实施。
- [scope:project] 🔴 觉醒击杀口径新增标记必须挂在**死亡敌人**身上（一次性），不能挂 attacker：`attacker._nightSlashKill` 是 TalentSuhua 的**粘性标记**（只设不清，首次通宵斩后恒 true），若觉醒1条件读它会让"通宵斩击杀×2"退化成"第3次攻击后任意击杀×2"（比原逻辑更强，违背专属口径设计）。正确做法：经 `statMeta` 透传（opts.isNightSlash/isCrit/isRicochet → statMetaFromProjOpts → dealDamageToUnit）写 `deadEnemy._killedByCrit/_killedByNightSlash/_killedByRicochet`，条件读死亡敌人标记。测试已加"粘性标记不误触发"防回归断言。
- [scope:project] 改觉醒叠层口径需同步三处：①`AwakeningGrowth.RULES/CONDITIONS`（逻辑）②`AwakeningConfig.DATA`（玩家可见文案，倍率×2 则文案数值也×2，如 0.15%→0.3%）③`getStatusLine` 按 stacks 动态算无需改。ATTR_MAP 系数不动（stacks 变大自动反映）。杠杆②专属口径必须核查触发频率不能过低致成长停滞（#13 弹射 TalentRosa 场上≥2敌即触发，挂机多怪频发，成立）。
- [scope:project] 本仓库是**浅克隆**（`--depth 1 --branch workspace926`），`remote.origin.fetch` 原只跟踪 workspace926。push 新分支后要建上游跟踪，须先 `git fetch origin <branch>:refs/remotes/origin/<branch>` 显式建 remote-tracking ref，再 `git branch --set-upstream-to`。push 命令带一次性凭据 URL 时若外层管道超时，先 `git ls-remote` 核对远端 ref 是否已到目标 commit，不要盲目重试。PAT 不进 origin URL/记忆；push 后 `git remote set-url origin` 用干净 URL。

- [scope:project] 2026-09-28 觉醒技能触发审查结论：觉醒/追加技（`systems/ExtraTalentSystem.lua` = ETS）与天赋（`systems/TalentManager.lua` = TAL）的战斗触发钩子（`onEnemyDeath/onAfterAttack/onBlock/onOverflowHeal/onShareFatal/onBattleStart/tryTicketRevive/update` 等）**只在真实逐帧战斗路径触发**：`ui/battle/`（BattleScene→BattleCasualty.process→TAL.onEnemyDeath→ETS.onEnemyDeath 叠层；BattleSceneTick.tick→TAL.update）、`ui/battle/tri/`、`ui/dungeon/DungeonBattleScene.lua`、`ui/tower/TowerTriBattle.lua`，及 `systems/talents/*` 子模块。**扫荡(`rules/sweep/SweepService`)、离线(`rules/offline/*`)、挂机结算(`systems/OfflineCalc`) 是纯数学查表，grep 对 Talent/ETS/TAL/onEnemyDeath 零匹配，不构造战斗单位、不跑攻击循环、不叠觉醒层**（只经 `HeroConfig`→`ETS.applyToAttrs` 消费过去真实战斗已攒下的永久层）。"挂机"分两种：**在线挂机**(BattleScene `battleMode=="idle"`，与 firstClear 共用同一 update 循环，会正常触发觉醒) vs **离线挂机**(OfflineCalc，不触发)。觉醒叠层落 `roster[heroId].extraTalent`，靠 `ETS.commit→markDirty→update 每 1.5s persistNow→SYNC_EXTRA_TALENT` 持久化。
- [scope:project] 2026-09-28 觉醒逻辑多元化现状：ETS 的"永久成长层"（觉醒1/`bruteEntries`）几乎全是**单一击杀叠层→线性 flat 属性**（stacks→MAX_HP/PHYS_ATK/MAG_ATK/ARMOR/SPI/CRIT_RATE/DMG_BONUS 等），25 名角色里绝大多数 `onEnemyDeath` 只有 `if n1 then bump() end` 一种累积口径，差异主要体现在觉醒2/3 的机制钩子（撕咬/冰雕/环绕/预存票/圣核等）。可多元化的方向：叠层触发条件（按属性击杀/暴击击杀/承受伤害/治疗溢出/连击/闪避）、成长曲线（分段/软上限/递减）、按敌人品质或关卡加权、跨场携带衰减、属性维度扩展。改动需同步：`AwakeningConfig.DATA`（文案）、`ETS.getStatusLine/getDesc`（面板）、`bruteEntries`（属性映射）、`NUM_KEYS/normalize`（存档字段），并跑 `tests/character_power_estimate_test.lua` 防战力回归。
- [scope:project] 🔴 **遗物（Relic）系统是「已丢弃内容」，禁止重建其 UI**（2026-09-28 教训）。礼拜堂（ChurchPage）底部只有「神器」Tab，用的是 **Artifact 神器系统**（`ChurchArtifactPanel`/`ArtifactDefs`/`mod_artifacts`/槽位装配+神器置换+洗练数值），与「遗物」是两套独立系统。遗物（Relic）= 五兽封兽祭阵/本座阵眼/合成升品（`RelicBagPanel`/`RelicDefs`/`mod_relics`），其 UI 面板在 workspace927 基线（ddcc8266）**本就已删除**，用户已确认丢弃。本次误从 git 历史（3cd2f48d）恢复重建了 RelicPage/RelicBagPanel/RelicDetailPanel/RelicReforgePanel + 城镇祭坛入口 + 关键词接入，已整体 revert（commit d7a92c0c 撤销 3597da37/3e407b60/73a3a0bb）。**教训：用户说"我把X放礼拜堂了"要先核对代码——「神器」≠「遗物」，别把术语当同一物；从 git 历史恢复"被删文件"前必须先问用户该功能是否已废弃。** 遗物后端（RelicSystem/RelicDefs/RelicService/RelicAltar/RelicBridge/RelicAffix/RelicConditionHandler + rules/relic + shared/relic）仍是基线自带、深度接入战斗/天赋/市场/副本（58 文件引用），未删；是否清理待用户单独决策。
- [scope:project] 分支并发：本会话工作分支是 `workspace927-keyword-system`（关键词系统）。撤错方向时用 `git revert --no-commit <新>..<旧>` 汇总撤销再一次性提交，**不强推**（记忆规则）。revert 会连记忆文件更新一起回退，撤销后需重新写正确教训。

- [scope:project] `StandaloneSave.writeFile` 必须检查 `File:WriteString` 的 boolean 返回；失败后不能记成功快照，且须安排下一轮重试。直接覆盖旧档与损坏 JSON 恢复仍未解决；`FileSystem:Rename` 在隔离存储平台上的行为未经验证，不能仅凭声明视为原子落盘。
- [scope:project] 离线英雄经验预览不能把编队中的 `0` 空槽、未拥有或重复 ID 算进平分分母；领取回退路径应使用同一有效名单规则。
- [scope:project] `ModuleRegistry` 与 `HeroesSchema` 在单机收到 heroes 时连续规范化，数字名册键必须保留；跨队同步不可逐队回调：第一队推送触发面板刷新会覆盖第二队未提交的编队。0 是空槽而非角色，normalize 不得删除后续队伍的 0。
- [scope:project] 清理旧 UI 前先核对真实 `init/open/draw` 玩家路径；旧面板可删，但城镇 `TaskPage`、签到/任务服务/协议/存档、GM `AnnouncementConfig` 和 `RewardPopup` 遗物图标有独立用途。原 `RelicReforgePanel` 拼接的遗物路径失效不代表五张奖励图标可删。
- [scope:project] `scripts/tests/lootbox_overflow_test.lua` 原有领取/回收弹窗断言与基线 `StandaloneBoot.lua` 仅 Toast 的实现不一致；执行时在第16/18条旧断言失败，不应把失败归因于旧面板清理；修测试或改玩法必须另外授权。
- [scope:project] 2026-09-27 清理旧 `DiaryPage`：五张 `UI_RZ*` 图片已在 `a852547` 删除，但 `Standalone` boot queue 仍调用 `.init()`，一图两错=10条。删除页时需保留仓库初始化与城镇 TaskPage 入口、保持 tab2 不可选；旧签到/公告/日周任务若恢复需重新设计入口。
- [scope:project] 装备详情小窗展开方向必须由 owner 区分：character（右栏）从鼠标左侧展开、对比继续向左；bag/backpack（左栏）从鼠标右侧展开、对比继续向右。别让边界夹取把小窗挤到鼠标另一侧；悬停锚点用鼠标坐标，钉住后不要用格子中心重设。
- [scope:project] 套装详情必须按最后一条随机词条的底部计算起点，并同步面板高度、按钮和热区；中文描述要换行并保证字号可读。
- [scope:project] 分支推送以用户当前轮次授权为准。2026-09-27 已授权新建并推送 `workspace926`，合入 `workspace925` 与全部 `feat926/`。历史「只推某个 feat926、不推基线」不再覆盖本轮。远端并发提交先 fetch 核对，不强推。不在凭据 URL/Git 配置/记忆中保存 PAT。
- [scope:project] 神器并行战线 `ArtifactRuntime.initBattle` 不能重置全局状态；`reset/update` 必须使用当前 allies。战斗效果为每次战斗独立状态，不能污染 `unit.artifactEffects`。亡魂计时在三行模式须逐队推进。
- [scope:project] 2026-09-27 当轮授权是新建并推送 `workspace926`（已含 `feat926/artifact-audit`）。不推 `workspace` / `workspace925`，不强推。不在凭据 URL/Git 配置/记忆中保存 PAT。
- [scope:project] 终焉之门多难度 Boss/章节是**按相对章复用**（Hard ch10 ≈ Normal ch10，章名/bossId 应一致，只 monsterLevel 缩放），且**所有 stage5 Boss 必须是 quality=5 传说怪**。查异常用横向对比脚本：①遍历全 15 难度同一相对章的 name/bossId，孤例（如只有 Hard 用「荒芜高原」+朱厌52，其余 14 难度都「悬魂瀑布」+当康25）= 旧版残留；②统计全 345 个 stage5 bossId 的 quality 分布，非 q5 = 配置手误（如 3105 的 bossId=22 罴是 q1 普通怪，2**8**→2**2** 一位手误导致 Boss HP 只有应有值 5.7%）。改 bossId 只影响 stage5 战斗内容，**不影响推荐战力表**（采样基于 stage1 首关），无需重跑拟合。Boss 无专属机制：isBoss 标志仅影响 UI 红字/出场插队敌列中部/套装攻条削减减半(0.2vs0.6)/gate_104_peel 天赋判定，难度纯靠 monsterLevel 数值缩放。

- [scope:project] 拟合曲线做"实测段 + 外推段"拼接的单调量表（如推荐战力）时，**衔接点必须单调续接**：外推段不能直接用拟合曲线值，因为曲线在采样上限外可能低于实测终点（v2.63 实测 ml46 展示 8520，但二次曲线 pred(47)=7810，直接拼会倒挂 4605→4701）。正确做法：外推段每章取 `max(round_up_10(pred(v)), round_up_10(前一章×最小增长))`，保证从实测终点单调爬升。测试必须加"衔接单调 p(末实测关)<p(首外推关)"断言专门锁这条。另：写这种 max(曲线, 前章) 的闭包时，缺口/外推分支都要传入对应的 pred 函数（pred_p/pred_e），第一版硬编码 pred_p 会对 e 序列算错值——凡是按 p/e 双口径分别生成的，pred_fn 必须参数化不能写死。
- [scope:project] battle-lab 阈值采样**扩难度会暴露采样噪声**：Hard 段（ml 24..46）实测阈值非单调更严重（ml37=3774 反常低于 ml34=4804，因怪物构成/词缀差异），PAVA 保序压平后个别点偏差达 36%。所以"保序修正偏差上限"不能设太死——v2.62 的 12% 是 Normal-only 口径，扩到 Hard 后必须放宽到 40%，否则测试假失败。原则：**单调性是玩家可见硬需求，优先于逐点还原实测值**；原始 RAW 值保留在测试表内作对照即可，展示值允许为单调性牺牲精度。

- [scope:project] 终焉之门章节是**全局连续编号跨 15 个难度文件**（Normal ch1-23 → Hard ch24-46 → … → 湮灭V ch323-345，chapter = stageId//100）。任何"与上一章比较"的批处理（怪物继承、难度衔接分析）**必须按全局 chapter 链跨文件建索引**，不能只在单个 `StageConfig_X.lua` 内找 `chapter-1`——第一版 `inject_chapter_inheritance.py` 只在文件内查，漏掉全部 14 个跨难度衔接点（Hard 首章 ch24 的上一章是 Normal 末章 ch23），被 `stage_inheritance_test.lua` 的"相邻章节零重叠清零"断言当场抓出。改跨文件脚本后务必跑该测试复验。
- [scope:project] 用实测数据生成的**玩家可见单调量**（推荐战力/难度曲线）不能直接把原始实测值上屏：battle-lab 阈值受怪物构成影响有真实回落（ml13<ml12、ml17<ml16、ml21<ml20），v2.61 在实测范围直接用原值导致选关 UI 出现"下一章推荐更低"的倒挂。正确做法：对首关阈值做 **PAVA 保序回归**（相邻违反者合并取均值）压平违反段，再对相等段施加最小梯度（×1.02、ceil 到 10）保证严格递增；**原始实测值保留在测试的 RAW 列作对照**，并加"修正幅度 ≤12%"断言防止保序把数据改飞。章内 2..5 关不要同值，向下一章首关插值（0.2/0.4/0.6/0.8 权重、取整 5、夹取非降且 <下一章首关，末章用外推曲线 ml+1 作虚拟下一章）。
- [scope:project] 改关卡 `monsters={...}` 数组做"继承上一章怪物"时**只动构成、不动总数**：战斗总怪数由 `firstCount`/`idleCount` 控制，出场轮换是 `((i-1)%#types)+1`，所以 types<3 追加、==3 替换末位槽都不改变实际怪物数量与难度量级，平衡风险最小；继承怪等级随关卡 `monsterLevel` 自动缩放不塌方；Boss 关（stage 5）保持纯净不注入；注入怪必须排除 bossId 且优先选上一章 2..4 关高频普通怪（玩家最熟的面孔）。注入脚本要幂等（已产生重叠的章节自动跳过）并支持 `--dry-run`，UI 卡面区宽度约束 types≤3（types+boss≤4）。

- [scope:project] 玩家可见数值/UI 改动必须非破坏性推进：v2.59 战力预估接线保持官方 `calcHeroPower` 数字零变化，新增预估副行用 `SHOW_ESTIMATE` 开关默认关闭，等真人视觉验收（本环境无法截图玩家 UI）再开。改 `CharacterPower` 时抽出共享 `buildHeroAttrs` 让战力与预估走同一管线，防止装备/遗物/神器应用逻辑漂移；改完必须跑 `tests/character_power_estimate_test.lua`（真实模块+mock 存档验证官方战力不回归）+ 主入口 validate（lua_errors=0，字体/图片缺失是 sparse checkout 无 assets 的环境噪音，不是代码错误）。

- [scope:project] 用战斗模拟数据回归属性→强度系数时，**因变量必须用 DPS（输出/秒）而不是败局总输出**：败局总输出=存活时间×DPS，生存属性（HP/护甲）通过拉长存活时间混杂进总输出，直接回归会让生存组吞掉攻击组信号（实测 physical R²≈0.03、攻击组负系数），DPS 口径才能拿到可解释系数（R²=0.43/0.52）。全胜样本伤害被怪物总血量截断，同样必须剔除（winRate=100 不进回归）。
- [scope:project] 战力系数回归**必须分难度带分桶，不能跨带混池**：L8/L16/L24 三带 DPS 量级差数倍，混池 ALL 桶 R² 为负、全部组系数被吞。分带后 magical 类三带 R²=0.63/0.68/0.96 全可信（off[phys] 0.33/0/0.028，均值≈0.12 支持 OFF_FACTOR=0.10 跨带稳定）；physical 类各带 R² 均低（战士 DPS 被衔骨狂天赋触发主导、武器扫描方差不足），不能靠回归标定，方向性只能由同种子 A/B 实测对照保证。速死带（<5s 阵亡）样本 DPS 噪声大，只作对照不作依据。
- [scope:project] 治疗量拟合同样要先查**需求截断饱和**：治疗=min(供给,需求)，heal/taken 比值高（≥0.65）时 HPS 不再随治疗属性变化（实测 W68@17→32 HPS 仅 24.0→23.6、几乎不动即饱和铁证），这类样本必须按 healTakenRatio 剔除。单人牧师无输出不能击杀：稳定关全超时、难关全阵亡，不存在「阵亡且非饱和」带，只有超时带（时间固定、需求未满足）可拟合，样本量因此受限（n=8、R²=0.32），结论只能作方向性验证。
- [scope:project] 战斗单位的攻击类型读 `unit.attrs.atkType`，不要读 `unit.atkType`：`HC.createHero` 构建的 unit 本体没有 atkType 字段（只有 dmgMainType/dmgSubType 中文名），`unit.atkType` 仅 ClassGateRuntime 战中转职时动态设置；`attrs.atkType` 由 UnitAttributes.create 从英雄配置写入，恒有值（nil 时 CombatFormula 回落 ATK_SLASH）。
- [scope:gamedev] `File:WriteString(cjson.encode(data))` 会给 JSON 追加 NUL，Python json.load 读不出；与外部工具交换单行 JSON 用 `File:WriteLine`/`File:ReadLine`，并实际在 OS 层解析验证。
- [scope:project] 战力校准样本必须先核对 `EquipmentConfig.ITEMS[templateId].levelRange`：C10/C4 模板最早 Lv.28，放在 Lv.1 虽能模拟却不属于正常掉落；跨种子 A/B 需模板等级合法、同装备品质、同一英雄/关卡，并避免在胜率全 0/全 100 时只靠胜率定权重。`BattleLab.prepare` 已加范围拒绝，回归见 `tests/battle_lab_boundary_test.lua`（改 prepare 校验必须同步过这个测试）。
- [scope:project] 战力校准取样要先探难度悬崖再定关卡：Lv7 大狗嚼在 302 双侧全胜、303 双侧全败，饱和区内 A/B 胜率差恒为 0，白跑 40 局；非饱和样本出在 tier2 下边界 Lv8/303（3/40 vs 0/40）。取样顺序 = 先用 20 局探 2~3 个关卡找到「有一侧不全胜不全败」的组合，再扩到 40 局 + 第二个种子窗口复验；全饱和时改看场均输出/承伤/耗时并如实标注不可外推。
- [scope:project] 战斗实验不要直接嵌入主游戏进程：MapAffixSystem/StageBerserk/遗物神器等共享模块级状态。新 Runtime 进程配模板英雄跑三行驱动；未经用户授权不要修改玩家编队/存档或发奖。
- [scope:project] 装备详情小窗展开方向必须由 owner 区分：character（右栏）从鼠标左侧展开、对比继续向左；bag/backpack（左栏）从鼠标右侧展开、对比继续向右。别让边界夹取把小窗挤到鼠标另一侧；悬停锚点用鼠标坐标，钉住后不要用格子中心重设。
- [scope:project] 套装详情必须按最后一条随机词条的底部计算起点，并同步面板高度、按钮和热区；中文描述要换行并保证字号可读。
- [scope:project] 2026-09-27 当轮授权是新建并推送 `workspace926`，其中已包含 `feat926/battle-lab`。不推 `workspace` / `workspace925`，不强推。凭据不进仓库或记忆。
- [scope:project] `CharacterDetail` 属性页仅角色切角能切角色；装备槽和一键操作只在配装页绘制/响应，配装页不要绘制/响应左右切角。底板/标题下移时列表网格和滚动热区必须同步，Tab 栏不能位移。
- [通用] 用户要求每次交付以 AskUserQuestion 选项询问下一步，不纯文字结束；记忆是提醒，自动执行的跨会话保证须配置 harness hook。

- [scope:project] 遗匣 `seeds[].equip` 为确定装备：挂机入匣即生成，旧分组只迁移一次；领取/重开/读档不重骰、不降级、不合并完整装备。
- [scope:project] UrhoXRuntime 自定义 `require` 有独立模块缓存；测试里单改 `package.loaded["模块名"]` 不一定替换实际依赖。需要注入替身时优先临时修改真实模块的函数，并在测试后恢复。
- [scope:project] 横屏全局奖励弹窗滚轮应先于 `BattleTriPage.handleScroll`（装备袋覆盖区）处理，否则奖励列表无法滚动。
- [scope:project] 遗匣稀有度筛选不重排源数据；单件使用原 sourceIndex，批量领取/回收传0全部或1..6精确品质。待整理项不参与回收，刷新取消旧确认。
- [scope:project] 遗匣现在是左栏地点页，不能再加回全局中栏模态路由；按鼠标栏路由滚轮，中缝返回须用窗口逻辑坐标。
- [通用] 凭证不能写进记忆、代码或提交；对话中贴出的PAT提示撤销轮换。

- [scope:gamedev] UrhoX 项目 assets 里的 `.png` 实际是 KTX GPU 压缩纹理:ImageMagick 读不了;`Texture2D:GetImage()` 对压缩纹理返回噪声;可靠导出/验收 = `UrhoXRuntime -graphicssurfaceless -screenshot`(离屏渲染)
- [scope:gamedev] UrhoX `-screenshot` 超时会静默失败(exit 0 但文件不落盘),完成后必须 `stat` 检查 mtime;软渲染大帧预算给足(timeout 280s+)
- [scope:gamedev] `nvgClip` 在 UrhoX Lua 绑定中不存在;用 `nvgImagePattern + RoundedRect 填充路径` 自带裁切,或 nvgScissor/nvgIntersectScissor
- [scope:gamedev] `nvgImagePattern` 的尺寸参数必须与 `nvgRect` 一致,否则内容错位
- [scope:gamedev] build 的 LSP 检查挡 Lua 类型标注:`nvgCreateImage` 返回 `integer?`,修法 = `or -1` 兜底 + 标注改 `integer`;行内抑制 `---@diagnostic disable-line`
- [scope:gamedev] generate_image 透明底用 `transparent=true` 边缘质量差;用**黑白抠图法**(白底生成 → edit_image 黑底【构图必须一致,黑底用 nanobanana 模型】→ ImageMagick difference 抠图)
- [scope:project] 天赋显示名已对齐梗人设（衔骨狂/已读不回/必杀蓄力/氮气/抄作业等）；内部 talentId 未改，避免存档/觉醒对不上
- [scope:project] 觉醒只有 3 阶：1 粗暴 / 2 机制 / 3 进化。旧 7 阶存档必须走 `AwakeningConfig.migrateAwakening`（旧 1–3→新1，4–6→新2，7→新3）。未打 `_awk3Migrated` 的档一律当旧 7 阶并，否则只点过前三阶会被当成新三阶全开。超模技 `hasNode(4/7)` 仍映射到 2/3。层数在 `roster.extraTalent`。竞技场对手 `createHero(..., false)` 打 `_etsDisabled`。击杀用 `_killedBy`，弹射击杀另标 `_killedByRicochet`
- [scope:project] 三行模式 `H_SEAM_BACK=true` 时二级页返回键由 Standalone 中缝层绘制；页内再 `drawBackChevron` 会在角色详情左缘叠一颗假返回按钮（输入已跳过、绘制漏跳过）
- [scope:project] **并行 agent 会话编辑同一项目会互相覆盖文件**(已发生:LetterIntro 被旧缓冲覆盖、HorizonBg 中间态卡 build)。多会话并行时:开工前 stat 关键文件 mtime;发现语义漂移立即停下与用户确认分工
- [scope:project] 用户会引用另一会话的产出(文案/文档/截图)让本会话落地,产出物以用户最新粘贴的为准
- [scope:project] 真人梗高风险:"牢大"(科比逝者恶搞)不可直接实装;活人梗(ikun)用软化变体;方案先给用户过目
- [通用] 用户短指令常有笔误("例会"=立绘、"该名字"=改名字),按语境理解意图
- [通用] 用户验收是逐张看图的严格模式,交付前先自查(引擎实拍 > 自述"完成")
- [scope:project] 默认禁止推 `workspace`；仅当用户**当前轮次明确要求**合入/推送 workspace 时才推。2026-09-22 晚已按用户指令把今天三线合入并推送 workspace。
- [scope:project] 玩家可见「冒险*」已改为远征世界观（远征等级/远征队员/远征招募券/远征日志）；内部键名 `adventurer`/`recruitTicket`/`playerLevel`/`guild` 不要跟着改，RelicBridge/TalentEffect 前缀解析要跟显示名同步
- [scope:project] 每步交付后必须用 AskUserQuestion 给下一步选项，禁止纯文字中断
- [scope:project] merge workspace 前必须干净工作区：还原 `.project/project.json` / `.agent` 改动，删除未跟踪 `*.meta`。脏树会让 `git merge` 直接失败且不建 MERGE_HEAD
- [scope:project] `Standalone.lua` 横屏输入/中缝已抽到 `network/StandaloneHorizon.lua`；workspace 改中缝条宽要打到 Horizon 的 `seamBackList`，用 `DrawUtil.SEAMBAR_ASPECT`
- [scope:project] workspace 已入库 791 个资源 `.meta`；本地引擎再生成的未跟踪 meta 不要提交，merge 前清掉以免挡住 checkout
- [scope:project] 抽取模块读 `TAL_BCS` 必须 `getTAL_BCS()`，bind 快照会在 `TAL.mount` 后过期
- [scope:project] 大页不要用 `_ENV = E` 注入闭包：LSP 会把里面的名字打成 undefined-global Error 挡 build。用 bind(deps) 具名局部
- [scope:project] 已去掉多人入口：`main.lua` 只加载 Standalone。玩法 `sendAction` 走 `network.GameAction`→LocalActionBridge。`network/Client.lua` / `Server.lua` 已删；`ClientDispatcher` 与 `server/` Handler 仍给单机本地桥用，勿当死代码删
- [scope:project] 已删 GuildPage / CharacterSelect / LoadingScreen / ServerSelectPanel / VersionMismatchPopup / GuildHandler / GuildService。StartScreen 不再选服；横屏仍 skipForReconnect → DarkTitleScreen。`shared/ServerListConfig` 与 `config/GuildConfig` 仍被存档/云排行使用，勿当死代码删
- [scope:project] ChurchPage 主绘制已抽到 `ui.ChurchDraw`（bind 具名注入，开关回调用 getter/setter）。大页继续禁止 `_ENV = E`
- [scope:project] Church 输入/名单、Blacksmith 输入、Talent onBeforeAttack/onDamageTaken 已抽成 bind 模块。TAL_BCS 必须 `getTAL_BCS()`
- [scope:project] Blacksmith 上半绘制依赖大量局部 img/CARD 常量，勿盲目整段抽；结果转发可抽 `BlacksmithResults`
- [scope:project] 不要把 `.project/i18n.json` 的 `enabled` 设为 true：自动提取会扫进 5800+ 梗名/剧情台词，构建会把玩家可见中文替换成 `t_xxx`。五语用 `scripts/core/I18n.lua` 运行时词表
- [scope:project] 不能取消/退出任务。每一步完成后必须用 AskUserQuestion 给下一步选项，禁止只用文字收尾或中断对话。即使用户没再说话，也要停在选项上等待。
- [scope:project] 从 `integrate/20260923` 新开功能分支继续开发。完成后只 push 当前功能分支，禁止推 `integrate/20260923`、`workspace` 或其他分支。旧规则「只 push integrate/20260923」已作废。
- [scope:project] 右键装备：不可穿 toast+轻点击音；已穿则 UNEQUIP；成功穿戴 play("install")+toast。提示走 `core/UiToast.lua`，横屏在 nvgEndFrame 前画
- [scope:project] 全 UI 五语用 `core/I18n.installDrawHook()` 拦 nvgText 按中文原文查 `I18nDict`。梗名/剧情/信件不进词表。不要开引擎 i18n enabled=true
- [scope:project] 主字体 `NotoSansCJKkr-Bold.otf`（OFL）。Resource Han Rounded CN-Heavy 是简体子集，韩文缺字。Pretendard / IBM Plex KR 中日也不全，五语不要单用它们
- [scope:project] 用户上传的 `assets/video/se.mp4` 实际是 RPG Maker VX Ace 风格 SE ZIP（m4a+ogg）。游戏 SE 走 OGG + GameSFX 键名；替换时覆盖同名文件、保留路径。新英雄攻击音必须同时进 GameSFX + ProjectileSystem.CONFIGS + 投射物图，否则无声无特效
- [scope:project] RPG Maker SE 包比原音效响；试听用 SettingsPanel `SFX_PACK_GAIN=0.05` 乘到 Effect 通道（过场/对话 blip 也走 Effect）。滑条仍是相对音量。BGM 不乘这个系数
- [scope:project] 战斗 SE 不要用 >0.85s 的包条目（Starlight/Load/Wolf/Monster8/Magic8 等是技能咏唱不是普攻）。哈基米禁止 Cat，用短治疗/圣咏
- [scope:project] `StageConfig.formatProgressDisplay` 必须用相对章节号（getRelativeChapter + stage），不要从 `entry.name` 抠 `1-1` 再拼 DIFF 前缀：高难名已是「困难·黑棘林道1-1」，会显示成「困难困难1-1」
- [scope:project] SE 听感延迟两处：ButtonFeedback 在 trigger/松开才 playUIClick（应按下即播）；ProjectileSystem 在 spawn 就播远程音，飞 0.5s 才命中。远程/bezier/fly 改命中播，melee/lightning 仍出手播
- [scope:project] 角色页「远征团」标题对齐详情页角色名 `MID_NAME_CY=995`（CharacterDetailDraw），不是贴 LIST_BG 顶边。总战力仍在 860（与「角色详情」同高）
- [scope:project] 三行 HUD 行标签底条已在 workspace 暗黑化中去掉，不要为了加宽标签把黑条加回去

- [scope:project] 2026-09-24：从 workspace924 新开 `workspace924-yixia-art`。只 push 这个功能分支，禁止推 workspace924 或其他分支。每步结束必须 AskUserQuestion，不能取消任务。
- [scope:project] 用拟合曲线生成配置表时必须设**外推上限**并处理"数据不支持"态：关卡推荐战力第一版把指数曲线（R²=0.9715，实测 ml 1..23）直接外推到全关卡表 ml=345，产出 p≈2e16 的数学垃圾条目。正确做法：①实测范围内直接用实测阈值不用曲线值（曲线在低端系统性低估：ml1 拟合 280 < 实测 318）；②外推只允许到采样上限×2（extrapCap=46）并标 x=true；③超上限不生成条目、查询 API 返回 nil，让接入方显式处理"数据不支持"。生成表必须配 sanity 测试锁住这三条（`tests/stage_recommend_test.lua`，v2.62 起 21 断言）。
- [scope:project] 阈值二分搜索要先验证单调性与悬崖陡峭度：正式采样前用单关（1501）探测等级→胜率曲线，确认单调且过渡带窄（L32=0% → L36=92%）才适合"爬升+二分"；阈值记录取保守侧（hi，winRate≥50% 一侧），并同时记 lo 侧供区间宽度审计。章节首关阈值随 ml 非严格单调（ml13/17/21 因怪物构成回落）是真实数据，**采样/记录层不要平滑**（保留原始值供审计）；但**玩家展示层**（推荐战力表）要另做 PAVA 保序修正防倒挂——两层分离，v2.62 起展示值与实测值并存（测试 RAW/DISPLAY 双列对照 + 偏差 ≤12% 断言）。
- [scope:project] 在既有 UI 行内加新文本前必须先算可用宽度并按最长内容定字号：选关弹窗左栏可用宽只有 ~124px（CARD_X−MID_X−边距），「推荐≈18110」（外推上限值）22 号字会溢出撞上敌人卡面，降到 20 号 ~115px 才安全。最长文本要按数据域的**上限值**估算（SRP extrapCap 边界），不是按常见值。
- [scope:project] 终焉之门五语翻译分两条路，**含动态数字/变量的串必须走 `I18n.t(key, args)` 键值表**（`core/I18n.lua` 的 `T` 表 + `{0}` 占位符，如 `expedition_lv`；v2.61c 的 rec_power/rec_power_approx 已于 v2.63 随 UI 图标化删除），**不能依赖 `installDrawHook` 的 nvgText 原文查表**——hook 按中文原文查 `I18nDict`，数字一变（「推荐 318」vs「推荐 480」）就查不到，五语下会漏翻成中文。纯静态中文串才走 draw-hook 自动查 `I18nDict`。译后串（如 "Rec. 18110"）再经 hook 查中文原文查不到会原样返回，无二次翻译风险。加动态文案时：在 `T` 五语块各加一个带 `{0}` 的 key，代码用 `I18n.t("key", n)`。
- [scope:project] headless Runtime 跑测试脚本必须**脚本自己在 Start() 结尾调 `engine:Exit()`**，否则断言全过、打印 ALL PASS 后进程仍空转不退出，外层 `timeout` 判 124 误报"挂起"。battle_stage_switch_test 曾因此被误判超时（13 断言全过却 EXIT=124），补 `engine:Exit()` 后 3/3 稳定 EXIT=0。排查测试"卡住"时：先看日志尾部是否已有 `ALL PASS`——有则是缺退出而非死循环；再用 `git stash` 二分改动确认与逻辑无关。
- [scope:project] 给敌人加运行时强化（Boss 词缀等）要用**按 chapter/difficulty 的确定性分配**（`pickAffixIds` 用 `((chapter-1)%n)+1` 起始轮转，零 `math.random`），否则采样/回归测试无法复现、平衡 A/B 对照失去基准。确定性 = 可测 + 可复现 + 玩家同关同体验。
- [scope:project] Boss 专属机制/词缀**不要进关卡推荐战力采样链路**：推荐战力采样打的是每章 stage1（无 Boss，Boss 只在 stage5 首通刷），词缀只作用 `unit.isBoss` 单位，天然不影响采样，StageRecommendPower 无需重跑。给 Boss 加机制时先确认采样入口（BattleLab.runSingle→BattleTriDriver）与真实战斗（BattleStageLoad）两条链路都接线，否则 lab 平衡验证与线上不一致。
- [scope:project] 系统模块对战斗上下文（`BattleCombat.dealDamageToUnit`/`BCS.ctx` 等）的依赖，在独立测试里会因缺上下文报 "attempt to call nil" 或 "getAllies nil"。解法：把外部依赖函数设成**可注入参数**（`onBossDamaged(boss,attacker,dmg,dealDamageFn)`，dealDamageFn 默认走真实实现、测试传 mock），既保持生产链路不变又可离线单测。
