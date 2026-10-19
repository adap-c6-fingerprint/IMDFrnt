---
summary: "IMDF에서 Polygon·LineString 등 점(Point)이 아닌 Feature를 지도에 라벨·아이콘으로 표시할 때 쓰는 대표 좌표점 속성. geometry가 아니라 properties 안에 들어가며, IMDF에서 좌표가 기록되는 두 자리 중 하나다"
source: "[[라벨에 관하여]], IMDF 1.0.0 공식 스펙(OGC docs.ogc.org/cs/20-094/Reference), src04·src12 조사"
related:
  - "[[IMDF]]"
  - "[[LABELS]]"
  - "[[GeoJSON]]"
  - "[[Feature Type]]"
  - "[[지오레퍼런싱]]"
  - "[[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]]"
  - "[[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]]"
  - "[[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]]"
created: "2026-08-12 00:00"
updated: "2026-10-18 22:03"
core_keywords:
  - Display Point
---
# Display Point

## 요약

Display Point는 IMDF(Indoor Mapping Data Format) 1.0.0 스펙의 Reference에 정의된 데이터 타입(DISPLAY-POINT)으로, Polygon·LineString처럼 점(Point)이 아닌 도형을 가진 Feature를, 지도 위 라벨이나 아이콘을 그릴 때 대표할 하나의 좌표점으로 나타낸다.

한 줄로 줄이면 **"이 도형의 이름표를 어디에 찍을 것인가"를 사람이 정해 박아 둔 좌표**다. 도형 자체를 이루는 좌표가 아니므로 `geometry`에 들어가지 않고, 이름·카테고리와 함께 `properties`에 들어간다.

## 1. 왜 필요한가

폴리곤 하나를 화면에 그리는 데는 꼭짓점 좌표만 있으면 된다. 그런데 그 방의 **이름("Ball Room")을 어느 위치에 찍을지**는 꼭짓점만으로 정해지지 않는다. 렌더러가 알아서 중심을 계산하게 두면 두 가지 문제가 생긴다.

1. **오목한 도형에서 중심이 도형 밖으로 나간다.** L자 복도, U자 매장의 무게중심(centroid)은 도형 바깥 허공에 찍힌다.
2. **자동 계산은 지도 디자인을 고려하지 못한다.** 통로 한복판, 문 바로 앞, 옆 매장 라벨과 겹치는 자리에 이름이 찍혀도 렌더러는 알 수 없다.

Display Point는 이 판단을 **데이터 제작 시점에 사람이 내려 파일에 저장해 두는** 장치다. 스펙이 정의를 "curated"(선별된·큐레이션된)라는 단어로 시작하는 이유가 이것이다.

## 2. 정의와 규정 원문

- 정의 원문(Reference): "A Display Point represents a curated, Point-based representation of a non-puntal Feature."
  - **non-puntal** = 점이 아닌. 즉 애초에 geometry가 Point인 Feature는 대상이 아니다.
- 규정 4개와 그 의미:

| 원문 규정 | 강도 | 의미 |
| --- | --- | --- |
| "Display Points are members of a Feature's `"property"` object" | 구조 | `geometry`가 아니라 `properties` 안에 산다 |
| "Display Points **MUST** be captured as GeoJSON Point objects" | MUST | 좌표쌍 배열이 아니라 `{"type":"Point","coordinates":[x,y]}` 형태의 온전한 GeoJSON Point 객체여야 한다 |
| "Display Points **MUST** be **within** the geometry of the Feature that possesses it" | MUST | 자기 도형 안에 있어야 한다 — centroid를 그냥 쓸 수 없는 근거 |
| "Display Points **SHOULD** be positioned in a location where map label 'collision' is least expected" | SHOULD | 라벨끼리 겹칠 가능성이 가장 낮은 자리에 두기를 권고 |

MUST 두 개는 위반하면 스펙 위반이고, SHOULD는 품질 권고다. 즉 **"도형 안"은 검사 대상이 될 수 있는 요구사항이고, "겹치지 않는 자리"는 제작자의 판단 영역**이다.

## 3. GeoJSON Feature 안에서의 실제 위치

Unit 공식 예시(OGC IMDF 1.0.0, Unit 페이지)에서 발췌하면 구조가 그대로 보인다.

```json
{
  "type": "Feature",
  "feature_type": "unit",
  "geometry": {
    "type": "Polygon",
    "coordinates": [[[100.0, 0.0], [101.0, 0.0], [101.0, 1.0], [100.0, 1.0], [100.0, 0.0]]]
  },
  "properties": {
    "category": "room",
    "name": { "en": "Ball Room" },
    "alt_name": null,
    "display_point": { "type": "Point", "coordinates": [100.0, 1.0] },
    "level_id": "22222223-2222-2222-2222-222222222222"
  }
}
```

- `geometry.coordinates` — 방의 **모양**을 이루는 좌표
- `properties.display_point.coordinates` — 방의 **이름표 위치** 좌표
- `properties.name` — 찍을 **텍스트**([[LABELS]] 타입, 언어 태그 딕셔너리)

