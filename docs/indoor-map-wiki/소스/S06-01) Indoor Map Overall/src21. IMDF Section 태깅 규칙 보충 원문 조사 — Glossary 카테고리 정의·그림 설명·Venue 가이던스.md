---
summary: "src15가 다루지 않은 Section 태깅 근거를 OGC IMDF 1.0.0 원문에서 보충 수집. Section 페이지의 (Illustration) 링크가 가리키는 Glossary 항목, SECTION-CATEGORY 71개 중 Glossary에 정의가 있는 45개의 정의문과 그림 설명 원문, 정의가 없는 26개 목록, Section 정의에 쓰인 Glossary 낱말(threshold·within·Venue Organization), Airport·Transit Station·Shopping Center 가이던스의 Section 행을 정리했다. Section 페이지에는 Unit과 달리 Category Specific Rules 절과 전용 Illustrative Guidance 페이지가 없다. IMDFrnt의 Section 처리 현황도 대조했다."
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0) Section·Glossary·Validations·Airport·Transit_Station·Shopping_Center 페이지 HTML 직접 취득(2026-10-18), IMDFrnt 레포 Model/PropertySchema.swift·Model/IMDFFeatureType.swift"
created: "2026-10-18 21:36"
updated: "2026-10-18 21:36"
---
# IMDF Section 태깅 규칙 보충 원문 조사 — Glossary 카테고리 정의·그림 설명·Venue 가이던스

## 수집 기준

- 수집일: 2026-10-18
- 목적: 사용자 요청 "section 태깅 규칙에 대해서도 위키 작업". Unit 태깅 규칙([[src20. IMDF Unit 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations]])과 같은 수준의 근거를 Section에도 갖추는 것이다.
- 선행 문서: [[src15. IMDF Section·Geofence properties 전수 대조와 카테고리 열거형 조사]](2026-08-29)가 Section 페이지의 Feature Structure·Property Keys 10개·Property Capturing Rules·Geometry Capturing Rules·Validations 23건·SECTION-CATEGORY 71개를 이미 원문 그대로 옮겼다. 이번에 Section 페이지를 다시 내려받아 대조했고, **src15의 원문 인용과 달라진 곳은 없다.** 이 문서는 그 문서를 반복하지 않고, 빠져 있던 부분만 보충한다.
- 방법: src15와 같이 `curl`로 HTML을 직접 받아 태그를 제거하고 본문을 추출했다. 요약 모델을 거치는 WebFetch는 쓰지 않았다.
- 취득한 페이지: Section, Glossary, Validations, Unit, Airport, Transit_Station, Shopping_Center, Apple_Guidance. 모두 본문 취득 성공.

## 핵심 출처

- Section: https://docs.ogc.org/cs/20-094/Section/index.html
- Glossary: https://docs.ogc.org/cs/20-094/Glossary/index.html
- Validations: https://docs.ogc.org/cs/20-094/Validations/index.html (`#section` 앵커)
- Airport Guidance: https://docs.ogc.org/cs/20-094/Airport/index.html
- Transit Station Guidance: https://docs.ogc.org/cs/20-094/Transit_Station/index.html
- Shopping Center Guidance: https://docs.ogc.org/cs/20-094/Shopping_Center/index.html

---

## 1. Section 페이지의 구성 — Unit과 다른 점

Section 페이지의 절은 Feature Structure, Properties, Example, Property Capturing Rules(CORRELATION_ID·PARENTS), Geometry Capturing Rules(Section Extent) 다섯 개뿐이다. 원문은 src15 1.1~1.5절에 있다.

Unit 페이지와 비교하면 두 가지가 없다.

| 항목 | Unit | Section |
| --- | --- | --- |
| Category Specific Rules 절 | 있음(nonpublic·elevator·stairs·walkway 등 category별 MUST 규칙) | **없음** |
| Illustrative Guidance 전용 페이지 | 있음(`illustrations/Unit`) | **없음.** 사이트의 Illustrations 메뉴는 Footprint·Level·Unit 세 개뿐이다 |

따라서 Section의 category별 판단 근거는 **Glossary의 category 정의문과 그 그림 설명**이 전부다. 2절이 그 원문이다.

Section 페이지 Geometry Capturing Rules의 `(Illustration)` 링크 두 개는 각각 Glossary의 `#eatingdrinking`(실제 앵커는 `#eatingdrinking-section`)과 `#retail-department`를 가리킨다. 본문의 다른 링크 세 개는 Glossary의 `threshold`, `Venue Organization`, `within`이다(3절).

## 2. Glossary의 Section category 정의 원문

