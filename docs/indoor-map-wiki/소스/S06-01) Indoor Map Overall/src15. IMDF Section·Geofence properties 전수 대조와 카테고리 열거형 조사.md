---
summary: "OGC IMDF 1.0.0의 Section·Geofence Feature Type 페이지 원문을 직접 취득해 두 타입의 properties 표를 한 칸도 빠짐없이 전수 대조하고, SECTION-CATEGORY 71종·GEOFENCE-CATEGORY 8종을 알파벳 순 전량 확보. Validations 페이지의 두 타입 검증 규칙까지 수집해 앱 PropertySchema와의 누락 필드를 판정"
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0 Community Standard) — Section, Geofence, Categories, Reference, Validations 페이지 원문(HTML 직접 취득)"
created: "2026-08-29 00:00"
updated: "2026-08-29 00:00"
---
# IMDF Section·Geofence properties 전수 대조와 카테고리 열거형 조사

## 수집 기준

- 수집일: 2026-08-29
- 목적: FP-to-IMDF 앱의 `~/Desktop/IM-DFrnt/Sources/IMDFrnt/Model/PropertySchema.swift:183~195`에 다음 미해결 주석이 남아 있다.

  ```swift
  case .section:
      // src11 3.7 — geometry Polygon. "A Section models the presence and approximate
      // extent of a theme." properties는 category·name·alt_name·display_point "등"까지만
      // 확인됨(전수 미대조, 확인 필요).
  ```

  `src11`(2026-08-20)은 16종 Feature Type을 훑는 과정에서 Section·Geofence의 properties를 "등"으로 줄여 기록했다. 앱은 이 스키마로 우측 인스펙터의 입력 슬롯과 category 드롭다운을 그리므로, **스키마에 없는 필드는 사용자가 입력할 방법 자체가 없는 필드**가 된다. 이 문서의 존재 이유는 그 "등"을 제거하는 것이다.
- 방법: WebFetch는 요약 모델을 거치기 때문에 표 전체를 원문대로 돌려주지 않는다(Section 페이지 조회 시 "properties table 있음, 값은 나열하지 않음" 식의 요약만 반환되었다). 따라서 **`curl`로 각 페이지의 HTML을 직접 내려받아 태그를 제거하고 표의 셀을 그대로 추출**하는 방식으로 전환했다. 아래 표·열거값·규칙은 모두 그 원문 추출 결과다.
- 취득한 페이지: Section, Geofence, Categories, Reference, Validations (5개, 전부 본문 취득 성공). 본문 취득에 실패한 URL은 없다. `register.apple.com/resources/imdf/`는 SPA 구조라 여전히 본문 추출 불가이며, 이번 조사에서는 시도하지 않았다(src04·src11에서 확인된 제약 그대로).
- src11과의 관계: src11 2절이 확보한 열거값과 5절의 종합표를 전제로 삼되, Section·Geofence 두 타입에 대해서는 **properties 표 전체·Property Capturing Rules·Geometry Capturing Rules·Validations 규칙**까지 내려간다. src11이 "약 70"으로 기록한 SECTION-CATEGORY 개수도 이번에 정확히 세었다.

## 핵심 출처

- Section: https://docs.ogc.org/cs/20-094/Section/index.html
- Geofence: https://docs.ogc.org/cs/20-094/Geofence/index.html
- Categories: https://docs.ogc.org/cs/20-094/Categories/index.html (`#section`, `#geofence` 앵커)
- Reference(타입 지정자·DISPLAY-POINT·참조 ID): https://docs.ogc.org/cs/20-094/Reference/index.html
- Validations(검증 규칙·심각도): https://docs.ogc.org/cs/20-094/Validations/index.html
- 선행 문서: `src11. IMDF 공식 스펙 — Feature Type 16종·카테고리 열거형 전수 조사.md` (2절 열거형, 3.7·3.8절, 5절 종합표)

---

## 1. Section — Feature Structure와 properties 전수

### 1.1 정의와 구조 규정 (원문)

> A Section models the presence and approximate extent of a theme. The boundary of a theme may be a threshold or an indeterminate border.

Feature Structure 규정 4줄, 원문 그대로:

> - Section objects are Feature objects
> - Section objects **MUST** have an `"id"` member with a `FEATURE-ID` value
> - Section objects **MUST** have a `"feature_type"` member with the value `"section"`
> - Section objects **MUST** have a `"geometry"` member with a `POLYGONAL` value

세 번째 줄이 중요하다. `feature_type` 값은 소문자 `"section"`으로 고정이며, Reference 페이지의 FEATURE-TYPE 절도 16개 값을 **case-sensitive**로 못 박는다. 네 번째 줄의 `POLYGONAL`은 Reference 페이지 Geometry Type Designators 표에서 "POLYGON or MULTI-POLYGON"으로 정의된다(6절 참조). 즉 Section geometry는 **Polygon 단독이 아니라 MultiPolygon도 허용**된다. src11 3.7절이 "geometry: Polygon"으로 적은 것은 정확하지 않다.

### 1.2 Property Keys 표 (원문 10행 전수)

스펙 표의 열은 Property / Type / Description 셋이다. 아래는 10개 행 전부이며, 한 행도 생략하지 않았다.

| Property | Type | Description (원문) | 한국어 해설 |
| --- | --- | --- | --- |
| `category` | `SECTION-CATEGORY` | The category that best describes the function of the Section | Section의 기능을 가장 잘 설명하는 카테고리. **타입에 `null or`가 붙지 않은 유일한 두 필드 중 하나** — 즉 null 불가, 사실상 필수 |
| `restriction` | `null` or `RESTRICTION-CATEGORY` | The category that best describes a restriction that applies to the entire Section | Section 전체에 적용되는 출입 제한. 값은 `employeesonly`·`restricted` 2종(src11 2.13절) |
| `accessibility` | `null` or JSON array of `ACCESSIBILITY-CATEGORY` | Indicates the type of accessibility provided by the Section to a pedestrian that experiences disabilities | 장애를 가진 보행자에게 이 Section이 제공하는 접근성 유형. **단일 값이 아니라 배열**이다. 값은 10종(src11 2.2절) |
| `name` | `null` or `LABELS` | The name of the Section as declared by the Venue Organization | Venue 운영주체가 선언한 이름. LABELS는 언어 태그를 키로 갖는 JSON 객체 |
| `alt_name` | `null` or `LABELS` | Alternative name for the Section that may be recognized by the Venue Organization | 운영주체가 인지하는 대체 이름 |
| `display_point` | `null` or `DISPLAY-POINT` | The curated location to use as the point-based representation of the Section | 점 기반 대표 위치. 요건은 6절 |
| `level_id` | `LEVEL-ID` | Unique identifier of the Level the Section possesses a spatial relationship with | 공간적 관계를 갖는 Level의 ID. **`null or`가 없다 — category와 함께 null 불가** |
| `address_id` | `null` or `ADDRESS-ID` | ID reference to Address record | Address 레코드 참조 |
| `correlation_id` | `null` or `UUID` | Correlation ID shared among similar Sections that occupy different floors of the physical Venue | **서로 다른 층에 걸쳐 있는 동일 성격의 Section들을 하나로 묶는 UUID.** "different floors"라는 문구가 명시적이다 |
| `parents` | `null` or JSON array of `SECTION-ID` | Unique identifier of the Section(s) that this Section possesses a child→parent relationship with | 이 Section이 자식→부모 관계를 갖는 상위 Section들의 ID 배열 |

