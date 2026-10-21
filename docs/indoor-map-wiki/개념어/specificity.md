---
summary: "CSS 셀렉터의 구체성 점수. id 개수(A)·class와 속성과 의사클래스 개수(B)·타입과 의사요소 개수(C)를 세어 (A,B,C)를 사전식으로 비교하고, 동률이면 문서 순서상 뒤가 이긴다"
source: "[[13) SVG 스타일이 요소에 도달하는 다섯 경로와 우선순위]], [[src14. SVG 스타일 적용 경로와 style 블록 지원 범위 조사]], W3C Selectors Level 4 §Calculating a selector's specificity"
related:
  - "[[CSS 캐스케이드]]"
  - "[[프레젠테이션 속성]]"
created: "2026-08-30 16:55"
updated: "2026-08-30 16:55"
core_keywords:
  - specificity
---
# specificity

## 요약

specificity(구체성)는 **CSS 셀렉터가 얼마나 구체적으로 대상을 지목했는지를 나타내는 점수**다. [[CSS 캐스케이드]]에서 같은 층에 있는 선언들이 경쟁할 때 이 값으로 승자를 가른다.

## 핵심 내용

### 세 자리로 센다

Selectors Level 4의 정의다.

> **A** — "ID selectors"
> **B** — "class selectors, attribute selectors, and pseudo-classes"
> **C** — "type selectors and pseudo-elements"

> "The universal selector contributes nothing to the specificity of a selector."

각 범주의 **개수를 세어** (A, B, C) 세 자리를 만들고, **사전식으로** 비교한다. A가 크면 B·C를 볼 것 없이 이긴다.

### 예시

| 셀렉터 | (A, B, C) |
|---|---|
| `*` | (0, 0, 0) |
| `rect` | (0, 0, 1) |
| `.cls-1` | (0, 1, 0) |
| `rect.cls-1` | (0, 1, 1) |
| `#wall` | (1, 0, 0) |
| `g .cls-1 rect` | (0, 1, 2) |

### 동률이면 문서 순서

(A, B, C)가 같으면 **문서에서 뒤에 나온 규칙이 이긴다.** 그래서 파서는 스타일시트 안 규칙의 등장 순서를 보존해야 한다.

### 범위 밖의 두 가지

- **인라인 선언은 이 계산에 참여하지 않는다.** `style` 속성의 내용은 "specificity higher than any selector"로 취급되어 어떤 셀렉터로도 이길 수 없다.
- **[[프레젠테이션 속성]]은 specificity 0**이다. `*`(0,0,0)와 같은 수준이거나 그 아래로, 사실상 모든 셀렉터에 진다. 이 때문에 `<style>`의 `rect { fill: red }` 한 줄이 요소의 `fill="blue"`를 이긴다.

### 구현할 때

셀렉터 엔진을 직접 만든다면 최소한 다음이 필요하다.

1. (A, B, C) 계산
2. 사전식 비교
3. **동률 시 문서 순서** — 이것을 빼면 조용히 틀린다

클래스·타입·그룹(콤마)·복합 셀렉터만 지원해도 익스포터가 생성하는 SVG는 대부분 커버된다. 의사 클래스는 정적 파싱에서 의미가 없으므로 제외해도 된다.

## 관련 링크

- [[CSS 캐스케이드]] — specificity가 쓰이는 단계
- [[프레젠테이션 속성]] — specificity 0인 특수 경로
- [[13) SVG 스타일이 요소에 도달하는 다섯 경로와 우선순위]] — SVG 파서 관점의 정리

## 미해결 질문

- 없음.
