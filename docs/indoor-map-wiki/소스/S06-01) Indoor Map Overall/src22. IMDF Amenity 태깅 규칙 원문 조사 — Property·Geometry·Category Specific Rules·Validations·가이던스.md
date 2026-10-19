---
summary: "IMDF Amenity 태깅 규칙을 OGC IMDF 1.0.0 원문 그대로 수집. Amenity 페이지 전문(정의·Feature Structure·Property Keys 10개·예제·CORRELATION_ID 규칙·Geometry Capturing Rules 5줄·parking·restroom Category Specific Rules), Glossary의 correlation_id(Amenity·Occupant)·공간 관계 낱말·Amenity category 정의(172개 중 135개, 그림 설명 5건), Validations의 Amenity 규칙 44건, 다른 Feature 페이지(Unit·Level·Kiosk)의 Amenity 조항, Reference의 HOURS·PHONE·WEBSITE, 공항·교통역·쇼핑센터 가이던스의 amenity 행을 정리했다. IMDFrnt의 Amenity 스키마·내보내기와도 대조했다."
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0) Amenity·Glossary·Validations·Categories·Reference·Unit·Level·Kiosk·Airport·Transit_Station·Shopping_Center 페이지 HTML 직접 취득(2026-10-18), IMDFrnt 레포 Model/PropertySchema.swift·Export/GeoJSONExporter.swift·Export/IMDFArchive.swift"
created: "2026-10-18 22:03"
updated: "2026-10-18 22:03"
---
# IMDF Amenity 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations·가이던스

## 수집 기준

- 수집일: 2026-10-18
- 목적: 사용자 요청 "Amenity 태깅 규칙에 대해서도 문서 작업". Unit([[src20. IMDF Unit 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations]])·Section([[src21. IMDF Section 태깅 규칙 보충 원문 조사 — Glossary 카테고리 정의·그림 설명·Venue 가이던스]])과 같은 수준으로 Amenity 근거를 모은다. IMDFrnt에서 Amenity 태깅은 도면 위에 점 하나를 찍어 Amenity Feature로 지정하고 category·`unit_ids` 등 속성을 채우는 작업이다.
- 기존 위키 기록: [[src11. IMDF 공식 스펙 — Feature Type 16종·카테고리 열거형 전수 조사]] 3.9절에 정의·Geometry 규칙 한 줄·속성 "등"까지만 있고, 2.3절은 AMENITY-CATEGORY를 "약 160"으로 적었다. src20 6절에 Unit과 관련된 Amenity 검증 9건이 있다. 이번에 전수로 보충한다.
- 방법: `curl`로 HTML을 직접 받아 태그를 제거하고 본문을 추출했다. 요약 모델을 거치는 WebFetch는 쓰지 않았다. category 개수와 정의 유무는 프로그램으로 집합 비교했다.
- 취득 페이지: Amenity, Glossary, Validations, Categories, Reference, Unit, Level, Opening, Fixture, Kiosk, Occupant, Airport, Transit_Station, Shopping_Center. 모두 본문 취득 성공.

## 핵심 출처

- Amenity: https://docs.ogc.org/cs/20-094/Amenity/index.html
- Glossary: https://docs.ogc.org/cs/20-094/Glossary/index.html (`#correlation-id`, `#touch-touching-touched`, `#neighboring`, `#equal`, `#overlap-overlapped-overlapping`, `#within`)
- Validations: https://docs.ogc.org/cs/20-094/Validations/index.html (`#amenity`)
- Categories: https://docs.ogc.org/cs/20-094/Categories/index.html (`#amenity`)
- Reference: https://docs.ogc.org/cs/20-094/Reference/index.html (`#hours`, `#phone`, `#website`)

---

## 1. Amenity 페이지 원문

### 1-1. 정의

> An Amenity models the physical presence and approximate point location of a pedestrian amenity that serves a utilitarian purpose or other convenience that serves to enhance the pedestrian "experience."

보행자에게 실용적 쓰임이나 편의를 주는 것(화장실, 엘리베이터, ATM, 정수기 등)이 **있다는 사실과 대략의 점 위치**를 나타낸다.

### 1-2. Feature Structure

> - Amenity objects are Feature objects
> - Amenity objects MUST have an "id" member with a FEATURE-ID value
> - Amenity objects MUST have a "feature_type" member with the value "amenity"
> - Amenity objects MUST have a "geometry" member with a POINT value

geometry는 **POINT만** 허용한다. Polygon·MultiPoint는 안 된다.

### 1-3. Property Keys (원문 10행 전수)

