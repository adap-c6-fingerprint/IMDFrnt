---
summary: "실내 지도의 위치 정확도 허용 오차에 공식 근거가 있는지 확정. OGC IMDF 1.0.0 Reference에 'Horizontal Positional Accuracy — 실제 지상 위치로부터 ±5m 이내' 규칙과 '좌표 소수점 7자리 이상(≈11mm)' 정밀도 권고가 MUST/SHOULD로 명시되어 있고, Venue·Level·Unit·Footprint·Fixture·Kiosk의 Geometry Capturing Rules가 이 규칙을 참조한다. Apple Indoor Maps Program 자체 문서에는 정량 허용 오차가 없다. NSSDA의 Accuracy=1.7308×RMSE 환산식으로 ±5m를 RMS 잔차 상한 2.89m로 옮길 수 있으나, 실내 축척에서는 훨씬 엄격한 임계값이 필요하다는 공학적 판단을 덧붙였다."
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0) Reference·Venue·Level·Unit·Footprint·Fixture·Kiosk 페이지, RFC 7946 §4·§3.1.10·§11.2, FGDC-STD-007.3-1998 (NSSDA), ASPRS Positional Accuracy Standards for Digital Geospatial Data (2014, Edition 1), docs.ogc.org/is/19-011r4 (IndoorGML 1.1), register.apple.com/resources/indoor"
created: "2026-08-29 11:20"
updated: "2026-08-29 11:20"
---
# 실내 지도 위치 정확도 허용 오차 기준 조사

## 수집 기준

- 수집일: 2026-08-29
- 목적: FP-to-IMDF 앱의 `~/Desktop/IM-DFrnt/Sources/IMDFrnt/Georeference/ResidualCalculator.swift`에 남은 미해결 항목을 확정하기 위한 조사. 이 파일은 Anchor 쌍별 잔차(m)와 RMS를 계산하고 `outliers(_:sigma:)`로 **평균+2σ를 넘는 쌍만** 강조하는데, "이 정도면 충분히 정확한가"를 판정할 **절대 임계값의 근거가 없다.** `src13` 4절이 미해결로 남긴 "Apple Indoor Maps Program이 요구하는 정량 정확도 기준이 있는가"의 후속 조사이기도 하다.
- 방법: (1) Apple Indoor Maps Program 공개 페이지, (2) OGC IMDF 1.0.0 전체 Feature 페이지, (3) IMDF가 준거하는 RFC 7946, (4) 대체 표준 후보(NSSDA·ASPRS·IndoorGML)를 직접 조회해 원문 인용. 인용은 영어 원문 그대로 옮기고 한국어 해설을 붙인다.

## 핵심 출처

