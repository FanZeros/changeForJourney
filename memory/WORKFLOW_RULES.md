# changeForJourney（终焉之门）项目工作铁律

> 强化记忆：以下规则在每轮任务中必须遵守。**每轮开始工作前先重读本节。**

1. **不能取消/退出任务**：必须持续推进直到完成。
2. **每轮完成后必须用 AskUserQuestion 提问下一步**：禁止以纯文本、总结或其他任何非 AskUserQuestion 的形式中断对话。这是硬性收尾动作，任何任务（包括纯调研）完成后都必须调用 AskUserQuestion。
   ⚠️ 强化记忆（用户多次重申）：任何一次任务完成（含 commit+push 之后）的最后一个动作必须是调用 AskUserQuestion 工具向用户提问下一步做什么。绝对不允许以普通文本消息结束回合。即使构建失败、测试失败、遇到阻塞，也要用 AskUserQuestion 给出处理选项。
3. **以新分支继续开发**：以用户当轮指定分支为基线创建独立开发分支，每次完成后 commit + push 到该开发分支；通常基于 `workspace930` 开发并通过 PR 合入。**禁止 push 到 workspace 或 workspace930 分支本身**，显式指定推送目标，不强推、不擅自合并 PR。用户明确要求修复既有 PR 冲突时，可在新修复分支验证后快进更新该 PR 的开发分支，不将该许可延伸到其他分支。
4. **部署位置**：游戏项目必须直接位于 `/workspace` 根目录。仓库可直接检出到该目录；若使用独立克隆目录，构建前应把 scripts/assets/.project 等同步到根目录，不要产生嵌套游戏入口。修改代码后调用官方 build 工具构建。

## 给后续 AI 的剧情待办交接（2026-10-03，用户要求暂缓）

- **用户最新决定**：剧情留交接说明，明确仍未完成；接下来先做其他事情。此时不要自动补译剧情、修链播或创建 PR，等待用户的新任务。
- **未完成状态**：当前配置 196 句台词仅有 17 句命中本批剧情词典，剩余 179 句未补繁中/英/日/韩；80 个编号情景只有 4 个完整覆盖，仍有 76 个未完成。44 个词典源条目包含信件/过场/标签，不等于 44 句配置剧情已翻译。
- **恢复入口**：`scripts/config/ScenarioDialogueConfig.lua` 是剧情源；`scripts/core/I18nStory.lua` 是完整句四语词典；`scripts/ui/story/StoryDisplay.lua` 与 `ScenarioDialogue.lua` 负责全文先译、UTF-8 打字和原样显示。恢复时重新核对配置和精确缺失原文，不直接沿用数量，不开启引擎自动翻译，不改角色名资源路径、存档或奖励键。
- **未修风险**：`ScenarioDialogue` 的链播回调清空顺序是基线既有问题；本批未修，也未实跑链播反例。已有 831 条剧情显示检查只覆盖非链播完成/skip。小屏长信件可缩至 7 号字，真实字体和可读性尚待验收。
- **后到的独立审查待办（尚未修）**：长英语装备名在 compact 详情固定 44px 下可能越界并推走锁图标；套装词典的英语 `Gate-gap` 与日语 `敵視` 尚未出现在关键词显式别名中，原机制点击入口可能丢失；天赋真实字体测试用 MiSans，而主入口用 NotoSansCJKkr-Bold，当前高度通过不代表生产字体通过。已逐文件核对相关实现存在，未把后到审查记录冒充已修复或实机验收。
- **剧情另待核实项**：旧 Intro 切语言继续用旧 elapsed，完成句可能退回部分新译文；独立审查还提示换行保留尾空格可能使行宽超限，恢复时需查看 `I18nStory.wrap` 并真实复现。用户本次要求先留未完成说明，暂不继续剧情修复；这批回归通过只证明已覆盖用例，不代表上述边界全通过。
- **已交付位置**：`dev/i18n-audit-20261003`，功能提交 `13724d3`；后续开发应按当轮指定基线另建工作分支，不推 workspace 系列，不把暂停待办标成完成。阶段汇报后仍实际调用 **AskUserQuestion**。

## 本轮续开发（2026-10-03，i18n 多分区）

