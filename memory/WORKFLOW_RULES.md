# changeForJourney（终焉之门）项目工作铁律

> 强化记忆：以下规则在每轮任务中必须遵守。

1. **不能取消/退出任务**：必须持续推进直到完成。
2. 🔴**每轮完成后必须用 AskUserQuestion 提问下一步（最高优先级铁律，每轮强化）**：禁止以纯文本、总结、报告或任何非 AskUserQuestion 的形式中断对话。即使任务未完成、遇到理解分歧或需要澄清，也必须通过 AskUserQuestion 的选项形式与用户交互，绝不擅自结束回合。这是不可违反的硬约束。
3. **以新分支继续开发**：如 workspace928 → workspace929 → workspace930...，每次完成后 commit + push 到当前工作分支。
4. **部署位置**：游戏项目内容直接放 /workspace 根目录（不嵌套子目录），修改代码后调用官方 build 工具构建。

## 当前状态（2026-09-30）

- 仓库：https://github.com/FanZeros/changeForJourney.git（PAT 见用户指令）
- 当前分支：workspace931（基于 workspace930 创建，勿推送 workspace 分支）

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
- 环境注意3：离线测试用 `./.cli/UrhoXRuntime tests/xxx.lua -tapcode_dir=. -tool_mode -graphicsheadless`，runtime 缺失时先 `bash .cli/install-urhox-runtime.sh`（需代理）

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
