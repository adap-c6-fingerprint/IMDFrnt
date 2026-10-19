---
summary: "IMDF Feature Type 중 하나로, 건물의 한 층(또는 시설과 떼어낼 수 없는 실외 구역)의 바닥 범위를 나타내는 Polygon. 외곽은 그 층 높이의 외벽면을 따르고(SHOULD), 같은 층 Unit들의 합집합과 정확히 같아야 한다(MUST)"
source: "[[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]], [[src20. IMDF Unit 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations]] 5-1절, docs.ogc.org/cs/20-094/Level"
related:
  - "[[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]]"
  - "[[Footprint]]"
  - "[[대칭차]]"
  - "[[Feature Type]]"
  - "[[IMDF]]"
  - "[[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]]"
  - "[[Section]]"
  - "[[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]]"
created: "2026-10-18 11:30"
updated: "2026-10-19 14:45"
core_keywords:
  - Level
---
# Level

## 요약

Level은 IMDF에서 **층 하나의 바닥 범위**를 나타내는 Feature다. geometry는 POLYGONAL(Polygon 또는 MultiPolygon)이고, `ordinal`(층 번호, 지상 출입층 = 0, 바로 아래 지하층 = −1)로 위아래 순서를 정한다. Unit은 모두 `level_id`로 하나의 Level을 가리키며, 한 Level에 속한 Unit들은 그 Level 도형을 빈틈·겹침 없이 채워야 한다.

## 핵심 내용

- **외곽 기준 (SHOULD):** "analogous to the surface (facade) of the physical building at the height where the modeled floor is positioned" — 그 층 높이에서 자른 건물 외벽면을 따른다. 층마다 외곽이 다를 수 있다. Unit Illustrative Guidance의 벽 단순화 그림(`UnitBoundaries.png`)에서 Level 외곽은 **외벽 바깥면**에 그어져 있다(2026-10-18 확인, 그림 판독).
- **Unit과의 관계 (MUST):** Unit 합집합과 Level 사이에 [[대칭차]]가 없어야 한다. 외벽 두께가 Level 안에 들어가면 그 자리도 어떤 Unit이든 덮어야 한다(안쪽 Unit에 포함하거나 `structure` Unit으로 따로 그림).
- **Level끼리의 관계:** 같은 Building·같은 ordinal Level은 겹치면 안 된다(MUST NOT). 외벽면이 같은 층들은 도형이 같아야 하며(MUST), 불가능하면 단면 방향 0.2m까지 차이를 허용한다(1:500 축척 식별 기준).
- **Footprint와의 관계:** ordinal 0 실내 Level 합집합 = `ground` Footprint, ordinal 0 이상 합집합 = `aerial`, −1 이하 합집합 = `subterranean`(Validations, Warning). 1층 Level과 `ground` Footprint가 완전히 같은 것은 정상이다. 자세한 예외는 [[Footprint]].
- **Section과의 관계 (2026-10-18 추가):** [[Section]]은 `level_id`로 Level 하나를 가리키고 그 Level 도형 안에 있어야 한다(`SectionMustBeCoveredByReferencedLevel`, Violation). Unit과 달리 Section은 Level을 덮을 의무가 없다. 스펙 그림에는 `parking` Level과 똑같은 도형의 `parking` Section 예가 있다. 근거: [[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]] 3-6절.
- **주요 속성:** `category`(LEVEL-CATEGORY), `ordinal`, `outdoor`(실내 false·실외 true, MUST), `name`·`short_name`(LABELS), `building_ids`, `address_id`, `display_point`, `restriction`.
- **이름 두 개가 모두 필수다(2026-10-19 확인):** `name`과 `short_name`의 Type은 `null or` 없는 `LABELS`이고, `LevelMustHaveName`·`LevelMustHaveShortName`이 모두 Violation이다. category도 필수다(`LevelMustHaveCategory`, Violation). `alt_name` 칸은 없다. 같은 건물의 층끼리 name·short_name이 겹치면 Warning이다. 정리는 [[19) name·category 필수 입력 여부 — Feature Type 16종 한눈에 보기]].
- **Opening:** Level은 최소 하나의 Opening이 참조해야 한다(MUST). 예외는 Level 전체가 `nonpublic`·`walkway.island` Unit 하나와 같을 때, 수직 이동 Amenity(`elevator`·`stairs` 등, [[Amenity]])가 Level 안에 있을 때다([[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]]).

## 관련 링크

- [[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]] — 2-2절 Level·Footprint·외벽 관계
- [[Footprint]] — Level 합집합과 비교되는 건물 외곽
- [[대칭차]] — Unit 합집합 = Level 규칙의 정의
- [[Feature Type]] — Level이 속한 분류
- [[IMDF]] — 규격
- [[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]] — Level 안에 얹히는 Section 규칙
- [[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]] — Level을 직접 가리키지 않는 Amenity, 수직 이동 Amenity의 Opening 예외

## 미해결 질문

- ~~Level 외곽을 외벽 바깥면과 안쪽 면 중 어디에 두는가~~ — 2026-10-18 해소: 바깥면(Unit Illustrative Guidance 그림, [[src20. IMDF Unit 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations]] 5-2절).
- Level 페이지의 ordinal·transit·경사 지형 규칙은 이번에 요지만 확인했다. 별도 정리 필요.
