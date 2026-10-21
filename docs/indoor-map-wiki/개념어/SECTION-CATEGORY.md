---
summary: "IMDF Section 피처의 category 속성에 들어갈 수 있는 열거값 71개. unspecified가 없고, Unit과 달리 category별 MUST 규칙이 없어 Glossary 정의문(45개에만 있음)으로 고른다. 공항·교통 운영, 상업, 식사·좌석, 전시·오락, 업무·안내, 주차 계열로 나뉜다"
source: "[[src15. IMDF Section·Geofence properties 전수 대조와 카테고리 열거형 조사]] 3절, [[src21. IMDF Section 태깅 규칙 보충 원문 조사 — Glossary 카테고리 정의·그림 설명·Venue 가이던스]] 2절, docs.ogc.org/cs/20-094/Categories·Glossary"
related:
  - "[[Section]]"
  - "[[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]]"
  - "[[UNIT-CATEGORY]]"
  - "[[08) IMDF Feature Type·카테고리 전체 레퍼런스]]"
  - "[[IMDF]]"
created: "2026-10-18 21:36"
updated: "2026-10-18 21:36"
core_keywords:
  - SECTION-CATEGORY
---
# SECTION-CATEGORY

## 요약

SECTION-CATEGORY는 [[Section]]의 `category` 속성에 들어갈 수 있는 값 목록이다. 정확히 71개이고 모두 소문자이며, 점(`.`)으로 하위 값을 만든다(예: `parking` → `parking.ev`). `unspecified`(미지정)가 없으므로 맞는 값이 없는 구역은 Section으로 만들지 않는 것도 선택지다.

## 핵심 내용

- **성격별 묶음:**
  - 공항·교통 운영: `checkin`, `baggageclaim`(`.intl`), `gatearea`(`.holding`), `immigration`(`.schengen`), `security`, `presecurity`, `postsecurity`, `paidarea`, `platform`, `ticketing`, `recomposearea`
  - 상업: `retail`, `retaildepartment`, `dutyfree`, `concessions`, `rental`, `carrental`(`.dropoff`)
  - 식사·좌석: `eatingdrinking`, `seating`, `seatingrow`, `recreation`
  - 전시·오락: `exhibit`, `exhibition`, `entertainmentarea`와 하위 4개, `arcade`, `gambling`과 하위 21개
  - 업무·안내: `information`, `servicearea`, `cubicle`, `private`
  - 차량: `parking`과 하위 8개, `parkandride`, `road`
  - 기타: `vegetation`, `walkway`
- **정의문 문형:** 대부분 "models the presence and approximate thematic extent of an open or semi-enclosed environment ..."다. Unit category의 "physical extent"와 대비된다.
- **정의가 없는 값 26개:** `arcade`, `gambling` 계열 22개, `recreation`, `rental`, `walkway`. Glossary에 Section 정의가 없다.
- **category별 강제 규칙 없음:** [[UNIT-CATEGORY]]에는 elevator·stairs·walkway 등에 MUST 규칙이 있지만 SECTION-CATEGORY에는 없다.
- **상위 값 사용:** `entertainmentarea`·`information`·`parking`·`retail`·`security`·`servicearea`는 "계층 안 다른 값으로 분류할 수 없을 때" 쓴다고 정의에 적혀 있다.
- **Geofence와 겹치는 값:** `paidarea`·`platform`·`postsecurity`·`presecurity`.
- **가이던스:** 공항은 `checkin`·`baggageclaim`·`immigration`·`security` Section에 display_point를 MUST로 요구하고, 교통역은 `immigration`·`paidarea`·`security` Section 수집을 MUST로 요구한다. 쇼핑센터 가이던스에는 Section 요구가 없다.
- **IMDFrnt:** 71개 드롭다운이 스펙과 일치한다(`Model/PropertySchema.swift:306~`).

## 관련 링크

- [[Section]] — 이 값이 붙는 Feature Type
- [[17) Section 레이어 태깅 규칙 — Unit 위에 주제 구역을 어디까지 긋고 무엇을 붙이는가]] — 4절 category 고르기·도서관 적용 해석
- [[UNIT-CATEGORY]] — Unit의 category 목록(규칙 강도 비교)
- [[08) IMDF Feature Type·카테고리 전체 레퍼런스]] — 전체 열거형
- [[IMDF]] — 규격

## 미해결 질문

- Section `walkway`의 용법(정의 없음).
- 도서관 서가 구역에 맞는 값이 있는가. 현재 판단은 "맞는 값 없음"(해석).
