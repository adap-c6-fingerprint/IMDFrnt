---
summary: "일반 방문자가 출입할 수 없는 공간(직원 사무실 등)을 IMDF에서 어떻게 표현하는지 공식 스펙 원문으로 확인. Unit category \"nonpublic\" 하나로 모델링하고(SHOULD), 맞닿은 nonpublic Unit은 조건부로 병합하며(SHOULD), restriction은 비우고(SHOULD NOT), Opening은 경계 안에 두지 않는다(SHOULD NOT). 층 전체가 비개방이면 Level 자체를 만들지 않는다(SHOULD NOT). restriction의 employeesonly·restricted는 '비개방 구역을 일부러 자세히 그릴 때'·'일부 방문자만 출입할 때'에 쓰는 별개 장치다."
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0) Unit·Level 페이지, register.apple.com/resources/imdf/types/unit, register.apple.com/resources/indoor/program/additional_resources"
created: "2026-10-17 17:30"
updated: "2026-10-17 17:30"
---
# IMDF 비개방 구역(nonpublic) 모델링 규칙 조사

## 수집 기준

- 수집일: 2026-10-17
- 목적: 실내지도 앱에서 일반 방문자에게 출입 권한이 없는 비개방 공간(직원 사무실 등)을 어떻게 표시해야 하는지 확인. 사용자 전제는 "이런 공간은 실내조사(survey)할 필요도, 도면에서 여러 Unit으로 나눠 태깅할 필요도 없다"는 것이다. 이 전제가 스펙과 맞는지 원문으로 검증한다.
- 방법: OGC가 호스팅하는 IMDF 1.0.0 정식판의 Unit·Level 페이지 HTML을 직접 받아 해당 조항을 원문 그대로 추출했다. Apple 자체 미러(register.apple.com/resources/imdf/types/unit)도 같은 조항을 담고 있음을 함께 확인했다. 두 판본은 같은 문서다(각 페이지 하단 "Copyright © 2021 Apple Inc. and OGC.", [[src16. 실내 지도 위치 정확도 허용 오차 기준 조사]] 핵심 출처 절 참고).
- 표기: 인용은 영어 원문 그대로 두고 아래에 한국어 해설을 붙인다. MUST(반드시), SHOULD(권장, 이유가 있으면 예외 가능), MAY(허용)의 강도는 원문 표기를 따른다.

## 핵심 출처

- OGC IMDF 1.0.0 Unit: https://docs.ogc.org/cs/20-094/Unit/index.html — Property Capturing Rules > RESTRICTION, Geometry Capturing Rules > Category Specific Rules > "nonpublic"·"opentobelow"
- OGC IMDF 1.0.0 Level: https://docs.ogc.org/cs/20-094/Level/index.html — Geometry Capturing Rules > Opening
- Apple IMDF Unit (미러): https://register.apple.com/resources/imdf/types/unit
- Apple, "Additional Resources": https://register.apple.com/resources/indoor/program/additional_resources
- OGC IMDF 1.0.0 Categories: https://docs.ogc.org/cs/20-094/Categories/index.html — 카테고리 이름만 있고 값별 정의 문장은 없다(2026-10-17 확인)

---

## 1. Unit의 두 속성 — category와 restriction

Unit Property Keys 표 원문:

| Property | Type | Description |
| --- | --- | --- |
| `category` | `UNIT-CATEGORY` | The category that best describes the function of the physical Unit |
| `restriction` | `null` or `RESTRICTION-CATEGORY` | The category that best describes a restriction that applies to the entire physical Unit |

- `category`는 공간의 **기능**, `restriction`은 그 Unit **전체에 걸리는 출입 제한**이다. 서로 다른 속성이다.
- `nonpublic`은 `category` 값(UNIT-CATEGORY 열거형)이고, `employeesonly`·`restricted`는 `restriction` 값(RESTRICTION-CATEGORY 열거형, 2종)이다. 열거형 전량은 [[src11. IMDF 공식 스펙 — Feature Type 16종·카테고리 열거형 전수 조사]] 참고.
- Categories 페이지에는 `nonpublic`의 정의 문장이 없다. 의미는 아래 Unit 페이지의 규칙에서 읽어 내야 한다.

## 2. "nonpublic" 카테고리 규칙 원문

위치: Unit > Geometry Capturing Rules > Category Specific Rules > "nonpublic"

> A space that contains non-public areas SHOULD be modeled as a "nonpublic" Unit

비개방 구역이 들어 있는 공간은 `nonpublic` Unit으로 모델링할 것을 권장한다.

> An entire floor that is non-public SHOULD NOT be modeled as one or more "nonpublic" Unit. By extension, the floor SHOULD NOT be modeled as a Level

층 전체가 비개방이면 그 층을 `nonpublic` Unit으로 채우지 말고, 더 나아가 그 층을 Level로도 만들지 말 것을 권장한다.

