---
summary: OGC IMDF 1.0.0이 공식 허용하는 Feature Type 16종과 카테고리 열거형 15종의 전체 값을 스펙 원문 기준으로 정리한 레퍼런스. 각 Feature Type의 geometry·필수 속성·category 대응 관계와 열거형별 허용값 전량을 담는다
source: "[[src11. IMDF 공식 스펙 — Feature Type 16종·카테고리 열거형 전수 조사]], [[src15. IMDF Section·Geofence properties 전수 대조와 카테고리 열거형 조사]]"
related:
  - "[[IMDF]]"
  - "[[05) 라벨에 관하여]]"
  - "[[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]]"
  - "[[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]]"
  - "[[11) 실내 지도의 위치 정확도 — ±5m는 어디서 오는가]]"
  - "[[LABELS]]"
  - "[[Display Point]]"
created: 2026-08-20 00:00
updated: 2026-08-30 17:00
core_keywords:
  - IMDF
  - Feature Type
  - UNIT-CATEGORY
  - SECTION-CATEGORY
  - GEOFENCE-CATEGORY
---
# IMDF Feature Type·카테고리 전체 레퍼런스

## 요약

이 문서는 **OGC IMDF 1.0.0이 공식적으로 허용하는 모든 Feature Type과 카테고리 값**을 스펙 원문 기준으로 모아둔 레퍼런스다. 기존 문서들이 각자의 질문에 필요한 만큼만 부분 인용했던 것을, 변환 도구를 만들 때 참조할 수 있도록 한자리에 정리한다.

구조는 두 층이다.

- **Feature Type 16종** — IMDF가 표현할 수 있는 사물의 종류. 각 Feature의 `feature_type` 필드에 들어가는 값이며, 이것이 곧 출력 GeoJSON 파일의 단위가 된다.
- **카테고리 열거형 15종** — 각 Feature가 "무엇인가"를 말하는 `category` 등의 속성값 목록. 이 값은 스펙이 열거한 것 중에서만 고를 수 있다.

두 층의 관계에서 핵심은 이것이다. **Feature Type 16종 중 12종만 `category`를 갖고, 4종(Kiosk·Anchor·Detail·Address)은 갖지 않는다.** 그리고 열거형 15종 중 12종은 특정 Feature Type 전용이지만, 3종(ACCESS-CONTROL·ACCESSIBILITY·RESTRICTION)과 DOOR-CATEGORY는 여러 Feature Type이 공유하는 속성용이다.

