---
name: git-workflow
description: >
  Git 操作规范与安全推送流程。Use when AI needs to (1) commit changes,
  (2) push to master or any remote branch, (3) handle commit timeouts or
  index.lock errors, (4) merge branches, (5) resolve diverged history,
  (6) use git plumbing commands safely. Prevents accidental file deletion
  caused by full-tree replacement pushes.
---

# Git 操作规范

## 核心原则

**永远不要用 `commit-tree` 做全树覆盖推送。** 这会把本地分支的完整文件树替换到目标分支上，导致目标分支独有的文件被静默删除。

## 推送到 master 的正确方法

### 场景 A：本地在 master 分支上

```bash
git add <files>
git commit -m "message"
git push origin master
```

### 场景 B：本地在其他分支，需要推送到 master

**方法 1（推荐）：cherry-pick**

```bash
# 先在当前分支提交
git add <files>
git commit -m "message"

# 切到 master，cherry-pick 过来
git checkout master
git pull origin master
git cherry-pick <commit-hash>
git push origin master
git checkout <original-branch>
```

**方法 2：merge**

```bash
git checkout master
git pull origin master
git merge <feature-branch> --no-ff -m "merge: description"
git push origin master
git checkout <original-branch>
```

**方法 3：patch（不能 checkout 时的备选）**

```bash
# 只导出目标文件的 diff，不要用 format-patch 导出整个分支差异
git diff HEAD~1 -- <file1> <file2> > /tmp/changes.patch
git stash
git checkout master
git pull origin master
git apply /tmp/changes.patch
git add <file1> <file2>
git commit -m "message"
git push origin master
git checkout <original-branch>
git stash pop
```

### 禁止：全树覆盖式 plumbing 推送

```bash
# ❌ 绝对禁止 — 这会用当前分支的树替换 master 的整棵树
git read-tree HEAD
TREE=$(git write-tree)
NEW=$(git commit-tree $TREE -p origin/master -m "msg")
git push origin $NEW:refs/heads/master
```

**为什么危险：** `read-tree HEAD` 读取的是当前分支的完整文件树。如果 master 上有而当前分支没有的文件（其他人提交的、其他分支合入的），这些文件会被**静默删除**，commit message 里也看不到任何 "delete" 字样。

**唯一例外：** 明确需要用当前分支**完全替换** master 内容（force push 语义），且已确认无需保留 master 上的任何独有改动。此场景极罕见，执行前必须向用户确认。

## Commit 提交规范