정리하면 Section의 properties는 **10개**이고, 그중 **null이 허용되지 않는 것은 `category`와 `level_id` 둘**이다. 나머지 8개는 모두 `null or ...` 형태다.

> 주의 — 스펙 표는 `MUST`/`MAY`라는 단어를 property 행에 직접 쓰지 않는다. 필수 여부는 (a) Feature Structure의 `MUST` 문장, (b) 타입 열의 `null or` 유무, (c) Validations 페이지의 `...MustHave...` 규칙 세 곳을 겹쳐 읽어야 확정된다. 세 근거가 모두 `category`와 `level_id`를 가리킨다(1.5절).

### 1.3 스펙 예제 (원문 그대로)

```json
{
  "id": "11111111-1111-1111-1111-111111111111",
  "type": "Feature",
  "feature_type": "section",
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
    "category": "parking",
    "restriction": "restricted",
    "accessibility": "wheelchair",
    "name": {
      "en": "Parking"
    },
    "alt_name": null,
    "display_point": {
      "type": "Point",
      "coordinates": [ 100.0, 1.0 ],
    },
    "level_id": "22222223-2222-2222-2222-222222222222",
    "address_id": null,
    "correlation_id": null,
    "parents": ["44444444-4444-4444-4444-444444444444"]
  }
}
```

이 예제에는 스펙 자체의 오류가 두 군데 있다. 하나는 `display_point`의 `"coordinates": [ 100.0, 1.0 ],` 뒤에 붙은 **후행 쉼표**로, 엄밀한 JSON 파서라면 거부한다. 다른 하나는 `accessibility`가 표에서는 "JSON array of ACCESSIBILITY-CATEGORY"인데 예제에서는 `"wheelchair"`라는 **문자열 스칼라**로 적혀 있다는 점이다. 구현 시에는 표의 규정(배열)을 따르는 것이 옳다. 예제를 그대로 신뢰하면 안 된다는 사례로 기록해 둔다.

### 1.4 Property Capturing Rules (원문 전수)

> **CORRELATION_ID**
> - MUST be present when the intent is to create an association between multiple Sections
>
> **PARENTS**
> - MAY reference a Section
> - MUST NOT reference any other feature type
> - MUST NOT contain duplicate entries
> - MUST NOT be self-referential
> - MUST NOT introduce circular dependencies between Sections
> - MUST reference the `id` of a Section when the intent is to create a child→parent relationship
> - MUST only reference a parent, NOT a child

`parents`에 걸린 제약은 7줄로, Geofence의 같은 필드보다 훨씬 촘촘하다. 특히 마지막 두 줄이 방향성을 못 박는다 — 배열에는 **부모만** 넣고 자식을 넣어서는 안 된다. 자기 참조 금지와 순환 의존 금지는 트리 구조를 강제하는 조항이다.

### 1.5 Geometry Capturing Rules (원문 전수)

Section의 Geometry Capturing Rules는 다른 Feature Type과 성격이 다르다. 좌표 정확도가 아니라 **"테마의 범위를 어디까지로 볼 것인가"라는 개념적 판단 절차**를 규정한다.

> **Section Extent**
>
> The Venue Organization **SHOULD NOT**, at first, be overly concerned with Units, Kiosks, and Fixtures that could or should be within a Section. The Venue Organization **SHOULD** first assess the physical environment and attempt to conceptualize a Section's extent as an operational and psychological theme:
>
> - **Venue Infrastructure & Operations** — Physical infrastructure and facilities that exist in support of the operational theme. This includes the personnel and equipment that exist to support manned, semi-automated and automated operations within the physical environment that would not otherwise exist if the underlying business function(s) did not exist
> - **Business Services & Amenities** — Business services, amenities, facilities, and utilities that exist solely for use by a pedestrian as they pass through and/or when they temporarily remain within the conceptual extent of the operational theme
> - **Traversal Capabilities** — Equipment and physical structures that convey a pedestrian into and out of the physical environment that would not otherwise exist if the business function(s) did not exist
>
> Psychology. The Venue Organization **MUST** take into account:
>
> - The pedestrian's perception of reality and conceptualize a thematic extent that includes feature types that a pedestrian would "naturally" associate with the operational theme
> - The pedestrian's conscious awareness and their belief about where they are physically located in a Venue and how tightly coupled that belief is to the proposed extent of an operational theme
>
> - A Section **SHOULD** model a theme whose interpreted extent is entirely or only partially enclosed by physical, vertical barriers. (Illustration)
> - Depending upon the map context, "gaps" **MAY** exist among Sections to facilitate visibility of the underlying "walkway" Unit that is intended for pedestrian use. (Illustration)
> - An Opening **SHOULD NOT** be used to model an entrance to a Section
>   - Occasionally, this is an illusion that is the consequence of a Unit legitimately requiring an Opening, and the Unit covers the boundary of a Section.

세 가지가 실무에 직접 걸린다. 첫째, Section 범위는 안에 무엇이 들어가는지(Unit·Kiosk·Fixture)를 먼저 따지지 말고 **운영 테마 단위로 먼저 그리라**는 순서 규정이 있다. 둘째, 보행자의 심리적 인지 범위를 `MUST` 수준으로 고려하라고 요구한다 — IMDF 전체에서 드문 종류의 조항이다. 셋째, **Section에는 Opening(출입구)을 붙이지 않는다.** 앱이 "문 빌려주기" 대상 판정에 `requiredGeometry == .polygon`을 쓰고 있는데(`IMDFFeatureType.swift:42~47`), 그 기준대로면 Section도 Opening을 빌려받는 대상에 포함된다. 스펙은 이를 `SHOULD NOT`으로 금지한다. 7절에서 다시 다룬다.

