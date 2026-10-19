---
summary: "도면의 닫힌 폴리곤을 Unit 레이어로 태깅할 때 지켜야 할 규칙을 OGC IMDF 1.0.0 Unit 페이지 전문과 Validations 페이지의 Unit 항목에서 원문 그대로 수집. Feature Structure 4개, Property Keys 7개, Property Capturing Rules(DISPLAY-POINT·NAME/ALT_NAME·RESTRICTION), Geometry Capturing Rules(벽 단순화, structure·column, 대칭차 금지, Opening 커버), Category Specific Rules(nonpublic·opentobelow·column·elevator·escalator·movingwalkway·ramp·stairs·steps·walkway), Unit Validations 17건과 Unit을 참조하는 Amenity·Anchor·Opening 검증 항목을 정리했다. IMDFrnt의 Unit 스키마와도 대조했다."
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0) Unit·Level·Footprint·Validations·Glossary·Unit Illustrative Guidance 페이지, Microsoft Places IMDF 요구사항, IMDFrnt 레포 PropertySchema.swift·Stores.swift"
created: "2026-10-18 10:41"
updated: "2026-10-18 14:40"
---
# IMDF Unit 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations

## 수집 기준

- 수집일: 2026-10-18
- 목적: 사용자 요청 "실내지도 unit 레이어 태깅 규칙에 대해 위키 작업". IMDFrnt 앱에서 "태깅"은 도면(SVG)의 개체를 하나의 property type(Feature Type)으로 지정하고 property 값을 채우는 작업을 말한다(`Stores.swift:272` "property type 태깅 대상", `Model/Assignment.swift:10` "방 하나를 태깅하려면"). 따라서 이번 조사 범위는 "닫힌 폴리곤을 Unit으로 지정할 때 무엇을 하나의 Unit으로 자르고, 어떤 category와 property를 넣어야 하는가"를 정하는 스펙 조항 전부다.
- 방법: OGC가 호스팅하는 IMDF 1.0.0 정식판의 Unit 페이지와 Validations 페이지 HTML을 `curl`로 직접 받아 태그를 벗기고 텍스트를 추출했다. 아래 인용은 그 추출본에서 옮긴 원문이다. [[src19. IMDF 비개방 구역(nonpublic) 모델링 규칙 조사]]가 같은 Unit 페이지에서 `nonpublic`·`RESTRICTION` 부분만 뽑았다면, 이번 문서는 나머지를 포함한 전문이다.
- 표기: 인용은 영어 원문 그대로 두고 아래에 한국어 해설을 붙인다. MUST(반드시), SHOULD(권장, 이유가 있으면 예외 가능), MAY(허용)의 강도는 원문 표기를 따른다.

## 핵심 출처

- OGC IMDF 1.0.0 Unit: https://docs.ogc.org/cs/20-094/Unit/index.html
- OGC IMDF 1.0.0 Validations: https://docs.ogc.org/cs/20-094/Validations/index.html
- Apple IMDF Unit (미러): https://register.apple.com/resources/imdf/types/unit — 같은 문서([[src19. IMDF 비개방 구역(nonpublic) 모델링 규칙 조사]] 수집 기준 참고)
- 미확인: Unit 페이지의 "See also: Unit Illustrative Guidance"가 가리키는 `../illustrations/Unit/index.html`은 2026-10-18 요청 시 `404 Not Found`였다. 본문의 "(Illustration)" 링크 일부는 Glossary 항목(예: `Glossary/index.html#elevator-unit`, `#private-lounge`)으로 연결된다. 그림은 이번에 확인하지 않았다. → 2026-10-18 14:40 정정: 404는 URL 대소문자 문제였다(올바른 경로 `illustrations/Unit`). 5-2절에서 수집.

---

## 1. Definition

> A Unit models the presence, location and approximate extent of a space. Extent may be characterized by:
> - A barrier, such as a wall
> - A physical boundary, not necessarily delimitted by a barrier, but beyond which traversal is not expected, such as the edge of a train platform
> - A legal instrument, such as the description of a gross leasable area

Unit은 공간의 존재·위치·대략적 범위를 모델링한다. 범위를 정하는 근거는 세 가지다. (1) 벽 같은 장벽, (2) 장벽은 없지만 더 나아가지 않을 것으로 기대되는 물리적 경계(예: 기차 승강장 가장자리), (3) 법적 문서(예: 임대 면적 설명). 즉 Unit 경계는 벽선만이 아니라 승강장 끝선, 임대 구획선으로도 그을 수 있다.

## 2. Feature Structure

> - Unit objects are Feature objects
> - Unit objects MUST have an "id" member with a FEATURE-ID value
> - Unit objects MUST have a "feature_type" member with the value "unit"
> - Unit objects MUST have a "geometry" member with a POLYGONAL value

`id`(FEATURE-ID, UUID), `feature_type: "unit"`, POLYGONAL geometry(Polygon 또는 MultiPolygon — 아래 Validations의 `UnitMustHavePolygonalGeometry` 설명 참고) 세 가지가 필수다.

## 3. Property Keys

| Property | Type | Description (원문) |
| --- | --- | --- |
| `category` | UNIT-CATEGORY | The category that best describes the function of the physical Unit |
| `restriction` | null or RESTRICTION-CATEGORY | The category that best describes a restriction that applies to the entire physical Unit |
| `accessibility` | null or JSON array of ACCESSIBILITY-CATEGORY | Indicates the type of accessibility provided by the Unit to a pedestrian that experiences disabilities |
| `name` | null or LABELS | The name of the Unit as declared by the Venue Organization |
| `alt_name` | null or LABELS | Alternative name for the Unit that may be recognized by the Venue Organization |
| `level_id` | LEVEL-ID | Unique identifier of the Level feature the Unit possesses a spatial relationship with |
| `display_point` | null or DISPLAY-POINT | The curated location to use as the point-based representation of the Unit |

null을 허용하지 않는 것은 `category`와 `level_id` 둘뿐이다. 나머지 다섯은 null로 둘 수 있다.

스펙 예시(원문 그대로, 원문에 `display_point` 객체 안 후행 쉼표가 있다):