| Property | Type | Description (원문) | 해설 |
| --- | --- | --- | --- |
| `category` | `AMENITY-CATEGORY` | The category that best describes the function and/or service provided by the Amenity | 필수(`null or` 없음) |
| `accessibility` | `null` or JSON array of `ACCESSIBILITY-CATEGORY` | Indicates the type of accessibility provided by the Amenity to a pedestrian that experiences disabilities | 배열 |
| `name` | `null` or `LABELS` | The name of the Amenity as declared by the Venue Organization | |
| `alt_name` | `null` or `LABELS` | Alternative name for the Amenity that may be recognized by the Venue Organization | |
| `hours` | `null` or `HOURS` | Hours of operation | 형식은 6절 |
| `phone` | `null` or `PHONE` | Main phone number | 형식은 6절 |
| `website` | `null` or `WEBSITE` | Website URL | 형식은 6절 |
| `unit_ids` | JSON array of `UNIT-ID` | Unique identifier of the Unit(s) the Amenity is associated with | **필수**(`null or` 없음). 배열 |
| `address_id` | `null` or `ADDRESS-ID` | ID reference to Address record | |
| `correlation_id` | `null` or `UUID` | Correlation ID shared among similar Amenities that occupy different floors of the physical Venue | |

- null이 허용되지 않는 것은 `category`와 `unit_ids` 둘이다. Validations의 `AmenityMustHaveCategory`·`AmenityMustReferenceUnit`(둘 다 Violation)이 이를 교차 확인한다.
- **`level_id`와 `display_point`가 없다.** Amenity는 층을 직접 가리키지 않고 `unit_ids`의 Unit을 통해 층이 정해진다. 점 Feature라 대표점도 두지 않는다([[Display Point]]의 "non-puntal Feature" 규정).

### 1-4. 예제 (원문)

```json
{
 "id": "11111111-1111-1111-1111-111111111111",
 "type": "Feature",
 "feature_type": "amenity",
 "geometry": {
 "type": "Point",
 "coordinates": [1.0, 2.0]
 },
 "properties": {
 "category": "phone",
 "accessibility": ["tdd", "trs"],
 "name": null,
 "alt_name": null,
 "phone": null,
 "website": null,
 "hours": null,
 "unit_ids": ["22222222-2222-2222-2222-222222222222"],
 "address_id": null,
 "correlation_id": null
 }
}
```

이 예제는 표와 일치한다(`accessibility`·`unit_ids` 모두 배열). 다만 id가 UUID v4 형식이 아니어서(세 번째 묶음이 `1111`) `InvalidFeatureID` 검증에는 걸린다. 다른 페이지 예제들과 같은 자리 표시용 값이다.

### 1-5. Property Capturing Rules — CORRELATION_ID (원문 전수)

> Correlation ID shared by two or more distinct Amenity records modeling the same service that exists on different Levels.
> - MUST NOT be used to correlate instances of the same Amenity that are spatially distributed across a horizontal plane
>
> MUST be specified when ALL of the following conditions are present:
> - The Amenities are within Units that reference different Levels
> - The Units are within, overlap or equal one another (Illustration)
> - Only one Amenity is expected to be visible in a mapping application before a user selects a particular Level
>
> "...within, overlap or equal one another." is equivalent to the same amenity or convenience being physically above or physically below the pedestrian's standing position.

정리하면 세 조건이 **모두** 성립할 때 반드시 넣는다(MUST): (1) 서로 다른 층의 Unit 안에 있고, (2) 그 Unit들이 위아래로 포개지며(within·overlap·equal), (3) 층을 고르기 전 지도에 하나만 보여야 할 때. 같은 층 여기저기 흩어진 같은 종류 Amenity를 묶는 데는 쓰지 않는다(MUST NOT).

`(Illustration)` 링크는 Glossary `#correlation-id`를 가리킨다(3-1절).

### 1-6. Geometry Capturing Rules (원문 전수)

> - MUST model the ground-truth or approximate physical location of the represented Amenity where possible
> - SHOULD be used when no exact ground-truth based placement is possible (e.g. "wifi")
> - SHOULD be used when it is not possible to explicitly model ground-truth using a Unit (e.g. "elevator") or Fixture (e.g. "baggagecarousel")
> - Multiple Amenities MAY be within a single Unit
> - SHOULD be used when the display-point capability of a Unit or Fixture is not suitable for mapping purposes

다섯 줄의 뜻:

1. 가능하면 실제(또는 대략의) 물리적 위치에 찍는다(MUST).
2. 정확한 실제 위치가 없는 것(Wi-Fi 구역)에 쓴다(SHOULD).
3. Unit(엘리베이터)이나 Fixture(수하물 컨베이어)로 실물을 그릴 수 없을 때 쓴다(SHOULD).
4. Unit 하나 안에 Amenity 여러 개를 둬도 된다(MAY).
5. Unit·Fixture의 display_point로는 지도 표시가 마땅치 않을 때 쓴다(SHOULD).

