---
summary: "IMDF Feature Type 중 하나로, 한 층 안에서 운영상 하나의 주제로 묶이는 구역의 대략적 범위를 나타내는 POLYGONAL Feature. Unit 위에 얹히며 층을 덮을 의무가 없다. category와 level_id가 필수이고, 참조한 Level 안에 있어야 한다(Violation)"
source: "[[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]], [[src15. IMDF Section·Geofence properties 전수 대조와 카테고리 열거형 조사]], [[src21. IMDF Section 태깅 규칙 보충 원문 조사 — Glossary 카테고리 정의·그림 설명·Venue 가이던스]], docs.ogc.org/cs/20-094/Section"
related:
  - "[[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]]"
  - "[[SECTION-CATEGORY]]"
  - "[[Level]]"
  - "[[walkway]]"
  - "[[Display Point]]"
  - "[[Feature Type]]"
  - "[[IMDF]]"
  - "[[correlation_id]]"
created: "2026-10-18 21:36"
updated: "2026-10-18 22:03"
core_keywords:
  - Section
---
# Section

## 요약

Section은 IMDF에서 **한 층 안의 주제 구역**을 나타내는 Feature다. 정의 원문은 "A Section models the presence and approximate extent of a theme. The boundary of a theme may be a threshold or an indeterminate border."이다. 공항의 체크인 구역, 쇼핑몰의 푸드코트처럼 같은 목적으로 운영되는 범위를 대략 그린다. 경계는 벽이 아니라 바닥의 문턱이나 정해지지 않은 테두리여도 된다.

## 핵심 내용

- **Unit과의 관계:** Unit이 층 바닥을 빈틈없이 나누고(합집합 = Level, MUST), Section은 그 위 필요한 곳에만 얹는다. Section이 덮지 않은 곳에서는 아래 Unit(대개 [[walkway]])이 지도에 드러난다. Section은 Unit을 대신하지 않는다.
- **geometry:** POLYGONAL(Polygon 또는 MultiPolygon). 구멍은 Info로 지적된다.
- **필수 속성:** `category`([[SECTION-CATEGORY]] 71개 중 하나), `level_id`(층 하나). 전체 속성은 10개(category, restriction, accessibility, name, alt_name, display_point, level_id, address_id, correlation_id, parents).
- **범위 규칙:** 안에 든 Unit·Fixture보다 운영 주제를 먼저 본다(SHOULD), 보행자 인식을 고려한다(MUST), 일부만 벽으로 둘러싸여도 된다(SHOULD), Section 사이 빈틈 허용(MAY), Opening으로 입구를 나타내지 않는다(SHOULD NOT).
- **검증:** 참조한 Level 밖으로 나가면 Violation(`SectionMustBeCoveredByReferencedLevel`). 같은 층 Section끼리 겹침은 Info(`SectionsOverlap`).
- **층간 묶음과 계층:** [[correlation_id]]는 다른 층의 같은 성격 Section과 같은 UUID를 나눠 갖는다(짝 필수, 같은 층 금지). `parents`는 부모 Section id만 담는 배열로, 순환·자기 참조 금지.
- **Geofence와의 차이:** Geofence는 `level_ids`·`building_ids`로 여러 층·건물에 걸칠 수 있다. Section은 층 하나다. `paidarea`·`platform`·`presecurity`·`postsecurity`는 양쪽에 있다.
- **IMDFrnt (2026-10-18):** 스키마는 7개 속성만 있고(`address_id`·`correlation_id`·`parents` 없음), geometry는 Polygon 고정, Opening 빌려주기 대상에 Section이 포함되어 있다.

## 관련 링크

- [[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]] — 태깅 규칙 전체와 예시
- [[SECTION-CATEGORY]] — category 값 목록
- [[Level]] — Section이 들어 있어야 하는 층 도형
- [[walkway]] — Section 사이로 드러나는 통로 Unit
- [[Display Point]] — 이름표 대표점
- [[Feature Type]] — Section이 속한 분류
- [[IMDF]] — 규격

## 미해결 질문

- Apple 지도 앱이 Section을 화면에 어떻게 표시하는가(색·이름표·탭 동작).
- 같은 정책 구역을 Section과 Geofence 중 무엇으로 그리는지에 대한 기준.
