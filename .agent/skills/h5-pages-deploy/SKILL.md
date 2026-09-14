---
name: h5-pages-deploy
description: >
  UrhoX H5 构建产物（dist）本地运行与 GitHub Pages 公开页部署指南。
  覆盖：本地静态服务（serve.json/Python）与 SharedArrayBuffer 所需的 COOP/COEP 响应头、
  Windows clone 的 CRLF 坑与 .gitattributes 修复、GitHub Pages 不发隔离头时用
  最小 Service Worker（sw-coop.js）注入跨域隔离、去 Maker 预览调试桥与 TapTap 水印、
  WebSocket shim 强制免登录离线运行、Playwright 端到端验证检查点、Electron Windows 离线版。
  Use when users need to (1) 本地运行/部署 UrhoX dist 产物, (2) 部署 H5 到 GitHub Pages
  或其他静态托管（Cloudflare Pages）, (3) 去掉 dist 里的调试按钮/水印, (4) 遇到
  SharedArrayBuffer is not available 或 size mismatch 报错, (5) 自部署形态下跳过
  TapTap 登录, (6) 用 Playwright 验证 H5 产物可玩, (7) 打包 Windows 双击即玩 exe。
---

# UrhoX H5 产物本地运行与 GitHub Pages 公开页部署

适用对象：UrhoX/Maker 项目构建出的 dist 目录（Bootstrap Loader + 哈希资源 + 清单）。
产物自包含：页面资源全部在包内；引擎运行时（JS/WASM，约 70MB）按 index.html 内置地址
从官方 CDN 加载，因此部署机需要能访问外网。

## 一、产物认知（先搞清楚在部署什么）

- dist/index.html：引导器，负责拉版本映射（1.x.x.json）、引擎清单（1.0.0/）与全部哈希资源
- dist/1.0.0/manifest-*.json：资源清单（fs_path → 哈希文件），游戏 Lua 脚本以源码形态随包分发
- dist/assets/：全部哈希资源（图片/音频/脚本/配置）
- dist/env.json、latest.json：安全可保留；mac-token.json、user_info.json 是运行时凭证，对外发布必须剔除
- 游戏逻辑仍由引擎 WASM 里的 Lua VM 执行——"打包成 H5"指运行形态，不是换语言

自包含验证方法：把 dist 复制到全新目录（旁边没有 scripts/assets 源码树），若能完整跑通，即为自包含。

## 二、本地运行（必带 COOP/COEP 响应头）

引擎要求 SharedArrayBuffer → 页面必须跨域隔离 → 服务器必须发这两个响应头，
且必须通过 localhost 或 HTTPS 访问（HTTP 非本机来源时浏览器会忽略隔离头）。

### 方式 A：npx serve + serve.json

在产物根目录放 serve.json（注意：headers 必须是数组，对象格式会报 must be array）：

```json
{
  "headers": [
    {
      "source": "**",
      "headers": [
        { "key": "Cross-Origin-Opener-Policy", "value": "same-origin" },
        { "key": "Cross-Origin-Embedder-Policy", "value": "credentialless" }
      ]
    }
  ]
}
```

```bash
npx serve -l 8080 .
```

### 方式 B：Python（Windows 上命令是 python）

根目录放 serve_coop.py：

```python
import http.server, functools

class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "credentialless")
        super().end_headers()

http.server.test(HandlerClass=functools.partial(H, directory="."), port=8080)
```

浏览器打开 http://localhost:8080 。首次加载约 70MB 引擎运行时（走官方 CDN，需联网）。

### Windows clone 的 CRLF 大坑

Windows git 默认 autocrlf=true，checkout 会把文本资源（json/lua/xml）的 LF 转成 CRLF，
每个换行多 1 字节 → 引擎 DownloadManager 逐文件报
size mismatch (expected X, got X+n) → 48 个文件拒收 → failed to resolve entry: main.lua。

修复：仓库根放 .gitattributes（内容一行 `* -text`）并提交；已损坏的本地目录必须
删除后重新 clone。用 zip 下载（codeload）则天然无此问题。

## 三、去掉预览调试桥与水印（自部署形态）