- 用户再次明确：每阶段完成（包括提交推送）后先报告实际结果，再真正调用 **AskUserQuestion** 提供 2–4 个具体下一步选项。持续推进已授权工作，不擅自取消；尊重用户后续停止指令、权限拒绝及安全边界。
- 从 `dev/i18n-audit-20261002@8874908` 创建 `dev/i18n-audit-20261003` 并合入最新 `workspace930@b24cad7`；只推新开发分支，绝不直接推 workspace 系列、不强推、不自动合并 PR。项目直接部署于 `/workspace` 根。
- 当前工作区为新环境，用户描述的上一轮未推送修改不能当作已存在；按远端实际文件恢复，分区推进装备、天赋、关键词富文本和剧情显示，基础词典机械拆分保持原文与顺序。继续使用自定义五语系统，不开启引擎自动翻译，不改配置源名、资源路径或存档键。
- PAT 不写入项目、Git 远端地址、日志或记忆；已在对话中出现的凭据应撤销轮换。本地构建绑定与共享 Git 配置分离，不提交临时身份变化。
- **已验证的本批进展**：基础词典拆为 13 行 facade + 688/688/684 行模块，同一 D 表按原序填充；2036 条旧赋值逐项一致（509 键/语），原文、译文和顺序差异均 0，韩文「第」空串及英语「个」单空格保持。装备补 353 名、25 子类型、57 词缀及 12 套名/36 套装说明，1932 四语组合及真实显示路径测试 8353 断言通过；天赋 209 节点的 161 名/179 效果完整显示覆盖，163 新精确键及严格纯属性模板，1045 五语组合、8648 断言通过。源配置、属性解析、归属和业务 ID 未改。
- **关键词显示链路**：25 实际关键词四语 title/desc 共 200 字段；完整句先本地化再按目标词最长匹配，英语词边界、UTF-8 折行与原 key 热区保持；raw 显示/测量 API 避免已翻译片段再次被 hook 翻译。1466 检查、180 套装描述用例通过；旧关键词测试补 pcall/engine:Exit 后正常退出。首轮失败的 ×2 数字、句末标点数值解析与繁中合法同形判断已逐项修正，未仅凭 exit0 宣称通过。
- 合并基线保留按普通 9-5/19-5 通关解锁队伍及行军提示；新增五语回归合计 42 断言通过，不恢复旧等级解锁。16 套阶段 Runtime 回归均有实际成功标记且 exit0；无头 audio/UI shader 初始化错误属已知环境噪音，不等同真实像素验收。主入口完成 18/18 启动队列；多语 UI 仍待真人验收。全仓 LSP 缓存汇总存在 46 个既有 Error，不宣称全仓清零。
- 剧情首批已完成显示链路、当前 12 行信件及跨行合句、5 条旧 Intro 字幕、10 条开场台词与 7 条代表剧情，合计 44 个完整源条目、176 四语译文；全文先译再 UTF-8 截字与原样绘制，切语言只刷新当前显示，不改变步骤、存档或奖励。831 检查通过；当前配置 196 句台词仅覆盖 17，仍有 179 句未覆盖，80 个编号情景仅 4 个完整覆盖，其余 76 个尚未补齐，不宣称全剧情完成。小窗口信件缩字可至 7，需要后续可读性与真实字体/像素验收。
- 最终 19 套 Runtime 国际化/剧情/装备交叉回归均有真实成功标记、exit0、断言错误 0（含剧情领奖及首通82兼容）；最终主入口限时 35 秒完成 18/18 启动队列，无 Lua 异常，exit124 为持续游戏被外部限时结束。官方最终 Build 成功，447 个 Lua 入包，本轮35个修改/新增 Lua 全在 manifest 中；逐文件 LSP 最终均无 Error（剧情两处 NVGcolor 和 source 注解已修），仓库规范 2575 路径 0 错误/警告，规范工具 36 项回归通过。真实字体/像素布局仍未全量验收。
- 功能提交 `13724d3f` 已推送到新分支 `dev/i18n-audit-20261003`，远端同名分支 SHA 与本地 HEAD 完全一致；先前同步基线提交为 `c978238`。没有推送 workspace 系列，期间共享基线由外部并行操作继续前进，不将其当成本会话推送。本地 `.project` 身份与运行参数留本地、不提交，未自行创建/合并 PR。仓库凭据扫描确认暂存差异与本地 Git 配置零令牌残留；每次阶段结束仍先报告真实结果，再实际调用 **AskUserQuestion** 选择下一步。
- 未知整句有意保持源文，不猜测子串；独立跨分区复核未发现新的注册/原样显示/动态模板阻塞。剧情末轮复核发现**基线既有链播回调缺陷**：自然结束/skip 先执行 `onFinishCb_()` 再置 nil，若 A 回调中 show(B)，B 新回调被 A 清掉。已与 `origin/workspace930` 原文比较确认三处顺序未由本轮改动；现测试只覆盖非链播 finish，不把它写成已修复，也不擅自扩大为剧情流程重构。下一阶段可明确授权最小修复与链播回归。

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


### 用户工作流确认（2026-10-03 再次强化）

- 用户再次明确：本轮及之后每轮完成（包括只读审查、构建失败或存在阻塞）都先汇报真实结果，再以 **AskUserQuestion** 具体选项交接下一步；不得以普通结束语代替，不自行取消已授权任务，尊重用户后续停止指令。每轮仅向新建工作分支 commit + push，不直接推送 `workspace` 或 `workspace930`，不擅自合并 PR。

