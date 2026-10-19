# IMDF 공식 스펙 — 라벨(Label)·Name·Display Point 필드 조사

## 수집 기준

- 수집일: 2026-08-12
- 목적: `A-06) Indoor Map/A-06-01) Indoor Map Overall/라벨에 관하여.md`의 질문(GQ1~GQ3)에 답하기 위해, WWDC19 전사문에 한 문장으로만 등장하는 "label"(line 65: "there are labels which are applied to the units, such as the name of a business that occupies a room.")의 실제 데이터 모델을 IMDF 공식 스펙에서 확인.
- 범위: `register.apple.com/resources/imdf/`는 SPA(자바스크립트 렌더링) 구조라 WebFetch로 본문 텍스트 추출이 되지 않음(메인 페이지에서 확인). 대신 동일 스펙의 OGC Community Standard 문서(`docs.ogc.org/cs/20-094`, IMDF 1.0.0)를 직접 조회. src01에서 이미 register.apple.com이 원본, OGC 문서가 표준화 버전임을 확인한 바 있음.

## 핵심 출처

- OGC IMDF 1.0.0 목차: https://docs.ogc.org/cs/20-094/index.html
- Reference(데이터 타입 정의): https://docs.ogc.org/cs/20-094/Reference/index.html
- Glossary: https://docs.ogc.org/cs/20-094/Glossary/index.html
- Unit: https://docs.ogc.org/cs/20-094/Unit/index.html
- Opening: https://docs.ogc.org/cs/20-094/Opening/index.html
- Kiosk: https://docs.ogc.org/cs/20-094/Kiosk/index.html
- Amenity: https://docs.ogc.org/cs/20-094/Amenity/index.html
- Section: https://docs.ogc.org/cs/20-094/Section/index.html
- Occupant: https://docs.ogc.org/cs/20-094/Occupant/index.html
- Anchor: https://docs.ogc.org/cs/20-094/Anchor/index.html
- Detail: https://docs.ogc.org/cs/20-094/Detail/index.html

## 1. IMDF Feature Type 전체 목록 (16개, 목차 기준)

Address, Amenity, Anchor, Building, Detail, Fixture, Footprint, Geofence, Kiosk, Level, Occupant, Opening, Relationship, Section, Unit, Venue.

→ 이 목록에 "Label"이라는 이름의 독립 Feature Type은 존재하지 않는다.

## 2. LABELS 데이터 타입 (Reference)

원문: "Labels are JSON objects used to capture a single lexical label for an entity in one or more explicitly stated languages."

- Labels **MUST** use a valid `LANGUAGE-TAG` as their members
- Labels **MUST NOT** contain duplicate `LANGUAGE-TAG` members
- Labels **MUST** contain a `STRING` value for each member
- Labels **MUST** contain an entry in the default language

예시:
```json
{"en": "red", "es": "rojo", "fi": "punainen", "fr": "rouge", "it": "rosso", "jp": "赤"}
{"en-US": "Center Pavillion", "en-GB": "Centre Pavillion"}
```

→ LABELS는 좌표·geometry 타입이 아니라, 언어 태그를 key로 하는 문자열 딕셔너리(JSON 객체) 타입이다.

## 3. DISPLAY-POINT 데이터 타입 (Reference)

원문: "A Display Point represents a curated, Point-based representation of a non-puntal Feature."

- Display Points are members of a Feature's `"property"` object
- Display Points **MUST** be captured as GeoJSON Point objects
- Display Points **MUST** be within the geometry of the Feature
- Display Points **SHOULD** be positioned in a location where map label "collision" is least expected

## 4. name/alt_name(LABELS) 및 display_point 속성 보유 여부 (Feature별 properties 테이블 기준)

