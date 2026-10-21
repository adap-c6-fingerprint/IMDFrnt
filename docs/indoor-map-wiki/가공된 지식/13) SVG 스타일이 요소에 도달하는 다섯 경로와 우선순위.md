---
summary: "SVG에서 스타일이 요소에 도달하는 경로는 프레젠테이션 속성·style 속성·style 요소·HTML link·xml-stylesheet PI의 다섯 가지이며, CSS 상속이 별도 축으로 겹친다. 프레젠테이션 속성은 두 판본 모두 specificity 0의 최하위라 style 블록의 타입 셀렉터 한 줄에도 진다. 따라서 style 블록을 읽지 않는 파서는 색을 덜 반영하는 것이 아니라 틀린 색을 그린다. style 요소는 문서 어디에나 놓일 수 있어 단일 패스 파싱으로는 원리적으로 지원할 수 없다"
source: "[[src14. SVG 스타일 적용 경로와 style 블록 지원 범위 조사]], W3C SVG 1.1 Second Edition Chapter 6, W3C SVG 2 Chapter 6, CSS Cascading and Inheritance Level 4, Selectors Level 4"
related:
  - "[[프레젠테이션 속성]]"
  - "[[CSS 캐스케이드]]"
  - "[[specificity]]"
  - "[[2-pass 파싱]]"
  - "[[SVG]]"
  - "[[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]]"
created: "2026-08-30 16:50"
updated: "2026-08-30 16:50"
core_keywords:
  - 프레젠테이션 속성
  - CSS 캐스케이드
  - specificity
  - 2-pass 파싱
---
# 13) SVG 스타일이 요소에 도달하는 다섯 경로와 우선순위

## 요약

SVG 파일을 읽어 도형의 색·선폭을 알아내려는 프로그램은 **"이 요소의 fill은 무엇인가"**라는 단순해 보이는 질문에 답해야 한다. 그런데 SVG에서 그 값이 정해지는 경로는 하나가 아니다. 다섯 가지이고, 서로 우선순위가 있으며, **가장 눈에 잘 띄는 경로가 가장 약하다.**

`<rect fill="blue">`라고 적혀 있어도 문서 어딘가의 `<style>` 블록에 `rect { fill: red }`가 있으면 **빨간색이 맞다.** 이 사실을 모르는 파서는 스타일을 "덜 반영"하는 것이 아니라 **정반대 색을 그린다.**

이 문서는 그 다섯 경로와 우선순위, 그리고 `<style>`을 지원하려 할 때 부딪히는 구조적 제약을 정리한다.

---

## 1. 다섯 경로

### SVG 1.1 — 명목상 둘, 실질 넷

SVG 1.1 §6.3은 대분류를 **둘**로 잡는다.

> "Styling properties can be assigned to SVG elements in the following **two ways**: **Presentation attributes** … **CSS Stylesheets** …"

그런데 두 번째 갈래가 §6.8에서 다시 셋으로 쪼개진다.

> "**External CSS style sheets** [XML-SS], **CSS style sheets within 'style' elements** and **CSS declaration blocks** … **within 'style' attributes** attached to specific SVG elements."

외부 스타일시트의 참조 수단은 HTML의 `<link>`가 아니라 **XML 처리 명령**이다.

> "External style sheets are referenced using the mechanism documented in Associating Style Sheets with XML documents Version 1.0 [XML-SS]."

즉 `<?xml-stylesheet type="text/css" href="…"?>`다.

### SVG 2 — 다섯으로 늘고, 지원이 필수로 승격

SVG 2 §6.1의 한 문장이 규범적으로 가장 중요한 변화다.

> "In SVG 1.1, support for inline style sheets using the ‘style’ element and ‘style’ **was not required. In SVG 2, these are required.**"

SVG 1.1은 `<style>` 지원을 "CSS를 지원하는 사용자 에이전트라면"이라는 조건절 아래 두었다. 그래서 CSS를 전혀 모르는 뷰어도 **적합(conforming)**할 수 있었다. SVG 2는 그 조건절을 없앴다.

경로도 하나 늘어난다.

> "An HTML ‘link’ element in an SVG document … with its ‘rel’ attribute set to 'stylesheet' must be processed as defined in the HTML specification"