### 1-7. Category Specific Rules (원문 전수)

> **"parking"**
> Amenities with a category value in the "parking" hierarchy are subject to the following additional restrictions.
> - MUST have an assigned "correlation_id" if eligibility requirements listed above are satisfied. (Illustration)

> **"restroom"**
> For Amenities with a category value in the "restroom" hierarchy, the following modeling approach is RECOMMENDED.
> When multiple Units representing restrooms with dissimilar category touch:
> - Centrally locate the Amenity among the Units
> - Select an Amenity category that is suitably abstract and describes the intended purpose of all the Units of dissimilar category
>
> MAY be positioned outside the boundary of a collection of Units that touch or neighbor one another when this is the most practical way to symbolize the existence of the restrooms

- parking 계열: 1-5절 세 조건이 맞으면 correlation_id를 반드시 넣는다.
- restroom 계열(권장): 서로 다른 category의 화장실 Unit들이 맞닿아 있으면(예: 남자 `restroom.male` + 여자 `restroom.female`) Amenity 하나를 그 가운데 두고, 모두를 아우르는 추상적인 category(예: `restroom`)를 고른다. 맞닿거나 이웃한 화장실 묶음 **바깥**에 두는 것이 가장 실용적이면 그래도 된다(MAY).

## 2. AMENITY-CATEGORY — 172개

Categories 페이지 `#amenity` 표에서 셀을 프로그램으로 추출해 **172개**를 확인했다. src11 2.3절의 "약 160"과 IMDFrnt 주석의 "160종"은 정확하지 않다(앱 목록 자체는 172개로 스펙과 양방향 차집합이 공집합).

`amphitheater`, `animalreliefarea`, `arrivalgate`, `atm`, `babychanging`, `baggagecarousel`, `baggagecarousel.intl`, `baggagecarts`, `baggageclaim`, `baggageclaim.oversize`, `baggagerecheck`, `baggagestorage`, `boardinggate`, `boardinggate.aircraft`, `boardinggate.bus`, `boardinggate.ferry`, `boardinggate.train`, `bus`, `bus.muni`, `bus.national`, `businesscenter`, `cabin`, `caregiver`, `carrental`, `cashier`, `changemachine`, `checkin`, `checkin.desk`, `checkin.desk.oversizebaggage`, `checkin.desk.transfer`, `checkin.selfservice`, `childplayarea`, `coinlocker`, `copymachine`, `defibrillator`, `drinkingfountain`, `eatingdrinking`, `elevator`, `emergencyshelter`, `entry`, `escalator`, `exhibit`, `faregate`, `faregate.oversized`, `fieldofplay`과 하위 11개, `firealarmpullstation`, `fireextinguisher`, `firstaid`, `fittingroom`, `foodservice`, `gatearea`, `groundtransportation`, `guestservices`, `handsanitizerstation`, `healthscreening`, `hoteling`, `immigration`, `information`, `information.bid`, `information.carrental`, `information.hotel`, `information.mufid`, `information.mufid.arrivals`, `information.mufid.departures`, `information.transit`, `landmark`, `library`, `limo`, `lostandfound`, `mailbox`, `meditation`, `meetingpoint`, `mobilityrescue`, `mothersroom`, `movingwalkway`, `paidarea`, `parkandride`, `parking`과 하위 7개, `payphone`, `pedestriancrossing`, `peoplemover`, `phone`, `phone.emergency`, `photobooth`, `platform`, `police`, `powerchargingstation`, `prayerroom`과 하위 10개, `privatelounge`, `productreturn`, `rail.muni`, `rail.national`, `ramp`, `reception.desk`, `recreation`, `restroom`과 하위 10개, `rideshare`, `seat`, `seating`, `security`, `security.checkpoint`, `security.inspection`, `service`, `shower`, `shuttle`, `sleepbox`, `smokingarea`, `stairs`, `storage`, `strollerrental`, `studentadmissions`, `studentservices`, `swimmingpool`, `swimmingpool.children`, `swimmingpool.family`, `taxi`, `ticketing`과 하위 8개, `traintrack`, `transit`, **`unspecified`**, `valet`, `vendingmachine`, `vendingmachine.trainticket`, `wheelchairassist`, `wifi`, `yoga`

- **`unspecified`가 있다.** Section·Geofence와 다르다. Glossary 정의: "models the presence and approximate point location of a physical object or service that cannot be classified using any other Amenity category." Validations에 `UnspecifiedAmenityShouldHaveName`(Warning)이 있다.
- 하위 계열 내역: `fieldofplay.`(americanfootball·baseball·basketball·fieldhockey·icehockey·rugby·soccer·softball·tennis·trackfield·volleyball), `parking.`(bicycle·compact·ev·longterm·motorcycle·shortterm·waitingarea), `prayerroom.`(buddhism·christianity·hinduism·islam·islam.female·islam.male·judaism·shintoism·sikh·taoic), `restroom.`(family·female·female.wheelchair·male·male.wheelchair·transgender·transgender.wheelchair·unisex·unisex.wheelchair·wheelchair), `ticketing.`(airline·bus·bus.muni·bus.national·rail·rail.muni·rail.national·shuttle). 위 목록의 "하위 N개"는 상위 값 자신을 뺀 개수다.