### 1.6 Validations 페이지의 Section 규칙 (원문 23행 전수)

| 심각도 | 규칙 | 정의(원문) |
| --- | --- | --- |
| Info | `SectionHasInteriorRing` | Validates that a Section does not possess an interior ring. |
| Info | `SectionHasParentReference` | Validates that a Section has a parent reference. |
| Info | `SectionsOverlap` | Validates that Section interiors do not intersect on the same Level. |
| Violation | `AccessibilityMustBeValid` | Validates the accessibility category assigned to the feature. |
| Violation | `AltNameMustBeString` | Validates that an alt_name is a string data type. |
| Violation | `CorrelationIdMustBeMatched` | Validates that a correlation_id is matched by at least one other feature's correlation_id in the same feature-type. |
| Violation | `DisplayPointMustBePointGeometry` | Validates that a display_point is a point geometry type. |
| Violation | `InvalidCorrelationID` | Validates that a 'correlation_id' is a valid v4 UUID value. |
| Violation | `InvalidFeatureID` | Validates that a feature ID is a valid v4 UUID value. |
| Violation | `InvalidLanguageTag` | Validates that a language tag is a valid value. |
| Violation | `LabelMustNotBeBlank` | Validates that a Label (prefLabel and altLabel) is not blank. |
| Violation | `LevelIDsMustBeDissimilarForCorrelationID` | Validates that features from the same feature-type, whose correlation_id match, possess dissimilar Level id values. |
| Violation | `NameMustBeString` | Validates that a name is a string data type. |
| Violation | `RestrictionCategoryMustBeValid` | Validates the category assigned to a Restriction. |
| Violation | `SectionCategoryMustBeValid` | Validates the category assigned to a Section. |
| Violation | `SectionMustBeCoveredByReferencedLevel` | Validates that a Section is covered by the referenced Level. |
| Violation | `SectionMustHaveCategory` | Validates that a Section has a category. |
| Violation | `SectionMustHavePolygonalGeometry` | Validates that a Section has a Polygon or MultiPolygon geometry. |
| Violation | `SectionMustReferenceLevel` | Validates that a Section references a Level. |
| Warning | `AltNameLangTagHasNoCorrespondingNameLangTag` | Validates that a language tag associated with an alt_name has a corresponding presence and association with a name value. |
| Warning | `CategoryShouldBeSameForCorrelationID` | Validates that features with matching correlation_id possess the same category. |
| Warning | `HasOnlyAltName` | Validates that an alt_name value is not exclusive, that it is accompanied by a name value. |
| Warning | `SectionGeometryMustContainDisplayPoint` | Validates that the display_point is within its Section. |

`SectionMustHaveCategory`와 `SectionMustReferenceLevel`이 둘 다 `Violation` 등급이라는 사실이, 1.2절 표에서 `null or`가 없던 두 필드가 실제로 필수라는 것을 교차 확인해 준다. `CorrelationIdMustBeMatched`와 `LevelIDsMustBeDissimilarForCorrelationID`를 함께 읽으면 `correlation_id`의 용법이 확정된다 — **같은 값을 가진 Section이 최소 둘 이상 있어야 하고, 그것들은 서로 다른 `level_id`를 가져야 한다.** 층을 가로지르는 묶음이라는 표 설명과 정확히 맞물린다. 혼자만 가진 `correlation_id`는 그 자체로 위반이다.

## 2. Geofence — Feature Structure와 properties 전수

### 2.1 정의와 구조 규정 (원문)

> A Geofence models the extent of a geofence.

src11 3.8절의 관찰이 이번에도 그대로 확인된다. **정의가 동어반복 한 줄뿐이며, 목적·용도를 설명하는 문단도 Geometry Capturing Rules 절 자체도 없다.** Section이 Geometry Capturing Rules에 긴 개념 규정을 붙인 것과 대조적이다. Geofence의 의미는 GEOFENCE-CATEGORY 열거값(4절)과 Property Capturing Rules(2.4절)에서 역으로 추정할 수밖에 없다.

> - Geofence objects are Feature objects
> - Geofence objects **MUST** have an `"id"` member with a `FEATURE-ID` value
> - Geofence objects **MUST** have a `"feature_type"` member with the value `"geofence"`
> - Geofence objects **MUST** have a `"geometry"` member with a `POLYGONAL` value

### 2.2 Property Keys 표 (원문 9행 전수)

| Property | Type | Description (원문) | 한국어 해설 |
| --- | --- | --- | --- |
| `category` | `GEOFENCE-CATEGORY` | The category that best describes the function of the Geofence | **`null or`가 없는 유일한 필드 — Geofence의 유일한 필수 property다.** src11 3.8절의 기록이 옳았음이 확인된다 |
| `restriction` | `null` or `RESTRICTION-CATEGORY` | The category that best describes a restriction that applies to the entire Geofence | Geofence 전체에 적용되는 출입 제한 |
| `name` | `null` or `LABELS` | The official name for the Geofence as declared by the Venue Organization | Section이 "The name of"인 데 반해 Geofence는 **"The official name for"**로 표현이 다르다 |
| `alt_name` | `null` or `LABELS` | Alternative name for the Geofence | Section 쪽 설명에 붙어 있던 "that may be recognized by the Venue Organization" 단서가 여기에는 없다 |
| `correlation_id` | `null` or `UUID` | Correlation ID shared among Geofences | Section과 달리 **"different floors" 단서가 없다.** 층 교차 조건 없이 그냥 Geofence들 사이에서 공유된다 |
| `display_point` | `null` or `DISPLAY-POINT` | The curated location to use as the point-based representation of the Geofence | Section과 동일 문구 |
| `building_ids` | `null` or JSON array of `BUILDING-ID` | Unique identifier(s) of the Building(s) the Geofence possesses an explicitly defined relationship with | **Section에는 없는 필드.** 복수 Building 참조 |
| `level_ids` | `null` or JSON array of `LEVEL-ID` | Unique identifier(s) of the Level(s) the Geofence possesses an explicitly defined relationship with | **Section의 `level_id`(단수·필수)와 결정적으로 다르다** — 복수 배열이며 nullable |
| `parents` | `null` or JSON array of `GEOFENCE-ID` | Unique identifier(s) of the Geofence(s) that this Geofence possesses an explicitly defined child→parent relationship(s) with | 상위 Geofence 배열 |

