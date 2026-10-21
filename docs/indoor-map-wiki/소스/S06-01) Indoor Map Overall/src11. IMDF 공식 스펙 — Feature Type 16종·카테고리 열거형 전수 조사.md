---
summary: "OGC IMDF 1.0.0 공식 스펙의 Categories 페이지와 16개 Feature Type 페이지를 전수 조회해, 모든 카테고리 열거형(15종)의 허용값 전체와 각 Feature Type의 geometry·properties·category 대응 관계를 원문 그대로 수집"
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0 Community Standard) — Categories, Reference, 및 Feature Type 개별 페이지"
created: "2026-08-20 00:00"
updated: "2026-08-20 00:00"
---
# IMDF 공식 스펙 — Feature Type 16종·카테고리 열거형 전수 조사

## 수집 기준

- 수집일: 2026-08-20
- 목적: `src04`(2026-08-12)는 라벨·Display Point 질문에 답하는 과정에서 Feature Type 목록과 일부 category 보유 여부만 확인했고, "Building, Footprint, Level, Venue, Address, Relationship의 category 보유 여부는 미조사"로 남겼다. 사용자가 "IMDF에서 공식적으로 허용하는 모든 카테고리/feature type의 하위 분류"를 요청함에 따라, 스펙의 **Categories 전용 페이지**를 처음으로 조회해 열거형 허용값을 전수 수집하고 미조사 Feature Type을 모두 채움.
- 범위: `docs.ogc.org/cs/20-094`(OGC Community Standard화된 IMDF 1.0.0). `register.apple.com/resources/imdf/`는 SPA 구조로 본문 추출 불가(src04에서 확인된 제약 그대로).
- 주의: **OCCUPANT-CATEGORY만 값이 수백~1000여 개 규모**로, WebFetch 응답에서 전체 열거가 잘려 "3dprinting, acai, accessories, accounting... through yugoslav" 형태로 축약 반환되었다. 전체 목록은 미확보이며, 이 조사에서는 그 사실 자체를 기록한다.

## 핵심 출처

- OGC IMDF 1.0.0 목차: https://docs.ogc.org/cs/20-094/index.html
- **Categories(카테고리 열거형 전체)**: https://docs.ogc.org/cs/20-094/Categories/index.html
- Reference(데이터 타입 정의): https://docs.ogc.org/cs/20-094/Reference/index.html
- Feature Type 개별 페이지 16종: `https://docs.ogc.org/cs/20-094/{Address|Amenity|Anchor|Building|Detail|Fixture|Footprint|Geofence|Kiosk|Level|Occupant|Opening|Relationship|Section|Unit|Venue}/index.html`

## 1. 스펙 목차 구조 (index.html)

- 일반 섹션: Home, License, Reference, Manifest, **Categories**, Glossary, Validations, CHANGELOG
- Feature Types(16): Address, Amenity, Anchor, Building, Detail, Fixture, Footprint, Geofence, Kiosk, Level, Occupant, Opening, Relationship, Section, Unit, Venue
- Apple Guidance: Overview, Airport, Shopping Center, Transit Station
- Illustrations: Footprint, Level, Unit

→ `Categories`가 독립 페이지로 존재한다는 사실은 src04에서 확인되지 않았던 부분이다. 모든 열거형이 이 한 페이지에 모여 있다.

## 2. Categories 페이지 — 열거형 전체 (원문 값 그대로)

Categories 페이지에는 **15개 열거형**이 정의되어 있다. 아래는 각 열거형의 허용값 전량이다(OCCUPANT-CATEGORY 제외).

### 2.1 ACCESS-CONTROL-CATEGORY (8)
`badgereader`, `fingerprintreader`, `guard`, `keyaccess`, `outofservice`, `passwordaccess`, `retinascanner`, `voicerecognition`

### 2.2 ACCESSIBILITY-CATEGORY (10)
`assisted.listening`, `braille`, `hearing`, `hearingloop`, `signlanginterpreter`, `tactilepaving`, `tdd`, `trs`, `volume`, `wheelchair`

