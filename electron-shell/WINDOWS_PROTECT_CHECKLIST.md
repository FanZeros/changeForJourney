# 本机 Windows 验证清单 · --protect 受保护打包 + L2 字节码 Q1

> 适用分支：`feat927/ele-protection-research-0927`（≥ commit `cccd920`）
> 目的：在真实 Windows 环境完成沙箱内无法验证的三件事——
> ①`--protect` 四步链全跑通并打出可玩的混淆包；②实机启动/存档回归；③L2 字节码 Q1 判定。
> 预计耗时：首次 40-70 分钟（大头是 npm 下 Electron 二进制 + preview prepare + 复制 assets）。

## 0.5 本机快速测试命令（Windows cmd，从切分支开始）

> 分五段：A 切分支装依赖 → B 四套测试 → C 效果预览/全量 → D --protect 打包全链 → E 相似度验证。
> B/C 纯本地（只需 Python + luaparser/lupa），D/E 需要本机 Maker 绑定与打包环境。

### A. 切分支 & 装依赖
```bat
cd /d C:\Users\fanzero\Desktop\GameMaking\changeForJourney
git fetch origin
git checkout feat927/ele-protection-research-0927
git pull
git log --oneline -3
REM 顶部应见: 925c68b feat: --file 单文件模式支持 --strip-comments

python -c "import sys; print(sys.executable)"
python -m pip install luaparser lupa
python -c "import luaparser, lupa; print('deps OK')"
```

### B. 四套回归测试（纯本地，约 2 分钟）
```bat
python electron-shell\test_lua_obfuscator.py
REM 期望: == behavior equivalence: 21 passed, 0 failed, 0 rejected ==

python electron-shell\test_lua_obfuscator_docsync.py
REM 期望: ==== OVERALL: ALL PASS ====

python electron-shell\test_field_rename.py
REM 期望: == synthetic field-rename: 8 passed, 0 failed ==

python electron-shell\test_strip_comments.py
REM 期望: == strip comments: ALL PASS ==
```

### C. 效果预览 & 全量产物
```bat
REM C1 单文件(默认档:仅改名,注释保留)
python electron-shell\lua_obfuscator.py --file scripts\shared\StageUtils.lua

REM C2 单文件(交付档:改名+剥注释+@param同步) —— 推荐先看这个
python electron-shell\lua_obfuscator.py --file scripts\shared\StageUtils.lua --strip-comments

REM C3 全量档A/档B 输出到仓库外目录(各约 5-8 分钟,耐心等)
python electron-shell\lua_obfuscator.py --source-root . --output-root ..\out-A
python electron-shell\lua_obfuscator.py --source-root . --output-root ..\out-B --strip-comments
REM 期望: files=361 changed=344 unchanged=16 rejected=1
REM       (rejected=DarkIcon.lua 解析失败保持明文,预期内)

REM C4 @param 残留校验(应 0)
python electron-shell\check_param_residual.py ..\out-B
REM 期望: checked=361 parse_fail=1 residual_param_mismatch=0

REM C5 全量行为等价抽样(需 lupa)
python electron-shell\verify_obfuscation_sample.py ..\out-B .
REM 期望: behavior sample: tested=71 passed=71 mismatch=0

REM C6(可选)档C 字段改名: 需 --emmylua-root 指向含 .emmylua/urhox-libs 的 Maker 工程根
REM python electron-shell\lua_obfuscator.py --source-root . --output-root ..\out-C --strip-comments --rename-fields --emmylua-root <你的Maker工程根>
```

### D. --protect 打包全链（出 Windows 成品包）
```bat
REM 前提: 仓库根有 .maker-mcp(本机 Maker 绑定生成)。没有则先双击 maker-mcp\update-maker-mcp.bat
dir /a .maker-mcp

electron-shell\build_protected_windows.bat
REM 四步成功标志逐条对照本清单 §1;产物在 electron-shell\release\*.zip
```

