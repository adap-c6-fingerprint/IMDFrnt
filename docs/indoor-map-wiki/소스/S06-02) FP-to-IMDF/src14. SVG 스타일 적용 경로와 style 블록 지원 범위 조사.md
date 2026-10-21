---
summary: "FP-to-IMDF 앱 StyleResolver가 '1차 범위 밖'으로 남긴 CSS `<style>` 블록 지원 여부를 W3C 스펙 원문으로 확정. (1) SVG의 스타일 적용 경로는 프레젠테이션 속성·`style` 속성·`<style>` 요소·외부 스타일시트 네 가지, (2) 프레젠테이션 속성은 specificity 0으로 어떤 CSS 선언에도 지는 최하위이며 SVG 2에서 `<style>` 지원이 선택에서 필수로 승격, (3) `<style>`의 type 기본값 text/css·media 기본값 all·CDATA 권고, (4) Illustrator·Inkscape 등 익스포터가 실제로 쓰는 경로, (5) 지원 시 구현해야 할 최소 셀렉터 범위와 specificity 계산"
source: "W3C SVG 1.1 Second Edition Chapter 6 Styling, W3C SVG 2 Chapter 6 Styling, CSS Cascading and Inheritance Level 4, Selectors Level 4, css-tricks.com·Inkscape 커뮤니티 문서(익스포터 관행)"
created: "2026-08-29 00:00"
updated: "2026-08-29 00:00"
---
# SVG 스타일 적용 경로와 style 블록 지원 범위 조사

## 수집 기준

- 수집일: 2026-08-29
- 목적: FP-to-IMDF 앱 `~/Desktop/IM-DFrnt/Sources/IMDFrnt/SVG/StyleResolver.swift:5`의 주석 "CSS `<style>` 블록 셀렉터는 1차 범위 밖(확인 필요)"를 확정하기 위한 조사. 현재 구현은 `merge(_:attributes:)`에서 **인라인 `style` 속성 → 프레젠테이션 속성 → 부모 상속** 세 경로만 합치고, `SVGParser.swift`의 `drawableElements` 집합에 `style` 요소가 없어 `<style>` 블록의 텍스트는 아예 읽지 않는다. 이 설계 결정이 스펙상 타당한 절충인지, 아니면 사양 위반이자 실무상 위험인지 판정한다.
- 방법: W3C SVG 1.1 Second Edition 6장, SVG 2 6장의 원문을 직접 조회(HTML 원본 다운로드 후 본문 추출)해 인용. CSS Cascade Level 4와 Selectors Level 4로 cascade·specificity 규정을 보강. 익스포터 관행은 벤더 문서와 커뮤니티 자료로 보조 확인하되 스펙과 구분해 표기.

## 핵심 출처

