---
summary: "IMDF Unit·Level·Section 등의 restriction 속성에 넣는 열거값. employeesonly(비개방 구역을 일부러 지도에 그릴 때)와 restricted(방문자 중 허가된 일부만 출입할 때) 2종이며, 제한이 없으면 null이다. nonpublic Unit에는 쓰지 않는다"
source: "[[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]], [[src19. IMDF 비개방 구역(nonpublic) 모델링 규칙 조사]], [[src11. IMDF 공식 스펙 — Feature Type 16종·카테고리 열거형 전수 조사]], docs.ogc.org/cs/20-094/Unit"
related:
  - "[[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]]"
  - "[[nonpublic]]"
  - "[[UNIT-CATEGORY]]"
  - "[[08) IMDF Feature Type·카테고리 전체 레퍼런스]]"
created: "2026-10-17 17:30"
updated: "2026-10-17 17:30"
core_keywords:
  - RESTRICTION-CATEGORY
---
# RESTRICTION-CATEGORY

## 요약

RESTRICTION-CATEGORY는 IMDF 요소의 `restriction`(출입 제한) 칸에 넣을 수 있는 열거값이다. 값은 `employeesonly`와 `restricted` 두 개뿐이고, 제한이 없으면 칸을 `null`로 둔다. Unit의 경우 원문 정의는 "The category that best describes a restriction that applies to the entire physical Unit", 즉 그 Unit **전체**에 걸리는 제한이다.

## 핵심 내용

- **`restricted` (SHOULD):** "entry to an area is restricted to an authorized sub-set of the general public". 방문자 중 허가받은 일부만 들어갈 수 있는 곳에 쓴다. 예: 공항 라운지, 회원 전용 시설.
- **`employeesonly` (SHOULD):** "when a Venue Organization deliberately wishes to map a non-public area". 운영 기관이 비개방 구역을 **일부러 자세히** 지도에 넣고 싶을 때 쓴다. 이때 Unit의 카테고리는 실제 용도(`office` 등)로 둔다.
- **`employeesonly`를 쓰지 않는 경우 (SHOULD NOT):** 평소 운영상 일반 대중이 방문하지 않고 예측 가능한 일부만 방문하는 시설.
- **`nonpublic` Unit과 함께 쓰지 않는다 (SHOULD NOT):** "A "nonpublic" Unit SHOULD NOT possess a restriction". 비개방 구역을 자세히 그리지 않을 때는 `restriction` 대신 `category: "nonpublic"`을 쓴다. 이 구분이 이 열거형을 이해할 때 가장 중요하다.
- **적용 대상:** Unit·Level에 `restriction` 속성이 있고([[src19. IMDF 비개방 구역(nonpublic) 모델링 규칙 조사]]), Section에도 같은 타입의 속성이 있다([[src15. IMDF Section·Geofence properties 전수 대조와 카테고리 열거형 조사]]).
- **IM-DFrnt 현황:** 앱의 `restriction` 필드는 항상 null(`.alwaysNull`)이라 두 값을 입력할 수 없다. `nonpublic` Unit에는 영향이 없다.

## 관련 링크

- [[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]] — `nonpublic`과의 비교표
- [[nonpublic]] — 비개방 구역을 자세히 그리지 않을 때의 카테고리 값
- [[UNIT-CATEGORY]] — Unit `category`에 들어가는 열거형
- [[08) IMDF Feature Type·카테고리 전체 레퍼런스]] — 열거형 전량

## 미해결 질문

- Level 전체에 `restriction`을 거는 경우(예: 층 전체가 `restricted`)의 규칙은 Level 페이지에 따로 있는가. 이번 조사에서는 Level 페이지의 restriction 관련 서술을 property 정의 외에 찾지 못했다.
