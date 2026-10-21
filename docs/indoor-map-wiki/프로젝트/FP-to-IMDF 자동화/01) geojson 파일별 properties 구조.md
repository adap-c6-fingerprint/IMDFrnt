**출처:** `IMDFData/` (각 파일의 `features` 배열 전체를 스캔하여 파일 내 블록 간 변수·타입 일관성 확인)

각 파일은 GeoJSON `Feature` 객체들의 배열이며, 공통적으로 `type`(항상 "Feature"), `id`(UUID v4 — 아래 "Feature id 규정" 절 참조), `feature_type`, `properties`, `geometry` 필드를 가진다. 아래는 `feature_type`별로 `properties`가 요구하는 변수와 타입.

타입 표기는 null 값을 제외한 실제 관측 타입 기준이며, 값이 항상 null인 필드는 "null(항상)"로 표기.

---

## address.geojson — feature_type: "address" (1개 블록)

| 변수                 | 타입       | 값 예시          | 비고     |
| ------------------ | -------- | ------------- | ------ |
| address            | string   | "80 Jigok-ro" | 도로명 주소 |
| unit               | null(항상) | null          |        |
| locality           | string   | "Pohang-si"   | 시/구    |
| province           | string   | "KR-47"       | 시/도 코드 |
| country            | string   | "KR"          | 국가 코드  |
| postal_code        | string   | "37673        | 우편번호   |
| postal_code_ext    | null(항상) | null          |        |
| postal_code_vanity | null(항상) | null          |        |

geometry: null
블록 간 변수 차이: 없음 (블록 1개)

---

## amenity.geojson — feature_type: "amenity" (36개 블록)

| 변수 | 타입 | 값 예시 | 비고 |
|---|---|---|---|
| category | string | "stairs" | 시설물 종류 |
| accessibility | null(항상) | null | |
| name | object{en} \| object{en,ko} | {en, ko} | 다국어 이름 객체 |
| alt_name | null(항상) | null | |
| hours | null(항상) | null | |
| phone | null(항상) | null | |
| website | null(항상) | null | |
| unit_ids | array\<string\> | ["..."] | 연결된 unit id 배열 |
| address_id | string \| null | "..." | address.geojson 참조 |
| correlation_id | null(항상) | null | |
| display_point | object{type,coordinates} | {type: Point, coordinates} | **36개 중 9개 블록에만 존재** |
| level_id | string | "..." | **36개 중 9개 블록에만 존재** |

geometry: Point
**블록 간 변수 차이 있음** — `display_point`, `level_id` 두 키는 9/36 블록에만 나타남. 이 9개는 카테고리가 elevator 등 층(level)에 직접 속한 시설이고, 나머지 27개는 `address_id`로만 연결되는 시설(계단 등)로 보임.

---

## anchor.geojson — feature_type: "anchor" (22개 블록)

| 변수 | 타입 | 값 예시 | 비고 |
|---|---|---|---|
| address_id | string | "..." | address.geojson 참조 |
| unit_id | string | "..." | unit.geojson 참조 |

geometry: Point
블록 간 변수 차이: 없음

---

## building.geojson — feature_type: "building" (1개 블록)

| 변수 | 타입 | 값 예시 | 비고 |
|---|---|---|---|
| name | object{en,ko} | {en, ko} | |
| alt_name | null(항상) | null | |
| category | string | "unspecified" | |
| restriction | null(항상) | null | |
| display_point | object{type,coordinates} | {type: Point, coordinates} | |
| address_id | string | "..." | address.geojson 참조 |

geometry: null
블록 간 변수 차이: 없음 (블록 1개)

---

## fixture.geojson — feature_type: "fixture" (38개 블록)

(이 파일만 필드 순서가 다름: id, type, feature_type, geometry, properties)

| 변수 | 타입 | 값 예시 | 비고 |
|---|---|---|---|
| category | string | "desk" | 비품 종류 |
| name | object{en} | {en} | |
| alt_name | null(항상) | null | |
| anchor_id | null(항상) | null | |
| display_point | object{type,coordinates} | {type: Point, coordinates} | |
| level_id | string | "..." | level.geojson 참조 |

geometry: MultiPolygon
블록 간 변수 차이: 없음

---

## footprint.geojson — feature_type: "footprint" (2개 블록)

| 변수 | 타입 | 값 예시 | 비고 |
|---|---|---|---|
| category | string | "ground" | |
| name | null(항상) | null | |
| building_ids | array\<string\> | ["..."] | building.geojson 참조 배열 |

geometry: Polygon
블록 간 변수 차이: 없음