SECTION-CATEGORY 71개 중 Glossary에 `Section category. "값" ...`으로 시작하는 정의가 있는 것은 **45개**다. 아래는 정의문과 그림 설명(Illustration 캡션) 원문이다. 그림 파일 이름은 원문 `src` 값이다. 그림 자체는 내려받지 않았다.

### 2-1. 그림 설명까지 있는 category (13개)

> **Baggage Claim (Section)** — Section category. "baggageclaim" models the presence and approximate thematic extent of an open or semi-enclosed environment containing a baggage claim operation.
> - Illustration: An operational theme that is suitable for capture as a single contiguous "baggageclaim" Section. (`Photo_BaggageClaimArea.png`)
> - "baggageclaim" Section within a Level. (`ClientBagClaimAreaSection.png`)

> **Check-in** — Section category. "checkin" models the presence and approximate thematic extent of an open or semi-enclosed environment containing a collection of check-in operations.
> - Illustration: An operational theme that is suitable for capture as a single contiguous "checkin" Section. (`Photo_CheckInArea.png`)
> - Two (2) "checkin" Sections within a Level that possess display-points which are the curated point-based representation of the Sections. (`ClientCheckinArea.png`)

> **Eating/Drinking (Section)** — Section category. "eatingdrinking" models the presence and approximate thematic extent of an open or semi-enclosed environment that is used as a "common" area for dining.
> - Illustration: An "eatingdrinking" Section. The display-point, whose display label (name) is "Food Court", is centrally positioned inside the Section. In this scenario, this Section:
>   - Touches several "room" Units
>   - Is within a "walkway" Unit and Level
>   - Models a physical environment that is partially enclosed by physical, vertical barriers
> - (`ClientEatingDrinkingArea.png`)

> **Gate Area (Section)** — Section category. "gatearea" models the presence and approximate extent of an open or semi-enclosed environment containing a collection of operationally related gate holding areas.
> - Illustration: A "gatearea" Section within a "departures" Level. The Section models an operational theme wherein boarding gates share a common identity which is the terminal name. (`ClientGateArea.png`)

> **Immigration (Section)** — Section category. "immigration" models the presence and approximate thematic extent of an open or semi-enclosed environment containing an immigration operation.
> - Illustration: An operational theme that is suitable for capture as a single contiguous "immigration" Section. In this physical environment, the size of each inspection desk makes them a candidate for capture as individual "immigration.desk" Fixtures. (`Immigration.jpg`)
> - An "immigration" Section that defines the extent of this operational theme. (`MeridianImmigrationArea.png`)

> **Parking (Section)** — Section category. "parking" models the presence and approximate thematic extent of an open or semi-enclosed environment whose intended purpose is the storage of vehicles. "parking" should be used when an area cannot be classified using any other category in the hierarchy. "parking" is not further defined in IMDF.
> - Illustration: "parking" Section that is equal to a "parking" Level. The "parking" Section possesses a display-point to be used as the curated point-based representation of the Section. (`MeridianOutdoorLvlParking.png`)

> **Platform (Section)** — Section category. "platform" models the presence and approximate thematic extent of an open or semi-enclosed area of a railway platform that is distinct from another area of the same physical railway platform.
> - Illustration: Physical environment in which the train platform is a candidate for capture as a single "platform" Unit. Conceptually, two (2) "platform" Sections may be used to define the extent of each side of the physical platform that has a different business purpose and a different label. (`ModPhoto_PlatformArea.jpg`)

> **Private** — Section category. "private" models the presence and approximate thematic extent of an open or semi-enclosed environment that is describable by the Venue Organization as private.
> - Illustration: An area of an anchor store that is, in physical reality, a set of rooms. For aesthetic reasons, and to create a simpler map, the rooms were modeled as a theme in the Section layer. This "private" Section touches several "retaildepartment" Sections. (`Meridian_Private_Area.png`)

> **Retail Department** — Section category. "retaildepartment" models the presence and approximate thematic extent of an open or semi-enclosed environment that contains a particular category of products and/or services. Categories of a "retaildepartment" are defined by the Venue Organization. They are not defined in IMDF.
> - Illustration: Several "retaildepartment" Sections within a "room" Unit. Some Sections touch while others are disjoint. The existence of "gaps" among Sections facilitates the exposure of a network of pedestrian pathways that are formerly recognized by the Venue Organization in this anchor store. In modeling terms, the "room" or "walkway" Unit category is "exposed" where the Section does not cover the Unit. (`MeridianDeptArea.png`)

> **Seating** — Section category. "seating" models the presence of an open or semi-enclosed seating environment.
> - Illustration: Physical environment in which the "seating" Section category may be used to define the extent of this service. (`ModPhoto2_SeatingArea.jpg`)