### E. 相似度验证（需 D 的成品包）
```bat
REM E1 克隆工具仓库(若本机没有)
cd /d C:\Users\fanzero\Desktop\GameMaking
git clone https://github.com/FanZeros/tempGame.git

REM E2 解压成品包 zip 到 ..\zip-test 后,比对"包内 game"与"工程源码"
cd changeForJourney
python ..\tempGame\skills\source-similarity\scripts\compare_lua_similarity.py --game ..\zip-test\resources\game --scripts scripts
REM 期望(交付档B): symmetric similarity ~39%, exact ~17

REM E3(可选)基线对照: 未混淆 dist(Maker Build 仓库根 dist) vs 源码,应 100%
python ..\tempGame\skills\source-similarity\scripts\compare_lua_similarity.py --game dist --scripts scripts
```

## 0. 准备（一次性）

- [ ] 装好 Python 3.10+（`python --version`）与 Node.js（`npx --version`）
- [ ] `pip install luaparser`（lupa 只有跑仓库内测试才需要，可选 `pip install lupa`）
- [ ] `git fetch origin && git checkout feat927/ele-protection-research-0927 && git pull`
- [ ] 确认磁盘余量 ≥ 3GB（assets 真实复制 ~400MB ×2 + dist ~400MB + Electron ~1GB）
- [ ] 确认仓库根有最新 `assets/`、`.project/`、`scripts/`（正常 clone 即有）

## 1. --protect 四步链全跑通

- [ ] 仓库根双击 `electron-shell\build_protected_windows.bat`
      （或 cmd 里跑同名命令；观察四步日志逐步推进）

**步骤 1（protect_build）成功标志：**
- [ ] 日志出现 `lua files=361 changed=344 unchanged=16 rejected=1`
      （rejected=1 是 `scripts/core/DarkIcon.lua`，解析失败保持明文，属预期）
