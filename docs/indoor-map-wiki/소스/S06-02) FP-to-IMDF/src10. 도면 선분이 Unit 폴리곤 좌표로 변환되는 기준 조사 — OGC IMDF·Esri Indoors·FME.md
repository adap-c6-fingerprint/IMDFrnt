---
summary: "도면의 방·문·창이 IMDF 좌표로 옮겨질 때 어떤 점이 좌표화되는지(Unit 경계 = 벽 중심선 또는 면), 문·창은 어떻게 취급되는지(Opening=LineString, 창은 Feature Type 없음), 그리고 선분 집합을 자동으로 '방'으로 묶는 기준(폴리곤화 + 레이어 매핑 + 앵커포인트 텍스트 귀속)을 OGC IMDF 스펙·Esri ArcGIS Indoors 공식 문서·FME 공식 문서로 조사"
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0), doc.esri.com/en/arcgis-pro (ArcGIS Indoors), docs.safe.com (FME AreaBuilder), shapely.readthedocs.io"
created: "2026-08-20 00:00"
updated: "2026-08-20 00:00"
---
# 도면 선분이 Unit 폴리곤 좌표로 변환되는 기준 조사

## 수집 기준

- 수집일: 2026-08-20
- 목적: `src06` 7절에서 "지오레퍼런싱은 컨트롤 포인트로 변환식을 만들고, 그 변환이 IMDF의 모든 geometry vertex에 적용된다"까지는 확인했으나, **그 vertex 집합이 애초에 어떻게 만들어지는가**는 미확인이었다. 구체적으로 (1) 사각형 방 하나가 IMDF로 갈 때 좌표화되는 점이 정확히 어디인지(벽 중심선인지 벽 면인지), (2) 문·창문의 좌표도 포함되는지, (3) 흩어진 선분 집합을 사람이 수동 지정하지 않고 자동으로 "방/문/창"으로 정의하려면 무엇을 기준으로 묶어야 하는지를 확인.
- 방법: OGC IMDF 1.0.0 공식 스펙(Unit·Opening 페이지), Esri ArcGIS Pro Indoors 공식 문서(CAD 준비 요건·Excel 매핑 구성), Safe Software FME 공식 문서(AreaBuilder), Shapely 공식 문서를 직접 조회.

## 핵심 출처

- OGC, "Unit — Indoor Mapping Data Format (1.0.0)": https://docs.ogc.org/cs/20-094/Unit/index.html
- OGC, "Opening — Indoor Mapping Data Format (1.0.0)": https://docs.ogc.org/cs/20-094/Opening/index.html
- Esri, "Prepare CAD for ArcGIS Indoors" (ArcGIS Pro): https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/cad-floor-plan-drawings.html
- Esri, "Configure CAD floor plan mappings and metadata" (ArcGIS Pro): https://doc.esri.com/en/arcgis-pro/latest/help/data/indoors/map-floor-plans-to-indoors.html
- Esri, "Import Floorplans To Indoors Geodatabase (Indoors Tools)": https://doc.esri.com/en/arcgis-pro/latest/tool-reference/indoors/import-floorplans-to-indoors-geodatabase.html
- Safe Software, "AreaBuilder" (FME 공식 트랜스포머 문서): https://docs.safe.com/fme/html/FME-Form-Documentation/FME-Transformers/Transformers/areabuilder.htm
- Shapely, "shapely.polygonize": https://shapely.readthedocs.io/en/stable/reference/shapely.polygonize.html
- Shapely, "shapely.node": https://shapely.readthedocs.io/en/stable/reference/shapely.node.html

## 1. Unit의 geometry — 좌표화되는 점의 위치 기준 (OGC IMDF 1.0.0, Unit)

- geometry 타입 규정 원문: "Unit objects **MUST** have a `"geometry"` member with a `POLYGONAL` value"
- 벽과의 관계 원문:
  - "A Unit boundary **MAY** approximate an imaginary line running down the center of a physical, vertical barrier" (벽 **중심선** 근사)
  - "a Unit boundary **MAY** follow [source data] that models the 'face' of a physical, vertical barrier" (벽 **면** 추종)
  - → 두 방식 모두 `MAY`로 허용된다. 스펙이 하나로 강제하지 않는다.