> A space that is non-public which is occupied by Venue personnel that exchange goods/services with a pedestrian MAY be excluded from the "nonpublic" Unit's extent when doing so would improve the map's aesthetic qualities. (Illustration)

직원이 방문자와 물건·서비스를 주고받는 비개방 공간(예: 카운터 안쪽)은 지도가 보기 좋아진다면 `nonpublic` Unit 범위에서 빼도 된다.

> "nonpublic" Units that touch and reference the same Level SHOULD be merged when:
> - The Venue Organization derives no business value from maintaining separate "nonpublic" Units
> - Map application performance is improved when multiple database records are merged
> - The map's aesthetic quality is improved. (Illustration)

같은 Level에서 맞닿은 `nonpublic` Unit은 다음 경우에 병합할 것을 권장한다. (1) 운영 기관이 따로 유지해서 얻는 업무상 가치가 없을 때, (2) 레코드를 합치면 지도 앱 성능이 나아질 때, (3) 지도 미관이 나아질 때.

> A Unit of dissimilar category MAY be surrounded by a "nonpublic" Unit  when:
> - The Unit models a vertical traversal capability which "passes" through the Level, where the "nonpublic" Unit is located, to another Level
>
> Comment: A Venue Organization should consider the business value of a map of a Level through which a pedestrian can only vertically pass. The value of a Unit on such a Level is likely negligible.
>
> - The Unit is one of a collection of Units, but at least one Unit or Amenity models a vertical traversal capability to the Level

다른 카테고리의 Unit이 `nonpublic` Unit에 둘러싸여도 되는 경우는 두 가지다. (1) 그 Unit이 이 Level을 지나 다른 Level로 가는 수직 이동 수단(엘리베이터·계단 등)일 때, (2) 그 Unit이 여러 Unit 묶음의 하나이고 그중 최소 하나의 Unit 또는 Amenity가 이 Level로 오는 수직 이동 수단일 때. 주석은 "보행자가 수직으로 지나가기만 하는 Level의 지도는 가치가 거의 없을 것"이라고 덧붙인다.

> An Opening SHOULD NOT be within the boundary of a Unit whose category is "nonpublic"
>
> Comment: Occasionally, this is an illusion that is the consequence of the flattening of a 3-dimensional space into a 2-dimensional view. An Opening will appear to model an entrance to a "nonpublic" Unit when, in fact, the Opening is a "threshold" across which the pedestrian transitions to a different Level (above or below). This is analogous to a pedestrian pathway that physically passes under (or over) a non-public space.

`nonpublic` Unit 경계 안에는 Opening(출입구)을 두지 않을 것을 권장한다. 주석: 3차원 공간을 2차원으로 눌러 그리면 가끔 비개방 공간으로 들어가는 문처럼 보이는 Opening이 생기는데, 실제로는 다른 층으로 넘어가는 "threshold"인 경우다. 비개방 공간 아래(또는 위)를 지나는 보행 통로와 같은 상황이다.

## 3. 다른 카테고리 규칙 중 nonpublic이 등장하는 곳

위치: Unit > Category Specific Rules > "opentobelow"

> Shafts and ducts that support building operational functions, which are typically hidden from view, MUST NOT be modeled as an "opentobelow" Unit
>
> Shafts and ducts MUST be modeled as "nonpublic" Units

건물 운영용 샤프트·덕트(보통 눈에 보이지 않음)는 `opentobelow`가 아니라 반드시 `nonpublic` Unit으로 모델링한다. `nonpublic`이 강제(MUST)로 쓰이는 유일한 조항이다.

## 4. restriction 규칙 원문

위치: Unit > Property Capturing Rules > RESTRICTION

> When the general public is expected to visit a physical Venue, but only a subset of that general public is permitted entry to a space, then a Unit SHOULD possess a restriction

일반 대중이 방문하는 Venue에서 그중 일부만 들어갈 수 있는 공간이면 Unit에 restriction을 둘 것을 권장한다.

> “employeesonly” SHOULD be present when a Venue Organization deliberately wishes to map a non-public area of the physical Venue

운영 기관이 비개방 구역을 **일부러 지도에 그리고자 할 때** `employeesonly`를 둘 것을 권장한다.

> “restricted” SHOULD be used when entry to an area is restricted to an authorized sub-set of the general public. (Illustration)

출입이 일반 대중 중 허가된 일부로 제한될 때 `restricted`를 쓸 것을 권장한다.

> “employeesonly” SHOULD NOT be used when the general public, as a matter of general operating procedure, is not expected to visit the Venue. In this situation, the Venue is only visited by a predictable subset of the general public. (Illustration)

평소 운영상 일반 대중이 방문하지 않는 Venue(예측 가능한 일부만 방문)에는 `employeesonly`를 쓰지 않을 것을 권장한다.

