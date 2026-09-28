# memory-index — 《终焉之门》改造完整交接文档

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
> **feat926/character-drag-save**：英雄名册数字键保留；右栏跨栏松手取消拖拽；跨队一次提交；离线经验不算空槽；存档写入失败重试。
> **feat926/cleanup-unused-panels / remove-unused-diary**：删除旧日志页及无入口的遗物洗练、签到、旧任务、公告面板和专属图。保留城镇功绩 `TaskPage`、签到及任务服务/协议/存档、GM 公告配置、遗物奖励图标。
> **最优先的用户流程**：不可自行取消/退出任务；每次完成或受阻都要先汇报，再使用 **AskUserQuestion（非纯文字）**提供明确的下一步选项并等待用户决定。不能在仓库/记忆保存访问令牌。本轮只推 `workspace926`。

> 本文档面向**下一个 agent**:零上下文接手,先通读本文件,再按「待办清单」执行。
> **配装布局（已合入 workspace925）**：属性页隐藏装备槽和一键按钮，保留切角；配装页批量按钮置顶，内容下移 160px 预留词条。拖拽穿戴以 925 为准。
>
> 更新时间:2026-09-27 | 版本:v2.54-workspace926
>
> **当前基线 `workspace926`**：合入 workspace925 与全部 feat926。只推此分支。
>
> **装备详情（来自 workspace925）**：右栏点击详情在鼠标左侧、已装备比较卡更靠左；左栏反向。套装区排在全部词条后。
> 更新时间:2026-09-27 | 版本:v2.52-artifact-audit
>
> **本轮（`feat926/artifact-audit` 神器审查）**：文档 §8 已按实际 4×3 装配、品质池与保底规则更新。`ArtifactRuntime` 按单位重置/更新并清理临时效果，影羽斗篷按初始 +200% 的比例衰减，审判锤切目标清旧层；三行加入首次死亡拦截与亡魂计时，通天塔逐名阵亡拦截。原有 `battle_stage_switch_test` 增至 24 个断言，0 FAIL；LSP 0 Error，官方 Build 成功。主入口 60 帧 0 Lua 错，5 个既有剧情日记图片缺失仍使完整 validate FAIL，不能宣称主入口完全通过。抽取中途失败的非原子性仅在人为损坏定义时可达，留待专项审查。操作不要在仓库写凭证或把测试生成的存档提交。
> **流程硬性要求（当前授权）**：不能取消/退出任务，每次交付先汇报结果、最后必须通过 AskUserQuestion 给选项问下一步，不能纯文字结束。本轮只 push `workspace926`。自动化 Stop hook 尚未配置，记忆本身不能保证执行。
>
> **上一轮（`workspace925` 装备详情）**：右栏点击详情在鼠标左侧、已装备比较卡更靠左；左栏反向。点击锚点用鼠标位置，悬停跟随、钉住不漂移；套装区排在全部词条后，独立描边底板、放大字体及换行，详情热区随内容高度变化。Lua LSP 0 Error，官方 Build 成功；本地 Runtime 安装超时，尚无实际页面截图验收。下一步用游戏预览点击左右栏带/不带已装备比较的详情，特别检查最长套装描述。
> **旧会话历史**：曾授权只 push `workspace925` 或某个 `feat926/`。这些授权已被本轮「新建并推送 workspace926」覆盖。访问令牌不写入仓库或记忆。
> 更新时间:2026-09-27 | 版本:v2.54-power-calibration-samples
> 更新时间:2026-09-28 | 版本:v2.61c-rec-power-i18n
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