즉 `display_point`와 `name`은 같은 `properties` 객체의 형제 멤버다. **"무엇을 쓸지(name)"와 "어디에 쓸지(display_point)"가 나란히 저장되고, 도형(geometry)은 그와 별개**라는 것이 IMDF의 라벨 모델이다.

## 4. 좌표가 기록되는 두 자리

- 값 자체는 GeoJSON Point 좌표이지만, Feature의 `geometry` 멤버가 아니라 `properties` 멤버 안에 속한다.
- **따라서 IMDF에서 좌표가 기록되는 자리는 `geometry`와 `properties.display_point` 두 곳이다.** 이 이원 구조 전체는 [[09) IMDF에서 좌표를 갖는 것 전체]] 참고.
- 실무적 귀결: **사각형 방 하나의 좌표점은 4개가 아니라 5개**(꼭짓점 4 + display_point 1)다. GeoJSON 링은 첫 점을 끝에 반복하므로 배열에 나타나는 좌표쌍은 6개가 된다.
- 좌표를 세거나, 변환하거나, 검증하는 코드를 짤 때 `geometry`만 순회하면 **Feature의 좌표를 전부 다룬 것이 아니다.**

## 5. 보유 Feature Type 9종 (전수 확인, 2026-08-20)

| 보유 여부 | Feature Type | 비고 |
| --- | --- | --- |
| **필수** | Venue | 16종 중 유일하게 null을 허용하지 않는다 |
| 있음 (null 허용) | Level, Unit, Section, Geofence, Fixture, Kiosk | 모두 POLYGONAL |
| 있음 (null 허용) | Opening | LINE-STRING인데도 갖는다 — 문 위에도 라벨·아이콘을 찍을 수 있다 |
| 있음 (null 허용) | Building | geometry가 `null` 필수인데 display_point는 갖는 특수 사례 |
| **없음** | Footprint, Detail, Amenity, Anchor, Occupant, Address, Relationship | 7종 |

없는 쪽의 이유:

- **Amenity·Anchor** — 자체 geometry가 이미 Point라 불필요하다(정의의 "non-puntal Feature"와 일관). 이미 점인 것에 대표점을 또 둘 이유가 없다.
- **Footprint** — 도형은 있지만 건물 이름 라벨의 위치는 Building이 대신 갖는다. 모양은 Footprint, 이름표는 Building으로 역할이 갈린다.
- **Detail** — properties가 `level_id` 하나뿐이라 이름도 카테고리도 없다. 찍을 라벨 자체가 없으니 대표점도 필요 없다.
- **Occupant·Address** — geometry가 `null` 필수이고 좌표는 `anchor_id`로 참조하는 Anchor가 대신 갖는다.

특수 사례:

- **Building은 geometry가 `null` 필수인데 display_point를 가질 수 있다** — 도형 없이 좌표만 갖는 유일한 사례. "MUST be within the geometry" 규정과 어떻게 양립하는지 스펙에 설명이 없다(확인 필요).
- **Venue만 필수인 이유**는 스펙에 근거 문장이 없다. 시설 전체를 가리키는 최상위 라벨이라 항상 찍혀야 하기 때문으로 추정될 뿐이다(확인 필요).

## 6. 만들 때 주의할 점

- **centroid를 그대로 쓰면 안 된다.** "MUST be within the geometry" 규정 때문이다. L자·U자 형태 폴리곤에서는 무게중심이 도형 밖으로 나갈 수 있으므로, 내부를 보장하는 연산(**point-on-surface** 계열 — PostGIS `ST_PointOnSurface`, Shapely `representative_point()`, Turf.js `pointOnFeature`)을 써야 한다. 볼록한 사각형 방에서는 둘의 결과가 같아서 문제가 드러나지 않으므로, 테스트 도면에 반드시 오목 폴리곤을 넣어야 한다.
- **MultiPolygon 주의.** `POLYGONAL`은 MultiPolygon을 포함하므로, 분리된 조각 여러 개를 가진 Unit이 있을 수 있다. display_point는 그중 **하나의 조각 안**에 있어야 하며, 보통 면적이 가장 큰 조각을 고른다.
- **구멍(hole) 주의.** 폴리곤 내부 링(중정, 기둥 구멍) 안에 점이 찍히면 "within" 위반이다. point-on-surface 계열 함수는 이를 처리하지만, 직접 구현할 때는 빠뜨리기 쉽다.
- **지오레퍼런싱 시 함께 변환해야 한다.** 회전·스케일·이동 변환식을 `geometry`에만 적용하고 display_point를 빠뜨리면 **도형은 제자리인데 라벨만 어긋난다.** 증상이 "지도는 맞는데 글씨만 엉뚱한 데 있다"로 나타나므로 원인 추적이 늦어진다. [[지오레퍼런싱]] 참고.
- **좌표 순서는 GeoJSON 규약대로 `[경도, 위도]`.** geometry와 같은 규약이지만, 별도 코드 경로로 만들어지다 보니 여기서만 뒤집히는 실수가 나온다.
- **Unit에서는 묶음 대표점으로도 쓸 수 있다 (2026-10-18 추가).** OGC IMDF 1.0.0 Unit의 Property Capturing Rules는 display_point를 Unit 하나의 대표점(MAY)뿐 아니라 "a collection of Units possessing the same category that touch", 즉 맞닿은 같은 category Unit 묶음의 대표점으로도 둘 수 있다고 한다(MAY). 위치 조건은 같다 — "MUST be within the boundary of the Unit". OGC Validations에서는 `UnitGeometryMustContainDisplayPoint`(Warning)가 이를 검사한다. 근거: [[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]] 5절, [[src20. IMDF Unit 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations]].
- **Section에서는 가이던스가 필수로 만들기도 한다 (2026-10-18 추가).** Section의 display_point는 스펙상 null 허용이지만, OGC Airport 가이던스는 `checkin`·`baggageclaim`·`immigration`·`security` Section에 display_point를 MUST로 요구한다. 보안검색 구역은 장비를 Fixture로 그리기보다 `security` Section 범위와 display_point로 나타내는 방식이 선호된다(Glossary). 위치 검사는 `SectionGeometryMustContainDisplayPoint`(Warning). 근거: [[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]] 5절.
- **Unit·Fixture 대표점 대신 Amenity 점 (2026-10-18 추가):** Amenity의 Geometry Capturing Rules는 "Unit·Fixture의 display-point 기능이 지도 표시에 마땅치 않을 때 Amenity를 쓴다(SHOULD)"고 한다. 세 Venue 가이던스는 `elevator`·`stairs`·`restroom` 등 Amenity에 "If preferred over Unit display_point" 비고를 단다. 같은 시설을 Unit 대표점으로 표시할지 Amenity 점으로 표시할지 고를 수 있다는 뜻으로 읽힌다(해석). Amenity 자신은 display_point를 갖지 않는다. 근거: [[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]] 3-2절.
- **null을 넣어도 된다.** Venue를 제외하면 모두 null 허용이므로, 자동 생성이 불확실할 때 잘못된 좌표를 넣기보다 `null`로 두는 편이 낫다.

