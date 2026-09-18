// 终焉之门·单机版 Windows 离线版（Electron，h5-pages-deploy skill §8）
// 内置 http 服务器：随机端口 + COOP/COEP 头（127.0.0.1 是可信来源，
// crossOriginIsolated 立即为 true，无需 Service Worker）。
// 免登录（WebSocket shim），广告为 FakeAd 预览。
const { app, BrowserWindow } = require('electron');
const http = require('http');
const fs = require('fs');
const path = require('path');

// 打包后 main.js 在 app.asar 内，game/ 在 resources/game（extraResources）
const ROOT = app.isPackaged
  ? path.join(process.resourcesPath, 'game')
  : path.join(__dirname, 'game');

// 诊断日志：写入 userData/electron-main.log（黑屏时取此文件排查）
function logLine(msg) {
  try {
    const dir = app.getPath('userData');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(path.join(dir, 'electron-main.log'),
      new Date().toISOString() + ' ' + msg + '\n');
  } catch (e) { /* 日志失败不影响运行 */ }
  console.log(msg);
}
const PORT_MIN = 30000;
const PORT_SPAN = 20000;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.ogg': 'audio/ogg',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.mp4': 'video/mp4',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.wasm': 'application/wasm',
  '.atlas': 'text/plain; charset=utf-8',
  '.xml': 'application/xml',
  '.lua': 'text/plain; charset=utf-8',
  '.mdl': 'application/octet-stream',
  '.ani': 'application/octet-stream'
};

// 防路径穿越：resolve 后必须仍在 ROOT 内
function safeResolve(urlPath) {
  const decoded = decodeURIComponent(urlPath);
  const resolved = path.resolve(ROOT, '.' + decoded);
  if (resolved === ROOT || resolved.startsWith(ROOT + path.sep)) {
    return resolved;
  }
  return null;
}

function sendFile(req, res, filePath) {
  let stat;
  try {
    stat = fs.statSync(filePath);
  } catch (e) {
    res.writeHead(404);
    res.end('not found');
    return;
  }
  const ext = path.extname(filePath).toLowerCase();
  const headers = {
    'Content-Type': MIME[ext] || 'application/octet-stream',
    'Accept-Ranges': 'bytes',
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'credentialless'
  };
  const range = req.headers.range;
  if (range) {
    const m = /bytes=(\d*)-(\d*)/.exec(range);
    let start = m && m[1] ? parseInt(m[1], 10) : 0;
    let end = m && m[2] ? parseInt(m[2], 10) : stat.size - 1;
    if (start > end || start >= stat.size) {
      res.writeHead(416, { 'Content-Range': 'bytes */' + stat.size });
      res.end();
      return;
    }
    if (end >= stat.size) end = stat.size - 1;
    headers['Content-Range'] = 'bytes ' + start + '-' + end + '/' + stat.size;
    headers['Content-Length'] = end - start + 1;
    res.writeHead(206, headers);
    fs.createReadStream(filePath, { start: start, end: end }).pipe(res);
  } else {
    headers['Content-Length'] = stat.size;
    res.writeHead(200, headers);
    fs.createReadStream(filePath).pipe(res);
  }
}

function startServer(port) {
  return new Promise(function (resolve) {
    const server = http.createServer(function (req, res) {
      try {
        let urlPath = (req.url || '/').split('?')[0];
        if (urlPath === '/') urlPath = '/index.html';
        const filePath = safeResolve(urlPath);
        if (filePath === null) {
          logLine('[server] 403 forbidden: ' + urlPath);
          res.writeHead(403);
          res.end('forbidden');
          return;
        }
        if (fs.existsSync(filePath) === false) {
          logLine('[server] 404 missing: ' + urlPath);
        }
        sendFile(req, res, filePath);
      } catch (e) {
        res.writeHead(400);
        res.end('bad request');
      }
    });
    server.listen(port, '127.0.0.1', function () {
      resolve(server);
    });
  });
}

async function createWindow() {
  const port = PORT_MIN + Math.floor(Math.random() * PORT_SPAN);
  await startServer(port);
  const targetUrl = 'http://127.0.0.1:' + port + '/index.html';
  logLine('[main] server up on port ' + port + ', loading ' + targetUrl);
  const win = new BrowserWindow({
    width: 1590,
    height: 987,
    useContentSize: true,
    resizable: false,      // 锁定窗口尺寸：任何分辨率/屏幕下 UI 元素大小恒定
    maximizable: false,
    fullscreenable: false,
    title: '终焉之门·单机版',
    icon: path.join(__dirname, 'icon.png'),
    backgroundColor: '#000000',
    autoHideMenuBar: true,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  win.setMenuBarVisibility(false);
  win.removeMenu();

  // ---- 黑屏诊断与自愈 ----
  // 页面控制台转发到终端与日志文件（黑屏时可看 exe 控制台或 electron-main.log）
  win.webContents.on('console-message', function (_e, _level, message) {
    logLine('[web] ' + message);
  });
  // 主框架加载失败（服务器/端口异常）：2s 后自动重试
  win.webContents.on('did-fail-load', function (_e, code, desc, url, isMain) {
    if (!isMain) return;
    logLine('[main] did-fail-load code=' + code + ' desc=' + desc + ' url=' + url);
    setTimeout(function () {
      win.loadURL(targetUrl).catch(function () {});
    }, 2000);
  });
  // 渲染进程崩溃：重建页面
  win.webContents.on('render-process-gone', function (_e, details) {
    logLine('[main] render-process-gone: ' + details.reason);
    win.webContents.reload();
  });
  // F12 切换 DevTools（用户自助诊断）
  win.webContents.on('before-input-event', function (_e, input) {
    if (input.type === 'keyDown' && input.key === 'F12') {
      win.webContents.toggleDevTools();
    }
  });

  await win.loadURL(targetUrl);
  logLine('[main] loadURL resolved (page DOM ready may follow)');
}

app.whenReady().then(createWindow);
app.on('window-all-closed', function () {
  app.quit();
});
