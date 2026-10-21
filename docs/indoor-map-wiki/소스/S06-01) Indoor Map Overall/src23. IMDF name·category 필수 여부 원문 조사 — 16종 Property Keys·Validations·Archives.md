---
summary: "OGC IMDF 1.0.0 Feature 페이지 16개의 Property Keys 표에서 name·alt_name·short_name·category 행을 원문 그대로 모으고, Validations 페이지에서 이름·카테고리 관련 검증 규칙(MustHaveCategory·CategoryMustBeValid·MustHaveName·ShouldHaveName·LabelMustNotBeBlank·HasOnlyAltName 등)의 대상 Feature와 등급을 전수 수집했다. Reference의 LABELS 규칙과 Archives 필수 파일 표도 함께 옮겼다."
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0) Address·Amenity·Anchor·Building·Detail·Fixture·Footprint·Geofence·Kiosk·Level·Occupant·Opening·Relationship·Section·Unit·Venue·Validations·Reference·Categories 페이지 HTML 직접 취득(2026-10-19)"
created: "2026-10-19 14:45"
updated: "2026-10-19 14:45"
---
# IMDF name·category 필수 여부 원문 조사 — 16종 Property Keys·Validations·Archives

## 수집 기준

- 수집일: 2026-10-19
- 목적: 사용자 요청 "name 또는 category가 들어가는 property type에 대해 name 및 category 필수 입력 여부를 표로 정리". 대화 중 "category는 필수인가", "name은 필수인가", "Unit·Fixture·Opening은 필수인가"를 차례로 물었고, 공식 문서로 확인해 답한 근거를 한곳에 모은다.
- 기존 위키 기록: [[src11. IMDF 공식 스펙 — Feature Type 16종·카테고리 열거형 전수 조사]]는 Venue·Geofence만 필수 여부를 적었고, 나머지는 속성 이름만 나열했다. [[src04. IMDF 공식 스펙 — 라벨·Name·Display Point 필드 조사]]는 LABELS 타입 규칙을 다뤘다. 이번에 16종 전부의 표 행과 검증 등급을 전수로 보충한다.
- 방법: `curl`로 HTML을 직접 받아 `<tr>` 행에서 셀 텍스트를 뽑았다. 요약 모델을 거치는 WebFetch는 쓰지 않았다. Validations는 본문 텍스트에서 규칙 이름·설명·대상 Feature·등급(Violation/Warning) 네 덩어리를 정규식으로 뽑았다.
- 표 읽는 법: Property Keys 표의 Type 칸이 `LABELS`처럼 단독이면 값이 반드시 있어야 하고, `null or LABELS`처럼 `null or`가 붙으면 비워 둘 수 있다. 스펙은 이 차이를 별도 문장으로 설명하지 않지만, Validations의 `MustHaveName`·`MustHaveCategory` 규칙이 `null or`가 없는 칸에만 붙어 있어 이 해석과 맞는다.

## 핵심 출처

- 각 Feature 페이지: `https://docs.ogc.org/cs/20-094/<Feature>/index.html` (경로 첫 글자는 대문자. 소문자 경로는 404)
- Validations: https://docs.ogc.org/cs/20-094/Validations/index.html
- Reference: https://docs.ogc.org/cs/20-094/Reference/index.html (`#labels`, `#archives`)

---

## 1. Property Keys 표 원문 — name·alt_name·short_name·category 행

Type 칸과 Description 칸을 원문 그대로 옮겼다. Description이 길면 앞부분만 옮겼다.

### 1-1. Venue

| Property | Type | Description |
| --- | --- | --- |
| category | VENUE-CATEGORY | The category that best describes the function of the physical Venue |
| name | LABELS | The official name for the Venue as declared by the Venue Organization |
| alt_name | null or LABELS | Alternative name for the Venue that may be recognized by the Venue Organization or which are commonly used amongst pedestrians that frequent the Venue |

### 1-2. Building

| Property | Type | Description |
| --- | --- | --- |
| name | null or LABELS | The official name for the Building as declared by the Venue Organization |
| alt_name | null or LABELS | Alternative name for the Building that may be recognized by the Venue Organization or which is commonly used amongst pedestrians that frequent the Building |
| category | BUILDING-CATEGORY | The category that best describes the function of the physical Building |