```json
{
  "id": "11111111-1111-1111-1111-111111111111",
  "type": "Feature",
  "feature_type": "unit",
  "geometry": {
    "type": "Polygon",
    "coordinates": [
      [
        [100.0, 0.0],
        [101.0, 0.0],
        [101.0, 1.0],
        [100.0, 1.0],
        [100.0, 0.0]
      ]
    ]
  },
  "properties": {
    "category": "room",
    "restriction": null,
    "accessibility": null,
    "name": {
      "en": "Ball Room"
    },
    "alt_name": null,
    "display_point": {
      "type": "Point",
      "coordinates": [ 100.0, 1.0 ],
    },
    "level_id": "22222223-2222-2222-2222-222222222222"
  }
}
```

## 4. Property Capturing Rules

### 4-1. DISPLAY-POINT

> - MAY be present to explicitly indicate (and symbolize) the location of a point-based representation of a Unit
> - MAY be present to explicitly indicate (and symbolize) a collection of Units possessing the same category that touch. (Illustration)
> - MUST be within the boundary of the Unit

display_point는 Unit 하나의 대표점으로 둘 수 있고(MAY), **같은 category이면서 맞닿은 Unit 묶음**의 대표점으로도 둘 수 있다(MAY). 어느 경우든 그 Unit 경계 안에 있어야 한다(MUST). 두 번째 조항의 Illustration 링크는 Glossary의 `elevator-unit` 항목으로 연결된다 — 엘리베이터 뱅크처럼 붙어 있는 같은 카테고리 Unit 묶음을 아이콘 하나로 표시하는 경우로 읽힌다(그림 미확인, 확인 필요).

### 4-2. NAME, ALT_NAME

> - When a Venue Organization aligns their internal classification scheme to name and alt_name, the following considerations SHOULD be borne in mind:
>   - A functional preference to "surface" one label over another when both name and alt_name store values
>   - A functional preference to "surface" at least one label when one or other property does not store a value
>   - Functional support for searching the content of both properties but only returning the label that is preferred
> - name and alt_name SHOULD NOT duplicate content present in another layer
> - name MUST be formatted consistently throughout the layer and across all deliveries when this is the expected pedestrian "experience"
> - name and alt_name SHOULD NOT store information of a type that supports addressing unless this is a coincidence
>   - A Venue Organization SHOULD use unit in Address. Then, position an Anchor inside the Unit and reference the Address via an Anchor point
>   - When it is a coincidence, then the label MAY be the same as the unit in Address

- 기관 내부 분류 체계를 name·alt_name에 맞출 때는 (1) 둘 다 값이 있으면 어느 쪽을 보여 줄지, (2) 한쪽만 있으면 최소 하나는 보여 줄 것, (3) 검색은 둘 다 하되 결과는 선호 라벨만 돌려줄 것을 고려한다(SHOULD).
- name·alt_name은 다른 레이어에 있는 내용을 중복하지 않는다(SHOULD NOT). 예: 매장명은 Occupant 레이어에 있으므로 Unit name에 또 넣지 않는 경우로 읽힌다(이 예시는 해석, 원문에 없음).
- name 형식은 레이어 전체와 모든 납품본에 걸쳐 일관되어야 한다(MUST, 보행자 경험상 그렇게 기대될 때).
- 호수 같은 주소성 정보는 name·alt_name에 넣지 않는다(SHOULD NOT). 대신 Address의 `unit`에 넣고, Unit 안에 Anchor를 두어 그 Address를 참조한다(SHOULD). 이름이 우연히 호수와 같을 때만 같아도 된다(MAY).

### 4-3. RESTRICTION

원문과 해설은 [[src19. IMDF 비개방 구역(nonpublic) 모델링 규칙 조사]] 4절과 같다. 요지: 일부 방문자만 들어가는 공간에 restriction(SHOULD), `employeesonly`는 비개방 구역을 일부러 그릴 때(SHOULD), `restricted`는 권한 있는 일부 방문자만 들어갈 때(SHOULD), `nonpublic` Unit에는 restriction 없음(SHOULD NOT).

## 5. Geometry Capturing Rules

> See also: Unit Illustrative Guidance
>
> Unit Extent
> - Horizontal positional accuracy MUST be within tolerance
> - A physical, vertical barrier SHOULD be simplified. (Illustration)
>   - A Unit boundary MAY approximate an imaginary line running down the center of a physical, vertical barrier
>   - Instead of an imaginary line, a Unit boundary MAY follow source data that models the "face" of a physical, vertical barrier
>
>   Comment: Good judgement should be exercised when selecting lines in source data to mitigate for any disproportionate impact upon a Unit's internal area measurement.
>   - The simplification of physical, vertical barriers MUST occur in all complex architectural scenarios such as:
>     - Multiple wall intersections
>     - Wall/column combinations
> - A Unit that models a space expected to be surveyed MUST NOT possess a boundary whose spatial location is arbitrary and effect an outcome where the "blue dot" position is unrealistic.
> - Physical, vertical barriers that are architecturally significant in appearance and/or size MAY be modeled as explicit geometries instead of being simplified
>   - A network of floor-to-ceiling walls or an integrated system of walls and columns MUST be modeled as a "structure" Unit. (Illustration) To more specifically describe the material nature of the physical, vertical barrier, the following Unit category types may be used:
>     - "brick"
>     - "concrete"
>     - "drywall"
>     - "glass"
>     - "wood"
>   - A floor-to-ceiling standalone column MUST be modeled as a "column" Unit. (Illustration)
> - Symmetrical difference MUST NOT exist:
>   - Among Units that reference the same Level
>   - Between the union of Units and their referenced Level
> - An Opening MUST be covered by a Unit boundary where the modeled entrance exists

해설:

