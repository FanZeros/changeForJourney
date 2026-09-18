# antibodies — 跨项目避雷清单(只增不减)

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