## 3. Glossary 원문

### 3-1. Correlation ID — Amenity, Occupant

> In the context of an Amenity and Occupant, a correlation_id is shared among similar features that occupy different floors of the physical Venue. It is used to indicate a common business or service among features that share the correlation_id. correlation_id is an input to a system function. The system function will, based upon the business rules implemented in the map application, render a single representation of the feature, instead of multiple representations. correlation_id is generally applicable when:
> - The features are within Units that reference different Levels
> - The Units overlap or equal one another
> - Only one feature is expected to be visible in the map application before a user selects a particular Level
>
> Comment: "...overlap or equal one another." is equivalent to the same business or service being either physically directly above or physically directly below the Pedestrian's standing position
>
> Illustration 1 — A pair of "parking" Amenities that would share a correlation_id. (`ClientLinkIDParking.png`)

지도 앱은 같은 correlation_id를 가진 Feature들을 **하나로만 그린다**(층 선택 전). 그래서 위아래로 겹친 주차장 입구 표시가 층마다 겹쳐 찍히지 않는다.

Illustration 1의 Data View 예제에는 오류가 두 군데 있다. `"unit_ids": "22222222-..."`가 배열이 아니라 **문자열**이고, `"correlation_id": "33333333-3333-3333-3333-3333333333333"`의 마지막 묶음이 13자리라 **UUID 형식이 아니다.** 표 규정(배열, UUID)을 따라야 한다.

### 3-2. 공간 관계 낱말 (Amenity 페이지에서 링크)

> **Within** — A spatial condition in which "...the first geometry is completely within the second geometry."
> **Overlap** — A spatial condition in which "...two geometries of the same dimension...returns t (TRUE) if their intersection set results in a geometry different from both but of the same dimension."
> **Equal** — A spatial condition in which "...two geometries of the same type have identical X,Y coordinate values." Illustration: "room" Units referencing different Levels that equal one another. / Different Levels that equal one another.
> **Touch** — A spatial condition in which "...none of the points common to both geometries intersect the interiors of both geometries." Illustration: Two Units that touch.
> **Neighboring** — In physical terms, "neighboring" is analogous to spaces separated by a wall or barrier.

### 3-3. Amenity category 정의

172개 중 **135개**에 `Amenity category. "값" ...` 정의가 있다. 거의 모두 "models the presence and approximate point location of ..." 문형이다(Unit은 "physical extent", Section은 "approximate thematic extent").

그림 설명이 있는 것은 5개다.

> **APM** — "peoplemover" models the presence and approximate point location of a transit stop that is associated with a transportation system describable as an Automated People Mover. (`Photo_APM_TransitLevel.jpg`)

> **Boarding Gate - Aircraft (Amenity)** — "boardinggate.aircraft" models the presence and approximate point location of an aircraft boarding gate operation. Illustration: "boardinggate.aircraft" Amenities within a "walkway" Unit and "gatearea" Section.

> **Check-in - Self Service** — "checkin.selfservice" models the presence and approximate point location of furniture/equipment that supports full or semi-automated check-in operations. Illustration: A physical environment where a single "checkin.selfservice" Amenity would be appropriate to model the existence of a collection of self-service check-in kiosks.

> **Fare Gate** — "faregate" models the presence and approximate point location of equipment that supports a fully automated or manned fare gate operation. Illustration: Options exist when considering how to map the presence of fare gates in this physical environment.
> - Capture a "faregate" and "faregate.oversized" Amenity. Note: Not advisable due to possible map label collision
> - Capture a single "faregate" Amenity
>
> The existence of services to persons that experience disabilities is evident in this physical environment. To model these services:
> - Capture a "faregate" Amenity
> - Capture individual Opening features for each faregate
> - On one (1) Opening, set accessibility category to "wheelchair" and "tactilepaving"
> - On each Opening, set Door type "turnstile.waistheight". This is the preferred approach
>
> In a transit station context, spaces beyond the fare gates are candidates for capture within a "paidarea" Section and/or Geofence.

> **Immigration (Amenity)** — "immigration" models the presence and approximate point location of an immigration operation. (Also known as "Passport Control.") Illustration: In this physical environment an "immigration" Amenity point would be appropriate to model the existence of a collection of automated systems that support the immigration operation.