> **Security (Section)** — Section category. "security" models the presence and approximate thematic extent of an open or semi-enclosed area containing a security operation. "security" should be used when an area cannot be classified using any other category in the hierarchy. "security" is not further defined in IMDF.
> - Illustration: The presence of capital equipment, such as security screening equipment, that supports the security operation may be captured as Fixtures. The preferred approach is to only define the extent of a security operation using a "security" Section and to use the display-point as the curated point-based representation of the Section. (`Photo_Security.png`)
> - Illustration: Two (2) "security" Sections that touch both "postsecurity" and "presecurity" Geofences. (`Meridian_Security_Area.png`)
> - A "security" Section's display-point. (`Client_SecCheck.png`)

> **Vegetation (Section)** — Section category. "vegetation" models the presence of an open or semi-enclosed vegetative area that may or may not be prohibited from being used as a pedestrian pathway.
> - Illustration: A physical environment where "vegetation" Sections would be appropriate to model the existence of these areas. Conceptually, where "vegetation" Sections do not cover the underlying Unit, the "walkway" Unit would be exposed. (`Photo_Veg_Area.jpg`)

Section이 그림에 함께 등장하는 다른 Feature Type 항목도 하나 있다.

> **Boarding Gate - Aircraft (Amenity)** — Illustration: "boardinggate.aircraft" Amenities within a "walkway" Unit and "gatearea" Section. (`ClientBoardingGateAmenity.png`)

### 2-2. 정의문만 있는 category (32개)

| 값 | 정의 원문(요지 부분) |
| --- | --- |
| `baggageclaim.intl` | ... containing a baggage claim operation dedicated to international flight operations. |
| `carrental` | ... containing one or more car rental operation. |
| `carrental.dropoff` | ... containing a car rental drop-off operation. |
| `concessions` | ... containing concession operations. |
| `cubicle` | models the presence and approximate thematic extent of a "...partially enclosed office workspace..." Reference. |
| `dutyfree` | ... where a pedestrian may purchase duty free goods and services. |
| `entertainmentarea` | ... whose intended purpose is the offering of entertainment. "entertainmentarea" should be used when an area cannot be classified using any other category in the hierarchy. "entertainmentarea" is not further defined in IMDF. |
| `entertainmentarea.game` | ... the offering of games or some other playful/competitive pursuit. |
| `entertainmentarea.music` | ... the offering of musical entertainment. |
| `entertainmentarea.performance` | ... the offering of movie, theater or live performances. |
| `entertainmentarea.sport` | ... the offering of a competitive physical activity. |
| `exhibit` | ... containing an exhibit. |
| `exhibition` | ... whose intended purpose is the "...organized presentation and display of a selection of items." |
| `gatearea.holding` | ... containing a single gate holding area. The function of the gate holding area is to "hold" persons that are expected to pass through a single boarding gate. |
| `immigration.schengen` | ... containing an immigration operation that "processes" pedestrians from multiple different countries in accordance with a legal framework that allows for a common visa policy. Comment: Although "Schengen" describes a border control arrangement that exists in Europe, the same category can be used to describe a similar legal arrangement that exists amongst other countries around the world. |
| `information` | ... whose intended purpose is the offering of information. "information" should be used when an area cannot be classified using any other category in the hierarchy. "information" is not further defined in IMDF. |
| `paidarea` | models the extent of a Section whose area encompasses a physical environment that is describable by the Venue Organization as a paid area. |
| `parking.bicycle` | ... the storage of bicycles. |
| `parking.compact` | ... the storage of vehicles defined in the automotive industry as being "compact." |
| `parking.ev` | ... the storage of electric vehicles. |
| `parking.longterm` | ... the storage of vehicles for an extended period of time. |
| `parking.motorcycle` | ... the storage of motorcycles. |
| `parking.shortterm` | ... the storage of vehicles for a short period of time. |
| `parking.waitingarea` | ... use by a person (and their vehicle) to wait for the arrival of another person(s). |
| `parkandride` | ... to host a Park & Ride service. |
| `postsecurity` | ... that is describable by the Venue Organization as post-security. |
| `presecurity` | ... that is describable by the Venue Organization as pre-security. |
| `recomposearea` | ... where one can restore composure or calmness. Such as when one exits a security check-point. |
| `retail` | ... containing a retail operation. "retail" should be used when an area cannot be classified using any other category in the hierarchy. "retail" is not further defined in IMDF. |
| `road` | models the presence of an open or semi-enclosed environment used by moving vehicles. |
| `seatingrow` | models the presence of a row of seats. |
| `servicearea` | ... containing a service operation. "servicearea" should be used when an area cannot be classified using any other category in the hierarchy. "servicearea" is not further defined in IMDF. |
| `ticketing` | ... containing ticketing operations and services. |