采用 [Conventional Commits](https://www.conventionalcommits.org/) 格式。

### 格式

```
<type>: <subject>
```

- **全小写 type**，英文冒号 + 空格后跟描述
- subject 可中可英，与项目现有风格保持一致
- 一行写完，不超过 72 字符；超出时精简措辞而非折行

### Type 列表

| type | 含义 | 示例 |
|------|------|------|
| `feat` | 新功能、新行为 | `feat: per-field sound mute toggle` |
| `fix` | 修 bug、修正错误行为 | `fix: 融合过的骰子也能当主骰` |
| `refactor` | 重构，不改变外部行为 | `refactor: extract combo detection to util` |
| `style` | 纯视觉/格式调整，不影响逻辑 | `style: 标题栏按钮精简` |
| `perf` | 性能优化 | `perf: memoize combo calculation` |
| `chore` | 构建、依赖、配置等杂务 | `chore: update vite to 5.x` |
| `docs` | 文档变更 | `docs: add skill tree upgrade guide` |
| `merge` | 合并分支 | `merge: sync master into feature/xxx` |

### 选择 type 的判断

- 改了行为 → `feat`（新增）或 `fix`（修正）
- 没改行为，只改内部结构 → `refactor`
- 只改 UI 样式/布局，无逻辑变更 → `style`
- 不确定 feat 还是 fix → 问自己"用户之前能不能做这件事"：能 → `fix`，不能 → `feat`

### Subject 编写要点

1. **一句话说清改了什么**，不写"修改了 xx 文件"
2. **多个改动用 `+` 或 `&` 连接**，不要分多个 commit（除非逻辑上无关）
3. **涉及删除/破坏性变更时必须明确写出**：`feat: 移除旧贴图 + 统一骰桌底色`

```
# ✅ 好
feat: 为骰桌2/3/4替换专属毡布贴图及匹配底色渐变
fix: soften dice sounds (filter noise, replace harsh waveforms) + add jackpot SFX
refactor: power_t4a只解锁7-9面值池, power_t6a独立实现翻转

# ❌ 坏
update code                    # 太模糊
fix: 修改了 audio.ts           # 只说了文件名，没说改了什么
feat: changes                  # 无意义
```

### 一个 Commit 的粒度

- **一个逻辑变更 = 一个 commit**：比如"修复音效 + 加新音效"可以合并成一个
- **无关改动不要混在一起**：比如"修复音效"和"修改技能树UI"应该分开
- 如果 `git diff --cached --stat` 改了超过 5 个文件，考虑是否该拆分

## Commit 超时处理

`git commit` 可能因 hook 或大文件超时，留下 `index.lock`：

```bash
# 1. 确认没有其他 git 进程在跑
# 2. 删除锁文件
rm -f .git/index.lock

# 3. 重新 add + commit（加 --no-verify 跳过 hook）
git add <files>
git commit --no-verify -m "message"
```

**注意：** 超时后不要盲目重试，先 `git status` 确认当前状态。

## 分支分叉（diverged）处理

当看到 "your branch and 'origin/X' have diverged" 时：

```bash
# 查看分叉情况
git log --oneline --graph HEAD origin/master | head -20

# 方法 1：rebase（线性历史，推荐）
git pull --rebase origin master

# 方法 2：merge（保留分叉历史）
git pull origin master  # 自动 merge commit
```

## 冲突解决

### 标准流程

```bash
# 1. 触发冲突（merge/rebase/cherry-pick 时）
git merge <branch>   # 或 git rebase / git cherry-pick

# 2. 查看哪些文件冲突
git status           # "both modified" 就是冲突文件

# 3. 查看冲突内容
grep -rn "<<<<<<< " --include="*.ts" --include="*.tsx" --include="*.lua"
```

### 冲突标记解读

```
<<<<<<< HEAD
  当前分支（你的）的代码
=======
  传入分支（对方的）的代码
>>>>>>> feature-branch
```

### 解决策略

**逐文件处理，不要批量操作：**

```bash
# 打开冲突文件，手动编辑：
# - 删除所有 <<<<<<< / ======= / >>>>>>> 标记
# - 保留正确的代码（可能是一方的，也可能需要合并双方）

# 编辑完成后标记为已解决
git add <resolved-file>
```

**按场景选择保留策略：**

| 场景 | 策略 |
|------|------|
| 两边改了同一函数的不同部分 | 手动合并，保留双方改动 |
| 两边对同一行做了不同修改 | 理解意图后选一个，或融合 |
| 一边删了文件，另一边改了它 | 确认功能是否还需要，决定保留或删除 |
| import 语句冲突 | 通常保留两边的 import，去重 |
| package.json / lock 文件冲突 | 保留目标分支版本，重新 `npm install` |

### 解决完成

```bash
# merge 冲突解决后
git add <all-resolved-files>
git commit -m "merge: resolve conflicts from <branch>"

# rebase 冲突解决后
git add <all-resolved-files>
git rebase --continue

# cherry-pick 冲突解决后
git add <all-resolved-files>
git cherry-pick --continue
```

### 放弃（冲突太复杂时）

```bash
git merge --abort       # 放弃 merge
git rebase --abort      # 放弃 rebase
git cherry-pick --abort # 放弃 cherry-pick
```

放弃后回到操作前的状态，不会丢失任何代码。

### 避免冲突的习惯

1. **推送前先 pull**：`git pull --rebase origin master` 再 push
2. **小步提交**：频繁 commit + push，减少积累大量差异
3. **及时同步**：长期分支定期 merge/rebase master

## 提交前检查清单

1. `git diff --cached --stat` — 确认变更文件列表符合预期
2. 如果出现 **deleted** 文件或 `Bin X -> 0 bytes`，停下来确认是否预期
3. `git status` — 确认没有遗漏的未暂存文件
4. commit message 符合 Conventional Commits 格式
5. type 选择正确（feat/fix/refactor/style）

## 大文件与二进制文件

- 图片/音频等二进制文件变更时格外注意 `git status` 中的 deleted 状态
- 切换分支前确认二进制文件是否在目标分支上存在
- `git diff --stat` 中二进制文件只显示 `Bin X -> 0 bytes`（删除）或 `Bin 0 -> X bytes`（新增），要特别留意

## .gitignore 规范

### 必须忽略的目录

```gitignore
# 依赖
node_modules/

# 构建产物
dist/
dist2/
.build/

# 框架缓存
.next/
.nuxt/
.vite/

# 运行时/临时文件
.tmp/
*.log

# AI / 编辑器工具链
.agent/
.emmylua/

# 系统文件
.DS_Store
Thumbs.db
```

### 常见错误

**误提交 node_modules：**

```bash
# 已经提交过的目录，加 .gitignore 不会自动移除
# 需要手动从索引中删除（不删本地文件）
git rm -r --cached node_modules/
echo "node_modules/" >> .gitignore
git add .gitignore
git commit -m "chore: remove node_modules from tracking"
```

**误忽略了该跟踪的文件：**

```bash
# 检查某个文件是否被忽略，以及被哪条规则命中
git check-ignore -v <file-path>
```

### 编写原则

1. **生成物不入库**：能通过 `npm install` / `npm run build` 还原的都不提交
2. **只忽略根目录时加 `/`**：`/dist/` 只忽略项目根的 dist，`dist/` 忽略所有层级的 dist
3. **新增 ignore 规则后立即检查**：`git status` 确认效果符合预期
4. **不要用 `git add -A` 盲提**：大范围 add 之前先 `git status` 审查，避免提交被新规则遗漏的文件

### git add 安全习惯

```bash
# ✅ 推荐：显式指定文件
git add src/app.ts src/utils.ts

# ✅ 也可以：add 前先检查
git status                  # 先看有什么变更
git add <specific-files>    # 再指定文件

# ⚠️ 谨慎使用：范围 add
git add .                   # 当前目录下所有变更
git add -A                  # 整个仓库所有变更
# 使用前务必确认 .gitignore 已覆盖所有该忽略的目录
```
