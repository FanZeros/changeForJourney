# 终焉之门 · Windows 离线版（Electron）

依据 `h5-pages-deploy` skill §8：内置 Node http 直发 COOP/COEP，127.0.0.1 可信来源，无需 Service Worker。免登录（WebSocket shim），广告为 FakeAd 预览。

## 工程

```
electron-shell/
  package.json
  main.js          内置 http + BrowserWindow
  icon.png         512x512
  game/            打过补丁的 dist（不入库）
  release/         构筑产物（不入库）
```

`game/` 相对官方 `dist/` 的补丁：

- 删除 `__preview-bridge.js` / `mac-token.json` / `user_info.json`
- 去掉水印、调试桥
- CSS 隐藏 fab + MutationObserver 移除 eruda
- WebSocket shim：登录服改连 `ws://127.0.0.1:1/` → skipping login

## PC 发行包代码保护现状（2026-09-24 审核）

- 现有流程是 Maker Build → `dist/` → `pack_release.py:sync_dist()` 原样复制到 `electron-shell/game/` → `electron-builder` 将 `game/` 放入 `extraResources`。目前**没有 Lua 混淆/加密步骤**；`app.asar` 只封装 Electron 壳的 `main.js`，不保护 `extraResources/game/assets`。
- 实测 `dist/1.0.7` 的 `main.lua`、`boot/Standalone.lua` 对应资源文件头是 Lua 源码，不是 Lua 字节码。UUID 文件名和 zip 压缩并不能阻止玩家恢复源码；Release `dist-snapshot` 上传的是同一份未混淆 `dist/`。
- **可以评估混淆，但不要直接对 `dist/assets/*.lua` 做文本替换**：manifest 记录文件 hash/size，可能还有变体与引用关系；直接替换会破坏资源加载/校验。更安全的试验路线是在 Maker Build 前，对独立发布用副本的 Lua 做**保守混淆**，保留资源文件名、模块名、`require` 字符串和对外 API，运行 LSP、官方 Build 与启动/存档回归后再接入打包脚本。Lua 5.4 字节码仅在确认当前运行时和构建器均支持加载、且与目标平台版本一致时才考虑；它也不等于不可逆加密。
- 如需求是**真正保密**，客户端运行的逻辑无法可靠隐藏，应把敏感规则/密钥移到可信服务端；本游戏当前是离线单机，不能把联网服务当成透明替换。未验证前不要对已有公开 Release/快照或正式 TapTap PC 版本执行替换上传。

## 构建前隔离混淆试验（2026-09-24）

`electron-shell/obfuscation_trial.py` 只允许处理 `scripts/shared/StageProvider.lua`，且要求内容完全符合本次审查过的模块。它只输出到**另一个目录**，绝不修改仓库源码或 `dist/`；变化仅为去注释/压缩排版和局部变量改名，`require` 模块名、文件名和外部方法名不变。这是流程可行性验证，**不是整个游戏已受保护**，其他 361 个 Lua 文件仍为可读源码。

```bash
python3 electron-shell/obfuscation_trial.py --source-root . --output-root ../pc-obfuscation-trial
# 在独立的测试工程副本中用生成的 scripts/shared/StageProvider.lua 替换同名文件，
# 然后用官方 build 构建该副本；不要修改 dist/assets/*.lua 或覆盖正式发布目录。
```

实测在隔离预览副本执行官方 Build 成功，`manifest-origin.json` 指向的该模块资源与输出逐字节相同；通过 UrhoXRuntime 对照运行 10 帧测试，原版和试验版均 `PASS`、0 Lua Error，四个导出方法返回值一致。`scripts/shared/StageProvider.lua` 原件 SHA256 为 `c503923c45d0dd87bcbe012d62984656d7d4908c1b1ed548d58b38d6887a13f2`，试验输出 SHA256 为 `7176b2c2092e0aec14dedde90d9682c5d6a67f9346c2ee94e7e25c5353653434`；预览已恢复到原版并重新 Build。

