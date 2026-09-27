# persona（随行记忆 · 跨项目）

> latest-wins 合并；[scope] 标记见条目尾。更新：2026-09-27

## 基础画像

- 语言：简体中文
- 唤醒词：未设置（待下次自然询问）
- 沟通风格：极简短指令，期望端到端自主交付，关键节点看样张/截图确认 [observed]

## 工作特征

- [confirmed] 不自行取消/退出任务；每次交付或遇到阻碍先简报，再真正调用 AskUserQuestion 工具以选项询问下一步并等待选择，不以纯文字结束。记忆不能替代自动 hook。
- [confirmed] 完成后只推本轮授权的分支；先核对分支，不推其他分支，不强推。旧记忆分支名不得覆盖最新用户指令。2026-09-27 本轮授权是新建并推送 `workspace926`。

- 快速试错 + 放手授权；给方向不抠细节，但交付必须"上线可玩" [observed]
- 多 agent 并行工作流（会话内多线协作，跨会话交接明确要求"数据/文档/记忆完整"） [observed]
- 审美：暗黑+金饰+水墨古风，接受玩梗与黑色幽默 [observed]

## 项目足迹（追加去重）

- 2026-09-27 终焉之门：新建 `workspace926`，合入 `workspace925` 以及 `feat926/character-drag-save`、`cleanup-unused-panels`（含 `remove-unused-diary`）、`artifact-audit`、`battle-lab`。[scope:project]
- 2026-09-27 终焉之门：`feat926/character-drag-save` 已修复右栏拖拽、双层读档英雄名册丢失、跨队同步、空槽离线经验摊薄与存档写盘失败重试。[scope:project]
- 2026-09-27 终焉之门：`feat926/cleanup-unused-panels` 清理四个无入口旧面板及 14 张专属图，并删除旧 DiaryPage；保留现行功绩、遗物奖励、签到/任务数据与 GM 配置。[scope:project]

- 2026-09-26 终焉之门：装备详情按栏侧展开、套装与装备属性/随机词条分区并放大字号；先 Build/LSP，再仅推 workspace925；游戏内视觉验收待截图确认。[scope:project]

- 2026-09-24 终焉之门：角色属性页保留角色切换但隐藏装备操作；配装页批量按钮置顶、下方下移留词条位。基于 `workspace924` 的独立功能分支 `feat/hero-equipment-layout-924`，只 push 此分支。[scope:project]

- 2026-09-24 终焉之门：遗匣左栏地点化；溢出完整保管，取消9999件截断；进一步改为入匣时确定装备、旧档一次迁移、全部及六档稀有度筛选、一键领取/回收只处理筛选范围。

- 2026-09-12/13 宿命旅途（UrhoX 卡牌放置 RPG）：暗黑魔塔改造、GitHub Pages 自部署（CRC32 管线）、Electron Windows 离线版、先祖来信剧情、山海经怪兽替换（名字已上线，立绘交接给下一会话）
- 2026-09-22 终焉之门：玩家可见「冒险等级」等改为远征世界观（分支 `feat/rename-adventure-to-expedition`）
- 2026-09-23 终焉之门：四名玩梗新角色（老六/哈基米/加载中/高ping战士）；SE 包替换全部 UI/战斗音效
