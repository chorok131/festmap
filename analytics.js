/*
 * analytics.js — [D의 씨앗] 행사 동선 데이터 수집 훅
 *
 * 지금(C 단계): 네트워크 전송 없음. 콘솔 로그 + 로컬 버퍼만. → 개인정보 위험 0.
 * 나중(D 단계): sink() 함수 '속'만 Firestore 전송으로 바꾸면, e.html 의
 *               콜사이트(Festmap.track(...))를 한 줄도 안 고치고 전 행사 수집 ON.
 *
 * D 켤 때 권장 Firestore 보안 규칙 (쓰기만 허용, 읽기 차단):
 *   match /traffic/{doc} {
 *     allow create: if true;          // 방문 기록은 누구나 남길 수 있음
 *     allow read, update, delete: if false;  // 통계는 관리자가 콘솔에서만
 *   }
 * → 키가 공개돼도 남이 데이터를 '읽어갈' 수 없음. (이번 대화에서 정한 패턴)
 */
(function (global) {
  'use strict';

  // 익명 세션 ID (개인 식별 불가, 그냥 같은 방문을 묶는 용도)
  function sid() {
    var k = 'festmap.sid';
    var v = sessionStorage.getItem(k);
    if (!v) { v = Date.now().toString(36) + Math.random().toString(36).slice(2, 8); sessionStorage.setItem(k, v); }
    return v;
  }

  // ── 실제 전송부. D 단계에서 여기만 교체 ──────────────────────────
  function sink(record) {
    // [C] 지금은 콘솔 + 로컬 버퍼(최근 200개)만. 외부로 안 나감.
    if (global.console && console.debug) console.debug('[festmap.track]', record);
    try {
      var buf = JSON.parse(localStorage.getItem('festmap.buf') || '[]');
      buf.push(record); if (buf.length > 200) buf = buf.slice(-200);
      localStorage.setItem('festmap.buf', JSON.stringify(buf));
    } catch (e) {}

    // [D] 나중에 이 주석을 풀고 Firestore로:
    //   firebase.firestore().collection('traffic').add(record);
  }

  var lastPing = 0;
  var Festmap = {
    // 일반 이벤트(open, locate_granted 등)
    track: function (type, payload) {
      sink(Object.assign({ t: type, sid: sid(), ts: Date.now() }, payload || {}));
    },
    // 위치 핑은 과하지 않게 스로틀(기본 10초). 동선/체류시간 리포트의 원천 데이터.
    ping: function (payload, minIntervalMs) {
      var now = Date.now();
      if (now - lastPing < (minIntervalMs || 10000)) return;
      lastPing = now;
      this.track('ping', payload);
    }
  };

  global.Festmap = Festmap;
})(window);
