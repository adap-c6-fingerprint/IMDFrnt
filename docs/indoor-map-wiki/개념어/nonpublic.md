---
summary: "IMDF Unit의 category 값 중 하나. 일반 방문자가 출입할 수 없는 구역(직원 사무실·창고·기계실·샤프트 등)을 안쪽 방 구분 없이 하나의 Unit으로 나타낸다. restriction은 비우고 경계 안에 Opening을 두지 않는다"
source: "[[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]], [[src19. IMDF 비개방 구역(nonpublic) 모델링 규칙 조사]], docs.ogc.org/cs/20-094/Unit"
related:
  - "[[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]]"
  - "[[UNIT-CATEGORY]]"
  - "[[RESTRICTION-CATEGORY]]"
  - "[[IMDF]]"
created: "2026-10-17 17:30"
updated: "2026-10-17 17:30"
core_keywords:
  - nonpublic
---
# nonpublic

## 요약

`nonpublic`은 IMDF Unit의 `category`(공간 용도) 칸에 넣는 값으로, "일반 방문자가 들어갈 수 없는 구역"을 뜻한다. 직원 사무 구역처럼 안에 방이 여러 개 있어도 바깥 윤곽 하나를 `nonpublic` Unit 하나로 그리는 것이 스펙의 권장 방식이다.

## 핵심 내용

- **하나로 그린다 (SHOULD):** "A space that contains non-public areas SHOULD be modeled as a "nonpublic" Unit". 안쪽 사무실·창고를 각각 `office`·`storage`로 나눌 필요가 없다.
- **붙어 있으면 합친다 (SHOULD, 조건부):** 같은 층에서 맞닿은 `nonpublic` Unit은 (1) 나눠 둘 업무상 가치가 없거나 (2) 합치면 앱 성능이 나아지거나 (3) 지도가 더 보기 좋아질 때 병합한다.
- **restriction은 비운다 (SHOULD NOT):** "A "nonpublic" Unit SHOULD NOT possess a restriction". 출입 불가라는 뜻이 이미 카테고리에 들어 있다.
- **Opening을 두지 않는다 (SHOULD NOT):** 경계 안에 출입구를 그리면 들어갈 수 있는 곳처럼 보인다.
- **샤프트·덕트는 반드시 nonpublic (MUST):** 설비용 수직 통로는 `opentobelow`가 아니라 `nonpublic`이다.
- **층 전체가 비개방이면 쓰지 않는다 (SHOULD NOT):** 그 층은 `nonpublic` Unit으로 채우지 않고 Level 자체를 만들지 않는다.
- **방문자 응대 공간은 빼도 된다 (MAY):** 매표소·안내 데스크 안쪽처럼 직원이 방문자와 물건·서비스를 주고받는 곳은 보기 좋아진다면 `nonpublic` 범위에서 제외할 수 있다.
- **`employeesonly`와의 구분:** 비개방 구역을 **일부러 자세히** 그리고 싶을 때는 `nonpublic` 대신 실제 용도 카테고리에 `restriction: "employeesonly"`를 붙인다. 자세한 비교는 [[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]] 4절.
- **Level 출입구 규칙의 예외:** Level은 최소 하나의 Opening이 참조해야 하지만(MUST), Level이 `nonpublic` Unit과 같은 경우는 예외로 허용된다.
- Categories 페이지에는 `nonpublic`의 정의 문장이 없고, 의미는 Unit 페이지의 규칙에서 읽어 내야 한다.

## 관련 링크

- [[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]] — 규칙 전체와 판단 순서도
- [[UNIT-CATEGORY]] — `nonpublic`이 속한 열거형
- [[RESTRICTION-CATEGORY]] — 혼동하기 쉬운 출입 제한 값
- [[IMDF]] — 규격 자체

## 미해결 질문

- `nonpublic` 공간을 Indoor Survey로 조사하지 않아도 된다고 명시한 Apple 문서가 있는가. 현재는 "조사가 예정된 공간"이라는 스펙 표현과 Apple 안내 문서의 "공공 건물 안 사적 구역의 입점자 정보는 불필요" 문장에서 나온 추론이다.
- `nonpublic` Unit에 둘러싸인 엘리베이터·계단 Unit의 출입구 처리 방식.
