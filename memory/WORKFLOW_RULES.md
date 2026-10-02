# changeForJourney（终焉之门）项目工作铁律

> 强化记忆：以下规则在每轮任务中必须遵守。**每轮开始工作前先重读本节。**

1. **不能取消/退出任务**：必须持续推进直到完成。
2. **每轮完成后必须用 AskUserQuestion 提问下一步**：禁止以纯文本、总结或其他任何非 AskUserQuestion 的形式中断对话。这是硬性收尾动作，任何任务（包括纯调研）完成后都必须调用 AskUserQuestion。
   ⚠️ 强化记忆（用户多次重申）：任何一次任务完成（含 commit+push 之后）的最后一个动作必须是调用 AskUserQuestion 工具向用户提问下一步做什么。绝对不允许以普通文本消息结束回合。即使构建失败、测试失败、遇到阻塞，也要用 AskUserQuestion 给出处理选项。
3. **以新分支继续开发**：基于 workspace930 拉新分支开发，每次完成后 commit + push 到该开发分支；**禁止 push 到 workspace 或 workspace930 分支本身**（用户明确要求），通过 PR 合入。推送时显式指定工作分支，不强推、不擅自合并 PR。
4. **部署位置**：游戏项目必须直接位于 `/workspace` 根目录。仓库可直接检出到该目录；若使用独立克隆目录，构建前应把 scripts/assets/.project 等同步到根目录，不要产生嵌套游戏入口。修改代码后调用官方 build 工具构建。

## 首批实施交接（2026-10-03，基础链路＋关卡模板）

- 用户通过 AskUserQuestion 选择**繁中、英语、日语、韩语同步补齐，首批基础链路＋关卡模板**。开始改码前已合入最新 workspace930（`eee25ef`），仅记忆文件冲突，双方内容保留；工作分支仍 `dev/i18n-audit-20261002`。
- 新增 `scripts/core/I18nStages.lua`：23 地名、7 基础难度与 II..V 后缀组成 15 难度、终焉原名、章节与短进度严格整串识别。覆盖全部 1739 条关卡记录（含 14 座神殿）、1737 个不同原名；未知原文与资源路径回退，不修改配置源值。英文难度 `Normal` 通过 `I18n.difficulty` 独立于品质 `Common`，原号码与前导零保持。
- `I18n.lookup` 委托关卡模板并按语言限额缓存；新增 `I18n.format`（先译 printf 模板再格式化）；`I18n.t` 改一次匹配原模板，参数中的百分号/占位符不级联替换；词典加载失败输出关键日志，普通空译文回退，保留韩文序数「第」空串既有例外。新增 `nvgTextBoxBounds` hook，两个测量 API 变参和多返回值完整透传。
- 25 条关卡相关动态/状态词条四语同步（100 个目标译文），已核对 printf 占位符类型和顺序。显示接线包括小队/共享池、轮回过渡、终焉确认、挂机范围、宝箱当前进度、关卡功绩任务和套装筛选计数。源缓存/任务配置/奖励标题语义不写译文，关卡编号仍维持选关绝对章号与进度相对章号各自原契约。
- 选关章名先译再测量，长标题折行并限额缓存（256）；终焉完整名称最多四行，当前 SRP 没有终焉推荐条目，不误报其与推荐战力碰撞。KeywordText 本批仅加语言变更清缓存/弹窗/热区护栏，**尚未实现完整四语关键词拆段与英文词边界排版**。
- 回归：`i18n_foundation_test` **158 断言 ALL PASS，6956 个四语关名组合全量通过**；`i18n_display_boundary_test` **20 断言 ALL PASS**；既有 keyword_text、lootbox_set_filter、stage_inheritance（9）和 terminal_raid 全 PASS。首次基础测试的四条失败来自扫荡带空格进度，已修复并重跑通过，不隐藏失败过程。
- LSP：本轮修改/新增文件逐文件诊断 0 Error；全仓汇总有 47 条基线类型诊断（NVGcolor 推导与 CharacterRadar 类型），未擅改无关模块。官方 Build 在最终修改后成功；主入口 headless 运行完成 18/18 启动队列，测试 stdout 未见新增翻译加载错误。
- **视觉未验收**：离线截图文件实际为黑屏，已移除本轮无效视觉入口，不交付假截图；选关长名、四语弹窗与三行 HUD 仍须真实预览验收。Build 和逻辑回归不等于 UI 完整验收。
- **本轮覆盖口径**：关卡名由模板覆盖，并非把原 4292 总数全补齐。装备、属性、天赋、复杂富文本、剧情/梗名旧译文仍为后续批次。原始 4292 与类别归属差异尚无完整缺失清单，不能承诺总体归零。
- 完成后只推工作分支，`.project` 本地身份与构建生成差异不提交；不得直接推 workspace/workspace930、不强推、不自行合并 PR。先如实汇报本批结果，再调用 AskUserQuestion 选择真实预览验收或下一批模块。