`...`는 반복되는 앞부분 "models the presence and approximate thematic extent of an open or semi-enclosed environment"를 줄인 것이다. `road`·`seating`·`seatingrow`·`vegetation`·`gatearea`·`paidarea`는 이 문형을 쓰지 않으므로 원문 전체를 옮겼다.

### 2-3. Glossary에 Section 정의가 없는 category (26개)

`arcade`, `gambling`과 `gambling.*` 21개(`baccarat`·`bingo`·`blackjack`·`craps`·`keno`·`mahjong`·`medalgame`·`minibaccarat`·`offtrackbetting`·`pachinko`·`paigow`·`poker`·`poker.letitride`·`poker.paigow`·`poker.threecard`·`poker.video`·`roulette`·`rummy`·`sicbo`·`slotmachine`·`slotmachine.highlimit`), `recreation`, `rental`, `walkway`.

- 71개 목록(Categories 페이지)과 Glossary의 `Section category. "값"` 문장 45개를 프로그램으로 집합 비교한 결과다. 45 + 26 = 71.
- `recreation`·`walkway`는 Glossary에 **Unit category** 정의만 있다("walkway" Unit: "models the presence and physical extent of a pedestrian pathway"). Section `walkway`의 용법은 원문에 없다. **확인 필요.**

### 2-4. 정의문에서 읽히는 공통 문형

거의 모든 정의가 같은 문형을 쓴다.

> models the presence and **approximate thematic extent** of an **open or semi-enclosed** environment ...

Unit category 정의는 "models the presence and **physical extent**"를 쓴다(예: walkway Unit). Section은 "approximate thematic extent"(대략적인 주제 범위), Unit은 "physical extent"(물리적 범위)로 문형 자체가 구분된다. 이 차이는 Section 정의("A Section models the presence and approximate extent of a theme. The boundary of a theme may be a threshold or an indeterminate border.")와 맞물린다.

"should be used when an area cannot be classified using any other category in the hierarchy"라는 문장은 `entertainmentarea`·`information`·`parking`·`retail`·`security`·`servicearea` 여섯 개에 붙는다. 앞의 네 개와 `security`는 하위 값(점 뒤 값)을 가진 계층의 최상위 값이고, `information`·`servicearea`는 하위 값이 없다. 문장이 말하는 "the hierarchy"가 그 값의 하위 계층인지, SECTION-CATEGORY 전체인지는 원문에 정의가 없다. **확인 필요.**

## 3. Section 정의에 쓰인 Glossary 낱말 원문

> **Threshold** — A doorsill, line, strip, or inferable boundary that exists along a horizontal plane that a pedestrian may cross to enter a separately defined physical space.

> **Within** — A spatial condition in which "...the first geometry is completely within the second geometry." Reference.
> - Illustration: Openings that are within the boundary of their respective Units. (`Client_CoincidentOpeningUnit.png`)
> - Units referencing different Levels. One Unit is within the other. (`Client_ParkingPartCover.png`)

> **Venue Organization** — A business, governing body or other institution that has the legal or management rights to capture, manage, maintain, or update a physical characteristic held by a physical Venue or the information used to describe the Venue.

Section 정의의 "threshold or an indeterminate border"는 "문턱·선·띠처럼 바닥에 있는(또는 추론 가능한) 경계, 혹은 경계가 정해지지 않은 테두리"라는 뜻이 된다. 벽이 아니어도 된다는 점이 핵심이다.

## 4. Venue 가이던스의 Section 행

### 4-1. Airport

- Feature-type property recommendations: `"section"` `"checkin"`·`"baggageclaim"`·`"immigration"`·`"security"`는 각각 **MUST possess `display_point`**.
- "The following feature-types/categories MUST be captured" 표의 section 행: `baggageclaim`, `checkin`, `gatearea`, `immigration`, `postsecurity`, `presecurity`, `security`.
- 같은 표의 amenity 행 비고: `"immigration"` — "If preferred over Section display_point", `"security.inspection"` — "If preferred over "security" Section display_point". Section의 display_point 대신 Amenity 점으로 그 자리를 나타내는 쪽을 택할 수 있다는 뜻으로 읽힌다(해석).

### 4-2. Transit Station

- "MUST be captured" 표의 section 행: `immigration`, `paidarea`, `security`.
- amenity 행 비고: `"immigration"` — "If preferred over Section display_point", `"security.checkpoint"`·`"security.inspection"` — "If preferred over "security" Section display_point".