| Feature Type | geometry 타입 | name/alt_name (LABELS) | display_point |
| --- | --- | --- | --- |
| Unit | Polygon | 있음 | 있음 |
| Kiosk | Polygon | 있음 | 있음 |
| Amenity | Point | 있음 | 명시 없음 |
| Section | Polygon | 있음 | 있음 |
| Opening | LineString | 있음 | 있음 |
| Occupant | null (geometry 없음) | 있음 (LABELS, null 아님·필수) | 해당 없음 |
| Anchor | Point | 명시 없음 | 해당 없음 |
| Detail | LineString | 명시 없음 (properties는 `level_id`뿐) | 해당 없음 |

Fixture, Geofence, Address, Building, Footprint, Level, Venue, Relationship의 name/LABELS 보유 여부는 이번 조사에서 확인하지 않음(미조사).

## 5. GeoJSON Feature 구조 안에서 라벨의 위치

- name/alt_name(LABELS)과 display_point는 모두 해당 Feature 객체의 `"properties"` 멤버 안에 있는 형제(sibling) 속성이다. (DISPLAY-POINT 정의 원문: "Display Points are members of a Feature's property object")
- 즉 IMDF GeoJSON Feature는 `{"type": "Feature", "geometry": {...}, "properties": {"name": {...LABELS...}, "display_point": {...Point...}, ...}}` 형태이며, 라벨(name)과 도형(geometry)은 같은 Feature 객체 안에서 `properties`와 `geometry`라는 서로 다른 멤버에 나뉘어 저장된다.
- 라벨만 따로 담는 별도의 배열이나 파일은 조사 범위(Reference, Unit/Kiosk/Amenity/Section/Opening/Occupant 정의) 안에서 확인되지 않았다.

## 6. Unit 정의 원문 중 "wall" 언급

Unit Definition 원문: "A Unit models the presence, location and approximate extent of a space. Extent may be characterized by: A barrier, such as a wall; A physical boundary, not necessarily delimitted by a barrier, but beyond which traversal is not expected, such as the edge of a train platform; A legal instrument, such as the description of a gross leasable area"

Unit Geometry Capturing Rule 원문: "Symmetrical difference MUST NOT exist: Among Units that reference the same Level; Between the union of Units and their referenced Level"

## 7. Opening 정의 원문 및 Unit 경계와의 관계

Opening Definition 원문: "With few exceptions, an Opening models the presence, location and physical extent (width) of an entrance."

Opening Geometry Capturing Rule 원문: "the Opening MUST cover a single Unit boundary where the modeled entrance should exist"

## 8. Glossary 중 "wall" 언급

- Room 정의: "distinguishable space within a structure. Usually, a room is separated from other spaces or passageways by interior walls; moreover, it is separated from outdoor areas by an exterior wall"
- Neighboring 정의: "In physical terms, 'neighboring' is analogous to spaces separated by a wall or barrier."
- 위 두 곳(Unit 정의, Glossary) 외에 "wall"이라는 단어가 등장하는 곳은 확인되지 않았고, "Wall"이라는 이름의 독립 Feature Type이나 데이터 타입도 목차·Reference 어디에도 없다.

## 9. "Feature Type" 용어와 `feature_type` 필드 (Reference — FEATURE-REFERENCE 정의)

FEATURE-REFERENCE 원문: "Feature references are JSON objects comprised of the target feature's `"id"` and `"feature_type"` values."

- Feature references MUST contain an `"id"` member with a `FEATURE-ID` value
- Feature references MUST contain a `"feature_type"` member with a `FEATURE-TYPE` value
- `feature_type` 필드 값 규정 원문: "The value of a Feature's `"feature_type"` member MUST be one of the following case-sensitive values:" — 그 값의 전체 목록은 1번 항목의 16개(address, amenity, anchor, building, detail, fixture, footprint, geofence, kiosk, level, occupant, opening, relationship, section, unit, venue, 소문자)와 일치.
- "A Feature Type is..." 같이 "Feature Type"이라는 용어 자체를 직접 정의하는 문장은 Reference 페이지에 없음(확인 필요). 다만 위 규정을 통해 "각 Feature 객체가 자신의 최상위 `feature_type` 필드에 담는, 자신이 속한 분류를 나타내는 문자열 값"이라는 역할은 명확히 확인됨.