### 角色审计复查（2026-10-03）

- 用户当前要求复查 `audit930/character-awakening-sets-1002` 对应角色逻辑，基于最新 `workspace930@eec2a976` 建立 `fix1003/character-awakening-audit`；本轮只审查，不擅自调平衡或实施套装设计。项目/.git均位于`/workspace`根。
- 旧审计分支没有角色技能修复提交；角色/觉醒/套装核心模块与旧快照逐字节一致。最新属性页/装备/战力/读档修复不能等同于战斗闭环修复。
- 恢复旧审计探针与原UUID，最新两次实跑均 `confirmed=17 healthy=0 harnessErrors=0`，exit0仅表示探针结束，17观察含同根因/接口误用风险/设计缺口，不能说17独立bug或17已修复。18套既有回归实际ALL PASS，但未覆盖这些技能路径。
- 最新官方Build成功，414个Lua资源；主入口30秒冒烟完成18/18，无Lua traceback，exit124为外部结束持续游戏；字体/shader无头错误不代表视觉通过。审计文件LSP零诊断，缓存320文件汇总16个既有Error，不把缓存当全仓清洁证明。
- 跨波套装残留只按旧BattleScene复用单位说明；三行每关新建单位，不能直接外推。死人周期输出要求尚有其他活队友且继续tick；opts作为source丢统计/noCounter，不等于实际打错阵营。
- 报告位于`docs/changeForJourney-gameplay.md`第21节。已推送工作分支，首次提交`967f49f0`，补充至`1cdb3204`；套装首次与独立反证已完成，最新属性/装备静态组已回传，角色技能/觉醒组未完整回传不宣称完成。最新已修点为升阶投入/魔化JSON回退/只读试穿/稳定属性/六围折算；残余候选含双持转职与自动配装、跨队卡面/星门上下文、老六物理计价与暗影魔伤冲突，均旧问题或修复遗漏而非已确认本轮新增回归。
- 完成后仅向工作分支提交推送，汇报真实结果后以 **AskUserQuestion** 选择下一批修复；不自行合并PR，本地生成`.project`身份/配置不提交，PAT不持久化。

### 关键角色故障修复授权（2026-10-03）

- 用户在 AskUserQuestion 明确选择“修复关键故障（推荐）”：授权小雀依赖、飞剑全盾结算、敌死事件以及永久生命成长，不调平衡倍率。以审查交付`8f434e70`新建`fix1003/character-critical-lifecycle`，仅向该新分支提交推送，不自动合入。
- 原角色审查工作流已最终完整回传，8个审查/独立验证任务均完成、0错误；此前“未完整回传”只表示审查初次推送时的进度。
- 多分区实施：主会话小雀/飞剑与伤害命中即时钩；成长分区只改ETS；死亡分区接三行/旧单场/副本/塔与终焉解绑前扫描。天赋事件幂等与经验/掉落账本分离，冻住/标记状态必须在清理前可见，不伪造终焉未命中Boss杀手。
- 新回归小雀/飞剑20断言、成长39断言、死亡53断言已独立实跑全过（112断言）；死亡包括真实四宿主/终焉、首次满层/夜斩/氮气、押韵、嵌套战线/异常恢复、小雀斩杀原标记消费。十四套最终回归全过，官方Build成功417 Lua，主入口30秒boot18/18无Lua异常，静态缓存仍16既有Error，不说全仓/视觉完全通过。旧专项探针为`confirmed=12 healthy=5 harnessErrors=0`，五项观察改善，不是全体角色/套装已修。
- 独立反证发现后攻击同步额伤先于归因/消耗的新时序回归：已将普攻/连击死亡消费放后攻击结束、同轮After/Combo按挂载战线暂存后消费；斩击/氮气旗标前置，小雀斩杀转标交死亡消费者。飞回全盾记池/转火追加效果、三阶/治疗功德/连射/概率/套装/计价剩余不在本批，塔旧onEnemyKill双入口不扩改。
- 首批功能提交`cffbc616`已推送到`fix1003/character-critical-lifecycle`，远端`workspace930`仍为`eec2a976`。用户随后明确选择“创建修复PR”，已创建PR #24：https://github.com/FanZeros/changeForJourney/pull/24，目标`workspace930`，open且未合并；附112断言/14套回归、构建和剩余边界，不据创建授权自动合入。最终独立只读复核未发现剩余可确认新增阻塞；死亡消费回调自身抛错、切战线不恢复、真正嵌套After/Combo仍列未覆盖边界，不据此捏造生产故障。
- 测试禁止只靠package.loaded预注入：托管Runtime会绕过它，必须验证真实替身命中；成长测试首轮harness失败已披露并改为全局require拦截后成功。每轮真实结果报告之后仍以 **AskUserQuestion** 提供下一步决定。
## 本轮协作要求强化（2026-10-02，历史指定基线）

