// 终焉之门·单机版 Windows 离线壳（h5-pages-deploy skill §8）
// 内置 Node http 服务器直发 COOP/COEP 头 → 127.0.0.1 可信来源，crossOriginIsolated 立即 true。
// Electron 本地形态无需 Service Worker。
const { app, BrowserWindow } = require('electron');
const http = require('http');
const fs = require('fs');
const path = require('path');

const GAME_DIR = path.join(process.resourcesPath || __dirname, 'game');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.ogg': 'audio/ogg',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.lua': 'text/plain; charset=utf-8',
  '.xml': 'application/xml',
  '.mdl': 'application/octet-stream',
  '.ani': 'application/octet-stream',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.mp4': 'video/mp4',
};

function sendJson(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
}

const server = http.createServer((req, res) => {
  let urlPath = decodeURIComponent(req.url.split('?')[0]);
  if (urlPath === '/') urlPath = '/index.html';

  // 防路径穿越：解析后必须仍在 GAME_DIR 内
  const filePath = path.normalize(path.join(GAME_DIR, urlPath));
  if (filePath !== GAME_DIR && !filePath.startsWith(GAME_DIR + path.sep)) {
    return sendJson(res, 403, { error: 'forbidden' });
  }

  fs.stat(filePath, (err, st) => {
    if (err || !st.isFile()) return sendJson(res, 404, { error: 'not found' });
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Content-Length': st.size,
      // 跨域隔离头：引擎 SharedArrayBuffer 依赖
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
      'Access-Control-Allow-Origin': '*',
    });
    fs.createReadStream(filePath).pipe(res);
  });
});

server.listen(0, '127.0.0.1', async () => {
  const port = server.address().port;
  const url = `http://127.0.0.1:${port}/`;
  console.log('[shell] serving', GAME_DIR, 'at', url);

  await app.whenReady();
  const win = new BrowserWindow({
    width: 1280,
    height: 720,
    minWidth: 800,
    minHeight: 450,
    backgroundColor: '#000000',
    title: '终焉之门·单机版',
    icon: path.join(__dirname, 'icon.png'),
    autoHideMenuBar: true,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      // 跨域隔离在本地 http 服务器下自动成立，无需 SW
    },
  });
  win.setMenuBarVisibility(false);
  win.loadURL(url);
  win.on('closed', () => {
    server.close();
    app.quit();
  });
});