| 元素 | 来源 | 删除方式 |
|---|---|---|
| 左侧悬浮球、右下角 eruda 齿轮 | script 引用 /__preview-bridge.js | 整行删除 |
| 右下角 TapTap 水印 | img#watermark-logo | 整行删除 |
| 加载屏大 Logo | img#loading-logo | 可选删除 |
| 悬浮球（fab-main）与 eruda 齿轮 | CDN 引导器注入（独立运行模式） | CSS 隐藏 + 3.1 MutationObserver 移除 eruda 节点 |

删除调试桥不影响游戏本体、存档与广告解锁流程（FakeAd 兜底仍在）。

### 3.1 eruda 节点移除（CSS 特异度压不住时）

```css
.fab-main, .fab-icon { display: none !important; }
#eruda, .eruda-entry-btn, .eruda-icon-tool { display: none !important; }
```

eruda 自带 `#eruda .eruda-entry-btn` ID 前缀选择器，CSS 可能压不住。确定解：head 内加
MutationObserver，eruda 节点一挂载就 remove（observer 须早于引导器注册）。
fab-main 用 CSS 隐藏即可（删了可能被引导器重建）。

## 四、GitHub Pages 公开页（核心难点：Pages 不发隔离头）

GitHub Pages 无法配置 COOP/COEP → 直接开 Pages 会报 SharedArrayBuffer is not available。
解法：最小 Service Worker 只给顶层导航响应注入隔离头，其余请求全部直通
（不要用 coi-serviceworker 全量重构响应——会卡死引擎的并发资源下载）。

### 4.1 sw-coop.js（放产物根目录）

```js
var BASE = self.location.pathname.replace(/sw-coop\.js$/, '');
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });
self.addEventListener('fetch', function (e) {
  var url = new URL(e.request.url);
  if (url.origin !== self.location.origin) return;
  var isNav = e.request.mode === 'navigate';
  var isRoot = url.pathname === BASE || url.pathname === BASE + 'index.html';
  if (isNav && isRoot) {
    e.respondWith(fetch(e.request).then(function (r) {
      var h = new Headers(r.headers);
      h.set('Cross-Origin-Opener-Policy', 'same-origin');
      h.set('Cross-Origin-Embedder-Policy', 'require-corp');
      return new Response(r.body, { status: r.status, statusText: r.statusText, headers: h });
    }));
  }
});
```

### 4.2 index.html 改造清单（按顺序）

1. head 尽早注册 SW 并等待激活后再 reload（必须等 serviceWorker.ready，直接 reload
   会与 SW 激活竞态）：

```html
<script src="sw-coop.js"></script>
<script>
(function () {
  var flag = 'coopReloaded';
  if (window.crossOriginIsolated) { sessionStorage.removeItem(flag); return; }
  if (sessionStorage.getItem(flag)) { return; }
  sessionStorage.setItem(flag, '1');
  navigator.serviceWorker.register('sw-coop.js');
  navigator.serviceWorker.ready.then(function () { location.reload(); });
})();
</script>
```

2. COEP require-corp 下，跨域子资源必须 CORS：给 CDN 的 script/img 加
   crossorigin="anonymous"（官方 CDN 返回 access-control-allow-origin: *，实测可用）。

3. 删除调试桥与水印（见第三节）。

### 4.3 免登录强制离线（可选）

HTTPS 部署时引擎会连登录服务器（wss://entrance-new-pd.spark.xd.com），无容器登录态时
弹 TapTap 扫码登录卡住引导。注入 WebSocket shim 让登录必然失败 → 引擎走 skipping
login 离线路径：

```html
<script>
(function () {
  var OrigWS = window.WebSocket;
  function PatchedWS(url, protocols) {
    if (String(url).indexOf('entrance-new-pd.spark.xd.com') !== -1) {
      url = 'ws://127.0.0.1:1/'; // 必然连接失败
    }
    return protocols === undefined ? new OrigWS(url) : new OrigWS(url, protocols);
  }
  PatchedWS.prototype = OrigWS.prototype;
  window.WebSocket = PatchedWS;
})();
</script>
```

前提：引擎的 WebSocket 在主线程页面上下文创建（实测如此）。代价：在线功能全部离线化，
广告走 FakeAd 预览。

## 五、发布步骤

