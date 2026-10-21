---
summary: "IMDF에서 서로 다른 층에 있는 같은 성격의 Feature들이 함께 갖는 임의의 UUID. 다른 Feature의 id를 가리키는 참조가 아니다. 지도 앱은 층 선택 전 이들을 하나로만 그린다. 짝이 최소 하나 있어야 하고(Violation) 짝끼리 다른 층이어야 하며(Violation) category가 같아야 한다(Warning)"
source: "[[src22. IMDF Amenity 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations·가이던스]] 1-5·3-1절, [[src15. IMDF Section·Geofence properties 전수 대조와 카테고리 열거형 조사]] 1.4·1.6절, docs.ogc.org/cs/20-094/Glossary#correlation-id"
related:
  - "[[Amenity]]"
  - "[[Section]]"
  - "[[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]]"
  - "[[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]]"
  - "[[IMDF]]"
created: "2026-10-18 22:03"
updated: "2026-10-18 22:03"
core_keywords:
  - correlation_id
---
# correlation_id

## 요약

`correlation_id`는 IMDF Feature의 속성으로, **여러 층에 걸쳐 있는 같은 서비스·구역**을 하나로 묶는 표시다. 값은 임의로 만든 UUID이고, 묶을 Feature들이 똑같은 값을 나눠 갖는다. 어떤 Feature의 `id`를 가리키는 참조가 아니라는 점이 `unit_ids`·`level_id` 같은 참조 속성과 다르다.

## 핵심 내용

- **보유 Feature:** Amenity, Section, Geofence, Occupant 등. Amenity·Section 페이지의 설명은 "shared among similar … that occupy different floors of the physical Venue"다.
- **지도 앱에서의 효과 (Glossary, Amenity·Occupant):** "render a single representation of the feature, instead of multiple representations" — 층을 고르기 전 하나로만 그린다. 예: 위아래 층의 같은 자리 엘리베이터 아이콘이 겹쳐 찍히지 않는다.
- **Amenity에서 반드시 넣는 조건(세 조건 모두):** 서로 다른 층의 Unit 안에 있고, 그 Unit들이 within·overlap·equal(바로 위아래)이며, 층 선택 전 하나만 보여야 할 때. 같은 층에 흩어진 같은 종류를 묶는 데는 쓰지 않는다(MUST NOT). `parking` 계열은 category 규칙에서 다시 강조.
- **Section에서:** 여러 Section을 연결하려는 의도가 있으면 반드시 둔다(MUST).
- **검증(공통):** 짝 없음 → `CorrelationIdMustBeMatched`(Violation), 짝이 같은 층 → `LevelIDsMustBeDissimilarForCorrelationID`(Violation), UUID v4 아님 → `InvalidCorrelationID`(Violation), category 다름 → `CategoryShouldBeSameForCorrelationID`(Warning). 혼자 가진 값은 그 자체로 위반이다.
- **스펙 예제 오류:** Glossary 예제의 `"33333333-3333-3333-3333-3333333333333"`은 마지막 묶음이 13자리라 UUID 형식이 아니다.
- **IMDFrnt (2026-10-18):** Amenity·Section 모두 입력할 수 없다(Amenity는 항상 null, Section은 속성 자체가 없음).

## 관련 링크

- [[Amenity]] — 층간 편의시설 묶음
- [[Section]] — 층간 구역 묶음
- [[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]] — 4-2절 조건과 예
- [[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]] — 5절 Section의 용법
- [[IMDF]] — 규격

## 미해결 질문

- `level_id`가 없는 Amenity에서 "짝끼리 다른 층" 검사가 층을 어떻게 판정하는가(unit_ids의 Unit 경유로 추정).
- Apple 지도 앱이 묶인 Feature 중 어느 층의 것을 대표로 그리는가.
