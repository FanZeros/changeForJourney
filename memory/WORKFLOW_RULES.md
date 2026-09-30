# changeForJourney（终焉之门）项目工作铁律

> 强化记忆：以下规则在每轮任务中必须遵守。

1. **不能取消/退出任务**：必须持续推进直到完成。
2. **每轮完成后必须用 AskUserQuestion 提问下一步**：禁止以纯文本、总结或其他任何非 AskUserQuestion 的形式中断对话。
3. **以新分支继续开发**：如 workspace928 → workspace929 → workspace930...，每次完成后 commit + push 到当前工作分支。
4. **部署位置**：游戏项目内容直接放 /workspace 根目录（不嵌套子目录），修改代码后调用官方 build 工具构建。

## 当前状态（2026-09-30）

- 仓库：https://github.com/FanZeros/changeForJourney.git（PAT 见用户指令）
- 当前分支：workspace930
- 已完成任务：锻炉页等阶角标统一右上显示
  - `scripts/ui/blacksmith/BlacksmithPage.lua`：工作台槽升阶角标 "+N" 从左上（drawTextStroke 绿 0x67ff75）改为右上（NVG_ALIGN_RIGHT+TOP、字体36、绿 0x00ff60 + 黑描边），与仓库格子 BackpackGrids.lua:143 的角标位置/样式完全一致；删除无用常量 EQUIP_LV_FONT_SIZE
  - 同轮梳理洗练四石逻辑（见下方"洗练石头逻辑速览"）
  - LSP 0 错误；build 通过
- 环境注意：新工作区克隆仓库后，`.project/project.json` 里的原作者身份（project_id m_tfv3 / developer_id 400200）与本地 workspace 身份冲突导致 build 报 "local taptap identity conflicts with claimed database identity"；本地已剥离 project_id/author/developer_id 字段（不提交 git），构建恢复正常

## 洗练石头逻辑速览（BlacksmithService.RefineEquip）

- 入口：洗练 tab 选额外资源 → RefineEquip(uid, seq, extraResource, lockedIndices)
- 公共消耗：精粹 = floor(QUALITY_COST[q].refBase * (1 + lv*refLvScale))，双手×2；锁定任意词缀整体×REFINE_LOCK_COST_MULT(1.5)；洗练次数 refineCount 仅计数封顶20，不影响费用
- 无石（普通洗练）：未锁定词缀重随机（种类+数值），结果存 pendingRefines 待玩家点"替换"；锁定数必须 < 词缀总数
- 洗练石 enhanceStone（1个）：词缀种类不变只重随数值/品质等级（rerollAffixValuesWithLocks），同样待替换
- 点金石 destroyStone（消耗=当前品质N个）：提品 +1（上限按最高通关难度：普通→4史诗/困难→5传说/噩梦及以后→6），保留原词缀、槽位不足补 roll；**直接生效**无需替换；无词缀装备也可用
- 腐化石 corruptStone（1个）：按权重 roll 7 种魔化效果（无变化25/单条-50% 20/新增第三条20/单条+50% 20/两条+50% 5/基础属性+50% 5/魔化词条5），**直接生效**；corruptCount+1，最多3次；首次腐化记录 corruptRevert 基线供净化回滚
- 神圣石 sacredStone（1个）：净化腐化（按 revert 基线回滚词缀与基础倍率、清 corruptCount），不耗精粹、不加洗练次数，直接生效
- 互斥规则：corruptCount>0 时禁止普通洗练/洗练石/点金石，只允许腐化石继续腐化或神圣石净化

## 标准收尾流程

代码修改 → LSP 诊断 0 错误 → mcp build → （必要时离线验证逻辑）→ git commit → git push → **AskUserQuestion 问下一步**