> "Note that an alternative way to reference external style sheets without using the HTML ‘link’ element is to use an **@import rule in an inline style sheet**."

### 정리

| # | 경로 | SVG 1.1 | SVG 2 |
|---|---|---|---|
| ① | 프레젠테이션 속성 `fill="red"` | ○ | ○ |
| ② | `style` 속성 `style="fill:red"` | ○ | ○ |
| ③ | `<style>` 요소 | ○ (조건부) | ○ (필수) |
| ④ | HTML `<link rel="stylesheet">` | — | ○ |
| ⑤ | `<?xml-stylesheet?>` PI | ○ | ○ |

여기에 **CSS 상속**이 별도 축으로 겹친다. 부모 `<g>`에 걸린 `fill`이 자식에게 내려오는 경로다.

그리고 ③ 안의 `@import`가 ④⑤와 같은 효과를 우회로로 낸다. **`<style>` 하나를 지원하기 시작하면 `@import` 처리 여부라는 후속 질문이 따라붙는다.**

---

## 2. 우선순위 — 프레젠테이션 속성이 최약체다

### 두 판본이 같은 결론을 말한다

SVG 1.1 §6.4:

> "The presentation attributes thus will participate in the CSS2 cascade as if they were replaced by corresponding CSS style rules placed at the start of the author style sheet **with a specificity of zero.** In general, this means that the presentation attributes have **lower priority** than other CSS style rules"

SVG 2 §6.6:

> "Presentation attributes contribute to the author level of the cascade, following all other author-level style sheets, and **have specificity 0.**"

SVG 2는 CSS2 §6.4.4 참조를 걷어내고 직접 서술로 바꿨을 뿐, **결론은 동일하다.**

탈출구도 막혀 있다. 두 판본 모두 프레젠테이션 속성 안의 `!important`를 **무효값**으로 규정한다.

> "an !important declaration within a presentation attribute will cause it to have an **invalid value**."

### 인라인 style 속성은 최강이다

CSS Cascade Level 4:

> "declarations that do not belong to a style rule (such as the contents of a style attribute) are considered to have a **specificity higher than any selector**."

### 최종 순위

| 순위 | 경로 | 근거 |
|---|---|---|
| 1 (최강) | `style` 속성 | "specificity higher than any selector" |
| 2 | `<style>`·외부 스타일시트의 규칙 | specificity 계산으로 서로 경쟁 |
| 3 (최약) | 프레젠테이션 속성 | "specificity of zero" |

### 실무적 함정

**`<style>`의 `rect { fill: red }` 한 줄이 요소의 `fill="blue"`를 이긴다.** 타입 셀렉터의 specificity는 (0,0,1)이고 프레젠테이션 속성은 0이기 때문이다.

이것이 이 주제의 핵심이다. `<style>`을 읽지 않는 파서의 실패는 **조용하고, 그럴듯하다.** 파싱이 실패하는 것이 아니라 아무 경고 없이 **틀린 색으로 잘 그려진다.** 사용자는 도면이 정상적으로 열렸다고 믿는다.

색을 기준으로 도형을 분류하거나 레이어를 나누는 프로그램이라면, 스타일 오독은 표시 품질 문제가 아니라 **분류 자체가 무너지는 문제**다.

---

## 3. `<style>` 요소의 요건 — 파서가 틀리기 쉬운 지점들

### type이 없어도 CSS다

> SVG 1.1: "**If a ‘type’ is not provided**, the value of ‘contentStyleType’ on the ‘svg’ element shall be used, **which in turn defaults to "text/css"**."
> SVG 2: "**If the attribute is not specified, then the style sheet language is assumed to be CSS.**"

파서는 `type` 속성 **유무**로 처리 여부를 가르면 안 된다. `type`이 명시되고 그 값이 `text/css`가 **아닐 때만** 건너뛰는 것이 맞다.

### media가 없어도 무조건 적용된다

기본값이 `all`이다. SVG 1.1은 미디어 서술자 목록으로, SVG 2는 미디어 쿼리로 해석한다. 정적 렌더링 도구라면 `all`·`screen`만 통과시키고 `print` 전용은 무시하는 근사가 가능하다.

### CDATA는 권고이지 강제가 아니다