**尚未通过整游戏启动/存档验收，禁止把此试验接入正式打包或上传 Release。** 未混淆的原版入口跑 60 帧已经报 `[systems/StoryPlayer]:7 Module not found: network.ClientDispatcher`；试验版出现相同错误，属于基线故障而非本试验引入。既有 `tests/lootbox_page_test.lua:173` 的存档断言和 `tests/lootbox_horizon_test.lua:49` 的旧模块路径也在当前分支基线上失败。需要先让基线测试恢复可用，再试更多模块与 Windows 离线包回归。

## 全量隔离压缩试点（2026-09-27，尚未接入发行）

`obfuscation_trial.py --all-scripts` 在工程之外的新目录生成全部 361 个 Lua 文件的**注释清理/缩排压缩副本**，保留文件名、所有代码、字符串、长字符串及供官方 LSP 使用的 EmmyLua 注释。输出目录必须不存在、且不能与源码树互相包含；仓库源码、`dist/` 和 `electron-shell/game/` 不会被修改。该模式**不会重命名全量变量、编译字节码、加密或保护资源**；原有不带 `--all-scripts` 的单模块试点保持不变。请勿把试点直接当成正式 PC 包保护方案。

```bash
python3 electron-shell/obfuscation_trial.py --all-scripts --source-root . --output-root ../pc-all-lua-trial
# 用独立项目副本补齐 assets/ 和 .project/，再对其 scripts/ 运行官方 Build 与运行时回归。
```

本次隔离副本从 6,008,895 字节变为 4,653,072 字节（减少约 22.6%，361/361 文件内容变化），原版和压缩版 60 帧 Runtime 验证均为 PASS、0 Lua/资源错误。当前副本放在 `.tmp` 下，官方 Build 的 LSP 检查报大量缺少引擎声明的 `undefined-global`，不能宣称它已通过正式 Build；待在正常可识别引擎类型定义的独立工程内完成完整 LSP、Build、存档及 Windows 成品包回归。所有处理后 Lua 仍是可读明文，当前发布流水线依然完全没有调用此脚本。

## L1 作用域安全混淆器 + L2 字节码 POC（2026-09-27，`feat927/ele-protection-research-0927`）

调研结论见 `docs/pc-protection-research-0927.md`。本节是把其中 **L1（AST 重命名）**
落地为可用脚本，并为 **L2（Lua 5.4 字节码）** 准备可行性探针。**均未接入正式打包流水线**，
`pack_release.py` / `build_local_windows.bat` 完全没调用它们。

### L1：`lua_obfuscator.py`（作用域安全重命名）

基于 luaparser 内置 ANTLR 语法树做标准 Lua 作用域解析，**只重命名局部绑定**
（文件级 local、函数参数、for 循环变量、local function、嵌套匿名函数的 local），
用 token 级 splice 改写，其余（注释、字符串、数字、空白、排版）**从原文逐字节拷贝**。

- **永不改名**：全局名（引擎 API、`require` 到的模块、未声明标识符）、
  所有字段名与方法名（`.` / `:` 之后、表构造器 key、`function a.b.c:d()` 中
  `.`/`:` 之后的部分）、`require` 路径字符串、goto label。
- **保留** EmmyLua `---` 注释（官方 LSP 依赖），但注释里的 `---@param 旧名`
  **不会跟着实参一起改**（见下方已知限制）。
- **安全策略**：任何解析失败、含未知语法形态、或未通过等价校验的文件，
  一律拒绝改写并原样复制——宁可漏混淆也不冒运行期破坏的风险。

```bash
# 依赖：python3 -m venv ~/luaenv && ~/luaenv/bin/pip install luaparser lupa
# 单文件诊断（打印混淆结果）：
python3 electron-shell/lua_obfuscator.py --file scripts/shared/StageProvider.lua
# 全量（输出必须在源码树之外）：
python3 electron-shell/lua_obfuscator.py --source-root . --output-root ../obf-out
```

**等价校验（内置，逐文件强制）**：混淆后必须①重新解析成功；②非 NAME token 序列
逐一致（保证只动标识符文本）；③字符串字面量完全一致；④NAME token 数量一致；
⑤全局名集合不变。任一不满足即 `rejected` 原样复制。