## 本轮交接（2026-10-02，i18n 完成方式评估）

- **协作规则再次确认**：持续推进任务，阶段完成或遇到需要用户决策的阻塞时，先如实汇报，再调用 AskUserQuestion 给出明确选项。只提交和推送独立任务分支，不直接推送 workspace、workspace930 或其他基线分支；访问令牌不写入文件、记忆或 Git 远程地址。
- **本轮分支**：从 workspace930 的 `196beec48aa2c9d9990aebc9a67c04ae07074b27` 创建 `dev/i18n-audit-20261002`，仓库直接检出在 `/workspace` 根目录。本阶段仅调查翻译方案，不宣称已补齐翻译。
- **部署**：首次官方 Build 因 `local taptap identity conflicts with claimed database identity` 失败。用户通过 AskUserQuestion 允许仅本地重新绑定；原配置已备份在 Git 内部目录，清除旧 project_id/author/developer_id 后官方 Build 成功。构建生成的 `.project` 身份、语言默认值、meta 等差异不提交。构建前独立 LSP 查询为 0 Error；尚未完成真人画面与交互验收。
- **实际翻译机制**：游戏使用 `scripts/core/I18n.lua` 的自定义五语系统；`.project/i18n.json enabled=false` 是明确设计，不代表游戏没有多语言。`I18n.t` 每语种 52 个语义键；`I18nDict` 509 个原文键、`I18nDictExtra` 261 个，重叠 1 个，合计每目标语言 769 个原文键。`i18n/{lang}.json` 各 35 条，但自定义运行链不读取它们，单独补这些 JSON 不会补齐当前游戏页面。
- **4292 不是已验证的当前基线总数**：未找到可复现此总数的入库清单或扫描器。用户给出的类别按杂项约 250 计算合计 4080，与 4292 相差 212，必须先统一口径。关卡共 1739 条记录、1737 个不同名称，其中 1736 个不同名称未命中；1735 是扣掉其他模块也出现的黑棘林道1-1 后的独占缺失名数。装备 368 可复现为 353 个不同装备名加 15 个子类型，不是 368 件装备。天赋 290 的粗扫描混入日志续段和资源路径，节点名及效果原文去重缺失为 130+156=286。不能把所有含汉字字面量直接等同于玩家漏翻。
- **高重复类别压缩依据**：1725 条普通关卡名称实际由 23 个地名、15 个完整难度名和数字组合；另加终焉神殿名与格式规则，保守只需 39 个命名单元，再逐项覆盖 14 个终焉特例。若基础难度加罗马数字，命名单元还能降到 31，但需验证各语言语法。天赋未命中 156 个不同效果中，139 条为纯属性（80 单属性、59 多属性），17 条为复杂机制；单属性 80 条可归并为 33 种数字无关模式。只添加裸地名/属性字典不会自动翻译现有整串，必须接入显示入口。
- **已确认的显示链路缺口**：`I18n.lookup` 只匹配完整原文；遗匣/仓库选中后显示 `套装 · N`，最终绘制 hook 无法命中 `套装`。动态句子应先翻译模板再格式化，名称等参数也要在展示时翻译，不能只补词典。
- **长文与热区风险**：KeywordText 在翻译前按中文拆段折行，缓存键不含语言；套装说明也有先拼接再折行路径。自定义 hook 未覆盖 nvgTextBoxBounds，可能测原文高度而绘制译文。剧情打字机先截取中文前缀，整串 hook 无法正确逐字播放译文。应先本地化再测量、折行、打字，并让缓存随语言失效。
- **版本漂移**：当前 LetterIntro 的十二行信件与旧词典不匹配；雷电麦坤四语仍沿用旧闪电卖鸡译名。已有条目不等于内容正确，需列入旧译文复核。
- **保护业务数据**：套装归属依赖中文装备名规则，角色素材路径也依赖姓名；保持配置源名称、ID、资源路径、协议与存档键不变，只在显示边界本地化。不要全局替换中文，不要直接叠加启用引擎自动 i18n。
- **建议实施顺序**：①建立按原文去重、带来源/类别/四语言状态的玩家文案基线，并明确保留名单；②统一现有语义表与原文词表的术语，先补动态模板、翻译前排版与语言缓存回归；③关卡名按难度/地区/关号组合、重复属性效果按模板处理，特殊名独立词条，保持中文源值不变；④分批补短 UI、属性/职业、装备/天赋/词缀，再处理复杂机制、剧情与专名。
- **验收**：每批建议约 100–200 条去重原文，按模块分开提交；四语补齐与英文先行应由用户选择。每批核对缺键/空值/重复覆盖、占位符与富文本标记、未经许可的英文中文残留，并扩展现有 keyword_text_test、配装文字探针与视觉入口。需要真实字体确认折行、滚动、热区和切语言；普通战斗回归和 Build 成功不能替代翻译验收。
- **后续**：本阶段先交付调查结论；实现范围及目标语言通过 AskUserQuestion 决定。不得把规划记录视为翻译实现完成。

