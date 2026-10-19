---
summary: "IMDF Feature Type 중 하나로, 보행자 편의시설·서비스가 있다는 사실과 대략의 위치를 점(Point) 하나로 나타낸다. level_id가 없고 unit_ids로 Unit을 반드시 가리킨다(Violation). Unit·Fixture로 그릴 수 없거나 그 대표점이 마땅치 않을 때 쓴다"
source: "[[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]], [[src22. IMDF Amenity 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations·가이던스]], docs.ogc.org/cs/20-094/Amenity"
related:
  - "[[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]]"
  - "[[AMENITY-CATEGORY]]"
  - "[[correlation_id]]"
  - "[[UNIT-CATEGORY]]"
  - "[[Display Point]]"
  - "[[Feature Type]]"
  - "[[IMDF]]"
created: "2026-10-18 22:03"
updated: "2026-10-18 22:03"
core_keywords:
  - Amenity
---
# Amenity

## 요약

Amenity는 IMDF에서 **편의시설의 점 위치**를 나타내는 Feature다. 정의 원문은 "An Amenity models the physical presence and approximate point location of a pedestrian amenity that serves a utilitarian purpose or other convenience that serves to enhance the pedestrian "experience."" 이다. 화장실·엘리베이터·정수기·ATM·AED·안내데스크 등이 해당한다.

## 핵심 내용

- **도형:** Point만 허용(`AmenityMustHavePointGeometry`, Violation). 이미 점이므로 `display_point`가 없다.
- **필수 속성:** `category`([[AMENITY-CATEGORY]] 172개 중 하나), `unit_ids`(Unit id 배열). 전체 10개(category, accessibility, name, alt_name, hours, phone, website, unit_ids, address_id, correlation_id).
- **층 참조 방식:** `level_id`가 없다. `unit_ids`의 Unit이 가진 `level_id`로 층이 정해진다. 점은 그 Unit 안에 있어야 한다(Warning).
- **언제 쓰는가:** 실제 위치에 찍되(MUST), 실제 위치가 없는 서비스(Wi-Fi), Unit·Fixture로 그릴 수 없는 것(엘리베이터·수하물 컨베이어), Unit·Fixture 대표점이 표시에 마땅치 않을 때(SHOULD). 같은 종류가 모여 있으면 점 하나로 묶는 예가 반복된다.
- **층간 묶음:** 위아래로 포개진 같은 서비스는 [[correlation_id]]로 묶는다(조건부 MUST). `parking` 계열은 category 규칙에서 한 번 더 강조한다.
- **화장실:** 서로 다른 category의 화장실 Unit이 맞닿으면 가운데 추상 category(`restroom`) 점 하나가 권장이다.
- **담을 수 없는 Unit:** 엘리베이터·에스컬레이터·무빙워크·계단·화장실 Unit 안에는 같은 계열 Amenity만, `steps`·`opentobelow`·구조체 Unit 안에는 Amenity를 두지 않는다(Warning, "contained (or touched)" 판정).
- **다른 Feature와:** 수직 이동 Amenity가 있는 Level은 Opening이 없어도 된다. Kiosk 안에 Amenity를 둘 수 있다(MAY).
- **IMDFrnt (2026-10-18):** 스펙 10개 속성이 모두 있고, 비표준 `display_point`·`level_id`를 추가로 내보낸다. `unit_ids`는 사람이 일련번호로 입력한다.

## 관련 링크

- [[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]] — 태깅 규칙 전체와 예시
- [[AMENITY-CATEGORY]] — category 값 목록
- [[correlation_id]] — 층간 묶음 조건
- [[UNIT-CATEGORY]] — Amenity를 담을 수 없는 Unit category
- [[Display Point]] — Unit·Fixture 대표점과의 선택
- [[Feature Type]] — Amenity가 속한 분류
- [[IMDF]] — 규격

## 미해결 질문

- 비표준 `level_id`·`display_point`가 붙은 Amenity를 Apple 검증기가 어떻게 처리하는가.
- 정의 없는 category(`library`·`coinlocker` 등 37개)의 용법.