## 10. Unit Feature 공식 예시(Example) 원문

Unit 페이지(https://docs.ogc.org/cs/20-094/Unit/index.html)에 실린 JSON 예시 그대로:

```json
{
  "id": "11111111-1111-1111-1111-111111111111",
  "type": "Feature",
  "feature_type": "unit",
  "geometry": {
    "type": "Polygon",
    "coordinates": [
      [
        [100.0, 0.0],
        [101.0, 0.0],
        [101.0, 1.0],
        [100.0, 1.0],
        [100.0, 0.0]
      ]
    ]
  },
  "properties": {
    "category": "room",
    "restriction": null,
    "accessibility": null,
    "name": {
      "en": "Ball Room"
    },
    "alt_name": null,
    "display_point": {
      "type": "Point",
      "coordinates": [100.0, 1.0]
    },
    "level_id": "22222223-2222-2222-2222-222222222222"
  }
}
```

이 예시로 name(LABELS)과 display_point(DISPLAY-POINT)가 `properties` 객체의 형제 멤버로 실제 나란히 들어있고, 도형 좌표는 별도의 `geometry` 객체 안에 있다는 5번 항목의 서술이 실제 JSON 구조로 확인된다.

## 11. category 속성 보유 여부 (Feature별 properties 테이블 기준, 라벨에 관하여.md GQ3 수정판 근거)

| Feature Type | geometry 타입 | category 속성 |
| --- | --- | --- |
| Unit | Polygon | 있음 (UNIT-CATEGORY) |
| Amenity | Point | 있음 (AMENITY-CATEGORY) |
| Section | Polygon | 있음 (SECTION-CATEGORY) |
| Opening | LineString | 있음 (OPENING-CATEGORY) |
| Occupant | null | 있음 (OCCUPANT-CATEGORY) |
| Fixture | Polygon | 있음 (FIXTURE-CATEGORY) — "The category that best describes the function of the physical Fixture" |
| Geofence | Polygon | 있음 (GEOFENCE-CATEGORY, 필수 속성) |
| Kiosk | Polygon | 명시 없음 (properties: name, alt_name, anchor_id, level_id, display_point만 확인됨) |
| Anchor | Point | 명시 없음 |
| Detail | LineString | 명시 없음 (properties는 level_id뿐) |

Fixture Definition 원문: "A Fixture models the presence and approximate physical extent of a moveable or semi-permanent physical asset"(구조적 비하중, 유틸리티 지지, 장식 등의 기능을 가진 것). Fixture는 Polygon geometry이며 `level_id`(필수)로 Level에 연결되고, `unit_id` 참조는 properties 목록에 없음(즉 특정 Unit에 소속되는 필드가 아니라 Level 위 어딘가에 독립적으로 위치하는 Polygon으로 존재). name/alt_name(LABELS)과 category(FIXTURE-CATEGORY)를 모두 가진다.

Building, Footprint, Level, Venue, Address, Relationship의 category 보유 여부는 이번 조사에서 확인하지 않음(미조사).

## 미해결 질문

- register.apple.com/resources/imdf/(원본, SPA)와 docs.ogc.org/cs/20-094(OGC Community Standard화 버전)의 세부 문구가 100% 동일한지는 대조 확인하지 못함. src01 기준 두 사이트가 같은 스펙을 가리키는 것은 확인되었으나 자구 차이 가능성은 남아 있음.
- Fixture, Geofence, Address, Building, Footprint, Level, Venue, Relationship의 name/LABELS 속성 보유 여부.
- "Unit 경계(boundary) = 벽(wall)"이라고 스펙이 명시적으로 등치시키는 문장은 발견하지 못함. Unit 정의는 "extent가 barrier·wall로 특징지어질 수 있다"고만 서술한다.
