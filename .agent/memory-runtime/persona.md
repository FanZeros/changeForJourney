# persona（随行记忆 · 跨项目）

> latest-wins 合并；[scope] 标记见条目尾。更新：2026-09-27

## 基础画像

- 语言：简体中文
- 唤醒词：未设置（待下次自然询问）
- 沟通风格：极简短指令，期望端到端自主交付，关键节点看样张/截图确认 [observed]

## 工作特征

- [confirmed] 不自行取消/退出任务；每次完成或受阻先汇报，再用 AskUserQuestion 选项询问下一步，不纯文字结束。记忆只能提醒，事件自动化需 harness hook。
- [confirmed] 完成后提交并只推本轮授权的当前功能分支；先核对分支，不推其他分支，不强推。本轮仅 `feat926/battle-lab`，不合并或推送 workspace；旧记忆分支名不得覆盖最新用户指令。

- 快速试错 + 放手授权；给方向不抠细节，但交付必须"上线可玩" [observed]
- 多 agent 并行工作流（会话内多线协作，跨会话交接明确要求"数据/文档/记忆完整"） [observed]
- 审美：暗黑+金饰+水墨古风，接受玩梗与黑色幽默 [observed]

## 项目足迹（追加去重）

- 2026-09-28 终焉之门：战力预估生产接线（玩家可见但默认关闭，非破坏性）。`CharacterPower` 抽出共享 `buildHeroAttrs`，官方 `calcHeroPower` 数字不变，新增并列 `calcHeroEstimate`（CPE 基础+觉醒+神器），经 CharacterPanel→Detail→Draw 注入；卡面「预估 N」副行由 `SHOW_ESTIMATE` 控制、默认 false（系数未跨全阵容标定、本环境无法截图验收），真人验收后 `Draw.setEstimateVisible(true)` 开启。新增 `tests/character_power_estimate_test.lua` 9 断言 ALL PASS（战力不回归 106/479、预估>0、未知英雄不崩），主入口 validate lua_errors=0，全回归通过。当前玩家数值零变化，只推 `feat926/battle-lab`。[scope:project]

- 2026-09-27 终焉之门：治疗系数拟合。新增 `tests/battle_lab_fit_healer.lua`（22 组牧师采样）+ `fit_power_estimate.py --mode healing`（HPS 口径、按 healTakenRatio 剔除需求截断饱和）。关键发现：治疗=min(供给,需求)，304/305 阵亡带全饱和（W68@17→32 HPS 24.0→23.6 几乎不动），仅 303 超时带 8 组非饱和可拟合；R²=0.32、输出组≈0.48 → 确认初值 HEALER_ATK_FACTOR=0.5 与数据一致并保留。至此 OFF_FACTOR(0.10)/HEALER(0.5) 均有数据依据。回归全绿、拟合可复现，正式公式未改，只推 `feat926/battle-lab`。[scope:project]

- 2026-09-27 终焉之门：分项计价系数数据驱动拟合。新增 `tests/battle_lab_fit.lua`（31 组败局带采样，新 API `Lab.runSingle`）+ `_proc/fit_power_estimate.py`（岭回归/非负截断/剔除饱和样本）。关键方法论：败局总输出被存活时间混杂，必须用 DPS 口径回归（physical R² 0.03→0.43、magical 0.52）。可信拟合异系攻击系数=0 → OFF_FACTOR 0.25→0.10（保留小正值防显示归零）；healing 拟合不成立保留 0.5 待牧师专属采样。方向断言复验更清晰（战士 128>122、法师 126>119）。报告新增 heroPowers[].groups 四组分解。回归全绿，正式公式未改，只推 `feat926/battle-lab`。[scope:project]

- 2026-09-27 终焉之门：实现分项计价战力原型 `systems/CombatPowerEstimate.lua`（仅 battle-lab 报告用，正式公式未改）：官方同底座 + 按伤害大类给 phys/mag/heal 区别系数（异系 0.25、治疗系输出 0.5）。方向验证通过：战士同战力 160 预估力量 133>智力 128（实测 3/40 vs 0/40），法师同战力 112 预估智力 85>力量 83（输出 287 vs 193）；边界测试第 9 节 + 旧入口/切关回归 ALL PASS。系数未拟合，只作方向参考。只推 `feat926/battle-lab`。[scope:project]

- 2026-09-27 终焉之门：补齐 battle-lab 边界样本。新增 `tests/battle_lab_boundary_test.lua`（60+ 断言覆盖 `Lab.prepare` 全部拒绝分支/钳制/levelRange/ascendLevel 边界，headless ALL PASS 且自带退出）；真实校准 4×40 局：Lv7 tier1 上边界在 302/303 双侧全胜/全败（难度悬崖），Lv8 tier2 下边界在 303 得到非饱和样本——同战力 160 力量戒 3/40 vs 智力戒 0/40（种子 3926 复验 1/40 vs 0/40），输出+333/承伤-55，与 v2.54 方向一致。未动正式战力权重，只推 `feat926/battle-lab`。[scope:project]

- 2026-09-27 终焉之门：更正先前 C10/C4 Lv.1 超出装备掉落范围，不能作为正常掉落平衡证据。实验已加入等级范围拒绝；合法 C1 力量戒与 C13 秘识饰物，在物理战士 Lv.1 同显示战力 112、40 局首通分别 40/40 与 14/40（另种子 40/40 与 10/40），跨 101–103、法师/游侠、双人队扩样。未动正式战力权重，只推 `feat926/battle-lab`。[scope:project]

- 2026-09-27 终焉之门：独立战斗实验扩展确定性普通装备 A/B 同种子校准；历史 20 局 `C10`/`C4` Lv.1 对照**超出两个模板等级范围，不可作平衡结论**，仅说明公式机制；详见上条合法样本。只推 `feat926/battle-lab`，尚未修改全局战力权重。[scope:project]

- 2026-09-27 终焉之门：独立战斗平衡工作台与批量 JSON 测试，真实三行战斗复用、固定种子复现；仅推 `feat926/battle-lab`。界面离屏验证通过，真人鼠标操作待验收。[scope:project]

- 2026-09-26 终焉之门：装备详情按栏侧展开、套装与装备属性/随机词条分区并放大字号；当时只推 workspace925（**历史授权，本轮已失效**）；游戏内视觉验收待截图确认。[scope:project]

- 2026-09-24 终焉之门：角色属性页保留角色切换但隐藏装备操作；配装页批量按钮置顶、下方下移留词条位。基于 `workspace924` 的独立功能分支 `feat/hero-equipment-layout-924`，只 push 此分支。[scope:project]

- 2026-09-24 终焉之门：遗匣左栏地点化；溢出完整保管，取消9999件截断；进一步改为入匣时确定装备、旧档一次迁移、全部及六档稀有度筛选、一键领取/回收只处理筛选范围。

- 2026-09-12/13 宿命旅途（UrhoX 卡牌放置 RPG）：暗黑魔塔改造、GitHub Pages 自部署（CRC32 管线）、Electron Windows 离线版、先祖来信剧情、山海经怪兽替换（名字已上线，立绘交接给下一会话）
- 2026-09-22 终焉之门：玩家可见「冒险等级」等改为远征世界观（分支 `feat/rename-adventure-to-expedition`）
- 2026-09-23 终焉之门：四名玩梗新角色（老六/哈基米/加载中/高ping战士）；SE 包替换全部 UI/战斗音效