1. **위치 정확도**는 Reference의 허용 오차(±5m)를 따른다(MUST). [[src16. 실내 지도 위치 정확도 허용 오차 기준 조사]].
2. **벽은 단순화한다(SHOULD).** 경계는 벽 두께의 중심선을 따르거나(MAY), 도면의 벽 "면"(안쪽 선)을 따라도 된다(MAY). 어느 선을 고르든 방 면적이 과도하게 달라지지 않게 판단하라는 주석이 붙는다. 벽이 여러 개 교차하거나 벽·기둥이 붙은 복잡한 곳은 반드시 단순화한다(MUST). 이 부분은 [[src10. 도면 선분이 Unit 폴리곤 좌표로 변환되는 기준 조사 — OGC IMDF·Esri Indoors·FME]]에서도 다뤘다.
3. **실내조사(survey)할 공간의 경계를 임의로 그어서 블루닷 위치가 비현실적으로 나오게 해서는 안 된다(MUST NOT).**
4. **벽을 단순화하지 않고 별도 도형으로 그릴 수도 있다(MAY)** — 외관·크기상 건축적으로 중요한 경우. 그렇게 할 때 바닥에서 천장까지 닿는 벽의 연결망 또는 벽·기둥 일체 구조는 반드시 `structure` Unit이다(MUST). 재질을 더 구체적으로 밝히려면 `brick`·`concrete`·`drywall`·`glass`·`wood`를 쓸 수 있다("may", 소문자). 바닥-천장 독립 기둥은 반드시 `column` Unit이다(MUST).
   - → [[src11. IMDF 공식 스펙 — Feature Type 16종·카테고리 열거형 전수 조사]]와 [[UNIT-CATEGORY]]가 "재질 값의 용법은 스펙에 설명 없음(확인 필요)"으로 남겨 둔 질문의 답이 이 조항이다. 재질 값은 `structure`를 재질로 구체화한 카테고리다.
5. **대칭차(symmetrical difference)가 없어야 한다(MUST NOT)** — (a) 같은 Level을 참조하는 Unit끼리, (b) Unit들의 합집합과 그 Level 사이. 두 도형의 대칭차는 "한쪽에만 속하는 부분"이다. (b)는 Unit들을 합치면 Level과 정확히 같아야 한다는 뜻(빈틈도, 삐져나감도 없음)으로 읽힌다. (a)를 문자 그대로 읽으면 Unit끼리 대칭차가 없다는 것은 서로 같다는 뜻이 되어 성립하지 않는다. ~~따라서 (a)는 Validations의 `UnitsMustNotOverlap`("Unit interiors do not intersect")과 WWDC19의 "In IMDF, units should never overlap"([[WWDC19 - Introducing the Indoor Maps Program]])에 맞춰 "Unit끼리 내부가 겹치지 않는다"로 읽는 것이 맞다(해석, 확인 필요).~~ → **2026-10-18 정정:** Glossary의 Simplification·Symmetrical Difference 원문(5-2절)에 따르면 (a)는 **Unit 사이에 빈틈을 두지 말라**는 뜻이다. 벽 두께만큼 틈을 비워 벽을 암시하던 예전 방식을 금지하고, 경계를 공유하게 한다. 겹침 금지는 (a)가 아니라 `UnitsMustNotOverlap`과 WWDC19 발언이 근거다.
6. **Opening(출입구 선분)은 출입구가 있는 자리의 Unit 경계 위에 놓여야 한다(MUST).**

## 5-1. 추가 수집 — Unit이 덮어야 할 경계: Level 외곽과 Footprint (2026-10-18 11:30)