Geofence의 properties는 **9개**다. `address_id`와 `accessibility`가 없고, 대신 `building_ids`가 있으며 Level 참조가 복수형이다. Section이 "특정 한 층 위에 놓인 테마 영역"인 반면 Geofence는 **층·건물을 가로질러 걸치는 영역**이라는 성격 차이가 필드 설계에 그대로 드러난다.

### 2.3 스펙 예제 (원문 그대로)

```json
{
  "id": "11111111-1111-1111-1111-111111111111",
  "type": "Feature",
  "feature_type": "geofence",
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
    "category": "geofence",
    "restriction": "employeesonly",
    "name": {
      "en": "Employee Parking"
    },
    "alt_name": null,
    "correlation_id": null,
    "display_point": {
      "type": "Point",
      "coordinates": [100.0, 0.0]
    },
    "building_ids": ["2222222-2222-2222-2222-222222222222"],
    "level_ids": [
      "33333333-3333-3333-3333-333333333333",
      "44444444-4444-4444-4444-444444444444"
    ],
    "parents": null
  }
}
```

이 예제에도 스펙 자체의 오류가 있다. `building_ids`의 값 `"2222222-2222-2222-2222-222222222222"`는 첫 그룹이 7자리로, **UUID v4 형식(8-4-4-4-12)을 만족하지 않는다.** `InvalidFeatureID` 규칙에 걸릴 값이다. `display_point`의 좌표 `[100.0, 0.0]`이 폴리곤의 꼭짓점 위에 놓여 있는 것도 `GeofenceGeometryMustContainDisplayPoint`("within the Geofence") 해석에 따라 경계 사례가 된다. 1.3절과 마찬가지로, 스펙 예제를 테스트 픽스처로 그대로 쓰면 안 된다.

### 2.4 Property Capturing Rules (원문 전수)

> **BUILDING_IDS**
> Building references are supported to enable the explicit association of a Geofence and one or more Building.
> - MUST NOT contain duplicate entries
> - MUST be assumed to apply to ALL Levels of a referenced Building, including all content within or associated with those Levels, unless constrained by explicit specification of `"level_ids"`
> - MUST reference Buildings with Footprint geometries that are entirely or partially within the Geofence's polygonal geometry
>
> **LEVEL_IDS**
> Level references are supported to enable the explicit association of a Geofence and one or more Levels, typically for the purpose of constraining the applicable Levels of a Building declared in `"building_ids"`.
> - MUST NOT contain duplicate entries
> - MUST be assumed to apply to ALL all content within, or associated with, the specified Level(s) OR the portion of those Level(s) that the Geofence's polygonal geometry overlaps
> - MUST reference Levels with geometries that are entirely or partially within the Geofence's polygonal geometry
>
> **CORRELATION_ID**
> - MUST be present when the intent is to create an association between multiple Geofences
>
> **PARENTS**
> Parent references are supported to enable the creation of hierarchical Geofences where necessary.
> - MUST NOT contain duplicate entries
> - MUST NOT be self-referential
> - MUST NOT introduce circular dependencies between Geofences

(LEVEL_IDS 두 번째 항목의 "ALL all"은 스펙 원문의 오타를 그대로 옮긴 것이다.)

이 절이 Geofence의 의미를 사실상 정의한다. **`building_ids`만 지정하면 그 건물의 전 층에 적용되고, `level_ids`를 함께 쓰면 적용 층을 그 목록으로 좁힌다.** 즉 Geofence는 "공간 폴리곤 + 적용 범위(건물·층) 선언"의 조합으로 동작하는, 정책·구역 지정용 피처다. Section이 지도 위에 그려지는 시각적 테마라면 Geofence는 적용 대상을 명시적으로 열거하는 **규칙 영역**에 가깝다. 스펙이 정의문에서 말하지 않은 이 성격은 이 규칙들에서만 읽어낼 수 있다.

`parents` 제약은 Section보다 3줄 적다. Section에 있던 "MUST NOT reference any other feature type", "MUST reference the id of a Section when...", "MUST only reference a parent, NOT a child" 세 줄이 Geofence 쪽에는 없다. 타입 시그니처(`JSON array of GEOFENCE-ID`)가 첫 줄을 대신하고 있다고 볼 수 있으나, "부모만 넣고 자식은 넣지 말라"는 방향성 조항이 명시되지 않은 것은 스펙의 비대칭이다. 실무에서는 Section과 동일하게 취급하는 편이 안전하다.

### 2.5 Validations 페이지의 Geofence 규칙 (원문 25행 전수)

| 심각도 | 규칙 | 정의(원문) |
| --- | --- | --- |
| Info | `GeofenceHasInteriorRing` | Validates that a Geofence does not possess an interior ring. |
| Info | `GeofenceHasNoBuildingReference` | Validates that a Geofence references a Building. |
| Info | `GeofenceHasNoLevelReference` | Validates that a Geofence references a Level. |
| Info | `GeofenceHasParentReference` | Validates that a Geofence has a parent reference. |
| Info | `GeofenceNotWithinReferencedBuildingFootprint` | Validates that a Geofence is within the referenced Building's union of Footprints. |
| Info | `GeofencesOverlap` | Validates that the interior geometry of a Geofence does not intersect the interior geometry of another on the same Level. |
| Violation | `AltNameMustBeString` | Validates that an alt_name is a string data type. |
| Violation | `CorrelationIdMustBeMatched` | Validates that a correlation_id is matched by at least one other feature's correlation_id in the same feature-type. |
| Violation | `DisplayPointMustBePointGeometry` | Validates that a display_point is a point geometry type. |
| Violation | `GeofenceCategoryMustBeValid` | Validates the category assigned to a Geofence. |
| Violation | `GeofenceMustHaveCategory` | Validates that a Geofence has a category value. |
| Violation | `GeofenceMustHaveLevelOrBuildingReference` | Validates that a Geofence references at least one Level or Building. |
| Violation | `GeofenceMustHavePolygonalGeometry` | Validates that a Geofence has Polygon or MultiPolygon geometry. |
| Violation | `InvalidCorrelationID` | Validates that a 'correlation_id' is a valid v4 UUID value. |
| Violation | `InvalidFeatureID` | Validates that a feature ID is a valid v4 UUID value. |
| Violation | `InvalidLanguageTag` | Validates that a language tag is a valid value. |
| Violation | `LabelMustNotBeBlank` | Validates that a Label (prefLabel and altLabel) is not blank. |
| Violation | `LevelIDsMustBeDissimilarForCorrelationID` | Validates that features from the same feature-type, whose correlation_id match, possess dissimilar Level id values. |
| Violation | `NameMustBeString` | Validates that a name is a string data type. |
| Violation | `RestrictionCategoryMustBeValid` | Validates the category assigned to a Restriction. |
| Warning | `AltNameLangTagHasNoCorrespondingNameLangTag` | Validates that a language tag associated with an alt_name has a corresponding presence and association with a name value. |
| Warning | `CategoryShouldBeSameForCorrelationID` | Validates that features with matching correlation_id possess the same category. |
| Warning | `GeofenceGeometryMustContainDisplayPoint` | Validates that the display_point is within the Geofence. |
| Warning | `GeofenceNotCoveredByReferencedLevel` | Validates that a Geofence is covered by the referenced Level. |
| Warning | `HasOnlyAltName` | Validates that an alt_name value is not exclusive, that it is accompanied by a name value. |

