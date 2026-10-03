# changeForJourney（终焉之门）项目工作铁律

> 强化记忆：以下规则在每轮任务中必须遵守。**每轮开始工作前先重读本节。**

1. **不能取消/退出任务**：必须持续推进直到完成。
2. **每轮完成后必须用 AskUserQuestion 提问下一步**：禁止以纯文本、总结或其他任何非 AskUserQuestion 的形式中断对话。这是硬性收尾动作，任何任务（包括纯调研）完成后都必须调用 AskUserQuestion。
   ⚠️ 强化记忆（用户多次重申）：任何一次任务完成（含 commit+push 之后）的最后一个动作必须是调用 AskUserQuestion 工具向用户提问下一步做什么。绝对不允许以普通文本消息结束回合。即使构建失败、测试失败、遇到阻塞，也要用 AskUserQuestion 给出处理选项。
3. **以用户当轮指定的分支继续开发**：本轮（2026-10-03，N02日志夹页）明确在 `feat1003/samsara-story-wiring-plan` 继续开发，完成后 commit + push 回同名分支；不另建分支、不推任何 `workspace` 系列、不强推、不擅自合并PR。其他轮次遵循用户当轮授权，历史“必须新建分支”不覆盖新的明确要求。
4. **部署位置**：当前仓库和游戏项目直接位于 `/workspace` 根目录，scripts/assets/.project 等不再嵌套子目录；保护引擎提供的只读目录，修改代码后调用官方 build 工具构建。

### N02日志夹页落地（2026-10-03）

- 用户要求核对当前分支进度并实现N02，明确继续并推送 `feat1003/samsara-story-wiring-plan`，不推workspace系列。基线 `b8645c20`；后四提交仅文档，旧过场退役代码止于 `dbd15caf`。用户通过AskUserQuestion选择功绩旁轻量“剧情记录”，不是恢复旧大日志页。
- 实施仅N02：独立键`samsara.log_leaf`、七步（一旁白＋六原句）、E01普通原件；无N12–14、无困难/地狱批注、无经济奖励。旧17–19和所有旧正文原样。新层只在旧pending/FOLLOW/FIFO消化、开场/教程/奖励/重要模态/按压/换关空闲后由唯一仲裁播；回看不写旧claimed/granted、不claim/tutorial/FOLLOW。
- 资格在RestoreData后、战斗max推断前捕获，阴性也保存historyCaptured；仅原104精确true或真实首通回调解锁，不能事后从被Sync补全的表扫描。历史已被旧版本写入true的来源不可反推，标clear_104_legacy而非完整阅读。schema两个onLoad共用、未来版本保全；正常session JSON换表通过显式订阅重新附着；reset/Stop取消token+epoch，中断不标完成，skip单独记账。
- 公开StandaloneSave.Flush仅增加boolean返回；新层失败2秒节流重试，实际File开档/写入/cjson编码失败均注入验证。开场宿主后帧接续修正避免旧callback清nil导致新门禁永久卡住，未改底层旧onFinish顺序。记录模态独占鼠标/触摸/滚轮/键盘，终焉确认open+closing也阻播。
- Runtime验证：数据496断言/0失败；集成49/49用例、763断言/0失败；八套旧剧情/教程/终焉/离线/存档回归均ALL PASS退出0。真实宿主原样源码开场四段混合自然/skip→Boot首通回调→旧17→N02跳过→E01→下帧回看通过，记录页真实截图已检查；该夹具战斗触发/File为替身，不证明完整战斗胜利或真实磁盘故障。主入口160帧Lua/资源错误0，原始FAIL仅软件渲染耗时尖峰；不以此冒称全流程通过。
- 宿主初次验收只显示标题，查明跨脚本字符串handler环境未接入，改真实源码私有env桥后实际推进；曾调用常规战斗tick暴露基线BattleScene:585 victoryMarch getter缺口，未混修。最终宿主原始PASS，200帧Lua/资源/引擎错误0（软件渲染阈值2500ms）；临时宿主夹具与meta清理，不随包。
- **再次强化用户流程：不擅自取消/退出已授权任务；每次完成、提交或确需用户决定的阻塞，简报真实结果后，最后真正调用AskUserQuestion给2–4个下一步选项，不能用普通结束语替代。尊重用户之后的停止指令、权限拒绝与安全边界。只推当前指定功能分支；PAT不写代码/Git配置/记忆，提醒撤销轮换；本地.project身份、验收截图/日志/存档不提交。**