> 출처는 전부 [OGC IMDF 1.0.0 Community Standard](https://docs.ogc.org/cs/20-094/index.html)이며, 카테고리 값은 [Categories 페이지](https://docs.ogc.org/cs/20-094/Categories/index.html)에서 전수 수집했다.

---

## 1. Feature Type 16종 한눈에 보기

`feature_type` 필드에 들어갈 수 있는 값은 다음 16개(소문자)뿐이다.

`address`, `amenity`, `anchor`, `building`, `detail`, `fixture`, `footprint`, `geofence`, `kiosk`, `level`, `occupant`, `opening`, `relationship`, `section`, `unit`, `venue`

| Feature Type     | geometry             | category 열거형              | 성격            |
| ---------------- | -------------------- | ------------------------- | ------------- |
| **Venue**        | Polygon              | VENUE-CATEGORY (필수)       | 장소 전체         |
| **Building**     | **null**             | BUILDING-CATEGORY         | 건물(비공간)       |
| **Footprint**    | Polygon/MultiPolygon | FOOTPRINT-CATEGORY        | 건물의 지면 범위     |
| **Level**        | Polygon              | LEVEL-CATEGORY            | 층             |
| **Unit**         | Polygon              | UNIT-CATEGORY             | 방·통로 등 공간     |
| **Section**      | Polygon/MultiPolygon | SECTION-CATEGORY          | 논리적 영역 묶음     |
| **Opening**      | LineString           | OPENING-CATEGORY          | 개구부(문)        |
| **Geofence**     | Polygon/MultiPolygon | GEOFENCE-CATEGORY (유일 필수) | 가상 경계         |
| **Amenity**      | Point                | AMENITY-CATEGORY          | 편의시설 위치       |
| **Fixture**      | Polygon              | FIXTURE-CATEGORY          | 가구·설비 등 물리 자산 |
| **Occupant**     | **null**             | OCCUPANT-CATEGORY         | 입주 업체(비공간)    |
| **Relationship** | null 또는 GEOMETRY     | RELATIONSHIP-CATEGORY     | 요소 간 연결(엣지)   |
| **Kiosk**        | Polygon              | —                         | 키오스크          |
| **Anchor**       | Point                | —                         | 측위·주소 참조점     |
| **Detail**       | LineString           | —                         | 자유 선형 객체      |
| **Address**      | **null**             | —                         | 우편 주소(비공간)    |

**geometry가 `null`인 Feature Type이 4종**이라는 점이 눈에 띈다. Building, Occupant, Address는 항상 null이고(도형이 아니라 정보 레코드), Relationship은 null이 기본이되 선택적으로 도형을 가질 수 있다. 즉 IMDF는 "지도에 그려지는 것"과 "지도에 붙는 정보"를 같은 Feature 구조로 다루되 geometry 유무로 구분한다.

---

## 2. Feature Type별 상세

### 2.1 Venue — 장소 전체

> "A Venue models the presence, location and approximate extent of a place"

- geometry: POLYGONAL **필수**
- **필수 properties:** `id`, `feature_type`, `category`(VENUE-CATEGORY), `name`(LABELS), `display_point`, `address_id`
- 선택: `restriction`, `alt_name`, `hours`, `phone`, `website`

16종 중 필수 property가 가장 많다. 장소 하나를 식별하는 최소 정보(이름·주소·대표점·분류)를 모두 갖춰야 한다는 뜻이다.

### 2.2 Building / Footprint — 건물과 그 지면 범위

> "A Building describes a physical building structure associated with a Venue."

Building의 geometry는 **null이 필수**다. 건물의 물리적 범위는 Building이 아니라 **Footprint**가 따로 표현한다.

> "A Footprint models the approximate physical extent of one or more referenced Buildings."

이 분리가 IMDF 설계의 특징이다. "건물"이라는 개념(이름·분류·주소)과 "건물이 땅 위에 차지하는 모양"을 별도 Feature로 나눠, 하나의 Building이 여러 Footprint를 갖거나(지상·지하 범위가 다른 경우) 여러 Building이 하나의 Footprint를 공유하는 상황을 표현할 수 있게 했다. Footprint의 `building_ids`는 1개 이상 필수다.

### 2.3 Level — 층과 ordinal

> "A Level models the presence, location and approximate physical extent of a floor area in a physical building or outdoor environment functionally inseparable from the Venue."

- geometry: POLYGONAL 필수
- properties: `category`(LEVEL-CATEGORY), `ordinal`(정수), `outdoor`(불리언), `restriction`, `address_id`, `building_ids`

**`ordinal`의 규정이 중요하다.** 지상 출입층은 반드시 `0`, 지하 첫 층은 `-1`이다. 모델링하지 않은 층이 있으면 번호를 건너뛸 수 있다. 그리고 **명칭이 아니라 실제 물리적 위치를 반영해야 한다** — 건물에서 "2층"이라 부르는 층이라도 지상층이 0이면 그 층의 ordinal은 `1`이다.

한국 건물에 적용하면 이렇다.

| 건물 표기 | ordinal |
| --- | --- |
| 1층 (지상 출입층) | `0` |
| 2층 | `1` |
| B1 | `-1` |
| B2 | `-2` |

즉 **엘리베이터 버튼에 적힌 이름은 `name`(LABELS)에 들어가고, ordinal은 별도의 물리적 순번**이다. `00) Apple Indoor Maps Program과 IMDF 개요` 4.3절이 말한 "엘리베이터 버튼에 표시되는 `L1` 같은 이름"이 바로 `name` 쪽이다.

### 2.4 Unit — 공간

- geometry: POLYGONAL 필수
- properties: `category`(UNIT-CATEGORY), `restriction`, `accessibility`, `name`, `alt_name`, `level_id`, `display_point`

Unit 경계가 벽의 중심선인지 면인지, 그리고 `MUST NOT symmetrical difference` 규정이 무엇을 강제하는지는 [[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]] 1절에 정리되어 있다.

### 2.5 Opening — 개구부

- geometry: LINE-STRING 필수
- properties: `category`(OPENING-CATEGORY), `accessibility`, `access_control`, `door`(DOOR 객체), `name`, `alt_name`, `display_point`, `level_id`

문짝의 형상은 좌표가 아니라 `door` 객체의 속성으로 들어간다([[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]] 2절).

### 2.6 Geofence — 가상 경계

> "A Geofence models the extent of a geofence."

- geometry: POLYGONAL 필수
- **`category`가 유일한 필수 property다.** 나머지(`restriction`, `name`, `alt_name`, `correlation_id`, `display_point`, `building_ids`, `level_ids`, `parents`)는 모두 선택.
- 계층 표현은 `parent_id` 단수가 아니라 **`parents` 배열**(GEOFENCE-ID)이다. 즉 하나의 지오펜스가 여러 상위 지오펜스에 속할 수 있다.

`00) 개요` 4.1절이 말한 "실제 벽 바깥으로 확장되는 가상 영역(보안검색 통과 후 구역, 푸드코트)"이 이 피처다.

### 2.7 Fixture — 물리 자산

> "A Fixture models the presence and approximate physical extent of a moveable or semi-permanent physical asset"

- geometry: Polygon
- properties: `category`(FIXTURE-CATEGORY), `name`, `alt_name`, `level_id`(필수)
- **`unit_id`가 없다.** 특정 Unit에 소속되는 것이 아니라 Level 위에 독립적으로 놓인 폴리곤이다.

`00) 개요` 8절이 언급한 "IMDF에 테이블 같은 fixture를 포함하면 측위 제약이 더해져 정확도가 올라간다"가 이 피처를 가리킨다.

### 2.8 Occupant / Anchor — 입주 업체와 그 위치

> "An Occupant models the presence and location (via Anchor) of a business entity that trades goods and/or services."

Occupant의 geometry는 **null 필수**다. 위치를 스스로 갖지 않고 `anchor_id`로 Anchor를 참조하며, 그 Anchor에서 Unit 위치·점 위치·Address 정보가 파생된다.

- Occupant properties: `name`(LABELS), `category`(OCCUPANT-CATEGORY), `anchor_id`, `hours`, `phone`, `website`, `validity`(TEMPORALITY), `correlation_id`
- Anchor: Point geometry, `address_id`·`unit_id` 등. **category 없음.**

이 구조 덕분에 **같은 자리에 입주 업체가 바뀌어도 Anchor는 그대로 두고 Occupant만 교체**할 수 있다. `00) 개요` 5절의 "입주자는 추적과 이름 갱신을 위해 고유 주소와 ID를 가져야 한다"가 이 설계와 맞물린다. `validity`(TEMPORALITY)가 입주 기간을 담는 필드다.

### 2.9 Relationship — 요소 간 연결

> "A Relationship models the physical or conceptual association between two map elements as an edge, with the optional inclusion of an intermediary element."

- geometry: **null 또는 GEOMETRY** — 기본은 위치 없는 엣지이나, 큐레이션된 경로를 담을 수 있다.
- properties: `category`(RELATIONSHIP-CATEGORY), `direction`, `origin`, `destination`, `intermediary`

| property | 값 |
| --- | --- |
| `direction` | `"directed"`(단방향) 또는 `"undirected"`(양방향) |
| `origin` | 시작 요소 (FEATURE-REFERENCE) |
| `destination` | 끝 요소 (FEATURE-REFERENCE) |
| `intermediary` | 사이에 기여하는 요소들 (FEATURE-REFERENCE 배열) |

**이것이 IMDF의 경로 그래프다.** "3층 엘리베이터 홀 ↔ 4층 엘리베이터 홀"을 `category: "elevator"`, `intermediary: [엘리베이터 Unit]`으로 잇는 식이다. 에스컬레이터처럼 한 방향으로만 갈 수 있는 경우 `direction: "directed"`를 쓴다.

### 2.10 Detail — 의미가 열린 선형

> "A Detail models the presence, location and extent of a physical object. Recognition of the feature in a map is heavily dependent upon the spatial context and cognitive recognition."

- geometry: LINEAL(LineString) 필수
- **properties가 `level_id` 하나뿐이다.** category도 name도 없다.

스펙은 Detail이 벽이나 비보행 선형을 모델링한다고 **명시하지 않는다.** 대신 Venue Organization이 자신의 필요와 지도 앱 use case에 따라 Detail의 범위와 목적을 정한다고 서술한다. 즉 **"그려는 두되 의미는 규정하지 않는" 자유 선형 피처**다. 속성이 없으니 렌더링 시 스타일을 구분할 근거도 없다.

### 2.11 Address — 우편 주소

> "An Address represents a postal address, of official or proprietary designation, associated with an element of a venue."

- geometry: **null 필수**
- properties: `address`, `unit`, `locality`, `province`, `country`, `postal_code`, `postal_code_ext`, `postal_code_vanity` — **category 없음**

### 2.12 Kiosk / Amenity / Section

- **Kiosk**: Polygon. properties는 `name`, `alt_name`, `anchor_id`, `level_id`, `display_point`. **category 없음** — 키오스크라는 것 자체가 이미 분류이기 때문으로 보인다.
- **Amenity**: Point. `category`(AMENITY-CATEGORY)로 편의시설 종류를 표현한다. 열거값이 약 160개로 가장 세분화되어 있다.
- **Section**: **POLYGONAL**(Polygon 또는 MultiPolygon). `category`(SECTION-CATEGORY). Unit보다 큰 논리적 영역 묶음(푸드코트, 게이트 구역 등).

#### Section·Geofence properties 전수 (2026-08-30 확정)

위 요약이 "`category`·`name`·`display_point` 등"으로 줄여 적었던 것을 전수로 채운다. 근거는 [[src15. IMDF Section·Geofence properties 전수 대조와 카테고리 열거형 조사]].

| | Section (10) | Geofence (9) |
|---|---|---|
| 필수 | `category` | `category` |
| 이름 | `name`, `alt_name` | `name`, `alt_name` |
| 표시점 | `display_point` | `display_point` |
| 참조 | `level_id`, `address_id`, `parents` | `building_ids`, `level_ids`, `parents` |
| 기타 | `restriction`, `accessibility`, `correlation_id` | `restriction`, `correlation_id` |

구현할 때 놓치기 쉬운 것들이다.

- **`correlation_id`와 `parents`는 두 Type 모두에 있다.** 스키마에서 빠뜨리면 사용자가 입력할 길이 없어진다.
- **Section은 `level_id`(단수)인데 Geofence는 `level_ids`(복수)다.** Geofence는 여러 층에 걸칠 수 있기 때문이다. `building_ids`도 복수다.
- **`parents`는 단수 `parent_id`가 아니라 배열**이다. 하나가 여러 상위에 속할 수 있다.
- **geometry가 `POLYGONAL`이지 `Polygon`이 아니다.** MultiPolygon이 허용되므로 Polygon으로 고정한 구현은 스펙과 어긋난다.
- Section 예제의 `accessibility` 값이 스칼라(`"wheelchair"`)로 적혀 있는데 표는 "JSON array"라고 한다 — **스펙 원문 내부의 불일치**다. `확인 필요`
- **Opening으로 Section 출입구를 모델링하지 않는다.** 스펙: "An Opening SHOULD NOT be used to model an entrance to a Section."
- Validations에 `GeofenceMustHaveLevelOrBuildingReference`(Violation 등급)가 있다. **표에서는 `building_ids`·`level_ids`가 둘 다 nullable인데 검증에서는 최소 하나가 필수**다. 표만 보고 구현하면 이 검증에 걸린다.

> **주의:** 스펙의 Section·Geofence 예제 JSON 두 개 모두에 원문 오류가 있다 — Section 예제는 후행 쉼표, Geofence 예제는 `building_ids` 값이 UUID v4 형식을 위반한다. **테스트 픽스처로 그대로 쓰면 안 된다.**

---

## 3. 카테고리 열거형 15종 — 전체 값

값은 전부 **소문자**이며, 도트(`.`)로 계층을 표현한다(예: `restroom` → `restroom.female` → `restroom.female.wheelchair`).

> **확인 필요:** Categories 페이지에는 열거값 목록만 있고, 도트 표기법의 의미·확장 가능 여부·미인식 값 처리·최구체값 선택 의무를 규정한 **서술 문단이 없다.** 계층 구조는 값의 형태에서 드러나지만 이를 명문화한 문장은 확보하지 못했다.

### 3.1 UNIT-CATEGORY (약 65) — 공간의 종류

**일반 공간**
`auditorium`, `classroom`, `conferenceroom`, `fitnessroom`, `foodservice`, `huddleroom`, `kitchen`, `laboratory`, `library`, `lobby`, `lounge`, `mailroom`, `mothersroom`, `movietheater`, `office`, `phoneroom`, `privatelounge`, `recreation`, `room`, `serverroom`, `shower`, `smokingarea`, `storage`, `theater`, `waitingroom`

**이동·통로**
`elevator`, `escalator`, `footbridge`, `movingwalkway`, `ramp`, `stairs`, `steps`, `walkway`, `walkway.island`, `road`, `platform`, `parking`

**화장실 계열 (11)**
`restroom`, `restroom.family`, `restroom.female`, `restroom.female.wheelchair`, `restroom.male`, `restroom.male.wheelchair`, `restroom.transgender`, `restroom.transgender.wheelchair`, `restroom.unisex`, `restroom.unisex.wheelchair`, `restroom.wheelchair`

**구조체·재질**
`brick`, `column`, `concrete`, `drywall`, `glass`, `structure`, `wood`

**기타**
`fieldofplay`, `firstaid`, `nonpublic`, `opentobelow`, `terrace`, `unenclosedarea`, `unspecified`, `vegetation`

> **주목할 점:** `brick`, `concrete`, `drywall`, `glass`, `wood`는 공간의 **용도가 아니라 재질**이다. `column`, `structure`도 같은 성격이다. 벽·기둥처럼 사람이 들어갈 수 없는 구조체를 Unit으로 표현해야 할 때 쓰는 값으로 보이는데, 스펙에 용법 설명이 없어 **확인 필요**로 남긴다. 이는 [[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]] 1.2절에서 정리한 "Unit 합집합 = Level" 규정과 관계가 있을 수 있다. 층 전체를 Unit으로 빈틈없이 덮어야 하므로, 벽이 차지하는 자리도 어떤 Unit으로든 채워야 하는 상황이 생기기 때문이다.

### 3.2 AMENITY-CATEGORY (약 160) — 편의시설

가장 값이 많은 열거형이다. 성격별로 나누면 다음과 같다.

**공항·교통 (약 45)**
`arrivalgate`, `baggagecarousel`, `baggagecarousel.intl`, `baggagecarts`, `baggageclaim`, `baggageclaim.oversize`, `baggagerecheck`, `baggagestorage`, `boardinggate`, `boardinggate.aircraft`, `boardinggate.bus`, `boardinggate.ferry`, `boardinggate.train`, `bus`, `bus.muni`, `bus.national`, `carrental`, `checkin`, `checkin.desk`, `checkin.desk.oversizebaggage`, `checkin.desk.transfer`, `checkin.selfservice`, `faregate`, `faregate.oversized`, `gatearea`, `groundtransportation`, `immigration`, `limo`, `parkandride`, `peoplemover`, `platform`, `rail.muni`, `rail.national`, `rideshare`, `shuttle`, `taxi`, `traintrack`, `transit`, `valet`, `wheelchairassist`

**티켓·안내**
`ticketing`, `ticketing.airline`, `ticketing.bus`, `ticketing.bus.muni`, `ticketing.bus.national`, `ticketing.rail`, `ticketing.rail.muni`, `ticketing.rail.national`, `ticketing.shuttle`, `information`, `information.bid`, `information.carrental`, `information.hotel`, `information.mufid`, `information.mufid.arrivals`, `information.mufid.departures`, `information.transit`, `guestservices`, `meetingpoint`, `lostandfound`, `reception.desk`, `cashier`, `changemachine`

**화장실·위생 (13)**
`restroom` 계열 11종(UNIT-CATEGORY와 동일), `babychanging`, `handsanitizerstation`

**안전·의료**
`defibrillator`, `emergencyshelter`, `firealarmpullstation`, `fireextinguisher`, `firstaid`, `healthscreening`, `mobilityrescue`, `police`, `security`, `security.checkpoint`, `security.inspection`, `phone.emergency`

**종교시설 (10)**
`prayerroom`, `prayerroom.buddhism`, `prayerroom.christianity`, `prayerroom.hinduism`, `prayerroom.islam`, `prayerroom.islam.female`, `prayerroom.islam.male`, `prayerroom.judaism`, `prayerroom.shintoism`, `prayerroom.sikh`, `prayerroom.taoic`, `meditation`

**주차 (9)**
`parking`, `parking.bicycle`, `parking.compact`, `parking.ev`, `parking.longterm`, `parking.motorcycle`, `parking.shortterm`, `parking.waitingarea`, `powerchargingstation`

**스포츠 시설 (12)**
`fieldofplay`, `fieldofplay.americanfootball`, `fieldofplay.baseball`, `fieldofplay.basketball`, `fieldofplay.fieldhockey`, `fieldofplay.icehockey`, `fieldofplay.rugby`, `fieldofplay.soccer`, `fieldofplay.softball`, `fieldofplay.tennis`, `fieldofplay.trackfield`, `fieldofplay.volleyball`

**수영장·레저**
`swimmingpool`, `swimmingpool.children`, `swimmingpool.family`, `amphitheater`, `childplayarea`, `exhibit`, `recreation`, `yoga`

**이동 수단**
`elevator`, `escalator`, `movingwalkway`, `ramp`, `stairs`, `pedestriancrossing`

**기타 편의**
`animalreliefarea`, `atm`, `businesscenter`, `cabin`, `caregiver`, `coinlocker`, `copymachine`, `drinkingfountain`, `eatingdrinking`, `entry`, `fittingroom`, `foodservice`, `hoteling`, `landmark`, `library`, `mailbox`, `mothersroom`, `paidarea`, `payphone`, `phone`, `photobooth`, `privatelounge`, `productreturn`, `seat`, `seating`, `service`, `shower`, `sleepbox`, `smokingarea`, `storage`, `strollerrental`, `studentadmissions`, `studentservices`, `unspecified`, `vendingmachine`, `vendingmachine.trainticket`, `wifi`

### 3.3 SECTION-CATEGORY (71) — 논리적 영역

> **(2026-08-30 확정)** 이전에 "약 70"으로 적었던 것을 `curl`로 스펙 HTML을 받아 `<td>` 셀을 전수 추출해 **정확히 71개**로 확정했다. 그리고 **`unspecified`가 없다** — 다른 여러 열거형과 달리 "미지정" 값을 두지 않으므로, 분류를 못 정한 영역은 Section으로 만들 수 없다. 상세는 [[src15. IMDF Section·Geofence properties 전수 대조와 카테고리 열거형 조사]].

**카지노 계열 (22)** — 이 열거형에서 가장 세분화된 부분이다
`gambling`, `gambling.baccarat`, `gambling.bingo`, `gambling.blackjack`, `gambling.craps`, `gambling.keno`, `gambling.mahjong`, `gambling.medalgame`, `gambling.minibaccarat`, `gambling.offtrackbetting`, `gambling.pachinko`, `gambling.paigow`, `gambling.poker`, `gambling.poker.letitride`, `gambling.poker.paigow`, `gambling.poker.threecard`, `gambling.poker.video`, `gambling.roulette`, `gambling.rummy`, `gambling.sicbo`, `gambling.slotmachine`, `gambling.slotmachine.highlimit`

**공항 구역**
`baggageclaim`, `baggageclaim.intl`, `carrental`, `carrental.dropoff`, `checkin`, `dutyfree`, `gatearea`, `gatearea.holding`, `immigration`, `immigration.schengen`, `postsecurity`, `presecurity`, `recomposearea`, `security`, `ticketing`

**상업·유흥**
`arcade`, `concessions`, `eatingdrinking`, `entertainmentarea`, `entertainmentarea.game`, `entertainmentarea.music`, `entertainmentarea.performance`, `entertainmentarea.sport`, `exhibit`, `exhibition`, `rental`, `retail`, `retaildepartment`

**주차 (8)**
`parking`, `parking.bicycle`, `parking.compact`, `parking.ev`, `parking.longterm`, `parking.motorcycle`, `parking.shortterm`, `parking.waitingarea`, `parkandride`

**기타**
`cubicle`, `information`, `paidarea`, `platform`, `private`, `recreation`, `road`, `seating`, `seatingrow`, `servicearea`, `vegetation`, `walkway`

### 3.4 OCCUPANT-CATEGORY (수백~1000여 개) — 업종

입주 업체의 업종·업태 분류로, IMDF에서 **압도적으로 값이 많은 열거형**이다. `3dprinting`, `acai`, `accessories`, `accounting`부터 `yugoslav`까지 알파벳 전 범위에 걸쳐 있으며, 음식점의 경우 요리 국적(`yugoslav` 등)까지 세분화되어 있다.

> **확인 필요:** 값이 너무 많아 이번 조사에서 **전체 목록을 확보하지 못했다.** 실제 사용 시에는 [Categories 페이지](https://docs.ogc.org/cs/20-094/Categories/index.html)를 직접 참조해야 한다.

### 3.5 VENUE-CATEGORY (22) — 장소 유형

`airport`, `airport.intl`, `aquarium`, `businesscampus`, `casino`, `communitycenter`, `conventioncenter`, `governmentfacility`, `healthcarefacility`, `hotel`, `museum`, `parkingfacility`, `resort`, `retailstore`, `shoppingcenter`, `stadium`, `stripmall`, `theater`, `themepark`, `trainstation`, `transitstation`, `university`

`00) Apple Indoor Maps Program과 IMDF 개요` 1절이 든 활용 사례(공항·쇼핑몰·병원·대학·대형 오피스)가 각각 `airport`, `shoppingcenter`, `healthcarefacility`, `university`, `businesscampus`에 대응한다.

### 3.6 LEVEL-CATEGORY (9) — 층의 기능

`arrivals`, `arrivals.domestic`, `arrivals.intl`, `departures`, `departures.domestic`, `departures.intl`, `parking`, `transit`, `unspecified`

9개 중 6개가 공항의 도착·출발 층이다. 일반 건물이라면 대부분 `unspecified`가 된다.

### 3.7 BUILDING-CATEGORY (5)

`parking`, `transit`, `transit.bus`, `transit.train`, `unspecified`

### 3.8 FOOTPRINT-CATEGORY (3)

`aerial`(공중), `ground`(지상), `subterranean`(지하)

### 3.9 OPENING-CATEGORY (7)

| 값 | 의미 |
| --- | --- |
| `pedestrian` | 보행자용. "with or without a physical door" — 문짝 유무와 무관 |
| `pedestrian.principal` | 장소를 외부 도로망과 연결하는 주 출입구 |
| `pedestrian.transit` | 대중교통과 연결 |
| `automobile` | 차량 전용 |
| `bicycle` | 자전거 전용 |
| `emergencyexit` | 비상용 |
| `service` | 천장까지 닿지 않는 장벽(카운터, 낮은 칸막이) |

### 3.10 DOOR-CATEGORY (11) — `door.type`의 값

`door`, `movablepartition`, `open`, `revolving`, `shutter`, `sliding`, `swinging`, `turnstile`, `turnstile.fullheight`, `turnstile.waistheight`, `unspecified`

Opening의 `door` 객체 안 `type` 필드에 들어간다. DOOR 객체의 세 멤버(`type`, `automatic`, `material`)는 스펙상 모두 `MAY`(선택)다.

### 3.11 FIXTURE-CATEGORY (15)

`baggagecarousel`, `boardinggate.desk`, `checkin.desk`, `checkin.kiosk`, `desk`, `equipment`, `furniture`, `immigration.desk`, `inspection.desk`, `obstruction`, `securityequipment`, `stage`, `vegetation`, **`wall`**, `water`

> **중요한 발견:** `wall`이 여기에 있다. [[05) 라벨에 관하여]] GQ3(b)와 [[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]]은 "IMDF에 Wall이라는 독립 Feature Type이 없다"고 확인했는데, **Fixture의 category 값으로는 `wall`이 존재한다.** 즉 벽을 명시적으로 남기고 싶다면 `feature_type: "fixture"`, `category: "wall"`인 Polygon으로 표현하는 경로가 스펙상 열려 있다. 다만 이것이 권장 방식인지는 스펙에 서술이 없어 **확인 필요**다.

### 3.12 GEOFENCE-CATEGORY (8)

`concourse`, `geofence`, `paidarea`, `platform`, `postsecurity`, `presecurity`, `terminal`, `underconstruction`

> **(2026-08-30 재확인)** 전수 추출로 8개가 맞음을 확인했다. 여기에도 **`unspecified`가 없다.** 목록에 `geofence`라는 값이 있는데, 이것이 "분류를 못 정했을 때 쓰는 범용값"인지는 **스펙에 규정 문장이 없다.** `unspecified` 대용으로 쓰는 관행이 있는지는 `확인 필요`.
>
> **SECTION과 겹치는 값이 넷 있다** — `paidarea`, `platform`, `postsecurity`, `presecurity`. 같은 개념을 Section으로 그릴지 Geofence로 그릴지 가르는 기준이 스펙에 없다. 실무에서는 "실제 벽이 있으면 Section, 가상 경계면 Geofence"로 나누는 것이 자연스럽지만 원문 근거는 없다. `확인 필요`

### 3.13 RELATIONSHIP-CATEGORY (7)

`elevator`, `escalator`, `movingwalkway`, `ramp`, `stairs`, `traversal`, `traversal.path`

앞의 5개는 층간·구간 이동 수단이고, `traversal`·`traversal.path`가 일반적인 통행 관계다.

### 3.14 ACCESSIBILITY-CATEGORY (10) — 여러 Feature 공유

`assisted.listening`, `braille`, `hearing`, `hearingloop`, `signlanginterpreter`, `tactilepaving`, `tdd`, `trs`, `volume`, `wheelchair`

Unit·Opening·Geofence 등의 `accessibility` 배열에 들어간다. `tdd`는 청각장애인용 전화 단말, `trs`는 통신 중계 서비스, `tactilepaving`은 점자블록이다.

### 3.15 ACCESS-CONTROL-CATEGORY (8) — Opening 공유

`badgereader`, `fingerprintreader`, `guard`, `keyaccess`, `outofservice`, `passwordaccess`, `retinascanner`, `voicerecognition`

Opening의 `access_control` 배열에 들어간다. 그 문을 통과하려면 무엇이 필요한지를 나타낸다.

### 3.16 RESTRICTION-CATEGORY (2) — 여러 Feature 공유

`employeesonly`, `restricted`

Venue·Building·Level·Unit·Geofence의 `restriction` 필드에 들어간다. 값이 둘뿐이며 `null`이면 제한 없음이다.

---

## 4. 열거형과 Feature Type의 대응 정리

| 열거형 | 쓰이는 곳 | 값 개수 |
| --- | --- | --- |
| OCCUPANT-CATEGORY | Occupant `.category` | 수백~1000여 (미확보) |
| AMENITY-CATEGORY | Amenity `.category` | 약 160 |
| SECTION-CATEGORY | Section `.category` | 약 70 |
| UNIT-CATEGORY | Unit `.category` | 약 65 |
| VENUE-CATEGORY | Venue `.category` | 22 |
| FIXTURE-CATEGORY | Fixture `.category` | 15 |
| DOOR-CATEGORY | Opening `.door.type` | 11 |
| ACCESSIBILITY-CATEGORY | 여러 Feature `.accessibility` | 10 |
| LEVEL-CATEGORY | Level `.category` | 9 |
| GEOFENCE-CATEGORY | Geofence `.category` | 8 |
| ACCESS-CONTROL-CATEGORY | Opening `.access_control` | 8 |
| OPENING-CATEGORY | Opening `.category` | 7 |
| RELATIONSHIP-CATEGORY | Relationship `.category` | 7 |
| BUILDING-CATEGORY | Building `.category` | 5 |
| FOOTPRINT-CATEGORY | Footprint `.category` | 3 |
| RESTRICTION-CATEGORY | 여러 Feature `.restriction` | 2 |

**열거형 15종 중 12종은 특정 Feature Type의 `category` 전용**이고, DOOR-CATEGORY·ACCESSIBILITY-CATEGORY·ACCESS-CONTROL-CATEGORY·RESTRICTION-CATEGORY 4종은 `category`가 아닌 다른 속성에 쓰이거나 여러 Feature가 공유한다.

값 개수의 분포도 시사적이다. **공간 구조를 나타내는 열거형(Footprint 3, Building 5, Level 9)은 값이 적고, 사람이 이용하는 대상을 나타내는 열거형(Occupant 1000+, Amenity 160)은 값이 많다.** IMDF가 건축 구조 기술 포맷이 아니라 **이용자 경험 기술 포맷**이라는 성격이 여기서 드러난다.

---

## 5. 자동 변환 도구를 만들 때의 실무 함의

[[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]] 5절에서 정리한 자동 분류 3축 중 "레이어 → 피처 타입 매핑"을 실제로 구현하려면 이 레퍼런스가 **매핑의 도착지 목록**이 된다.

- **출력 파일 단위 = Feature Type.** FME Writer가 "levels, units, openings, venue, address, building, footprints"를 각각 GeoJSON으로 낸다고 한 것([[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] 5.1절)이 이 16종 중 실제로 쓰이는 것들이다.
- **category 값은 자유 문자열이 아니다.** 도면 텍스트에서 "회의실"을 읽었다면 `conferenceroom`으로, "탕비실"이라면 `kitchen`으로 매핑하는 **한국어 → 열거값 사전**을 따로 만들어야 한다. 이 사전이 없으면 category를 채울 수 없다.
- **매칭 실패 시 폴백이 있다.** UNIT-CATEGORY·LEVEL-CATEGORY·BUILDING-CATEGORY·AMENITY-CATEGORY에는 `unspecified`가 있어, 분류가 안 되는 경우 이 값으로 떨어뜨릴 수 있다. 다만 `00) 개요` 5절이 "카테고리는 좋은 지도와 올바른 렌더링 동작에 결정적"이라 했으므로 `unspecified` 남발은 지도 품질을 떨어뜨린다.
- **category가 없는 4종은 매핑 대상이 아니다.** Kiosk·Anchor·Detail·Address는 분류를 고민할 필요가 없다. 특히 **Detail은 properties가 `level_id` 하나뿐이라, 분류하기 애매한 선형을 일단 담아두는 자리**로 쓸 수 있다.
- **벽을 남기고 싶다면** Fixture(`category: "wall"`) 또는 UNIT-CATEGORY의 재질 값(`brick`·`concrete`·`drywall`) 두 경로가 있다. 둘 중 무엇이 권장인지는 확인되지 않았다.

---

## 관련 링크

- [[IMDF]] — 규격 자체의 개요
- [[05) 라벨에 관하여]] — `name`(LABELS)·`display_point` 등 category 외 속성의 데이터 구조
- [[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]] — 이 레퍼런스의 category 값을 자동으로 채우는 방법
- [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] — Feature Type이 출력 파일 단위가 되는 파이프라인
- [[00) Apple Indoor Maps Program과 IMDF 개요]] — Feature 계층의 개념적 설명
- [[LABELS]], [[Display Point]] — Reference 데이터 타입

## 미해결 질문

- **OCCUPANT-CATEGORY 전체 값 목록** — 수백~1000여 개 규모로 이번 조사에서 미확보. 페이지 분할 조회 등 별도 수집 방법 필요.
- 도트 표기법의 계층 의미, 확장 가능 여부, 미인식 값 처리, 최구체값 선택 의무를 규정한 **서술 문장** — Categories 페이지에 없음. Validations·Apple Guidance 페이지 확인 필요.
- UNIT-CATEGORY의 재질 값(`brick`·`concrete`·`drywall`·`glass`·`wood`)과 `column`·`structure`의 정확한 용법 — 스펙에 설명 없음.
- FIXTURE-CATEGORY의 `wall`이 벽 표현의 권장 경로인가 — Apple Guidance 확인 필요.
- Occupant의 `alt_name` 보유 여부 — `src04`는 "있음", `src11` 조회는 목록에 없음으로 상충.
- Apple Guidance 4개 페이지(Overview, Airport, Shopping Center, Transit Station)의 venue 유형별 카테고리 사용 권장사항 — 미조사.