**공통점:** 자동 체크인기 여러 대, 출입국 자동 심사기 여러 대, 개찰구 여러 개처럼 **같은 종류가 모여 있으면 Amenity 점 하나**로 나타내는 예가 반복된다. 개찰구 그림은 점 두 개(`faregate`+`faregate.oversized`)를 라벨 충돌 때문에 권하지 않는다.

도서관·대학 맥락에서 참고할 정의(원문, 앞부분 "models the presence and approximate point location of" 생략):

| 값 | 정의 |
| --- | --- |
| `information` | a: Manned information desk / Automated visitor and/or general information kiosk |
| `reception.desk` | a front desk operation |
| `studentservices` | a student services operation |
| `studentadmissions` | a student admissions operation |
| `copymachine` | a copy machine service |
| `wifi` | a designated zone/area/"hot spot" where Wi-Fi service is available |
| `powerchargingstation` | an automated charging machine |
| `drinkingfountain` | drinking water |
| `vendingmachine` | an automated system that vends products/services that include, but are not limited to, electronics, cosmetics, food and beverage |
| `lostandfound` | a service where a pedestrian may retrieve personal belongings |
| `seating` | one or more seat |
| `seat` | a seat |
| `storage` | a storage facility |
| `restroom` | one or more neighboring space containing bathroom facilities |
| `elevator` | one or more elevator that offers vertical traversal capabilities |
| `stairs` | one or more neighboring staircase that supports vertical traversal to a physically different floor that may or may not be eligible for capture as a Level |
| `escalator` | one or more neighboring escalator that offers vertical traversal capabilities |
| `entry` | an entrance to a physical building |
| `landmark` | a recognizable or substantial natural or artificial feature that is useful for pedestrian navigation or orientation |
| `meetingpoint` | a defined place where people can meet |
| `exhibit` | "...an object, work of art, activity, artifact or poster designed to demonstrate a concept or show an example." |
| `firstaid` | A medical support operation. Or, First Aid Kit |
| `defibrillator` | an Automated External Defibrillator (AED). See also: "firstaid". |
| `fireextinguisher` | a fire protection device |
| `businesscenter` | a space that provides office facilities and services to the public |
| `emergencyshelter` | a room designed to provide shelter. E.g., protection from severe weather conditions. |
| `atm` | an Automated Teller Machine. "atm" may be used to model the location of a "white-label" or brand-name ATM. A brand name ATM should possess a name. |

화장실 하위 값은 문형이 다르다. `restroom.female` 등은 "one or more neighboring space"(이웃한 공간 하나 이상), `restroom.male`만 "a space"로 적혀 있다. `restroom.wheelchair`는 "a bathroom facility that is entirely dedicated to persons with a disability. Related categories available for more precise mapping: restroom.female.wheelchair, restroom.male.wheelchair, restroom.transgender.wheelchair …"이다.

"cannot be classified using any other … category" 문장이 붙는 값: `boardinggate`, `parking`, `security`, `service`, `ticketing`, `transit`, `unspecified`. `service`는 "cannot be classified using any other "service" category in the hierarchy", `unspecified`는 "any other Amenity category"로 범위가 다르게 적혀 있다.

정의가 없는 37개: `checkin`, `coinlocker`, `fieldofplay.` 하위 11개, `information.hotel`, **`library`**, `mailbox`, `meditation`, `payphone`, `photobooth`, `prayerroom.` 하위 10개, `privatelounge`, `restroom.female.wheelchair`, `restroom.male.wheelchair`, `restroom.transgender.wheelchair`, `restroom.unisex.wheelchair`, `ticketing.bus`, `ticketing.rail`, `yoga`. (135 + 37 = 172)

## 4. Validations — Amenity 규칙 44건 (원문)