## 7. 자주 하는 오해

- **"display_point는 도형의 중심점이다"** — 아니다. 중심일 필요가 없고, 겹침을 피하기 위해 일부러 치우친 자리에 둘 수도 있다. 규정이 요구하는 건 "도형 안"뿐이다.
- **"라벨 텍스트가 들어 있다"** — 아니다. 텍스트는 `name`([[LABELS]])이고 display_point는 좌표만 갖는다.
- **"점형 Feature도 갖는다"** — 아니다. Amenity·Anchor는 없다.
- **"geometry가 있어야 갖는다"** — 아니다. Building이 반례다.

## 관련 링크

- [[IMDF]] — Display Point가 속한 상위 스펙
- [[LABELS]] — 같은 Feature의 `properties` 안에 나란히 있는 텍스트 라벨 속성
- [[GeoJSON]] — display_point 값이 따르는 Point 객체 규약
- [[Feature Type]] — display_point 보유 여부가 갈리는 기준 분류
- [[지오레퍼런싱]] — 좌표 변환 시 display_point 누락 주의
- [[09) IMDF에서 좌표를 갖는 것 전체]] — geometry·display_point 이원 구조와 Feature Type 16종 전수표
- [[08) IMDF Feature Type·카테고리 전체 레퍼런스]] — display_point를 포함한 각 Feature Type의 속성 전체
- [[05) 라벨에 관하여]] — name·display_point가 함께 이루는 IMDF 라벨 모델
- [[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]] — Unit 태깅 시 display_point 규칙과 검증 항목
- [[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]] — Section의 display_point 규칙과 공항 가이던스
- [[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]] — Unit 대표점 대신 Amenity 점을 쓰는 경우

## 미해결 질문

- ~~Amenity 외에 자체 geometry가 Point인 Feature(Anchor 등)에도 display_point가 별도로 존재하는지~~ — 2026-08-20 전수 확인으로 해소(Anchor·Amenity 모두 없음). 다만 "점형 Feature는 display_point가 불필요하다"는 명시적 문장 자체는 여전히 미확인이며, 정의의 "non-puntal Feature" 표현으로 추론한 것이다.
- Building이 geometry `null`이면서 display_point를 갖는 것과 "MUST be within the geometry" 규정의 양립 방식.
- Venue만 display_point가 필수인 근거 — 스펙에 설명 문장 미확인.
- display_point가 `null`일 때 MapKit 등 렌더러가 라벨 위치를 어떻게 결정하는가(폴리곤 중심 자동 계산 여부) — 스펙 범위 밖, MapKit 문서 확인 필요.
- IMDFValidator가 "display_point가 geometry 안에 있는가"를 실제로 검사하는가. — 2026-10-18: OGC Validations 표에 Unit은 `UnitGeometryMustContainDisplayPoint`(Warning)가 있음을 확인. 다른 Feature Type의 대응 항목과 Apple 검수 도구의 실제 동작은 미확인.
- MultiPolygon Feature에서 display_point를 어느 조각에 두어야 하는지에 대한 스펙 규정이 있는가 — 미확인.
- "collision이 가장 적게 예상되는 위치"를 판정하는 기준이 스펙에 더 구체적으로 정의되어 있는가 — 미확인.