### 轮回最小剧情切片接线规划（2026-10-03，纯文档）

- 用户选择“制定接线方案”：由精修提交 `bc85ac6b` 新建 `feat1003/samsara-story-wiring-plan`，仅规划不改Lua/队列/存档，不推workspace系列，不自动建PR/合入。
- 方案 `docs/轮回剧情最小切片接线方案-1003.md`：两单元四新节点（N02日志，N12–14征用核验）用独立字符串命名空间，不塞旧数字FIFO；旧播放源先消化，教程/奖励/开场/重要模态空闲后才新层peek/begin，token+epoch+reason结果下一帧排播，回看独立无奖。
- 源码事实：claimed在show前预写，granted为结算账本，均不能当完整阅读；73是4905入场，旧backfill只CLEAR不补ENTER；新资格严格cleared=true不看max猜；session未知字段虽可保存，旧表不自动补默认；真实磁盘写入是StandaloneSave.Flush，PDM.FlushImmediate仅日志。新方案明确schema共用迁移、保全旧字段、失败重试和reset取消租约。
- 首批N03未实现但N12引用E02，方案提供204静态货单支持；缺204历史时以铁匠案件副本标独立来源，不伪造玩家持有史。旧档缺73不设硬门槛，新调查自成语境，原70–73仅主动无奖补读。新证据/回看claim/tutorial/FOLLOW调用必须为0，不改旧奖励服务。
- 独立方案复核五项已补正：旧take=nil还要非破坏性检查pending/FOLLOW；资格不直接公开E05/批注；最小N14用独立语境不引用旧72“送走”；新结果helper只碰新槽不顺手改旧onFinish同步清理；实际Flush未来转发boolean、底层编码/开档/写失败注入和节流重试均列验收。两个session onLoad与重复normalize分别测试。当前源码路径与文档链接核实存在，纯文档diff/仓库规范通过；未实施、未重复构建。
- 本轮纯文档，所有候选API/模块/字段明确未实现。完成后只commit/push方案分支并真正AskUserQuestion给2–4项继续，尊重用户后续停止/权限拒绝，不提交PAT、本地.project、截图/日志/存档。

### 轮回剧情正文精修（2026-10-03，纯文档）

- 用户在AskUserQuestion选择“精修现有正文”：由正文提交 `8f8d1e92` 新建 `feat1003/samsara-story-polish`，只精修现有25场，不扩后半段、不接游戏，不推workspace系列。
- 同一正文文档升级v0.2：普通/困难减少制度说明，让狗的迟疑、龙的罐头/等待、鸡的短通知承担悬疑；N15不再重复问“想结束吗”，让旧鸡要求别只回复“收到”。灰印者N17交出原始副联、N25明确未结责任；少女交缺页并限定不能代人签撤离；制度精确解释留幕后档案。
- 同步修正文内部物件/揭露节奏：N01未开罐、第三道刻痕半成→N08前一日补完；原联交出后N25不取回；E04初次来源/关联名遮盖，N18核验页才揭旧队担保；未团灭路径不冒称当前队已获救，N25仍非最终交接完成。
- 最终独立复核没有主因果阻塞，四处局部连续性已收紧：本地抄片承载别页申请而非跨页纸；第三道刻痕明确“划完”；N11口粮罐与纪念罐分开；N25先登记姓名、意愿等本人填写。25场编号连续唯一，双经历/有限来源/原联不取回/不代签与未结结尾均核验；对白最长33字符，文档差异及仓库规范通过。纯文档未重复构建，前序官方Build部署保留。
- 全部仍为文档，旧对白与Lua、经济、资源零改动；当前预览部署的旧过场退役状态不回退，未据推送假称主分支已合入。完成后只commit/push本轮新分支并用AskUserQuestion给2–4项继续；尊重后续停止与权限拒绝，凭据/本地.project/日志/截图不提交。

### 轮回剧情正文扩写（2026-10-03，纯文档）