### 用户工作流确认（2026-10-02）

- 每轮汇报实际结果后，以 **AskUserQuestion** 具体选项询问下一步；已获明确授权的步骤持续推进，不擅自取消任务，也不忽略用户后来明确提出的停止要求。
- 分支排查必须区分“分支最新提交未被完整合并”和“实际功能尚未合入”，避免把合并后追加的记忆文档当作遗漏功能。
- PAT 不写入仓库、远端 URL、日志或长期记忆；用户在对话中公开过的凭据应提醒撤销并更换。
- 导入配置的旧项目身份与当前工作区冲突时，本地配置须与源仓库提交分开；不得将当前工作区的身份回写到共享仓库。

## 本轮整合确认（2026-10-02）

- 用户授权合入 `dev/level-select-hard-24-0930` 与 `workspace931`；使用工作分支 `integrate/workspace930-level-power-20261002`，通过 PR 合入 `workspace930`，不直接 push 基线。
- `integrate/workspace930-local-art-20261001` 本轮只读调研，未合并。有效待选项是离线收益全窗绘制与输入、三行升级弹窗绘制条件、语言按钮两列三行与玩家信息增高、城镇名牌微调；章节背景与部分 CG 已合入。不得整树覆盖觉醒新布局或批量恢复旧资源。
- 工作期间远端 PR #14 已由其他操作合入，最新基线同步至 `196beec`；本轮保留该装备预览与快速装备功能。
- 整合时保留“已嵌合”亮字规则，仅未满足条件使用灰蓝色；本地 `.project` 身份与构建配置不提交。
- 兼容修复：升阶 `ascBonus` 不按洗练后当前 value 裁剪；新魔化 quality=0 的有限正值读档保持、旧品质值仍纠正；腐化 JSON patch 数字索引恢复，确保净化能还原原词条及投入。
- 持续遵守每轮实际结果汇报后调用 **AskUserQuestion** 选择下一步；仅在用户明确授权的范围内推进。

## 历史状态（2026-10-01，仅供参考）