### 2.3 AMENITY-CATEGORY (약 160)
`amphitheater`, `animalreliefarea`, `arrivalgate`, `atm`, `babychanging`, `baggagecarousel`, `baggagecarousel.intl`, `baggagecarts`, `baggageclaim`, `baggageclaim.oversize`, `baggagerecheck`, `baggagestorage`, `boardinggate`, `boardinggate.aircraft`, `boardinggate.bus`, `boardinggate.ferry`, `boardinggate.train`, `bus`, `bus.muni`, `bus.national`, `businesscenter`, `cabin`, `caregiver`, `carrental`, `cashier`, `changemachine`, `checkin`, `checkin.desk`, `checkin.desk.oversizebaggage`, `checkin.desk.transfer`, `checkin.selfservice`, `childplayarea`, `coinlocker`, `copymachine`, `defibrillator`, `drinkingfountain`, `eatingdrinking`, `elevator`, `emergencyshelter`, `entry`, `escalator`, `exhibit`, `faregate`, `faregate.oversized`, `fieldofplay`, `fieldofplay.americanfootball`, `fieldofplay.baseball`, `fieldofplay.basketball`, `fieldofplay.fieldhockey`, `fieldofplay.icehockey`, `fieldofplay.rugby`, `fieldofplay.soccer`, `fieldofplay.softball`, `fieldofplay.tennis`, `fieldofplay.trackfield`, `fieldofplay.volleyball`, `firealarmpullstation`, `fireextinguisher`, `firstaid`, `fittingroom`, `foodservice`, `gatearea`, `groundtransportation`, `guestservices`, `handsanitizerstation`, `healthscreening`, `hoteling`, `immigration`, `information`, `information.bid`, `information.carrental`, `information.hotel`, `information.mufid`, `information.mufid.arrivals`, `information.mufid.departures`, `information.transit`, `landmark`, `library`, `limo`, `lostandfound`, `mailbox`, `meditation`, `meetingpoint`, `mobilityrescue`, `mothersroom`, `movingwalkway`, `paidarea`, `parkandride`, `parking`, `parking.bicycle`, `parking.compact`, `parking.ev`, `parking.longterm`, `parking.motorcycle`, `parking.shortterm`, `parking.waitingarea`, `payphone`, `pedestriancrossing`, `peoplemover`, `phone`, `phone.emergency`, `photobooth`, `platform`, `police`, `powerchargingstation`, `prayerroom`, `prayerroom.buddhism`, `prayerroom.christianity`, `prayerroom.hinduism`, `prayerroom.islam`, `prayerroom.islam.female`, `prayerroom.islam.male`, `prayerroom.judaism`, `prayerroom.shintoism`, `prayerroom.sikh`, `prayerroom.taoic`, `privatelounge`, `productreturn`, `rail.muni`, `rail.national`, `ramp`, `reception.desk`, `recreation`, `restroom`, `restroom.family`, `restroom.female`, `restroom.female.wheelchair`, `restroom.male`, `restroom.male.wheelchair`, `restroom.transgender`, `restroom.transgender.wheelchair`, `restroom.unisex`, `restroom.unisex.wheelchair`, `restroom.wheelchair`, `rideshare`, `seat`, `seating`, `security`, `security.checkpoint`, `security.inspection`, `service`, `shower`, `shuttle`, `sleepbox`, `smokingarea`, `stairs`, `storage`, `strollerrental`, `studentadmissions`, `studentservices`, `swimmingpool`, `swimmingpool.children`, `swimmingpool.family`, `taxi`, `ticketing`, `ticketing.airline`, `ticketing.bus`, `ticketing.bus.muni`, `ticketing.bus.national`, `ticketing.rail`, `ticketing.rail.muni`, `ticketing.rail.national`, `ticketing.shuttle`, `traintrack`, `transit`, `unspecified`, `valet`, `vendingmachine`, `vendingmachine.trainticket`, `wheelchairassist`, `wifi`, `yoga`

### 2.4 BUILDING-CATEGORY (5)
`parking`, `transit`, `transit.bus`, `transit.train`, `unspecified`

### 2.5 DOOR-CATEGORY (11)
`door`, `movablepartition`, `open`, `revolving`, `shutter`, `sliding`, `swinging`, `turnstile`, `turnstile.fullheight`, `turnstile.waistheight`, `unspecified`

### 2.6 FIXTURE-CATEGORY (15)
`baggagecarousel`, `boardinggate.desk`, `checkin.desk`, `checkin.kiosk`, `desk`, `equipment`, `furniture`, `immigration.desk`, `inspection.desk`, `obstruction`, `securityequipment`, `stage`, `vegetation`, `wall`, `water`

