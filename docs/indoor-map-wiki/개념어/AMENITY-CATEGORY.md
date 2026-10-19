---
summary: "IMDF Amenity 피처의 category 속성에 들어갈 수 있는 열거값 172개. unspecified가 있고(이름 필수, Warning), 135개에 Glossary 정의가 있다. parking·restroom 계열에만 category별 규칙이 있으며, 세 Venue 가이던스가 화장실·엘리베이터·계단·정수기·AED·안내 등을 필수 수집으로 지정한다"
source: "[[src22. IMDF Amenity 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations·가이던스]] 2·3·7절, docs.ogc.org/cs/20-094/Categories·Glossary"
related:
  - "[[Amenity]]"
  - "[[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]]"
  - "[[UNIT-CATEGORY]]"
  - "[[SECTION-CATEGORY]]"
  - "[[08) IMDF Feature Type·카테고리 전체 레퍼런스]]"
  - "[[IMDF]]"
created: "2026-10-18 22:03"
updated: "2026-10-18 22:03"
core_keywords:
  - AMENITY-CATEGORY
---
# AMENITY-CATEGORY

## 요약

AMENITY-CATEGORY는 [[Amenity]]의 `category` 속성에 들어갈 수 있는 값 목록이다. 정확히 **172개**이고(이전 위키 기록의 "약 160"은 부정확), 모두 소문자이며 점(`.`)으로 하위 값을 만든다. SECTION-CATEGORY와 달리 **`unspecified`가 있다.**

## 핵심 내용

- **성격별 묶음(주요 값):**
  - 수직 이동: `elevator`, `escalator`, `movingwalkway`, `stairs`, `ramp`, `peoplemover`
  - 화장실·위생: `restroom`과 하위 10개, `babychanging`, `mothersroom`, `shower`, `handsanitizerstation`
  - 안내·서비스: `information`과 하위 7개, `reception.desk`, `guestservices`, `lostandfound`, `service`, `studentservices`, `studentadmissions`
  - 기기: `atm`, `copymachine`, `vendingmachine`, `powerchargingstation`, `changemachine`, `phone`, `payphone`, `photobooth`, `wifi`
  - 안전·의료: `defibrillator`, `fireextinguisher`, `firealarmpullstation`, `firstaid`, `emergencyshelter`, `police`, `healthscreening`
  - 교통·주차: `parking`과 하위 7개, `taxi`, `rideshare`, `shuttle`, `bus` 계열, `rail` 계열, `ticketing`과 하위 8개, `faregate`
  - 공항: `boardinggate` 계열, `checkin` 계열, `baggagecarousel` 계열, `immigration`, `security` 계열
  - 기타: `entry`, `landmark`, `meetingpoint`, `seating`, `seat`, `storage`, `coinlocker`, `library`, `prayerroom`과 하위 10개, `fieldofplay`와 하위 11개, `unspecified`
- **정의문 문형:** "models the presence and approximate point location of ..." — Unit("physical extent"), Section("approximate thematic extent")과 구분된다.
- **정의 없는 값 37개:** `library`, `coinlocker`, `mailbox`, `checkin`, `fieldofplay`·`prayerroom` 하위 전부, 휠체어 화장실 4종 등.
- **category별 규칙:** `parking` 계열은 층간 조건이 맞으면 correlation_id 필수, `restroom` 계열은 맞닿은 화장실 묶음 가운데 추상 값 점 하나가 권장.
- **이름 관련 Warning:** `unspecified`·탑승구·도착구·수하물 컨베이어는 이름 필요. 이름이 category와 같으면 Warning.
- **가이던스 공통 필수:** 공항·교통역·쇼핑센터 모두 `elevator`·`escalator`·`movingwalkway`·`stairs`·`restroom` 계열·`information`·`drinkingfountain`·`defibrillator`·`firstaid`·`lostandfound`·`babychanging`·`mothersroom`·`eatingdrinking`·`parking`·`smokingarea`·`taxi`·`rideshare`·`shuttle`·`peoplemover`·`wheelchairassist`·`vendingmachine.trainticket`를 필수로 수집한다.
- **IMDFrnt:** 172개 드롭다운이 스펙과 일치한다(`Model/PropertySchema.swift:257~`, 주석은 "160종").

## 관련 링크

- [[Amenity]] — 이 값이 붙는 Feature Type
- [[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]] — 5절 category 고르기·도서관 적용 해석
- [[UNIT-CATEGORY]] — 같은 이름의 Unit category(`restroom`, `elevator` 등)와의 관계
- [[SECTION-CATEGORY]] — `unspecified`가 없는 Section 목록과 비교
- [[08) IMDF Feature Type·카테고리 전체 레퍼런스]] — 전체 열거형
- [[IMDF]] — 규격

## 미해결 질문

- `library` Amenity와 `library` Unit의 구분.
- 단순 벽 콘센트를 `powerchargingstation`으로 표시해도 되는가.