- 仓库：https://github.com/FanZeros/changeForJourney.git（凭据仅使用本次授权，禁止持久化）
- 活跃分支：`dev/930-scenario82-check`（PR #9，首通情景接线修复）；已合并：PR #6（装备详情UI+万单位）、PR #7（剧情落档）、PR #8（仓库/遗匣套装筛选）
- PR 创建方式备忘：GitHub API `POST /repos/FanZeros/changeForJourney/pulls`（PAT 认证 + 代理 http://127.0.0.1:1080），body 里 head=开发分支 base=workspace930；PR dirty 时本地 merge origin/workspace930 解冲突再 push

- 已完成任务10（2026-10-01，分支 dev/930-scenario82-check，PR #9）：**修复"首通205看不到大狗嚼剧情/碎片引导"（用户报告）**
  - 根因1（主）：0922 删联网壳（4e184304）时首通触发情景的接线丢失——原 ClientBoot.setOnFirstClear 里的 lastClearedStageId_ 赋值+NEXT_STAGE 链没搬进单机 StandaloneBoot，ClientMessageHandler:440 读该字段但单机无人赋值 → **所有首通情景（5-22/35-37/44-46/51-53/55-60/62/69/82）在单机永不触发**。进入类情景（41-43等走 BattleScene.loadStage）不受影响
  - 根因2：13df6a95 起客户端播放前预写 claimedScenarios（防中途退出重播），单机 PDM 与 ClientDispatcher 共享同一张 session 表 → 播完领奖被 BattleService 防重复"已领取"拦截，**即使情景播出奖励也发不出**
  - 修复1：`StandaloneBoot.setOnFirstClear` 落盘进度后直接 `StoryPlayer.onStage(clearedStageId,"clear")`
  - 修复2：`StoryPlayer.backfillCleared()` 新函数——扫 battle.clearedStages 把已首通未领情景补入队（救老档）；`Standalone.update` 在 postStartFlowDone_ 且 hasData() 后一次性调用（storyBackfilled_ 标记，清档重置）
  - 修复3：`ClaimScenarioReward(uid, scenarioId, preClaimed)` 拆 wrapper+core：防刷改用独立账本 `session.scenarioRewardsGranted`（**成功发放才记账**，失败可重试）；preClaimed=true 跳过 claimed 拦截；Standalone 领奖处传 preClaimed=true；ModuleRegistry session onLoad 补 granted 账本 cjson 字符串 key 修正
  - 新增回归 `scripts/tests/scenario82_firstclear_test.lua`（5组用例 ALL PASS：补播入队/preClaimed发60碎片/无preClaimed已claimed拒绝/账本防二次领取/未通关失败不记账可重试）；terminal_raid/hero_scenario_claim/equip_ascend/corrupt_convert 全 PASS；LSP 0 错误；build 通过
  - 注意：测试 mock 方式=覆盖 PDM.GetModule/ClientDispatcher.get 指向测试 modules 表（引擎 require 单例，覆盖全局生效），无需替换 require（真实 BattleService 可直接加载）

- 已完成任务9（2026-09-30，分支 feat930/warehouse-relic-set-filter，PR #8）：仓库/遗匣装备套装筛选（弹窗多选，品质+套装 AND 组合）
  - 新组件 `scripts/ui/widget/SetFilterDialog.lua`：12 套装+「无套装」多选弹窗，套装色圆点、勾选实时写回调用方集合表、清空/完成、模态消费全部输入；NONE_KEY="none"
  - `scripts/config/EquipmentSetConfig.lua`：新增 SET_ORDER 固定展示顺序 + orderedSetIds()
  - 遗匣 `LootBoxPage.lua`：state.setFilter；入口按钮「套装·N」(cx=190,cy=286)；rebuildSummary 品质+套装 AND；批量领取/回收透传 (qualitySet, setFilter)；状态行/确认弹窗/空态文案联动
  - 系统 `LootBoxSystem.lua`：claimAll/decomposeAll 新增第 4/3 参 setFilter（旧签名兼容；matchesSet 用 getSetIdForTemplate 判归属）
  - 仓库 `BackpackPanel.lua` + `BackpackGrids.lua`：decomposeState.setFilter；入口按钮 (cx=396,cy=610，紧凑布局 cy=325)；setChecked 注入网格过滤；弹窗打开时禁拖拽/hover/滚轮；⚠️ handleHover 与 0930 分解tab悬停委托有冲突，合并时保留双方逻辑（弹窗 isOpen 早退分支放最前）
  - `StandaloneBoot.lua`：claimLoot/decomposeLoot 接线透传 setFilter
  - I18nDictExtra 补 7 条五语词条；测试 `tests/lootbox_set_filter_test.lua`（24 断言 ALL PASS）；4 个既有回归全过；LSP 0 Error；build 通过
  - 该会话工作区部署方式：.git 直接在 /workspace 根（无嵌套克隆），git restore --source=HEAD :/ 恢复全部文件