→ **주목:** `wall`이 여기에 있다. src04와 `05) 라벨에 관하여` GQ3(b)가 "Wall이라는 독립 Feature Type은 없다"고 확인했는데, **Fixture의 category 값으로는 `wall`이 존재**한다. 즉 벽을 명시적으로 표현할 경로가 하나 있다.

### 2.7 FOOTPRINT-CATEGORY (3)
`aerial`, `ground`, `subterranean`

### 2.8 GEOFENCE-CATEGORY (8)
`concourse`, `geofence`, `paidarea`, `platform`, `postsecurity`, `presecurity`, `terminal`, `underconstruction`

### 2.9 LEVEL-CATEGORY (9)
`arrivals`, `arrivals.domestic`, `arrivals.intl`, `departures`, `departures.domestic`, `departures.intl`, `parking`, `transit`, `unspecified`

### 2.10 OCCUPANT-CATEGORY (수백~1000여 개, 전량 미확보)
업종·업태 분류. WebFetch 응답이 축약되어 `3dprinting`, `acai`, `accessories`, `accounting` … `yugoslav` 범위라는 것만 확인됨. **전체 목록 미확보 — 확인 필요.**

### 2.11 OPENING-CATEGORY (7)
`automobile`, `bicycle`, `emergencyexit`, `pedestrian`, `pedestrian.principal`, `pedestrian.transit`, `service`

### 2.12 RELATIONSHIP-CATEGORY (7)
`elevator`, `escalator`, `movingwalkway`, `ramp`, `stairs`, `traversal`, `traversal.path`

### 2.13 RESTRICTION-CATEGORY (2)
`employeesonly`, `restricted`

### 2.14 SECTION-CATEGORY (약 70)
`arcade`, `baggageclaim`, `baggageclaim.intl`, `carrental`, `carrental.dropoff`, `checkin`, `concessions`, `cubicle`, `dutyfree`, `eatingdrinking`, `entertainmentarea`, `entertainmentarea.game`, `entertainmentarea.music`, `entertainmentarea.performance`, `entertainmentarea.sport`, `exhibit`, `exhibition`, `gambling`, `gambling.baccarat`, `gambling.bingo`, `gambling.blackjack`, `gambling.craps`, `gambling.keno`, `gambling.mahjong`, `gambling.medalgame`, `gambling.minibaccarat`, `gambling.offtrackbetting`, `gambling.pachinko`, `gambling.paigow`, `gambling.poker`, `gambling.poker.letitride`, `gambling.poker.paigow`, `gambling.poker.threecard`, `gambling.poker.video`, `gambling.roulette`, `gambling.rummy`, `gambling.sicbo`, `gambling.slotmachine`, `gambling.slotmachine.highlimit`, `gatearea`, `gatearea.holding`, `immigration`, `immigration.schengen`, `information`, `paidarea`, `parkandride`, `parking`, `parking.bicycle`, `parking.compact`, `parking.ev`, `parking.longterm`, `parking.motorcycle`, `parking.shortterm`, `parking.waitingarea`, `platform`, `postsecurity`, `presecurity`, `private`, `recomposearea`, `recreation`, `rental`, `retail`, `retaildepartment`, `road`, `seating`, `seatingrow`, `security`, `servicearea`, `ticketing`, `vegetation`, `walkway`

### 2.15 UNIT-CATEGORY (약 65)
`auditorium`, `brick`, `classroom`, `column`, `concrete`, `conferenceroom`, `drywall`, `elevator`, `escalator`, `fieldofplay`, `firstaid`, `fitnessroom`, `foodservice`, `footbridge`, `glass`, `huddleroom`, `kitchen`, `laboratory`, `library`, `lobby`, `lounge`, `mailroom`, `mothersroom`, `movietheater`, `movingwalkway`, `nonpublic`, `office`, `opentobelow`, `parking`, `phoneroom`, `platform`, `privatelounge`, `ramp`, `recreation`, `restroom`, `restroom.family`, `restroom.female`, `restroom.female.wheelchair`, `restroom.male`, `restroom.male.wheelchair`, `restroom.transgender`, `restroom.transgender.wheelchair`, `restroom.unisex`, `restroom.unisex.wheelchair`, `restroom.wheelchair`, `road`, `room`, `serverroom`, `shower`, `smokingarea`, `stairs`, `steps`, `storage`, `structure`, `terrace`, `theater`, `unenclosedarea`, `unspecified`, `vegetation`, `waitingroom`, `walkway`, `walkway.island`, `wood`