---

## level.geojson — feature_type: "level" (6개 블록)

| 변수 | 타입 | 값 예시 | 비고 |
|---|---|---|---|
| category | string | "unspecified" | |
| restriction | null(항상) | null | |
| outdoor | boolean | false | |
| ordinal | integer | 0 | 층 순서 |
| name | object{en,ko} | {en, ko} | |
| short_name | object{en} | {en} | |
| display_point | object{type,coordinates} | {type: Point, coordinates} | |
| address_id | string | "..." | address.geojson 참조 |
| building_ids | array\<string\> | ["..."] | building.geojson 참조 배열 |

geometry: Polygon
블록 간 변수 차이: 없음

---

## occupant.geojson — feature_type: "occupant" (22개 블록)

| 변수 | 타입 | 값 예시 | 비고 |
|---|---|---|---|
| category | string | "sharedofficespace" | |
| name | object{en} \| object{en,ko} | {en} | |
| unit_id | string | "..." | unit.geojson 참조 |
| level_id | string | "..." | level.geojson 참조 |
| correlation_id | null(항상) | null | |
| anchor_id | string | "..." | anchor.geojson 참조 |
| hours | null(항상) | null | |
| phone | null(항상) | null | |
| validity | null(항상) | null | |
| website | null(항상) | null | |

geometry: null
블록 간 변수 차이: 없음

---

## opening.geojson — feature_type: "opening" (59개 블록)

| 변수 | 타입 | 값 예시 | 비고 |
|---|---|---|---|
| category | string | "pedestrian" | 문/통로 종류 |
| access_control | null(항상) | null | |
| door | null(항상) | null | |
| name | object{en} | {en} | |
| alt_name | null(항상) | null | |
| level_id | string | "..." | level.geojson 참조 |
| display_point | null(항상) | null | |
| accessibility | null(항상) | null | |

geometry: LineString
블록 간 변수 차이: 없음

---

## unit.geojson — feature_type: "unit" (167개 블록)

| 변수 | 타입 | 값 예시 | 비고 |
|---|---|---|---|
| category | string | "structure" | 공간 종류 |
| name | null \| object{en} \| object{en,ko} | null | |
| alt_name | null(항상) | null | |
| level_id | string | "..." | level.geojson 참조 |
| restriction | null(항상) | null | |
| display_point | null \| object{type,coordinates} | {type: Point, coordinates} | |
| accessibility | null(항상) | null | |
| id | string | "..." | **167개 중 166개 블록에만 존재**, properties 안에 id 중복(주의) |

geometry: Polygon
**블록 간 변수 차이 있음** — `id` 키가 166/167 블록에만 존재하고 1개 블록엔 없음. 나머지 필드는 모든 블록에 공통.

---

## venue.geojson — feature_type: "venue" (1개 블록)

| 변수 | 타입 | 값 예시 | 비고 |
|---|---|---|---|
| category | string | "university" | |
| restriction | null(항상) | null | |
| name | object{en,ko} | {en, ko} | |
| alt_name | object{ko} | {ko} | |
| address_id | string | "..." | address.geojson 참조 |
| hours | null(항상) | null | |
| phone | string | "+820542798881" | |
| website | string | "https://www.postech.ac.kr" | |
| display_point | object{type,coordinates} | {type: Point, coordinates} | |
| building_ids | array\<string\> | ["..."] | building.geojson 참조 배열 |

geometry: Polygon
블록 간 변수 차이: 없음 (블록 1개)

---

## Feature `id` 규정 — RFC 4122 version 4 UUID (2026-08-24 확정)

**출처:** OGC IMDF 1.0.0 Reference — `https://docs.ogc.org/cs/20-094/Reference/index.html`

`id`가 UUID라는 것은 관측에서 추론한 것이 아니라 **공식 스펙에 MUST로 명시된 규정**이다. 원문:

> "A Feature object **MUST** contain the GeoJSON `"id"` member with a `FEATURE-ID` value"

`FEATURE-ID`는 세 가지를 강제한다.

| # | 원문 | 도구 설계에 미치는 영향 |
|---|---|---|
| 1 | "Feature IDs **MUST** be a globally unique, RFC 4122 compliant **version 4** UUID" | 시각 기반(v1)·이름 기반(v3/v5)이 아니라 **난수 기반 v4**여야 한다. Swift `UUID()`가 v4를 생성하므로 그대로 쓸 수 있다 |
| 2 | "Feature IDs **MUST** be retained to identify the target feature during the lifetime of its existence **across distinct deliveries**" | 같은 대상을 다시 내보낼 때 **같은 UUID를 유지**해야 한다. 내보낼 때마다 새로 발급하면 스펙 위반이므로, 발급한 UUID를 프로젝트 파일에 영구 저장해야 한다 |
| 3 | "Feature IDs **MUST NOT** be re-assigned to another Feature of any type within the target dataset or any other" | 삭제·휴지통 처리된 Feature의 UUID를 다른 Feature가 물려받아서는 안 된다 |