### 1-3. Footprint

| Property | Type | Description |
| --- | --- | --- |
| category | "aerial" , "ground" , "subterranean" | The category that best describes the nature of the Footprint |
| name | null or LABELS | The name for the Footprint as declared by the Venue Organization. If present, assumed to be metadata not intended for rendering purposes |

Footprint에는 `alt_name`이 없다. category는 열거형 이름 대신 값 세 개를 직접 적었다.

### 1-4. Level

| Property | Type | Description |
| --- | --- | --- |
| category | LEVEL-CATEGORY | The category that best describes the function of the physical Level |
| name | LABELS | The name of the Level as declared by the Venue Organization |
| short_name | LABELS | The short name of the Level as declared by the Venue Organization |

Level에는 `alt_name`이 없고 대신 `short_name`이 있다.

### 1-5. Unit

| Property | Type | Description |
| --- | --- | --- |
| category | UNIT-CATEGORY | The category that best describes the function of the physical Unit |
| name | null or LABELS | The name of the Unit as declared by the Venue Organization |
| alt_name | null or LABELS | Alternative name for the Unit that may be recognized by the Venue Organization |

### 1-6. Section

| Property | Type | Description |
| --- | --- | --- |
| category | SECTION-CATEGORY | The category that best describes the function of the Section |
| name | null or LABELS | The name of the Section as declared by the Venue Organization |
| alt_name | null or LABELS | Alternative name for the Section that may be recognized by the Venue Organization |

### 1-7. Opening

| Property | Type | Description |
| --- | --- | --- |
| category | OPENING-CATEGORY | The category that best describes the function of the physical entrance |
| name | null or LABELS | The name of the Opening as declared by the Venue Organization |
| alt_name | null or LABELS | Alternative name for the Opening that may be recognized by the Venue Organization |

### 1-8. Geofence

| Property | Type | Description |
| --- | --- | --- |
| category | GEOFENCE-CATEGORY | The category that best describes the function of the Geofence |
| name | null or LABELS | The official name for the Geofence as declared by the Venue Organization |
| alt_name | null or LABELS | Alternative name for the Geofence |

### 1-9. Amenity

| Property | Type | Description |
| --- | --- | --- |
| category | AMENITY-CATEGORY | The category that best describes the function and/or service provided by the Amenity |
| name | null or LABELS | The name of the Amenity as declared by the Venue Organization |
| alt_name | null or LABELS | Alternative name for the Amenity that may be recognized by the Venue Organization |

### 1-10. Fixture

| Property | Type | Description |
| --- | --- | --- |
| category | FIXTURE-CATEGORY | The category that best describes the function of the physical Fixture |
| name | null or LABELS | The name of the Fixture as declared by the Venue Organization |
| alt_name | null or LABELS | Alternative name for the Fixture that may be recognized by the Venue Organization |

### 1-11. Kiosk

| Property | Type | Description |
| --- | --- | --- |
| name | null or LABELS | The name of the Kiosk as declared by the Venue Organization |
| alt_name | null or LABELS | Alternative name for the Kiosk that may be recognized by the Venue Organization |

Kiosk 표에는 category 행이 없다.

### 1-12. Occupant

| Property | Type | Description |
| --- | --- | --- |
| name | LABELS | The brand name for the Occupant |
| category | OCCUPANT-CATEGORY | The category that best describes the function and/or service provided by the Occupant |

Occupant에는 `alt_name`이 없다.

### 1-13. Relationship

| Property | Type | Description |
| --- | --- | --- |
| category | RELATIONSHIP-CATEGORY | The category that best describes the Relationship. |

Relationship 표에는 name 행이 없다.

### 1-14. name·category가 모두 없는 Feature

Anchor·Detail·Address 표의 전체 행이다. name·alt_name·category가 하나도 없다.

| Feature | Property 전체 |
| --- | --- |
| Anchor | `address_id`(null or ADDRESS-ID), `unit_id`(UNIT-ID) |
| Detail | `level_id`(LEVEL-ID) |
| Address | `address`(STRING), `unit`(null or STRING), `locality`(STRING), `province`(null or ISO 3166-2), `country`(ISO 3166), `postal_code`(null or STRING), `postal_code_ext`(null or STRING), `postal_code_vanity`(null or STRING) |

