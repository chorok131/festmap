// 축제지도 서비스워커 — 오프라인/약신호 대비 (stale-while-revalidate)
// 핵심: GPS는 위성이라 인터넷 불필요 → 약도·코드만 캐시돼 있으면 행사장 통신 마비에도 전부 동작.
// 구조 변경 시 이 버전을 올리면(activate에서) 옛 캐시가 자동 폐기됨 → 기존 사용자 화면 고착 방지
const CACHE = 'festmap-v19';
const CORE = [   // 앱 셸 (Leaflet은 자체 호스팅 → 외부 CDN 의존 없음)
  './', './index.html', './e.html', './apply.html', './apply-good.png', './apply-bad.png',
  './analytics.js', './firebase-config.js',
  './events/events.json', './manifest.json',
  './vendor/leaflet.css', './vendor/leaflet.js',
  './icon-192.png', './icon-512.png', './apple-touch-icon.png',
];

// 설치 시: 앱 셸 + "모든 행사의 약도·좌표"까지 미리 캐시
// → 집/와이파이에서 한 번만 열어보면, 행사장에서 인터넷 없이도 지도가 뜬다.
self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    await c.addAll(CORE).catch(() => {});
    try {
      const { events } = await (await fetch('./events/events.json')).json();
      for (const ev of (events || [])) {
        try {
          const base = `./events/${ev.slug}/`;
          const g = await (await fetch(base + 'georef.json')).json();
          await c.addAll([base + 'georef.json', base + g.image]).catch(() => {});
          await c.add(base + 'pois.json').catch(() => {});  // 핀 데이터(있으면)
          if (ev.short) await c.add('./' + ev.short + '/').catch(() => {});  // QR 짧은 경로

        } catch (err) {}
      }
    } catch (err) {}
  })());
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
  if (url.origin !== location.origin) return; // 외부 요청은 그대로

  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(req, { ignoreSearch: url.pathname.endsWith('.html') });
    const net = fetch(req).then((r) => { if (r && r.ok) cache.put(req, r.clone()); return r; }).catch(() => null);
    return cached || (await net) || new Response('offline', { status: 503 });
  })());
});