`GeofenceMustHaveLevelOrBuildingReference`가 `Violation` 등급이라는 점이 중요하다. **properties 표에서는 `building_ids`·`level_ids`가 둘 다 nullable인데, 검증 단계에서는 둘 중 최소 하나가 반드시 있어야 한다.** 표만 읽고 구현하면 놓치는 조건이다. 결과적으로 Geofence의 실질 필수 입력은 `category` 하나가 아니라 `category` + (`building_ids` 또는 `level_ids`) 둘이다. `Section` 쪽에 이에 대응하는 규칙은 `SectionMustReferenceLevel`이며, 이쪽은 표에서도 이미 필수(`LEVEL-ID`, null 불가)로 드러나 있다.

`Section`에는 있고 `Geofence`에는 없는 검증이 `AccessibilityMustBeValid`다. Geofence에 `accessibility` 필드가 없으므로 당연한 결과이며, 2.2절 표를 교차 확인해 준다.

## 3. SECTION-CATEGORY — 열거값 전량 (71개)

Categories 페이지 `#section` 앵커의 표에서 셀을 그대로 추출해 세었다. **총 71개**이며 알파벳 순이다(src11 2.14절은 "약 70"으로 적었으나 정확한 수는 71이다).

`arcade`, `baggageclaim`, `baggageclaim.intl`, `carrental`, `carrental.dropoff`, `checkin`, `concessions`, `cubicle`, `dutyfree`, `eatingdrinking`, `entertainmentarea`, `entertainmentarea.game`, `entertainmentarea.music`, `entertainmentarea.performance`, `entertainmentarea.sport`, `exhibit`, `exhibition`, `gambling`, `gambling.baccarat`, `gambling.bingo`, `gambling.blackjack`, `gambling.craps`, `gambling.keno`, `gambling.mahjong`, `gambling.medalgame`, `gambling.minibaccarat`, `gambling.offtrackbetting`, `gambling.pachinko`, `gambling.paigow`, `gambling.poker`, `gambling.poker.letitride`, `gambling.poker.paigow`, `gambling.poker.threecard`, `gambling.poker.video`, `gambling.roulette`, `gambling.rummy`, `gambling.sicbo`, `gambling.slotmachine`, `gambling.slotmachine.highlimit`, `gatearea`, `gatearea.holding`, `immigration`, `immigration.schengen`, `information`, `paidarea`, `parkandride`, `parking`, `parking.bicycle`, `parking.compact`, `parking.ev`, `parking.longterm`, `parking.motorcycle`, `parking.shortterm`, `parking.waitingarea`, `platform`, `postsecurity`, `presecurity`, `private`, `recomposearea`, `recreation`, `rental`, `retail`, `retaildepartment`, `road`, `seating`, `seatingrow`, `security`, `servicearea`, `ticketing`, `vegetation`, `walkway`

**`unspecified`는 없다.** 앱의 판단이 맞다. `PropertySchema.swift:308`의 주석("`unspecified`가 없다. 이전 코드가 넣어 뒀던 것은 스펙에 없는 값이었다")은 이번 재확인으로 유지된다. 참고로 `unspecified`를 갖는 열거형은 AMENITY·BUILDING·DOOR·LEVEL·UNIT 5종이며, SECTION과 GEOFENCE는 여기 포함되지 않는다(src11 2절 대조).

특징적인 분포로, 71개 중 22개가 `gambling.*` 계열이고 9개가 `parking.*` 계열이다. 카지노와 주차장이 압도적으로 세분화되어 있는 반면, 사무 공간이나 교육 시설을 나타낼 값은 사실상 `private`·`servicearea` 정도밖에 없다. 국내 오피스·캠퍼스 대상 데이터를 만들 때 적절한 Section 카테고리를 찾기 어려운 이유가 여기에 있다.

## 4. GEOFENCE-CATEGORY — 열거값 전량 (8개)

Categories 페이지 `#geofence` 앵커의 표에서 추출했다. **총 8개**, 알파벳 순이다.

`concourse`, `geofence`, `paidarea`, `platform`, `postsecurity`, `presecurity`, `terminal`, `underconstruction`

여기에도 **`unspecified`는 없다.** 값의 성격을 뜯어보면 Geofence의 용도가 드러난다.

- `terminal`·`concourse`·`platform` — 공항·철도역의 대형 구역 구분. 여러 층·여러 건물에 걸치는 단위이며, `building_ids`/`level_ids` 설계와 정확히 맞물린다.
- `presecurity`·`postsecurity`·`paidarea` — **보안검색 전/후, 유료 구역.** 통행 정책이 다른 영역을 나누는 값으로, "geofence"라는 이름의 본래 의미(경계를 넘을 때 규칙이 바뀌는 영역)에 가장 부합한다.
- `underconstruction` — 공사 중 영역. 일시적 상태를 표현한다.
- `geofence` — 위 어느 것에도 해당하지 않을 때 쓰는 **범용 값**. 스펙 예제(2.3절)도 이 값을 쓴다. `unspecified`가 없는 대신 이 값이 그 자리를 대신한다고 읽는 것이 타당하다. 다만 스펙에 그렇게 규정한 문장은 없다 — **확인 필요.**

