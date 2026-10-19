---
summary: "IMDF에서 텍스트 이름(라벨)을 나타내는 데이터 타입. 언어 태그를 key로, 문자열을 value로 갖는 JSON 객체"
source: "[[라벨에 관하여]], IMDF 1.0.0 공식 스펙(OGC docs.ogc.org/cs/20-094/Reference)"
related:
  - "[[IMDF]]"
  - "[[Display Point]]"
created: "2026-08-12 00:00"
updated: "2026-10-19 14:45"
core_keywords:
  - LABELS
---
# LABELS

## 요약

LABELS는 IMDF(Indoor Mapping Data Format) 1.0.0 스펙의 Reference에 정의된 데이터 타입으로, 하나의 개체(entity)에 대한 어휘적 라벨(이름)을 하나 이상의 언어로 담는 JSON 객체다. IMDF에는 "Label"이라는 이름의 독립 Feature Type이 없고, 대신 Unit·Kiosk·Amenity·Section·Opening·Occupant 등 여러 Feature Type의 `properties` 안에 있는 `name`/`alt_name` 속성이 이 LABELS 타입을 쓴다.

## 핵심 내용

- 정의 원문(Reference): "Labels are JSON objects used to capture a single lexical label for an entity in one or more explicitly stated languages."
- 규칙: Labels **MUST** use a valid `LANGUAGE-TAG` as their members / **MUST NOT** contain duplicate `LANGUAGE-TAG` members / **MUST** contain a `STRING` value for each member / **MUST** contain an entry in the default language.
- 예시: `{"en": "red", "es": "rojo", "fi": "punainen", "fr": "rouge", "it": "rosso", "jp": "赤"}`, 또는 세밀한 언어 태그 예시 `{"en-US": "Center Pavillion", "en-GB": "Centre Pavillion"}`.
- name/alt_name(LABELS) 속성을 가진 것으로 확인된 Feature Type: Unit, Kiosk, Amenity, Section, Opening, Occupant. (Anchor, Detail은 확인 결과 없음. Fixture·Geofence·Address·Building·Footprint·Level·Venue·Relationship은 미조사.)
- **2026-10-19 전수 확인:** LABELS 칸을 가진 Feature는 13종이다. `name`은 Venue·Building·Footprint·Level·Unit·Section·Opening·Geofence·Amenity·Fixture·Kiosk·Occupant 12종에 있고, Level은 `short_name`(LABELS)을 하나 더 갖는다. Relationship·Anchor·Detail·Address에는 LABELS 칸이 없다. `alt_name`은 Level·Footprint·Occupant에 없다.
- **필수 여부:** 표의 Type이 `LABELS`만이면 필수, `null or LABELS`면 선택이다. 필수는 Venue·Level(name·short_name)·Occupant뿐이다(각 `MustHaveName` Violation). Building은 선택이지만 비우면 `BuildingHasNoName` Warning이다. 전체 표는 [[19) name·category 필수 입력 여부 — Feature Type 16종 한눈에 보기]].
- **검사 규칙:** 빈 글자 금지(`LabelMustNotBeBlank`, Violation), `alt_name`만 단독으로 두지 않기(`HasOnlyAltName`, Warning), `alt_name`의 언어 코드는 `name`에도 두기(`AltNameLangTagHasNoCorrespondingNameLangTag`, Warning). 근거는 [[src23. IMDF name·category 필수 여부 원문 조사 — 16종 Property Keys·Validations·Archives]].
- LABELS 값은 Feature의 `geometry` 멤버가 아니라 `properties` 멤버 안에 저장된다. 즉 라벨 텍스트와 좌표(도형)는 같은 Feature 객체 안에서 서로 다른 멤버에 나뉘어 저장된다.

## 관련 링크

- [[IMDF]] — LABELS가 속한 상위 스펙
- [[Display Point]] — 같은 Feature의 `properties` 안에 나란히 존재하며, 라벨을 그릴 좌표를 지정하는 속성
- [[19) name·category 필수 입력 여부 — Feature Type 16종 한눈에 보기]] — Feature별 name 필수 여부와 형식 규칙

## 미해결 질문

- ~~Fixture, Geofence, Address, Building, Footprint, Level, Venue, Relationship에도 name/alt_name(LABELS) 속성이 있는지 미확인.~~ — 2026-10-19 해소: 위 핵심 내용의 전수 확인 항목.
- Address에는 LABELS 칸이 없는데 Validations의 `LabelMustNotBeBlank`가 Address에도 실려 있는 이유.
