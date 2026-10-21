---
summary: IMDF Unit 피처의 `category` 속성에 들어갈 수 있는 약 65개 열거값. 공간의 용도뿐 아니라 재질(brick·concrete·glass 등)과 구조체(column·structure)도 포함한다
source: "[[08) IMDF Feature Type·카테고리 전체 레퍼런스]], docs.ogc.org/cs/20-094/Categories"
related:
  - "[[08) IMDF Feature Type·카테고리 전체 레퍼런스]]"
  - "[[Feature Type]]"
  - "[[IMDF]]"
  - "[[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]]"
  - "[[nonpublic]]"
  - "[[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]]"
  - "[[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]]"
  - "[[대칭차]]"
  - "[[walkway]]"
  - "[[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]]"
  - "[[Amenity]]"
created: 2026-08-20 00:00
updated: 2026-10-18 22:03
core_keywords:
  - UNIT-CATEGORY
---
# UNIT-CATEGORY

## 요약

UNIT-CATEGORY는 IMDF의 Unit 피처가 `category` 속성에 담을 수 있는 열거값 목록이다. 약 65개이며, 도면에서 추출한 방 폴리곤이 "무슨 공간인가"를 나타낸다. `00) Apple Indoor Maps Program과 IMDF 개요` 5절이 "카테고리는 좋은 지도와 올바른 렌더링 동작에 결정적"이라 한 그 필드다.

## 핵심 내용

- 값은 전부 소문자이며 도트(`.`)로 계층을 표현한다. 예: `restroom` → `restroom.female` → `restroom.female.wheelchair`
- 성격별 분류
  - **일반 공간:** `room`, `office`, `conferenceroom`, `huddleroom`, `classroom`, `auditorium`, `lobby`, `lounge`, `kitchen`, `library`, `laboratory`, `storage`, `serverroom`, `mailroom`, `waitingroom` 등
  - **이동·통로:** `walkway`, `walkway.island`, `stairs`, `steps`, `elevator`, `escalator`, `ramp`, `movingwalkway`, `footbridge`, `road`, `platform`, `parking`
  - **화장실 11종:** `restroom` 및 성별·휠체어 조합
  - **재질·구조체:** `brick`, `concrete`, `drywall`, `glass`, `wood`, `column`, `structure`
  - **기타:** `unspecified`(폴백), `nonpublic`, `opentobelow`, `unenclosedarea`, `terrace`, `vegetation`, `fieldofplay`
- **재질 값이 들어 있다는 점이 특이하다.** `brick`·`concrete`·`drywall`·`glass`·`wood`는 공간의 용도가 아니다. 벽·기둥처럼 사람이 들어갈 수 없는 구조체를 Unit으로 표현할 때 쓰는 값으로 보이며, 이는 "모든 Unit의 합집합이 Level과 정확히 일치해야 한다"(`MUST NOT symmetrical difference`)는 규정과 관계가 있을 수 있다. 층을 빈틈없이 덮어야 하므로 벽이 차지하는 자리도 어떤 Unit으로든 채워야 하기 때문이다. ~~다만 스펙에 용법 설명이 없어 **확인 필요**다.~~ → **2026-10-18 확인:** OGC IMDF 1.0.0 Unit의 Geometry Capturing Rules에 근거가 있다. 벽을 단순화하지 않고 별도 도형으로 그릴 때, 바닥-천장 벽의 연결망이나 벽·기둥 일체 구조는 반드시 `structure` Unit이고(MUST), 재질을 밝히려면 `brick`·`concrete`·`drywall`·`glass`·`wood`를 쓸 수 있다(may). 독립 기둥은 `column`(MUST, 면적 0.09㎡ 초과 SHOULD), 벽에 붙은 기둥은 `structure`(MUST). 재질 값은 `structure`를 재질별로 구체화한 값이다. 
- **자동 변환 실무:** 도면 텍스트의 한국어("회의실", "탕비실")를 이 열거값(`conferenceroom`, `kitchen`)으로 옮기는 **매핑 사전**을 따로 만들어야 한다. 매칭 실패 시 `unspecified`로 떨어뜨릴 수 있으나 남발하면 지도 품질이 떨어진다. 자세한 맥락은 [[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]] 5절 참고.
- **`nonpublic`의 용법 (2026-10-17 추가):** 방문자 출입 불가 구역을 안쪽 방 구분 없이 Unit 하나로 그리는 값이다(SHOULD). 맞닿은 `nonpublic` Unit은 조건부로 병합하고, `restriction`은 비우며, 경계 안에 Opening을 두지 않는다. 샤프트·덕트는 반드시(MUST) `nonpublic`이다. 출입 제한 칸의 `employeesonly`와는 쓰임이 다르다. 자세한 내용은 [[nonpublic]], [[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]].
- **category별 "반드시" 규칙 (2026-10-18 추가):** `elevator`·`escalator`·`movingwalkway`는 실물 하나당 Unit 하나(MUST), `stairs`는 다른 층으로 가는 계단실(MUST), 같은 층 단차는 조건부 `steps`(MUST), 보이는 수직 빈 공간은 `opentobelow`(MUST), 통로는 `walkway`(MUST)이며 맞닿은 walkway는 조건부 병합(SHOULD). 태깅 때 판단 순서와 층간 정렬 규칙은 [[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]] 3·4절.
- **Amenity를 담을 수 있는 Unit (2026-10-18 추가):** `elevator`·`escalator`·`movingwalkway`·`stairs` Unit 안(또는 경계)에는 같은 이름의 Amenity만, `restroom` 계열 Unit 안에는 `restroom` 계열 Amenity만 둔다. `restroom.female`·`restroom.male` Unit 안에 다른 성별 화장실 Amenity를 두지 않는다. `steps`·`opentobelow`·구조체(`structure`·`column`·`brick`·`concrete`·`drywall`·`glass`·`wood`) Unit 안에는 Amenity를 두지 않는다. 모두 Warning. 근거: [[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]] 3-5절.
- 전체 값 목록은 [[08) IMDF Feature Type·카테고리 전체 레퍼런스]] 3.1절에 있다.

## 관련 링크

- [[08) IMDF Feature Type·카테고리 전체 레퍼런스]] — UNIT-CATEGORY를 포함한 열거형 15종 전량
- [[Feature Type]] — UNIT-CATEGORY가 붙는 Unit이 속한 상위 분류 체계
- [[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]] — 도면에서 이 값을 자동으로 채우는 방법
- [[IMDF]] — 규격 자체
- [[nonpublic]] — 비개방 구역 카테고리의 규칙
- [[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]] — `nonpublic`과 `restriction` 비교
- [[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]] — 태깅 때 category 판단 순서와 경계 규칙
- [[walkway]] — 통로 category의 병합·분할 규칙
- [[18) Amenity 레이어 태깅 규칙 — 편의시설을 점 하나로 어디에 찍고 무엇을 연결하는가]] — Unit category별로 담을 수 있는 Amenity

## 미해결 질문

- ~~재질 값(`brick`·`concrete`·`drywall`·`glass`·`wood`)과 `column`·`structure`의 정확한 용법 — 스펙에 설명 없음.~~ — 2026-10-18 해소: Unit Geometry Capturing Rules에 규정 확인([[src20. IMDF Unit 태깅 규칙 원문 조사 — Property·Geometry·Category Specific Rules·Validations]] 5절).
- 한국어 공간 명칭 → UNIT-CATEGORY 매핑 사전은 어디까지 자동화 가능한가. 표준 사전이 존재하는가.