`paidarea`·`platform`·`postsecurity`·`presecurity` 네 값은 SECTION-CATEGORY(3절)에도 동일하게 존재한다. 같은 개념을 Section으로 그릴지 Geofence로 그릴지 선택할 수 있다는 뜻인데, **어느 쪽을 언제 써야 하는지 판단 기준을 규정한 문장은 스펙 어디에도 없다. 확인 필요** — Apple Guidance의 Airport·Transit Station 페이지에 실무 지침이 있을 가능성이 있으나 이번 조사 범위 밖이다.

## 5. Section vs Geofence — properties 대조

두 타입은 폴리곤 위에 "구역"을 얹는다는 점에서 겉보기가 비슷하다. 필드 단위로 놓고 보면 차이가 뚜렷하다.

| Property | Section | Geofence |
| --- | --- | --- |
| `category` | `SECTION-CATEGORY` (필수) | `GEOFENCE-CATEGORY` (필수) |
| `restriction` | nullable | nullable |
| `accessibility` | nullable 배열 | **없음** |
| `name` | nullable LABELS | nullable LABELS |
| `alt_name` | nullable LABELS | nullable LABELS |
| `display_point` | nullable | nullable |
| `level_id` / `level_ids` | `LEVEL-ID` **단수·필수** | `level_ids` **복수 배열·nullable** |
| `building_ids` | **없음** | nullable 배열 |
| `address_id` | nullable | **없음** |
| `correlation_id` | nullable UUID (다른 층의 유사 Section 묶음) | nullable UUID (Geofence 간 묶음, 층 조건 없음) |
| `parents` | `SECTION-ID` 배열 | `GEOFENCE-ID` 배열 |
| 총 개수 | **10** | **9** |

핵심 차이는 층 참조의 기수(cardinality)다. Section은 정확히 한 층에 귀속되고(`SectionMustBeCoveredByReferencedLevel`), Geofence는 여러 층·여러 건물에 걸칠 수 있으며 걸치는 범위를 명시적으로 열거한다. `accessibility`가 Section에만 있는 것도 같은 맥락이다 — 접근성은 보행자가 실제로 다니는 층 단위 공간의 속성이지, 정책 구역의 속성이 아니다. `address_id`가 Section에만 있는 것 역시 Section이 물리적 장소에 대응하기 때문이다.

## 6. geometry 타입 제약과 display_point 요건

### 6.1 POLYGONAL의 정의 (Reference 페이지 Geometry Type Designators 표 원문)

| Designator | Value Type | Description |
| --- | --- | --- |
| `GEOMETRY` | object | GeoJSON Geometry object |
| `POINT` | `GEOMETRY` | GeoJSON Point geometry |
| `MULTI-POINT` | `GEOMETRY` | GeoJSON MultiPoint geometry |
| `LINE-STRING` | `GEOMETRY` | GeoJSON LineString geometry |
| `MULTI-LINE-STRING` | `GEOMETRY` | GeoJSON MultiLineString geometry |
| `POLYGON` | `GEOMETRY` | GeoJSON Polygon geometry |
| `MULTI-POLYGON` | `GEOMETRY` | GeoJSON MultiPolygon geometry |
| `POLYGONAL` | `POLYGON` or `MULTI-POLYGON` | Option of POLYGON or MULTI-POLYGON geometry |
| `LINEAL` | `LINE-STRING` or `MULTI-LINE-STRING` | Option of LINE-STRING or MULTI-LINE-STRING geometry |
| `DISPLAY-POINT` | `POINT` | POINT based representation of Polygonal or Lineal Features |

따라서 **Section·Geofence 모두 Polygon과 MultiPolygon을 허용하며, `null`은 허용하지 않는다.** Validations의 `SectionMustHavePolygonalGeometry`·`GeofenceMustHavePolygonalGeometry`가 "Polygon or MultiPolygon"이라고 명시해 이를 확정한다. null geometry가 허용되는 것은 Building·Occupant·Address(그리고 조건부로 Relationship)뿐이다(src11 5절).

내부 링(구멍)에 대해서는 두 타입 모두 `Info` 등급의 `SectionHasInteriorRing`·`GeofenceHasInteriorRing`이 걸린다. **금지가 아니라 정보성 경고**다. 도넛 형태 구역이 불가능하지는 않지만 검증기가 지적한다는 뜻으로 읽어야 한다.

### 6.2 DISPLAY-POINT 요건 (Reference 페이지 원문)

> A Display Point represents a curated, Point-based representation of a non-puntal Feature.
> - Display Points are members of a Feature's `"property"` object
> - Display Points **MUST** be captured as GeoJSON Point objects
> - Display Points **MUST** be within the geometry of the Feature that possesses it
> - Display Points **SHOULD** be positioned in a location where map label "collision" is least expected

Section·Geofence 모두 `display_point`는 nullable이므로 **필수는 아니다.** 다만 값을 넣는다면 세 가지 `MUST`가 걸린다. 이 중 "within the geometry"는 Validations에서 각각 `SectionGeometryMustContainDisplayPoint`·`GeofenceGeometryMustContainDisplayPoint`로 구현되어 있고, 흥미롭게도 **심각도가 `Warning`이다.** Reference 페이지는 `MUST`라고 쓰고 Validations는 `Warning`으로 처리하는 불일치가 있으며, 실제 검증기는 후자를 따를 것으로 보인다. 구현 시에는 엄격한 쪽(`MUST`)에 맞춰 폴리곤 내부에 찍는 것이 안전하다.

`DisplayPointMustBePointGeometry`는 `Violation` 등급이다. 즉 **타입이 틀린 것은 치명적, 위치가 벗어난 것은 경고**라는 구분이다.

## 7. Section·Geofence에만 있는 특이 필드

앞 절들의 결과를 참조 관계 중심으로 정리한다.

| 필드 | 보유 타입 | 참조 대상 | 성격 |
| --- | --- | --- | --- |
| `level_id` | Section | Level (단수, 필수) | 이 Section이 놓인 층. `SectionMustBeCoveredByReferencedLevel`로 기하학적 포함까지 요구 |
| `level_ids` | Geofence | Level (복수, nullable) | 이 Geofence가 적용되는 층 목록. 미지정 시 `building_ids` 건물의 전 층 |
| `building_ids` | Geofence | Building (복수, nullable) | 적용 건물. Footprint가 Geofence 폴리곤과 전부 또는 일부 겹쳐야 함 |
| `address_id` | Section | Address | Section에 부여된 우편 주소 |
| `accessibility` | Section | ACCESSIBILITY-CATEGORY 배열 | 값 10종. 단일 문자열이 아니라 배열 |
| `restriction` | 양쪽 | RESTRICTION-CATEGORY | `employeesonly`·`restricted` 2종 |
| `correlation_id` | 양쪽 | UUID (참조 아님) | 동일 값을 가진 형제 피처들을 묶는 태그. 단독 사용 금지 |
| `parents` | 양쪽 | 같은 타입의 FEATURE-ID 배열 | 계층 표현. `parent_id` 단수 필드가 아니라 **배열**이라는 점이 다른 스키마와 다르다 |

