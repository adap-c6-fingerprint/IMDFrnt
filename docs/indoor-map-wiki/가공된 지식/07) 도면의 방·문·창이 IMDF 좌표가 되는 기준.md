---
summary: 도면 위의 사각형 방 하나가 IMDF 좌표로 옮겨질 때 정확히 어떤 점이 좌표화되는지(Unit 폴리곤 꼭짓점 = 벽 중심선 또는 면), 문·창문은 각각 어떻게 취급되는지(문=Opening LineString, 창=IMDF에 없음), 그리고 흩어진 선분 집합을 자동으로 '방'으로 묶는 세 가지 기준(레이어·위상·텍스트 앵커)을 OGC IMDF 스펙과 Esri·FME 공식 문서로 정리
source: 01-2) 소스 --------------------/S06) Indoor Map/S06-02) FP-to-IMDF/src10. 도면 선분이 Unit 폴리곤 좌표로 변환되는 기준 조사 — OGC IMDF·Esri Indoors·FME.md
related:
  - "[[IMDF]]"
  - "[[GeoJSON]]"
  - "[[지오레퍼런싱]]"
  - "[[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]]"
  - "[[05) 라벨에 관하여]]"
  - "[[04) ArcGIS Indoors]]"
  - "[[03) FME]]"
created: 2026-08-20 00:00
updated: 2026-08-20 00:00
core_keywords:
  - IMDF
  - 폴리곤화
  - CAD 레이어 표준
  - 지오레퍼런싱
---
# 도면의 방·문·창이 IMDF 좌표가 되는 기준

## 요약

[[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]]은 "지오레퍼런싱으로 도면 전체에 변환식이 적용되고, 그 결과 IMDF의 모든 geometry vertex가 지구 좌표를 갖는다"까지를 다뤘다. 이 문서는 그 **한 단계 앞**을 다룬다. 즉 좌표를 부여받을 그 vertex 집합이 애초에 도면의 어느 선에서, 어떤 기준으로 만들어지는가다.

질문은 셋으로 나뉜다.

1. 사각형 방 하나가 IMDF로 갈 때 **정확히 어떤 점이 좌표화되는가.** 꼭짓점만인가, 문·창까지인가.
2. 문과 창문은 각각 어떻게 취급되는가.
3. 그 좌표들의 집합을 사람이 하나하나 지정하지 않고 **자동으로 "방"·"문"으로 정의하려면 무엇을 기준으로 묶어야 하는가.**

결론을 먼저 말하면 이렇다. 좌표로 남는 것은 **방의 Unit 폴리곤 꼭짓점**과 **문의 Opening LineString 양 끝점**뿐이고, **창문은 IMDF에 아예 남지 않는다.** 그리고 자동 그룹화의 기준은 좌표값 자체가 아니라 **레이어(의미) · 위상(닫힘) · 텍스트 앵커(이름)** 세 축의 조합이다.

---

## 1. 방 — 좌표화되는 점은 어디인가

### 1.1 Unit은 폴리곤이고, 남는 점은 그 꼭짓점이다

OGC IMDF 1.0.0 스펙의 Unit 페이지는 geometry 타입을 이렇게 규정한다.