- 단순화 규정 원문: "A physical, vertical barrier **SHOULD** be [simplified]" / "The simplification of physical, vertical barriers **MUST** occur in all complex architectural scenarios" — 명시된 복잡 시나리오 예: "Multiple wall intersections", "Wall/column combinations".
- 위상 규정 원문: "[Symmetrical difference] **MUST NOT** exist: Among Units that reference the same Level" / "Between the [union] of Units and their referenced Level."
  - → Unit끼리 겹치거나 틈이 있어서는 안 되고, Unit 전체의 합집합이 Level과 정확히 일치해야 한다. 즉 **벽 두께만큼의 영역을 Unit 사이 빈 공간으로 남기는 것은 스펙 위반**이다(빈틈 = symmetrical difference).

## 2. Opening의 geometry — 문의 취급 (OGC IMDF 1.0.0, Opening)

- geometry 타입 규정 원문: "Opening objects **MUST** have a `"geometry"` member with a `LINE-STRING` value"
- properties 목록: `id`, `feature_type`, `category`(OPENING-CATEGORY), `accessibility`, `access_control`, `door`(DOOR 객체 또는 null), `name`, `alt_name`, `display_point`, `level_id`
- OPENING-CATEGORY 값 목록: `automobile`, `bicycle`, `pedestrian`, `emergencyexit`, `pedestrian.principal`, `pedestrian.transit`, `service`
  - `pedestrian` 정의: "models the presence and physical extent of an entrance with or without a physical door" — 즉 물리적 문짝의 유무와 무관하게 **통과 가능한 개구부의 물리적 범위**를 모델링한다.
  - `service` 정의: "Non-floor-to-ceiling barrier (counter/pony wall)"
- DOOR 객체 구조: `automatic`(boolean), `material`(예: `"glass"`), `type`(예: `"sliding"`)
  - → 문짝의 재질·개폐 방식은 **geometry가 아니라 properties의 속성값**으로 들어간다. 문짝 패널의 형상(호(arc)로 그려지는 스윙 궤적 등)은 좌표화 대상이 아니다.

## 3. 창문(window)의 취급

- Opening의 category 값 목록에 `window`에 해당하는 값이 없다. `service`가 "non-floor-to-ceiling barrier (counter/pony wall)"로 카운터·낮은 칸막이를 다루지만, 이는 창문이 아니라 서비스 카운터 개념이다.
- `src04`(IMDF 공식 스펙 조사)에서 확인된 Feature Type 16종 목록에도 window에 해당하는 타입은 없다.
- → **IMDF에는 창문을 표현하는 Feature Type도, Opening category 값도 존재하지 않는다.** 창문은 IMDF 최종 산출물에 좌표로 남지 않는다.
- 반면 Esri ArcGIS Indoors의 중간 데이터 모델(Details 피처 클래스)에는 창문이 들어간다(4절 참조). 즉 창문은 **중간 모델에는 있고 최종 IMDF에는 없는** 요소다.

## 4. Esri ArcGIS Indoors — CAD 준비 요건 (doc.esri.com, "Prepare CAD for ArcGIS Indoors")

**지오레퍼런싱 전제:** "Drawings must be georeferenced with projection files (`.prj`) and world files (`.wld3`) to ensure correct positioning and scaling."

**레이어 명명:** "Consistent layer naming across CAD drawings allows for a well-organized and extendable data conversion and management process." — **U.S. National CAD Standard(AEC Naming convention)** 준수를 권장한다.

**필요 정보 원문:**
- "Room numbers or identifications that can be mapped to the `NAME` field of the Units layer"
- "Text describing the use type of a unit (for example Kitchen, Office, or Stairs)"
- "Layers with closed polylines that represent the level footprint" (또는 결합해 Level 경계를 이루는 unclosed polyline)
- "Layers with closed polylines, where each closed polyline represents a room" (또는 결합해 room을 이루는 unclosed feature)
- "Polylines representing the geometry of details. For example, you may have polylines representing **walls, doors, windows, columns, and furniture**"

**기하 품질 기준 원문:** "Endpoints must be within the configured xy tolerance range (**default 1mm**) to be considered as connected." 추가로 unit polyline은 서로 겹치면 안 되고, self-intersecting 객체는 피해야 한다.

→ 핵심: Esri 경로가 요구하는 이상적 입력은 **"방 하나 = 닫힌 폴리라인 하나"**이며, 그것이 없으면 unclosed 선분들을 결합해 만든다. 벽·문·창·기둥·가구는 별도의 "details"로 분류된다.