- 用户再次要求：持续推进直到完成；每次完成后必须真正调用 **AskUserQuestion**，提供 2–4 个下一步选项，不用普通文本问题代替，不以非 AskUserQuestion 的形式中断对话。
- 当轮基线：`feat930/equipment-attribute-preview`；开发分支：`feat930/equipment-bonus-toggle-1002`。当轮完成后只推开发分支并向当轮基线提交 PR，绝不推 workspace；此历史授权不覆盖后续任务。
- 凭据仅用于即时鉴权，不写入项目、Git 配置、提交或记忆；若遇到失败/阻塞，必须如实报告，并用选项询问处理方向，不绕过权限。

### 本轮实现与验证（2026-10-02）

- 配装下部标题可单击切换「角色属性 / 装备加成」；装备模式只显示装备引起的正增益，实际攻击间隔缩短按增益保留。六围雷达同步显示装备净增益，无增益显示空态，普通属性页不变。
- `EquipmentPreview.build` 的 `includeEquipmentBonuses` 按需启用同人物穿装/裸装完整差分；两侧神器为空，排除神器来源；保留六围派生、普通词条倍率、魔化最终乘区、升阶和两件套面板属性。套装四/六件条件效果仍在摘要说明，不提前执行战斗触发。
- 原试穿差值保留；标题归比较保留热区，不关闭钉住候选，不取消副手筛选，不发穿戴操作。显示模式进入缓存键，切换重置属性滚动和说明，后续帧继续命中缓存。同队转移装备时，当前和试穿世界分别构建裸装基准，星门共鸣净贡献与实际穿后保持一致。
- 回归：装备预览 117 断言、配装绘图/缓存 97 断言、横屏手势 44 断言、稳定属性列表 55 断言、真实模块集成冒烟均通过。装备雷达小数保留有效精度并限制栏内宽度，避免长数值越界。主入口运行一分钟，初始化 18/18 完成，未出现 Lua 运行错误。修改文件 LSP 无 Error；官方 Build 成功，410 个 Lua 入包。首次集成测试失败因先选副手按既有筛选逻辑清了候选，修正 fixture（先选副手，再 open/pin）后通过，非显示切换缺陷。
- 已交付：功能提交 `923f547a` 已推送到 `feat930/equipment-bonus-toggle-1002`；PR #16（https://github.com/FanZeros/changeForJourney/pull/16）已创建，base 为 `feat930/equipment-attribute-preview`。未推 workspace 或原分支，未自动合并 PR。构建生成的 `.project` 改动仅留本地、不提交。视觉与设备触控等待人工预览验收；完成简报后仍必须真正调用 **AskUserQuestion** 询问下一步。


### 用户工作流再次确认（2026-10-03）

- 本轮从 `workspace930` 拉取至 `/workspace` 根目录，在新的开发分支推进；每轮完成后显式推送该开发分支，绝不推送 `workspace` 或 `workspace930`。
- 完成或遇到阻塞时，先报告实际结果，再以 **AskUserQuestion** 的具体选项询问下一步；不以普通文本结束回合。持续推进已授权任务，同时尊重用户后续明确的停止要求和权限拒绝。
- 本轮 PAT 不持久化，不进入项目、Git 远端地址、日志或记忆；提醒用户撤销已公开的凭据。

### 用户工作流确认（2026-10-02）

- 每轮汇报实际结果后，以 **AskUserQuestion** 具体选项询问下一步；已获明确授权的步骤持续推进，不擅自取消任务，也不忽略用户后来明确提出的停止要求。
- 分支排查必须区分“分支最新提交未被完整合并”和“实际功能尚未合入”，避免把合并后追加的记忆文档当作遗漏功能。
- PAT 不写入仓库、远端 URL、日志或长期记忆；用户在对话中公开过的凭据应提醒撤销并更换。
- 导入配置的旧项目身份与当前工作区冲突时，本地配置须与源仓库提交分开；不得将当前工作区的身份回写到共享仓库。

## 仓库文件提交规范（2026-10-02）

### 资源元数据

