/*
 * analytics.js — 행사 사용 집계 + (옵션) 동선 수집
 *
 * 1단계(기본): 열람/위치사용 "숫자만" 집계. 좌표 저장 안 함 → 개인정보 위험 0.
 * 2단계(행사별 옵션): georef.json 에 "track":"full" 이면 동선 경로까지 수집.
 *
 * 설계 원칙
 *  - 비차단: Firebase는 지도 로드 후 lazy 로드, 실패해도 지도는 멀쩡(분석은 조용히 포기).
 *  - 배치: 세션 단위로 모아 1~2회만 전송 → Firestore 무료 한도(쓰기 2만/일) 안에서 수천 명.
 *  - 미설정 안전: firebase-config.js 가 비어 있으면 로컬 버퍼만(원격 전송 0).
 *
 * 켜는 법: firebase-config.js 에 콘솔 설정 붙여넣기 + Firestore 보안규칙 적용. (ANALYTICS_SETUP.md)
 *   규칙: sessions = 쓰기만 허용/읽기 차단, daily = 읽기 허용/increment.
 */
(function (global) {
  'use strict';

  function sid() {
    var k = 'festmap.sid';
    var v = sessionStorage.getItem(k);
    if (!v) { v = Date.now().toString(36) + Math.random().toString(36).slice(2, 8); sessionStorage.setItem(k, v); }
    return v;
  }
  function kstDate() { return new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10); }

  var cfg = global.FESTMAP_FB || null;   // 공개 설정(보안은 Firestore 규칙이 담당)
  var mode = 'counts';                   // 'counts' | 'full' | 'off'
  var db = null, ready = false, loading = false;
  var session = null, flushTimer = null, lastPing = 0;

  function localBuf(rec) {
    if (global.console && console.debug) console.debug('[festmap.track]', rec);
    try {
      var buf = JSON.parse(localStorage.getItem('festmap.buf') || '[]');
      buf.push(rec); if (buf.length > 200) buf = buf.slice(-200);
      localStorage.setItem('festmap.buf', JSON.stringify(buf));
    } catch (e) {}
  }

  function inject(src, cb) {
    var s = document.createElement('script');
    s.src = src; s.async = true; s.onload = cb; s.onerror = function () { loading = false; };
    document.head.appendChild(s);
  }
  function loadFirebase(cb) {
    if (ready) return cb();
    if (!cfg || !cfg.apiKey || mode === 'off') return;        // 미설정/끔 → 로컬만
    if (!navigator.onLine) return;                            // 오프라인 → 로컬만(나중에 전송 안 함)
    if (loading) return; loading = true;
    var b = 'https://www.gstatic.com/firebasejs/10.12.2/';
    inject(b + 'firebase-app-compat.js', function () {
      inject(b + 'firebase-firestore-compat.js', function () {
        try {
          if (!global.firebase.apps.length) global.firebase.initializeApp(cfg);
          db = global.firebase.firestore(); ready = true; loading = false; cb();
        } catch (e) { loading = false; }
      });
    });
  }

  function ensureSession(slug) {
    if (!session) session = { slug: slug, opened: false, located: false, firstTs: Date.now(), lastTs: Date.now(), path: [] };
    return session;
  }
  function scheduleFlush() {
    if (!cfg || mode === 'off' || flushTimer) return;
    flushTimer = setTimeout(function () { flushTimer = null; flush(); }, 4000);
  }
  function flush() {
    if (!session || !cfg || mode === 'off') return;
    loadFirebase(function () {
      if (!ready) return;
      var s = session, FV = global.firebase.firestore.FieldValue;
      // 1) 원천 세션 문서(읽기 차단). 좌표는 full 모드에서만.
      var doc = { slug: s.slug, opened: s.opened, located: s.located, firstTs: s.firstTs, lastTs: s.lastTs, updated: FV.serverTimestamp() };
      if (mode === 'full') doc.path = s.path;
      db.collection('events').doc(s.slug).collection('sessions').doc(sid()).set(doc, { merge: true }).catch(function () {});
      // 2) 공개 가능한 일별 집계(숫자만). 세션당 1회씩만 증가.
      var day = kstDate(), daily = db.collection('events').doc(s.slug).collection('daily').doc(day);
      var inc = {};
      if (s.opened && !sessionStorage.getItem('festmap.cnt.o.' + s.slug)) { inc.opens = FV.increment(1); sessionStorage.setItem('festmap.cnt.o.' + s.slug, '1'); }
      if (s.located && !sessionStorage.getItem('festmap.cnt.l.' + s.slug)) { inc.locates = FV.increment(1); sessionStorage.setItem('festmap.cnt.l.' + s.slug, '1'); }
      if (Object.keys(inc).length) { inc.day = day; daily.set(inc, { merge: true }).catch(function () {}); }
    });
  }

  var Festmap = {
    // e.html이 georef의 track 모드를 넘겨줌: 'counts'(기본) | 'full' | 'off'
    setConfig: function (o) { if (o && o.mode) mode = o.mode; },
    track: function (type, payload) {
      var rec = { t: type, sid: sid(), ts: Date.now() };
      for (var k in (payload || {})) rec[k] = payload[k];
      localBuf(rec);
      var slug = (payload && payload.event) || (session && session.slug);
      if (!slug) return;
      var s = ensureSession(slug); s.lastTs = Date.now();
      if (type === 'open') s.opened = true;
      if (type === 'locate_tap') s.located = true;
      scheduleFlush();
    },
    ping: function (payload, minMs) {
      var now = Date.now();
      if (now - lastPing < (minMs || 10000)) return;
      lastPing = now;
      var rec = { t: 'ping', sid: sid(), ts: now };
      for (var k in (payload || {})) rec[k] = payload[k];
      localBuf(rec);
      if (session && mode === 'full' && payload && payload.lat != null) {
        session.path.push([Math.round((now - session.firstTs) / 1000), payload.lat, payload.lng]);
        session.lastTs = now; scheduleFlush();
      }
    }
  };

  // 떠날 때 마지막 전송(배치 마무리)
  global.addEventListener('pagehide', flush);
  document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'hidden') flush(); });

  global.Festmap = Festmap;
})(window);