- 已完成任务8（2026-09-30，分支 dev/ui-fixes-930a）：全游戏"万"单位改 k/M/B
  - `scripts/ui/battle/stage/SweepDialog.lua` getStageRewardStr：`%.1f万` → `NumberUtil.format(v)`（<10000 原样、10k/1.2M/3.4B 短表示）
  - `scripts/ui/dev/CEPanel.lua` 按钮标签"全资源+100万"→"全资源+1M"；`scripts/rules/gm/CEService.lua` toast 同步
  - 排查结论：游戏内动态数字大多已走 NumberUtil.format（k/M/B/T）；BlacksmithPage.formatCompact / BlacksmithRefine.formatShortNum 是自实现 k/M（非万，未动）；LootBox.formatNumber 是千分位逗号（非万，未动）；"万剑归宗/雷霆万钧/一剑破万法"等固有名词保留
  - LSP 0 错误；build 通过

- 已完成任务7（2026-09-30，分支 dev/ui-fixes-930a，PR #6）：装备详情 UI 三处修改
  - 装备详情名称不再拼接 "+N Lv.X"（大面板 drawEquipPanel + compact 小窗 drawCompactPanel 都改）：名称只显示纯名字，+N 升阶仍由图标右上角标展示，Lv 改为绘制在稀有度（品质色文字）下方 48px（大面板）/40px（小窗）；compactContentBottom 同步把小窗内容底部下移（+18→+58）防止新增 Lv 行与属性区重叠
  - 按钮收窄 + 改名"强化"：REF_ENH_BTN_W 410→300、COMPACT_BTN_W (BG_W-56=544)→300；按钮文本"前往洗练"→"强化"（大面板与小窗两处）；按钮显示门控沿用 TutorialManager.isBuildingUnlocked("smith")（铁匠铺未解锁不显示，满足"解锁了才显示按钮"）；顺手修正大面板 BF.begin 误传 REF_BTN_W/REF_BTN_H 为实际按钮尺寸
  - 中缝返回条消缝隙：StandaloneHorizon.seamBackList() 返回前统一对 dir=="left" 的条 cx-2px（往左收）、dir=="right" 的条 cx+2px（往右收），条与页面边缘重叠 2px 消除中缝空隙；seamHitAt 命中判定共用同一列表自动同步
  - 关键词系统去横线：KeywordText:draw 移除关键词下划线绘制（金色高亮与悬停加亮保留），删除 UNDERLINE_W 常量；keyword_text_test headless 回归 ALL PASS；三文件 LSP Error=0；build 通过
  - I18nDict 中"前往洗练"词条保留未删（其他语言包仍引用；nvgText hook 会把"强化"翻译为 D.en["强化"]="Enhance" 等，无需新增词条）

