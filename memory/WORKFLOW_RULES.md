# changeForJourney（终焉之门）项目工作铁律

> 强化记忆：以下规则在每轮任务中必须遵守。

1. **不能取消/退出任务**：必须持续推进直到完成。
2. **每轮完成后必须用 AskUserQuestion 提问下一步**：禁止以纯文本、总结或其他任何非 AskUserQuestion 的形式中断对话。
3. **以新分支继续开发**：如 workspace928 → workspace929 → workspace930...，每次完成后 commit + push 到当前工作分支。
4. **部署位置**：游戏项目内容直接放 /workspace 根目录（不嵌套子目录），修改代码后调用官方 build 工具构建。

## 当前状态（2026-09-29）

- 仓库：https://github.com/FanZeros/changeForJourney.git（PAT 见用户指令）
- 当前分支：workspace929（基于 workspace928 创建，已推送）
- 已完成任务：选关弹窗终焉神殿拆分为单难度独立组
  - `scripts/ui/battle/stage/StageSelectDialog.lua`：collectChapterGroups 不再合并 14 座终焉为单个 "T" 组；每座终焉独立成组 key="T<神殿id>"，沿关卡链排在对应难度 23 章之后（普通23章→普通终焉→困难1-23章→困难终焉→噩梦1章→…）；终焉组副标题显示难度名；chapterHue 按神殿 id 取色
  - `scripts/tests/chapter_team_offline_test.lua`：断言更新为 345+14 组，校验困难终焉位置与副标题
  - LSP 全工作区 0 错误；build 通过；已 commit 4b43cd36 并 push

## 标准收尾流程

代码修改 → LSP 诊断 0 错误 → mcp build → （必要时离线验证逻辑）→ git commit → git push → **AskUserQuestion 问下一步**