→ **주목:** `brick`, `concrete`, `drywall`, `glass`, `wood`가 UNIT-CATEGORY에 들어 있다. 이들은 공간의 용도가 아니라 **재질**이며, 벽 같은 구조체를 Unit으로 표현할 때 쓰이는 값으로 보인다(스펙에 용법 설명은 없음 — 확인 필요). `column`, `structure`도 같은 성격이다.

### 2.16 VENUE-CATEGORY (22)
`airport`, `airport.intl`, `aquarium`, `businesscampus`, `casino`, `communitycenter`, `conventioncenter`, `governmentfacility`, `healthcarefacility`, `hotel`, `museum`, `parkingfacility`, `resort`, `retailstore`, `shoppingcenter`, `stadium`, `stripmall`, `theater`, `themepark`, `trainstation`, `transitstation`, `university`

### 2.17 Categories 페이지의 서술 규정

이 페이지에는 **열거값 목록만 있고, 도트 표기법의 의미·확장 가능 여부·미인식 값 처리·최구체값 선택 규칙 등을 설명하는 서술 문단이 없다.** (WebFetch 재조회로 확인: "The content provided consists entirely of category listings without explanatory documentation.") → 도트 표기(`restroom.female.wheelchair`)가 계층을 뜻한다는 것은 값의 형태에서 드러나지만, 이를 규정한 문장은 미확보. **확인 필요.**

## 3. Feature Type 16종 — geometry·category·주요 properties (개별 페이지 원문)

### 3.1 Venue
- 정의: "A Venue models the presence, location and approximate extent of a place"
- geometry: **POLYGONAL 필수** — "Venue objects **MUST** have a `"geometry"` member with a polygonal value"
- 필수 properties: `id`, `feature_type`("venue"), `category`(VENUE-CATEGORY), `name`(LABELS), `display_point`(DISPLAY-POINT), `address_id`(ADDRESS-ID)
- 선택 properties: `restriction`, `alt_name`, `hours`, `phone`, `website`

### 3.2 Building
- 정의: "A Building describes a physical building structure associated with a Venue."
- geometry: **null 필수** — "Building objects must have a `"geometry"` member with a `null` value." 물리적 범위는 Footprint가 따로 표현한다.
- properties: `name`, `alt_name`, `category`(BUILDING-CATEGORY), `restriction`, `display_point`, `address_id`

### 3.3 Footprint
- (src06 7절/02번 문서 기존 확인) 정의: "A Footprint models the approximate physical extent of one or more referenced Buildings."
- geometry: Polygon / MultiPolygon
- properties: `category`(FOOTPRINT-CATEGORY), `name`, `building_ids`(1개 이상 필수)

### 3.4 Level
- 정의: "A Level models the presence, location and approximate physical extent of a floor area in a physical building or outdoor environment functionally inseparable from the Venue."
- geometry: **POLYGONAL 필수**
- properties: `category`(LEVEL-CATEGORY), `ordinal`(INTEGER), `outdoor`(Boolean), `restriction`, `address_id`, `building_ids`
- **ordinal 규정:** 지상 출입층은 반드시 `0`, 지하 첫 층은 `-1`. 모델링하지 않은 층이 있으면 번호를 건너뛸 수 있다. **명칭이 아니라 실제 물리적 위치를 반영해야 한다** — "2층"이라도 지상층이 0이면 ordinal은 `1`이 된다.

### 3.5 Unit
- geometry: **POLYGONAL 필수**
- properties: `category`(UNIT-CATEGORY), `restriction`, `accessibility`, `name`, `alt_name`, `level_id`, `display_point`
- (경계-벽 관계 및 symmetrical difference 규정은 `src10` 1절 참조)

### 3.6 Opening
- geometry: **LINE-STRING 필수**
- properties: `category`(OPENING-CATEGORY), `accessibility`, `access_control`, `door`(DOOR 객체), `name`, `alt_name`, `display_point`, `level_id`
- (상세는 `src10` 2절 참조)

### 3.7 Section
- 정의: "A Section models the presence and approximate extent of a theme. The boundary of a theme may be a threshold or an indeterminate border." (2026-08-20 재조사 보강)
- 보조 규정: 테마 범위는 "entirely or only partially enclosed by physical, vertical barriers"일 수 있고, 아래에 깔린 walkway Unit이 보이도록 gap을 둘 수 있다.
- geometry: Polygon
- properties: `category`(SECTION-CATEGORY), `name`, `alt_name`, `display_point` 등

