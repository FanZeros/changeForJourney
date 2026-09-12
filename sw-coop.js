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