1. GitHub API 建公开仓库（或用户自建），默认分支 main
2. 推送改造后的产物（整目录 + sw-coop.js + serve.json + README；剔除凭证文件）
3. 开启 Pages：POST /repos/{owner}/{repo}/pages，body {"source":{"branch":"main","path":"/"}}
4. 轮询构建：GET .../pages/builds/latest 直到 status: built（首次 1-3 分钟）
5. 访问 https://<owner小写>.github.io/<repo>/

## 六、Playwright 端到端验证检查点

控制台日志按序出现即成功：

```
[UrhoX] ✓ Env: production
WebSocket connection to 'ws://127.0.0.1:1/' failed   ← shim 生效
WARNING: ConnectError in WASM [1: connected failed.], skipping login
[Script] [Main] Phase -> title
```

页面 JS 断言：window.crossOriginIsolated === true。
资源渐进加载（DWP title=2 rest=24），停滞但无失败日志属正常后台下载。
无服务器验证：Playwright ctx.route 回填本地 dist 文件并注入 COOP/COEP 响应头；
Chromium 参数 --no-sandbox --enable-unsafe-swiftshader --use-angle=swiftshader。

## 七、常见故障速查

| 症状 | 原因 | 处理 |
|---|---|---|
| SharedArrayBuffer is not available | 页面未隔离 | 服务器没发 COOP/COEP，或非 localhost/HTTPS |
| size mismatch (expected X, got X+n) | Windows clone CRLF | .gitattributes + 删除重 clone |
| TapTap 扫码登录弹窗 | HTTPS 下登录服务可达 | 注入 4.3 WS shim |
| 加载屏停滞 | SW 全量重构响应破坏并发下载 | 用 4.1 最小 SW |
| SW 注入不生效 | BASE 路径推导错误 | pathname.replace(/sw-coop\.js$/, '') |
| 首次加载隔离失败 | reload 与 SW 激活竞态 | 等 serviceWorker.ready 再 reload |
| Pages 改动不生效 | Fastly 边缘缓存 max-age=600 | URL 加随机参数，最长等 10 分钟 |
| must be array（serve 报错） | serve.json headers 写成对象 | 改数组格式 |
| 引擎 404（wasm/js） | CDN 路径带版本/哈希被硬编码 | 保持 index.html 原生引用 |
| 悬浮球/eruda 仍在 | 引导器注入 + ID 前缀特异度 | CSS 隐藏 + MutationObserver 移除 |

## 八、Windows 离线版制作要点（Electron 打包 exe，免登录离线可玩）

定位：脱离 TapTap 生态、双击即玩的 Windows 版。广告为 FakeAd 预览；TapTap PC 官方版
（app_platforms 含 2）才是原生+真实广告的路径。

### 8.1 工程结构（electron-shell/）

```
package.json   main=main.js, build.extraResources=[{from:game,to:game}]
main.js        内置 http 服务器（随机端口，直接发 COOP/COEP 头）→ BrowserWindow 加载
game/          dist 打包产物（已打补丁：去桥/水印/免登录 shim）
icon.png       512x512 图标
```

要点：COI 头由内置 Node 服务器直接发（127.0.0.1 是可信来源，crossOriginIsolated 立即
true），Electron 里不需要 Service Worker；防路径穿越：resolve 后 indexOf 校验。

### 8.2 构建

```bash
npm install
npm run dist    # electron-builder --win nsis portable --x64
```

Linux（无 wine/sudo）替代：`--dir` 目标产 win-unpacked/ 直接 zip；package.json 加
`build.win.signAndEditExecutable: false` 免 rcedit/wine。

### 8.3 沙箱/代理下载 Electron 的坑

`ELECTRON_GET_USE_PROXY=true` + `GLOBAL_AGENT_HTTP(S)_PROXY`；ELECTRON_CACHE /
ELECTRON_BUILDER_CACHE 指到可写目录。发布走 GitHub Release（单资产上限 2GB）。

## 九、已知限制

- Safari 对 credentialless 支持有限；require-corp 方案 Safari 15.2+ 可用
- 普通宿主下广告走引擎 FakeAd 预览，真实变现需 TapTap 容器
- GitHub Pages 单文件上限 100MB、站点建议 <1GB；超出改用 Cloudflare Pages（_headers 原生支持隔离头）
- SW 首次注册触发一次自动刷新（coi 标准行为）
- Pages/Fastly 对 HTML max-age=600：推完新构建最长 10 分钟全量生效
