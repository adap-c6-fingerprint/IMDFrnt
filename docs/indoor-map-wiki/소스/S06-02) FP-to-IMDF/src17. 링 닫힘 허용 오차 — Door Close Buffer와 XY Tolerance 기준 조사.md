---
summary: "도면 선분을 폴리곤으로 닫을 때 쓰는 허용 오차의 공식 기본값을 확정. Esri ArcGIS Indoors의 Door Close Buffer(폐기 예정 도구, 단위 인치, 기본값 0)와 그 후속인 Import CAD To Indoor Dataset의 Door To Wall Distance(기본값 0.3 international inch = 7.62mm), ArcGIS의 XY Tolerance 기본값 0.001m(1mm)·XY Resolution 기본값 0.0001m(0.1mm)를 원문으로 확인했다. 모든 공식 기본값이 절대 물리 치수(인치·mm·m)이며 도면 크기 비례값은 어디에도 없다 — FP-to-IMDF 앱의 overlapTolerance가 쓰는 비례 방식은 근거가 없다는 판정."
source: "pro.arcgis.com (Import CAD To Indoor Dataset, Import Floorplans To Indoors Geodatabase, XY Tolerance·XY Resolution 환경 설정, Feature class basics), docs.safe.com (FME AreaBuilder·Snapper), docs.ogc.org/cs/20-094 (IMDF 1.0.0 Kiosk)"
created: "2026-08-29 11:45"
updated: "2026-08-29 11:45"
---
# 링 닫힘 허용 오차 — Door Close Buffer와 XY Tolerance 기준 조사

## 수집 기준

- 수집일: 2026-08-29
- 목적: FP-to-IMDF 앱의 `~/Desktop/IM-DFrnt/Sources/IMDFrnt/Geometry/RingClosureValidator.swift`가 쓰는 허용 오차의 근거를 확정하기 위한 조사. 이 파일은 끝점 짝짓기로 링 닫힘을 판정하면서 `tolerance` 안이면 붙은 것으로 간주하는데, **호출부가 넘기는 값이 임시값**이다. 실제 호출부는 `~/Desktop/IM-DFrnt/Sources/IMDFrnt/App/AppEnvironment.swift`의 `ringClosure(of:)`이고, 거기서 넘기는 것은 같은 파일의 `overlapTolerance` — `max(0.25, min(캔버스 너비, 캔버스 높이) / 2000)`이라는 **도면 크기 비례값**이다. 소스 주석이 근거로 지목한 Esri의 `Door Close Buffer`가 실제로 무엇이고 기본값이 얼마인지를 원문으로 확인한다.
- 방법: Esri ArcGIS Pro 공식 도구 레퍼런스, ArcGIS 환경 설정 문서, FME 트랜스포머 문서를 직접 조회해 원문 인용. `src13`이 겪은 Esri 문서 리다이렉트 문제를 감안해 pro.arcgis.com과 doc.esri.com 양쪽, 그리고 도구별 페이지를 각각 시도했다.

## 핵심 출처