---

## 2. Validations 원문 — 이름·카테고리 관련 규칙 전수

Validations 표는 규칙 이름, 설명, 대상 Feature, 등급(Violation 또는 Warning)으로 되어 있다. 같은 이름의 규칙이 여러 Feature에 반복해서 실려 있어, Feature별로 나눠 옮겼다.

### 2-1. category가 있는가 (`...MustHaveCategory`)

| 규칙 | 대상 | 등급 | 설명 원문 |
| --- | --- | --- | --- |
| VenueMustHaveCategory | Venue | Violation | Validates that the Venue has a category. |
| BuildingMustHaveCategory | Building | Violation | Validates that a Building has a category. |
| LevelMustHaveCategory | Level | Violation | Validates that a Level has a category value. |
| UnitMustHaveCategory | Unit | Violation | Validates that a Unit has a category. |
| SectionMustHaveCategory | Section | Violation | Validates that a Section has a category. |
| OpeningMustHaveCategory | Opening | Violation | Validates that an Opening has a category. |
| GeofenceMustHaveCategory | Geofence | Violation | Validates that a Geofence has a category value. |
| AmenityMustHaveCategory | Amenity | Violation | Validates that an Amenity has a category value. |
| FixtureMustHaveCategory | Fixture | Violation | Validates that a Fixture has a category value. |
| OccupantMustHaveCategory | Occupant | Violation | Validates that an Occupant has a category value. |

Footprint·Relationship에는 `MustHaveCategory` 규칙이 없다. 두 Feature도 표의 category Type 칸에 `null or`가 없다.

### 2-2. category 값이 목록 안에 있는가 (`...CategoryMustBeValid`)

모두 Violation이다. 대상: Venue, Building, Footprint, Level, Unit, Section, Opening, Geofence, Amenity, Fixture, Occupant, Relationship(12종 전부). 설명 원문 형식은 "Validates the category assigned to a(n) <Feature>."이다.

### 2-3. name이 있는가 (`...MustHaveName`·`...HasNoName`)

| 규칙 | 대상 | 등급 | 설명 원문 |
| --- | --- | --- | --- |
| VenueMustHaveName | Venue | Violation | Validates that a Venue has a Name. |
| LevelMustHaveName | Level | Violation | Validates that a Level has a name. |
| LevelMustHaveShortName | Level | Violation | Validates that a Level has a short_name. |
| OccupantMustHaveName | Occupant | Violation | Validates that an Occupant has a Name. |
| BuildingHasNoName | Building | **Warning** | Validates that a Building has a name. |

### 2-4. 특정 category일 때 name이 있어야 하는가 (`...ShouldHaveName`)

모두 Warning이다.

| 규칙 | 대상 | 설명 원문 |
| --- | --- | --- |
| AircraftBoardingGateAmenityShouldHaveName | Amenity | Validates that a 'boardinggate.aircraft' Amenity possesses a name. |
| ArrivalGateAmenityShouldHaveName | Amenity | Validates that an 'arrivalgate' Amenity possesses a name. |
| BaggageCarouselAmenityShouldHaveName | Amenity | Validates that a 'baggagecarousel' Amenity possesses a name. |
| BusBoardingGateAmenityShouldHaveName | Amenity | Validates that a 'boardinggate.bus' Amenity possesses a name. |
| TrainBoardingGateAmenityShouldHaveName | Amenity | Validates that a 'boardinggate.train' Amenity possesses a name value. |
| BaggageCarouselFixtureShouldHaveName | Fixture | Validates that a 'baggagecarousel' Fixture has a name value when it has a display_point, and the Fixture does not contain a 'baggagecarousel' Amenity. |
| BaggageCarouselFixtureShouldHaveDisplayPointAndName | Fixture | (설명 원문 끝부분) …display_point and name when the Fixture does not contain a 'baggagecarousel' Amenity. |

### 2-5. name 값의 형식