같은 페이지의 `UUID` 데이터 타입 정의도 "RFC 4122, section 4.4 compliant version 4 UUID"로 동일하다. RFC 4122 §4.4가 난수 기반 UUID를 정의하는 절이다.

**참고:** `unit.geojson`의 `properties` 안에 중복 기재된 `id`(166/167 블록)는 이 규정과 무관한 비표준 확장이다. 스펙은 `id`를 **top-level Feature 멤버로만** 요구한다.

---

## 파일 내 블록 간 변수 불일치 요약

| 파일 | 불일치 내용 |
|---|---|
| amenity.geojson | `display_point`, `level_id` 키가 9/36 블록에만 존재 |
| unit.geojson | `id` 키가 166/167 블록에만 존재 |

나머지 파일(address, anchor, building, fixture, footprint, level, occupant, opening, venue)은 블록 수와 무관하게 모든 블록이 동일한 키 집합을 가짐.

---

## Apple/OGC 공식 IMDF 1.0.0 스펙과의 대조

**출처:** OGC Community Standard `https://docs.ogc.org/cs/20-094/` (Apple이 register.apple.com에 게시한 IMDF 스펙과 동일 계보의 공식 문서)

실제 프로젝트 데이터(`IMDFData/`)를 공식 스펙의 각 feature_type properties 표와 하나씩 대조한 결과, **4개 필드가 공식 스펙에는 없는 비표준(프로젝트 확장) 필드**로 확인됨.

| 파일 | 비표준 필드 | 내용 |
|---|---|---|
| amenity.geojson | `level_id`, `display_point` | 공식 스펙의 amenity properties는 `category, accessibility, name, alt_name, hours, phone, website, unit_ids, address_id, correlation_id` 10개뿐. `level_id`/`display_point`는 정의돼 있지 않음 (36개 중 9개 블록에만 등장) |
| occupant.geojson | `unit_id` | 공식 스펙의 occupant properties는 `name, category, anchor_id, hours, phone, website, validity, correlation_id` 8개뿐. `unit_id`는 정의돼 있지 않으며, 스펙상 occupant의 위치는 `anchor_id` 참조로만 결정됨 |
| venue.geojson | `building_ids` | 공식 스펙의 venue properties는 `category, restriction, name, alt_name, hours, phone, website, display_point, address_id` 9개뿐. `building_ids`는 정의돼 있지 않음 |
| unit.geojson | `id` (properties 내부) | 공식 스펙은 "Unit objects MUST have an `id` member"를 **top-level Feature에만** 요구하며, properties 스키마에는 `id`가 포함되지 않음. 실제 데이터는 properties 안에도 `id`를 중복 기재(166/167 블록) |

나머지 항목(address, anchor, building, fixture, footprint, level, opening)은 공식 스펙의 properties 목록과 완전히 일치함 (관측된 필드 = 스펙에 정의된 필드).

**참고:** 이 프로젝트 데이터가 실제 iOS 앱(`IMDFModel/`)에서 이 비표준 필드들을 활용 중이므로(예: `Amenity.Properties.unit_ids`, `Occupant.Properties.anchorId` 등 Swift 모델 참조), 자동화 파이프라인에서 이 필드들을 계속 생성할지, 공식 스펙 준수를 우선해 제거할지는 별도 검토 필요.

---

## 참고

- `manifest.json`은 feature 파일이 아니라 전체 세트의 메타데이터: `version`, `created`, `generated_by`, `language`
- `LICENSE/` 폴더는 별도 확인 안 함
- **이 문서의 `값 예시`는 실제 샘플 파일에서 관찰된 값이지 허용값 목록이 아니다.** type별 `category` 허용값 전체는 OGC IMDF 1.0.0 Categories 페이지가 정본이며, `01) Wiki/01-2) 소스 .../src11. IMDF 공식 스펙 — Feature Type 16종·카테고리 열거형 전수 조사.md` 2절에 전량 수집돼 있다. 프로토타입의 드롭다운(`PropertySchema.categoryOptions`)은 2026-08-25에 그 원문과 전량 대조를 마쳤다(`03) FTI 아키텍쳐.md` 2.18절)