- 用户在上一轮AskUserQuestion选择“扩写剧情正文（推荐）”：授权采用已交付主轴，细写普通至炼狱新增对话与物证，暂不接入游戏。由规划提交 `faf5129d` 新建 `feat1003/samsara-story-script`，本轮仅推此分支，不推workspace系列，不自动建PR/合入。
- 产出 `docs/未寄出的撤离令-剧情正文普通至炼狱-1003.md`：五幕25场N01–N25，原情景外增量叙事，E01–E07原件及追加核验、E08后半段待办模板、作者事件表与来源守卫。N10/N19按真实团灭经历双文本；药箱十二唯一、十三另物，旧伙伴投影与三实体接驳点分开；灰印者承担原令责任，当前队主动补救；炼狱只补收件人不提前发最终交接。
- 文档独立复核提出五项一致性问题，已最小补正：货牌记录箱底修补图（不是拿货牌铆钉证明箱子）；十三号来自已登记保全库库存；夹页经林道路标交接、镜像凭片为本页载体生成；配额为有限现存总量且换担保不能增余额；N25仅登记收件人、不代替本人意愿确认。场景N01–N25连续唯一、内部文档链接存在、diff-check及仓库规范检查通过。本轮Lua/资源与faf5129d差异为空，未重复构建（上一轮官方Build成功）。
- 全部新增内容仅文档，未注册Scenario ID、未改Lua/队列/奖励、未生成素材。旧对话保持，新正文仍可审阅，折磨/湮灭后半段没有在本轮写完，不宣称完整故事已上线。
- 持续遵守：每次报告真实交付后真正调用AskUserQuestion给2–4个选项；已授权工作持续推进，尊重用户后来停止/权限拒绝。凭据、本地.project身份与截图/存档不提交。

### 轮回剧情核对与旧过场退役（2026-10-03）

- 用户指定 `workspace930`，基线 `b24cad7c`；项目与 Git 直接部署于 `/workspace`，新分支 `feat1003/samsara-loop-story-plan`，仅提交推送该分支，不推 `workspace` / `workspace930`，不擅自合并。
- 用户明确“保留对话，移除旧过场”并要求原创循环悬疑规划文档。全部 `SCENARIO` / `OPENING` / `OPENING_JOINS`、战斗台词、外祖父来信和 StoryPlayer 正文/接线不改；旧 `IntroCutscene` 时间轴及生产/调试/输入/绘制接线退役，两张JQBJ与六条专属音效连同meta删除。共享对话音效、轮回BGM、开场三人CG、角色CG和地图保留。五句过场独白只在规划附录存档，不再运行。
- 无过场旧单场轮回：Phases只准备pending和本帧ready，宿主完成全部状态回灌后再调用外部回调或默认complete；避免同步读不到pending以及加载被旧ctx覆盖。ready不持久化，异步通知仅一次。三队共享池胜负链保持，仅删除旧模块守卫。
- 新文档 `docs/轮回剧情核对与循环悬疑规划-1003.md` 暂定《未寄出的撤离令》：救援、商队劫案、镜像旧伙伴与未结撤离的因果链，先行记录页自我、八项固定物证、前五档揭真相、后续验证与共同退出。**这是待确认策划，不是已上线新剧情**；不生成视频、不改养成/掉落/奖励。剧情总表修正旧82文档60→当前10碎片，以及实际入队顺序，代码奖励不变。
- 实际验证：新增无过场专项256断言/0失败/退出0；八套既有Runtime回归退出0且成功标记核实，遗匣重跑18/18 ALL PASSED但进程未自行退出由120秒超时结束；官方最终Build成功425Lua，无旧引用。主入口离屏160帧原始PASS，Lua/资源/引擎错误0、17/17初始化完成，截图只到标题页，不宣称新档完整通关。对话五核心文件/共享素材逐字节不变，角色CG目录50文件一致；修改文件LSP无Error，缓存仍45既有Error。存活队伍探针暴露基线victoryMarch getter缺口，未混修，空队专项不证明新关常规tick或经济磁盘往返。
- 交付必须报告实际测试/构建边界。完成或真正需用户决定的阻塞后，**最后真正调用 AskUserQuestion 提供2–4个选项**；不以普通结束语代替，不擅自取消已授权任务，同时尊重用户后续停止指令与权限拒绝。PAT不写项目、Git配置/远端URL、日志或记忆；本地构建身份、存档、截图不提交。

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
