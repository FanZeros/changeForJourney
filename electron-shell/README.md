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

## 构筑

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

产物：`release/ZhongYanZhiMen-win64-unpacked.zip`（解压后运行 `ZhongYanZhiMen.exe`）。
首次启动仍需联网拉引擎 WASM（约 70MB，官方 CDN）。