- 保留项目资源 `.meta`：它保存稳定 UUID，可能还含 `c_or_s`；不要增加全局 `*.meta` 忽略规则。
- 新增、删除、移动构建资源时，同步处理对应 `.meta`。重命名保持原 UUID，不得仅为构建或合并重生成已有身份。自动检查保护同路径以及 Git 已识别重命名的 UUID；移动且大改内容导致 Git 无法识别时，仍需人工确认身份保留。
- 校验 JSON、非空 UUID、全仓 UUID 唯一和源文件配对；开发配置 `.luarc.json` / `.luarc.jsonc` 不强制配元数据。运行资源 `.json` 只检查语法，不强制套用不完整的引擎 schema；`.jsonc` 不按普通 JSON 解析。
- `assets/`、`scripts/`、`i18n/` 和 `.project/` 的明确构建资源扩展参与配对检查；普通文档、Python 工具不机械要求 `.meta`。`game_material/` 是上传发布素材目录，不是本项目构建资源根，不强制新增元数据。
- 引擎参考目录的忽略规则必须根锚定，例如 `/schemas/`，不能用 `schemas/` 误排除 `scripts/shared/schemas/`；项目内同名业务目录正常追踪。
- 验收图片放本地 `screenshots/`；需要提交的正式素材放 `assets/` 或 `game_material/`，不要混入临时目录。

### 项目配置与本地身份

- `.project/project.json`、`settings.json`、`resources.json`、`i18n.json` 继续版本管理，不整体忽略 `.project/`。
- 普通功能提交不应改变 `project_id`、`author.id` 或 `taptap_publish` 下的 `app_id` / `developer_id` / `miniapp_id` / `client_id`。它们是项目绑定身份，不是秘密；本地预览重绑定不应带回共享仓库。
- 入口、版本、发布方向等共享配置有业务需求时可正常改动；不把未经证实的 `project.local.json` 当作引擎已支持的配置覆盖方式。
- 正式身份迁移须单独说明并明确授权；本地 `--allow-identity-change` 只用于核验迁移，不是绕过 CI 的许可。CI 默认不允许身份迁移，正式迁移需专门审阅调整规则，不能偷偷关闭整个检查。
- 生成时间戳变化提示告警，提交前确认是否必要。

### 禁止提交

- 构建／缓存／依赖目录：`dist/`、`.build/`、`.cli/`、日志、临时目录、`node_modules/`、`__pycache__/`，以及 Electron 的 `game/`、`game_engine/`、`release/`。
- 本地验收 `screenshots/`、根目录 `standalone_save.json`、`battle_lab_*.json`，包括这些产物的 `.meta`。
- `.git-credentials`、`.netrc`、`.env`、含真实值的环境配置和私钥；无秘密值的 `.env.example` / `.env.sample` / `.env.template` 可提交。
- 引擎提供的参考目录不作为项目源码提交。现有项目工具和协作记忆保留，不盲目删除已追踪的合法文件。
- `.gitignore` 不影响已经追踪的文件；必须检查 Git 内容，不能只看文件是否被忽略。

### 提交前检查与 CI

```bash
# 检查暂存区，比较 HEAD；不会读取未暂存的本地构建身份
python3 .github/scripts/repository_policy.py --staged

# 校验器自身回归（只用标准库与临时 Git 仓库）
python3 -m unittest discover -s .github/scripts -p 'test_repository_policy.py' -v

# 检查已提交 HEAD，相比目标分支；不读取工作区/暂存区
python3 .github/scripts/repository_policy.py --base origin/workspace930
```

- GitHub Actions 的 `repository-policy` 对 `workspace930` 的 PR、推送及手动触发运行；不设 `paths` 过滤，避免后续作为必需检查时永久 Pending。
- Actions 仅 `contents: read`，不持久化 checkout 凭据，不给 PR 检查传 PAT，不用 `pull_request_target` 检出并执行 PR 代码。
- 本轮只增加 workflow，不修改 GitHub 分支保护。因此检查会显示结果，但尚不强制阻止管理员合并；保护规则需要另行授权。
- 不默认强制他人审批：单协作者不能批准自己的 PR。持续保留已有 GitHub secret scanning 和 push protection。

## PR24 冲突修复（2026-10-03）

- 用户明确要求解决PR24冲突，并另行排查升级白图、规划升级奖励页。PR24源=`fix1003/character-critical-lifecycle@765dc22c`，最新目标=`workspace930@8d3e62f`（PR21由外部操作合入）；新建`fix/pr24-conflicts-20261003`，只同步目标并解冲突，不混入升级UI或经济奖励实现。
- 唯一文本冲突是本文件中的角色审计/关键修复记录与目标协作记录，全部保留；BattleTriDriver/BattleTriPage自动合并。回归验证保留当前行军、小队通关解锁、PR21装备净加成与PR24死亡消费/成长生命修复，不调平衡。
- 14套Runtime退出0且ALL PASS：新critical20、成长39、敌死生命周期、行军27、小队解锁115、终焉/切关、装备预览117/真实冒烟、套装筛选、升阶、腐化、离线487和UI525；官方Build成功。自动合并两文件逐文件LSP无Error，不宣称全仓零Error；真实离屏启动160帧原始PASS，Lua/资源/引擎错误0、缺图为空；仓库规范2521路径0错误0警告、36单元测试全过。
- 完成后只推新修复分支及非强推快进PR24源分支以消除其冲突，不push workspace/workspace930、不自动合并PR。本地.project身份与生成配置不提交。升级白图/奖励页另开范围，奖励数值与发放逻辑未经确认不实施。报告真实结果后以AskUserQuestion继续。