| 심각도 | 규칙 | 정의(원문) |
| --- | --- | --- |
| Info | `GenericRestroomUnitCategoryContainsSpecificRestroomAmenityCategory` | Validates that a 'restroom.family', 'restroom.female', 'restroom.male', 'restroom.transgender', or 'restroom.unisex' Amenity is not contained (or touched) by a 'restroom' Unit. |
| Violation | `AccessibilityMustBeValid` | Validates the accessibility category assigned to the feature. |
| Violation | `AltNameMustBeString` | Validates that an alt_name is a string data type. |
| Violation | `AmenityCategoryMustBeValid` | Validates the category assigned to an Amenity. |
| Violation | `AmenityMustHaveCategory` | Validates that an Amenity has a category value. |
| Violation | `AmenityMustHavePointGeometry` | Validates that an Amenity is a Point geometry. |
| Violation | `AmenityMustReferenceUnit` | Validates that an Amenity references a Unit. |
| Violation | `CorrelationIdMustBeMatched` | Validates that a correlation_id is matched by at least one other feature's correlation_id in the same feature-type. |
| Violation | `HoursMustNotBeBlank` | Validates that hours are not blank. (Not empty string or whitespace.) |
| Violation | `InvalidCorrelationID` | Validates that a 'correlation_id' is a valid v4 UUID value. |
| Violation | `InvalidFeatureID` | Validates that a feature ID is a valid v4 UUID value. |
| Violation | `InvalidLanguageTag` | Validates that a language tag is a valid value. |
| Violation | `LabelMustNotBeBlank` | Validates that a Label (prefLabel and altLabel) is not blank. |
| Violation | `LevelIDsMustBeDissimilarForCorrelationID` | Validates that features from the same feature-type, whose correlation_id match, possess dissimilar Level id values. |
| Violation | `NameMustBeString` | Validates that a name is a string data type. |
| Violation | `PhoneMustBeValid` | Validates that the phone is correctly formatted. |
| Violation | `WebsiteMustBeValid` | Validates that a website URL is correctly formatted. |
| Warning | `AircraftBoardingGateAmenityShouldHaveName` | Validates that a 'boardinggate.aircraft' Amenity possesses a name. |
| Warning | `AltNameLangTagHasNoCorrespondingNameLangTag` | Validates that a language tag associated with an alt_name has a corresponding presence and association with a name value. |
| Warning | `AmenityNameAndCategoryAreSame` | Validates that an Amenity does not possess a category that matches the name. |
| Warning | `AmenityNameShouldNotBeDuplicate` | Validates that names among Amenities with the same category ('arrivalgate', 'boardinggate.aircraft', 'boardinggate.bus' and 'boardinggate.train') are distinct. |
| Warning | `AmenityShouldBeCoveredByReferencedUnit` | Validates that an Amenity is covered by the referenced Unit. |
| Warning | `AmenityShouldNotEqualAmenity` | Validates that Amenities are not coincident on the same Level. |
| Warning | `ArrivalGateAmenityShouldHaveName` | Validates that an 'arrivalgate' Amenity possesses a name. |
| Warning | `BaggageCarouselAmenityNameIsDuplicateInSameBuilding` | Validates that 'baggagecarousel' Amenity names are distinct in the same Building. |
| Warning | `BaggageCarouselAmenityShouldHaveName` | Validates that a 'baggagecarousel' Amenity possesses a name. |
| Warning | `BusBoardingGateAmenityShouldHaveName` | Validates that a 'boardinggate.bus' Amenity possesses a name. |
| Warning | `CategoryShouldBeSameForCorrelationID` | Validates that features with matching correlation_id possess the same category. |
| Warning | `ElevatorUnitMayOnlyContainElevatorAmenity` | Validates that an Amenity, if present and contained (or touched) by an 'elevator' Unit, is an 'elevator' Amenity and not any other category of Amenity. |
| Warning | `EscalatorUnitMayOnlyContainEscalatorAmenity` | Validates that an Amenity, if present and contained (or touched) by an 'escalator' Unit, is an 'escalator' Amenity and not any other category of Amenity. |
| Warning | `FemaleRestroomUnitMustNotContainRestroomAmenityCategory` | Validates that a 'restroom.family', 'restroom.male', 'restroom.transgender' or 'restroom.unisex' Amenity is not contained (or touched) by a 'restroom.female' Unit. |
| Warning | `HasOnlyAltName` | Validates that an alt_name value is not exclusive, that it is accompanied by a name value. |
| Warning | `KioskMustNotContainAmenityCategory` | Validates that an 'elevator', 'escalator', 'movingwalkway' or 'stairs' Amenity is not contained (or touched) by a Kiosk. |
| Warning | `MaleRestroomUnitMustNotContainRestroomAmenityCategory` | Validates that a 'restroom.family', 'restroom.female', 'restroom.transgender' or 'restroom.unisex' Amenity is not contained (or touched) by a 'restroom.male' Unit. |
| Warning | `MovingWalkwayUnitMayOnlyContainMovingWalkwayAmenity` | Validates that an Amenity, if present and contained (or touched) by a 'movingwalkway' Unit, is a 'movingwalkway' Amenity and not any other category of Amenity. |
| Warning | `OpenToBelowUnitMustNotContainAmenity` | Validates that an Amenity is not contained (or touched) by an 'opentobelow' Unit. |
| Warning | `RestroomUnitCategoryShouldNotContainRestroomAmenityCategory` | Validates i) '.female', '.male', '.transgender', '.unisex' (plus .wheelchair) Amenity is not contained (or touched) by a 'restroom.family' Unit. ii) '.family', '.female', '.male', '.transgender' (plus .wheelchair) Amenity is not contained (or touched) by a 'restroom.unisex' Unit. |
| Warning | `RestroomUnitMayOnlyContainAmenityFromRestroomHierarchy` | Validates that an Amenity, if present and contained (or touched) by a Unit whose category is in the Restroom hierarchy, also possesses a category from the Restroom hierarchy. |
| Warning | `StairsUnitMayOnlyContainStairsAmenity` | Validates that an Amenity, if present and contained (or touched) by a 'stairs' Unit, is a 'stairs' Amenity and not any other category of Amenity. |
| Warning | `StepsUnitMustNotContainAmenity` | Validates that an Amenity is not contained (or touched) by a 'steps' Unit. |
| Warning | `StructuralUnitMustNotContainAmenity` | Validates that an Amenity is not contained (or touched) by a Unit that models physical/structural elements, such as 'brick', 'column', 'concrete', 'drywall', 'glass', 'structure', and 'wood'. |
| Warning | `TrainBoardingGateAmenityShouldHaveName` | Validates that a 'boardinggate.train' Amenity possesses a name value. |
| Warning | `UnspecifiedAmenityShouldHaveName` | Validates that an 'unspecified' Amenity possesses a name. |