## 5. Esri Excel 매핑 구성 — 자동 분류의 실제 기준 (doc.esri.com, "Configure CAD floor plan mappings and metadata")

**Layer to Feature Class 시트** — CAD 레이어를 Indoors 피처 클래스에 매핑한다.

| 컬럼 | 원문 정의 |
| --- | --- |
| `UNITS` | "CAD layer or layers with **closed polylines** that define the extents of individual units, such as rooms, hallways, and other navigable spaces." |
| `UNIT_LINES` | 닫히지 않은 여러 폴리라인으로 unit이 정의되는 경우 이 컬럼을 대신 사용한다. |
| `DETAILS` | "any CAD layers with polylines (closed or unclosed) that define interior details that you want to import, such as **walls, doors, and windows**." |
| `OPENINGS` | "CAD layer or layers with polylines (closed or unclosed) that represent **doors that must be shut when generating the output unit polygons**." |

**Level Properties 시트**
- `CLOSE_DOORS`: "type a Y or N to configure whether the Import Floorplans To Indoors Geodatabase tool should treat the level's doors as **closed** when generating unit features from CAD polylines."
- `LEVEL_ID`: 시설 식별자와 "the unique identifier string for each level. Usually this is the level number."를 결합한 값.

**Import Floorplans To Indoors Geodatabase 도구 파라미터**
- `Door Close Buffer`: "used to account for **poor CAD topology** — for example, line gaps between doors and walls — when the `CLOSE_DOORS` column is set to Y."

**Annotation to Field 시트** — CAD 텍스트를 unit 속성으로 귀속시킨다.
- 3개 컬럼: `SOURCE_ANNOTATION`(주석이 있는 CAD 레이어), `TARGET_FEATURE_CLASS`(대상 피처 클래스), `TARGET_FIELD_NAME`(대상 필드).
- 귀속 규칙 원문: 도구는 "uses the CAD annotation's **anchor point** to determine the associated unit feature" — 즉 **텍스트의 앵커포인트가 어느 폴리곤 내부에 떨어지는가(point-in-polygon)**로 이름을 방에 붙인다.

**CAD 핸들 매핑 제약 원문:** "Mapping CAD handles to an existing text field requires **single, closed polyline entities** in the input CAD file to represent single polygons in the Indoors workspace. Mapping CAD handles is not supported when a polygon in the Indoors workspace is composed of multiple objects (for example, if a unit is created by combining multiple CAD entities representing **walls, windows, and doors**)."

→ 종합: Esri 경로에서 "좌표들의 집합을 방으로 정의하는 기준"은 ① **CAD 레이어 이름**(어느 레이어에 있는가) → 피처 종류 결정, ② **닫힌 폴리라인 여부** → 폴리곤 성립 여부, ③ **문 레이어를 닫아서(CLOSE_DOORS) 개구부를 메움** → 방이 닫힌 도형이 되게 함, ④ **텍스트 앵커포인트의 point-in-polygon** → 이름·용도 귀속. 네 가지다.

## 6. FME AreaBuilder — 선분에서 폴리곤을 만드는 방식 (docs.safe.com)

- 기능 원문: "Creates polygons from **topologically correct** linear features." / "creates areas wherever the linework **surrounds closed shapes**."
- 입력 요건: 입력이 clean topology를 가져야 하며, 그렇지 않으면 `Incomplete` 포트로 나간다. 대표적 문제로 교차점에서 끊기지 않은 선(features not terminating at intersections), 어긋난 노드(misaligned nodes), 오버슛/언더슛(overshoots/undershoots), 교차점 노드 누락이 열거된다.
- 스냅핑: End Point Snapping(선 끝점끼리) 또는 Vertex Snapping(정점끼리)을 지정 tolerance 내에서 수행하는 옵션이 있다. 다만 더 복잡한 경우 "the Snapper provides more snapping options"라고 안내한다.
- 닫히지 않는 선: 폴리곤을 만들지 못한 피처는 `Incomplete` 포트로, 잘못된 지오메트리 타입·정점 부족·degenerate 지오메트리는 `<Rejected>` 포트로 보낸다.

## 7. 오픈소스 경로 — Shapely (shapely.readthedocs.io)

