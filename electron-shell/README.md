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

## 一键脚本（推荐，本机跑）

云端代理传 ~466MB zip 会被超时掐断，**打包和上传请在本机直连 GitHub**。

Windows 双击：

| 文件 | 做什么 |
|------|--------|
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
首次启动仍需联网拉引擎 WASM（约 70MB，官方 CDN）。

## 运行行为（main.js 定稿）

- 窗口锁定 **1590×987**（resizable/maximizable/fullscreenable 均关）：任何屏幕下 UI 元素大小恒定
- 内置 http 监听 `127.0.0.1:30000-49999` 随机端口，支持 Range 请求（视频拖动进度条）
- 黑屏自愈：加载失败 2s 自动重试；渲染进程崩溃自动 reload
- 诊断日志：`%APPDATA%/zhongyan-zhimen-win64-offline/electron-main.log`（黑屏排查取此文件）
- **F12** 切换 DevTools（用户自助诊断）