**本轮实测**（本分支源码）：
- 单元/行为等价测试 `test_lua_obfuscator.py`：21/21 PASS（覆盖递归、upvalue 闭包、
  shadowing、`self` 方法、数值/泛型 for、goto label、repeat-until、`<const>`、
  多重赋值、varargs、do-block、字段 vs 局部同名等）。
- 全量 361 文件：**344 改名 / 17 未变**（16 个纯数据表 StageConfig/AssetManifest
  无 local 绑定；`scripts/core/DarkIcon.lua` 因 luaparser 对某中文 token 解析失败
  被安全拒绝、原样复制）。体积 6,008,895 → 5,843,096 字节（-2.76%，因保留注释
  与排版，本就不是压缩目标）。
- 行为等价抽样 `verify_obfuscation_sample.py`（lupa Lua 5.4 真跑 + 确定性深度序列化
  比对返回值）：**71/71 PASS，0 mismatch**，290 个依赖引擎全局的文件离线跳过。

```bash
python3 electron-shell/test_lua_obfuscator.py          # 单元/行为等价
python3 electron-shell/verify_obfuscation_sample.py ../obf-out .   # 全量抽样行为等价
```

**已修复：`---@param` 注释同步改名（2026-09-27）**：混淆器现在会解析紧邻函数声明
上方的 doc 注释块，把其中的 `@param <旧名>` 同步为该形参的新名（仅当旧名确是
该函数形参；注释块与函数之间夹任何代码则判定「非本函数 doc」而不关联，绝不跨代码
误伤；字符串里的 `---@param` 因属 `NORMALSTRING` token 而非注释 token，天然不动）。
`@param` 后的**类型名与描述文字保留不变**（那不是参数名）。匿名函数
（`local g = function(x)`）的 doc 注释锚点有歧义故跳过——实测本项目 1373 个
`@param` doc 块**全部**紧邻命名函数/`local function`，无一匿名，跳过是安全的。

**本轮实测（doc 同步后）**：
- 全量 361 文件重新混淆后，`@param` 残留不匹配 **219 文件 → 0**（残留校验脚本逐函数
  核对注释 `@param` 名是否都在实参表内）。
- 行为等价抽样 **71/71 PASS，0 mismatch**（同步注释未破坏任何代码）。
- **官方 Build 成功（0 Error）**：把混淆产物 + 268 个引擎 `.emmylua` 类型定义放入
  隔离工程跑官方 MCP Build，构建通过，且 `dist/assets/*.lua` 产物确认就是混淆后
  代码（嵌套闭包 `_z0_/_z1_/_z11_` 等正确改名）。这直接推翻了「去注释试点在 .tmp
  Build 报大量 undefined-global」的旧结论——**根因是缺引擎类型定义，不是混淆本身**。
  ⚠️ LSP `textDocument/diagnostic` 的 workspace 汇总接口对**磁盘替换**返回陈旧缓存
  （实测注入语法错误都不报），只有 `didOpen`（编辑器缓冲）或官方 Build 进程才读最新
  内容；本结论以官方 Build + dist 产物为准，不以那个汇总接口为准。

**剩余已知限制**：
1. **`DarkIcon.lua` 被跳过**（luaparser 对某中文 token 解析失败），仍是明文；
   需换 parser 或手工处理该文件（361 中仅此 1 个）。
2. **仍是可读明文源码**：L1 只去掉变量名语义，控制流与字符串依旧可读。要显著提高
   阅读难度必须叠加 L2（字节码）——但 L2 有前置未知，见下。

### L2：`lua_bytecode_poc.py`（字节码可行性探针）

把 Lua 源码 `string.dump` 成 Lua 5.4 字节码。**本地已验证**标准 Lua 5.4 可往返
（header `1b 4c 75 61 54 00` = `\x1bLua` + 版本 0x54），体积 -22.8%。

```bash
python3 electron-shell/lua_bytecode_poc.py --file scripts/shared/StageProvider.lua --out-dir .tmp/bc-poc
```

生成 `.luac` 字节码 + `poc_loader.lua` 自包含探针（把 `return 42` 编译成字节码，
与业务模块解耦）。本地 lupa Lua 5.4 跑探针输出
`VERDICT: VM ACCEPTS bytecode (Q1=yes), returned 42`。