### 4-3. Shopping Center

- Section 행이 **없다.** MUST capture 표는 amenity·fixture·kiosk·unit만 열거한다. 쇼핑센터 가이던스는 Section을 요구하지 않는다.

### 4-4. 그 밖

- 가이던스 페이지는 Airport·Shopping Center·Transit Station 세 종류뿐이다. 도서관·대학 캠퍼스·사무실용 가이던스는 없다.

## 5. Validations의 Section 규칙 재확인

src15 1.6절의 23건과 대조해 차이가 없음을 확인했다. Validations 페이지에서 Section을 언급하는 규칙은 `#section` 절의 것뿐이고, 다른 Feature Type 절에서 Section을 참조하는 규칙은 없다(Unit·Opening·Fixture 절에 Section 관련 항목 없음). 심각도만 다시 정리한다.

| 심각도 | 규칙 |
| --- | --- |
| Info | `SectionHasInteriorRing`(구멍), `SectionHasParentReference`(parents 있음), `SectionsOverlap`(같은 층 Section 내부 겹침) |
| Violation | `SectionMustHaveCategory`, `SectionCategoryMustBeValid`, `SectionMustHavePolygonalGeometry`, `SectionMustReferenceLevel`, `SectionMustBeCoveredByReferencedLevel`, `CorrelationIdMustBeMatched`, `LevelIDsMustBeDissimilarForCorrelationID`, `InvalidCorrelationID`, `InvalidFeatureID`, `DisplayPointMustBePointGeometry`, `AccessibilityMustBeValid`, `RestrictionCategoryMustBeValid`, `NameMustBeString`, `AltNameMustBeString`, `InvalidLanguageTag`, `LabelMustNotBeBlank` |
| Warning | `SectionGeometryMustContainDisplayPoint`, `CategoryShouldBeSameForCorrelationID`, `AltNameLangTagHasNoCorrespondingNameLangTag`, `HasOnlyAltName` |

Section끼리 겹치는 것이 **Info**(정보)일 뿐이라는 점이 Unit과 크게 다르다. Unit은 겹침·빈틈이 Warning이고, Unit 합집합 = Level을 MUST로 요구한다(src20). Section은 층을 빈틈없이 덮을 의무가 없다.

## 6. IMDFrnt 현황 대조

레포 `/Users/sionlee/Documents/GitHub/IMDFrnt` 커밋 `bec89f3`과 작업 트리 기준(2026-10-18 21:36 확인). 코드는 수정하지 않았다.

| 항목 | 위치 | 현황 |
| --- | --- | --- |
| Section 스키마 | `Model/PropertySchema.swift:183~195` | 7개 행(category, name, alt_name, restriction, accessibility, level_id, display_point). src15가 지적한 `address_id`·`correlation_id`·`parents` 누락이 **그대로**다. 주석 "전수 미대조, 확인 필요"도 남아 있다 |
| category 목록 | `PropertySchema.swift:306~` | 71개, `unspecified` 없음. 주석은 아직 "70종" |
| geometry | `Model/IMDFFeatureType.swift:23` | `.polygon` 고정. 스펙은 POLYGONAL(MultiPolygon 허용) |
| Opening 빌려주기 | `IMDFFeatureType.swift:46~51` `canBorrowOpenings` | polygon 계열이면 true라 Section도 포함. 스펙은 "Opening SHOULD NOT be used to model an entrance to a Section" |
| 안내문 | `IMDFFeatureType.swift:57~` `note` | "테마의 대략적 범위. 경계가 물리적 벽이 아닐 수 있고, 아래 walkway가 보이도록 gap을 둘 수 있다." — 스펙과 맞음 |
| display_point | `IMDFFeatureType.swift:30` `hasDisplayPoint` | Section 포함. 찍기 버튼 있음 |

## 미해결 질문

- SECTION-CATEGORY 26개(arcade·gambling 계열·recreation·rental·walkway)는 Glossary에 Section 정의가 없다. 특히 Section `walkway`를 언제 쓰는지(같은 공간의 walkway Unit과 어떻게 구분하는지) 원문에 없다. **확인 필요.**
- "should be used when an area cannot be classified using any other category in the hierarchy"의 "hierarchy"가 그 값의 하위 계층인지 SECTION-CATEGORY 전체인지. **확인 필요.**
- 그림 파일(`MeridianDeptArea.png` 등)은 내려받지 않았다. 캡션만으로 판단했다.
- 도서관에 대한 Venue 가이던스가 없다. 열람 구역·서가 구역에 어떤 Section category를 쓸지는 정의문을 근거로 한 해석이 된다(A 문서에서 다룸).
