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

## 一键脚本（推荐，本机跑）

云端代理传 ~466MB zip 会被超时掐断，**打包和上传请在本机直连 GitHub**。

Windows 双击：

| 文件 | 做什么 |
|------|--------|
| `../maker-mcp/update-maker-mcp.bat` | **本机 Maker MCP + 本地 Runtime**（官方口径，单机不用远端构建） |
| `update_runtime.bat` | Electron 离线包：拉最新 `dist-snapshot` → 打补丁 → 打 zip |
| `push_dist_snapshot.bat` | **云端 Build 后**：把 `dist/` 分片传到 `dist-snapshot`（80s 限时，反复点即可续传） |
| `pack_release.bat` | 同步 `dist/` → 打补丁 → electron-builder → zip |
| `pack_and_upload.bat` | 上面全套 + 上传 GitHub Release `win64-v{version}` |
| `upload_only.bat` | 已有 zip 只上传（不重打） |

命令行：

```bash
cd electron-shell
python pack_release.py              # 只打包
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
