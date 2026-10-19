---
summary: "IMDF Feature Type 중 하나로, 하나 이상의 Building의 대략적 물리 범위를 나타내는 Polygon. ground·aerial·subterranean 세 category가 있고, 각각 ordinal 0 / 0 이상 / −1 이하 실내 Level들의 합집합과 같아야 한다(검증 Warning)"
source: "[[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]], [[src20. IMDF Unit 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations]] 5-1절, docs.ogc.org/cs/20-094/Footprint"
related:
  - "[[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]]"
  - "[[Level]]"
  - "[[대칭차]]"
  - "[[Feature Type]]"
  - "[[IMDF]]"
created: "2026-10-18 11:30"
updated: "2026-10-18 11:30"
core_keywords:
  - Footprint
---
# Footprint

## 요약

Footprint는 IMDF에서 **건물의 외곽 범위**를 나타내는 Feature다(원문: "the approximate physical extent of one or more referenced Buildings"). Level이 층 하나의 바닥이라면, Footprint는 여러 층을 묶은 건물 단위 외곽이다. Unit이 직접 덮어야 하는 기준은 Footprint가 아니라 [[Level]]이며, Footprint는 Level들을 합친 결과와 비교된다.

## 핵심 내용

- **category 세 가지:**

| category | 원문 정의 요지 | 같아야 하는 Level 묶음 (Validations, Warning) |
| --- | --- | --- |
| `ground` | 지상 높이에서 건물의 물리적 범위(MUST). 경사 지형이면 지면에 노출된 모든 층 부분의 합 | ordinal 0인 실내 Level 합집합 |
| `aerial` | 머리 위 무한히 먼 광원이 아래로 드리운 건물 그림자(MUST) | ordinal 0 이상 실내 Level 합집합 |
| `subterranean` | 지하 모든 층 범위의 최대치(MUST) | ordinal −1 이하 Level 합집합 |

- **Level과 완전히 일치해도 되는가:** 된다. ordinal 0 Level이 하나뿐인 건물은 그 Level과 `ground` Footprint가 같은 도형인 것이 검증 기준이다. 외벽이 수직으로 곧은 건물이면 모든 지상층 Level이 `aerial`과도 같다.
- **일치하지 않는 것이 정상인 경우:** 위층 셋백·돌출(위층 Level 하나가 `aerial`보다 작음), 같은 ordinal에 Level 여럿(합집합으로 비교), 경사 지형, 실외 Level(검증 대상 아님), 공유 건물에서 구조상 떼어낼 수 없는 공간을 Footprint에 포함한 경우(SHOULD).
- **항공·위성 사진으로 만들 때:** 건물이 가려지거나 기복 변위(radial displacement)로 형태가 왜곡되면 `aerial`·`ground` Footprint를 만들지 않을 것을 권장한다(SHOULD NOT).
- **IMDFrnt:** IMDF Footprint는 도면 폴리곤을 태깅해 만드는 type이다(`Model/IMDFFeatureType.swift:23`). `UI/Anchor/BuildingFootprints.swift`의 "BuildingFootprint"는 OpenStreetMap 건물 외곽을 지도 정합 후보로 가져오는 별개 자료다.

## 관련 링크

- [[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]] — 2-2절 Level·Footprint·외벽 관계
- [[Level]] — Footprint와 비교되는 층 도형
- [[대칭차]] — 도형 일치 판정의 정의
- [[Feature Type]] — Footprint가 속한 분류
- [[IMDF]] — 규격

## 미해결 질문

- 공유 건물에서 Footprint가 Level 합집합보다 커질 때(SHOULD 포함 규정) Level 불일치 Warning을 어떻게 처리하는가.
- Footprint Illustrative Guidance 그림 미확인.