사용자 질문 "층을 빈틈없이 덮는 기준 경계선이 Footprint 외곽인가", "건물 외벽도 Unit인가", "Level과 Footprint가 완전히 일치해도 되는가"에 답하기 위해 OGC IMDF 1.0.0 Level·Footprint 페이지(https://docs.ogc.org/cs/20-094/Level/index.html, https://docs.ogc.org/cs/20-094/Footprint/index.html)와 Validations의 Footprint 항목을 같은 방식으로 추출했다.

### Level — Definition

> A Level models the presence, location and approximate physical extent of a floor area in:
> - A physical building where the Level's extent is expected to be analogous to the surface (facade) of the physical building at the height where the floor is positioned
> - An outdoor environment that is functionally inseparable from the physical Venue

### Level — Geometry Capturing Rules (발췌)

> The Level SHOULD possess an extent that is analogous to the surface (facade) of the physical building at the height where the modeled floor is positioned. (Illustration)
>
> Level
> - MUST NOT overlap or lay within another Level when all the following are true:
>   - Levels reference the same Building
>   - Levels possess the same ordinal
> - When more than one Level is necessary to model physical floors of the same extent at different relative heights in the same referenced Building, and the physical building does not possess a facade whose extent is variable amongst floors, then:
>   - Levels MUST be equal. (Illustration)
>
> If Levels cannot equal one another, for technical/practical reasons, then Levels MUST possess the following spatial characteristics:
> - With the human eye, no symmetrical difference is discernible between the Levels
>
> "...discernible..." - Symmetrical difference that is visible at a map scale of 1:500. This value translates into an allowance, in a cross-sectional direction, of up to 0.2 meters (8") of symmetrical difference.
>
> Symmetrical difference MUST NOT exist between the union of Units and their referenced Level
>
> Footprint
> When Levels, of dissimilar ordinal, model a physical environment that is positioned on a sloped terrain and the Levels define, in part or in whole, ground-floor access, then portions of the Levels that are "exposed" at ground MUST be within a "ground" Footprint.

해설: Unit이 덮어야 할 기준은 Level 도형이고(MUST), Level 외곽은 그 층 높이의 외벽면(facade)과 "analogous"(대략 같음)해야 한다(SHOULD). 바깥면·안쪽면 중 어느 쪽인지는 원문에 없다(→ 5-2절 그림에서 바깥면으로 확인). 같은 Building·같은 ordinal Level끼리 겹침 금지(MUST NOT). 외벽면이 층마다 같으면 Level 도형도 같아야 하고(MUST), 불가능하면 1:500에서 식별 불가한 수준(단면 방향 0.2m)까지 허용.

### Footprint — Definition·Geometry·Category Specific Rules (발췌)

> A Footprint models the approximate physical extent of one or more referenced Buildings.
>
> - When a Venue operates inside a shared physical Building that includes spaces not considered to be functionally relevant but structurally inseparable, then the inseparable spaces SHOULD be included in a Footprint to the extent necessary to support cognitive recognition. (Illustration)
>
> "ground"
> - MUST be used when the Footprint is derived from a site plan, source data, or a view that explicitly describes the physical extent of the Building at ground-level. (Illustration)
> - MUST represent the totality of all portions of the floor(s) that are exposed at ground-level when physical access to a Building exists on more than one Level because of a sloped terrain
>
> "aerial"
> - MUST possess an extent describable as the physical Building(s) "...represented as the shadow projected downward from an overhead light at infinity." (Illustration)
>
> "subterranean"
> - MUST be derived from the maximum extent of all floors, modeled as one or more Level, that exist below ground-level

### Validations — Footprint 항목 (Level과의 일치)

| feature | severity | rule | 원문 설명 |
| --- | --- | --- | --- |
| Footprint | Warning | IndoorLevelNotEqualToAerialFootprint | Validates that the union of all Indoor Levels whose ordinal is '0' and greater, is equal to the 'aerial' Footprint referencing the same Building. |
| Footprint | Warning | IndoorLevelNotEqualToGroundFootprint | Validates that the union of all Indoor Levels whose ordinal is '0' is equal to the 'ground' Footprint referencing the same Building. |
| Footprint | Warning | IndoorLevelNotEqualToSubterraneanFootprint | Validates that the union of all Indoor Levels, ordinal '-1' and less, is equal to the 'subterranean' Footprint referencing the same Building. |

해설: Level과 Footprint는 Level 하나가 아니라 ordinal 묶음의 합집합 단위로 비교된다. ordinal 0 Level이 하나뿐이면 그 Level과 `ground` Footprint는 같은 도형이 되는 것이 검증 기준이다. 비교 대상은 "Indoor Levels"이므로 실외 Level은 빠진다. 공유 건물에서 Footprint가 구조상 떼어낼 수 없는 공간을 포함하면(SHOULD) Level 합집합보다 커질 수 있는데, 이 경우 위 Warning과의 관계는 원문에 설명이 없다(확인 필요).

### 외벽에 대한 원문 유무

Unit·Level·Footprint 페이지 어디에도 "외벽(exterior wall)"을 따로 다룬 조항은 없다. 외벽 두께를 어느 Unit이 덮는지는 Level 외곽 = facade, Unit 합집합 = Level, 벽 일반의 단순화·`structure` 조항(5절)을 조합해 판단해야 한다.

## 5-2. 추가 수집 — Glossary·Unit Illustrative Guidance (2026-10-18 14:40)

사용자 질문 "벽을 따로 Unit으로 분리하는 경우 하나의 큰 덩어리여도 되는가, 구역마다 조각으로 나눠야 하는가" 조사 중 수집. 수집 기준에서 404로 기록한 그림 페이지는 URL 대소문자 문제였다. 올바른 경로는 https://docs.ogc.org/cs/20-094/illustrations/Unit/index.html 이다(`Illustrations`로 요청하면 404).

출처:
- OGC IMDF 1.0.0 Glossary: https://docs.ogc.org/cs/20-094/Glossary/index.html — 항목 `#structure`, `#column`, `#simplified-simplification`, `#symmetrical-difference`, `#non-public`, `#open-to-below`
- OGC IMDF 1.0.0 Unit Illustrative Guidance: https://docs.ogc.org/cs/20-094/illustrations/Unit/index.html
- 그림 파일: https://docs.ogc.org/cs/20-094/images/UnitBoundaries.png, `Sym_Difference.png`, `Sym_Difference2.png`, `ClientNonPublic.png`
- Microsoft Places, "Configure floorplans (maps)": https://learn.microsoft.com/en-us/microsoft-365/places/configure-maps-in-places — Supported IMDF files 표

### Glossary — Structure

> Unit category. "structure" models the presence and physical extent of a network of floor-to-ceiling walls or an integrated system of walls and columns.
> Illustration
> Walls and structurally integrated columns are captured as "structure" to model the physical extent of a network of floor-to-ceiling barriers.
> [그림: Sym_Difference.png]

그림 판독(이 위키의 해석): 왼쪽 위 "2D View of Venue's Structure" 삽화와 3D 투시도가 함께 있다. 외벽·내벽 전체가 한 가지 색으로 칠해져 있고, 문 자리마다 벽이 끊겨 있으며, 벽에 붙은 작은 기둥 돌출부가 벽과 한 몸으로 그려져 있다. Feature 경계 표시는 없어 Unit 개수는 그림으로 알 수 없다.

### Glossary — Column

> Unit category. "column" models the presence and physical extent of a floor-to-ceiling standalone column.
> Illustration
> A series of physical standalone columns that are not structurally integrated into a wall. These columns are candidates for capture as "column" Units. These features are particularly helpful during the survey process.

### Glossary — Simplified, Simplification

> Simplification is the process of reducing a physical, vertical barrier, of variable cross-sectional depth, to a boundary that is shared by Units. In other words, symmetrical difference does not exist among Units that reference the same Level. Additionally, symmetrical difference does not exist between the union of all Units and the referenced Level.
> Illustration
> Two different approaches to the simplification of physical, vertical barriers:
> Approach One: Follow source data that describes the "face" of a physical, vertical barrier. Left-side illustration
> Approach Two: Approximate an imaginary line running down the center of a physical, vertical barrier. Right-side illustration
> Note In both cases, the Level extent is "...analogous to the surface (facade) of the physical building at the height where the modeled floor is positioned."
> [그림: UnitBoundaries.png]

같은 문단과 그림이 Unit Illustrative Guidance > Geometry Capturing Rules > Unit Extent > Illustration 1에도 실려 있다.

그림 판독(이 위키의 해석): 두 방식 모두 가장 바깥 빨간 경계선이 외벽 띠의 바깥쪽 가장자리에 있고, 외벽 두께는 안쪽 방 Unit 경계 안에 들어가 있다. 따라서 Level 외곽 = 외벽 바깥면이며, 단순화 시 외벽 두께는 안쪽 Unit이 가진다. 파란 선은 Opening(문)이다.

### Glossary — Symmetrical Difference

> Symmetrical difference may either be unintentional or intentional.
> Unintentional symmetrical difference is the consequence of the poor "snapping" of vertices among features in or among different layers.
> Intentional symmetrical difference is a legacy map production approach. It was used to imply the existence of a physical, vertical barrier. Symmetrical difference was limited to the following feature type:
> Unit
> Illustration
> [그림: Sym_Difference2.png]
> When it is a requirement to only generally model a physical, vertical barrier, then the following Unit categories may be used:
> "structure"
> "column"
> When it is a requirement to specifically describe the material nature of the physical, vertical barrier, then the following Unit categories may be used:
> "brick" "concrete" "drywall" "glass" "wood"

해설: IMDF에서 "Unit 사이의 대칭차"는 Unit과 Unit 사이의 **빈틈**을 가리킨다. 스냅 불량으로 생긴 틈(의도하지 않음)과, 벽을 암시하려고 일부러 비워 둔 틈(예전 방식, 의도함) 두 가지다. 벽을 표현하려면 빈틈 대신 `structure`·`column`이나 재질 값 Unit을 쓴다. 5절 5번의 (a) 해석을 이 원문에 따라 정정했다.

### Glossary — Non-Public

> An area/space that contains operational, administrative, and/or management functions whose environments, if mapped, would have little or no relevance from a pedestrian standpoint.
> Illustration
> Several Units ("nonpublic" category) that define the extent of non-public spaces. For aesthetic reasons, all neighboring non-public spaces are modeled as a single feature regardless of ownership and actual physical separation.

### Glossary — Open to Below

> Unit category. "opentobelow" models the presence and physical extent of a vertical "column" of air that is visible to a pedestrian, and which extends through one or more floor of a physical building.
> Comment: The boundary of an "opentobelow" does not model a physical, vertical (floor-to-ceiling) barrier except along a Level boundary. Along with "walkway.island", "road" and "platform", this is an exception to the general rule.

### Microsoft Places — Supported IMDF files 표의 unit 행

> `unit.geojson` | Unit | Features representing spaces, walkways, and walls | Polygon, multipolygon | Rooms, workspaces, kitchenettes, restrooms, stairwells, elevators, walkways, and walls. Any space that is represented with a polygon on the map. Walls are also represented with closed polygon shapes.

### 벽 Unit 분할 단위에 대한 원문 유무

`structure` Unit을 층당 하나로 할지, 조각마다 나눌지, 구역별로 나눌지를 정한 조항은 Unit 페이지·Glossary·Illustrative Guidance·Validations 어디에도 없다. 원문이 쓰는 단위는 "a network of floor-to-ceiling walls … a "structure" Unit"(연결망 하나 = Unit 하나)이며, `nonpublic`·`walkway`와 달리 `structure`에는 병합 조항이 없다. Unit geometry는 Polygon·MultiPolygon 모두 허용된다(`UnitMustHavePolygonalGeometry`).

## 6. Category Specific Rules

### 6-1. "nonpublic"

[[src19. IMDF 비개방 구역(nonpublic) 모델링 규칙 조사]] 2절에 원문 전문이 있다. 이번 추출본과 대조해 문구가 같음을 확인했다.

### 6-2. "opentobelow"

> - A vertical column of air MUST be modeled as an "opentobelow" Unit when it is physically visible. (Illustration)
>   Although "...physically visible.", it is assumed that when this Unit touches another Unit category, the boundary models a physical barrier, but not a barrier that is floor-to-ceiling.
> - Shafts and ducts that support building operational functions, which are typically hidden from view, MUST NOT be modeled as an "opentobelow" Unit
>   - Shafts and ducts MUST be modeled as "nonpublic" Units
> - An Opening SHOULD NOT be within the boundary of a Unit whose category is "opentobelow"
>   Comment: Occasionally, this is an illusion that is the consequence of the flattening of a 3-dimensional space into a 2-dimensional view.

눈에 보이는 수직 빈 공간(아트리움 위층의 뚫린 부분 등)은 반드시 `opentobelow`(MUST). 이 Unit이 다른 Unit과 맞닿는 경계는 물리적 장벽(난간 등)이지만 바닥-천장 벽은 아니라고 가정한다. 눈에 안 보이는 샤프트·덕트는 `opentobelow`가 아니라 `nonpublic`(MUST). `opentobelow` 경계 안에는 Opening을 두지 않는다(SHOULD NOT).

### 6-3. "column"

> - A Venue Organization that captures physical, vertical barriers as explicit geometries MUST capture a column that is structurally integrated into a physical wall as a "structure" Unit. (Illustration)
> - A floor-to-ceiling standalone column captured as a "column" Unit SHOULD possess an area measurement that exceeds 0.09 square meters (exceeds 0.9 square feet). (Illustration)
>
> Comment: The survey process is reliant upon the availability of mapped objects for orientation amongst real-world physical objects. Certain features serve as a "reference network." This reference network, in combination with other mapped objects, can be leveraged to help trouble-shoot and communicate unexpected map data issues, trouble-shoot data collection issues, and assess the performance of the location-based system. In general, "column" features are only necessary in areas that are expected to be surveyed.

벽을 별도 도형으로 그리는 경우, 벽에 붙은 기둥은 `column`이 아니라 `structure`(MUST). 독립 기둥을 `column`으로 그릴 때 면적은 0.09㎡ 초과(SHOULD) — 약 30cm×30cm보다 커야 한다. 주석: 실내조사는 현실의 물체를 기준점 삼아 방향을 잡는데, 기둥 같은 객체가 그 "기준 네트워크" 역할을 한다. 그래서 `column`은 대체로 실내조사 예정 구역에서만 필요하다.

### 6-4. Vertical Traversal Capabilities

> Units that support vertical traversal capabilities are subject to the following additional restrictions.

**"elevator"**

> - Each physical elevator's floor area, in an elevator bank, MUST be modeled as an individual "elevator" Unit. (Illustration)
> - An instance of an "elevator" Unit MUST equal all other instances of the same Unit category on each Level where the presence of the same physical elevator is modeled
>   - If the prior requirement cannot be satisfied, then overlap MUST be less than 10%
>   - Overlap or disjointedness is only allowable when an incline elevator is present

엘리베이터 뱅크 안의 엘리베이터 칸마다 Unit 하나(MUST). 같은 물리 엘리베이터는 각 Level에서 같은 도형(MUST). 불가능하면 어긋남(overlap) 10% 미만(MUST). 어긋나거나 떨어지는 것은 경사형 엘리베이터만 허용.

**"escalator"**

> - Each physical escalator MUST be modeled as an individual "escalator" Unit. (Illustration)
> - "escalator" Units that reference Levels that are only one (1) ordinal apart SHOULD:
>   - Touch.
>   - Exhibit perfect alignment in the physical direction of travel. (Illustration)
>   - Model approximately half the length of the physical object
>   - If the prior requirement cannot be satisfied, then:
>     - Lengthwise, Units MAY be equal or overlap
>     - Alignment (offset) MAY exist in an amount no greater than 10%
> - "escalator" Units that reference Levels that are greater than one (1) ordinal apart MUST exhibit perfect alignment.
>   - If the prior requirement cannot be satisfied, then:
>     - Alignment (offset) MAY exist in an amount no greater than 10%
> - The presence of a physical escalator between floors SHOULD NOT be modeled. (Illustration)
> - If source data shows an escalator covering other elements in source data that are expected to be modeled, then the extent of a "escalator" Unit SHOULD be curtailed to allow other physical objects to be modeled to the fullest extent possible
> - Neighboring escalators MUST be modeled as Units that touch. (Illustration)

에스컬레이터마다 Unit 하나(MUST). ordinal이 1 차이 나는 두 Level의 에스컬레이터 Unit은 서로 맞닿고, 진행 방향으로 정렬되며, 각각 실물 길이의 약 절반을 그린다(SHOULD). 안 되면 길이가 같거나 겹쳐도 되고, 옆으로 10% 이하 어긋나도 된다(MAY). ordinal이 2 이상 차이 나면 완전 정렬(MUST), 안 되면 10% 이하 어긋남(MAY). 층 사이 공중 구간은 그리지 않는다(SHOULD NOT). 도면에서 에스컬레이터가 다른 그릴 대상을 덮고 있으면 에스컬레이터 Unit을 줄인다(SHOULD). 나란히 있는 에스컬레이터 Unit끼리는 맞닿아야 한다(MUST).

**"movingwalkway"**

> - Each physical moving walkway MUST be modeled as an individual "movingwalkway" Unit
> - Physically adjacent moving walkways MUST be modeled as Units that touch. (Illustration)

무빙워크마다 Unit 하나, 인접한 것끼리는 맞닿게(둘 다 MUST).

**"ramp"**

> - A grade that supports a vertical traversal capability to a different Level SHOULD be modeled as a "ramp" Unit
> - A grade along the same floor (no vertical traversal capability to a different Level), MAY be modeled as a "ramp" Unit when they exist as an alternative to steps, mini-escalators and elevators. Else, the grade MUST be modeled as a "walkway" Unit. Illustration
> - Modeling a grade as a "walkway" Unit is preferable when the following are true:
>   - The Venue Organization derives no business value from capturing grades as individual "ramp" Units.
>   - The map application user "experience" is not diminished by their absence
>   - The map's aesthetic quality is enhanced by the presentation of a contiguous system of walkable areas
>   - The conscious, physical "experience" of the grade by a pedestrian, particularly among persons with disabilities, would likely elicit an emotional response that is no different in a circumstance where the grade had been captured as a "ramp", instead of a "walkway"
> - When a grade and a set of risers are structurally integrated, then the entire structure SHOULD be modeled as a "ramp" Unit. (Illustration)

다른 Level로 이어지는 경사로는 `ramp`(SHOULD). 같은 층 안 경사로는 계단·미니 에스컬레이터·엘리베이터의 대안일 때만 `ramp`(MAY), 아니면 `walkway`(MUST). `walkway`로 두는 편이 나은 조건 네 가지(업무 가치 없음, 앱 경험 손실 없음, 연속된 보행 구역이 더 보기 좋음, 장애가 있는 보행자의 체감 차이 없음). 경사로와 계단 단(riser)이 일체 구조면 전체를 `ramp`(SHOULD).

**"stairs"**

> - A stairwell that supports a vertical traversal capability to a different Level MUST be modeled as a "stairs" Unit
> - Visible open space that extends vertically through the stairwell SHOULD be included within the "stairs" Unit. Else, it MAY be modeled as an "opentobelow" Unit
> - If source data shows a staircase and/or landing covering other elements in source data that are expected to be modeled, then the extent of a "stairs" Unit SHOULD be curtailed to allow other physical objects to be modeled to the fullest extent possible

다른 Level로 이어지는 계단실은 `stairs`(MUST). 계단실을 수직으로 관통하는 빈 공간은 `stairs` Unit에 포함(SHOULD), 아니면 `opentobelow`로 분리(MAY). 계단·참이 다른 그릴 대상을 덮으면 `stairs` 범위를 줄인다(SHOULD).

**"steps"**

> - A set of steps along a pedestrian pathway, on the same floor (modeled as the same Level), MUST be modeled as a "steps" Unit when any of the following are true:
>   - The steps are unavoidable. A pedestrian must use them in order to reach an area
>   - The steps are architecturally significant. Modeling the physical object heightens cognitive recognition and improves the pedestrian's ability to relate the map view to the physical one when present in the Venue itself
>   - Modeling the steps as a "steps" Unit improves environmental awareness among pedestrians with a disability. This is especially important among persons with a sight disability that may rely upon map application vocalization of information about obstacles that lay in their direction of travel. (Illustration)

같은 층 보행로 위 단차 계단은 다음 중 하나면 `steps`(MUST): (1) 피할 수 없음, (2) 건축적으로 눈에 띔(지도와 현장을 대응시키기 쉬워짐), (3) 장애가 있는 보행자, 특히 음성 안내에 의존하는 시각장애인의 장애물 인지에 도움이 됨. 다른 Level로 가면 `stairs`, 같은 Level 안이면 `steps`로 구분된다.

### 6-5. "walkway"

> - As a general rule, a "walkway" Unit MUST model a pathway whose design and intended purpose is to facilitate pedestrian movement through a Venue. (Illustration)
> - "walkway" Units that touch which reference the same Level SHOULD be merged when:
>   - A comparison of the physical characteristics generates no distinct differences
>   - A door or other physical barrier does not exist where "walkway" Units touch
>   - A physical door exists but modeling the door as an Opening offers no derivable benefit
>
>   Comment: A decision to not model entrances along a pathway should take into consideration the map application "experience." A possible negative "experience" might stem from a pedestrian's inability to judge their location on the map if the approach taken was to capture a pathway as a single contiguous Unit
> - "walkway" Units that touch SHOULD NOT be merged when:
>   - A physical door exists whose access is controlled
> - The presence of a pedestrian service/function along a pathway SHOULD not alter the modeling approach when the purpose of the pathway, in the majority, is to facilitate the movement of a pedestrian through the Venue. (Illustration)
> - When an area is interpreted as being equally a pedestrian destination and a pathway, then the area SHOULD be modeled as a "room" Unit. This modeling approach is preferable when:
>   - A comparison of the service/function of one area with another area reveals distinct differences in their associated descriptive properties
>   - Separation of distinct areas is facilitated by the presence of a physical, vertical barrier.
>   - A preference exists to enclose the "distinct differences"
> - When an area is equally a pedestrian destination and a pathway but the separation of areas is not facilitated by the presence of a physical, vertical barrier, then the area SHOULD be modeled as a "walkway" Unit. This modeling approach is preferable when:
>   - The primary function of the area is to support/contain pedestrian destinations. A secondary function of the area is to support pedestrian travel along an inferable pathway. (Illustration)
> - When neither pedestrian destinations nor pathways are inferable, then the area SHOULD be modeled as a "walkway" Unit. This modeling approach is preferable when area utilization is dynamic. Example: An Exhibition or Convention Center

- `walkway`는 보행자 이동을 위해 설계된 통로(MUST).
- 같은 Level에서 맞닿은 `walkway`는 병합(SHOULD) — 물리적 특성 차이가 없거나, 맞닿는 곳에 문·장벽이 없거나, 문은 있지만 Opening으로 그려도 얻는 것이 없을 때. 주석: 통로 전체를 Unit 하나로 그리면 보행자가 지도에서 자기 위치를 가늠하기 어려워질 수 있으니 앱 경험을 고려하라.
- 출입 통제 문이 있으면 병합하지 않는다(SHOULD NOT).
- 통로 옆에 서비스(예: 키오스크)가 있어도 주 목적이 이동이면 `walkway` 그대로(SHOULD).
- 목적지이자 통로인 구역: 물리적 장벽으로 나뉘고 기능 차이가 뚜렷하면 `room`(SHOULD), 장벽 없이 이어져 있으면 `walkway`(SHOULD).
- 목적지도 통로도 추론할 수 없는(용도가 수시로 바뀌는) 구역 — 전시장·컨벤션 센터 — 은 `walkway`(SHOULD).

## 7. Validations — Unit 항목

OGC Validations 페이지의 표에서 feature가 Unit인 행 전부(17건):

| severity | rule | 원문 설명 |
| --- | --- | --- |
| Violation | AccessibilityMustBeValid | Validates the accessibility category assigned to the feature. |
| Violation | AltNameMustBeString | Validates that an alt_name is a string data type. |
| Violation | DisplayPointMustBePointGeometry | Validates that a display_point is a point geometry type. |
| Violation | InvalidFeatureID | Validates that a feature ID is a valid v4 UUID value. |
| Violation | InvalidLanguageTag | Validates that a language tag is a valid value. |
| Violation | LabelMustNotBeBlank | Validates that a Label (prefLabel and altLabel) is not blank. |
| Violation | NameMustBeString | Validates that a name is a string data type. |
| Violation | RestrictionCategoryMustBeValid | Validates the category assigned to a Restriction. |
| Violation | UnitCategoryMustBeValid | Validates the category assigned to a Unit. |
| Violation | UnitMustBeCoveredByReferencedLevel | Validates that a Unit is covered by the referenced Level. |
| Violation | UnitMustHaveCategory | Validates that a Unit has a category. |
| Violation | UnitMustHavePolygonalGeometry | Validates that a Unit has Polygon or MultiPolygon geometry. |
| Violation | UnitMustReferenceLevel | Validates that a Unit references a Level. |
| Warning | AltNameLangTagHasNoCorrespondingNameLangTag | Validates that a language tag associated with an alt_name has a corresponding presence and association with a name value. |
| Warning | HasOnlyAltName | Validates that an alt_name value is not exclusive, that it is accompanied by a name value. |
| Warning | UnitGeometryMustContainDisplayPoint | Validates that a display_point, if present, is contained by the Unit. |
| Warning | UnitsMustNotOverlap | Validates that Unit interiors do not intersect. |

관찰:

- Unit끼리 겹침(`UnitsMustNotOverlap`)은 Violation이 아니라 **Warning**으로 분류되어 있다. 반면 WWDC19 데모에서는 Sandbox가 Unit 겹침을 "error"로 보여 주며 "it cannot have any errors"라고 설명한다. OGC 표와 2019년 Sandbox 동작이 다르다(어느 쪽이 현재 Apple 검수 기준인지 확인 필요).
- "Unit 합집합 = Level"의 빈틈 쪽(Level 안인데 어떤 Unit도 덮지 않은 부분)은 Unit 항목이 아니라 Level 항목 `LevelMustBeFullyCoveredByUnits`(Warning)가 잡는다(7-2절). 삐져나감 쪽은 `UnitMustBeCoveredByReferencedLevel`(Violation)이 잡는다.
- `HasOnlyAltName`: alt_name만 있고 name이 없으면 Warning.

### 7-1. Unit을 참조·포함 관계로 검사하는 다른 Feature의 항목

| feature | severity | rule | 원문 설명 |
| --- | --- | --- | --- |
| Opening | Warning | OpeningMustBeCoveredByUnitBoundary | Validates that an Opening is covered by a Unit's boundary. |
| Amenity | Violation | AmenityMustReferenceUnit | Validates that an Amenity references a Unit. |
| Amenity | Warning | AmenityShouldBeCoveredByReferencedUnit | Validates that an Amenity is covered by the referenced Unit. |
| Amenity | Warning | ElevatorUnitMayOnlyContainElevatorAmenity | Validates that an Amenity, if present and contained (or touched) by an 'elevator' Unit, is an 'elevator' Amenity and not any other category of Amenity. |
| Amenity | Warning | EscalatorUnitMayOnlyContainEscalatorAmenity | (escalator Unit 안에는 escalator Amenity만) |
| Amenity | Warning | MovingWalkwayUnitMayOnlyContainMovingWalkwayAmenity | (movingwalkway Unit 안에는 movingwalkway Amenity만) |
| Amenity | Warning | StairsUnitMayOnlyContainStairsAmenity | (stairs Unit 안에는 stairs Amenity만) |
| Amenity | Warning | StepsUnitMustNotContainAmenity | Validates that an Amenity is not contained (or touched) by a 'steps' Unit. |
| Amenity | Warning | OpenToBelowUnitMustNotContainAmenity | Validates that an Amenity is not contained (or touched) by an 'opentobelow' Unit. |
| Amenity | Warning | StructuralUnitMustNotContainAmenity | Validates that an Amenity is not contained (or touched) by a Unit that models physical/structural elements, such as 'brick', 'column', 'concrete', 'drywall', 'glass', 'structure', and 'wood'. |
| Amenity | Info/Warning | 화장실 계열 5건 | `restroom` Unit 안의 세부 화장실 Amenity(Info), `restroom.female`·`restroom.male` Unit 안의 다른 성별 Amenity(Warning) 등 |
| Anchor | Violation | AnchorMustReferenceUnit / AnchorMustBeCoveredByReferencedUnit | Anchor는 Unit을 참조하고 그 안에 있어야 한다 |
| Anchor | Warning | OpenToBelowUnitMustNotContainAnchor / StructuralUnitMustNotContainAnchor | `opentobelow`·구조체 Unit 안에 Anchor 금지 |

괄호 안 설명은 원문 문장을 줄인 것이다.

### 7-2. Level 쪽에서 Unit을 검사하는 항목

| feature | severity | rule | 원문 설명 |
| --- | --- | --- | --- |
| Level | Violation | LevelMustBeReferencedByUnit | Validates that a Level is referenced by at least one Unit. |
| Level | Warning | LevelMustBeFullyCoveredByUnits | Validates that the union of all Units is equal to the Level they reference. |
| Level | Warning | ParkingLevelShouldContainParkingUnit | Validates that a 'parking' Level contains a 'parking' Unit. |
| Level | Warning | ParkingUnitShouldBeContainedByParkingLevel | Validates that a Level containing a 'parking' Unit, and no other Unit, is categorized as a 'parking' Level. |

"Unit 합집합 = Level" 규칙(5절 5번 (b))의 검증은 `LevelMustBeFullyCoveredByUnits`(Warning)다. 빈틈과 삐져나감을 함께 본다. 삐져나감은 Unit 쪽 `UnitMustBeCoveredByReferencedLevel`(Violation)이 한 번 더 잡는다.

## 8. IMDFrnt 앱과의 대조 (2026-10-18, 레포 `bec89f3` 기준)

- `IM-DFrnt/Sources/IMDFrnt/Model/PropertySchema.swift:173~182` — Unit 필드: `category`(.string, 드롭다운), `name`(.localizedName), `alt_name`(.alwaysNull), `level_id`(.reference(.level)), `restriction`(.alwaysNull), `display_point`(.point, 편집 불가), `accessibility`(.alwaysNull), 그리고 맨 앞에 `id`(내보내기 시 UUID v4).
  - 스펙의 Property Keys 7개가 모두 있다. 필수인 `category`·`level_id`는 입력 가능하다.
  - `restriction`·`accessibility`·`alt_name`은 항상 null이다. 스펙상 null 허용이라 위반은 아니지만, `restricted`가 필요한 공간(라운지 등)이나 휠체어 접근성 표시는 지금 입력 수단이 없다.
- `PropertySchema.swift:239~260` — Unit category 드롭다운 65종(src11 대조값). 재질 값 주석은 "스펙에 용법 설명이 없다(확인 필요)"로 되어 있는데, 이번 조사로 Geometry Capturing Rules에 근거가 확인됐다(5절 4번).
- `Store/Stores.swift:375~` `OpeningGateStore` — Opening을 다른 type보다 먼저 태깅하게 하는 게이트. 이유는 "실제 도면의 방은 문 자리에서 벽이 끊겨 있어, 문 선분으로 링을 닫아야 하기 때문"이다. 스펙의 "An Opening MUST be covered by a Unit boundary"와 방향이 맞는다.
- `Geometry/OverlapDetector.swift` — 선택한 개체가 다른 벡터와 겹치는 곳을 표시한다. 꼭짓점 접합은 겹침으로 보지 않는다. Unit 폴리곤끼리 내부 겹침(`UnitsMustNotOverlap`)을 내보내기 전에 검사하는지는 이번에 확인하지 않았다(확인 필요).
- 이 레포 코드는 수정하지 않았다.

## 9. 남은 확인 사항

- ~~Unit Illustrative Guidance 그림(링크 404)~~ — 해소(5-2절). 에스컬레이터·display_point 묶음 그림은 미판독.
- ~~대칭차 조항 (a)의 정확한 의미~~ — 해소: 빈틈 금지(5-2절).
- `structure` Unit을 실제 IMDF 데이터에서 층당 1개로 만드는지 조각별로 만드는지 — 샘플 데이터 미확인.
- `UnitsMustNotOverlap`이 Warning인데 Apple 검수에서 Unit 겹침을 반려 사유로 보는지.
- ~~Level 외곽이 외벽 바깥면인지 안쪽 면인지~~ — 해소: 바깥면(5-2절 UnitBoundaries 그림).
- Validations 표의 Violation/Warning 구분이 Apple Maps Connect 검수의 반려 기준과 같은지.
