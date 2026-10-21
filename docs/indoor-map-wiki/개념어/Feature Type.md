---
summary: IMDF에서 각 Feature 객체가 자신의 `feature_type` 필드에 담는 분류 값. 스펙이 허용하는 16개 값만 쓸 수 있으며, 이 분류가 곧 출력 GeoJSON 파일의 단위가 된다
source: "[[08) IMDF Feature Type·카테고리 전체 레퍼런스]], docs.ogc.org/cs/20-094"
related:
  - "[[08) IMDF Feature Type·카테고리 전체 레퍼런스]]"
  - "[[IMDF]]"
  - "[[GeoJSON]]"
  - "[[UNIT-CATEGORY]]"
created: 2026-08-20 00:00
updated: 2026-10-19 14:45
core_keywords:
  - Feature Type
---
# Feature Type

## 요약

Feature Type은 IMDF에서 각 Feature 객체가 자신의 최상위 `feature_type` 필드에 담는, 자신이 속한 분류를 나타내는 문자열 값이다. 스펙이 열거한 **16개 값**만 쓸 수 있고, 이 분류가 곧 IMDF 아카이브 안의 출력 GeoJSON 파일 단위가 된다.

## 핵심 내용

- 허용값 16종(소문자): `address`, `amenity`, `anchor`, `building`, `detail`, `fixture`, `footprint`, `geofence`, `kiosk`, `level`, `occupant`, `opening`, `relationship`, `section`, `unit`, `venue`
- 스펙 규정 원문: "The value of a Feature's `"feature_type"` member **MUST** be one of the following case-sensitive values" — 대소문자를 구분하며 목록 밖의 값은 허용되지 않는다.
- FEATURE-REFERENCE(다른 Feature를 가리키는 참조 객체)도 대상의 `id`와 `feature_type`을 함께 담는다. 즉 참조에도 이 분류가 따라붙는다.
- **geometry 유무로 성격이 갈린다.** Building·Occupant·Address는 geometry가 `null` 필수(도형이 아니라 정보 레코드), Relationship은 null이 기본이되 선택적으로 도형을 가질 수 있다. 나머지는 Polygon·LineString·Point 중 하나를 필수로 갖는다.
- **16종 중 12종만 `category` 속성을 갖는다.** Kiosk·Anchor·Detail·Address에는 category가 없다.
- **category는 칸이 있는 12종 모두 필수다(2026-10-19 확인).** 10종은 `<Feature>MustHaveCategory`(Violation) 검사가 있고, Footprint·Relationship은 검사 규칙 없이 표의 Type 칸만으로 필수다. name은 Venue·Level·Occupant만 필수다. 정리는 [[19) name·category 필수 입력 여부 — Feature Type 16종 한눈에 보기]].
- "Feature Type"이라는 용어 자체를 "A Feature Type is..." 형태로 직접 정의하는 문장은 Reference 페이지에 없다(확인 필요). 다만 위 규정으로 역할은 명확하다.
- 전체 목록과 각 타입의 geometry·properties·category 대응은 [[08) IMDF Feature Type·카테고리 전체 레퍼런스]] 참고.

## 관련 링크

- [[08) IMDF Feature Type·카테고리 전체 레퍼런스]] — 16종 전체와 카테고리 열거형 전량
- [[IMDF]] — Feature Type이 속한 규격
- [[GeoJSON]] — Feature Type이 파일 단위가 되는 출력 포맷
- [[UNIT-CATEGORY]] — Feature Type 중 Unit이 갖는 하위 분류 열거형
- [[19) name·category 필수 입력 여부 — Feature Type 16종 한눈에 보기]] — 16종별 name·category 필수 여부

## 미해결 질문

- 스펙이 "Feature Type" 용어를 직접 정의한 문장이 Glossary 등 다른 페이지에 있는가.
- IMDF 확장(EXTENSIONS 데이터 타입)으로 16종 밖의 Feature Type을 추가할 수 있는가.
