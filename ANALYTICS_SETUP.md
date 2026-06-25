# 사용 집계 켜기 (Firebase) — 10분, 코드 0줄

분석 코드(`analytics.js`)는 이미 들어가 있고, **Firebase 설정만 붙이면 켜집니다.**
설정 전에는 "로컬 전용"으로 조용히 동작(아무것도 안 깨짐).

수집 단계 (행사별 `georef.json` 의 `"track"` 값으로 제어):
- `"counts"` (기본): 열람 수 / 위치사용 수만. **좌표 저장 안 함 → 개인정보 위험 0.**
- `"heat"` (권장 동선): **익명 격자 히트맵.** 좌표를 약 25m 칸으로 뭉개 "칸별 인원수"만 집계. 개인 경로 저장 안 함 → 익명 통계라 **동의 없이도 안전**(4원칙은 코드로 강제, `heatmap.html`에서 시각 설명). `"cellM"`으로 칸 크기(m) 조절.
- `"full"`: 개인 GPS 경로까지 저장(세밀 경로선). **개인정보라 관람객 본인 동의·고지 필요.** 특수 용역에서만.
- `"off"`: 전송 안 함.

### 익명 격자(heat)의 4원칙 — `heatmap.html` 데모로 설명
① 칸을 크게(25m) ② 세션ID와 칸을 서버에서 분리(카운터만 +1) ③ 희소 칸은 렌더 시 숨김(임계값) ④ 일 단위만, 정밀 시각 미저장. → 개인 경로 복원 불가. 데이터는 기존 `daily/{day}` 문서에 `h_<칸>` 필드로 누적(보안 규칙 변경 불필요).

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

    // 셀프 편집 저장본(핀/라벨): 공개 읽기(뷰어가 사용), 쓰기 허용.
    // 운영: 비공개 편집링크(?edit=<키>)로만 편집 UI 진입 + "원본 되돌리기"로 복구.
    match /events/{slug}/live/{doc} {
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
