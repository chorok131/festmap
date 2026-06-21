# 사용 집계 켜기 (Firebase) — 10분, 코드 0줄

분석 코드(`analytics.js`)는 이미 들어가 있고, **Firebase 설정만 붙이면 켜집니다.**
설정 전에는 "로컬 전용"으로 조용히 동작(아무것도 안 깨짐).

수집 단계 (행사별 `georef.json` 의 `"track"` 값으로 제어):
- `"counts"` (기본): 열람 수 / 위치사용 수만. **좌표 저장 안 함 → 개인정보 위험 0.**
- `"full"`: 동선 경로까지(히트맵·체류시간용). **위치정보라 수집 고지 필요.** 유료 행사에서만 권장.
- `"off"`: 전송 안 함.

---

## 1. Firebase 프로젝트 만들기
1. https://console.firebase.google.com → **프로젝트 추가** → 이름 `festmap` (Google 애널리틱스는 꺼도 됨)
2. 왼쪽 **빌드 → Firestore Database → 데이터베이스 만들기** → **프로덕션 모드** → 위치 `asia-northeast3 (서울)`

## 2. 웹앱 등록 + 설정 복사
1. 프로젝트 개요 옆 **⚙ → 프로젝트 설정 → 일반 → 내 앱 → 웹(`</>`)** 추가 (앱 닉네임 `festmap-web`)
2. 표시되는 `firebaseConfig` 객체를 복사 → 저장소 **`firebase-config.js`** 의 `window.FESTMAP_FB = { ... }` 안에 붙여넣기
   (이 값들은 비밀이 아님 — 공개돼도 됩니다. 보안은 아래 규칙이 담당)
3. `git add firebase-config.js && git commit && git push`

## 3. 보안 규칙 (가장 중요) — Firestore → 규칙 탭에 붙여넣고 게시
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // 원천 세션 기록: 누구나 자기 것 쓰기만, 읽기/삭제 차단 (D단계 동선 원본)
    match /events/{slug}/sessions/{sid} {
      allow create, update: if true;
      allow read, delete: if false;
    }

    // 일별 집계 숫자: 공개 읽기 가능(민감X), 증가 쓰기 허용
    match /events/{slug}/daily/{day} {
      allow read: if true;
      allow write: if true;
    }
  }
}
```
> 트레이드오프: `daily` 쓰기를 열어둬서 누군가 숫자를 부풀릴 수 있음(소규모 행사엔 사실상 무의미). **진짜 원천은 `sessions`**(세션ID별, 위조 불가)이라 검증은 거기서.

## 4. 숫자 확인하는 법
- Firebase 콘솔 → Firestore → `events/seoulforest-2026/daily/<날짜>` 문서 → `opens`, `locates` 필드.
- 인바운드 증거 메일엔 이 숫자면 충분: *"○월 ○일 △△행사에서 지도 열람 N명, 위치사용 M명."*

## 5. 동선까지 켜기 (유료 행사)
해당 행사 `georef.json` 에 `"track": "full"` 로 바꾸면, 세션별 경로가 `sessions/{sid}.path` 에 쌓임.
좌표 샘플 간격은 `"sampleSec"` 로 조절(기본 180초). **이때는 뷰어에 "통계 목적 위치 수집" 고지 한 줄 추가 필요.**

샘플 간격별 무료 수용(쓰기 2만/일, 30분 체류 기준):
- `"sampleSec": 180` (기본): 1인당 ~12 write → **하루 ~1,500명**. 존별 체류·히트맵엔 충분.
- `"sampleSec": 10` : 1인당 ~180 write → 하루 ~150명. 세밀 경로선용, 대형 행사 + Blaze 전환 시.

```json
{ "event": "...", "track": "full", "sampleSec": 180, "corners": { ... } }
```