- [ ] 生成 `.tmp\protected-workspace\`，其下 `scripts\main.lua` 开头是混淆代码
      （`local _z0_ = nil` 等 `_zN_` 名），`protect-report.json` 存在
- [ ] `.tmp\protected-workspace\assets\` 是**真实目录**（不是链接），大小 ~398MB

**步骤 2（preview prepare / 官方 Build）成功标志：**
- [ ] 命令退出码 0（无 LSP Error 中断）
- 若报 `Preview requires a bound Maker project with .maker-mcp/config.json`：
  说明仓库根缺 `.maker-mcp/`（Maker 绑定目录，被 gitignore 不入库，各机器本地生成）。
  protect_build.py 已自动复制它进混淆工作区；若源仓库根就没有，先在仓库根跑一次
  `maker-mcp\update-maker-mcp.bat`（或任何一次成功的官方 preview prepare / Maker 绑定）
  生成 `.maker-mcp\config.json`，再重跑本 bat。
- [ ] `%USERPROFILE%\.taptap-maker\preview\<...>\preparations\<...>\source\dist\` 生成
- [ ] **关键**：该 dist 的 `<版本>\manifest-origin.json` 里统计资源——
      应有 `361 .lua + 770 .png + 77 .ogg + 6 .atlas + 字体`（共约 1226 项）。
      快速核对（cmd）：`findstr /C:"\"ext\"" <dist>\<版本>\manifest-origin.json | find /C "png"`
      若 png/ogg 为 0 → assets 没被烘焙，**停**，把日志发回会话排查（见 §5）。

**步骤 3（prepare_local_dist）成功标志：**
- [ ] 日志 `assets_gate_ok non_lua={...含 .png 与 .ogg...}`（资产闸门通过）
- [ ] 日志 `ok <版本> lua 361 ...`，`electron-shell\game\` 生成且含混淆版资源

**步骤 4（pack_release）成功标志：**
- [ ] 日志出现 `（--protect 混淆基准）` 字样（说明确实以混淆树为校验基准）
- [ ] `prepare 产物校验通过：v<版本>、361 个 Lua 文件与基准源码树一致`
- [ ] electron-builder 完成，`electron-shell\release\ZhongYanZhiMen-win64-offline-<版本>.zip` 生成

## 2. 包内容抽检（证明保护生效）

- [ ] 解压 zip，进 `resources\game\assets\`，任选一个 `.lua` 用记事本打开：
      **应看到 `_z0_`/`_z1_` 等混淆名**，而不是 `local M = {}`、`function M.Get()` 原文
- [ ] 对照：仓库 `scripts\shared\StageProvider.lua` 原文 vs 包内对应 lua——变量名应全变、
      但 `require("config.StageConfig")` 字符串与 `Get`/`GetForServer` 等对外字段名不变
- [ ] `resources\game\assets\` 里图片/音频数量正常（游戏能显示图、放音效的前提）

## 3. 实机启动 / 存档回归（与原版行为一致才算过）

- [ ] 运行 `ZhongYanZhiMen.exe`，主界面正常显示（图片/字体不缺）
- [ ] 新档：过开场 → 编队 → 打 1-2 关战斗（三行战斗动画/结算正常）→ 存档
- [ ] 读档：关闭重开，进度、编队、金币、英雄等级与存档前一致
- [ ] 挂机收益：放置几分钟后领取，数值合理（离线经验不含空槽）
- [ ] 抽卡/遗匣/装备穿戴等核心 UI 各点一遍，无报错弹窗、无黑屏
- [ ] F12 打开 DevTools → Console 无红色 Lua Error（基线已知的 5 张剧情日记贴图缺失
      与 `StoryPlayer` 引用 `network.ClientDispatcher` 缺失属**既有基线问题**，
      非本轮混淆引入，可对照原版包确认同样存在即可）

## 4. L2 字节码 Q1 判定（决定字节码路线生死）

- [ ] 云端已生成探针（或本机跑）：`python electron-shell\lua_bytecode_poc.py --file scripts\shared\StageProvider.lua --out-dir .tmp\bc-poc`
- [ ] **隔离工程法**（最可靠）：新建空 Maker 工程，把 `.tmp\bc-poc\poc_entry.lua`
      内容作为其 `scripts\main.lua`，官方 Build 后运行看日志：
  - 打印 `VERDICT: VM ACCEPTS bytecode (Q1=yes), returned 42` → **L2 可行**，
    下一步可评估「L1 混淆 → 引擎侧编译字节码」接入
  - 打印 `VERDICT: VM REJECTS bytecode (Q1=no)` → **L2 作废**，保护止于 L1
    （可选评估调研文档里的 L3 静态加密作补偿）
- [ ] 把 VERDICT 结果回报会话（决定后续路线）
- [ ] ⚠️ 即使 Q1=yes 也别急着接发行：本地 lupa 编的字节码是标准 Lua 5.4 头，
      引擎 WASM Lua 小版本若不同会拒载；正式化必须用**引擎自身**的 dump 能力
      （需另行验证 `string.dump` 在引擎 VM 内是否可用）

## 5. 失败回报模板（贴回会话即可）

```
步骤N失败：
- 命令：<完整命令行>
- 关键日志：<最后 30 行>
- manifest 统计（若步骤2失败）：png=? ogg=? lua=?
- 系统：Windows 10/11，Python 版本，Node 版本
```

## 6. 验证完成后的决策点（回报后由用户选择）

| Q1 结果 | 建议路线 |
|---------|---------|
| ACCEPTS | L1 混淆 + 评估引擎侧字节码（L2）→ 三层保护 |
| REJECTS | L1 混淆为最终形态；如需更强，评估 L3 静态加密（调研文档 §L3） |

**注意**：验证期间产生的 `.tmp\protected-workspace\`、`electron-shell\game\`、
`release\` 均已被 .gitignore 排除，不会误提交；`protect-report.json` 留在工作区内。