## 新手教程位置、卡死与横屏修复（2026-10-03）

- 基于 `workspace930@eec2a976` 新建 `fix930/tutorial-horizon-flow-1003`，只推本轮独立分支，不推 workspace 系列，不擅自合并。用户要求修复教程位置错误、卡住和横屏适配。
- 首轮装备链改为默认配装页→真实武器槽→左仓库双击/右键快捷穿戴，移除不存在的旧详情按钮；一键穿戴与快捷穿戴均等实际成功事件结束，保留失败重试。第二击关闭候选详情后仍补派发同装备格，避免教程期间双击被吞。
- 教程覆盖层拆为屏幕逻辑坐标响应式模块，按实际面板note投影目标；热点清理移到渲染帧起点，补角色内容平移与仓库左栏归属。气泡UTF-8换行、避开目标和skip；缺目标skip仍可点；拖角色时不全屏压暗。bag详情归右栏，smith归中栏，绘制/输入共享映射。
- 教程门控前置于装备浮层/返回条；只对真正按钮边界放行，不把光环外扩当按钮。触摸从TouchID/X/Y取真实物理坐标，代理MOUSEB_LEFT，不依赖不存在的Button或鼠标坐标；非首指不释放原按压。奖励/剧情等更高优先层绘制与输入共同让位。
- session增加独立tutorialProgress，真实完成/跳过才记completed；后续组排队，不覆盖当前组。重启未完成组恢复合法入口，不重复发剧情奖励。招募取消/不足不提前等待，失败/超时/未处理/缺结果回退，清旧newHeroId；全重复招募无新角色不死等拖拽。横屏隐藏旧副本页签时直接打开副本教学入口。
- 验证：官方Build成功，修改Lua无LSP Error（全仓44条既有Error未混修）；13套Runtime回归通过，新增目标39、布局1189、横屏54案例355断言，流程恢复49断言；另快装78、手势38、滚动10、离线覆盖487及剧情/切关/终焉等通过。屏幕覆盖层已在1280×720与844×390真实离屏截图确认目标镂空、气泡和skip位置；完整新档全流程仍需用户实机验收，不能把mock/夹具说成真人通关。
- 临时截图脚本和测试生成招募历史清理，不提交；新增Lua保留官方生成meta，原UUID未变。本地构建身份不提交，凭据不进Git/配置/日志/记忆。
- 已创建 **PR #25**：https://github.com/FanZeros/changeForJourney/pull/25，head=`fix930/tutorial-horizon-flow-1003`，base=`workspace930`，未自动合并。创建时最新基线`8d3e62fe`已包含PR21/22/23，本分支尚未同步；merge-tree仅本记忆文件文本冲突，其余玩法重叠可自动合并。处理冲突后需合并态重新验证，不以源分支回归代替并行功能验收。
- 每次完成必须先如实简报，再真正调用 **AskUserQuestion** 提供2–4个下一步选项；持续推进已授权任务，尊重用户后续停止要求及权限拒绝。
## PR21 冲突修复（2026-10-03）

- 用户明确要求“看看解决下21的conflict”。PR21 源为 `feat930/equipment-attribute-preview@4f6737d6`、目标为 `workspace930`；拉取后目标已前进至 `a89e3fda`（PR22与PR23已由外部操作合入，不是本会话自动合并）。新建 `fix/pr21-conflicts-20261003` 从PR源开发分支起步，合入最新目标，保留双方功能。
- 仅两处文本冲突：`memory/WORKFLOW_RULES.md` 双保留协作记录并注明历史指定基线；`tests/lootbox_set_filter_test.lua` 保留PR21套装数量getter/刷新/品质筛选全部用例，以及目标 `runTests + pcall + engine:Exit` 包装。测试cleanup改为无论断言是否失败都恢复Dialog.open、time和package替身，成功标记只在测试与cleanup都成功时输出。
- 自动合并独立只读审查未确认业务回归：净加成/套装计数核心保留，六槽共享坐标保留；最新无框徽记、Horizon输入拆分、首通/升阶腐化兼容、PR22语言与轮回补图、PR23行军与按关卡解锁小队全部保留。三处交叉业务UI变化仅禁用色更新。不能因合并暂存区包含目标既有文件就误认新增开发范围。
- 验证：18套独立Runtime回归退出0且成功标记均核实（装备预览117、配装97、手势44、仓库259、徽记92、属性55、滚动10、离线487、本轮UI525、小队解锁115、行军27，以及套装筛选/装备冒烟/雷达/升阶/腐化/战力/小队同步）。小队同步成功标记为 `PASS: atomic swap...`，不是ALL PASS，已单跑确认；不得把解析器未匹配标记写为测试失败。
- 冲突文件逐文件LSP无Error；全仓LSP仍有既有跨文件雷达类型和HeroService等诊断，未混入无关重构，不宣称全仓零Error。官方Build成功；真实离屏启动160帧原始PASS、Lua/资源/引擎错误0、无缺图；仓库规范2513路径0错误0警告、36单元测试全过。
- 推送授权只用于新修复分支，以及通过非强推快进更新 PR21 的源开发分支以实际消除冲突；不push `workspace` / `workspace930`、不合并PR21、不改其他PR。本地.project身份与自动生成配置不提交。普通词条ascBonus与净加成组合、行军中切换属性及设备触控没有新增专项验收，不把分别通过的测试当成组合覆盖。完成后继续以AskUserQuestion提供下一步。