- 已完成任务5（2026-09-30）：**调研"角色点击详情一直显示剧情"**，报告见 `docs/角色详情剧情显示调研-0930.md`
  - 唯一入口：CharacterDetail.open/_switchHero → HeroScenario.onOpenHero，仅玩梗四人 18/19/24/25 生效
  - 根因：闲聊剧情 78–81 只记在**内存表 idleSeen_**（不落档），设计上"每局进程每角色播一次"→ 每次重启 build/预览后点详情必弹
  - 次生问题：showScenario 忙时 enqueue 进 pending_，但 pending_ 只在下次 onOpenHero/onRecruitResults 时才 drain（ScenarioDialogue 播完无广播）→ 延迟到"下次点详情"突然补播，体感每点必弹
  - 入队 74–77 已落档（markClaimed→claimedScenarios→Flush），跨进程只播一次；4a152ca8 已给 markClaimed 加 pcall 保护
- 已完成任务6（2026-09-30）：**用户选定方案A+C 修复**（PR #7 已合并进 workspace930，合并提交 67e67d69）
  - 方案A：`HeroScenario.playIdle` 改为查 `isClaimed(idleId)` 落档记录（闲聊终身一次），播出后 `markClaimed(idleId)`；idleSeen_ 降级为落档失败时的进程内兜底
  - 方案C：`ScenarioDialogue` 三处结束路径（dismiss 完成/large 播完/skip）`EventBus.emit("scenario_dialogue_finished")`；HeroScenario 模块加载时订阅该事件调 drainPending → 积压请求即时补播，不再等下次点击
  - **意外抓出真实 bug**：`local function drainPending()` 重新声明遮蔽前向声明的 local → playIdle/playJoinThenIdle 捕获的 upvalue 恒为 nil，busy 兜底路径必崩（attempt to call a nil value）；已改为 `drainPending = function()` 赋值写法
  - 新增回归测试 `scripts/tests/hero_scenario_claim_test.lua`（9用例 ALL PASS）；mock 要点：**引擎 require 忽略 package.loaded 预注入、且有内部缓存无法重载模块** → 必须替换全局 require + 自带 loadedCache + mocks 表，测试全程共用唯一模块实例、每角色只走一条流程，"重启"场景用预置存档 claimed 模拟
  - 既有回归 corrupt_convert / refine_cost_fixed / equip_ascend_affix 全 PASS；LSP 0 错误；build 成功
  - 部署：项目内容已复制到 /workspace 根（scripts/assets/.project/i18n/game_material），本地 .project/project.json 已剥离 project_id/author/developer_id（不提交 git）

- 历史分支：workspace931（2026-10-01 的战力与禁用文字修正；本轮由独立整合分支接入，不直接推送基线）

- 已完成任务（2026-09-30 / workspace931）：②棕色选项文字换色 + ③装备战力口径修正
  - **②棕色→灰蓝**：全局统一的"资源不足/禁用/锁定"文字色从棕色 `0x8d5f41` 改为灰蓝 `0x8b95a5`（更贴合暗黑冷色调、深色底可读性更好）。批量替换 25 文件 41 处（含 SweepDialog/BlacksmithEnhance 分行写法 + ChurchArtifactDrawPanel 十进制 141,95,65 + ChurchClassChange 0x462f20 保留不动=可购金币色）。刻意排除 3 类非"选项文字"棕色：EquipmentBag:1072 tab选中背景块、SettingsPanel 滑条/开关描边、RedeemCodePanel 输入框描边（装饰性，保持原样）。ACQ_DESC 0x8d7362(获取途径说明)/COLOR_BROWN 0x81573c(死常量无引用) 非选项文字未动
  - **③单件战力口径修正**：根因=`calcStatPower` 旧逻辑仅在 heroId≠nil 时对六围(str/agi/int/vit/luk/spi)走派生表折算(≈1.5/点)，heroId=nil 视角(总背包/铁匠铺/战利品掉落 LootBoxPage:356/BackpackPanel:1373,1490/BlacksmithInput/BlacksmithDecompose)六围按 valueModel=5 满额计价→戒指/吊坠等六围饰品战力虚高3.3倍。改为六围**恒**按派生表折算。改两处副本(需同步)：`scripts/ui/character/equip/EquipmentDetail.lua:183` + `scripts/rules/equipment/EquipmentService.lua:42`(服务端一键装备)。Python复现验证：金光之戒str4.28 21.4→6.42(命中设计调平6.43)；珊瑚吊饰/银质耳环30→8.9；全部饰品统一到8.9~9.0，非六围饰品(海灵之戒9.01)零变化
  - **③关于"套装战力显示在装备上"**：经核查 `calcEquipPower` 单件战力**只遍历 baseStats+affixes，从不含套装加成**(EquipmentDetail.lua:236-249)。套装2件属性仅在**角色总战力**层由 EquipmentSetSystem.applyToUnit→applyTwoPieceToUnit 以单个 modifier `set2_<setId>` 注入**一次**(不乘件数、不摊到单件)，4/6件为战斗被动零战力。装备详情面板的套装区块(compactSetLines)仅渲染描述文本+激活高亮，不含任何战力数字。→ 用户"套装战力直接显示在装备上"的观感可能来自别处，已在收尾 AskUserQuestion 中向用户确认具体位置
  - 口径一致性：总战力 calcHeroPower 的 POWER_SKIP 跳过六围(避免与派生双计)，六围经派生属性进总战力——与修复后单件"派生折算"口径一致，方向正确
  - LSP：基线35 error(全是预存 param-type-mismatch/NVGcolor 标注，stash前后一致)，本次改动0新增error
