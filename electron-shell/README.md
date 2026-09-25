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