- W3C SVG 1.1 (Second Edition), Chapter 6 Styling: https://www.w3.org/TR/SVG11/styling.html
- W3C SVG 2, Chapter 6 Styling: https://www.w3.org/TR/SVG2/styling.html
- W3C CSS Cascading and Inheritance Level 4: https://www.w3.org/TR/css-cascade-4/
- W3C Selectors Level 4, §Calculating a selector's specificity: https://www.w3.org/TR/selectors-4/#specificity-rules
- CSS-Tricks, "The Different Ways of Getting SVG Out of Adobe Illustrator": https://css-tricks.com/illustrator-to-svg/
- Adobe 공식 SVG 옵션 문서(https://helpx.adobe.com/illustrator/using/svg.html, /using/saving-artwork.html)는 2026-08-29 조회 시 두 차례 모두 60초 타임아웃으로 **본문 취득 실패**. Illustrator 옵션명의 정확한 원문은 CSS-Tricks 및 커뮤니티 자료로 대체 확인했고, 해당 부분은 아래에서 `확인 필요`로 표시한다.

---

## 1. 스타일 적용 경로는 몇 가지인가

### 1.1 SVG 1.1 — 명목상 두 가지, 실질 네 가지

SVG 1.1 §6.3 "Alternative ways to specify styling properties" 원문:

> "Styling properties can be assigned to SVG elements in the following **two ways**:
> **Presentation attributes** — Styling properties can be assigned using SVG's presentation attributes. For each styling property defined in this specification, there is a corresponding XML presentation attribute available on all relevant SVG elements. […] Conforming SVG Interpreters and Conforming SVG Viewers are required to support SVG's presentation attributes.
> **CSS Stylesheets** — To support usage scenario 3 above, SVG content can be styled with CSS. […] Conforming SVG Interpreters and Conforming SVG Viewers that support CSS styling of generic (i.e., text-based) XML content are required to also support CSS styling of SVG content."

1.1은 대분류를 **둘**로 잡지만, 두 번째 갈래인 "CSS Stylesheets"가 §6.8에서 다시 셋으로 쪼개진다.

> "In an SVG user agent that supports CSS style sheets, the following facilities from CSS2 must be supported: […] **External CSS style sheets** [XML-SS], **CSS style sheets within 'style' elements** and **CSS declaration blocks** ([CSS2], section 4.1.7) **within 'style' attributes** attached to specific SVG elements."

외부 스타일시트의 참조 수단은 §6.9가 지정한다.

> "External style sheets are referenced using the mechanism documented in Associating Style Sheets with XML documents Version 1.0 [XML-SS]."

즉 XML 처리 명령 `<?xml-stylesheet type="text/css" href="…"?>`다. HTML의 `<link>`가 아니다.

**판정:** SVG 1.1에서 스타일이 요소에 도달하는 경로는 실질적으로 **네 가지**다 — ① 프레젠테이션 속성, ② `style` 속성(인라인 선언), ③ `<style>` 요소(문서 내장 스타일시트), ④ `<?xml-stylesheet?>` 처리 명령(외부 스타일시트). 여기에 CSS 상속(property inheritance)이 별도 축으로 겹친다. 현재 앱은 ①②와 상속만 구현했고 ③④는 미구현이다.

### 1.2 SVG 2 — 다섯 가지로 확장되고, 지원이 "필수"로 승격

SVG 2 §6.1 원문:

> "Elements in an SVG document can be styled using CSS. […] **SVG user agents must support all of the CSS styling mechanisms described in this chapter.**
> In SVG 1.1, support for inline style sheets using the ‘style’ element and ‘style’ was not required. **In SVG 2, these are required.**"

이 한 문장이 이번 조사에서 가장 중요한 규범적 변화다. SVG 1.1은 `<style>` 지원을 "CSS를 지원하는 사용자 에이전트라면"이라는 조건절 아래 두었고, 그래서 CSS를 전혀 모르는 뷰어도 **적합(conforming)**할 수 있었다. SVG 2는 그 조건절을 없앴다.

경로 목록도 늘어난다. §6.3 원문:

> "An HTML ‘link’ element in an SVG document (that is, an element in the HTML namespace with local name "link") with its ‘rel’ attribute set to 'stylesheet' must be processed as defined in the HTML specification and cause external style sheets to be loaded and applied to the document."
> "Note that an alternative way to reference external style sheets without using the HTML ‘link’ element is to use an **@import rule in an inline style sheet**."
> "Or, in XML documents, external CSS style sheets may be included using the **<?xml-stylesheet?> processing instruction** [xml-stylesheet]."

**판정:** SVG 2의 경로는 **다섯 가지**다 — ① 프레젠테이션 속성, ② `style` 속성, ③ `<style>` 요소, ④ HTML 네임스페이스 `<link rel="stylesheet">`, ⑤ `<?xml-stylesheet?>` PI. 그리고 ③ 안의 `@import`가 ④⑤와 같은 효과를 우회로로 낸다. `<style>` 하나를 지원하기 시작하면 `@import` 처리 여부라는 후속 질문이 따라붙는다는 뜻이기도 하다.

---

## 2. cascade에서 프레젠테이션 속성의 지위

### 2.1 SVG 1.1 — "author 스타일시트 맨 앞, specificity 0"

SVG 1.1 §6.4 원문:

> "For user agents that support CSS, the presentation attributes must be translated to corresponding CSS style rules according to rules described in Precedence of non-CSS presentational hints ([CSS2], section 6.4.4), with the additional clarification that the presentation attributes are conceptually inserted into a new author style sheet which is the first in the author style sheet collection. **The presentation attributes thus will participate in the CSS2 cascade as if they were replaced by corresponding CSS style rules placed at the start of the author style sheet with a specificity of zero.** In general, this means that the presentation attributes have **lower priority** than other CSS style rules specified in author style sheets or ‘style’ attributes."

같은 절의 부수 규정:

> "An !important declaration ([CSS2], section 6.4.2) within a presentation attribute definition is an invalid value."

프레젠테이션 속성 안에 `!important`를 써서 우선순위를 끌어올리는 탈출구는 막혀 있다는 뜻이다.

### 2.2 SVG 2 — 문언은 다듬어졌지만 결론은 동일

SVG 2 §6.6 원문:

> "Some styling properties can be specified not only in style sheets and ‘style’ attributes, but also in **presentation attributes**. These are attributes whose name matches (or is similar to) a given CSS property and whose value is parsed as a value of that property.
> **Presentation attributes contribute to the author level of the cascade, following all other author-level style sheets, and have specificity 0.**
> Since presentation attributes are parsed as CSS values, not declarations, an !important declaration within a presentation attribute will cause it to have an **invalid value**."

SVG 2는 CSS2 §6.4.4 참조를 걷어내고 "author level of the cascade … specificity 0"이라는 직접 서술로 바꿨다. 두 판본 모두 결론은 같다 — **프레젠테이션 속성은 CSS 선언에 진다.**

### 2.3 CSS Cascade Level 4와의 관계

CSS Cascade 4의 origin 정렬 원문(내림차순):

> "1. Transition declarations / 2. Important user agent declarations / 3. Important user declarations / 4. Important author declarations / 5. Animation declarations / 6. Normal author declarations / 7. Normal user declarations / 8. Normal user agent declarations"

프레젠테이션 힌트에 대한 원문:

> "All document language-based styling must be translated to corresponding CSS rules and enter the cascade as rules in either the UA-origin or a **special-purpose author presentational hint origin between the regular user origin and the author origin**."

인라인 선언에 대한 원문:

> "declarations that do not belong to a style rule (such as the contents of a style attribute) are considered to have a **specificity higher than any selector**."

**판정:** 세 문서를 합치면 실제 우선순위는 다음 순서로 굳는다(모두 normal 선언 기준, `!important` 제외).

| 순위 | 경로 | 근거 |
|---|---|---|
| 1 (최강) | `style` 속성(인라인 선언) | css-cascade-4 "specificity higher than any selector" |
| 2 | `<style>` 요소 / 외부 스타일시트의 규칙 | specificity 계산 결과로 서로 경쟁 |
| 3 (최약) | 프레젠테이션 속성 | SVG 1.1·2 공통 "specificity of zero" / presentational hint origin |

여기서 실무상 함정이 나온다. **`<style>` 블록의 `rect { fill: red }` 같은 타입 셀렉터 한 줄이 요소에 붙은 `fill="blue"` 프레젠테이션 속성을 이긴다.** 타입 셀렉터의 specificity는 (0,0,1)이고 프레젠테이션 속성은 0이기 때문이다. `<style>`을 무시하는 파서는 스타일을 "덜 반영"하는 것이 아니라 **정반대 색을 그린다**.

한 가지 문언상 미세한 불일치는 남는다. SVG 2는 프레젠테이션 속성을 "author level … following all other author-level style sheets"라고 서술하는 반면 CSS Cascade 4는 author origin **아래**의 별도 presentational hint origin에 둔다. specificity 0이 사실상 모든 셀렉터에 지므로 두 서술의 결과는 거의 언제나 같지만, 전칭 셀렉터 `* { … }`(specificity 0,0,0)와 맞붙는 극단적 경우에는 갈릴 여지가 있다. 이 앱 용도에서는 무시해도 되지만 **정확한 판정은 `확인 필요`**로 남긴다.

---

## 3. `<style>` 요소의 스펙상 요건

### 3.1 SVG 1.1 §6.10

> "The ‘style’ element allows style sheets to be embedded directly within SVG content. SVG's ‘style’ element has the same attributes as the corresponding element in HTML."
> **Content model:** "Any elements or character data."
> **type** — "This attribute specifies the style sheet language of the element's contents. The style sheet language is specified as a content type (e.g., "text/css"), as per MIME Part Two: Media Types [RFC2046]. **If a ‘type’ is not provided, the value of ‘contentStyleType’ on the ‘svg’ element shall be used, which in turn defaults to "text/css"**. If a ‘style’ element falls outside of the outermost svg element and the ‘type’ is not provided, the ‘type’ must default to "text/css"."
> **media** — "This attribute specifies the intended destination medium for style information. It may be a single media descriptor or a comma-separated list. **The default value for this attribute is "all"**."
> **title** — "(For compatibility with HTML 4.) This attribute specifies an advisory title for the ‘style’ element."

CDATA에 대한 §6.6 원문:

> "Note how the CSS style sheet is placed within a CDATA construct (i.e., `<![CDATA[ ... ]]>`). **Placing internal CSS style sheets within CDATA blocks is sometimes necessary since CSS style sheets can include characters, such as ">", which conflict with XML parsers.** Even if a given style sheet does not use characters that conflict with XML parsing, **it is highly recommended that internal style sheets be placed inside CDATA blocks.**"

배치 위치에 대한 §6.15 원문:

> "**Stand-alone SVG document** — There is one parse tree. Style sheets defined **anywhere within** the SVG document (in style elements or style attributes, or in external style sheets linked with the style sheet processing instruction) **apply across the entire SVG document**."

### 3.2 SVG 2 §6.2

> "The ‘style’ element allows style sheets to be embedded directly within SVG content. SVG's ‘style’ element has the same attributes as the corresponding element in HTML."
> **Content model:** "**Character data.**"
> **type** — 초기값 `text/css`. "This attribute specifies the style sheet language of the element's contents, as a media type [rfc2046]. **If the attribute is not specified, then the style sheet language is assumed to be CSS.**"
> **media** — 초기값 `all`. "This attribute specifies a **media query** that must be matched for the style sheet to apply. Its value is parsed as a media_query_list. **If not specified, the style sheet applies unconditionally.**"
> "The semantics and processing of a ‘style’ and its attributes must be the same as is defined for the HTML ‘style’ element."
> "The style sheet's text content is **never directly rendered**; the display value for the ‘style’ element must always be set to none by the user agent style sheet, and this declaration must have importance over any other CSS rule or presentation attribute."

**판정 (요건 정리):**

- **`type` 없어도 CSS다.** 두 판본 모두 기본값이 `text/css`이므로, 파서는 `type` 속성 유무로 처리 여부를 가르면 안 된다. `type`이 명시되고 그 값이 `text/css`가 **아닐** 때만 건너뛰는 것이 맞다.
- **`media` 없어도 무조건 적용된다.** 기본값 `all`. `media`가 붙어 있으면 SVG 1.1은 미디어 서술자 목록, SVG 2는 미디어 쿼리로 해석한다. 화면 렌더링 도구 관점에서는 `all`·`screen`만 통과시키고 `print` 전용은 무시하는 근사가 가능하다.
- **CDATA는 강력 권고이지 강제가 아니다.** 스펙 문언은 "sometimes necessary" / "highly recommended"다. 따라서 파서는 CDATA로 감싼 경우와 감싸지 않은 경우를 **둘 다** 처리해야 한다. `XMLParser`(NSXMLParser)는 CDATA를 `foundCDATA:` 델리게이트로, 일반 텍스트를 `foundCharacters:`로 나눠 보내므로 **두 콜백을 모두 붙여 이어붙여야** 한다. 이 점은 구현상 실수하기 쉬운 지점이다.
- **배치 위치에 제약이 없다.** §6.15의 "anywhere within … apply across the entire SVG document"가 결정적이다. `<defs>` 안이든 문서 끝이든, 문서 어디에 있든 문서 전체에 적용된다. 이는 파싱 전략에 직접적인 결과를 낳는다 — **SAX 방식으로 한 번 훑으면서 스타일을 즉시 확정하는 현재 구조로는 `<style>`을 지원할 수 없다.** `<style>`이 도형들보다 뒤에 나올 수 있기 때문이다. 2-pass(1차: `<style>` 수집, 2차: 도형 해석)나 DOM 구축 후 후처리가 필요하다.
- SVG 1.1의 콘텐츠 모델은 "Any elements or character data"로 느슨했지만 SVG 2는 "Character data"로 좁혔다. 실무상 텍스트만 읽으면 된다.

---

## 4. 실무에서 `<style>` 블록은 얼마나 흔한가

이 절은 스펙이 아니라 도구 동작에 관한 것이므로 **사실과 추정을 구분해 표기**한다.

**사실로 확인된 것:**

- **Adobe Illustrator는 `<style>` 블록 출력을 정식 옵션으로 제공한다.** SVG 저장/내보내기 옵션의 "CSS Properties" 항목에서 네 갈래 중 하나를 고른다 — Presentation Attributes / Style Attributes(= 인라인 `style`) / Style Attributes (Entity References) / **Style Elements**. CSS-Tricks 원문: "‘Presentation Attributes’ means stuff like `fill: red;` rather than ‘Inline Styles’ which means `style='fill: red;'`. Presentation attributes are easier to override in CSS. Inline styles provide more style resilience. **There is also an option to export styles in a `<style>` block within the SVG**, which may be efficient on SVG with lots of similar elements." Illustrator가 이 경로를 택하면 `.cls-1`, `.cls-2` 같은 자동 생성 클래스명과 `class` 속성 쌍이 나온다. 도형 수가 많고 스타일 종류가 적은 도면일수록 파일 크기 이득이 커서 선택될 유인이 크다.
- **Inkscape의 기본값은 인라인 `style` 속성이다.** 각 요소에 `style="fill:#000000;stroke:none;…"`를 붙이며, `<style>` 요소를 기본으로 만들지 않는다. 다만 "Optimized SVG로 저장" 시 "convert CSS attributes to XML attributes" 옵션으로 프레젠테이션 속성 변환을 시도할 수 있다. 즉 Inkscape 산출물은 현재 앱 구현으로 대부분 커버된다.
- **Qt `QSvgGenerator` 계열(QGIS 인쇄 레이아웃 SVG 내보내기 포함)은 요소별 속성 위주의 단순한 출력을 낸다.** QGIS 문서 및 개발자 메일링 리스트에서 "SVG 출력이 매우 기초적이며 이는 QGIS가 아니라 하부 Qt 라이브러리의 한계"라는 서술이 확인된다.

**추정 또는 미확인 (`확인 필요`):**

- Illustrator에서 "Export As > SVG"와 "Save As > SVG" 각각의 **기본 선택값**이 무엇인지 — 자료마다 "Presentation Attributes가 기본일 가능성이 높다"는 서술과 "Internal CSS가 기본"이라는 서술이 엇갈린다. Adobe 공식 문서 두 곳이 모두 타임아웃으로 취득 실패해 확정하지 못했다.
- **AutoCAD의 SVG 출력 경로** — AutoCAD는 SVG를 1급 내보내기 형식으로 다루지 않고 서드파티 플러그인·변환기를 거치는 것이 일반적이라, "AutoCAD가 내보낸 SVG"의 스타일 경로는 변환기마다 다르다. 단일한 답이 없으므로 확정 불가.
- **Visio의 SVG 저장 산출물 구조** — File > Save As로 SVG 저장이 가능한 것은 확인했으나, 그 산출물이 `<style>` 블록을 쓰는지 프레젠테이션 속성을 쓰는지는 공식 문서에서 확인하지 못했다. SvgPublish 같은 서드파티 애드인이 CSS 클래스 태깅을 지원한다는 서술로 미루어 클래스 기반 출력이 존재할 가능성은 있으나 추정이다.
- 웹 최적화 도구(SVGO, svgcleaner) 및 CAD→SVG 변환 스크립트가 중간에 끼면 경로가 통째로 바뀐다. 앱이 받는 파일이 원 익스포터의 출력 그대로라는 보장이 없다는 점도 위험 요인이다.

**판정:** `<style>` 블록은 드문 예외가 아니라 **주요 벡터 편집기가 정식 옵션으로 제공하고, 도형이 많은 도면에서 오히려 선택될 유인이 큰 경로**다. 특히 층 평면도처럼 "같은 스타일의 벽 선이 수천 개" 있는 입력은 Illustrator의 Style Elements 옵션이 가장 큰 이득을 보는 형태다. 반면 Inkscape·Qt 계열은 현재 구현으로 충분하다. 요약하면 — **안전하지 않다. 다만 전면적으로 위험한 것도 아니고, 입력 출처에 따라 갈린다.**

---

## 5. 지원한다면 최소 어느 범위까지 구현해야 하는가

### 5.1 스펙이 요구하는 범위 (참고선, 전량 구현 대상 아님)

SVG 1.1 §6.8:

> "CSS2 **selectors** within style sheets ([CSS2], chapter 5). Because SVG is intended to be used as one component in a multiple namespace XML application and CSS2 is not namespace aware, **type selectors will only match against the local part of the element's qualified name.**"
> "CSS2 rules for assigning property values, **cascading and inheritance** ([CSS2], chapter 6)."
> "**@font-face, @media, @import and @charset rules** within style sheets."
> "CSS2's dynamic pseudo-classes :hover, :active and :focus and pseudo-classes :first-child, :visited, :link and :lang must be supported."

SVG 2 §6.9:

> "Besides the features described above, the following CSS features must be also supported in SVG user agents: in XML documents, external CSS style sheets using the `<?xml-stylesheet?>` processing instruction; **@media, @import and @charset rules** within style sheets, as defined in CSS 2.1; **@font-face** rules within style sheets; **all pseudo-classes defined in CSS 2.1** (including :hover, :link, :active, :visited, :focus, :first-child and :lang); the ::first-letter and ::first-line pseudo-elements defined in CSS 2.1 (on ‘text’ elements)."

이것은 **범용 SVG 뷰어**에 대한 요구다. 도면을 정지 상태로 한 번 읽어 벡터 개체로 평탄화하는 도구에는 과잉이다. `:hover`·`:active`·`:focus`는 상호작용 상태이므로 정지 파싱에서 의미가 없고, `::first-letter`·`::first-line`은 텍스트 렌더링용인데 이 앱은 `text` 요소를 아예 그리지 않는다(`drawableElements`에 없다).

### 5.2 specificity 계산 규칙

Selectors Level 4 §Calculating a selector's specificity 원문 요지:

> **A** — "ID selectors"
> **B** — "class selectors, attribute selectors, and pseudo-classes"
> **C** — "type selectors and pseudo-elements"
> "The universal selector contributes nothing to the specificity of a selector."

(A, B, C) 세 자리 수를 사전식으로 비교하고, 동률이면 문서 순서상 뒤에 나온 규칙이 이긴다.

### 5.3 실용 최소 구현 범위 (권고)

도면 파싱 용도로 **실제 산출물에 등장할 확률과 구현 비용**을 함께 따져 다음 순서로 자른다.

| 단계 | 셀렉터·기능 | specificity | 필요성 |
|---|---|---|---|
| 필수 | 클래스 셀렉터 `.cls-1` | (0,1,0) | Illustrator Style Elements 출력의 사실상 전부 |
| 필수 | 타입 셀렉터 `rect`, `path` | (0,0,1) | 손으로 쓴 SVG·간이 익스포터에서 흔함 |
| 필수 | 그룹(콤마) 셀렉터 `.a, .b` | 각 항 개별 계산 | 익스포터가 동일 스타일을 묶을 때 사용 |
| 필수 | 복합 셀렉터 `rect.cls-1` | 합산 | 위 세 가지의 자연스러운 조합 |
| 권장 | id 셀렉터 `#foo` | (1,0,0) | 드물지만 계산 규칙이 단순해 비용 대비 이득 |
| 권장 | `!important` 처리 | origin 승격 | 무시하면 우선순위가 뒤집힌다 |
| 선택 | 후손 셀렉터 `g .cls-1`, 자식 `>` | 합산 | 익스포터 출력에서는 드묾. 조상 스택 추적 필요 |
| 제외 | 의사 클래스·의사 요소 전부 | — | 정지 파싱에서 무의미 |
| 제외 | `@font-face`, `@charset` | — | 텍스트 미지원 |
| 제외 (초기) | `@media`, `@import` | — | `@media`는 `all`/`screen`만 통과시키는 근사, `@import`는 외부 파일 접근이므로 보류 타당 |

여기에 스펙이 못 박은 두 가지 파싱 제약이 붙는다.

- **타입 셀렉터는 local name으로만 매칭한다** (SVG 1.1 §6.8 인용문). `svg|rect` 같은 네임스페이스 한정을 구현할 필요가 없다는 뜻이자, 접두사가 붙은 문서에서도 `rect`로 매칭해야 한다는 뜻이다. `SVGParser`가 이미 `elementName.lowercased()`로 local name을 쓰고 있어 이 부분은 그대로 맞다.
- **CSS 속성명은 대소문자를 구분하지 않지만 값은 구분할 수 있다.** 현재 `StyleResolver.color`가 입력을 `lowercased()` 처리하는데, 색상 키워드·16진 표기에는 안전하나 `url(#Gradient1)` 같은 참조를 다루게 되면 문제가 된다. 지금은 `url(...)`을 파싱하지 않으므로 실해는 없다.

---

## FP-to-IMDF 앱에 대한 결론

**질문 1 — 스타일 적용 경로는 몇 가지인가.**
SVG 1.1 기준 네 가지(프레젠테이션 속성 / `style` 속성 / `<style>` 요소 / `<?xml-stylesheet?>` PI), SVG 2 기준 다섯 가지(여기에 HTML `<link rel="stylesheet">` 추가, 그리고 `<style>` 내부 `@import`가 우회로). 여기에 CSS 상속이 별도 축으로 작동한다. 현재 앱은 **네 경로 중 둘 + 상속**을 처리한다.

**질문 2 — cascade 우선순위.**
`style` 속성 > `<style>`·외부 스타일시트 규칙 > 프레젠테이션 속성 순이다. 프레젠테이션 속성은 SVG 1.1이 "placed at the start of the author style sheet **with a specificity of zero**", SVG 2가 "contribute to the author level of the cascade … **and have specificity 0**"으로 명시한 **최하위**다. 두 판본 사이에 결론상의 차이는 없고, 문언만 CSS2 §6.4.4 참조에서 직접 서술로 바뀌었다. **결정적 함의:** `<style>`의 `rect { fill: red }` 한 줄이 요소의 `fill="blue"`를 이긴다. 따라서 `<style>`을 무시하는 파서는 "정보를 덜 반영"하는 것이 아니라 **틀린 색·틀린 선폭을 표시**한다. 앱의 핵심 기능이 "같은 속성의 벡터만 모아보기"(명세 2항)인 이상, 스타일 오독은 그룹핑 자체를 무너뜨린다.

**질문 3 — `<style>` 요소 요건.**
`type` 기본값 `text/css`(속성이 없어도 CSS로 처리해야 함), `media` 기본값 `all`(없으면 무조건 적용), CDATA는 "highly recommended"이나 강제 아님(따라서 CDATA·일반 텍스트 양쪽 콜백을 모두 처리해야 함), 콘텐츠 모델은 SVG 2에서 character data, **배치 위치 제약 없음**(문서 어디에 있든 문서 전체에 적용).

**질문 4 — 실무 빈도.**
Illustrator가 `<style>` 블록 출력을 정식 옵션("Style Elements")으로 제공하며, 동일 스타일 도형이 대량인 도면일수록 이 옵션이 유리해 선택될 유인이 크다. Inkscape는 인라인 `style` 속성이 기본, Qt/QGIS 계열은 단순 속성 출력이라 현재 구현으로 커버된다. AutoCAD·Visio는 확정하지 못했다.

**질문 5 — 최소 구현 범위.**
클래스 / 타입 / 그룹(콤마) / 복합 셀렉터 + specificity (A,B,C) 계산 + 동률 시 문서 순서. id 셀렉터와 `!important`는 권장. 후손·자식 결합자는 선택. 의사 클래스·의사 요소, `@font-face`, `@charset`은 제외. `@media`는 `all`/`screen` 통과 근사, `@import`는 보류.

### 권고

**"1차 범위 밖"이라는 현재 판단은 유지하되, 주석의 성격을 바꿔야 한다.** 지금 주석은 "확인 필요"라는 미결 표시인데, 조사 결과 이것은 미결 사항이 아니라 **알려진 한계**다. 근거는 셋이다.

1. **오작동이 조용하다.** `<style>`을 무시하면 파싱이 실패하는 것이 아니라, 아무 경고 없이 프레젠테이션 속성 값(또는 기본 검정 선)으로 그려진다. 사용자는 도면이 잘 열렸다고 믿는다. 반면 오류로 드러나면 사용자가 다른 형식으로 다시 내보내면 된다. **따라서 최소한의 조치로 `<style>` 요소의 존재를 감지해 "이 SVG는 CSS 스타일시트를 포함하고 있어 색·선폭이 원본과 다르게 표시될 수 있습니다"라는 경고를 띄우는 것이 우선순위 1이다.** 이것은 셀렉터 엔진 없이 `SVGParser`에 요소명 검사 한 줄로 가능하다.
2. **구현 비용이 셀렉터 엔진만이 아니다.** SVG 1.1 §6.15의 "anywhere within … apply across the entire SVG document" 때문에, 현재의 단일 패스 SAX 구조로는 원리적으로 지원할 수 없다. 도형보다 뒤에 나온 `<style>`도 그 도형에 적용돼야 하기 때문이다. **2-pass 구조로의 전환**(1차 패스에서 `<style>` 텍스트와 요소별 `class`/`id`만 수집, 2차 패스에서 도형 해석)이 선행되어야 한다. 이는 `StyleResolver`가 아니라 `SVGParser`의 구조 변경이며, 1차 범위에서 미루는 판단이 그래서 합리적이다.
3. **입력 출처를 통제할 수 있다면 위험이 크게 줄어든다.** 이 앱이 받는 도면의 출처가 Inkscape·QGIS·Qt 계열로 한정된다면 현재 구현으로 충분하다. Illustrator 산출물을 받는다면 사용자에게 "CSS Properties를 Presentation Attributes로 두고 내보내 달라"고 안내하는 것으로도 실질적으로 해결된다. **즉 문서화와 경고가 코드보다 먼저다.**

**2차에서 구현할 때의 범위 권고:** 위 5.3 표의 "필수" 네 줄(클래스·타입·그룹·복합) + specificity 계산 + `!important`까지. 후손 결합자와 `@media`는 실제 산출물에서 발견되면 그때 추가한다. 파싱 구조는 2-pass. 이 범위면 Illustrator Style Elements 출력을 사실상 전부 커버하면서, CSS 파서를 통째로 만드는 비용은 피할 수 있다.

## 미해결 질문

- SVG 2 §6.6의 "author level of the cascade, following all other author-level style sheets"와 CSS Cascade 4의 별도 "author presentational hint origin" 사이의 문언 불일치가 전칭 셀렉터(`*`, specificity 0,0,0)와 맞붙는 경우 실제 브라우저에서 어떻게 해소되는지 — 미확인. 이 앱 용도에서는 영향 없음.
- Illustrator "Export As > SVG" 및 "Save As > SVG"의 CSS Properties **기본 선택값** — Adobe 공식 문서 두 URL(helpx.adobe.com) 모두 2026-08-29 조회 시 타임아웃으로 본문 취득 실패. 실물 산출물로 재확인 필요.
- Microsoft Visio의 네이티브 SVG 저장이 `<style>` 블록을 쓰는지 프레젠테이션 속성을 쓰는지 — 공식 문서에서 확인 실패.
- AutoCAD 계열은 SVG를 1급 내보내기 형식으로 다루지 않아 변환기마다 결과가 달라짐 — 단일 답 없음. 실제 사용될 변환 경로가 정해지면 그 산출물로 개별 확인 필요.
- SVGO 등 최적화 도구가 프레젠테이션 속성 ↔ `<style>` 클래스 사이를 재작성하는 조건 — 미조사.