- 已完成任务：锻炉页等阶角标统一右上显示
  - `scripts/ui/blacksmith/BlacksmithPage.lua`：工作台槽升阶角标 "+N" 从左上（drawTextStroke 绿 0x67ff75）改为右上（NVG_ALIGN_RIGHT+TOP、字体36、绿 0x00ff60 + 黑描边），与仓库格子 BackpackGrids.lua:143 的角标位置/样式完全一致；删除无用常量 EQUIP_LV_FONT_SIZE
  - 同轮梳理洗练四石逻辑（见下方"洗练石头逻辑速览"）
  - LSP 0 错误；build 通过
- 已完成任务2：洗练锁定词缀精粹消耗按条数阶梯累乘
  - `scripts/config/BlacksmithConfig.lua`：applyRefineLockCostMult 从"lockedCount>0 一律×1.5"改为每条锁定 ×1.5 累乘（1条×1.5 / 2条×2.25 / 3条×3.375）；UI（BlacksmithRefine.recalcRefineEssenceCost）与服务端（BlacksmithService.RefineEquip）共用该函数，展示与扣费自动一致
  - `scripts/tests/refine_cost_fixed_test.lua`：断言更新为阶梯三档；headless 回归 ALL PASS（125→188/281/422）
- 环境注意：新工作区克隆仓库后，`.project/project.json` 里的原作者身份（project_id m_tfv3 / developer_id 400200）与本地 workspace 身份冲突导致 build 报 "local taptap identity conflicts with claimed database identity"；本地已剥离 project_id/author/developer_id 字段（不提交 git），构建恢复正常
- 环境注意2：远端 workspace930 常有并发提交，push 被拒时先 fetch + merge --no-edit → build → 再 push
- 环境注意3：离线测试用 `./.cli/UrhoXRuntime tests/xxx.lua -tapcode_dir=. -tool_mode -graphicsheadless`（runtime 在 `/workspace/.cli/`，项目根跑用绝对路径），runtime 缺失时先 `bash /workspace/.cli/install-urhox-runtime.sh`（需代理 http://127.0.0.1:1080）
- 环境注意4：GitHub API 走代理可创建/查询 PR；合并 PR 后远端 workspace930 前进，其他活跃开发分支需 merge origin/workspace930 解冲突后才能合入

- 已完成任务4（2026-09-30）：洗练石保底 + 点金石后期出口 + 修"点击洗练无反应"bug
  - bug 根因：BlacksmithRefine.showRefineToast 走 LootBoxPage.showToast，该函数在非抽卡页静默丢弃消息 → 拒绝原因(精粹不足/全锁等)无任何反馈，用户以为按钮没反应；已改为抽卡页开着走队列、否则回退 core.UiToast
  - 洗练石：reroll 后逐条取新旧较高者（保底只升不降），魔化/锁定槽不受影响
  - 点金石：品质达进度上限(getUpgradeMaxQuality)后不再拒绝 → 转随机一条普通词缀品级+1（最高S=5），回包 affixGradeUp{index,before,afterQ}，UI 用 corruptResultInfo 展示"词缀「X」品级 D→C"；全S品才拒绝；apply 分支不再无条件写 equip.quality（防 nil）
  - 文案：KeywordConfig 洗练石/点金石描述更新
  - corrupt_convert_test 扩展第6/7组（保底+提品）ALL PASS；三回归全 PASS

