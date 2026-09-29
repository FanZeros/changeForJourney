# versions — 版本历史(最新在最上面)

> ⚠️ GitHub Release `win64-v1.0.2` 上的 zip 为 2026-09-14 内容(462.5MB),落后当前代码——再交付前需用最新 dist 重打(见 electron-shell/README.md)。

| 版本 | 日期 | 摘要 |
|------|------|------|
| v2.83-remove-church-frames | 2026-09-29 | 删除未绘制的转职彩框 UI_TFWBK 五色、标题底 UI_ZBT1、天赋背景 UI_JTTF_BJ/BJGY。光晕和滑块保留。 |
| v2.82-remove-town-tag | 2026-09-29 | 删除未引用的城镇标签底 UI_CZ_BQ。UI_WORLD_BG 与 UI_CZ_BJ 仍作横屏和城镇背景。 |
| v2.81-remove-old-nav | 2026-09-29 | 删除未使用的旧导航图 ICON_GN_2-5、ICON_GN_BAN。正式导航已是矢量。词缀等级标 ICON_CZBZ 保留。 |
| v2.80-remove-recruit-glow | 2026-09-29 | 抽卡结果不再显示 SR/SSR/UR 品质光框 UI_PZG，并删除这三张图。 |
| v2.79-remove-old-frames | 2026-09-29 | 删除未使用的旧品质框 UI_ZBTS_1-6 与卡底 KP_TY_N/R/SR/SSR/UR。卡底已改矢量绘制。 |
| v2.78-remove-stat-icons | 2026-09-29 | 删除六维属性图标 ICON_SX。雷达图只画文字，去掉只加载不绘制的句柄。 |
| v2.77-remove-unused-icons | 2026-09-29 | 删除未引用的排行榜冠亚季图标和宝箱图标 ICON_PHB_TOP1-3、ICON_BX。 |
| v2.76-remove-unused-spine | 2026-09-29 | 删除未加载的天赋背景 Spine UI_SPINE_TFBJ 整套及清单条目。其余 Spine 特效仍在使用。 |
| v2.75-remove-rank-icons | 2026-09-29 | 删除未使用的段位图标 ICON_DW_1-8 及 AssetManifest、暗黑合图清单引用。 |
| v2.74-boss-art-arcs | 2026-09-29 | 困难首通追加怪 1005/1006/1007 暂用帝江/朱厌/巴蛇正式卡面。投掷物按同时在飞的数量左右分道、分三层弧高，并错开飞行时间。 |
| v2.73-bag-equip-clip | 2026-09-29 | 仓库装备格滚到标题或底栏时按格子裁切，穿戴者头像不再盖住黄线、稀有度和批量分解；装备标题、黄线和稀有度筛选上移。 |
| v2.72-march-enter-offline-sync | 2026-09-29 | 前进进入下一场不再重播己方入场滑入；离线奖励的队员升级与物品获得同时开始显示。 |
| v2.71-panel-title-line | 2026-09-29 | 矢量面板标题金线两端内收，菱形不再顶出面板外沿。DarkIcon.drawNine panel 一处生效，所有弹窗标题饰线一起变短。 |
| v2.70-button-text-gold | 2026-09-29 | 可点按钮旧绿字改为金黄 #FFD666：铁匠分解/强化/一键强化/洗练、强化确认、装备穿戴、神器合成与置换、转职「已拥有」。禁用态仍为棕色 #8d5f41。 |
| v2.69-equip-drag-hidden-tab | 2026-09-29 | 修复不显示配装页时从左侧仓库拖装备仍能不可见地拖入右栏原装备位的 bug：EquipCrossDrag 门控从「非觉醒页」收紧为「必须配装页」（新增 CharacterDetail.isEquipTab，tryDrop/draw 两处同步）；属性/转职页拖装弹「请先切到配装页」且不发 EQUIP_ITEM。LSP 0 Error + 回归 ALL PASS + 官方 Build + dist 验证。 |
| v2.68-remove-title-deco | 2026-09-28 | 批量移除 5 个页面（背包/神器背包/神器宝箱×2处/商城/酒馆商店）标题栏下方黄色「菱形+横行+菱形」装饰图 UI_JJC_BTBJ.png 的绘制/加载/常量；LevelUpPopup 弹窗文字底图仍用同图故保留资源与清单条目。LSP 0 Error + 回归 ALL PASS + 官方 Build 成功 + dist 验证。 |
| v2.66-first-damage-fade | 2026-09-28 | 修复首个伤害飘字显示延迟：BattleDraw.drawFloatingTexts 淡入曲线从 10 帧(0.33s, frame=0 时 alpha=0 不可见)缩到 3 帧(0.1s)，与即时的受击闪烁/音效同步。淡出段不变，对所有飘字类型生效。 |
| v2.55-shield-scaling | 2026-09-28 | 护盾成长层：护盾锚定最终HP×8% + 六围派生每级+5%（`AD.SHIELD_SCALING`，recalc §5.5），修复中后期护盾占比塌陷（敌人雷神 Lv345 护盾 821→2.56e15=HP的8%）；无盾敌人门控不加盾、enabled=false 一键回退；15断言回归 + 官方战力测试 + BattleLab A/B（胜局不翻盘、败局存活+26%）。设计文档 `docs/护盾成长层设计.md`。 |
| v2.55-docs-cleanup | 2026-09-28 | 文档整理：11 份已完成/过时规划归档至 `docs/archive/`（加归档头）；修订剧情总表（教堂神器登记文案、SCENARIO_82、触发链改 StoryPlayer、补 55-57 摘要）、memory-index（boot/Standalone 入口、情景 1~82、待办过期项）、低差异规划（三批全部落地标注）、套装规划（P1-P3 落地、转职入口迁移说明）与本文。 |
| v2.55-battle-reset-diff | 2026-09-28 | 编队布局未实质改变（只动其他队/原位放回）不再重置三行战斗；CharacterHeroSync 按队 diff 后选择性失效签名。 |
| v2.55-no-team-hide-enemies | 2026-09-28 | 无编队的战线完全不显示敌人（血条/名字也隐藏）；奖励弹窗跟随触发面板显示在左/中/右栏并接收对应输入。 |
| v2.55-talent-more-paths | 2026-09-28 | 天赋星图新增 16 条双向连通边（含顶部 1-2 直连），形成多环路可选路径；UI 与服务器判定同源 TalentNodeDefs。 |
| v2.55-church-badge-artifact | 2026-09-27 | 教堂角标只看神器可合成（绿箭头），移除转职红点；转职入口已迁角色详情页。 |
| v2.55-reward-close-anywhere | 2026-09-27 | 合并远端 workspace926；奖励弹窗可被任意点击关闭（面板外/行外点击不再悬挂）。 |
| v2.55-button-brown-disabled | 2026-09-27 | 全 UI 统一：按钮条件不满足时文字棕色 0x8d5f41，满足时亮色（23 个文件）。 |
| v2.55-church-story-rewrite | 2026-09-27 | 教堂剧情重写为神器登记/嵌槽（祝福已不存在）：情景 24-30/41 文案更新。 |
| v2.55-story-82-shard | 2026-09-27 | 新增情景 82：首通 2-5(205) 后大狗嚼剧情发碎片×60，领奖后自动打开角色详情觉醒页引导升潜能。 |
| v2.55-sweep-autoclose | 2026-09-27 | 扫荡奖励弹出时自动关闭扫荡弹窗；副本扫荡奖励同时自动离开副本页，避免奖励被模态页盖住。 |
| v2.55-reward-autoscroll | 2026-09-27 | 奖励内容超高时弹窗自动滚动到底（cascade 逐件跟随 + 非 cascade ease-out）；大数字徽章字号自适应缩小。 |
| v2.54-workspace926 | 2026-09-27 | 新建 workspace926，合入 workspace925 与 feat926/character-drag-save、cleanup-unused-panels、remove-unused-diary、artifact-audit、battle-lab。 |
| v2.53-offline-save-reliability | 2026-09-27 | 修复离线经验空槽摊薄与存档写入失败后重试。直接覆盖中断安全与损坏存档备份仍待验证。 |
| v2.53-cleanup-unused-panels | 2026-09-27 | 删除四个无入口旧界面、专属接线及 14 张图片；保留功绩/签到数据/GM 配置/遗物奖励。 |
| v2.52-character-drag-save | 2026-09-27 | 修复英雄存档双层恢复丢名册、右栏跨栏拖拽头像假消失与跨队编队同步丢人。 |
| v2.52-remove-unused-diary | 2026-09-27 | 删除旧日志页及失效引导/页签/启动引用，消除 UI_RZ 五图启动加载错误。 |
| v2.52-artifact-audit | 2026-09-27 | 神器规范按实际 4×3 结构和抽取规则修订；隔离并行战线状态、修复亡魂计时/审判叠层/闪避衰减，通天塔按逐名阵亡拦截。回归 24 PASS。已合入 workspace926。 |
| v2.54-power-calibration-samples | 2026-09-27 | 校验模板掉落等级范围并扩样至战士/法师/游侠、101–103、两个种子窗口及双人队伍；合法 Lv.1 同战力力量/秘识装备战士 101 胜场 40/40 vs 14/40（另种子 40/40 vs 10/40），正式战力公式未改。纠正 v2.53 的 `C10`/`C4` Lv.1 对照超出掉落等级范围，不可作为正常掉落平衡证据。已合入 workspace926。 |
| v2.53-power-calibration | 2026-09-27 | 无存档的确定性普通装备 A/B 同种子战力校准报告；历史演示 `C10`/`C4` 用于 Lv.1 英雄超出两模板 28 级掉落下限，仅说明估值机制，不可用于掉落平衡结论。已合入 workspace926。 |
| v2.52-battle-lab | 2026-09-27 | 独立进程交互工作台 + 批量 JSON 测试，真实三行战斗驱动、固定种子、多局胜负与逐英雄统计。已合入 workspace926。 |
| v2.64-boss-affix | 2026-09-28 | `feat926/battle-lab`：Hard+ Boss 真差异化词缀系统。v2.63b 调查确认 Hard Boss 纯角色复用零专属机制，本版落地机制层：新增 `config/BossAffixConfig.lua`（6 词缀：守护之盾/强化体魄/狂暴姿态/暴怒/生命汲取/荆棘之体，base+perTier×难度tier(hard=1..annih5=14) clamp 到 cap；数量阶梯 tier≤2→1/≤5→2/else→3；`pickAffixIds` 按 chapter 确定性轮转（无随机，可复现可测）；Normal 无词缀）+ `systems/BossAffixSystem.lua`（静态注入 ENERGY_SHIELD/MAX_HP(同步当前血)/ATK_SPEED(重算 atkInterval)；tick 驱动 regen 每秒回血与 enrage 40% 血线一次性触发 DMG_BONUS+ATK_SPEED+横幅；`onBossDamaged` 荆棘反弹 dealDamageFn 可注入便于测试，防重入 `_thornsReflecting`）。接线 5 处：BattleStageLoad（首通 onStageLoad+applyToBosses 战场+队列，非首通 clear）、BattleSceneTick（isFirstClear+hasAffixes→tick）、BattleCombat.performAttack（curTgt.isBoss→onBossDamaged）、BattleScene UI（词缀行绯红 235,96,96「首领·」前缀与地图词缀合并渲染 + y=608 暴怒横幅）、BattleTriDriver（lab 首通同链路，保证阈值采样/battle-lab 一致模拟）。Boss 词缀不进 StageRecommendPower 采样（采样打 stage1 无 Boss）。测试：`boss_affix_test.lua` 37 断言 + `boss_affix_smoke_test.lua` 12 断言（真实 BattleLab.runSingle 打 3105/3405/3205/805，确认实战中暴怒触发）ALL PASS；平衡性 A/B 对照（warden_shield Δwin+0pt / thorns Δwin+0pt Δtime+1.8s / enrage Δwin-12pt）确认词缀温和不碾压（调参用一次性脚本 balance_check 已删）。回归：recommend 24 / inheritance 9 / 切关 13（修 battle_stage_switch_test 缺 `engine:Exit()` 导致断言全过后引擎空转假挂起，3/3 稳定）ALL PASS；LSP 287 文件 Error=0；官方 build 成功。 |
| v2.63b-hard-boss-fix | 2026-09-28 | `feat926/battle-lab`：困难难度 Boss 调查 + 2 处配置异常修复。调查结论：Hard 23 章 Boss 与 Normal 完全复用同 bossId（无任何专属机制，isBoss 只影响 UI 红字/出场位置/套装攻条削减 0.2vs0.6/一个天赋判定），差异仅 monsterLevel 24..46 数值缩放。修复：①3105(困难·断魂裂谷8-5) bossId 22→28——罴是 quality=1 普通怪，全游戏 345 个章 Boss 中唯一非 q5，HP 只有应有值(黄能@ml31)的 5.7%，疑似 2**8**→2**2** 手误；②Hard ch10 章名「荒芜高原」→「悬魂瀑布」(5 关)、3305 bossId 52→25——其余 14 难度该章均为悬魂瀑布+当康，Hard 是旧版残留孤例。修复后全 345 章 Boss 品质 100% q5、Hard 与 Normal 章名/Boss 0/23 差异。回归：inheritance 9 + recommend 24 + 切关 ALL PASS，官方 build 成功。 |
| v2.63-hard-sampling-icon | 2026-09-28 | `feat926/battle-lab`：①battle-lab 采样扩到 Normal+Hard 46 章首关（ml 1..46 真实重跑，46/46 收敛），拟合模型转 quadratic R²=0.9526，实测关翻倍到 230、外推段 ml47..92（extrapCap 92）；②修复实测→外推衔接倒挂（二次曲线 pred(47) 低于 ml46 实测终点）：外推段取 max(曲线, 前章×1.02) 单调续接；③推荐战力 UI 图标化：「推荐 N/推荐≈N」文字改 DarkIcon power 火焰图标+纯数字，≈ 取消（外推关蓝灰数字色区分），五语死键 rec_power/rec_power_approx 与 i18n_rec_power_test 清理。stage_recommend_test 重写 24 断言（偏差上限放宽 12%→40%，Hard 段采样噪声保序压平代价）+ inheritance 9 断言 + 回归全绿 + build 成功 + LSP Error=0。 |
| v2.62-rec-power-monotonic | 2026-09-28 | `feat926/battle-lab`：推荐战力三修正。①章间倒挂（ml13<ml12/ml17<ml16/ml21<ml20 实测回落）→ 拟合脚本加 PAVA 保序 + ×1.02 最小梯度，章间严格递增（修正幅度 ≤12% 测试锁死）；②章内 5 关同值 → stage 2..5 向下一章首关 0.2/0.4/0.6/0.8 插值取整到 5；③全 15 难度 90 处章节与上一章怪物零重叠 → 新增 `_proc/inject_chapter_inheritance.py`（全局 chapter 链，x-2/x-4 关注入上一章高频普通怪，types<3 追加/==3 替换末位，不改总怪数），共注入 180 关清零。`stage_recommend_test.lua` 重写 21 断言 + 新增 `stage_inheritance_test.lua` 9 断言 ALL PASS；回归全绿（i18n 28/切关/边界/主入口/官方 build/LSP Error=0）。正式战力公式未改。 |
| v2.61c-rec-power-i18n | 2026-09-28 | `feat926/battle-lab`：推荐战力五语词表。`core/I18n.lua` 的 `T` 键值表五语块各加 `rec_power`/`rec_power_approx` 两键（简推荐/繁推薦/英 Rec./日推奨/韩추천 + ≈，共 10 条），沿用 `expedition_lv` 的 `{0}` 占位符范式。关键：动态数字串走 `I18n.t(key,n)` 键值替换而非 draw-hook 原文查表；StageSelectDialog 已改用 `I18n.t`。译后串再经 hook 查不到原样返回无二次翻译。新增 `tests/i18n_rec_power_test.lua` 28 断言 ALL PASS，LSP 0 Error，主入口 validate lua_errors=0，切关回归 ALL PASS。 |
| v2.61b-stage-recommend-ui | 2026-09-28 | `feat926/battle-lab`：推荐战力接入选关弹窗显示（**玩家可见**）。`StageSelectDialog` 中栏关卡行左中新增「推荐 N」20 号小字：实测关与玩家总战力比较着色（达标绿/不足红/未知中性）、外推关「推荐≈N」蓝灰、ml>46 无数据不绘制；未解锁行降透明度同显。只读展示无门槛，正式战力公式未改。主入口 validate lua_errors=0（资源缺失为 sparse checkout 环境噪音）、切关回归 13 PASS ALL PASS、LSP 0 Error。五语词表与真人视觉验收待做。 |
| v2.61-stage-recommend-power | 2026-09-28 | `feat926/battle-lab`：关卡推荐战力标定。新增 `tests/battle_lab_threshold.lua`（开荒三人组、首通、12 局定种，对 Normal 23 章节首关二分搜索 winRate≥50% 阈值等级，23/23 收敛：ml1/318 → ml23/2195）+ `_proc/fit_stage_recommend.py`（线性/二次/指数择优：官方战力指数 R²=0.9715、预估二次 R²=0.9705；实测范围内用实测阈值，ml>46=采样上限×2 不生成条目防指数发散垃圾值）→ 生成 `config/StageRecommendPower.lua`（230 关有推荐：115 实测+115 外推 x=true；`SRP.get/getEstimate/model`）。新增 `tests/stage_recommend_test.lua` 15 断言 ALL PASS，LSP Error=0，回归全绿（边界/生产接线/切关/默认 lab 20/20 v1）。纯数据模块无 UI 接线，正式战力公式未改。 |
| v2.60-off-factor-cross-band-validation | 2026-09-28 | `feat926/battle-lab`：OFF_FACTOR 跨难度带验证。新增 `tests/battle_lab_fit_expand.lua`（63 组：三职业 × L8/L16/L24 三带 × 武器等级/饰品变异）+ `fit_power_estimate.py --mode expand`（按 band 分桶岭回归 + 可信桶 off 波动汇总）。结论：跨带混池不成立（ALL R²=-5.5）必须分带；magical 三带 R²=0.63/0.68/0.96 全可信，off[phys]=0.33/0/0.028 均值 0.119≈0.10 → **OFF_FACTOR=0.10 跨带稳定，维持不变**；physical 三带 R² 均低（战士 DPS 被天赋触发主导）无法回归标定，方向性由 A/B 实测保证。系数值零改动，回归全绿。 |
| v2.59-power-estimate-production-wiring | 2026-09-28 | `feat926/battle-lab`：分项计价预估生产接线（**玩家可见改动，默认关闭**）。`CharacterPower` 抽出共享 `buildHeroAttrs`，官方 `calcHeroPower` 公式/数字不变，新增并列 `calcHeroEstimate`（预估=CPE 基础+觉醒+神器），经 CharacterPanel→Detail→Draw 注入；卡面战力下方「预估 N」副行由 `SHOW_ESTIMATE` 控制、默认 false（系数未跨全阵容标定、本环境无法截图验收），真人验收后 `Draw.setEstimateVisible(true)` 开启。新增 `tests/character_power_estimate_test.lua` 9 断言 ALL PASS（战力不回归 106/479、预估>0、未知英雄不崩、管线可重复），主入口 validate lua_errors=0，边界/切关/默认 lab 全回归。玩家数值零变化。 |
| v2.58-healer-coefficient-fit | 2026-09-27 | `feat926/battle-lab`：治疗系数数据驱动拟合。新增 `tests/battle_lab_fit_healer.lua`（22 组牧师采样）+ `fit_power_estimate.py --mode healing`（HPS 口径、按 healTakenRatio 剔除需求截断饱和）。关键发现：治疗=min(供给,需求)，304/305 阵亡带全饱和（W68@17→32 HPS 24.0→23.6 几乎不动），仅 303 超时带 8 组非饱和可拟合。结果 R²=0.32、输出组系数≈0.48 → **确认初值 HEALER_ATK_FACTOR=0.5 与数据一致并保留**。回归全绿、拟合确定性复现，正式公式未改。至此两系数均有数据依据。 |
| v2.57-power-estimate-fit | 2026-09-27 | `feat926/battle-lab`：分项计价系数数据驱动拟合。新增 `tests/battle_lab_fit.lua`（31 组败局带采样，新 API `Lab.runSingle` 单方案跑）+ `_proc/fit_power_estimate.py`（岭回归、非负截断、剔除饱和样本）。方法论：败局总输出被存活时间混杂（physical 总输出口径 R²≈0.03），改 DPS 口径后 physical R²=0.43 / magical R²=0.52；可信拟合异系攻击系数=0 → `OFF_FACTOR` 0.25→0.10（保留小正值防显示归零），方向断言复验更清晰（战士 128>122、法师 126>119）。healing 拟合不成立（R²<0，healer 局全超时）保留 0.5 待专属采样。报告新增 heroPowers[].groups 四组分解。回归全绿，正式公式未改。 |
| v2.56-power-estimate-prototype | 2026-09-27 | `feat926/battle-lab`：分项计价战力原型 `systems/CombatPowerEstimate.lua`（lab-only，正式公式未改）——与官方同底座，按英雄伤害大类给 phys/mag/heal 属性区别系数（异系 0.25、治疗系输出 0.5）；BattleLab 报告新增 teamEstimate/heroPowers.estimate/category/delta.teamEstimate，CLI 输出预估。方向验证通过：战士同战力 160 预估力量 133>智力 128（实测 3/40 vs 0/40）、法师同战力 112 预估智力 85>力量 83（实测输出 287 vs 193）；边界测试第 9 节 8 断言 + 旧入口/切关回归 ALL PASS。系数未拟合，仅方向性参考。 |
| v2.55-battle-lab-boundary-samples | 2026-09-27 | `feat926/battle-lab`：补齐校准边界样本——新增 `tests/battle_lab_boundary_test.lua`（60+ 断言覆盖 `Lab.prepare` 全部拒绝分支与钳制/levelRange/ascendLevel 边界，ALL PASS、自带退出）；真实边界校准 4×40 局：tier1 上边界 Lv7 302 双侧全胜、303 双侧全败（难度悬崖），tier2 下边界 Lv8/303 非饱和样本同战力 160 力量戒 3/40 vs 智力戒 0/40（种子 3926 复验 1/40 vs 0/40），力量饰品输出+333/承伤-55，方向与 v2.54 一致。正式战力公式未改，仅推任务分支。 |
| v2.54-power-calibration-samples | 2026-09-27 | `feat926/battle-lab`：校验模板掉落等级范围并扩样至战士/法师/游侠、101–103、两个种子窗口及双人队伍；合法 Lv.1 同战力力量/秘识装备战士 101 胜场 40/40 vs 14/40（另种子 40/40 vs 10/40），正式战力公式未改。纠正 v2.53 的 `C10`/`C4` Lv.1 对照超出掉落等级范围，不可作为正常掉落平衡证据。 |
| v2.53-power-calibration | 2026-09-27 | `feat926/battle-lab`：无存档的确定性普通装备 A/B 同种子战力校准报告；历史演示 `C10`/`C4` 用于 Lv.1 英雄超出两模板 28 级掉落下限，**仅说明估值机制，不可用于掉落平衡结论**；详见 v2.54 合法样本。LSP/Build、同方案复现、旧入口与切关断言通过。仅推任务分支。 |
| v2.52-battle-lab | 2026-09-27 | `feat926/battle-lab`：独立进程交互工作台 + 批量 JSON 测试，真实三行战斗驱动、固定种子、多局胜负与逐英雄统计；LSP/Build/离屏界面/胜负超时及回归验证通过。仅推任务分支，不推 workspace。 |
| v2.51-equipment-detail-popup | 2026-09-26 | workspace925 装备详情按左右栏反向展开，对比卡继续排在外侧；套装效果独立分区，增加字号、换行和点击热区。LSP/Build 通过，视觉预览待验收。 |
| v2.50-workspace925 | 2026-09-25 | workspace925 补合立绘、配装布局、功绩边框、失焦挂机，以及 integration 的本地 Electron 打包校验。配装拖拽仍以 925 为准。 |
| v2.49.2-local-electron-pack | 2026-09-24 | Electron 本地专用 `--local-dist`：校验 dist 中 Lua 与当前源码一致，禁止下载快照替换。 |
| v2.48-electron-background-trial | 2026-09-24 | Electron 离线包 BrowserWindow 关闭后台节流；Windows 失焦/最小化实测待做。 |
| v2.48-pc-obfuscation-trial | 2026-09-24 | 外部副本保守混淆单模块；官方构建与隔离测试通过。整游戏原版已有启动错误，正式 PC 包未发布。 |
| v2.47-hero-equip-layout | 2026-09-24 | 属性页隐藏装备/批量按钮保留角色切换；配装页隐藏切角、批量按钮置顶，下方内容下移 160px 预留词条区域。 |
| v2.47-pc-obfuscation-review | 2026-09-24 | 新分支核查 PC 构建：Lua 资源明文，Electron 原样打包；确认混淆试验边界及预览构建路径。 |
| v2.47-background-idle-research | 2026-09-24 | 从 workspace924 开独立分支调研失焦挂机；重建可用预览，明确网页隐藏页需离线补算、Electron 可试关闭后台节流；未改玩法。 |
| v2.44-lootbox-rarity | 2026-09-24 | 遗匣默认展示确定装备；六档稀有度筛选，范围内领取/回收。 |
| v2.43-lootbox-left | 2026-09-24 | 遗匣改城镇左栏地点；满包奖励完整保管；滚轮按鼠标所在区域滚动。 |
| v2.42-workspace924 | 2026-09-24 | 从当前集成线开 workspace924，补合天赋分支新增的古树图标与星图铺满。 |
| v2.41-stable-frame | 2026-09-24 | 横屏画布固定 1920x1080，半屏/全屏只等比缩放，布局不再随窗口重排。 |
| v2.40-merge-today | 2026-09-24 | 合入今日分支：首通奖励、遗匣/仓库滚动、天赋星图加宽与终焉环。 |
| v2.39-preview-args | 2026-09-24 | Windows 前台启动补上入口和 tapcode_dir，避免只传 -skip_login 时提示 Start。 |
| v2.38-default-start | 2026-09-24 | 不带参数默认等于 --start，Windows 前台开窗口并跳过扫码。 |
| v2.37-skip-login | 2026-09-24 | Windows 前台启动补上 -skip_login，不再弹出 Tap 扫码登录。 |
| v2.36-win-foreground-runtime | 2026-09-24 | Windows --start 跳过隐藏 PowerShell supervisor，项目目录前台启动 UrhoXRuntime.exe。 |
| v2.35-four-hero-scenario | 2026-09-23 | 老六/哈基米/加载中/高ping战士补入队与闲聊情景。首次获得或第一次打开详情播放，闲聊每局一次。 |
| v2.34-local-preview-log | 2026-09-23 | 本地 --start 不再吞 npm 日志：流式输出、单步超时、未绑定先失败。不是云端 Build。 |
| v2.33-integrate-20260923 | 2026-09-23 | 从 workspace 开 integrate/20260923，合入今天滚轮/i18n、四人角色/SE、未解锁职业标，以及 workspace923 的一键脚本修复。 |
| v2.29.6-exp-text | 2026-09-23 | 详情页经验条在等级后显示当前/目标经验。 |
| v2.29.5-roster-title | 2026-09-23 | 「远征团」对齐详情页角色名 Y=995（与点进去名字同位置）。 |
| v2.29.4-se-latency | 2026-09-23 | UI 点击按下即播；远程攻击 SE 改命中时播，去掉听感延迟。 |
| v2.29.3-stage-progress | 2026-09-23 | 修关卡进度文案：高难不再重复难度前缀；章节名去掉「困难·」。 |
| v2.32-i18n-names-letter | 2026-09-23 | 补漏翻 + 角色名/称号/天赋/开场信五语（信达雅、不露真名）。I18nDictExtra。 |
| v2.29.2-se-short | 2026-09-23 | 战斗 SE 去掉过长条目（阈值约 0.85s）；哈基米不用 Cat；音量 5%。 |
| v2.31-noto-cjk-kr | 2026-09-23 | 主字体换成 Noto Sans CJK KR Bold（OFL），韩文可显示。对比图 `assets/image/font_compare_kr.png`。 |
| v2.29.1-se-gain | 2026-09-23 | 新 SE 太响，Effect 通道压到原音量 10% 试听。 |
| v2.29-se-pack | 2026-09-23 | 用 RPG Maker SE 包替换全部 UI/战斗音效；#18/#19/#24/#25 补独立攻击 SE。分支 feat/four-meme-heroes。 |
| v2.30-i18n-nvg-hook | 2026-09-23 | 全 UI 接入：I18nDict 约 500 条 + nvgText 运行时查表；梗名/剧情不翻。标题语言改为左下弹出。 |
| v2.29-i18n-rightequip-tune | 2026-09-23 | 扩 HUD/城镇/配装五语词表；右键不可穿提示、已穿卸下、音效+Toast。分支 `feat/wheel-rightequip-i18n`。 |
| v2.28-four-meme-heroes | 2026-09-23 | 接入老六/哈基米/加载中/高ping战士（替代立绘）。分支 feat/four-meme-heroes。 |
| v2.28-wheel-rightequip-i18n | 2026-09-23 | 滚轮补齐 + 右键快速装备 + 顶栏远征等级 + 五语切换。分支 `feat/wheel-rightequip-i18n` 已 push。 |
| v2.27-workspace-integrate | 2026-09-22 | 整合今天三线到 workspace：overlays 星图剔除+CharacterPower、docs 套装/六契/1.5竖屏天赋树、rename 远征文案。已推 origin/workspace。 |
| v2.26-rename-expedition | 2026-09-22 | 玩家可见文案：冒险等级→远征等级、冒险家→远征队员、冒险招募券→远征招募券、冒险日志/奖励→远征日志/奖励。内部键名不变。分支 `feat/rename-adventure-to-expedition`。 |
| v2.25-refactor-three-more | 2026-09-22 | Talent 减伤/复活、Church 槽位动画、Blacksmith 结果转发。Talent 1116 / Church 1004 / Blacksmith 1337。 |
| v2.24-refactor-four-extracts | 2026-09-22 | Church 输入/名单 + Talent 攻前/受伤 + Blacksmith 输入。Church 1060 / Talent 1315 / Blacksmith 1384。 |
| v2.23-refactor-church-draw | 2026-09-22 | ChurchPage drawPageImpl 抽到 ChurchDraw。ChurchPage 1416 / ChurchDraw 568。 |
| v2.22-drop-guild-shell | 2026-09-22 | 删版本不一致弹窗与公会 Handler/Service；城镇卸空回调。GuildConfig 排行保留。 |
| v2.21-drop-server-select | 2026-09-22 | 卸掉 StartScreen 选服条与 ServerSelectPanel；点击直接进游戏。 |
| v2.20-drop-mp-ui | 2026-09-22 | 删除公会页/选角/加载页等仅多人 UI；消息处理器解绑。 |
| v2.19-drop-multiplayer-shell | 2026-09-22 | 去掉多人入口，删除 Client/Server 联网壳；单机仍用 LocalActionBridge+server Handler。 |
| v2.18-gameaction-local | 2026-09-22 | 单机 sendAction 走 GameAction→LocalActionBridge，UI 不再加载 Client。 |
| v2.17-refactor-market-input | 2026-09-22 | Market 点击/拖拽/滚轮抽到 MarketInput。Market 1402。 |
| v2.16-refactor-town-draw | 2026-09-22 | Market/Blacksmith drawPageImpl 抽到 MarketDraw/BlacksmithDraw。Market 1589 / Blacksmith 1533。 |
| v2.15-refactor-four | 2026-09-22 | onAfterAttack/ClientUpdate/BattleScenePhases + 市场商品卡/铁匠装备槽。TalentManager 1728 / Client 1348 / BattleScene 1765。 |
| v2.14-merge-workspace | 2026-09-22 | 合并 origin/workspace（中缝C款/ICON_UP/礼拜堂标签/ZBBJ/791 meta）。冲突仅 Standalone.lua，SEAMBAR_ASPECT 补进 Horizon。@ fa7a775 |
| v2.13-refactor-server-town | 2026-09-22 | ServerEnterGame + BattleSceneTick + 城镇页 DrawUtil 委托。Server 1693 / BattleScene 1890。@ 24eb755 |
| v2.12-refactor-four | 2026-09-22 | 连击Combo + loadStage + TAL.update + ClientRender。TalentManager 2838 / Client 1844 / BattleScene 2014 / BattleCombat 1637。@ 88ccd19 |
| v2.11-refactor-casualty | 2026-09-22 | BattleScene 抽出死亡补位/胜负到 BattleCasualty；2384→2154。分支 refactor/extract-battle-overlays @ ebc1db4 |
| v2.10-refactor-clientboot | 2026-09-22 | Client 抽出启动接线到 ClientBoot；2487→2143。分支 refactor/extract-battle-overlays @ a9c2566 |
| v2.9-refactor-talents | 2026-09-22 | TalentManager 再抽 Alex/Elwyn/Sera/Suhua；3276 行。分支 refactor/extract-battle-overlays @ 3e9920f |
| v2.8-refactor-anim | 2026-09-22 | BattleCombat 抽出卡牌动画到 BattleCombatAnim；修 Lua5.4 `\!` 启动崩 + ETS 依赖。分支 refactor/extract-battle-overlays @ a3f6930 |
| v2.7-awk3 | 2026-09-18 | 觉醒 7 阶压成 3 阶：粗暴/机制/进化，旧档 1–3→1、4–6→2、7→3 |
| v2.6-awk-extra | 2026-09-18 | 超模技改成觉醒1/4/7解锁，不再默认自带 |
| v2.5-talent-rework | 2026-09-18 | 8 个主技能按梗人设整段换机制 |
| v2.4-talent-rename | 2026-09-18 | 全员天赋改名+5 主技能机制对齐梗人设 |
| v2.3-electron-win | 2026-09-17 | Electron Windows 离线包：win-unpacked zip 461MB |
| v2.2-extra-talent | 2026-09-17 | 4 个混合追加技试点：衔骨图鉴/冰雕/分裂弹/预存复活 |
| v2.1-seam-back | 2026-09-17 | 三行模式隐藏页内重复返回键，只留中缝层 |
| v2.1-workspace | 2026-09-17 | 新工作区检出 origin/workspace@d790dc0；已 build 单机；等用户指令 |
| v2.0.1-electron-release | 2026-09-14 | Electron zip 462.5MB 覆盖上传 GitHub Release win64-v1.0.2（含暗黑建筑五件套/骷髅头Boss/阵亡紧凑/击杀进度%） |
| v2.1-wip | 2026-09-13 | 暗黑强梗试点(#4/#5)完成待验收;三层参考管线确立;交接文档部署 |
| v2.0 | 2026-09-13 | 卡面/立绘 v1 全量实装(浅灰白背景版,用户验收未通过);入队台词调研挂起 |
| v1.9 | 2026-09-13 | 名字二轮(黄桃龙/阿姨压/小黑子/真布诗人)+20 称号玩梗化+远征长替换 |
| v1.8 | 2026-09-13 | 对话全量重写(战斗 24 角色+剧情 73 情景)+"汪"→"叫!" |
| v1.7 | 2026-09-13 | 外祖父遗产信(LetterIntro)实装+世界观修正+视觉精修 |
| v1.6 | 2026-09-13 | 世界大背景(全窗口+7 页背景+27 关卡图)统一 |
| v1.5 | 2026-09-13 | 暗黑标题页(DarkTitleScreen 终焉之门版)上线,游戏内实拍验收通过 |
| v1.4 | 2026-09-13 | A 方案实装(#9/#11/#21 立绘+卡面),高清立绘导出管线 |
| v1.3 | 2026-09-13 | 20 张玩梗立绘三批生成(全部达标),双参考管线+暗黑前基准图 |
| v1.2 | 2026-09-12 | 角色总览图(引擎渲染);资产盘点(KTX 发现) |
| v1.1 | 2026-09-12 | 玩梗改名全量(20 角色+台词+剧情)+文本一致性 |
| v1.0 | 2026-09-12 | 玩梗匹配方案(联网调研)+用户拍板 |
