# 축제지도 — 이어서 작업 노트

## 지금까지 (2026-06-08)
"누구나 행사 약도를 올리고, 누구나 그 행사에서 길찾는" 플랫폼. 첫 사례 = 2026 서울숲 정원박람회.
원칙: **"행사는 코드가 아니라 데이터"** (행사 1건 = georeference 모서리 좌표).

도구 2개 (`/Users/rok/claude/축제지도`):
1. **PC 정렬도구** `georeferencer.html` — **GCP 방식**(QGIS 지도참조자처럼): 왼쪽 약도에서 점 찍고 오른쪽 OSM에서 같은 곳 찍기 → 2점 유사변환 / 3점 어파인 / 4점+ 투영. `좌표 내보내기`로 `georef.seoulforest.json` 출력.
2. **Flutter 앱** `app/` — OSM + 약도 오버레이(`assets/georef.json`의 모서리 사용) + 현위치 + 네이버식 방향 부채꼴(나침반).

## 실행
- 정렬도구: 프로젝트 루트에서 `python3 -m http.server 8777` → 브라우저 `http://localhost:8777/georeferencer.html`
- 앱: `cd app && flutter run -d <시뮬레이터UDID>` (iPhone 17 Pro 시뮬 사용 중)

## 다음 할 일 (여기서 멈춤)
1. 정렬도구로 약도를 실제 서울숲에 GCP로 맞추기 → `georef.seoulforest.json` 내보내기
2. 그 JSON 내용을 `app/assets/georef.json`에 덮어쓰기 → 앱에서 정렬 확인
3. (이후) 정원 핀(탭하면 이름), 앱 내에서 georef.json 파일 불러오기, 실기기에서 방향/현위치 테스트

## 핵심 파일
- `georeferencer.html` (GCP 정렬도구) · `app/lib/main.dart` (앱) · `app/assets/georef.json` (정렬 데이터) · `app/assets/seoulforest_map.png` (약도, PDF 3p 렌더)
- 원본 PDF: `69f09f2d1bd399.00570729.pdf` (4p; p3=서울숲 상세약도, ~30° 시계방향 기울어짐)

## 메모
- 베이스 지도는 저작권상 네이버/카카오 금지 → OSM 사용
- 약도 정북 아님(시계 ~30°) → GCP로 맞추면 자동 처리됨