- OGC IMDF 1.0.0 Reference: https://docs.ogc.org/cs/20-094/Reference/index.html — **조회 성공. 이번 조사의 정본.**
- OGC IMDF 1.0.0 Venue / Level / Unit / Footprint / Fixture / Kiosk: https://docs.ogc.org/cs/20-094/{Venue,Level,Unit,Footprint,Fixture,Kiosk}/index.html — 전 페이지 조회 성공
- IETF RFC 7946 (The GeoJSON Format): https://datatracker.ietf.org/doc/html/rfc7946
- FGDC-STD-007.3-1998, *Geospatial Positioning Accuracy Standards, Part 3: National Standard for Spatial Data Accuracy* (NSSDA): https://transportation.ky.gov/Highway-Design/Documents/FGDC%20STD%20007.3%201998.pdf (원 배포처 fgdc.gov는 2026-08-29 조회 시 HTTP 403 — 동일 PDF의 공공기관 미러로 대체, 문서 번호·본문 동일)
- ASPRS, *Positional Accuracy Standards for Digital Geospatial Data* (2014, Edition 1, Version 1.0): https://florida.asprs.org/images/documents/ASPRS_Positional_Accuracy_Standards_Edition1_Version100_November2014.pdf
- OGC IndoorGML 1.1: https://docs.ogc.org/is/19-011r4/19-011r4.html
- Apple, "Indoor Maps in Apple Maps": https://register.apple.com/resources/indoor/program/indoor_maps
- Apple, "Additional Resources": https://register.apple.com/resources/indoor/program/additional_resources
- **조회 실패 기록:** Apple이 자체 호스팅하는 IMDF 스펙 미러(https://register.apple.com/resources/imdf/)는 JavaScript로 본문을 채우는 페이지라 `Reference` 하위 경로가 HTTP 404를 반환하고 본문 취득에 실패했다. 아래 인용은 모두 **OGC가 호스팅하는 정식 표준판(20-094)** 기준이다. IMDF 1.0.0은 Apple과 OGC의 공동 저작권 표기(각 페이지 하단 "Copyright © 2018, 2019, 2020 Apple Inc. All rights reserved. Copyright © 2021 Apple Inc. and OGC.")를 달고 있어 두 판본은 같은 문서로 취급한다.

---

## 1. Apple Indoor Maps Program 자체 문서에는 정량 허용 오차가 **없다**

Apple의 프로그램 안내 페이지에서 정확도와 관련해 확인한 문장은 두 개뿐이다.

> "Apple indoor positioning can typically provide GPS level accuracy when inside a building."

> "The Indoor Survey app requires a floor plan of the building in IMDF to be correctly geo-referenced to latitude and longitude."

앞 문장은 **Apple의 실내 측위(positioning)가 사용자에게 제공하는 정확도**를 말하는 것이지, 제출하는 도면 데이터가 지켜야 할 요건이 아니다. 뒤 문장은 "올바르게 지오레퍼런싱되어야 한다"고만 하고 *얼마나* 올바라야 하는지는 말하지 않는다.

"Additional Resources" 페이지에서 검증에 관해 확인한 문장:

> "when you upload an IMDF into your account on ABR, a detailed validation of the IMDF is performed. The resulting report can be used to correct any errors or warnings."

> "it may mean your indoor map is not correctly geo-referenced to latitude/longitude or it may mean you have a bug in your code."

업로드 시 검증이 돌아간다는 사실은 확인되지만, 그 검증이 어떤 수치를 임계값으로 쓰는지는 공개 문서에 없다.

**판정:** Apple Indoor Maps Program **가입·제출 안내 문서 계층에는 정량적 위치 정확도 요건이 존재하지 않는다.** 프로그램 페이지·추가 리소스 페이지·Indoor Survey 안내를 훑어 확인한 결과이며, "없음"이 이 절의 결론이다. 다만 이것은 **Apple에 요건이 없다는 뜻이 아니다** — 요건은 프로그램 문서가 아니라 **데이터 포맷 스펙(IMDF) 쪽에 들어 있다.** 2절이 그것이다.

---

## 2. OGC IMDF 1.0.0에는 **±5m 수평 위치 정확도 규칙이 MUST로 명시되어 있다**

IMDF 1.0.0 Reference 페이지의 `Horizontal Positional Accuracy` 절 원문 전체:

> **Horizontal Positional Accuracy**
> "Features that explicitly reference this rule-set **MUST** be within +/- 5 meters of their actual ground location when tested using an independent source of higher accuracy."
> - "The independent source of higher accuracy shall be of the highest accuracy feasible and practicable to evaluate the accuracy of the feature"

한국어 해설: IMDF는 정확도 규칙을 **개별 Feature 페이지마다 반복해 쓰지 않고 Reference 페이지에 "규칙 세트(rule-set)"로 한 번만 정의한 뒤, 각 Feature가 이를 참조하는 구조**를 쓴다. 그래서 Reference 페이지만 보면 "이 규칙 세트를 명시적으로 참조하는 Feature"라는 조건절이 붙어 있고, 실제로 어떤 Feature가 참조하는지는 각 Feature 페이지를 봐야 한다.

전 Feature 페이지를 훑어 `Geometry Capturing Rules` 안에서 이 규칙을 참조하는 문장을 찾은 결과는 다음과 같다. **6개 Feature Type이 참조한다.**

| Feature Type | 원문 |
|---|---|
| Venue | "Horizontal positional accuracy **MUST** be within tolerance" |
| Level | "Level Extent — Horizontal positional accuracy **MUST** be within tolerance" |
| Unit | "Unit Extent — Horizontal positional accuracy **MUST** be within tolerance" |
| Footprint | "Horizontal positional accuracy **MUST** be within tolerance" |
| Fixture | "Horizontal positional accuracy **MUST** be within tolerance" |
| Kiosk | "Horizontal positional accuracy **MUST** be within tolerance" |

Opening·Detail·Section·Amenity·Anchor·Address·Occupant·Geofence·Relationship 페이지에는 같은 문장이 **없다.** 즉 정확도 요건은 **공간 범위를 정의하는 폴리곤 계열 Feature**에 집중돼 있고, 그 안에 놓이는 점·선 계열에는 명시적으로 걸려 있지 않다.

Footprint 페이지에는 이 규칙을 왜 두는지 보여 주는 서술도 있다. 위성/항공 영상에서 건물 윤곽을 유도할 때의 제약이다.

> "The physical building, when observed in aerial/satellite imagery, is obscured to an extent that derivation of the Footprint would be impeded. Consequently, any derived geometries would possess a shape and spatial extent with questionable horizontal positional accuracy"

> "Radial displacement would cause derived geometries to possess a shape and spatial extent with questionable horizontal positional accuracy"

**판정:** "IMDF에 위치 정확도 요건이 있는가"의 답은 **있다 — ±5m, MUST**다. 이것은 추정이 아니라 스펙 원문이며, FP-to-IMDF 앱이 생산하는 Unit 폴리곤은 이 규칙을 참조하는 6개 Type 중 하나다. 따라서 **앱은 이 요건의 적용 대상이다.**

다만 다음 세 가지를 혼동하지 않아야 한다.

1. **±5m는 "절대 지상 위치와의 편차"이지 "컨트롤 포인트 잔차"가 아니다.** 스펙이 요구하는 검증 방법은 "an independent source of higher accuracy"로 테스트하는 것이다. 앱이 계산하는 잔차 RMS는 사용자가 찍은 Anchor 쌍에 대한 **내부 적합도(fit)** 지표이며, 사용자가 위경도 자체를 잘못 찍었다면 잔차가 0이어도 지상 위치는 수십 m 어긋난다.
2. 따라서 잔차 RMS는 ±5m 준수의 **필요조건 대리 지표일 뿐 충분조건이 아니다.** 앱 UI가 "IMDF 기준 통과"라고 단정해서는 안 되고, "이 기준을 넘으면 확실히 위반"이라는 방향으로만 써야 한다.
3. ±5m는 **Feature 단위**의 요건이지 데이터셋 평균이 아니다. 한 쌍만 크게 어긋나도 그 근처 Feature는 위반이 된다 — 이것이 잔차의 **최대값**도 함께 봐야 하는 이유다.

---

## 3. 좌표 정밀도(precision)와 좌표계(CRS) 요건

### 3-1. IMDF의 정밀도 권고 — 소수점 7자리, ≈11mm

같은 Reference 페이지의 `Precision` 절 원문:

> **Precision**
> "Precision **SHOULD** be at least seven (7) decimal places."
> - "Seven (7) decimal places is equivalent to a planar distance of ~11mm which is tolerable for mapping and surveying purposes"

한국어 해설: 위경도 소수점 7자리는 위도 방향으로 약 11mm에 해당한다(위도 1도 ≈ 110,540m이므로 1e-7도 ≈ 11.05mm). 경도 방향은 위도에 따라 짧아진다 — 위도 37도에서는 1e-7도 ≈ 8.9mm다. `SHOULD`이므로 강제는 아니지만, **내보내기 시 좌표를 7자리 미만으로 반올림하면 스펙 권고 위반**이다.

주의할 점은 **정밀도(precision)와 정확도(accuracy)는 다른 축**이라는 것이다. IMDF는 정확도에 ±5m(MUST), 정밀도에 7자리(SHOULD)를 요구한다. 즉 "11mm 단위로 기록하되 위치 자체는 5m까지 틀려도 된다"는, 언뜻 모순돼 보이지만 표준 측량 문서에서는 흔한 조합이다. RFC 7946도 같은 취지를 못 박아 둔다.

> RFC 7946 §3.1.10 Uncertainty and Precision:
> "As in [RFC5870], the number of digits of the values in coordinate positions **MUST NOT** be interpreted as an indication to the level of uncertainty."

즉 자릿수를 늘려도 정확해지는 것이 아니다. **판정:** 앱은 좌표를 최소 7자리로 기록해야 하지만(SHOULD), 그 자릿수를 근거로 정확도를 주장해서는 안 된다.

### 3-2. CRS — IMDF 본문에는 CRS 조항이 없고, RFC 7946을 통해 WGS 84로 확정된다

IMDF 1.0.0 전 페이지를 훑은 결과 `WGS`, `EPSG`, `4326`, `coordinate reference system`이라는 문자열은 **한 번도 등장하지 않는다.** IMDF가 좌표계를 정하는 방식은 상속이다.

> IMDF 1.0.0 Reference: "A Feature object represents a physical or conceptual element of an indoor map as an **RFC 7946 compliant** GeoJSON object."

> IMDF 1.0.0 (개요): "IMDF conforms to RFC 7946, ensuring compatibility and transferability of the data."

그리고 RFC 7946 §4 원문:

> "The coordinate reference system for all GeoJSON coordinates is a geographic coordinate reference system, using the World Geodetic System 1984 (WGS 84) [WGS84] datum, with longitude and latitude units of decimal degrees. This is equivalent to the coordinate reference system identified by the Open Geospatial Consortium (OGC) URN `urn:ogc:def:crs:OGC::CRS84`. An OPTIONAL third-position element SHALL be the height in meters above or below the WGS 84 reference ellipsoid."
> "Note: the use of alternative coordinate reference systems was specified in [GJ2008], but it has been removed from [RFC 7946]."

**판정:** IMDF의 좌표계는 **WGS 84 / OGC:CRS84, 십진도, 경도-위도 순서**로 확정된다. 흔히 쓰는 "EPSG:4326"이라는 표기는 축 순서가 위도-경도로 정의되어 있어 GeoJSON의 경도-위도 순서와 축 순서가 반대다. 정확한 식별자는 `urn:ogc:def:crs:OGC::CRS84`다. 파일 안에 `crs` 멤버를 써 넣는 것은 RFC 7946에서 제거된 기능이므로 **넣지 않는 것이 맞다.**

RFC 7946은 자릿수의 실용적 의미도 적어 두었다 — 정밀도 결정의 근거로 인용할 만하다.

> RFC 7946 §11.2 Coordinate Precision:
> "For geographic coordinates with units of degrees, 6 decimal places (a default common in, e.g., sprintf) amounts to about 10 centimeters, a precision well within that of current GPS systems. Implementations should consider the cost of using a greater precision than necessary."

즉 6자리는 약 10cm, 7자리는 약 11mm다. IMDF는 RFC의 "6자리로 충분"보다 한 자리 더 요구한다.

---

## 4. 대체 기준 후보 검토 — NSSDA·ASPRS·IndoorGML

2절에서 공식 근거를 확보했으므로 대체 기준은 "±5m를 대신할 기준"이 아니라 **"잔차 RMS라는 통계량을 정확도 판정으로 옮기는 환산 절차"**로서 필요하다. 그 관점에서 후보 셋을 검토한다.

### 4-1. NSSDA (FGDC-STD-007.3-1998) — 적용 가능. 환산식의 근거가 된다

NSSDA의 수평 오차 정의와 환산식 원문(Appendix 3-A, normative):

> "Horizontal error at point *i* is defined as `sqrt[(x_data,i − x_check,i)² + (y_data,i − y_check,i)²]`. Horizontal RMSE is: `RMSE_r = sqrt[Σ((x_data,i − x_check,i)² + (y_data,i − y_check,i)²)/n] = sqrt[RMSE_x² + RMSE_y²]`"

> "It is assumed that systematic errors have been eliminated as best as possible. If error is normally distributed and independent in each the x- and y-component and error, the factor 2.4477 is used to compute horizontal accuracy at the 95% confidence level (Greenwalt and Schultz, 1968)."

> "`Accuracy_r = 2.4477 * RMSE_x = 2.4477 * RMSE_y = 2.4477 * RMSE_r/1.4142`"
> "`Accuracy_r = 1.7308 * RMSE_r`"

검사점 개수와 보고 형식 원문(§3.2.2, §3.2.3):

> "A minimum of 20 check points shall be tested, distributed to reflect the geographic area of interest and the distribution of error in the dataset. When 20 points are tested, the 95% confidence level allows one point to fail the threshold given in product specifications."

> "If fewer than twenty points can be identified for testing, use an alternative means to evaluate the accuracy of the dataset."

> "Report accuracy at the 95% confidence level for data tested for both horizontal and vertical accuracy as: **Tested ____ (meters, feet) horizontal accuracy at 95% confidence level**"

> "Use the 'compiled to meet' statement below when the above guidelines for testing by an independent source of higher accuracy cannot be followed and an alternative means is used to evaluate accuracy: **Compiled to meet ____ (meters, feet) horizontal accuracy at 95% confidence level**"

한국어 해설: NSSDA는 **잔차 RMS(RMSE_r)를 95% 신뢰수준 정확도로 옮기는 계수 1.7308**을 정의한다. IMDF의 ±5m를 이 식으로 되돌리면 대응하는 RMS 상한이 나온다.

```
RMSE_r ≤ 5 m / 1.7308 = 2.889 m
```

즉 "RMS 잔차가 2.89m를 넘으면 IMDF ±5m 요건을 95% 신뢰수준에서 만족한다고 주장할 수 없다."

**판정:** NSSDA는 **적용 가능하며, 이 조사에서 확보한 유일한 "RMS → 정확도" 공식 환산 경로**다. 다만 세 가지 단서를 붙여야 한다.
- NSSDA의 RMSE는 **독립적인 고정확도 출처와 비교한 검사점**에서 계산한 값이다. 앱의 잔차는 **변환식을 만드는 데 쓴 바로 그 점들**에서 계산한 값(내적 적합도)이라 통계적으로 낙관적이다. 같은 이름의 통계량이지만 성격이 다르다.
- NSSDA는 최소 20점을 요구한다. 앱의 `GeoAffineTransform.recommendedPairs`는 4다. **NSSDA의 정식 절차를 따르는 것은 아니고, 그 환산 계수만 빌려 쓰는 것**이다.
- 따라서 앱이 산출하는 문구는 "Tested"가 아니라 NSSDA가 예비해 둔 **"Compiled to meet"** 계열에 해당한다.

### 4-2. ASPRS 2014 Positional Accuracy Standards — 적용 가능하나 임계값을 주지는 않는다

ASPRS 2014판의 성격을 보여 주는 원문(§7.3):

> "While prior ASPRS standards used numerical ranks for discrete accuracy classes tied directly to map scale (i.e., Class 1, Class 2, etc.), many modern applications ... A Scope of Work, for example, can specify that digital orthoimagery, digital planimetric data, or scaled maps must be produced to meet ASPRS Accuracy Standards for **7.5 cm RMSE_x and RMSE_y Horizontal Accuracy Class**."

NSSDA와의 환산 예제(Annex B):

> "According to NSSDA, the horizontal positional accuracy is estimated `Accuracy_r = 2.4477 × RMSE_x = 2.4477 × RMSE_y` ... `= 1.7308(RMSE_r) = 1.7308(21.21 cm) = 36.71 cm`"

레거시 표준에 대한 평가:

> "The National Map Accuracy Standard (NMAS) of 1947 established horizontal accuracy thresholds ... as a function of map scale ... they are inappropriate for digital geospatial data where scale and contour interval are changed with a push of a button while not changing the underlying horizontal and/or vertical accuracy."

한국어 해설: ASPRS 2014판의 핵심 설계는 **"정확도 등급을 축척에서 떼어냈다"**는 것이다. 등급은 이름표가 아니라 `RMSE_x` 값 자체로 지정한다("7.5cm 등급"처럼). 그래서 **표준이 "실내 도면은 몇 cm여야 한다"고 말해 주지 않는다** — 발주자가 작업 명세(Scope of Work)에서 고르는 구조다.

**판정:** ASPRS는 **"허용 오차를 축척 비례가 아니라 절대 수치로 지정하라"는 원칙의 근거로는 인용 가치가 있으나, 실내 도면용 임계값을 제공하지는 않는다.** NSSDA와 동일한 1.7308 환산식을 쓰고 있어 4-1의 환산을 교차 검증해 준다는 부수적 가치가 있다. 축척 비례 임계값이 디지털 데이터에 부적절하다는 지적은 `src17`(링 닫힘 허용 오차)의 판정과도 방향이 같다.

### 4-3. OGC IndoorGML 1.1 — 적용 불가. 정확도 조항이 존재하지 않는다

IndoorGML 1.1 표준 문서 전문(약 17만 자)에서 `accuracy`와 `tolerance`를 검색한 결과 **일치 0건**이다. 문서가 스스로 밝히는 범위 원문:

> "The geometric representation of 2D or 3D features in indoor space is **not a major focus of IndoorGML**, since they are clearly defined by ISO 19107, CityGML, and IFC."

**판정:** IndoorGML은 **실내 공간의 위상(topology)과 내비게이션 그래프를 정의하는 표준**이며, 기하 정확도는 명시적으로 자기 관심사가 아니라고 선언한다. 대체 기준 후보에서 **탈락**이다. (참고로 IndoorGML의 `anchor node`는 실내 CRS와 실외 CRS를 잇는 노드로, IMDF의 Anchor와도 앱의 컨트롤 포인트와도 또 다른 세 번째 의미다 — `src13` 2절이 정리한 용어 충돌에 한 겹이 더 있는 셈이다.)

### 4-4. Esri ArcGIS Indoors의 정합 권고

`src13` 3절에서 이미 확보한 Esri 지오레퍼런싱 문서(변환 종류별 최소 링크 수, 잔차·RMS 정의, 링크 배치 권고)를 여기서 반복하지 않는다. 이번 조사에서 추가로 확인한 것은 **Esri Indoors 계열 문서에도 "정합 잔차가 몇 m 이하여야 한다"는 정량 임계값은 없다**는 점이다. Esri가 제시하는 것은 절차적 권고("코너마다 하나 + 내부에 몇 개")이지 합격선이 아니다. Esri Indoors의 도면 취급 파라미터 쪽 기본값은 `src17`에서 별도로 다룬다.

---

## 5. 현재 앱의 이상치 판정 방식 검토 — 평균+2σ에는 구조적 사각지대가 있다

`ResidualCalculator.outliers(_:sigma:)`의 현재 구현을 그대로 옮기면 다음과 같다.

```swift
static func outliers(_ residuals: [Double], sigma: Double = 2.0) -> Set<Int> {
    guard residuals.count > 3 else { return [] }
    let mean = residuals.reduce(0, +) / Double(residuals.count)
    let variance = residuals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(residuals.count)
    let sd = variance.squareRoot()
    ...
    for (i, r) in residuals.enumerated() where (r - mean) / sd > sigma { out.insert(i) }
}
```

여기에 세 가지 구조적 한계가 있다. **이 절은 공식 문서 인용이 아니라 표준 통계에 근거한 자체 분석이다.**

**(1) 표본 수가 적으면 2σ를 넘는 것이 수학적으로 불가능하다.**
표본표준편차를 `n`으로 나눠 구하는(모집단 공식) 경우, 어떤 값의 표준화 점수 `(r − mean)/sd`가 가질 수 있는 최대값은 `(n−1)/√n`으로 제한된다. 실제 값을 넣어 보면:

| n (Anchor 쌍 수) | 표준화 점수 상한 `(n−1)/√n` | 2σ 도달 가능? |
|---|---|---|
| 4 | 1.500 | **불가능** |
| 5 | 1.789 | **불가능** |
| 6 | 2.041 | 가능(간신히) |
| 8 | 2.475 | 가능 |
| 12 | 3.175 | 가능 |

`guard residuals.count > 3`이 통과시키는 최소 개수는 4인데, **n=4와 n=5에서는 한 점이 아무리 심하게 어긋나도 이 함수가 절대 아무것도 반환하지 않는다.** 그런데 `GeoAffineTransform.recommendedPairs`는 4다. 즉 **앱이 권장하는 쌍 개수에서 이상치 강조 기능이 동작하지 않는다.**

**(2) 계통 오차에는 반응하지 않는다.** 사용자가 좌표를 옮겨 적어 모든 쌍이 고르게 3m씩 어긋난 경우, 잔차의 분산이 작아 이상치는 0건이고 UI는 아무 경고도 띄우지 않는다. 그러나 이것이야말로 IMDF ±5m 요건을 위협하는 상황이다.

**(3) 판정의 의미가 상대적이다.** "이 쌍이 다른 쌍들에 비해 튄다"는 정보는 어느 쌍을 고칠지 알려 주지만, "지금 정합이 쓸 만한가"는 알려 주지 않는다. 두 질문은 다르고, 사용자에게는 둘 다 필요하다.

**판정:** 평균+2σ는 **폐기 대상이 아니라 보완 대상**이다. "어느 쌍을 다시 찍을 것인가"라는 질문에는 여전히 이 방식이 맞다. 다만 (1)의 수학적 사각지대는 실질적인 결함이므로 개수 조건을 고쳐야 하고, (2)(3)을 메우려면 절대 임계값을 병행해야 한다.

---

## FP-to-IMDF 앱에 대한 권고

### 권고 1. 절대 임계값을 3단계로 두고, 상대 판정(2σ)과 병행한다 — **병행 여부는 공학적 판단, 상한선 하나는 공식 근거**

`ResidualCalculator`에 아래 등급을 추가할 것을 권고한다. 각 수치의 성격을 열에 명시했다.

| 등급 | RMS 잔차 | 근거의 성격 | 근거 |
|---|---|---|---|
| 양호 | ≤ 0.10 m | **공학적 판단** | 일반적인 벽 두께 하한(0.1m) 이내. 이 범위에서는 정합 오차가 벽 두께에 묻힌다. |
| 주의 | 0.10 ~ 0.30 m | **공학적 판단** | 벽 두께 범위(0.1~0.3m)와 겹친다. 방 경계가 인접한 벽 쪽으로 밀려 보일 수 있다. |
| 경고 | > 0.30 m | **공학적 판단** | 벽 두께 상한을 넘는다. Unit 폴리곤이 물리적 벽 밖으로 나가기 시작한다. |
| 위반 위험 | > 2.89 m | **공식 근거에서 유도** | IMDF "±5m MUST"를 NSSDA `Accuracy_r = 1.7308 × RMSE_r`로 환산한 상한(5 ÷ 1.7308 = 2.889m). 이 값을 넘으면 95% 신뢰수준에서 IMDF 요건 충족을 주장할 수 없다. |

수치 선정의 논리를 밝혀 둔다. 실내 축척에서 판정의 기준이 되는 물리 치수는 **방 폭이 아니라 벽 두께**다. 방 폭(3~10m)을 기준으로 하면 IMDF의 ±5m조차 "방 하나 통째로 옆방"인 수준이라 실용적인 경고선이 되지 못한다. 반면 벽 두께(0.1~0.3m)는 "Unit 폴리곤이 실제 벽 안에 머무는가"라는 질문에 직접 대응하고, 실내 지도에서 오정합이 눈에 띄기 시작하는 지점도 여기다. **0.10m와 0.30m는 이 논리에서 나온 값이며, 어떤 표준 문서에도 이 숫자는 없다.**

경고 UI 문구는 등급의 성격을 반영해야 한다.
- 0.30m 초과: "정합 오차가 벽 두께를 넘습니다. Anchor를 다시 확인하세요." — **앱의 권고**임을 알 수 있게
- 2.89m 초과: "IMDF 규격(수평 위치 정확도 ±5m)을 만족하지 못할 수 있습니다." — **규격 참조**임을 알 수 있게. 단정("위반입니다")은 하지 말 것. 2절 판정에서 정리했듯 잔차 RMS는 지상 정확도의 대리 지표일 뿐이다.

### 권고 2. RMS만이 아니라 최대 잔차도 함께 판정한다 — **공식 근거에서 유도**

IMDF의 ±5m는 **Feature 단위** 요건이지 데이터셋 평균이 아니다("Features ... **MUST** be within +/- 5 meters"). 쌍이 10개인데 9개가 0.05m이고 하나가 4m라면 RMS는 약 1.27m로 "경고"에 그치지만, 그 한 쌍 근처의 Feature는 요건을 위반한다. 따라서:

- **최대 개별 잔차 > 0.5m**: 해당 쌍을 붉게 표시(공학적 판단 — 벽 두께 상한 0.3m에 여유를 둔 값)
- **최대 개별 잔차 > 5.0m**: 해당 쌍은 IMDF 요건을 직접 위반하는 위치이므로 별도 표시(공식 근거 — 스펙 원문의 ±5m를 그대로 적용)

`ResidualCalculator`는 이미 쌍별 잔차 배열을 반환하므로 최대값 판정은 추가 계산 없이 얻을 수 있다.

### 권고 3. `outliers(_:sigma:)`의 개수 조건을 고친다 — **수학적 근거**

5절 (1)에서 보인 대로 `n=4`, `n=5`에서는 2σ 판정이 원리적으로 아무것도 반환할 수 없다. 현재 `guard residuals.count > 3`은 이 두 경우를 통과시켜, 함수가 조용히 빈 집합을 돌려주고 UI는 "이상치 없음"으로 읽는다. 두 가지 중 하나를 택할 것을 권고한다.

- **간단한 안** — 가드를 `residuals.count >= 6`으로 올린다. 그리고 n이 6 미만일 때는 UI가 "쌍이 적어 이상치 판정을 할 수 없습니다"라고 **명시**한다. 지금처럼 "이상치 없음"과 구별되지 않는 것이 문제의 본질이다.
- **더 나은 안** — `sigma` 기본값을 표본 수에 맞춰 조정하거나(예: `min(2.0, 0.8 * (n-1)/√n)`), 표본 수에 강건한 중앙값 기반 판정(잔차의 중앙값 + k × MAD)으로 바꾼다. 잔차 분포는 소수의 오지정 때문에 꼬리가 두꺼워지기 쉬운데, 그런 분포에서는 평균·표준편차 자체가 오지정에 끌려가 판정력을 잃는다.

어느 쪽이든 **권고 1의 절대 임계값이 들어가면 이 사각지대의 실질적 위험은 크게 줄어든다** — n이 4든 5든 절대 임계값은 정상 동작하기 때문이다. 상대 판정과 절대 판정을 병행해야 하는 실무적 이유가 여기 하나 더 있다.

### 권고 4. 내보내기 좌표는 소수점 7자리 이상으로 기록한다 — **공식 근거(SHOULD)**

3-1절의 IMDF `Precision` 조항에 따라, GeoJSON 직렬화 시 위경도를 7자리 미만으로 반올림하지 않아야 한다. Swift의 기본 `Double` 인코딩은 자릿수를 잃지 않으므로 별도 포맷팅을 넣지 않는 편이 안전하다. **명시적으로 `%.6f` 류의 포맷을 쓰고 있다면 그것이 스펙 권고 위반**이므로 확인이 필요하다.

### 권고 5. 정확도 표기 문구는 "Compiled to meet" 계열을 쓴다 — **공식 근거(NSSDA 보고 형식)**

앱이 프로젝트 문서나 내보내기 리포트에 정확도를 적는다면, NSSDA §3.2.3이 규정한 두 문구 중 **"Compiled to meet ____ meters horizontal accuracy at 95% confidence level"** 쪽이 맞다. 앱의 잔차는 독립적인 고정확도 출처로 검증한 값이 아니므로 "Tested"를 쓸 수 없다(4-1 판정 참조). 값은 `1.7308 × RMS`로 계산한다.

---

## 미해결 질문

- Apple Business Register(ABR) 업로드 시 실행되는 IMDF 검증기가 **위치 정확도를 실제로 검사하는지**, 검사한다면 어떤 임계값을 쓰는지 — 공개 문서에 없다. IMDF Sandbox(https://register.apple.com/indoor/imdf-sandbox)는 로그인이 필요해 미확인.
- Apple이 자체 호스팅하는 IMDF 스펙 미러의 `Reference` 페이지 본문 — 2026-08-29 조회 시 취득 실패(SPA·404). OGC 판과 내용이 동일한지 대조하지 못했다. 두 판이 다를 가능성은 낮지만 확인 필요.
- 권고 1의 0.10m / 0.30m 경계는 **일반적인 벽 두께에서 유도한 공학적 판단**이며, 실제 도면 몇 건으로 검증한 값이 아니다. 앱을 실제 도면에 적용해 보고 조정할 것.
- ±5m 규칙을 참조하지 않는 Feature Type(Opening·Detail·Amenity 등)에도 사실상 같은 정확도가 요구되는지 — 스펙은 침묵한다. 상위 Unit이 ±5m를 지키면 그 안에 놓이는 Opening은 자동으로 만족한다는 해석이 자연스럽지만, 스펙 원문에는 그런 서술이 없다.