`parents`가 배열이라는 사실의 함의는 작지 않다. 단일 부모를 갖는 트리가 아니라 **여러 부모를 동시에 가질 수 있는 DAG**를 허용한다는 뜻이다. 순환만 금지되어 있을 뿐(`MUST NOT introduce circular dependencies`) 다중 부모 자체는 금지되지 않는다. 하나의 Section이 두 상위 Section에 동시에 속할 수 있다.

`correlation_id`는 참조 ID가 아니라는 점에서 나머지와 성격이 다르다. 어떤 피처의 `id`를 가리키는 것이 아니라, **같은 임의의 UUID를 여러 피처가 나눠 갖는 방식**이다. 그래서 `CorrelationIdMustBeMatched`(짝이 최소 하나 있어야 함)와 `CategoryShouldBeSameForCorrelationID`(짝끼리 category가 같아야 함) 두 규칙이 따라붙는다.

## 앱 현재 스키마와의 대조

기준 파일: `~/Desktop/IM-DFrnt/Sources/IMDFrnt/Model/PropertySchema.swift`(2026-08-29 시점 읽기 전용 확인), `Model/IMDFFeatureType.swift`.

### Section (`PropertySchema.swift:183~195`)

앱이 가진 필드는 7개(`id` 슬롯 제외 시 7개: category, name, alt_name, restriction, accessibility, level_id, display_point)이고, 스펙은 10개다.

| 스펙 필드 | 앱 상태 | 앱의 타입 | 판정 근거 |
| --- | --- | --- | --- |
| `category` | 있음 | `.string` + 71종 드롭다운 | 열거값 전량 일치(아래 확인) |
| `restriction` | **불일치** | `.alwaysNull` | 스펙은 `null or RESTRICTION-CATEGORY`. 앱은 항상 null이라 `employeesonly`·`restricted`를 입력할 수 없음 |
| `accessibility` | **불일치** | `.alwaysNull` | 스펙은 `null or JSON array of ACCESSIBILITY-CATEGORY`. 배열 입력 수단 없음 |
| `name` | 있음 | `.localizedName` | LABELS에 대응 |
| `alt_name` | **불일치** | `.alwaysNull` | 스펙은 `null or LABELS`. 대체 이름 입력 불가 |
| `display_point` | 있음 | `.point`, `isEditable: false` | 지도에서 찍는 방식이므로 텍스트 편집 불가는 의도된 설계 |
| `level_id` | 있음 | `.reference(.level)` | 필수 필드 대응 |
| `address_id` | **누락** | — | 스펙 표에 있으나 앱 스키마에 행 자체가 없음 |
| `correlation_id` | **누락** | — | 상동 |
| `parents` | **누락** | — | 상동 |

**누락 3개: `address_id`, `correlation_id`, `parents`.** 불일치(항상 null이라 입력 불가) 3개: `restriction`, `accessibility`, `alt_name`.

실무 중요도 판단:

- `parents` — **중요도 높음.** Section 계층은 스펙이 Property Capturing Rules 7줄을 할애할 만큼 명시적으로 지원하는 기능이고, "쇼핑몰 > 푸드코트" 같은 중첩 구역은 실제 현장에서 흔하다. 앱에 슬롯이 없으면 계층 구조를 가진 데이터를 아예 만들 수 없다. 다만 UI 관점에서는 다른 Section의 UUID를 골라 넣는 다중 선택 위젯이 필요해, 단순 텍스트 슬롯 추가로 끝나지 않는다.
- `correlation_id` — **중요도 중간.** 다층 건물에서 같은 성격의 Section(예: 각 층의 `retail` 구역)을 묶는 용도다. 없어도 데이터는 유효하지만, 여러 층을 다루는 Venue에서는 곧 필요해진다. 주의할 것은 **단독으로 넣으면 오히려 `Violation`**(`CorrelationIdMustBeMatched`)이라는 점이다. 슬롯을 추가한다면 "짝이 있는지" 검사를 함께 넣어야 한다.
- `address_id` — **중요도 낮음.** Section에 개별 우편 주소를 부여하는 경우는 드물다. 앱이 이미 `address` 피처와 `.reference(.address)` 타입을 다루고 있으므로 추가 비용은 가장 작다.
- `restriction`·`accessibility`·`alt_name`의 `.alwaysNull` — **중요도 중간.** 앱 전반이 이 세 필드를 모든 타입에서 `.alwaysNull`로 두는 일관된 정책을 쓰고 있어(Unit·Opening·Building 등도 동일), Section만의 문제는 아니다. 다만 `accessibility`는 Section에서 `Violation` 등급 검증(`AccessibilityMustBeValid`)이 걸리는 필드이고 배열 타입이라, 나중에 지원할 때 `FieldType`에 새 케이스가 필요할 수 있다.

### Geofence (`PropertySchema.swift:196~210`)

| 스펙 필드 | 앱 상태 | 앱의 타입 | 비고 |
| --- | --- | --- | --- |
| `category` | 있음 | `.string` + 8종 드롭다운 | 열거값 전량 일치 |
| `restriction` | **불일치** | `.alwaysNull` | Section과 동일 사유 |
| `name` | 있음 | `.localizedName` | |
| `alt_name` | **불일치** | `.alwaysNull` | |
| `correlation_id` | **불일치** | `.alwaysNull` | 슬롯은 있으나 값을 넣을 수 없음 |
| `display_point` | 있음 | `.point`, `isEditable: false` | |
| `building_ids` | 있음 | `.stringArray` | |
| `level_ids` | 있음 | `.stringArray` | |
| `parents` | 있음 | `.stringArray` + note | |

**Geofence는 스펙 9개 필드가 모두 스키마에 존재한다. 누락 없음.** src11 3.8절이 Geofence properties를 이미 전부 나열해 둔 덕분이다. 미해결 주석이 Section 쪽에만 달려 있던 것도 이와 부합한다.

### category 열거값 대조