> "Unit objects **MUST** have a `"geometry"` member with a `POLYGONAL` value"
> — [OGC IMDF 1.0.0, Unit](https://docs.ogc.org/cs/20-094/Unit/index.html)

즉 사각형 방 하나는 최종 IMDF에서 **꼭짓점 4개(+ 시작점 반복 1개)를 가진 Polygon 하나**가 된다. 도면에 그 방을 그리기 위해 몇 개의 선분·호·블록이 쓰였든, 최종 산출물에 남는 좌표는 그 폴리곤의 꼭짓점 목록뿐이다.

```json
{
  "type": "Feature",
  "feature_type": "unit",
  "geometry": {
    "type": "Polygon",
    "coordinates": [[
      [126.9780, 37.5665],
      [126.9782, 37.5665],
      [126.9782, 37.5667],
      [126.9780, 37.5667],
      [126.9780, 37.5665]
    ]]
    // 사각형 방 = 꼭짓점 4개 + 첫 점 반복(폴리곤 링은 닫혀야 함)
  },
  "properties": { "category": "room", "level_id": "...", "name": { "ko": "회의실 A" } }
}
```

### 1.2 그 꼭짓점은 벽의 어디에 놓이는가 — 중심선인가 면인가

여기가 실무에서 가장 헷갈리는 지점이다. 벽은 도면에서 두께를 가진 **두 줄**로 그려지는데, 방 폴리곤의 변은 그중 어느 선을 따라가야 하는가.

스펙은 **둘 다 허용**한다.

> "A Unit boundary **MAY** approximate an imaginary line running down the **center** of a physical, vertical barrier"
> "a Unit boundary **MAY** follow [source data] that models the **'face'** of a physical, vertical barrier"
> — [OGC IMDF 1.0.0, Unit](https://docs.ogc.org/cs/20-094/Unit/index.html)

- **중심선(centerline) 방식:** 벽 두께의 한가운데를 지나는 가상의 선을 방 경계로 삼는다.
- **면(face) 방식:** 벽의 실제 안쪽 면(방에서 보이는 벽면)을 방 경계로 삼는다.

그런데 스펙에는 이 선택을 사실상 좁히는 다른 규정이 하나 더 있다.

> "[Symmetrical difference] **MUST NOT** exist: Among Units that reference the same Level" / "Between the [union] of Units and their referenced Level."
> — [OGC IMDF 1.0.0, Unit](https://docs.ogc.org/cs/20-094/Unit/index.html)

**Symmetrical difference(대칭차)**란 두 도형 중 어느 한쪽에만 속하는 영역을 말한다. 쉽게 말해 이 규정은 **① Unit끼리 겹치거나 사이에 틈이 있으면 안 되고, ② 모든 Unit을 합친 도형이 Level(층 전체)과 한 치의 오차 없이 같아야 한다**는 뜻이다. `00) Apple Indoor Maps Program과 IMDF 개요`가 말한 "레벨은 유닛으로 완전히 덮인다"가 스펙 문장으로는 이렇게 표현된 것이다.

이 규정을 앞의 선택지와 겹쳐 보면:

| 방식 | 인접한 두 방 사이에서 | 결과 |
| --- | --- | --- |
| 면(face) | 각 방이 자기 쪽 벽면까지만 차지 → **벽 두께만큼 빈 영역**이 남음 | 빈 영역 = symmetrical difference → **규정 위반** |
| 중심선(center) | 두 방이 벽 중앙에서 정확히 맞닿음 → 빈 영역 없음 | **규정 충족** |

따라서 **인접 실이 있는 내부 벽에서는 중심선 방식으로 수렴**한다. 반면 건물 외곽처럼 반대편에 다른 Unit이 없는 경계에서는 면 방식도 성립한다.

> **확인 필요:** 이 "중심선으로 수렴" 결론은 스펙이 한 문장으로 명시한 것이 아니라, `MAY` 두 개와 `MUST NOT symmetrical difference` 규정을 결합해 도출한 해석이다. Apple·OGC 문서에 이를 직접 권고하는 문장이 있는지는 추가 확인이 필요하다.

이 결론은 [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] 3절의 FME 실무 규칙("Units 레이어 안의 빈 영역은 최종 IMDF에서 벽으로 취급된다")과도 어긋나지 않는다. FME 규칙은 **Units 레이어를 그리는 중간 단계**에서 채워지지 않은 자리를 벽으로 해석한다는 도구 차원의 관행이고, 최종 IMDF 단계에서는 그 벽이 독립 도형으로 남는 게 아니라 양옆 Unit 경계가 맞닿은 선으로 흡수된다.

### 1.3 벽 교차부·기둥은 단순화가 의무다

스펙은 복잡한 지점에서 단순화를 요구한다.

> "A physical, vertical barrier **SHOULD** be [simplified]"
> "The simplification of physical, vertical barriers **MUST** occur in all complex architectural scenarios" — 예시로 "Multiple wall intersections", "Wall/column combinations"를 든다.
> — [OGC IMDF 1.0.0, Unit](https://docs.ogc.org/cs/20-094/Unit/index.html)

벽이 여러 개 만나는 모서리나 벽에 기둥이 물린 자리를 도면 그대로 옮기면 꼭짓점이 수십 개로 늘어난다. 스펙은 이런 곳에서 **`MUST`(의무)로 단순화**하라고 한다. 즉 좌표화는 "도면의 모든 점을 그대로 옮기는 작업"이 아니라 **의도적으로 점을 줄이는 작업**을 포함한다.

---

## 2. 문 — 별도 피처로, 선분으로 좌표화된다

문은 방 폴리곤에 포함되는 것이 아니라 **독립된 Opening 피처**가 된다.

> "Opening objects **MUST** have a `"geometry"` member with a `LINE-STRING` value"
> — [OGC IMDF 1.0.0, Opening](https://docs.ogc.org/cs/20-094/Opening/index.html)

**LineString**이므로 문 하나는 보통 **좌표 2개(개구부의 양 끝점)**로 표현된다. 벽 선 위에서 문이 뚫린 구간을 잇는 선분 하나라고 보면 된다.

주목할 점은 문짝 자체의 형상이 좌표로 들어가지 않는다는 것이다. CAD 도면에서 문은 보통 문짝 패널과 열림 궤적을 나타내는 호(arc)로 그려지는데, 이 형상은 IMDF에서 좌표가 아니라 **properties의 `door` 객체**로 들어간다.

| `door` 객체 필드 | 값 예시 |
| --- | --- |
| `automatic` | `true` / `false` (자동문 여부) |
| `material` | `"glass"` 등 |
| `type` | `"sliding"` 등 (개폐 방식) |

즉 **"미닫이 유리 자동문"이라는 정보는 도형이 아니라 속성값으로 기록된다.** 좌표는 개구부 양 끝점 2개뿐이다.

Opening의 category 값은 `automobile`, `bicycle`, `pedestrian`, `emergencyexit`, `pedestrian.principal`, `pedestrian.transit`, `service` 일곱 가지다. 이 중 기본값 격인 `pedestrian`의 정의는 다음과 같다.

> "models the presence and physical extent of an entrance **with or without a physical door**"
> — [OGC IMDF 1.0.0, Opening](https://docs.ogc.org/cs/20-094/Opening/index.html)

문짝이 달려 있든 없든(아치형 통로, 문 없는 출입구 등) **통과 가능한 개구부의 물리적 범위**를 모델링한다는 뜻이다. 이 정의는 Opening이 "문"이 아니라 "지나갈 수 있는 구멍"을 나타내는 피처임을 분명히 한다.

---

## 3. 창문 — IMDF에 남지 않는다

Opening의 category 일곱 값 어디에도 창문에 해당하는 것이 없다. `service`가 "non-floor-to-ceiling barrier (counter/pony wall)"로 카운터나 낮은 칸막이를 다루지만 이는 서비스 창구이지 채광용 창이 아니다. [[05) 라벨에 관하여]]에서 확인한 **Feature Type 16종 목록**에도 window에 해당하는 타입은 없다.

즉 **창문은 IMDF 최종 산출물에 좌표로 존재하지 않는다.**

이유는 IMDF의 목적을 생각하면 자연스럽다. IMDF는 실내에서의 **방향 잡기·경로 안내·측위**를 위한 포맷이다(`00) 개요` 참조). 사람이 통과할 수 있는 문은 경로 그래프에 필수지만, 통과할 수 없는 창은 경로에 아무 영향이 없다.

다만 중간 단계에서는 창문이 다뤄진다. Esri ArcGIS Indoors는 CAD 준비 단계에서 창문 레이어를 명시적으로 요구한다.

> "Polylines representing the geometry of details. For example, you may have polylines representing **walls, doors, windows, columns, and furniture**"
> — [Esri, Prepare CAD for ArcGIS Indoors](https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/cad-floor-plan-drawings.html)

정리하면 **창문은 ArcGIS Indoors의 Details 중간 모델에는 들어가지만, IMDF export 대상은 아니다.** 자동화 툴을 만든다면 창문은 파싱 대상에서 제외하거나, 파싱하더라도 최종 출력에서 버리는 데이터로 설계하면 된다.

---

## 4. 여기까지의 답 — 사각형 방 하나가 남기는 좌표

| 도면 위 요소 | IMDF 최종 좌표 | 형태 |
| --- | --- | --- |
| 방의 벽 4면 | **있음** — Unit 폴리곤 꼭짓점 4개 | Polygon (벽 중심선 기준으로 수렴) |
| 벽 두께(두 줄) | 없음 — 한 줄로 흡수 | — |
| 벽 교차부·기둥 물린 자리 | 없음 — 단순화 의무 | — |
| 문 | **있음** — Opening 양 끝점 2개 | LineString (별도 피처) |
| 문짝·스윙 호 | 없음 — `door` properties로 이동 | 속성값 |
| 창문 | **없음** | — |
| 가구·설비 | 없음(단, Fixture로 선택적 표현 가능) | — |

> **후속 확인(2026-08-20):** [[08) IMDF Feature Type·카테고리 전체 레퍼런스]]를 작성하며 **FIXTURE-CATEGORY에 `wall` 값이 존재**하는 것이 확인됐다. "Wall이라는 독립 Feature Type은 없다"는 사실은 그대로지만, 벽을 명시적으로 남기고 싶다면 `feature_type: "fixture"`, `category: "wall"`인 Polygon으로 표현하는 경로가 스펙상 열려 있다. UNIT-CATEGORY에도 `brick`·`concrete`·`drywall`·`glass`·`wood` 같은 재질 값과 `column`·`structure`가 있어, 벽·기둥을 Unit으로 표현하는 경로도 존재한다. 둘 중 무엇이 권장 방식인지는 스펙에 서술이 없어 확인 필요.

---

## 5. 자동 그룹화 — 좌표 집합을 무엇을 기준으로 "방"으로 묶는가

이제 핵심 질문이다. 도면 파일 안에는 수천 개의 선분이 좌표값으로만 흩어져 있다. 이걸 사람이 하나씩 "이 4개는 회의실"이라고 지정하지 않고 자동으로 묶으려면 무엇을 기준으로 삼아야 하는가.

답은 **좌표값 자체로는 불가능하다**는 것이다. 좌표는 "여기에 선이 있다"만 말해줄 뿐 "이게 방이다"를 말해주지 않는다. 상용 도구들이 실제로 쓰는 기준은 좌표 바깥에 있는 **세 축**이다.

### 5.1 축 1 — 레이어: "이 선이 무엇인가"

CAD 도면의 모든 엔티티는 레이어에 속한다. 벽은 벽 레이어에, 문은 문 레이어에, 방 경계는 방 레이어에 그려진다. **이 레이어 이름이 의미 정보의 유일한 출처다.**

Esri는 이 때문에 레이어 명명 규약 준수를 요구한다.

> "Consistent layer naming across CAD drawings allows for a well-organized and extendable data conversion and management process."
> — [Esri, Prepare CAD for ArcGIS Indoors](https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/cad-floor-plan-drawings.html)

권장 규약은 **U.S. National CAD Standard**의 AEC Naming convention이다. 이는 `A-WALL`, `A-DOOR`처럼 분야 코드(A=Architectural)와 요소 코드를 조합하는 표준 레이어 명명 체계다. 규약이 지켜진 도면이라면 레이어 이름만으로 벽·문·창을 기계적으로 분류할 수 있다.

실제 매핑은 Excel 구성 파일로 이뤄진다([Esri, Configure CAD floor plan mappings](https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/map-floor-plans-to-indoors.html)).

| 컬럼 | 무엇을 받는가 |
| --- | --- |
| `UNITS` | "closed polylines that define the extents of individual units, such as rooms, hallways, and other navigable spaces" |
| `UNIT_LINES` | 닫히지 않은 선분들로 unit을 구성해야 하는 경우 |
| `OPENINGS` | "polylines... that represent doors that must be shut when generating the output unit polygons" |
| `DETAILS` | "interior details that you want to import, such as walls, doors, and windows" |

즉 **"어느 레이어가 방이고 어느 레이어가 문인가"를 사람이 한 번 선언하면, 그 뒤로는 도구가 자동 처리한다.** 자동화의 실체는 "AI가 도형을 보고 방을 알아맞히는 것"이 아니라 **레이어 → 피처 타입 매핑 테이블을 한 번 만들어 재사용하는 것**이다. (도면마다 레이어 이름이 제각각이면 이 테이블을 매번 새로 만들어야 하고, 이것이 CAD→IMDF 변환이 완전 자동화되지 못하는 근본 이유다.)

### 5.2 축 2 — 위상: "어디까지가 한 방인가"

레이어로 "이 선들은 방 경계다"까지 알았다면, 다음은 그 선들을 **닫힌 면 단위로 묶는** 작업이다. 이것을 **폴리곤화(polygonization)**라 한다.

가장 쉬운 경우는 도면이 애초에 방마다 닫힌 폴리라인 하나로 그려진 경우다. Esri가 요구하는 이상적 입력이 바로 이것이다.

> "Layers with **closed polylines**, where each closed polyline represents a room"
> — [Esri, Prepare CAD for ArcGIS Indoors](https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/cad-floor-plan-drawings.html)

하지만 대부분의 실제 도면은 그렇지 않다. 벽이 그냥 선분들로 흩어져 있고, 방은 그 선분들이 우연히 둘러싼 영역으로만 존재한다. 이때 필요한 것이 **평면 그래프에서 닫힌 면을 추출하는 알고리즘**이다.

FME는 이를 `AreaBuilder` 트랜스포머로 제공한다.

> "Creates polygons from **topologically correct** linear features... creates areas wherever the linework **surrounds closed shapes**."
> — [Safe Software, AreaBuilder](https://docs.safe.com/fme/html/FME-Form-Documentation/FME-Transformers/Transformers/areabuilder.htm)

오픈소스로 직접 구현한다면 Shapely의 `polygonize`가 같은 일을 한다.

> "polygonizes an array of Geometries that contain **linework which represents the edges of a planar graph**"
> — [Shapely, shapely.polygonize](https://shapely.readthedocs.io/en/stable/reference/shapely.polygonize.html)

```python
from shapely import LineString, polygonize
lines = [
    LineString([(0, 0), (1, 1)]),
    LineString([(0, 0), (0, 1)]),
    LineString([(0, 1), (1, 1)]),
]
polygonize(lines)
# <GEOMETRYCOLLECTION (POLYGON ((1 1, 0 0, 0 1, 1 1)))>
# 선분 3개가 둘러싼 닫힌 영역 하나를 폴리곤으로 추출
```

두 도구 모두 **"위상적으로 깨끗한 선형"**을 전제로 한다는 점이 결정적이다. FME 문서가 열거하는 실패 원인은 다음과 같다.

- 교차점에서 끊기지 않은 선 (features not terminating at intersections)
- 어긋난 노드 (misaligned nodes)
- 오버슛/언더슛 (overshoots/undershoots) — 선이 교차점을 지나쳐 튀어나오거나 못 미쳐 끊긴 경우
- 교차점 노드 누락

폴리곤을 만들지 못한 선은 `Incomplete` 포트로 빠진다. Shapely에서는 `polygonize_full`이 같은 진단 정보를 반환하고, `shapely.node`가 폴리곤화 전 **노딩**(모든 교차점에서 선을 쪼개는 작업)을 담당한다.

> "[`node`] can be used to create a **fully-noded** linework suitable to [be] passed as input to polygonize."
> — [Shapely, shapely.node](https://shapely.readthedocs.io/en/stable/reference/shapely.node.html)

허용 오차 기준도 명시되어 있다.

> "Endpoints must be within the configured xy tolerance range (**default 1mm**) to be considered as connected."
> — [Esri, Prepare CAD for ArcGIS Indoors](https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/cad-floor-plan-drawings.html)

즉 **1mm 이내로 떨어진 끝점끼리만 연결된 것으로 간주**한다. 도면에서 눈으로는 붙어 보여도 실제로 0.5mm 벌어져 있으면 붙은 것으로 처리되지만, 2mm 벌어져 있으면 그 방은 닫히지 않아 폴리곤이 만들어지지 않는다.

### 5.3 축 2의 함정 — 문 때문에 방이 닫히지 않는다

여기에 실내 도면 특유의 문제가 하나 있다. **벽에 문이 뚫려 있으면 그 방은 위상적으로 닫히지 않는다.** 개구부만큼 벽 선이 끊겨 있으니 폴리곤화 알고리즘 입장에서는 그 방과 복도가 하나로 이어진 영역이다.

Esri는 이를 **문을 일시적으로 닫아버리는** 방식으로 해결한다.

> `OPENINGS` 컬럼: "CAD layer or layers with polylines (closed or unclosed) that represent doors **that must be shut when generating the output unit polygons**."
> `CLOSE_DOORS` 컬럼: "type a Y or N to configure whether the... tool should treat the level's doors as **closed** when generating unit features from CAD polylines."
> — [Esri, Configure CAD floor plan mappings](https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/map-floor-plans-to-indoors.html)

문틀 사이를 선으로 이어 임시로 막은 뒤 폴리곤화를 돌리는 것이다. 여기에 도면 품질이 나쁠 때를 위한 보정 파라미터도 있다.

> `Door Close Buffer`: "used to account for **poor CAD topology** — for example, line gaps between doors and walls — when the `CLOSE_DOORS` column is set to Y."
> — [Esri, Import Floorplans To Indoors Geodatabase](https://doc.esri.com/en/arcgis-pro/latest/tool-reference/indoors/import-floorplans-to-indoors-geodatabase.html)

**이 순서가 중요하다.** 문은 "먼저 닫아서 방을 만들고, 그다음 다시 열어서 Opening 피처로 뽑는" 이중 역할을 한다. 자동화 툴을 설계한다면 이 두 단계를 명시적으로 나눠야 한다.

```
문 레이어 선분
  ├─(1) 임시로 벽 개구부를 막음 → 폴리곤화 → Unit 폴리곤 확정
  └─(2) 개구부 양 끝점을 LineString으로 추출 → Opening 피처 생성
```

### 5.4 축 3 — 텍스트 앵커: "이 방의 이름이 무엇인가"

폴리곤까지 만들어도 그것은 아직 "이름 없는 닫힌 영역"이다. 도면에는 방 이름과 번호가 텍스트로 따로 그려져 있고, 이 텍스트를 어느 폴리곤에 붙일지 결정해야 한다.

기준은 **텍스트의 앵커포인트가 어느 폴리곤 안에 떨어지는가**다.

> 도구는 "uses the CAD annotation's **anchor point** to determine the associated unit feature"
> — [Esri, Configure CAD floor plan mappings](https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/map-floor-plans-to-indoors.html)

**앵커포인트(anchor point)**란 CAD 텍스트 엔티티가 가진 삽입 기준점이다. 텍스트는 화면상 일정한 넓이를 차지하지만 데이터로는 "이 좌표에서 시작하는 문자열"로 저장되며, 그 좌표가 앵커포인트다. 이 점 하나가 어느 방 폴리곤 내부에 있는지를 판정하는 **point-in-polygon** 연산으로 이름이 귀속된다.

매핑 규칙은 Annotation to Field 시트에 선언한다.

| 컬럼 | 역할 |
| --- | --- |
| `SOURCE_ANNOTATION` | 주석이 들어 있는 CAD 레이어 |
| `TARGET_FEATURE_CLASS` | 붙일 대상 피처 클래스 |
| `TARGET_FIELD_NAME` | 붙일 대상 필드 (예: `NAME`) |

Esri가 CAD 준비 단계에서 요구하는 텍스트도 이와 짝을 이룬다.

> "Room numbers or identifications that can be mapped to the `NAME` field of the Units layer"
> "Text describing the use type of a unit (for example Kitchen, Office, or Stairs)"
> — [Esri, Prepare CAD for ArcGIS Indoors](https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/cad-floor-plan-drawings.html)

두 번째 항목이 곧 **category 자동 판정의 근거**다. 도면에 "Kitchen"이라 적혀 있으면 그 폴리곤의 `category`를 그에 맞는 UNIT-CATEGORY 값으로 매핑한다. 이 category·name 필드가 최종 IMDF에서 어떤 구조로 저장되는지는 [[05) 라벨에 관하여]]에, 이 속성 부여 단계가 전체 파이프라인 어디에 위치하는지는 [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] 4절에 정리되어 있다.

이 방식의 취약점도 분명하다. 앵커포인트가 방 경계 바깥에 찍혀 있거나(작은 방이라 이름을 밖에 빼서 지시선으로 연결한 경우), 한 방에 텍스트가 여러 개 있거나, 아예 없는 경우 자동 귀속이 실패한다. 이런 케이스는 사람이 확인해야 한다.

### 5.5 자동화가 막히는 경계선

Esri 문서는 자동 매핑이 성립하지 않는 조건을 명시한다.

> "Mapping CAD handles to an existing text field requires **single, closed polyline entities** in the input CAD file to represent single polygons... Mapping CAD handles is **not supported** when a polygon in the Indoors workspace is composed of multiple objects (for example, if a unit is created by combining multiple CAD entities representing walls, windows, and doors)."
> — [Esri, Configure CAD floor plan mappings](https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/map-floor-plans-to-indoors.html)

**CAD 핸들(handle)**은 CAD 파일 안에서 각 엔티티에 부여된 고유 ID다. 원본 엔티티와 결과 폴리곤을 1:1로 추적하려면 "방 하나 = 엔티티 하나"여야 하는데, 여러 벽·문·창 선분을 합쳐 만든 폴리곤은 대응할 원본 엔티티가 하나로 특정되지 않아 추적이 끊긴다. 즉 **폴리곤화로 만들어낸 방은 원본과의 추적 연결을 잃는다.** 도면이 갱신됐을 때 변경분만 반영하는 증분 업데이트를 설계한다면 이 제약을 먼저 고려해야 한다.

---

## 6. 전체 흐름 정리

```
CAD 도면 (좌표만 있는 선분 수천 개)
  │
  ├─ [축 1] 레이어 이름으로 의미 분류
  │    A-WALL → 벽, A-DOOR → 문, A-AREA → 방 경계, ...
  │    (National CAD Standard 등 명명 규약 / Excel 매핑 테이블)
  │
  ├─ [축 2] 위상으로 면 추출
  │    ① 노딩 (모든 교차점에서 선 분할, shapely.node)
  │    ② 문 개구부 임시 폐쇄 (CLOSE_DOORS / Door Close Buffer)
  │    ③ 폴리곤화 (AreaBuilder / shapely.polygonize)
  │    ④ 실패분(Incomplete) 검토 — 오버슛·언더슛·1mm 초과 간격
  │    → 이름 없는 방 폴리곤 확정
  │
  ├─ [축 3] 텍스트 앵커포인트로 이름·용도 귀속
  │    point-in-polygon → name, category 채움
  │
  ├─ 단순화 (벽 교차부·기둥 — 스펙상 MUST)
  ├─ 문 개구부를 다시 열어 Opening LineString 추출
  ├─ 창문·가구 폐기 (IMDF에 대응 타입 없음)
  │
  ├─ 지오레퍼런싱 — 컨트롤 포인트로 만든 변환식을 전체 vertex에 적용
  │    (→ [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] 2절)
  │
  └─ IMDF 출력
       units.geojson    : Polygon (방 꼭짓점)
       openings.geojson : LineString (문 양 끝점)
       levels.geojson, footprints.geojson, ...
```

---

## 관련 링크

- [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] — 이 문서가 다루는 좌표화 단계를 포함한 전체 파이프라인
- [[지오레퍼런싱]] — 이렇게 만들어진 vertex 집합에 실제 지구 좌표를 부여하는 단계
- [[05) 라벨에 관하여]] — 5.4절에서 귀속시킨 name·category가 최종 파일에서 갖는 데이터 구조
- [[04) ArcGIS Indoors]] — 5절 자동 분류 기준의 출처가 되는 도구
- [[03) FME]] — AreaBuilder 등 폴리곤화 트랜스포머를 제공하는 도구
- [[IMDF]] — Unit·Opening을 포함한 Feature Type 전체 규격

## 미해결 질문

- Unit 경계가 중심선/면 중 무엇으로 수렴하는지를 스펙이나 Apple 문서가 **직접 권고한 문장**이 있는가 — 1.2절 결론은 두 규정의 결합 해석이며 원문 근거는 미확보.
- `Door Close Buffer`의 기본값과 실무 권장 범위는 얼마인가 — 도구 참조 페이지에서 수치 미확인.
- 앵커포인트가 방 밖에 있거나 한 방에 텍스트가 복수인 경우 Esri 도구의 폴백 동작은 무엇인가.
- FME의 IMDF 3부작 튜토리얼이 Unit 폴리곤 생성에 실제로 AreaBuilder를 쓰는지 — `support.safe.com` 403 차단으로 미확인.
- 폴리곤화로 생성한 Unit이 CAD 핸들 추적을 잃는 제약(5.5절) 아래에서, 도면 갱신 시 증분 업데이트를 어떻게 설계하는가 — 선행 사례 미확인.