### 3.8 Geofence
- 정의: "A Geofence models the extent of a geofence." — **2026-08-20 재조사 결과, OGC 개별 페이지에 이 동어반복 문장 외에 목적·용도·Geometry Capturing Rule 설명이 없음을 재확인.** 의미 추정은 `GEOFENCE-CATEGORY` 열거값에 의존해야 한다.
- geometry: **POLYGONAL 필수**
- properties: `category`(GEOFENCE-CATEGORY, **유일한 필수 property**), `restriction`, `name`, `alt_name`, `correlation_id`, `display_point`, `building_ids`, `level_ids`, `parents`(GEOFENCE-ID 배열 — 계층은 `parent_id`가 아니라 `parents` 배열로 표현)

### 3.9 Amenity
- 정의: "An Amenity models the physical presence and approximate point location of a pedestrian amenity that serves a utilitarian purpose or other convenience that serves to enhance the pedestrian 'experience.'" (2026-08-20 재조사 보강)
- Geometry Capturing Rule: geometry는 "MUST model the ground-truth or approximate physical location of the represented Amenity where possible"
- geometry: Point
- properties: `category`(AMENITY-CATEGORY), `name`, `alt_name` 등

### 3.10 Fixture
- 정의: "A Fixture models the presence and approximate physical extent of a moveable or semi-permanent physical asset"
- geometry: Polygon
- properties: `category`(FIXTURE-CATEGORY), `name`, `alt_name`, `level_id`(필수). `unit_id`는 없음 — 특정 Unit 소속이 아니라 Level 위에 독립적으로 놓인다.

### 3.11 Kiosk
- 정의: "A Kiosk models the presence and physical extent of furniture that facilitates the distribution of products and/or services." (2026-08-20 재조사 보강)
- 범위 한정 원문: "A Kiosk models the extent of the physical object, only. It is not used to describe the business or service that is operating out of the Kiosk." — 유인 매대·자판기·안내 키오스크를 포괄하며, 사업체 자체는 Occupant가 담당.
- geometry: Polygon
- properties: `name`, `alt_name`, `anchor_id`, `level_id`, `display_point` — **category 없음**

### 3.12 Occupant
- 정의: "An Occupant models the presence and location (via Anchor) of a business entity that trades goods and/or services."
- geometry: **null 필수** — 위치는 Anchor를 통해 얻는다.
- properties: `name`(LABELS), `category`(OCCUPANT-CATEGORY), `anchor_id`(ANCHOR-ID), `hours`, `phone`, `website`, `validity`(TEMPORALITY), `correlation_id`
- `anchor_id`가 참조하는 Anchor에서 Unit 위치·점 위치·Address 정보가 파생된다.
- **참고:** `alt_name`은 Occupant properties 목록에 없다(src04는 "있음"으로 기록했으나 이번 조회에서는 미확인 — 상충, 확인 필요).

### 3.13 Anchor
- geometry: Point
- properties: `address_id`, `unit_id` 등 — **category 없음**

### 3.14 Detail
- 정의: "A Detail models the presence, location and extent of a physical object. Recognition of the feature in a map is heavily dependent upon the spatial context and cognitive recognition."
- geometry: **LINEAL(LineString) 필수**
- properties: `level_id` **하나뿐** — **category 없음, name 없음**
- 용도: 스펙은 Detail이 벽이나 비보행 선형을 모델링한다고 **명시하지 않는다.** 대신 "Venue Organization이 자신의 필요·지도 앱 use case·사용자 경험 향상 정도에 따라 Detail의 범위와 목적을 정한다"고 서술한다. 즉 **의미가 열려 있는 자유 선형 피처**다.

### 3.15 Address
- 정의: "An Address represents a postal address, of official or proprietary designation, associated with an element of a venue."
- geometry: **null 필수**
- properties: `address`, `unit`, `locality`, `province`, `country`, `postal_code`, `postal_code_ext`, `postal_code_vanity` — **category 없음**