- SECTION: 앱 `PropertySchema.swift:309~326`의 71개와 스펙 71개를 프로그램으로 집합 비교한 결과 **양방향 차집합이 공집합**이다. 완전 일치.
- GEOFENCE: 앱 `PropertySchema.swift:330~333`의 8개와 스펙 8개 **완전 일치**.

두 열거형 모두 `unspecified`를 갖지 않는다는 앱의 판단도 정확하다.

### 스키마 외 대조 — geometry와 Opening 빌려주기

두 가지가 `PropertySchema.swift` 바깥에서 스펙과 어긋난다.

1. **geometry 종류.** `IMDFFeatureType.swift:23`은 `case .footprint, .geofence, .level, .section, .unit, .venue: return .polygon`으로 Section·Geofence를 Polygon 전용으로 고정한다. 스펙은 `POLYGONAL`, 즉 MultiPolygon도 허용한다(6.1절). 앱이 단일 폴리곤만 만들도록 제한하는 것은 편집기 정책으로서 정당할 수 있으나, 스펙 제약을 그대로 옮긴 것은 아니다. 참고로 `fixture`는 앱에서 `.multiPolygon`인데 스펙상 Fixture도 `POLYGONAL`이므로 같은 층위의 문제다.
2. **Opening 빌려주기 대상.** `IMDFFeatureType.swift:42~47`의 `canBorrowOpenings`는 폴리곤 계열이면 전부 true를 돌려주므로 Section이 포함된다. 스펙 Section의 Geometry Capturing Rules는 "An Opening **SHOULD NOT** be used to model an entrance to a Section"이라고 명시한다(1.5절). `SHOULD NOT`이므로 절대 금지는 아니지만, 기본값으로 허용하는 현재 동작은 스펙 권고와 반대 방향이다.
3. **`GeofenceMustHaveLevelOrBuildingReference`.** properties 표만 보면 `building_ids`·`level_ids`가 둘 다 nullable이지만 검증에서는 최소 하나가 `Violation` 등급으로 요구된다(2.5절). 앱에 이 조건을 검사하는 곳이 있는지는 이번 조사 범위 밖이다 — **확인 필요.**

## 결론

**`PropertySchema.swift:185`의 "…등까지만 확인됨(전수 미대조, 확인 필요)" 주석은 지울 수 있다.** Section의 properties는 10개이고 이 문서 1.2절이 원문 표를 한 칸도 빠짐없이 옮겼다. Geofence의 9개, SECTION-CATEGORY 71개, GEOFENCE-CATEGORY 8개도 모두 확정되었다. "등"으로 남겨 둔 부분은 더 이상 없다.

다만 주석을 지우는 것과 스키마를 스펙에 맞추는 것은 별개다. 주석을 지우기 전에 정리해야 할 것을 우선순위 순으로 적는다.

1. **Section에 `address_id`·`correlation_id`·`parents` 3개 행을 추가한다.** 가장 단순한 형태로는 `address_id`를 `.reference(.address)`, `correlation_id`를 `.alwaysNull`, `parents`를 `.stringArray`로 두면 Geofence와 동일한 수준의 표현력을 갖게 된다. Geofence가 이미 `parents`를 `.stringArray`로 갖고 있으므로 새 `FieldType` 케이스는 필요 없다.
2. **주석을 사실 기술로 교체한다.** "전수 미대조"를 지우고, 대신 (a) geometry가 `POLYGONAL`이지 Polygon 단독이 아니라는 점, (b) `category`·`level_id` 둘만 null 불가라는 점, (c) Opening을 Section 출입구로 쓰지 말라는 `SHOULD NOT` 규정, (d) 이 문서(src15)를 근거로 참조한다는 점을 남긴다.
3. **`restriction`·`accessibility`·`alt_name`의 `.alwaysNull` 정책은 별도 과제로 분리한다.** Section만의 문제가 아니라 앱 전반의 설계 선택이므로, Section 주석 해소와 묶어 처리할 사안이 아니다. 특히 `accessibility`는 배열 타입이라 `FieldType`·`PropertyValue` 양쪽에 손이 필요하다.
4. **`canBorrowOpenings`에서 Section을 제외할지 결정한다.** 스펙은 `SHOULD NOT`이므로 강제는 아니다. 제외하지 않기로 한다면 그 판단 근거를 코드 주석에 남겨 두는 편이 낫다.
5. **`GeofenceMustHaveLevelOrBuildingReference` 검사 유무를 확인한다.** 내보내기 시점에 `building_ids`와 `level_ids`가 모두 비어 있으면 경고를 띄우는 것이 맞다.

1번과 2번만 처리하면 `PropertySchema.swift:185` 주석은 근거를 갖고 삭제할 수 있다.

## 미해결 질문

- GEOFENCE-CATEGORY의 `geofence` 값이 다른 열거형의 `unspecified`에 해당하는 범용 값인지 — 스펙 예제가 그렇게 쓰고 있으나 규정 문장은 없다. **확인 필요.**
- `paidarea`·`platform`·`postsecurity`·`presecurity` 네 값이 SECTION과 GEOFENCE에 중복 존재하는데, 같은 개념을 어느 타입으로 그려야 하는지 판단 기준 — 스펙 본문에 없음. Apple Guidance의 Airport·Transit Station 페이지 미조사. **확인 필요.**
- Section 예제의 `accessibility: "wheelchair"`(스칼라)와 표의 "JSON array" 규정 불일치가 스펙 오타인지 배열·스칼라 양쪽 허용인지 — Validations의 `AccessibilityMustBeValid` 정의문("Validates the accessibility category assigned to the feature")으로는 판별 불가. **확인 필요.**
- `display_point`의 "within the geometry" 요건이 Reference에서는 `MUST`, Validations에서는 `Warning`인 불일치 — 실제 Apple 검증기가 어느 쪽으로 동작하는지 미확인. **확인 필요.**
- 앱이 `GeofenceMustHaveLevelOrBuildingReference` 조건을 내보내기 검증에서 확인하는지 — 이번 조사는 `PropertySchema.swift`·`IMDFFeatureType.swift` 두 파일만 읽었다. **확인 필요.**
- Section·Geofence의 Illustration 페이지(Geometry Capturing Rules 본문에 "(Illustration)" 링크로 언급됨) — 스펙 목차의 Illustrations 항목은 Footprint·Level·Unit 셋뿐이라 Section 삽화의 실제 위치가 불분명하다. **확인 필요.**