| 규칙 | 대상과 등급 | 설명 원문 |
| --- | --- | --- |
| LabelMustNotBeBlank | Address·Amenity·Building·Fixture·Footprint·Geofence·Kiosk·Level·Occupant·Opening·Section·Unit·Venue, 모두 Violation | Validates that a Label (prefLabel and altLabel) is not blank. |
| NameMustBeString | Violation: Amenity·Building·Geofence·Level·Occupant·Opening·Section·Unit·Venue / Warning: Fixture·Footprint·Kiosk | Validates that a name is a string data type. |
| AltNameMustBeString | Amenity·Building·Fixture·Geofence·Kiosk·Opening·Section·Unit·Venue, 모두 Violation | Validates that an alt_name is a string data type. |
| HasOnlyAltName | Warning: Amenity·Building·Fixture·Opening·Section·Unit / Kiosk는 Violation과 Warning에 둘 다 실림 | Validates that an alt_name value is not exclusive, that it is accompanied by a name value. |
| AltNameLangTagHasNoCorrespondingNameLangTag | Amenity·Building·Fixture·Geofence·Kiosk·Opening·Section·Unit·Venue, 모두 Warning | Validates that a language tag associated with an alt_name has a corresponding presence and association with a name value. |

- Kiosk의 HasOnlyAltName은 한 번은 Violation("Kiosk feature severity rule definition"이라는 문구가 붙음), 한 번은 Warning으로 실려 있다. **스펙 원문 안에서 일치하지 않는다.** `확인 필요`
- LabelMustNotBeBlank가 Address에도 실려 있지만, Address 표에는 LABELS 타입 칸이 없다. 왜 Address에 붙어 있는지는 원문에 설명이 없다. `확인 필요`

### 2-6. 이름 중복·혼동

| 규칙 | 대상 | 등급 | 설명 원문 |
| --- | --- | --- | --- |
| AmenityNameAndCategoryAreSame | Amenity | Warning | Validates that an Amenity does not possess a category that matches the name. |
| AmenityNameShouldNotBeDuplicate | Amenity | Warning | Validates that names among Amenities with the same category ('arrivalgate', 'boardinggate.aircraft', 'boardinggate.bus' and 'boardinggate.train') are distinct. |
| BaggageCarouselAmenityNameIsDuplicateInSameBuilding | Amenity | Warning | Validates that 'baggagecarousel' Amenity names are distinct in the same Building. |
| BuildingNameIsNotDistinct | Building | Warning | Validates that a Building name is distinct. |
| BuildingAltNameShouldBeDistinct | Building | Warning | Validates that a Building's alt_name is distinct. |
| BuildingNameMatchesOccupantName | Building | Warning | Validates that a Building name does not match an Occupant name it 'contains'. |
| LevelNamesInBuildingShouldBeDistinct | Building | Warning | Validates that Levels referencing the same Building possess dissimilar name values. |
| LevelShortNamesInBuildingShouldBeDistinct | Building | Warning | Validates that Levels referencing the same Building possess dissimilar short_name values. |

---

## 3. Reference 원문

### 3-1. LABELS

> Labels are JSON objects used to capture a single lexical label for an entity in one or more explicitly stated languages.
> - Labels MUST use a valid LANGUAGE-TAG as their members
> - Labels MUST NOT contain duplicate LANGUAGE-TAG members
> - Labels MUST contain a STRING value for each member
> - Labels MUST contain an entry in the default language

예시 원문: `{ "en": "red", "es": "rojo", "fi": "punainen", "fr": "rouge", "it": "rosso", "jp": "赤" }`, `{ "en-US": "Center Pavillion", "en-GB": "Centre Pavillion" }`

### 3-2. Archives — 납품 ZIP의 필수 파일

> Note: Feature types that require at least one (1) instance to qualify as a structurally valid delivery are listed as Required below.

| Filename | Presence |
| --- | --- |
| manifest.json | Required |
| address.geojson | Required |
| venue.geojson | Required |
| 나머지 13종 `.geojson`(amenity·anchor·building·detail·fixture·footprint·kiosk·level·occupant·opening·relationship·section·geofence·unit) | Optional |

### 3-3. null 값 칸을 생략해도 되는가

Reference·Feature 페이지에서 "null인 속성도 키를 반드시 적어야 한다"는 문장은 찾지 못했다. 스펙의 모든 예제는 값이 없는 칸을 `"alt_name": null`처럼 키를 남기고 `null`로 적는다. `확인 필요`
