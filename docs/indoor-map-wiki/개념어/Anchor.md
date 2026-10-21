---
summary: IMDF Feature Type 16종 중 하나로, 특정 Address 또는 비주소 대상의 대표 표시 지점을 나타내는 Point 피처. geometry가 null이어야 하는 Occupant의 좌표를 대신 갖는다. 지오레퍼런싱 기준점과는 무관한 별개 개념
source: "OGC IMDF 1.0.0 Anchor (docs.ogc.org/cs/20-094/Anchor), [[src13. 지오레퍼런싱 기준점 최소 개수·Feature id UUID 요건 조사]], [[09) IMDF에서 좌표를 갖는 것 전체]]"
related:
  - "[[IMDF]]"
  - "[[Feature Type]]"
  - "[[Display Point]]"
  - "[[컨트롤 포인트]]"
  - "[[GeoJSON]]"
created: 2026-08-24 00:00
updated: 2026-08-24 13:00
core_keywords:
  - Anchor
---
# Anchor

## 요약

Anchor는 [[IMDF]]의 [[Feature Type]] 16종 중 하나로, **특정 주소(Address) 또는 주소를 갖지 않는 장치·서비스·설비·물리 환경의 대표 표시 지점**을 나타내는 Point 피처다. `anchor.geojson`에 저장된다.

## 핵심 내용

- 정의 원문: "An Anchor represents the curated Point used as the preferred display location of a specific Address OR non-addressable device, service, equipment or physical environment."
- geometry: **Point 필수** — "Anchor objects must have a `"geometry"` member with a `POINT` value"
- properties는 두 개뿐이다.

| 변수 | 타입 | 내용 |
|---|---|---|
| `address_id` | `null` 또는 `ADDRESS-ID` | Address 레코드 참조 |
| `unit_id` | `UNIT-ID` | "Unique identifier of the Unit the Anchor possesses a spatial relationship with" |

- **category가 없다.** IMDF Feature Type 16종 중 category를 갖지 않는 4종(Anchor·Kiosk·Detail·Address) 중 하나다.
- **[[Display Point]]도 없다.** geometry가 이미 Point이므로 별도의 대표점이 필요 없다. DISPLAY-POINT는 "non-puntal Feature"의 점 표현으로 정의되어 있어 일관적이다.
- **Occupant의 좌표를 대신 갖는 존재다.** Occupant는 geometry가 `null` 필수이므로, 입주 업체의 위치는 Occupant가 아니라 그 `anchor_id`가 가리키는 Anchor에서 나온다. Kiosk·Fixture·Amenity도 `anchor_id`로 Anchor를 참조한다.

### 지오레퍼런싱 기준점과의 구분

이름 때문에 [[컨트롤 포인트]]와 혼동되기 쉬우나 전혀 다른 개념이다.

| | IMDF Anchor | 지오레퍼런싱 기준점 |
|---|---|---|
| 목적 | 주소·입주자의 대표 표시 지점 | 도면 좌표 → 위경도 변환식 계산 |
| 최종 파일 | `anchor.geojson`에 남음 | 남지 않음 |
| 갖는 값 | 위경도 Point 하나 | 도면 좌표 + 위경도의 쌍 |
| 개수 | 주소·입주자 수만큼 | 최소 2~3, 실무상 5~10 |

두 개념이 별개라고 해서 반드시 다른 이름을 써야 하는 것은 아니다. **화면을 분리하면 같은 이름으로도 구분된다** — FP-to-IMDF 프로젝트는 지오레퍼런싱 기준점을 계속 `Anchor`라 부르되 전용 화면에서만 지정하도록 나눴다. 다만 IMDF Anchor Feature는 `unit_id` 참조를 요구하므로, 건물 외곽 모서리처럼 Unit 밖에 놓인 기준점용 Anchor는 `anchor.geojson`으로 내보낼 수 없다.

## 관련 링크

- [[IMDF]] — Anchor가 속한 데이터 포맷
- [[Feature Type]] — Anchor를 포함한 16종 분류
- [[Display Point]] — Anchor가 갖지 않는 대표점 필드
- [[컨트롤 포인트]] — 이름이 비슷한 별개 개념
- [[09) IMDF에서 좌표를 갖는 것 전체]] — Anchor의 위상을 다룬 5절

## 미해결 질문

- `unit_id`가 필수인지 null 허용인지 — OGC 표에 명시가 불충분해 확인 필요.