## 本地美术迁移 PR 交接（2026-10-03）

- 用户通过 AskUserQuestion 选择“创建PR”；已创建 **PR #22**：https://github.com/FanZeros/changeForJourney/pull/22，head=`feat/workspace930-ui-reincarnation-20261003`，base=`workspace930`。功能提交42cfb0e、迁移交接1e36319；本轮PR说明包含最小范围、保留内容与真实验证边界。
- 创建后查询：PR open、未合并，mergeable=true（无文本合并冲突）；repository-policy CI 当时为 in_progress，不虚称已通过。此记录之后的交接提交会重新触发检查，最终状态以远端最新head为准。
- 本轮只更新交接记忆并push同一新功能分支，未改Lua，不重复构建；前轮官方最终Build已成功。本地.project配置不提交。创建授权不包含合并，等待用户后续明确选择；报告后继续用AskUserQuestion提供下一步。

## 本地美术选择性迁移完成（2026-10-03）

- 用户通过 **AskUserQuestion** 选择“UI＋轮回补图”；基于最新 `workspace930@eec2a976` 新建 `feat/workspace930-ui-reincarnation-20261003`，不整支合并候选 `integrate/workspace930-local-art-20261001@6e94b7bc`。前序只读审查及详细资源分类已推到 `review/workspace930-local-art-audit-20261003@68e9a14`，本轮不将那个分支当作功能遗漏或强行合入。
- 只迁三组局部 UI：语言五枚按2+2+1、末枚右对齐（行中心1480/1534/1588，默认嵌入偏移40）；兑换码中心1768/嵌入1808，独立背景保持顶785.5、底扩展到1918，绘制与点击同源。玩家信息背景保持顶193.5、底扩展到2070.5（向下增高130）；四种“远征时间”文案保留原计时/存档口径。城镇仅遗匣与功绩名牌对齐及删除遗匣300×64额外底板，其余地点、门控、奖励、红点和点击热区不变。
- 恢复当前有轮回引用但缺失的 `assets/image/界面底板/剧情日记/JQBJ_1.png`、`JQBJ_2.png` 与原 `.meta`；两图共2,971,190字节，SHA与候选原图一致，UUID保持，最终 manifest 及正式打包PNG已核实存在。未恢复其它旧资源、旧方CG、Spine或BGM。
- 回退保护：觉醒、Standalone、Horizon及输入模块、EquipmentSetIcon、BattleTriPage与基线逐字节相同；73张现有CG/套装PNG哈希全部不变。`showSetIcons` 开关及其持久化字段保留。已有偏好测试的 I18n 桩补齐真实五语列表；首次回归失败因旧桩无LANGS，不是生产语言数据缺失，补齐后26断言全过。
- 新持久回归 `tests/local_art_ui_migration_test.lua`：真实三模块公开 draw/input/init/update + 内存File与NanoVG spy，22用例/525断言全部通过；涵盖语言/点击边角/缝隙/兑换码/背景边界/false偏好保存、PIP四格式及dt区间/20秒保存、Town两名牌及六个原地点布局。Runtime有额外require缓存，测试读真实资源源码并用load隔离实例，不改源码、不使用debug窥私有状态，所有存档写入仅内存。
- 验证：修改/新增Lua逐文件LSP无Error；官方最终Build成功。旧套装偏好26、角标66、离线覆盖487、剧情82首通、真实装备预览冒烟均Runtime exit0且ALL PASS。9组真实离屏渲染（玩家信息、独立设置五语、城镇、轮回两阶段）均135帧原始PASS、Lua/资源/引擎错误0，图片像素已查看。只验收静态布局与代表性阶段，不宣称GM/头像子面板、完整动画、真实设备全流程已测。临时 `_local_art_preview.lua` 及sidecar已删除，最终Build不含临时入口。
- 本轮结束仍必须先如实报告，再以 **AskUserQuestion** 提供下一步选项。只commit/push新功能分支，不push `workspace`/`workspace930`、不强推、不自动合并PR；PAT、本地预览身份与生成配置、验收截图不提交。全局记忆目录在本环境未挂载，要求已强化到本项目现有记忆，不虚称已写全局记忆。