### 3.16 Relationship
- 정의: "A Relationship models the physical or conceptual association between two map elements as an edge, with the optional inclusion of an intermediary element."
- geometry: **null 또는 GEOMETRY** — "Relationship objects **MAY** have a `"geometry"` member with a `null` or `GEOMETRY` value." 기본은 unlocated이나 curated path를 담을 수 있다.
- properties: `category`(RELATIONSHIP-CATEGORY), `direction`(`"directed"` 또는 `"undirected"`), `origin`(FEATURE-REFERENCE), `destination`(FEATURE-REFERENCE), `intermediary`(FEATURE-REFERENCE 배열)
- `direction` 정의: "Directionality of declared Relationship from `origin` to `destination`"

## 4. Reference 페이지 — 데이터 타입 21종

STRING, UUID, URI, WEBSITE, HOURS(OSM Opening Hours 형식), PHONE(E.164), ISO-639-1, ISO-639-2, ISO-3166, ISO-3166-2, ISO-15924, DATE-TIME(ISO 8601), FEATURE-ID, FEATURE-TYPE, FEATURE-REFERENCE, LANGUAGE-TAG(RFC 5646), LABELS, TEMPORALITY, DOOR, VERSION, EXTENSIONS

DOOR 객체 원문: "Door objects are JSON objects. Door objects **MAY** have a `"type"` member. Door objects **MAY** have an `"automatic"` member. Door objects **MAY** have a `"material"` member."
→ `door.type`의 값이 DOOR-CATEGORY(2.5절)다. 세 멤버 모두 `MAY`(선택).

## 5. 종합 — category 보유 여부 전수 정리

| Feature Type | geometry | category 열거형 |
| --- | --- | --- |
| Venue | Polygon | VENUE-CATEGORY (필수) |
| Building | null | BUILDING-CATEGORY |
| Footprint | Polygon/MultiPolygon | FOOTPRINT-CATEGORY |
| Level | Polygon | LEVEL-CATEGORY |
| Unit | Polygon | UNIT-CATEGORY |
| Section | Polygon | SECTION-CATEGORY |
| Opening | LineString | OPENING-CATEGORY |
| Geofence | Polygon | GEOFENCE-CATEGORY (유일 필수 property) |
| Amenity | Point | AMENITY-CATEGORY |
| Fixture | Polygon | FIXTURE-CATEGORY |
| Occupant | null | OCCUPANT-CATEGORY |
| Relationship | null 또는 GEOMETRY | RELATIONSHIP-CATEGORY |
| Kiosk | Polygon | **없음** |
| Anchor | Point | **없음** |
| Detail | LineString | **없음** |
| Address | null | **없음** |

→ 16종 중 **12종이 category를 갖고, 4종(Kiosk·Anchor·Detail·Address)은 갖지 않는다.** src04가 미조사로 남긴 Building·Footprint·Level·Venue·Relationship은 모두 category를 가지며, Address만 없다.

→ 열거형 15종 중 **12종은 특정 Feature Type의 `category` 필드 전용**이고, 나머지 3종(ACCESS-CONTROL-CATEGORY, ACCESSIBILITY-CATEGORY, RESTRICTION-CATEGORY)과 DOOR-CATEGORY는 **여러 Feature Type이 공유하는 속성 전용 열거형**이다.

## 미해결 질문

- **OCCUPANT-CATEGORY 전체 값 목록** — WebFetch 응답 축약으로 미확보. 수백~1000여 개 규모라 별도 수집 방법(페이지 분할 조회 등) 필요.
- 도트 표기법(`restroom.female.wheelchair`)의 계층 의미, 확장 가능 여부, 미인식 값 처리, 최구체값 선택 의무를 규정한 **서술 문장** — Categories 페이지에 없음. Reference·Validations·Apple Guidance 페이지에 있는지 미확인.
- UNIT-CATEGORY의 재질 값(`brick`, `concrete`, `drywall`, `glass`, `wood`)과 `column`·`structure`의 정확한 용법 — 스펙에 설명 없음. 벽·기둥을 Unit으로 표현하는 경우를 위한 값으로 추정되나 근거 미확보.
- FIXTURE-CATEGORY의 `wall` 값과 `05) 라벨에 관하여` GQ3(b)의 "Wall Feature Type 없음" 결론의 관계 — 벽을 Fixture로 표현하는 것이 권장 경로인지, Apple Guidance에 언급이 있는지 미확인.
- Occupant의 `alt_name` 보유 여부 — src04는 "있음", 이번 조회는 목록에 없음으로 상충.
- Apple Guidance 4개 페이지(Overview, Airport, Shopping Center, Transit Station)는 이번 조사 범위 밖 — venue 유형별 카테고리 사용 권장사항이 있을 가능성.