- `shapely.polygonize`: "polygonizes an array of Geometries that contain **linework which represents the edges of a planar graph**." 입력 중 "only the constituent lines and rings will be used to create the output polygons"이며 결과는 GeometryCollection으로 반환된다.
- `shapely.polygonize_full`: polygonize와 같은 작업을 하되 폴리곤 결과뿐 아니라 "all extra outputs"(잘린 선·dangle 등)까지 반환한다 — FME의 `Incomplete` 포트에 대응하는 디버깅 경로.
- `shapely.node`: "can be used to create a fully-noded linework suitable to [be] passed as input to polygonize." — 즉 polygonize 전에 노딩(교차점 분할)이 선행되어야 한다.
- 공식 예시:
  ```python
  >>> from shapely import LineString
  >>> lines = [
  ...     LineString([(0, 0), (1, 1)]),
  ...     LineString([(0, 0), (0, 1)]),
  ...     LineString([(0, 1), (1, 1)])
  ... ]
  >>> shapely.polygonize(lines)
  <GEOMETRYCOLLECTION (POLYGON ((1 1, 0 0, 0 1, 1 1)))>
  ```

→ FME AreaBuilder와 Shapely polygonize는 **같은 알고리즘 계열**(planar graph의 닫힌 면 추출)이며, 둘 다 "노딩된 깨끗한 선형 위상"을 전제로 한다는 점이 공통이다.

## 8. 종합 판단

1. **좌표화되는 점:** 사각형 방 하나가 IMDF로 갈 때 남는 것은 그 방을 둘러싼 **Unit 폴리곤의 꼭짓점 4개**(단순화 후)다. 그 꼭짓점이 벽의 중심선 위에 놓일지 벽 면 위에 놓일지는 스펙이 둘 다 `MAY`로 허용하지만, "Unit 합집합 = Level"이라는 `MUST NOT symmetrical difference` 규정 때문에 **인접 실 사이에서는 사실상 중심선 방식으로 수렴**한다(벽 면 방식이면 벽 두께만큼 빈틈이 생기기 때문). 건물 외곽처럼 인접 Unit이 없는 경계에서는 면 방식도 성립한다. (※ 이 수렴 논리는 스펙이 명시한 문장이 아니라 두 규정을 결합한 해석 — **확인 필요**로 표시.)
2. **문:** 별도의 Opening 피처로 **LineString**(보통 시작점·끝점 2개)이 되어 좌표화된다. 방 폴리곤과는 별개의 피처이며, 문틀의 두께나 문짝 스윙 호는 좌표가 아니라 `door` properties(재질·타입·자동 여부)로 들어간다.
3. **창문:** IMDF에 대응 Feature Type도 category 값도 없어 **최종 좌표로 남지 않는다.** ArcGIS Indoors의 Details 중간 모델에는 들어가지만 IMDF export 대상이 아니다.
4. **자동 그룹화의 기준(핵심 질문):** 좌표 집합을 자동으로 "방"으로 정의하는 기준은 좌표값 자체가 아니라 **레이어(의미) + 위상(닫힘) + 텍스트 앵커(이름)** 세 축의 조합이다.
   - 무엇인지(방/벽/문/창) = **CAD 레이어 이름** (National CAD Standard 등 명명 규약)
   - 어디까지가 한 방인지 = **폴리곤화(polygonize/AreaBuilder)로 추출한 닫힌 면**, 단 문 개구부를 미리 닫아야(`CLOSE_DOORS`, `Door Close Buffer`) 방이 닫힌다
   - 이름·용도가 무엇인지 = **텍스트 앵커포인트의 point-in-polygon 귀속**

## 미해결 질문

- Unit 경계가 중심선/면 중 무엇으로 수렴하는지를 스펙이나 Apple 문서가 명시적으로 권고한 문장이 있는가 — 이번 조사에서는 두 규정의 결합 해석에 그침.
- `Door Close Buffer`의 기본값과 권장 범위는 얼마인가 — 도구 참조 페이지에서 값 미확인.
- IMDF에 창문을 남길 우회 방법(예: Detail 또는 Fixture 피처로 표현)이 실무에서 쓰이는가 — 선행 사례 미확인.
- FME의 IMDF 3부작 튜토리얼이 Unit 폴리곤 생성에 AreaBuilder를 쓰는지, 다른 트랜스포머를 쓰는지 — `support.safe.com` 403 차단으로 여전히 미확인(`src06`의 기존 미해결 질문과 동일).