> "Placing internal CSS style sheets within CDATA blocks is **sometimes necessary** since CSS style sheets can include characters, such as ">", which conflict with XML parsers. … **it is highly recommended**"

"sometimes necessary" / "highly recommended"이지 MUST가 아니다. 따라서 파서는 **CDATA로 감싼 경우와 감싸지 않은 경우를 둘 다** 처리해야 한다.

SAX 계열 파서(`XMLParser`/`NSXMLParser` 등)는 CDATA를 `foundCDATA:`로, 일반 텍스트를 `foundCharacters:`로 **나눠서** 보낸다. **두 콜백을 모두 붙여 이어붙여야** 한다. 하나만 구현하면 절반의 파일에서 조용히 실패한다.

### 배치 위치에 제약이 없다 — 이것이 구조를 결정한다

SVG 1.1 §6.15:

> "Style sheets defined **anywhere within** the SVG document … **apply across the entire SVG document.**"

`<defs>` 안이든 문서 맨 끝이든, 어디에 있든 문서 전체에 적용된다.

**이 한 줄이 파싱 전략을 결정한다.** SAX 방식으로 한 번 훑으면서 만나는 순서대로 스타일을 확정하는 구조로는 `<style>`을 **원리적으로 지원할 수 없다.** 도형보다 뒤에 나온 `<style>`도 그 도형에 적용돼야 하기 때문이다.

따라서 [[2-pass 파싱]]이 선행되어야 한다 — 1차에서 `<style>` 텍스트와 요소별 `class`/`id`만 수집하고, 2차에서 도형을 해석한다. 이는 스타일 해석 모듈이 아니라 **파서 자체의 구조 변경**이다.

---

## 4. 실무에서 `<style>` 블록은 얼마나 흔한가

**확인된 사실**

- **Adobe Illustrator는 `<style>` 블록 출력을 정식 옵션으로 제공한다.** SVG 저장 옵션의 "CSS Properties"에서 네 갈래 중 하나를 고르는데, 그중 하나가 **Style Elements**다. 이 경로를 택하면 `.cls-1`, `.cls-2` 같은 자동 생성 클래스명과 `class` 속성 쌍이 나온다. **도형 수가 많고 스타일 종류가 적을수록 파일 크기 이득이 커서 선택될 유인이 크다** — 즉 "같은 스타일의 벽 선이 수천 개"인 층 평면도가 정확히 그 조건이다.
- **Inkscape의 기본값은 인라인 `style` 속성**이다. `<style>` 요소를 기본으로 만들지 않는다.
- **Qt `QSvgGenerator` 계열(QGIS 인쇄 레이아웃 SVG 포함)은 요소별 속성 위주의 단순 출력**을 낸다.

**미확인 (`확인 필요`)**

- Illustrator의 Export As / Save As 각각의 **기본 선택값** — Adobe 공식 문서 두 곳이 조회 실패했고 2차 자료의 서술이 엇갈린다.
- Visio 네이티브 SVG 저장의 스타일 경로 — 공식 문서 확인 실패.
- AutoCAD는 SVG를 1급 내보내기 형식으로 다루지 않아 변환기마다 다르다 — **단일한 답이 없다.**
- SVGO 등 최적화 도구가 중간에 끼면 경로가 통째로 바뀔 수 있다. **받은 파일이 원 익스포터의 출력 그대로라는 보장이 없다.**

**정리:** `<style>`은 드문 예외가 아니라 주요 편집기가 정식 옵션으로 제공하고, 도형이 많은 도면일수록 선택될 유인이 큰 경로다. 다만 전면적으로 위험한 것도 아니다 — **입력 출처에 따라 갈린다.**

---

## 5. 지원한다면 어디까지

스펙이 요구하는 범위는 **범용 뷰어** 기준이라 정적 파싱 도구에는 과잉이다. `:hover`·`:active`·`:focus`는 상호작용 상태라 정지 파싱에서 의미가 없고, `::first-letter`는 텍스트 렌더링용이다.

[[specificity]] 계산은 Selectors Level 4가 정의한다 — **A**(id) / **B**(class·속성·의사 클래스) / **C**(타입·의사 요소) 세 자리를 사전식 비교하고, 동률이면 문서 순서상 뒤가 이긴다.