**两个前置未知必须在真实引擎上验证（沙箱无 WASM 引擎资产，跑不了）**：
- **Q1**：UrhoX 的 **WASM Lua VM 是否接受字节码 chunk**？
  把 `poc_loader.lua` 贴进官方 Runtime / 预览 Console 运行：
  打印 `VM ACCEPTS (Q1=yes)` → L2 可行；`VM REJECTS (Q1=no)` → **L2 作废，退回纯 L1**。
- **Q2**：`dist/assets/*.lua` 的 manifest hash/size 是否被引擎**运行时强校验**？
  若是，字节码化必须发生在官方 Build **之前**（对源码副本混淆+编译 → 用副本走 Build，
  manifest 天然一致），不能事后替换 `dist`（会破坏校验，README 早有结论）。
- **版本锁死风险**：字节码与 Lua 版本/字长/endianness 绑定；本地 5.4 编的字节码
  未必匹配引擎 WASM Lua 版本。引擎升级即可能失效，需在 CI/打包机用引擎自带 `luac`
  或 VM 内 `string.dump` 生成，而非本地 lupa。

### 建议的下一步顺序（供决策，不代表已执行）
1. **P0**：发布版关 F12 DevTools（`main.js:172`）——当前等于官方送提取器，一行改动。
2. **Q1-POC**：在本机 Windows 用官方 Runtime 跑 `poc_loader.lua`，定 L2 生死。
3. 若 L2 可行：`源码 → L1 混淆 → luac 字节码 → 官方 Build`（解决 `---@param` 后）。
4. 若 L2 不可行：`源码 → L1 混淆（修 @param）→ 官方 Build`，可选叠加 L3 静态加密。

## --protect 受保护打包（2026-09-27，`feat927/ele-protection-research-0927`）

L1 混淆已接入打包流程（默认关闭，不影响现有一键脚本）。**四步链**：

```
protect_build.py                物化「混淆工作区」：361 个 Lua 全部 L1 混淆
                                + .meta/.py 逐字节复制 + assets/ 真实复制 + .project/ 复制
                                + .maker-mcp/ 等 Maker 绑定目录复制（官方 preview
                                prepare 要求 target-dir 已绑定 Maker，缺
                                .maker-mcp/config.json 会 FAIL）
  ↓
taptap-maker preview prepare    官方 Build 跑在混淆工作区上（LSP/烘焙/manifest 全走正式流程）
  ↓
prepare_local_dist.py           --scripts-root 指向混淆工作区：校验 dist Lua 与混淆源码
  --scripts-root <ws>/scripts   逐字节一致 + 资产闸门（manifest 必须含 png/ogg，
                                缺资源即拒包）→ 打补丁 → game/
  ↓
pack_release.py                 --protect-scripts-root 同基准复核 → electron-builder → zip
  --prepare-dist
  --protect-scripts-root <ws>/scripts
```

一键入口：

| 文件 | 平台 | 说明 |
|------|------|------|
| `build_protected_windows.bat` | Windows | 四步链一键；混淆工作区在 `.tmp/protected-workspace`（.gitignore 已排除） |
| `build_protected_windows.sh` | Linux/macOS | 同上；`PYTHON=~/luaenv/bin/python` 指定解释器 |

依赖：`pip install luaparser`（lupa 仅测试需要）。

### 本轮实测（沙箱内完成的部分）

- `protect_build.py` 小规模工作区端到端 PASS：混淆产物、`@param` 同步、
  非 Lua 逐字节复制、protect-report.json（含每文件处置与 SHA256）。
- **官方 Build（混淆 scripts + 真实 assets 复制）成功**：manifest 1226 项
  （361 lua + 770 png + 77 ogg + 6 atlas + 字体），dist lua 与混淆源码
  **361/361 逐字节一致**，344 个文件确认含混淆名。
