---
summary: OGC IMDF 커뮤니티 표준 Archives·Manifest 절과 FME Writer 문서에서 확인한 IMDF 아카이브(ZIP) 구성 규칙 조사
source: https://docs.ogc.org/cs/20-094/Reference/index.html , https://docs.ogc.org/cs/20-094/Manifest/index.html , https://docs.safe.com/fme/html/FME-Form-Documentation/FME-ReadersWriters/imdf/imdf.htm
related:
  - "[[14) .geojson 파일을 모아 IMDF 아카이브로 패키징하는 과정]]"
created: 2026-10-15 21:00
updated: 2026-10-15 21:00
core_keywords:
  - IMDF 아카이브
  - Manifest
---
# src18. IMDF 아카이브 패키징 규격 조사

- 수집일: 2026-10-15
- 목적: IM-DFrnt 이슈 #38("`.geojson` 모아서 `.imdf` 변환")의 출력물 규격 확인

## 1. Archives 절 (OGC 20-094 Reference)

- "Datasets **MUST** be delivered as ZIP compressed archives using the ".zip" filename extension" — 전달 단위는 ZIP, 확장자는 `.zip`이다. 확인한 페이지 어디에도 `.imdf` 확장자는 나오지 않는다.
- 아카이브에는 "a Manifest object supplied in a dedicated file named "manifest.json""이 반드시 있어야 한다.
- Feature는 동질적인 GeoJSON FeatureCollection으로 묶여, 각각 `.geojson` 확장자의 전용 파일에 담긴다.
- 필수 파일: `manifest.json`, `address.geojson`, `venue.geojson`.
- 선택 파일: amenity, anchor, building, detail, fixture, footprint, kiosk, level, occupant, opening, relationship, section, geofence, unit (각 `.geojson`).
- 문자열은 STRING 절에서 "MUST be UTF-8 encoded"를 요구한다.
- 디렉터리 구조(파일을 ZIP 최상위에 둘지)에 대한 별도 규정은 확인한 본문에 없다.

## 2. Manifest 절

| 필드 | 필수 | 요건(원문 요지) |
| --- | --- | --- |
| `version` | 필수 | 현재 허용 값은 `"1.0.0"` 하나뿐 |
| `created` | 필수 | 아카이브가 생성·패키징된 시각의 유효한 DATE-TIME. 패키징 시점에 생성하는 것을 권장(SHOULD) |
| `generated_by` | 선택(null 허용) | 불투명 문자열. 감사·문제 해결 용도 |
| `language` | 필수 | Venue 데이터의 기본 언어를 나타내는 유효한 LANGUAGE 태그 |
| `extensions` | 선택(null 허용) | 사용한 정식 IMDF 확장 식별자 배열 |

예시: `{"version":"1.0.0","created":"2020-09-09T12:34:56","generated_by":"FME 2019.0 b19238","language":"en-US","extensions":[...]}`

## 3. FME Writer 문서

- "IMDF datasets are often written using a .zip extension, which automatically creates a single zipped file containing the feature type GeoJSON files."
- "The writer creates this manifest.json file automatically, based on the user's default language setting."
- "The IMDF writer will reproject all geometric features to WGS84 when they are written."
- 페이지에서 `.imdf` 확장자는 언급되지 않는다.

## 확인 필요

- `.imdf`가 어떤 도구·업로드 경로에서 쓰이는 확장자인지 — 이번 조사에서 근거 없음. Apple Maps Connect 업로드 화면의 허용 확장자는 미확인.
- ZIP 최상위에 파일을 두어야 하는지(하위 폴더 허용 여부) — 스펙 본문에 규정 없음.
- `created`의 시간대 표기 요건 — 예시는 오프셋 없는 형식이나 규범적 요건은 확인 못 함.
- 이 문서의 Archives 절 인용은 WebFetch 요약 결과이므로 원문 대조 권장.