실용적 절단선은 다음과 같다.

| 단계 | 대상 | specificity | 이유 |
|---|---|---|---|
| 필수 | 클래스 `.cls-1` | (0,1,0) | Illustrator 출력의 사실상 전부 |
| 필수 | 타입 `rect` | (0,0,1) | 손으로 쓴 SVG·간이 익스포터 |
| 필수 | 그룹 `.a, .b` | 각 항 개별 | 익스포터가 동일 스타일을 묶을 때 |
| 필수 | 복합 `rect.cls-1` | 합산 | 위 세 가지의 자연스러운 조합 |
| 권장 | id `#foo` | (1,0,0) | 드물지만 계산이 단순 |
| 권장 | `!important` | origin 승격 | 무시하면 우선순위가 뒤집힌다 |
| 선택 | 후손 `g .cls-1` | 합산 | 익스포터 출력에서는 드묾 |
| 제외 | 의사 클래스·의사 요소 | — | 정지 파싱에서 무의미 |
| 제외 | `@font-face`·`@charset` | — | 텍스트 미지원 시 불필요 |

스펙이 못 박은 파싱 제약도 둘 있다.

- **타입 셀렉터는 local name으로만 매칭한다.** SVG 1.1 §6.8: "type selectors will only match against the **local part** of the element's qualified name." 네임스페이스 한정을 구현할 필요가 없다는 뜻이자, 접두사가 붙은 문서에서도 `rect`로 매칭해야 한다는 뜻이다.
- **CSS 속성명은 대소문자를 구분하지 않지만 값은 구분할 수 있다.** 입력 전체를 소문자화하는 구현은 색상 키워드에는 안전하지만 `url(#Gradient1)` 같은 참조를 다루게 되면 깨진다.

---

## 6. 지원하지 않기로 했다면 — 최소한 이것은 해야 한다

`<style>` 지원을 미루는 판단 자체는 합리적일 수 있다. 3절에서 본 대로 파서 구조 변경이 선행되어야 하기 때문이다.

다만 **미루는 것과 모른 척하는 것은 다르다.**

**오작동이 조용하다는 것이 핵심 위험이다.** 파싱이 실패하면 사용자가 다른 형식으로 다시 내보내면 된다. 그런데 조용히 틀린 색으로 그려지면 사용자는 그것이 원본이라고 믿는다.

그래서 **셀렉터 엔진을 만들기 전에 `<style>` 요소의 존재를 감지해 경고하는 것이 우선순위 1**이다. "이 SVG는 CSS 스타일시트를 포함하고 있어 색·선폭이 원본과 다르게 표시될 수 있습니다" 한 줄이면 되고, 구현은 요소명 검사 한 줄이다.

그리고 **입력 출처를 통제할 수 있다면 위험이 크게 줄어든다.** Illustrator 산출물을 받는다면 "CSS Properties를 Presentation Attributes로 두고 내보내 달라"는 안내만으로 실질적으로 해결된다. **문서화와 경고가 코드보다 먼저다.**

---

## 관련 링크

- [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] — SVG 파싱이 놓인 전체 파이프라인
- [[12) 도면을 폴리곤으로 닫는 허용 오차 — 절대 치수인가 비례값인가]] — 같은 SVG 입력에서 생기는 다른 축의 문제
- [[프레젠테이션 속성]] · [[CSS 캐스케이드]] · [[specificity]] · [[2-pass 파싱]]

## 미해결 질문

- SVG 2 §6.6("author level … following all other author-level style sheets")과 CSS Cascade 4의 별도 presentational hint origin 사이 문언 불일치 — 전칭 셀렉터 `*`(0,0,0)와 맞붙는 경계 사례의 실제 해소 방식 미확인. 정적 파싱 용도에는 영향 없음. `확인 필요`
- Illustrator Export As / Save As의 CSS Properties 기본 선택값 — 공식 문서 조회 실패. 실물 산출물로 재확인 필요. `확인 필요`
- Visio 네이티브 SVG 저장의 스타일 경로 — 공식 문서 확인 실패. `확인 필요`
- SVGO 등 최적화 도구가 프레젠테이션 속성 ↔ `<style>` 클래스를 재작성하는 조건 — 미조사. `TODO`
