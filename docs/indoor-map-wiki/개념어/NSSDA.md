---
summary: 미국 연방지리정보위원회(FGDC)가 1998년 제정한 공간 데이터 위치 정확도 표준(FGDC-STD-007.3-1998). RMS 오차를 95% 신뢰수준 정확도로 옮기는 환산 계수 1.7308과, 검사점 최소 20개·보고 문구 형식을 규정한다
source: "[[11) 실내 지도의 위치 정확도 — ±5m는 어디서 오는가]], [[src16. 실내 지도 위치 정확도 허용 오차 기준 조사]], FGDC-STD-007.3-1998 Appendix 3-A·§3.2.2·§3.2.3"
related:
  - "[[RMS 오차]]"
  - "[[수평 위치 정확도]]"
  - "[[지오레퍼런싱]]"
created: "2026-08-30 16:10"
updated: "2026-08-30 16:10"
core_keywords:
  - NSSDA
---
# NSSDA

## 요약

NSSDA(National Standard for Spatial Data Accuracy)는 미국 연방지리정보위원회(FGDC)가 1998년 제정한 공간 데이터 위치 정확도 표준이다(문서 번호 FGDC-STD-007.3-1998). 이 표준의 실무적 가치는 **[[RMS 오차]]라는 통계량을 "95% 신뢰수준 정확도"라는 판정으로 옮기는 환산 절차**를 제공한다는 데 있다.

## 핵심 내용

### 환산식

- 수평 오차 정의: 점 *i*의 오차는 `sqrt[(x_data,i − x_check,i)² + (y_data,i − y_check,i)²]`
- 수평 RMSE: `RMSE_r = sqrt[RMSE_x² + RMSE_y²]`
- 95% 신뢰수준 환산: `Accuracy_r = 2.4477 × RMSE_x = 2.4477 × RMSE_r/1.4142` → **`Accuracy_r = 1.7308 × RMSE_r`**
- 계수 2.4477의 출처는 Greenwalt and Schultz(1968)이며, x·y 각 성분의 오차가 정규분포이고 서로 독립이라는 가정 위에서 성립한다. 표준 원문도 "It is assumed that systematic errors have been eliminated as best as possible"이라는 전제를 명시한다.

### 검사점 요건

- "A minimum of **20 check points** shall be tested, distributed to reflect the geographic area of interest and the distribution of error in the dataset."
- 20점을 시험할 때 95% 신뢰수준은 **한 점의 임계값 초과를 허용**한다.
- "If fewer than twenty points can be identified for testing, use an alternative means to evaluate the accuracy of the dataset."

### 보고 문구 두 가지

표준은 정확도를 적는 문장 형식까지 규정하며, **검증 방식에 따라 문구가 갈린다.**

- 독립적인 고정확도 출처로 검증한 경우: `Tested ____ (meters, feet) horizontal accuracy at 95% confidence level`
- 그 절차를 따를 수 없어 대체 수단을 쓴 경우: `Compiled to meet ____ (meters, feet) horizontal accuracy at 95% confidence level`

### 지오레퍼런싱 도구에 적용할 때의 단서

환산 계수만 빌려 쓰는 것이지 정식 절차를 따르는 것이 아니다. 세 가지가 어긋난다.

1. **통계량의 성격이 다르다.** NSSDA의 RMSE는 독립적인 고정확도 출처와 비교한 **검사점**에서 계산한다. 지오레퍼런싱 도구의 잔차는 **변환식을 만드는 데 쓴 바로 그 점들**에서 계산한 내부 적합도라 구조적으로 낙관적이다.
2. **표본 수가 다르다.** NSSDA는 최소 20점, 실무 도면 정합은 4~5쌍이다.
3. **따라서 보고 문구는 `Tested`가 아니라 `Compiled to meet`이다.**

## 관련 링크

- [[RMS 오차]] — 환산의 입력이 되는 통계량
- [[수평 위치 정확도]] — 환산의 출력이 대응하는 요건
- [[11) 실내 지도의 위치 정확도 — ±5m는 어디서 오는가]] — IMDF ±5m를 이 식으로 RMS 2.89m로 옮기는 과정

## 미해결 질문

- ASPRS 2014판이 같은 1.7308 계수를 쓰면서도 정확도 등급을 축척에서 분리한 이유와, 두 표준을 함께 쓸 때의 우선순위 — 미정리.
