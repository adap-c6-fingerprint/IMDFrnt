---
summary: "같은 속성에 여러 선언이 경쟁할 때 무엇이 이기는지 정하는 규칙. origin과 !important로 먼저 층을 가르고, 같은 층 안에서 specificity로, 그것도 같으면 문서 순서로 결정한다"
source: "[[13) SVG 스타일이 요소에 도달하는 다섯 경로와 우선순위]], [[src14. SVG 스타일 적용 경로와 style 블록 지원 범위 조사]], W3C CSS Cascading and Inheritance Level 4"
related:
  - "[[specificity]]"
  - "[[프레젠테이션 속성]]"
created: "2026-08-30 16:55"
updated: "2026-08-30 16:55"
core_keywords:
  - CSS 캐스케이드
---
# CSS 캐스케이드

## 요약

캐스케이드(cascade)는 **같은 속성에 여러 선언이 경쟁할 때 무엇이 이기는지 정하는 규칙**이다. 판정은 세 단계로 내려간다 — **origin과 `!important` → [[specificity]] → 문서 순서**.

## 핵심 내용

### origin 정렬

CSS Cascade Level 4의 내림차순 원문이다.

> "1. Transition declarations / 2. Important user agent declarations / 3. Important user declarations / 4. **Important author declarations** / 5. Animation declarations / 6. **Normal author declarations** / 7. Normal user declarations / 8. Normal user agent declarations"

`!important`가 붙으면 층 자체가 바뀐다는 점이 중요하다. **author의 important가 user의 normal보다 위**이고, 사용자 지정 스타일의 important는 author의 important보다도 위다(접근성 보장을 위한 설계다).

### 프레젠테이션 힌트는 별도 층

> "All document language-based styling must be translated to corresponding CSS rules and enter the cascade as rules in either the UA-origin or a **special-purpose author presentational hint origin between the regular user origin and the author origin**."

[[프레젠테이션 속성]]이 여기 해당한다.

### 인라인 선언은 셀렉터를 이긴다

> "declarations that do not belong to a style rule (such as the contents of a style attribute) are considered to have a **specificity higher than any selector**."

`style="fill:red"`는 어떤 셀렉터로도 이길 수 없다(`!important` 제외).

### SVG에 적용하면

| 순위 | 경로 | 근거 |
|---|---|---|
| 1 (최강) | `style` 속성 | "specificity higher than any selector" |
| 2 | `<style>`·외부 스타일시트 규칙 | specificity로 서로 경쟁 |
| 3 (최약) | 프레젠테이션 속성 | "specificity of zero" |

### 상속은 캐스케이드가 아니다

- 캐스케이드는 **한 요소에 걸린 여러 선언 중 승자를 고르는** 절차다.
- 상속(inheritance)은 **승자가 없을 때 부모의 값을 물려받는** 별개 축이다.
- SVG 파서는 이 둘을 모두 구현해야 한다 — `<g fill="red">` 아래의 `<path>`에 `fill`이 없으면 빨강이 되는 것이 상속이다.

## 관련 링크

- [[specificity]] — 같은 층 안에서의 경쟁 규칙
- [[프레젠테이션 속성]] — 캐스케이드 최하위에 놓이는 경로
- [[13) SVG 스타일이 요소에 도달하는 다섯 경로와 우선순위]] — SVG에서의 적용

## 미해결 질문

- 없음.