> A "nonpublic" Unit SHOULD NOT possess a restriction

`nonpublic` Unit에는 restriction을 두지 않을 것을 권장한다.

## 5. Level 규칙 중 nonpublic이 등장하는 곳

위치: Level > Geometry Capturing Rules > Opening

> A Level MUST be referenced by at least one Opening, with the following allowable exceptions:
> - Level is equal to a "nonpublic" or "walkway.island" Unit
> - An Amenity that models a vertical traversal capability is within the Level

Level은 최소 하나의 Opening이 참조해야 하지만(MUST), Level이 `nonpublic` 또는 `walkway.island` Unit과 같은 경우는 예외다.

## 6. 실내조사(survey)와의 관계

위치: Unit > Geometry Capturing Rules > Unit Extent

> A Unit that models a space expected to be surveyed MUST NOT possess a boundary whose spatial location is arbitrary and effect an outcome where the "blue dot" position is unrealistic.

조사가 예정된(expected to be surveyed) 공간의 Unit은 경계를 임의로 그려 "파란 점"(사용자 현재 위치 표시)이 비현실적인 곳에 찍히게 해서는 안 된다(MUST NOT).

위치: Unit > Category Specific Rules > "column" 주석

> In general, "column" features are only necessary in areas that are expected to be surveyed.

일반적으로 `column` 피처는 조사가 예정된 구역에서만 필요하다.

**확인 필요:** 스펙은 "조사가 예정된 공간"과 그렇지 않은 공간을 구분해서 쓰지만, "`nonpublic` 공간은 조사하지 않는다"고 직접 말하는 문장은 Unit·Level 페이지에서 찾지 못했다. 비개방 공간을 조사할 필요가 없다는 판단은 아래 Apple 문서와 위 구분에서 나온 추론이다.

## 7. Apple Indoor Maps Program 문서

위치: Additional Resources

> Because Apple is adding indoor maps of airports and shopping centers to Apple Maps, we need basic information about occupants in public areas. (…) Apple does not need to know any information about occupants inside private buildings, or private areas inside public buildings.

Apple은 공항·쇼핑센터의 **공용 구역** 입점자 정보는 필요로 하지만, 사적인 건물이나 **공공 건물 안의 사적 구역**의 입점자 정보는 필요로 하지 않는다. 이 문장은 입점자(Occupant) 정보에 관한 것이며 Unit 기하나 조사 범위를 직접 규정하지는 않는다.

## 8. 정리

| 상황 | 스펙이 권하는 표현 | 강도 |
| --- | --- | --- |
| 직원 사무실 등 방문자 출입 불가 구역 | `category: "nonpublic"` Unit | SHOULD |
| 맞닿은 여러 비개방 공간 | 하나의 `nonpublic` Unit으로 병합(조건부) | SHOULD |
| `nonpublic` Unit의 restriction | 두지 않음(null) | SHOULD NOT |
| `nonpublic` Unit 경계 안 Opening | 두지 않음 | SHOULD NOT |
| 층 전체가 비개방 | `nonpublic` Unit으로도, Level로도 만들지 않음 | SHOULD NOT |
| 방문자 응대 카운터 안쪽 | `nonpublic` 범위에서 빼도 됨 | MAY |
| 샤프트·덕트 | `nonpublic` Unit | MUST |
| 비개방 구역을 일부러 자세히 그릴 때 | 실제 카테고리 + `restriction: "employeesonly"` | SHOULD |
| 방문자 중 허가된 일부만 출입 | 실제 카테고리 + `restriction: "restricted"` | SHOULD |

## 9. IM-DFrnt 코드 대조 (2026-10-17)

- `IMDFrnt/IM-DFrnt/Sources/IMDFrnt/Model/PropertySchema.swift:247` — Unit 카테고리 선택지에 `nonpublic`이 있다.
- 같은 파일의 `restriction` 필드는 `.alwaysNull`이다([[src15. IMDF Section·Geofence properties 전수 대조와 카테고리 열거형 조사]]에서 "불일치"로 기록한 항목). `nonpublic` Unit은 restriction을 두지 않으므로 이 경우에는 스펙과 충돌하지 않는다. `employeesonly`·`restricted`를 쓰려는 경우에만 입력 수단이 없다.

## 미해결 질문

- `nonpublic` 공간을 Indoor Survey 앱으로 조사하지 않아도 되는지를 명시한 Apple 문서가 있는가. (6절: 현재는 추론)
- "Illustration" 링크(Unit Illustrative Guidance)의 그림은 이번에 확인하지 않았다. 병합·제외 예시의 실제 모양 확인 필요.
- `nonpublic` Unit 안에 둘러싸인 엘리베이터·계단 Unit에 접근하는 Opening은 어떻게 처리하는가(2절의 "둘러싸여도 되는" 조건과 Opening 금지 조항의 관계).