## 装备套装徽记去框（2026-10-03）

- 用户已自行处理 PR #19（远端确认已合并）；基于 `workspace930@c7cff542` 新建 `feat1003/equipment-set-badge-frameless`，功能提交 `61c63244` 已推送，PR #20：https://github.com/FanZeros/changeForJourney/pull/20，目标 `workspace930`，未自动合并，不推基线。
- 用户要求仅装备上的套装图标不要框，只保留内部内容。统一八角框、黑底和背景泛光原本烘焙在 V3 PNG 内，不是绘制代码额外画框。
- 原离线生成器新增 `-set-badges`，从同一 V3 主体/雕刻代码输出12张透明主体图到 `assets/image/套装图标/badge/`；原12张V3图片哈希不变。保留主体自有门框、盾沿、轮毂和星轨，不能把这些符号结构误删。
- `EquipmentSetIcon.drawBadge` 使用独立无框图片缓存；`get/draw` 保持V3供筛选与套装正文。角标布局/等级/开关和所有装备入口不变，缺图时跳过而不回退带框图。
- 验证：本轮3个Lua文件LSP无Error，官方Build成功；偏好26断言、全部角标66断言、滚动10断言、装备集成冒烟、遗匣筛选5套Runtime回归全过。真实离屏截图确认装备角标仅主体、下方完整图仍带原框；临时验收脚本已清理，不入包。
- 完成后报告实际结果并调用 AskUserQuestion 选择下一步；不擅自合并、不给新任务沿用旧授权、不将本地预览身份或凭据提交。

## 本轮最小规范进展（2026-10-02）

- 基线 `workspace930@eee25ef6`，新分支 `chore1002/repository-file-policy`，只推新分支并向 `workspace930` 提交 PR，不直接推基线。
- 清理 5 个已确认源文件不存在的 `.meta`；`CharacterSchema.lua.meta` 从历史 `2ad68424` 恢复原 UUID，而非新生成。官方 Build 成功，manifest 已确认使用恢复的 UUID；剧情首通、战力、升阶、切关 4 套 Runtime 回归均退出 0、ALL PASS。Lua 逻辑未改，本地生成的 `.project` 身份/设置未暂存。
- 新增只读 Git 快照校验器及独立临时仓库回归，36 个测试全部通过；本地暂存区检查 2473 路径，0 错误/警告。workflow 语法、只读权限与无 paths 过滤已校验。
- 用户再次明确授权最小规范；不扩展为配置加载重构，不修改远端保护。完成后先报告真实验证结果，再调用 AskUserQuestion 选择下一步；不得擅自取消已授权任务，也不得忽略用户后续停止或权限拒绝。
- 完整提交已推送，PR #19：https://github.com/FanZeros/changeForJourney/pull/19，目标 `workspace930`。用户补充 workflow 权限后成功推送；随后同步并发 PR #18（基线 `ce1d16f4`），仅工作记忆追加块冲突，双保留，不改对方弹窗功能。
- 2026-10-03 交付验证：PR #19 已无冲突，远端规范 CI 成功（https://github.com/FanZeros/changeForJourney/actions/runs/37031081154）；合并态本地 36 个规范测试与离线覆盖层 487 断言、配装手势、遗匣横屏、切关回归全部通过，官方 Build 成功。`workspace930` 保护仍未开启，PR 未自动合并。

## 弹窗选择性提取确认（2026-10-02）

- 用户在 PR #17 合入后选择“先提取弹窗修复”，工作分支 `fix/workspace930-fullscreen-popups-20261002` 基于 `eee25ef`。
- 范围仅离线收益全窗绘制、统一输入坐标与防穿透、三行升级弹窗独立显示；不接入黑色全窗遮罩、时间文案、语言布局、城镇名牌、觉醒旧逻辑和旧素材。
- 候选分支的 Up 拦截位于装备拖放之后，必须提前消费；触控用真实 TouchID/X/Y，不假设 Button 字段，保留 PR14 快装和只读预览。
- 超长横屏宿主按渲染/输入拆分，保持所有 Handle*Horizon 全局接口；测试 require mock 必须透传新输入和离线覆盖模块。
- 交付后仅推送新分支，以 **AskUserQuestion** 询问验收、合入或下一项需求，不据旧授权自动合入本轮改动。

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