Info 1 · Violation 16 · Warning 27 = 44. 눈에 띄는 점:

- `AmenityMustReferenceUnit`은 Violation이지만 `AmenityShouldBeCoveredByReferencedUnit`(점이 그 Unit 안에 있는가)은 **Warning**이다. 1-7절 restroom 규칙이 "묶음 바깥에 둬도 된다(MAY)"고 한 것과 맞물린다.
- `LevelIDsMustBeDissimilarForCorrelationID`는 Amenity에 `level_id`가 없는데도 Amenity 절에 있다. 층은 `unit_ids`의 Unit을 통해 판정된다고 읽힌다(해석, 확인 필요).
- 수직 이동·화장실 Unit 안에는 같은 계열 Amenity만, 계단 단차(`steps`)·뚫린 공간(`opentobelow`)·구조체 Unit 안에는 Amenity를 두지 않는다(모두 Warning). 판정은 "contained (or touched)"(안에 있거나 경계에 닿음)다.

## 5. 다른 Feature 페이지의 Amenity 조항

> **Unit — "nonpublic"** — A Unit of dissimilar category MAY be surrounded by a "nonpublic" Unit when: … The Unit is one of a collection of Units, but at least one Unit or Amenity models a vertical traversal capability to the Level

> **Level — Opening** — A Level MUST be referenced by at least one Opening, with the following allowable exceptions:
> - Level is equal to a "nonpublic" or "walkway.island" Unit
> - An Amenity that models a vertical traversal capability is within the Level

> **Kiosk** — A Kiosk models the extent of the physical object, only. It is not used to describe the business or service that is operating out of the Kiosk. An Occupant (via Anchor) or Amenity would model the operation. … An Amenity MAY be positioned within a Kiosk

수직 이동 Amenity(`elevator`·`stairs`·`escalator` 등)는 층의 출입구 역할을 할 수 있어 Opening 없는 Level의 예외 조건이 된다. Kiosk는 물건의 외곽만 그리고, 거기서 하는 서비스는 Amenity나 Occupant가 맡는다.

## 6. Reference — HOURS·PHONE·WEBSITE (원문)

> **HOURS** — Hours of Operation communicate a fixed or predictable (yearly) set of opening hours for a Feature.
> - MUST communicate the actual advertised hours of operation of the entity
> - MUST NOT describe weekly, bi-weekly, monthly, or temporary operating hours
> - MUST NOT be assumed, guessed or derived using a third-party resource (e.g. Yelp, Google, etc.)
> - MUST be valid per the OSM Opening Hours specification

> **PHONE** — Telephone numbers are provided for various Features to support an inquiry about the entity in the referenced location.
> - MUST NOT be a facsimile (fax) number
> - MUST be prefixed with a country calling code
> - MAY contain an extension number
> - MUST be complete such that a telephone connection is assured whether the caller is located inside the venue or outside of the administrative area
> - MUST be E.164-compliant

> **WEBSITE** — Website URIs are provided for various Features to directly support access to information about the referenced entity.
> - MUST have a scheme value of "http" or "https"
> - SHOULD return an HTTP 200 (OK) status response when resolved

## 7. Venue 가이던스의 amenity 행

### 7-1. 공통(Airport·Transit Station·Shopping Center 모두)

"When not derivable as Units from source data, then the following feature-type/categories MUST be captured": amenity `elevator`, `escalator`, `movingwalkway`, `stairs`. 원본 도면에서 이것들을 Unit으로 만들 수 없으면 Amenity 점으로라도 반드시 넣는다.

