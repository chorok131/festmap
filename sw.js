// 축제지도 서비스워커 — 오프라인/약신호 대비 (stale-while-revalidate)
// 구조 변경 시 이 버전을 올리면(activate에서) 옛 캐시가 자동 폐기됨 → 기존 사용자 화면 고착 방지
const CACHE = 'festmap-v2';
const CORE = [   // 앱 셸만 미리 캐시. 행사별 약도/georef는 방문 시 on-demand 캐시.
  './', './index.html', './e.html', './analytics.js',
  './events/events.json', './manifest.json',
  './icon-192.png', './icon-512.png', './apple-touch-icon.png',
  'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css',
  'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js',
];

self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(CORE).catch(() => {})));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const sameOrigin = url.origin === location.origin;
  const isLeaflet = url.host === 'unpkg.com';
  if (!sameOrigin && !isLeaflet) return; // OSM 타일 등은 네트워크 그대로

  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(req);
    const net = fetch(req).then((r) => { if (r && (r.ok || r.type === 'opaque')) cache.put(req, r.clone()); return r; }).catch(() => null);
    return cached || (await net) || new Response('offline', { status: 503 });
  })());
});
