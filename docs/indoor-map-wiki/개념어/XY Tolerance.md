---
summary: "ArcGIS 지오데이터베이스가 '두 좌표가 같은 자리인가'를 판정하는 거리. 기본값은 실제 지상 거리 0.001m(1mm)이며, 좌표가 얹히는 격자 간격인 XY Resolution(0.0001m)의 10배로 정의된다. Esri는 이 값을 사용자가 바꾸는 것을 명시적으로 만류한다"
source: "[[12) 도면을 폴리곤으로 닫는 허용 오차 — 절대 치수인가 비례값인가]], [[src17. 링 닫힘 허용 오차 — Door Close Buffer와 XY Tolerance 기준 조사]], Esri ArcGIS Pro 'Feature class basics'·'XY Tolerance (Environment setting)'"
related:
  - "[[허용 오차]]"
  - "[[스냅]]"
  - "[[ArcGIS Indoors]]"
created: "2026-08-30 16:25"
updated: "2026-08-30 16:25"
core_keywords:
  - XY Tolerance
---
# XY Tolerance

## 요약

XY Tolerance는 ArcGIS 지오데이터베이스가 **"두 좌표가 같은 자리인가"를 판정하는 거리**다. 기하 연산 중 클러스터링에서 이 거리 안에 있는 좌표들은 하나로 취급된다. 짝이 되는 개념인 XY Resolution은 좌표가 얹히는 **격자의 간격**이다.

## 핵심 내용

### 두 값과 그 관계

| 값 | 기본값 | 의미 |
|---|---|---|
| XY Resolution | **0.0001 m (0.1 mm)** | 좌표가 얹히는 정수 격자의 간격. 저장 가능한 최소 좌표 차이 |
| XY Tolerance | **0.001 m (1 mm)** | 두 좌표를 같은 자리로 볼 거리. Resolution의 **10배** |

원문:

> "The x,y tolerance is an extremely small distance (the default is **0.001 meters in on-the-ground units**). It is used to resolve inexact intersection locations of coordinates during clustering operations."

> "**The default value for the x,y tolerance is 10 times the default x,y resolution**, and this is recommended for most cases."

### "on the ground"의 뜻

- 데이터셋의 좌표계 단위가 무엇이든 **실제 지상 1mm에 해당하는 값**으로 환산된다.
- 문서의 예시: 좌표계가 state plane feet이면 기본값은 0.003281피트가 된다.
- 위경도 좌표계라면 XY Resolution 기본값은 0.000000001도다.
- 즉 **도면 파일이 크든 작든 물리적으로 같은 거리**를 뜻한다. 이것이 [[허용 오차]]를 도면 크기에 비례시키면 안 되는 이유의 직접적 근거다.

### 10배 관계에 이유가 있다

- 허용 오차가 격자 간격에 근접하면 **"같은 자리"라는 판정이 격자 양자화 오차와 구별되지 않는다.**
- 10배의 여유가 그 구별을 보장한다.
- 자체 [[스냅]] 격자를 쓰는 구현에서도 참고할 만한 비율이다 — 격자 해상도와 판정 허용 오차 사이에 일정한 배율을 두어 두 판정이 서로 간섭하지 않게 하는 발상이다.

### 좌표가 움직이는 거리의 상한

> "The maximum distance a coordinate can move to its new location during such operations is **the square root of 2 times the x,y tolerance**. The clustering algorithm is iterative, so in some cases coordinate locations may shift more than this distance."

클러스터링이 반복적이므로 이 상한도 절대적이지 않다는 단서가 붙어 있다.

### Esri는 변경을 만류한다

> **Caution:** "**Overriding the default XY Tolerance is not recommended.** Instead, ensure that your input data spatial reference uses the default settings for its XY Resolution and XY Tolerance properties prior to analysis."

> "**Your x,y tolerance should never approach your data capture resolution.** ... **it is best to use the default x,y tolerance values in all but extreme cases.**"

허용 오차를 키우면 **feature 경계 표현의 정확도가 훼손된다**("This can compromise the accuracy of feature boundary representations").

## 관련 링크

- [[허용 오차]] — 상위 개념
- [[스냅]] — 이 거리를 적용해 좌표를 실제로 붙이는 동작
- [[12) 도면을 폴리곤으로 닫는 허용 오차 — 절대 치수인가 비례값인가]] — 다른 도구의 임계값들과 함께 정리한 문서

## 미해결 질문

- 없음.