- 已完成任务3（2026-09-30）：腐化构筑模型大改（用户选定方案二）
  - 腐化石：随机7效果废弃 → 一条普通词缀转同类型魔化词条（AffixConfig.NORMAL_TO_CORRUPT_KEY 映射，数值 max(原×1.8, 模板×1.8)）+ 叠一层诅咒（corruptBaseMult=0.9^层，最多3层）；patch 记录带 layer 标记 {"c", idx, 原词条, layer}
  - 神圣石：全量回滚废弃 → 逐层洗除最上层诅咒（cleansed 结果带剩余 corruptCount + corruptRevert），魔化词条保留
  - 解除腐化硬禁：腐化后普通洗练/洗练石可用，精粹 ×2（CORRUPTED_ESSENCE_MULT，UI/服务端双端一致）；魔化词条在洗练/洗练石重随中固定（rerollKeepCorrupt wrapper）
  - 旧档兼容：corruptOriginalAffixes / 无 layer 的 patches 走一次性全清分支
  - 新增测试 tests/corrupt_convert_test.lua（ALL PASS）；equip_ascend_affix_test e12 fixture 改为 5 普通词条（转换后恰满员4）
  - 文案同步：KeywordConfig 腐化/腐化石/神圣石、BackpackPanel 资源描述、洗练页状态行"诅咒 N/3 层"
  - 关键文件：scripts/rules/blacksmith/BlacksmithService.lua、scripts/ui/blacksmith/BlacksmithRefine.lua、scripts/config/AffixConfig.lua

## 洗练石头逻辑速览（BlacksmithService.RefineEquip）

- 入口：洗练 tab 选额外资源 → RefineEquip(uid, seq, extraResource, lockedIndices)
- 公共消耗：精粹 = floor(QUALITY_COST[q].refBase * (1 + lv*refLvScale))，双手×2；锁定任意词缀整体×REFINE_LOCK_COST_MULT(1.5)；洗练次数 refineCount 仅计数封顶20，不影响费用
- 无石（普通洗练）：未锁定词缀重随机（种类+数值），结果存 pendingRefines 待玩家点"替换"；锁定数必须 < 词缀总数
- 洗练石 enhanceStone（1个）：词缀种类不变只重随数值/品质等级，**保底只升不降**（逐条取新旧较高者）；同样待替换
- 点金石 destroyStone（消耗=当前品质N个）：提品 +1（上限按最高通关难度：普通→4史诗/困难→5传说/噩梦及以后→6），保留原词缀、槽位不足补 roll；**达品质上限后转为随机一条普通词缀品级+1（最高S）**；**直接生效**无需替换；无词缀装备也可用
- 腐化石 corruptStone（1个）：一条普通词缀转同类型魔化词条（数值×1.8）+ 叠一层诅咒（基础×0.9^层，最多3层），**直接生效**；需至少一条可转换普通词缀（NORMAL_TO_CORRUPT_KEY 映射）
- 神圣石 sacredStone（1个）：洗除最上层诅咒（基础属性恢复、该层转换还原），魔化词条保留；不耗精粹、不加洗练次数；3层需3颗
- 腐化共存规则（构筑模型 2026-09-30）：corruptCount>0 时普通洗练/洗练石仍可用但精粹×2；魔化词条在重随中固定；点金石不受影响

## 标准收尾流程

代码修改 → LSP 诊断 0 错误 → mcp build → （必要时离线验证逻辑）→ git commit → git push → **AskUserQuestion 问下一步**