- **关键发现：官方 Build 不烘焙符号链接的 assets/**——工作区 assets 用
  symlink 时 manifest 只剩 361 lua + 4 json（游戏必然黑屏缺图）。故
  `protect_build.py` 默认**真实复制** assets（+398MB），`--link-assets`
  降级为实验选项并打醒目警告；`prepare_local_dist.py` 新增资产闸门
  （manifest 缺 .png/.ogg 即拒包），闸门双向测试 PASS（真实 dist 通过、
  伪造 lua-only manifest 拒包）。
- `verify_prepare_dist` 加 `--protect-scripts-root` 后：无覆盖时正确拒绝
  混淆 dist（与仓库原版源码不一致），有覆盖时通过（361 文件逐字节一致）。

### 本机实跑修复记录（2026-09-28）
- `protect_build.py:109` 反斜杠感叹号 SyntaxError → 已修（b204359）。
- pip/python 解释器错位致 `No module named antlr4` → bat/sh 加 [0/4] 预检 +
  报错打印 sys.executable（dda8be7）；修复用 `python -m pip install luaparser lupa`。
- 工作区守卫方向写反，误拒 `.tmp/protected-workspace` → 已修（22257b9）。
- 步骤 2 报 `Preview requires a bound Maker project with .maker-mcp/config.json`
  → protect_build 现自动复制 `.maker-mcp/.maker/.installer/.cli/.sce`（存在即复制）；
  若仓库根本身没有 `.maker-mcp/`，先在仓库根跑一次 `maker-mcp\update-maker-mcp.bat`
  完成 Maker 绑定再重跑本链。

### 尚未验证（需本机 Windows 实机）

**逐步骤验证清单见 `electron-shell/WINDOWS_PROTECT_CHECKLIST.md`**（含成功标志、
包内容抽检、实机回归项、L2 Q1 判定与失败回报模板）。

1. **成品包回归**：`build_protected_windows.bat` 全链 + Electron zip +
   实机启动/存档/战斗 60 帧（沙箱没有 npx taptap-maker CLI 与 Electron）。
2. **junction 行为**：Windows 上 assets 真实复制耗磁盘 ~400MB；若改用
   junction 需实测官方 Build 是否跟随（Linux symlink 已证实不跟随）。
3. `prepare_local_dist.py` 的 `latest_prepare_source()` 取「最近一次 preview
   prepare 产物」——多工程并存时确认拿到的是混淆工作区那次。

## 一键脚本（推荐，本机跑）

云端代理传 ~466MB zip 会被超时掐断，**打包和上传请在本机直连 GitHub**。

Windows 双击：

| 文件 | 做什么 |
|------|--------|
| `../maker-mcp/update-maker-mcp.bat` | **本机 Maker MCP + 本地 Runtime**（官方口径，单机不用远端构建） |
| `update_runtime.bat` | Electron 离线包：拉最新 `dist-snapshot` → 打补丁 → 打 zip |
| `push_dist_snapshot.bat` | **云端 Build 后**：把 `dist/` 分片传到 `dist-snapshot`（80s 限时，反复点即可续传） |
| `build_local_windows.bat` | **本机一键**：preview prepare → 校验并补入口 → Electron 打包；不读仓库根 dist、不上传 |
| `pack_release.bat` | **仅本地**：校验当前源码与 `dist/` 中全部 Lua 一致 → 打补丁 → electron-builder → zip；不拉快照、不上传 |
| `pack_and_upload.bat` | 原有远端快照检查 + 打包 + 上传 GitHub Release `win64-v{version}`；**不是**本地专用入口 |
| `upload_only.bat` | 已有 zip 只上传（不重打） |

命令行：

本机无仓库根 dist 时，在仓库根目录双击 `electron-shell/build_local_windows.bat`，或执行：

```bat
electron-shell\build_local_windows.bat
```

它依次运行 preview prepare、prepare_local_dist.py、pack_release.py --prepare-dist。
成功标志是 `ok 1.0.7 lua 364`，最终 zip 在 `electron-shell/release/`。

```bat
cd electron-shell
python pack_release.py --local-dist
```

推荐：Maker Build 后，只用当前本地 dist，不上传。

`--local-dist` 在任何下载/复制前校验 `dist/<游戏版本>/manifest-origin.json` 中全部 Lua
与 `scripts/` 源文件逐字节一致；缺文件或内容不一致直接退出。此校验只覆盖 Lua，
图片/音频等经烘焙的资源不能据此证明是最新版本；改动非 Lua 资源后也必须重新 Build。
它不会拉 `dist-snapshot`，也不会执行清理仓库根的 `clean_dist_spill()`；
仍会按需联网下载离线引擎运行时和 Electron 依赖。
`--skip-runtime` 会省去运行时下载，但生成的包首次启动需联网。若入口脚本或资源变动，先在 Maker 中
调用 Build 重新生成仓库根目录的 `dist/index.html`，仅启动本地预览不会生成这个发布产物。
`--local-dist` 不允许搭配 `--upload`、`--skip-sync` 或 `--skip-build`。

旧版快照/上传命令（**不要用于仅本地打包**）：

```bash
cd electron-shell
python pack_release.py              # 默认会校验云端快照，可能替换本地 dist
python pack_release.py --upload     # 打包并上传
python pack_release.py --upload-only  # 已有 zip 只上传
```

上传凭据（任选）：`gh auth login` / 环境变量 `GITHUB_TOKEN` / git 已保存的 github.com 凭据。
版本号读 `package.json` 的 `version`。产物：`release/ZhongYanZhiMen-win64-offline-{version}.zip`。

前提：仓库根已有最新 `dist/`（Maker Build 过）。脚本会删预览桥/凭证、去水印、注入免登录 WS shim。

**本机没有 dist/？** 脚本会自动从 GitHub Release `dist-snapshot` 拉取最新快照
（文件名 `dist-{version}-{commit短hash}.zip`，脚本列资产自动选最新，天然避开旧缓存；
需本机 GitHub 凭据/token 仅用于上传，下载匿名）。**云端每次 build 后都要重传**，否则本机拉到旧快照。

**云端维护快照**（Build 之后跑一次）：

```bash
python electron-shell/snapshot.py                      # 压缩+分片上传+清旧，一条命令
python electron-shell/snapshot.py --max-seconds 80     # 沙箱/弱网限时分批，反复重跑即断点续传
```

- 分片 16MB/片（单连接大 POST 会被代理劣化卡死）；幂等：已传片秒跳过，可随时中断重跑
- 传完自动删除其它 commit 的旧片防混片；产物 `dist-{version}-{commit7}.zip.partNN`
- 直连 GitHub 失败加 `--proxy http://127.0.0.1:7890`（pack_release 拉取端同样支持并会自动探测常见端口）

## 构筑（手动）

本机 Windows（有 NSIS）：

```bash
cd electron-shell
npm install
npm run dist    # portable exe
```

Linux（无 wine）：

```bash
cd electron-shell
npm install
npm run dir     # 产出 release/win-unpacked/
# 再 zip win-unpacked
```

产物：`release/ZhongYanZhiMen-win64-offline-{version}.zip`（解压后运行 `ZhongYanZhiMen.exe`）。

## 自带运行时（完全离线）

`pack_release.py` 默认把**引擎运行时**（UrhoXRuntime wasm/js/data，约 83MB）从官方 CDN
镜像到 `game_engine/`（`.gitignore` 已排除，不入库），打包时并入 `game/src/engine/`，
并把 `game/1.0.2/engine-*.json` 的 `base_url` 补丁成相对路径 `src/engine/`、
web 入口 loader `index.min.js` 本地化到 `game/src/web/src/`。

- 引擎加载链（`stable.json → manifest → assets/{uuid}-{hash}{ext}`）全部落在本地 server
- **玩家首次启动零联网**（登录服已被 WebSocket shim 拦截 → skipping login）
- 镜像按 size 校验、幂等增量下载：`--runtime-only` 单独预下载；`--skip-runtime` 退回联网拉取形态

## 运行行为（main.js 定稿）

- 窗口锁定 **1590×987**（resizable/maximizable/fullscreenable 均关）：任何屏幕下 UI 元素大小恒定
- 内置 http 监听 `127.0.0.1:30000-49999` 随机端口，支持 Range 请求（视频拖动进度条）
- 黑屏自愈：加载失败 2s 自动重试；渲染进程崩溃自动 reload
- 诊断日志：`%APPDATA%/zhongyan-zhimen-win64-offline/electron-main.log`（黑屏排查取此文件）
- **F12** 切换 DevTools（用户自助诊断）