"MUST be captured" 표에서 세 가이던스에 공통인 amenity: `babychanging`, `defibrillator`, `drinkingfountain`, `eatingdrinking`, `elevator`, `escalator`, `firstaid`, `information`, `lostandfound`, `mothersroom`, `movingwalkway`, `parking`, `peoplemover`, `restroom`과 하위(family·female·female.wheelchair·male·male.wheelchair·unisex·unisex.wheelchair·wheelchair), `rideshare`, `shuttle`, `smokingarea`, `stairs`, `taxi`, `vendingmachine.trainticket`, `wheelchairassist`.

비고 "If preferred over Unit display_point"가 붙는 값: `elevator`, `escalator`, `movingwalkway`, `parking`, `platform`(Airport·Transit Station만), `restroom`, `restroom.female`, `restroom.female.wheelchair`, `restroom.male`, `restroom.male.wheelchair`, `restroom.wheelchair`, `stairs`. 그 Unit의 display_point로 표시하는 대신 Amenity 점을 택할 수 있다는 뜻으로 읽힌다(해석).

### 7-2. 가이던스별 차이

| 가이던스 | 추가 amenity | 속성 요구 |
| --- | --- | --- |
| Airport | `animalreliefarea`, `baggagecarousel`(If preferred over Fixture display_point), `baggagecarts`, `boardinggate.aircraft`, `checkin.desk`(If preferred over Fixture ("checkin.desk") display_point), `checkin.desk.oversizebaggage`, `checkin.selfservice`, `checkin.desk.transfer`, `immigration`(If preferred over Section display_point), `platform`, `security.checkpoint`, `security.inspection`(If preferred over "security" Section display_point), `ticketing.airline`, `ticketing.rail` | `boardinggate.aircraft` MUST possess `name`. Fixture로 만들 수 없는 `baggagecarousel` Amenity는 MUST possess `name` |
| Transit Station | `animalreliefarea`, `baggagecarousel`, `baggagecarts`, `boardinggate.train`, `checkin.desk`, `checkin.selfservice`, `coinlocker`, `faregate`, `immigration`, `parking.bicycle`, `platform`, `security.checkpoint`·`security.inspection`(둘 다 If preferred over "security" Section display_point) | — |
| Shopping Center | `parking.bicycle`, `ticketing.rail` | — |

도서관·대학용 가이던스는 없다.

## 8. IMDFrnt 현황 대조

레포 `/Users/sionlee/Documents/GitHub/IMDFrnt` 커밋 `bec89f3`과 작업 트리 기준(2026-10-18 22:03 확인). 코드는 수정하지 않았다.

| 항목 | 위치 | 현황 |
| --- | --- | --- |
| Amenity 스키마 | `Model/PropertySchema.swift:83~99` | 스펙 10개 전부 있음. 추가로 `display_point`·`level_id` 2개를 `isNonStandard: true`("공식 스펙에 없음 (36블록 중 9개에만 존재)")로 둔다 |
| 입력 가능 여부 | 같은 곳 | `category`(드롭다운), `name`, `unit_ids`(`.stringArray`, 일련번호 입력 → UUID 변환), `address_id`만 입력 가능. `accessibility`·`alt_name`·`hours`·`phone`·`website`·`correlation_id`는 `.alwaysNull` |
| category 목록 | `PropertySchema.swift:257~` | 172개, 스펙과 일치. 주석은 "160종" |
| geometry | `Model/IMDFFeatureType.swift` `requiredGeometry` | `.point` |
| 내보내기 | `Export/GeoJSONExporter.swift:86~132` | 스키마의 모든 키를 쓴다. 비표준 `display_point`(점 좌표 또는 null)와 `level_id`(층 UUID)도 출력된다. `unit_ids`는 사람이 넣은 일련번호를 UUID로 바꿀 뿐, 점이 들어 있는 Unit을 자동으로 찾아 채우지 않는다 |
| 층 참조 | `Export/IMDFArchive.swift` | `level_id`가 null이면 그 층 UUID로 채운다. Amenity에도 적용된다 |

## 미해결 질문

- IMDFrnt가 Amenity에 비표준 `level_id`·`display_point`를 내보내는 것이 Apple 검증기에서 문제가 되는가. 스펙은 "추가 속성 금지" 조항을 Amenity 페이지에 두지 않았다. Reference의 일반 규정 확인 필요.
- `unit_ids`를 비우고 내보내면 빈 배열인가 null인가 — `AmenityMustReferenceUnit` Violation에 걸리는지 IMDFrnt 동작 확인 필요.
- `LevelIDsMustBeDissimilarForCorrelationID`가 `level_id` 없는 Amenity에서 층을 어떻게 판정하는가(unit_ids의 Unit 경유로 추정).
- `library` Amenity는 Glossary 정의가 없다. Unit `library`와 어떻게 구분해 쓰는지 원문에 없다.
- 그림 파일은 내려받지 않았다. 캡션만으로 판단했다.