- Esri, "Import CAD To Indoor Dataset (Indoors Tools)": https://pro.arcgis.com/en/pro-app/latest/tool-reference/indoors/import-cad-to-indoor-dataset.htm — **조회 성공. 현행 도구, 이번 조사의 정본.**
- Esri, "Import Floorplans To Indoors Geodatabase (Indoors Tools)": https://pro.arcgis.com/en/pro-app/latest/tool-reference/indoors/import-floorplans-to-indoors-geodatabase.htm — 조회 성공. `Door Close Buffer`가 실린 페이지. **폐기 예정(deprecated) 도구.**
- 위 문서의 doc.esri.com 판(https://doc.esri.com/en/arcgis-pro/latest/tool-reference/indoors/import-floorplans-to-indoors-geodatabase.html)도 조회했고 **바이트 단위로 동일한 본문**임을 확인했다. `src13`이 기록한 리다이렉트 문제는 지오레퍼런싱 문서(help/data 계층)에 한정된 것으로 보이며, tool-reference 계층은 양쪽 도메인 모두 정상 응답한다.
- Esri, "XY Tolerance (Environment setting)": https://pro.arcgis.com/en/pro-app/latest/tool-reference/environment-settings/xy-tolerance.htm
- Esri, "XY Resolution (Environment setting)": https://pro.arcgis.com/en/pro-app/latest/tool-reference/environment-settings/xy-resolution.htm
- Esri, "Feature class basics": https://pro.arcgis.com/en/pro-app/latest/help/data/geodatabases/overview/feature-class-basics.htm — XY Tolerance·Resolution 기본값의 서술이 가장 상세한 페이지
- Safe Software, "AreaBuilder": https://docs.safe.com/fme/html/FME-Form-Documentation/FME-Transformers/Transformers/areabuilder.htm
- Safe Software, "Snapper": https://docs.safe.com/fme/html/FME-Form-Documentation/FME-Transformers/Transformers/snapper.htm
- **조회 실패 기록:** ArcGIS Indoors의 CAD 도면 준비 가이드(https://pro.arcgis.com/en/pro-app/latest/help/data/indoors/prepare-cad-floor-plan-data.htm)는 2026-08-29 조회 시 HTTP 404를 반환했다. 도면 품질 요건이 이 계층에 있었다면 확인하지 못한 것이며, 아래 결론은 도구 레퍼런스 계층에서 확보한 것으로만 구성했다.

---

## 1. `Door Close Buffer`는 실재한다 — 단, 폐기 예정 도구의 파라미터이고 기본값은 0이다

`Door Close Buffer`가 실린 도구는 **Import Floorplans To Indoors Geodatabase**다. 페이지 상단의 경고 원문:

> **Legacy:** "This is a **deprecated** tool. This functionality has been replaced by the **Import CAD To Indoor Dataset** tool."

Usage 절의 설명 원문:

> "The **Door Close Buffer** parameter is used to account for poor CAD topology—for example, line gaps between doors and walls—when the `CLOSE_DOORS` column is set to Y in the configuration spreadsheet."

> **Caution:** "Identify polylines that are to be merged in the `OPENINGS` column of the *Layer to Feature Class sheet* before running the tool with `CLOSE_DOORS` set to Y."

파라미터 표의 정의 원문:

> **Door Close Buffer** (Optional)
> "The distance, **in inches**, that will be searched from a door to find and snap to the nearest wall. This parameter is used when the `CLOSE_DOORS` column is set to Y in the input Excel template file. **The default is 0.**"
> Data type: Double

한국어 해설: 세 가지가 확정된다.

1. **`RingClosureValidator.swift`의 주석이 인용한 문장은 정확하다.** 소스 주석의 `"used to account for poor CAD topology — for example, line gaps between doors and walls."`는 위 Usage 원문과 일치한다. 개념 대응도 타당하다 — CAD 도면에서 문과 벽 사이가 미세하게 벌어져 있는 문제를 허용 오차로 흡수한다는 발상이 같다.
2. **단위는 인치(inch)다.** 도면 좌표계 단위도, 지리좌표 도(degree)도 아닌 **절대 물리 길이**다.
3. **기본값은 0이다.** 즉 Esri는 "이 정도면 붙은 것으로 쳐라"라는 권장 수치를 이 도구에서 제시하지 않는다. 기본 동작은 **아무것도 스냅하지 않는 것**이고, 사용자가 자기 도면을 보고 값을 넣어야 한다. 게다가 `CLOSE_DOORS`를 `Y`로 켜고 어느 폴리라인을 병합할지 `OPENINGS` 열에 미리 지정해야만 작동한다 — **전면 자동이 아니라 명시적 옵트인**이다.

**판정:** `Door Close Buffer`는 실존하는 파라미터이며 앱이 참조한 개념 대응도 맞다. 그러나 **여기서 얻을 수 있는 "권장 기본값"은 없다.** 기본값 0은 수치 권고가 아니라 "기능 꺼짐"이다. 그리고 이 도구 자체가 폐기 예정이므로, 근거로 인용해야 할 것은 후속 도구다. 2절이 그것이다.

---

## 2. 후속 도구의 `Door To Wall Distance`에는 **명확한 기본값 0.3 인치(7.62mm)가 있다**

후속 도구 **Import CAD To Indoor Dataset**의 Usage 절 원문:

> "In the **Source CAD Layers For Doors** or **Source Layers For Doors** parameters, provide the CAD or map layers that contain door features. Optionally, provide a value for the **Door To Wall Distance** parameter. This parameter value indicates the distance the tool will search from the door feature for the boundary of the related unit. The parameter value must include a numeric value and a unit of measure (**international inches or millimeters**). **The default is 0.3 international inches.**"

파라미터 표의 정의 원문:

> **Door To Wall Distance** (Optional)
> "The distance the tool will search from a door feature for a unit boundary in international inches or millimeters. **The default is 0.3 international inches.**"
> Data type: **Linear Unit**

한국어 해설: 이것이 이번 조사에서 확보한 **가장 직접적인 공식 근거**다. 뜯어보면 다음과 같다.

- **0.3 international inch = 7.62 mm** (international inch는 정확히 25.4mm로 정의된 단위다).
- 데이터 타입이 `Double`이 아니라 **`Linear Unit`**이다. 즉 사용자가 "7.62 Millimeters"처럼 **값과 단위를 함께** 입력한다. Esri가 이 값을 "좌표계 단위의 무차원 수"가 아니라 **물리적 길이**로 다루겠다고 타입 수준에서 선언한 것이다.
- 허용 단위가 **인치 또는 밀리미터**로 한정된다. 미터나 피트가 아니다. 이 선택 자체가 이 파라미터가 다루는 오차의 규모를 말해 준다 — **밀리미터 단위의 접합부 오차**다.
- 폐기된 도구의 기본값 0(기능 꺼짐)과 달리, 후속 도구는 **기능을 기본으로 켜 두고 7.62mm를 기본 탐색 거리로 준다.** Esri가 축적한 실무 경험이 반영된 값으로 읽는 것이 자연스럽다.

**판정:** "도면 선분을 폴리곤으로 닫을 때 문과 벽 사이 틈을 얼마까지 허용할 것인가"에 대한 **업계 표준 도구의 공식 기본값은 7.62mm**다. 이것은 추정이 아니라 문서에 명시된 수치다. 그리고 그 단위는 **도면 크기와 무관한 절대 물리 치수**다.

### 2-1. 같은 도구의 다른 임계값 파라미터

`Door To Wall Distance`만 보면 사례가 하나뿐이므로, 같은 도구가 쓰는 다른 임계값도 확인했다. 모두 단위가 붙은 절대 치수라는 점을 보이기 위해서다.

> **Minimum Unit Width** (Optional)
> "The minimum width **in international feet or meters** that a space must be to be considered a unit feature. Features with a width below this threshold will be written to a nonunit polygons feature class and will not be included in the target Units layer. **The default is 3 international feet.**"

> **Minimum Unit Area** (Optional)
> "The minimum area in square international feet or square meters that a space must be to be considered a unit feature. ... **The default is 9 square international feet.**"

> (폐기 도구 쪽) **Sliver Threshold** (Optional)
> "The ratio of perimeter to area that defines a sliver polygon. It is used when importing Unit polygons to improve the quality of the imported data. ... **The default is 2.**"

| 파라미터 | 기본값 | SI 환산 | 단위 성격 |
|---|---|---|---|
| Door To Wall Distance | 0.3 international inch | **7.62 mm** | 절대 길이 |
| Minimum Unit Width | 3 international feet | **914.4 mm** | 절대 길이 |
| Minimum Unit Area | 9 square international feet | **0.8361 m²** | 절대 면적 |
| Sliver Threshold | 2 | — | 무차원 비(둘레/면적) |

`Sliver Threshold`만 무차원인데, 이것은 **길이 허용 오차가 아니라 형상의 가늘기를 재는 비율**이라 성격이 다르다. **길이·면적 임계값은 예외 없이 절대 물리 치수다.**

참고로 IMDF 스펙에도 같은 성격의 절대 면적 하한이 하나 있다(`src11`이 다룬 Kiosk 페이지).

> IMDF 1.0.0 Kiosk: "A Kiosk **SHOULD** possess an area measurement that exceeds 0.5 square meters (exceeds 5.3 square feet)"

**판정:** 도면을 폴리곤으로 만드는 파이프라인의 임계값들은 **일관되게 실제 건물의 물리 치수로 정의된다.** 도면 파일의 크기·범위·좌표 자릿수와는 무관하다.

---

## 3. ArcGIS의 `XY Tolerance` / `XY Resolution` — 지오데이터베이스 계층의 공식 기본값

Esri Indoors보다 한 층 아래, 지오데이터베이스 자체가 "두 좌표가 같은 자리인가"를 판정하는 값이다. `RingClosureValidator`가 하는 일과 개념적으로 가장 가깝다.

"Feature class basics" 원문:

> "The x,y tolerance is an extremely small distance (the default is 0.001 meters in on-the-ground units). It is used to resolve inexact intersection locations of coordinates during clustering operations. When processing feature classes using geometry operations, coordinates whose x distance and y distance are within the x,y tolerance of each other are coincident (in other words, share the same x,y location)."

> "The maximum distance a coordinate can move to its new location during such operations is the square root of 2 times the x,y tolerance. The clustering algorithm is iterative, so in some cases coordinate locations may shift more than this distance."

> "**The default x,y tolerance is set to 0.001 meters or its equivalent in the units of the dataset's real-world coordinate system** (in other words, 0.001 meters on the ground). For example, if your coordinate system is recorded in state plane feet, the default x,y tolerance is 0.003281 feet (0.03937 inches). **The default value for the x,y tolerance is 10 times the default x,y resolution**, and this is recommended for most cases."

> "**The default x,y resolution for feature classes is 0.0001 meters** or its equivalent in the units of the dataset's coordinate system. For example, if a feature class is stored in state plane feet, the default precision is 0.0003281 feet (0.003937 inches). **If coordinates are in latitude-longitude, the default x,y resolution is 0.000000001 degrees.**"

"XY Tolerance (Environment setting)" 원문:

> **Caution:** "By default, a tool that uses this environment setting will use the x,y tolerance of the input feature class's spatial reference. **Overriding the default XY Tolerance is not recommended.** Instead, ensure that your input data spatial reference uses the default settings for its XY Resolution and XY Tolerance properties prior to analysis."

> "For tools such as Create Feature Class, Create Feature Dataset, and Create Raster Catalog, **the default x,y tolerance for the output geodataset is 0.001 meters (1 millimeter)** or its equivalent in map units."

허용 오차를 크게 잡을 때의 위험에 대한 경고 원문:

> "This can compromise the accuracy of feature boundary representations. **Your x,y tolerance should never approach your data capture resolution.** For example, at a map scale of 1:12,000, 1 inch equals 1,000 feet, and 1/50 of an inch equals 20 feet. Keep the coordinate movement using the x,y tolerance well under these numbers. Remember, the default x,y tolerance in this case is 0.0003281 feet, which is a reasonable default value for x,y tolerance; **in fact, it is best to use the default x,y tolerance values in all but extreme cases.**"

정리하면:

| 값 | 기본값 | 의미 |
|---|---|---|
| XY Resolution | **0.0001 m (0.1 mm)** | 좌표가 얹히는 정수 격자의 간격. 저장 가능한 최소 좌표 차이. |
| XY Tolerance | **0.001 m (1 mm)** | 두 좌표를 같은 자리로 볼 거리. Resolution의 **10배**. |

**판정:** 세 가지가 확정된다.

1. **기본 허용 오차는 1mm이고, 기준 단위는 "on-the-ground", 즉 실제 지상 거리다.** 데이터셋의 좌표계 단위가 무엇이든 실지상 1mm에 해당하는 값으로 환산된다. 도면 파일이 크든 작든 값은 같다.
2. **Tolerance = Resolution × 10이라는 관계에는 이유가 있다.** 허용 오차가 격자 간격에 근접하면 "같은 자리"라는 판정이 격자 양자화 오차와 구별되지 않는다. 10배의 여유가 그 구별을 보장한다. 앱이 자체 스냅 격자(`SnapPointExtractor.mergeTolerance = 0.05`, `ClosedPolygonFinder.mergeTolerance = 0.05`)를 쓰고 있으므로 이 비율 관계는 참고할 만하다.
3. **Esri는 이 값을 사용자가 건드리는 것을 명시적으로 말린다.** "Overriding the default XY Tolerance is not recommended", "it is best to use the default x,y tolerance values in all but extreme cases". 허용 오차를 키우는 것은 정합성을 사는 대신 **경계 정확도를 파는 거래**이고, Esri는 그 거래를 기본적으로 권하지 않는다.

---

## 4. FME의 스냅 허용 오차 — 기본값이 없고, "실측해서 정하라"고 안내한다

FME **AreaBuilder** 트랜스포머의 스냅 전처리 파라미터 원문:

> **Snapping Type:** "Select a method for the optional pre-processing of input features:"
> - "**None** — No pre-processing is done."
> - "**End Point Snapping** — Snaps end points of lines together if the distance between them is within the specified Snapping Tolerance."
> - "**Vertex Snapping** — Snaps vertices of lines together if the distance between them is within the specified Snapping Tolerance."
> "When two features are snapped together, the last feature (in order of processing) is modified to match the first."

> **Snapping Tolerance:** "When Snapping Type is End Point Snapping or Vertex Snapping, specify the maximum distance **in ground units** between points for them to be snapped together."

**Snapper** 트랜스포머 쪽의 대응 파라미터:

> **Snapping Distance:** "specifies the distance, **in ground units**, that the snapping occurs between features."

한국어 해설: FME는 **기본값을 제시하지 않는다.** 기본 Snapping Type이 `None`이므로 스냅 자체가 꺼져 있고, 켜면 사용자가 값을 넣어야 한다. Safe Software의 커뮤니티 안내는 값을 정하는 방법을 이렇게 설명한다 — 좌표계의 지상 단위(UTM이면 미터, 위경도면 도)로 넣되, **FME Data Inspector에서 실제 틈을 재어 보고 그 값에 맞추라**는 것이다.

또 하나 눈여겨볼 것은 AreaBuilder가 **스냅을 "전처리(pre-processing)"로 분리**해 두었다는 점이다. 선분에서 폴리곤을 만드는 작업(면 구성)과 끝점을 붙이는 작업(스냅)이 별개의 단계로 설계돼 있고, 스냅은 선택이다.

**판정:** FME에서도 **권장 기본 수치는 얻을 수 없다.** 그러나 세 가지 방향성은 Esri와 정확히 일치한다 — (1) 단위는 **ground units**, 즉 실제 지상 거리다, (2) 기본은 **꺼짐**이다, (3) 값은 **도면 크기가 아니라 실제 틈의 크기**에서 나온다. `src06`·`src10`이 정리한 FME 워크플로우와 같은 맥락이다.

---

## 5. "도면 크기 비례" 접근의 타당성 — **부적절하다**

앱의 현재 구현(`AppEnvironment.swift`)은 다음과 같다.

```swift
/// 도면 크기에 비례한 허용오차. 고정값을 쓰면 큰 도면에서는 이중선이 안 잡히고
/// 작은 도면에서는 멀쩡한 선이 겹침으로 잡힌다.
var overlapTolerance: Double {
    guard let d = document else { return 0.5 }
    return max(0.25, min(d.canvasSize.width, d.canvasSize.height) / 2000)
}
```

그리고 이 값이 링 닫힘 판정에 그대로 재사용된다.

```swift
return RingClosureValidator.validate(segments: segments, tolerance: overlapTolerance)
// 겹침 판정과 같은 허용 오차를 쓴다. 도면 크기에 비례하므로 큰 도면에서도 같은 기준이 된다.
```

**이 절은 원문 인용이 아니라 위 1~4절의 사실에 근거한 자체 판정이다.**

### 5-1. 물리적 근거의 문제

CAD 도면에서 문과 벽 사이가 벌어지는 원인은 **작도 과정의 실수와 스냅 실패**다. 제도자가 벽 선을 문틀 위치까지 끌어오다 몇 mm 못 미치거나 지나친 것이고, 그 편차의 크기는 **그리고 있는 대상의 실제 치수**에 좌우된다. 건물이 10층이든 1층이든, 도면 파일의 viewBox가 1000이든 100000이든, 문틀 접합부의 틈은 실제 세계에서 수 mm 규모다.

Esri가 이 파라미터의 허용 단위를 **인치 또는 밀리미터로 못 박고**(2절), 타입을 `Linear Unit`으로 정의하고, 지오데이터베이스 계층의 XY Tolerance를 **"0.001 meters on the ground"**로 정의한 것(3절)은 모두 같은 인식의 표현이다. 조사한 세 계열(Esri Indoors 도구, ArcGIS 지오데이터베이스, FME 트랜스포머) 어디에도 **도면 크기·범위·축척에 비례하는 허용 오차는 없다.**

오히려 ASPRS 2014 표준이 축척 연동 임계값을 명시적으로 폐기한 논리가 여기 그대로 적용된다(`src16` 4-2절 인용).

> "they are inappropriate for digital geospatial data where scale and contour interval are changed with a push of a button while not changing the underlying horizontal and/or vertical accuracy."

한국어 해설: 축척은 버튼 한 번으로 바뀌지만 그 아래 깔린 데이터의 정확도는 바뀌지 않는다 — 그러므로 정확도 기준을 축척에 매다는 것은 틀렸다는 논지다. 도면 크기에 매단 허용 오차도 같은 오류의 변형이다.

### 5-2. 현재 공식의 실제 거동

`min(canvasSize.width, canvasSize.height) / 2000`이 어떤 값을 내는지, SVG 파서의 기본 캔버스(`SVGParser.swift`: `CGSize(width: 1000, height: 800)`)와 몇 가지 viewBox를 가정해 계산하면 다음과 같다. **아래 표의 "실제 의미" 열은 viewBox 단위가 무엇이냐에 따른 가정이며, 앱은 그 단위를 알지 못한다.**

| 도면 viewBox | `overlapTolerance` (도면 단위) | viewBox 단위가 mm라면 | viewBox 단위가 px(96dpi)라면 |
|---|---|---|---|
| 1000 × 800 (파서 기본값) | max(0.25, 0.4) = **0.4** | 0.4 mm | 0.106 mm |
| 20000 × 15000 (mm 단위 도면) | max(0.25, 7.5) = **7.5** | **7.5 mm** | 1.98 mm |
| 100000 × 80000 | max(0.25, 40) = **40** | 40 mm | 10.6 mm |
| 300 × 200 | max(0.25, 0.1) = **0.25** (하한) | 0.25 mm | 0.066 mm |

두 가지가 드러난다.

**(1) 우연히 맞는 구간이 있다.** viewBox가 mm 단위이고 도면이 20m × 15m 규모라면 7.5mm가 나오는데, 이는 Esri의 `Door To Wall Distance` 기본값 7.62mm와 거의 일치한다. 이 우연이 개발 중 "잘 동작하는 것처럼" 보이게 했을 가능성이 있다.

**(2) 그러나 그 구간을 벗어나면 급격히 무너진다.** 같은 mm 단위 가정에서 도면이 5배 커지면 허용 오차는 40mm — **일반적인 벽 두께(100~300mm)의 절반에 육박**하고, 문 하나 폭(약 900mm)의 4%가 넘는다. 이 정도면 붙어 있지 않은 벽이 붙은 것으로 판정되고, `RingClosureValidator`의 `usable = segments.filter { $0.length > tolerance }`가 40mm 미만의 짧은 선분을 링의 변에서 통째로 제외한다.

**(3) 단위를 모른다는 것이 근본 문제다.** SVG `viewBox`의 값은 무차원 사용자 단위다. 같은 `viewBox="0 0 1000 800"`이 20m짜리 사무실일 수도, 200m짜리 공항 터미널일 수도 있다. **비례 공식은 이 불확실성을 해결하지 않고 감출 뿐이다** — 어떤 도면에서든 그럴듯한 숫자를 내놓지만, 그 숫자가 물리적으로 무엇을 뜻하는지는 앱도 사용자도 모른다.

### 5-3. 원래 주석의 논리 재검토

주석은 "고정값을 쓰면 큰 도면에서는 이중선이 안 잡히고 작은 도면에서는 멀쩡한 선이 겹침으로 잡힌다"고 한다. 이 진술은 **"고정값"을 도면 사용자 단위의 고정 상수로 해석할 때만 참**이다. 물리 단위(mm)로 고정하고 축척을 통해 도면 단위로 환산하면, 큰 도면에서든 작은 도면에서든 **같은 물리 거리**를 뜻하게 되어 문제가 사라진다. 즉 주석이 지적한 현상은 실재하지만, 원인 진단이 "고정값이라서"가 아니라 **"물리 단위를 모른 채 고정했기 때문"**이다.

**판정:** 도면 크기 비례 접근은 **공식 근거가 없고, 물리적 근거도 없다.** 조사한 모든 공식 문서가 절대 물리 치수를 쓴다. 다만 비례값이 완전히 무가치한 것은 아니다 — **축척을 알 수 없을 때의 마지막 대비책**으로는 남길 수 있다. 6절 권고에서 그 위치를 지정한다.

---

## FP-to-IMDF 앱에 대한 권고

### 권고 1. 허용 오차를 **밀리미터로 정의하고 축척으로 환산한다** — 단위 선택은 **공식 근거**, 기본값은 **공식 근거에 근거한 판단**

허용 오차의 1차 정의를 **실제 건물의 밀리미터**로 바꿀 것을 권고한다.

```
tolerance_도면단위 = tolerance_mm / (1 도면단위당 mm)
```

`1 도면단위당 mm`(축척)를 얻는 경로는 둘이다.

- **지오레퍼런싱이 끝난 뒤**: `GeoAffineTransform`에서 직접 유도할 수 있다. 변환식 `lon = a·x + b·y + c`, `lat = d·x + e·y + f`에서, 도면 단위 1당 지상 거리는 위도 φ에서 대략 `√((a·111320·cosφ)² + (d·110540)²)` (x 방향)이다. `ResidualCalculator.metersBetween`이 이미 같은 등거리 원통 근사를 쓰고 있으므로 상수를 공유하면 된다. 이 값에 1000을 곱하면 도면 단위당 mm다.
- **지오레퍼런싱 전**: 사용자에게 축척을 직접 받는다. 도면에서 알려진 두 점을 찍고 실제 거리를 입력받는 방식이 가장 짧다. Anchor 두 개를 찍는 절차와 UI가 겹치므로 재사용 여지가 있다.

**권장 기본값: 10 mm.** 근거는 다음과 같다.

| 참조값 | 수치 | 성격 |
|---|---|---|
| ArcGIS XY Tolerance 기본값 | 1 mm | 공식 기본값 — 하한 참조 |
| Esri Door To Wall Distance 기본값 | 7.62 mm | 공식 기본값 — **직접 대응하는 사례** |
| **권고 기본값** | **10 mm** | 위 두 값 사이. 7.62mm를 십진 반올림한 값 |
| 일반적인 벽 두께 하한 | 100 mm | 넘어서는 안 되는 선 (10배 여유) |
| Esri Minimum Unit Width 기본값 | 914.4 mm | 훨씬 큰 규모 — 간섭 없음 |

10mm는 **Esri의 7.62mm를 실무적으로 다루기 쉬운 십진값으로 올린 것**이며, ArcGIS의 1mm보다는 관대하되 벽 두께 하한(100mm)보다 한 자릿수 작다. 스냅으로 붙일 수 있는 틈과 실제로 뚫린 개구부를 가르는 위치로 적절하다. **7.62mm는 공식 문서의 수치이고, 10mm는 그것을 근거로 삼은 이 문서의 판단**임을 구분해 둔다.

조절 범위는 **1 ~ 50 mm**를 권고한다. 하한 1mm는 ArcGIS XY Tolerance 기본값이고, 상한 50mm는 벽 두께 하한 100mm의 절반이다. 그 이상은 벽 자체를 삼키기 시작하므로 UI에서 막는 편이 낫다.

### 권고 2. **사용자 조절을 허용하되, 기본값 사용을 권장하는 방향으로 안내한다** — **공식 근거**

3절에서 확인한 Esri의 태도가 그대로 적용된다.

> "Overriding the default XY Tolerance is not recommended."
> "it is best to use the default x,y tolerance values in all but extreme cases."

허용 오차를 키우면 판정은 통과하지만 **경계 정확도를 잃는다.** 사용자가 "닫히지 않았습니다"라는 경고를 없애려고 값을 계속 올리는 것은 자연스러운 행동이고, 그 결과는 실제로 벌어진 도면이 닫힌 것으로 처리되는 것이다.

따라서 조절은 허용하되(FME도 Esri도 모두 사용자 입력값이다), UI에서 다음을 갖출 것을 권고한다.

- 기본값을 명시하고 되돌리는 버튼을 둔다.
- 기본값을 크게 벗어난 값(예: 3배 이상)을 넣으면 "허용 오차를 키우면 실제로 벌어진 곳도 닫힌 것으로 판정됩니다"라고 알린다.
- **틈의 실제 크기를 mm로 보여 준다.** `RingClosureValidator.Gap.distance`가 이미 최근접 거리를 갖고 있으므로, 축척만 있으면 "이 자리는 23mm 벌어져 있습니다"라고 표시할 수 있다. FME 커뮤니티가 권하는 "실측 후 결정"을 앱이 대신 해 주는 셈이고, 값을 조절할 때 근거를 준다.

### 권고 3. **링 닫힘 허용 오차와 겹침 허용 오차를 분리한다** — **공학적 판단**

현재는 `ringClosure(of:)`가 `overlapTolerance`를 그대로 넘긴다. 그러나 두 판정은 묻는 것이 다르다.

| 판정 | 묻는 것 | 적정 허용 오차의 성격 |
|---|---|---|
| 링 닫힘 | "이 끝점과 저 끝점은 같은 자리인가" | 작아야 한다. CAD 접합부 오차 규모(mm). |
| 겹침 | "이 선과 저 선이 같은 벽인가" | 더 클 수 있다. 이중선의 간격은 작도 방식에 따라 cm 규모일 수도 있다. |

링 닫힘을 통과시키려고 허용 오차를 키우면 겹침 판정이 과민해지고, 그 반대도 마찬가지다. **둘을 별개의 값으로 분리하되, 둘 다 물리 단위(mm)로 정의**할 것을 권고한다. 링 닫힘의 기본값은 권고 1의 10mm, 겹침은 그보다 크게 잡되(예: 25mm) 실제 도면으로 조정한다. **겹침 쪽 수치는 이 조사에서 공식 근거를 확보하지 못했다.**

### 권고 4. `usable` 필터의 임계값을 허용 오차와 분리한다 — **공학적 판단**

`RingClosureValidator.validate`의 첫 줄:

```swift
let usable = segments.filter { $0.length > tolerance }
// 길이가 오차보다 짧은 선분은 점이나 다름없어 링의 변으로 세면 판정이 흔들린다.
```

의도는 타당하다 — 허용 오차보다 짧은 선분은 그 자체가 잡음이다. 그러나 **허용 오차를 키우면 이 필터가 함께 커지는 부작용**이 있다. 5-2절에서 본 대로 허용 오차가 40mm까지 커지면 40mm 미만 선분이 전부 제외되는데, 실제 도면에는 문설주 마감선처럼 그 정도 길이의 유효한 짧은 선분이 존재한다.

두 값을 분리하고, 잡음 선분 필터는 **허용 오차와 무관한 고정 물리 치수**(예: 2mm)로 두거나 `tolerance / 2` 정도로 완만하게 연동할 것을 권고한다. 이는 3절에서 확인한 Esri의 "Tolerance = Resolution × 10" 관계와 같은 발상 — **격자 해상도와 판정 허용 오차 사이에 일정한 배율을 두어 두 판정이 서로 간섭하지 않게 하는 것**이다.

### 권고 5. 축척을 끝내 알 수 없을 때의 대비책 — **차선책임을 명시**

지오레퍼런싱 전이고 사용자도 축척을 입력하지 않은 상태에서는 물리 단위 환산이 불가능하다. 이때만 현재의 비례 공식을 **폴백(fallback)**으로 남긴다. 다만 두 가지를 지킬 것을 권고한다.

- 코드 주석과 UI 양쪽에서 **"축척 미상 시의 임시값"**임을 명시한다. 지금처럼 "도면 크기에 비례하므로 큰 도면에서도 같은 기준이 된다"고 적어 두면 근거가 있는 값으로 오독된다 — 5-1절에서 본 대로 그 진술은 성립하지 않는다.
- 이 상태에서는 링 닫힘 판정 결과를 **확정으로 다루지 않는다.** 내보내기 직전 경고(`openRingFeatures`)는 지오레퍼런싱이 끝난 뒤 물리 단위로 재판정한 결과를 쓰는 것이 맞다. 어차피 내보내기는 지오레퍼런싱 이후에만 가능하므로 순서상 무리가 없다.

---

## 미해결 질문

- ArcGIS Indoors의 CAD 도면 준비 가이드(`prepare-cad-floor-plan-data.htm`)가 2026-08-29 조회 시 404였다. 도면 품질에 대한 권고(예: 허용 가능한 틈의 크기, 레이어 구성 요건)가 이 계층에 있었을 가능성이 있으므로 경로를 다시 찾아 확인할 것.
- `Door To Wall Distance` 기본값 0.3 inch가 어떤 근거에서 나왔는지 — Esri 문서는 값만 제시하고 유래를 설명하지 않는다. `Door Close Buffer`(기본값 0)에서 후속 도구(기본값 0.3 inch)로 넘어오며 값이 생긴 경위도 문서화되어 있지 않다.
- 권고 3의 겹침 허용 오차 기본값(25mm)은 **공식 근거 없는 임시 제안**이다. 이중선으로 그려진 벽의 실제 간격 분포를 도면 몇 건으로 확인한 뒤 정할 것.
- SVG `viewBox` 단위를 추정할 수 있는 단서가 SVG 파일 자체에 있는지 — `width`/`height` 속성에 `mm`·`in` 같은 물리 단위가 붙어 있으면 `viewBox`와의 비로 축척을 직접 계산할 수 있다. `SVGParser.swift`가 그 속성을 파싱하는지, 파싱한다면 단위를 보존하는지 미확인.
- FME `AreaBuilder`가 스냅을 "전처리"로 분리한 설계가 앱에도 유효한지 — 지금 앱은 판정만 하고 붙이지는 않는다. 사용자에게 "이 틈들을 붙일까요"를 제안하는 단계를 둘 가치가 있는지는 별도 검토가 필요하다.
