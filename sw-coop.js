var BASE = self.location.pathname.replace(/sw-coop\.js$/, '');

// ============================================================================
// [engine-cache] 引擎静态资源本地缓存
// 背景：tapcode CDN 对引擎文件（index.min.js / UrhoXRuntime.wasm / .data /
//       engine-res / official-res）只给 cache-control: max-age=5，
//       导致每次进游戏都要重新走网络拉引擎，引导阶段明显变慢。
// 方案：SW Cache Storage 缓存优先（命中即秒出），同时后台发条件请求
//       （ETag 协商，304 廉价）跟进引擎版本更新；更新生效延迟一次访问。
// ============================================================================
var CACHE = 'engine-cache-v1';
var ENGINE_HOSTS = ['tapcode-sce.spark.xd.com'];
var ENGINE_PREFIX = '/src/';   // 覆盖 /src/engine/、/src/web/、/src/engine-res/、/src/official-res/

function isEngineAsset(url) {
  if (ENGINE_HOSTS.indexOf(url.hostname) === -1) return false;
  return url.pathname.indexOf(ENGINE_PREFIX) === 0;
}

self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) {
  e.waitUntil((async function () {
    var keys = await caches.keys();
    await Promise.all(keys.filter(function (k) { return k !== CACHE; })
      .map(function (k) { return caches.delete(k); }));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', function (e) {
  var url = new URL(e.request.url);

  // —— 同源：根导航补 COOP/COEP 头（原有行为不变）——
  if (url.origin === self.location.origin) {
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
    return;
  }

  // —— 跨域引擎静态资源：缓存优先 + 后台协商校验 ——
  if (e.request.method !== 'GET' || !isEngineAsset(url)) return;

  e.respondWith((async function () {
    var cache;
    try { cache = await caches.open(CACHE); } catch (err) { return fetch(e.request); }
    var hit = null;
    try { hit = await cache.match(e.request, { ignoreVary: true }); } catch (err) {}

    if (hit) {
      // 后台校验：cache:'no-cache' 发条件请求，304 代价极小；200 则更新缓存
      try {
        fetch(e.request, { cache: 'no-cache', credentials: 'same-origin' })
          .then(function (r) { if (r && r.ok) return cache.put(e.request, r.clone()); })
          .catch(function () { /* 离线/网络抖动：继续用缓存 */ });
      } catch (err) { /* 老内核不支持 cache 选项则跳过校验 */ }
      return hit;
    }

    var res = await fetch(e.request);
    if (res && (res.ok || res.type === 'opaque')) {
      try { await cache.put(e.request, res.clone()); } catch (err) { /* 配额不足等：忽略 */ }
    }
    return res;
  })());
});
