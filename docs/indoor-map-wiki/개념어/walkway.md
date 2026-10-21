---
summary: "IMDF Unit의 category 값 중 하나. 보행자의 이동을 돕도록 설계된 통로를 나타낸다(MUST). 같은 층에서 맞닿은 walkway는 특성 차이·문이 없으면 병합하고(SHOULD), 출입 통제 문이 있으면 나눈다(SHOULD NOT 병합). 목적지와 통로를 겸하는 구역은 장벽 유무로 room과 walkway를 가른다"
source: "[[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]], [[src20. IMDF Unit 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations]], docs.ogc.org/cs/20-094/Unit"
related:
  - "[[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]]"
  - "[[UNIT-CATEGORY]]"
  - "[[IMDF]]"
  - "[[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]]"
  - "[[Section]]"
created: "2026-10-18 10:41"
updated: "2026-10-18 21:36"
core_keywords:
  - walkway
---
# walkway

## 요약

`walkway`는 IMDF Unit의 category 값으로, 복도·통로·홀처럼 **보행자가 지나다니도록 설계된 공간**을 나타낸다. WWDC19 발표는 "Everything on the level is a unit, including walkways which have their own category"라고 소개한다. 통로는 도면에서 여러 조각으로 나뉘어 그려지기 쉬워 병합·분할 규칙이 따로 있다. 하위 값으로 `walkway.island`가 있다.

## 핵심 내용

- **정의 규칙 (MUST):** "a "walkway" Unit MUST model a pathway whose design and intended purpose is to facilitate pedestrian movement through a Venue."
- **병합 (SHOULD):** 같은 Level에서 맞닿은 walkway는 (1) 물리적 특성 차이가 없거나, (2) 맞닿는 자리에 문·장벽이 없거나, (3) 문이 있지만 Opening으로 그려도 얻는 것이 없을 때 합친다. 단, 통로 전체를 Unit 하나로 만들면 보행자가 지도에서 자기 위치를 가늠하기 어려울 수 있으니 앱 경험을 고려하라는 주석이 있다.
- **분할 (SHOULD NOT 병합):** 출입이 통제되는 문이 있으면 합치지 않는다.
- **room과의 구분:**
  - 통로 옆에 서비스가 있어도 주 목적이 이동이면 `walkway` (SHOULD).
  - 목적지이자 통로인 구역이 물리적 장벽으로 나뉘고 기능 차이가 뚜렷하면 `room` (SHOULD).
  - 장벽 없이 이어지면 `walkway` (SHOULD).
  - 목적지도 통로도 추론할 수 없는 구역(전시장·컨벤션 센터처럼 용도가 수시로 바뀜)은 `walkway` (SHOULD).
- **ramp와의 구분:** 같은 층 경사로가 계단·미니 에스컬레이터·엘리베이터의 대안이 아니면 `ramp`가 아니라 `walkway` (MUST).
- **Section과의 관계 (2026-10-18 추가):** [[Section]]은 층을 덮지 않고 필요한 곳에만 얹으므로, Section 사이 빈틈으로 아래 walkway Unit이 드러난다. 스펙은 "gaps MAY exist among Sections to facilitate visibility of the underlying "walkway" Unit"이라고 이를 허용한다. SECTION-CATEGORY에도 `walkway` 값이 있지만 Glossary에 Section 정의가 없어 용법은 확인 필요다. 근거: [[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]] 3-4절.
- **IMDFrnt:** 길찾기 그래프의 같은 층 연결 종류도 `walkway`로 부른다(`Routing/RoutingGraph.swift:44`). 이것은 RoutingEdgeCategory이며 Unit category와는 별개 값이다.

## 관련 링크

- [[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]] — 4절 병합·분할 표
- [[UNIT-CATEGORY]] — 전체 category 목록
- [[IMDF]] — 규격
- [[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]] — Section 사이로 walkway가 드러나는 규칙

## 미해결 질문

- `walkway.island`의 정의 — Unit 페이지에는 Level Opening 예외 조항에만 등장하고 별도 규칙이 없다. 섬처럼 떨어진 보행 구역을 뜻하는지 확인 필요.
- 긴 복도를 어디서 나누는 것이 위치 파악에 유리한지에 대한 Apple의 정량 기준이 있는가.
