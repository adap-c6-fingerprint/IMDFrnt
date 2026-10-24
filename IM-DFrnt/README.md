# IM-DFrnt

SVG 도면에서 IMDF GeoJSON을 반자동으로 추출하는 macOS 앱의 **UI 우선 Working Prototype**.

길찾기 노드는 `IMDF 불러오기…`(⌘⇧I)에서 완성된 IMDF ZIP·폴더를 연 뒤 ⌘ Command+클릭으로 찍는다. 일반 클릭은 선택이며 ⌥ Option+핀 드래그로 연결한다. 층별 공간·UUID·위경도를 가져오므로 SVG 준비나 별도 좌표 기준점이 필요 없다. 노드 정보 편집·연결·Delete·실행취소·프로젝트 저장·클라이언트용 GeoJSON(JSON) 내보내기를 지원한다. SVG·PNG·JPG 도면을 쓰는 기존 흐름도 유지한다. [사용법과 클라이언트 파일 계약](../docs/routing/NODE_EDITOR.md).

`파일 → 새 프로젝트`(⌘N)로 빈 `.imdfrnt` 작업을 시작하고 ⌘S로 저장할 수 있다. 프로젝트 이름·저장 상태를 표시하며, 수정한 작업을 교체하거나 종료할 때 저장·저장하지 않음·취소를 확인한다. 자동 저장은 복구본을 보존한다. [프로젝트 생성·저장](../docs/projects/PROJECT_LIFECYCLE.md).

상단 **건물·층 관리**에서 공통 Level과 건물 정보를 관리한다. 전역 Footprint는 메인 화면의 `footprint` 레이어에서 그리고 편집한다. **Anchor 지정**에서 Footprint에 GPS를 설정하고 **Level · Footprint 정렬**에서 층별 대응점과 이동·회전·크기를 조정한다. [Footprint 작업 순서](../docs/projects/GLOBAL_FOOTPRINT.md), [건물과 Level 관리](../docs/projects/BUILDING_LEVELS.md).

명세: `02) Projects/06) Challenge 6/02) FP-to-IMDF 자동화/00) FP-to-IMDF 새버전 (반자동화).md`
아키텍처: 같은 폴더 `03) FTI 아키텍쳐.md`

---

## 빌드와 실행

### 1) Xcode에서 열고 실행 (권장)

이 폴더의 **`IM-DFrnt.xcodeproj`**를 더블클릭하거나 Xcode의 File → Open으로 엽니다.

1. 상단 Scheme을 **IM-DFrnt**, 실행 대상을 **My Mac**으로 선택합니다.
2. **⌘R**로 빌드·실행합니다. **⌘B**로 빌드만 할 수도 있습니다.
3. 로컬 실행용 ad-hoc 서명이 기본이므로 개발자 계정이나 Team을 설정할 필요가 없습니다.

기존 `Sources/IMDFrnt`를 직접 사용하는 macOS 앱 타깃입니다. 소스를 복사하지 않으며 이 폴더 안에 추가한 Swift 파일도 자동으로 포함합니다. Swift 6를 지원하는 Xcode와 macOS 14 이상이 필요합니다.

명령행에서도 Xcode 빌드를 실행할 수 있습니다.

```bash
xcodebuild -project IM-DFrnt.xcodeproj -scheme IM-DFrnt -configuration Debug -destination 'platform=macOS' build
```

### 2) 스크립트로 .app 번들 만들기

```bash
cd IM-DFrnt
./build-app.sh
```

`IM-DFrnt.app`이 같은 폴더에 생성됩니다. Finder에서 더블클릭하거나 `open IM-DFrnt.app`으로 실행하세요.

> 이 프로토타입은 앱을 자동으로 띄우지 않습니다. 실행은 직접 하십시오.

### 3) Swift Package로 개발 중 실행

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build && ./.build/debug/IMDFrnt
```

`xcode-select`가 CommandLineTools를 가리키고 있어도 위 `DEVELOPER_DIR` 지정으로 빌드됩니다.
`build-app.sh`는 이 처리를 스크립트 안에서 자동으로 합니다.

### 4) GUI 없이 엔진 점검

```bash
./IM-DFrnt.app/Contents/MacOS/IM-DFrnt --selftest
./run-self-tests.sh ./IM-DFrnt.app
```

파싱·기하·변환·직렬화·상호작용 계층을 점검하고 결과를 출력한 뒤 종료합니다.
UI를 눌러보지 않고 회귀를 확인하는 용도입니다. CLI 검사는 SwiftUI/NSApplication 초기화 전에 실행됩니다. 스크립트는 6종 검사의 종료 코드와 전체 로그를 남깁니다. [Self-test 재현 및 검증 범위](../docs/projects/SELF_TESTS.md)를 참고하세요.

Xcode로 빌드한 앱에도 같은 검사 스크립트를 사용할 수 있습니다. Xcode의 Products → `IM-DFrnt.app` → Show in Finder에서 앱 경로를 확인해 전달합니다.

`Package.swift`를 직접 여는 기존 방식도 유지합니다. Finder 문서 연결 정보는 두 빌드 방식이 **`Configuration/Info.plist`** 하나를 공유합니다.

---

## 화면 구성

### 메인 화면 (3분할)

| 영역 | 내용 |
|---|---|
| 좌측 사이드바 | 진행률 · 보기 모드 · **Anchor 지정 진입** · property type 12종 · 레이어 목록 |
| 중앙 캔버스 | 하위 기본 레이어(원위치 20%) + 상위 기본 레이어, 줌·팬, 선택 상단바 |
| 우측 사이드바 | feature 목록 · 인스펙터(속성 슬롯·좌표 표) · 휴지통 · 내보내기 |

### 전역 Footprint와 층 정렬

1. 메인 화면의 왼쪽 `footprint` 레이어에서 도면 위에 점을 찍어 전역 Footprint를 그립니다. GPS가 없어도 저장하며 모든 층이 같은 Feature를 공유합니다.
2. **Anchor 지정**으로 들어가 왼쪽 Footprint와 오른쪽 지도 사이의 GPS 대응점을 최소 3쌍 지정합니다. 꼭짓점·교점·변 자석을 사용하고 기존 쌍은 다시 선택해 수정합니다.
3. **Level · Footprint 정렬**에서 각 층의 Level 점과 Footprint 대응점을 2쌍 이상 지정하고 정렬합니다. 층별 표시·불투명도와 이동·회전·균일 크기를 조절합니다.

[화면별 상세 사용법과 저장/내보내기 동작](../docs/projects/GLOBAL_FOOTPRINT.md). 기존 **지도 정렬** 도구는 별도로 유지합니다. property type `anchor`는 IMDF anchor Feature로, Footprint의 GPS 대응점과 구분합니다.

---

## 조작법

| 동작 | 방법 |
|---|---|
| 개체 선택 | **fn + shift + z**를 누른 채 클릭 (명세 5항) |
| 선택 해제 | 같은 조작으로 토글, 또는 `esc` |
| 개체 이동 | 수식키 없이 드래그 (영구 저장되지 않음) |
| 원위치 | 상단바 `원위치` 또는 좌측 `모든 개체 원위치` |
| 캔버스 팬 | 빈 곳 드래그 |
| 줌 | 트랙패드 핀치 또는 좌하단 버튼 |
| 그룹화 | 개체 선택 → 상단바 `Feature로 저장` |
| 내보내기 | `⌘E` 또는 우측 하단 버튼 |

### fn 키가 안 먹을 때

`fn`은 시스템 설정(받아쓰기·이모지·F키 동작)에 선점될 수 있습니다.
캔버스 우하단 상태칩의 **`고정` 토글**을 켜면 수식키 없이 선택 모드가 유지됩니다.
현재 선택 모드 여부는 같은 칩의 초록 점으로 항상 보입니다.

키 입력은 `NSEvent.addLocalMonitorForEvents`(로컬 모니터)만 사용합니다.
전역 모니터를 쓰지 않으므로 **입력 모니터링 권한이 필요하지 않고**, 앱이 최전면일 때만 동작합니다.

---

## 구현된 것

- **SVG 파싱** — `XMLParser` + 자체 path-data 파서. `path`(M,L,H,V,C,S,Q,T,A,Z 대소문자 전부), `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon`. `<g>` transform 누적(translate/scale/rotate/matrix/skew)과 스타일 상속. 2차 베지어와 호(A)는 파싱 시점에 3차로 환산.
- **스타일 원본 보존** — stroke RGB·두께·dash를 그대로 들고 있어 `같은 속성의 벡터만 모아보기`가 동작합니다.
- **레이어** — 하위 기본(원위치 20%, 히트테스트 off, 닫기·숨기기 불가) / 상위 기본(닫기 불가) / property type / 속성 필터.
- **선택** — fn+shift+z 게이팅, 선택 시 나머지 70% opacity, 드래그·shift 다중선택 없음(명세 금지).
- **보기 모드** — `그룹화되지 않은 개체 보기`(그룹화된 것 75%), `곡선 개체만 따로 보기`(곡선 아닌 것 75%, 하위 토글 시 곡선 50%·선분화된 것 100%).
- **선분화** — 적응 de Casteljau 분할. 결과는 이어진 폴리라인이 아니라 **개별 선분 배열**이며, `SegmentationValidator`가 인접 선분의 벌어짐(gap)과 비인접 선분의 교차(crossing)를 검사합니다. 원본 개체를 대체하지 않는 파생 상태(`SegmentationStore`)라 **선분화 해제**와 **곡선 개체 단위 선택**이 가능합니다.
- **소유권** — 개체는 전 레이어 통틀어 feature 하나에만 속합니다. 충돌 시 명세 4-1) 경고창과 두 선택지(`{기존 type} 레이어로 이동` / `현재 레이어에 남기`)가 그대로 뜹니다.
- **feature 인스펙터** — `01) geojson 파일별 properties 구조.md`의 표를 그대로 옮긴 스키마. 타입 고정 컨트롤, 기본값 null, `id`는 비활성(`내보내기 시 자동 생성`), 비표준 필드 배지, 참조 필드는 일련번호 드롭다운.
- **좌표 표** — 명세 7-3-5)의 규칙(Polygon 꼭짓점 / LineString 양 끝점 / Point)대로 추출하고 위경도를 병기합니다. read-only.
- **display point** — 그룹 bounding box 밖이면 거부.
- **휴지통** — 삭제가 아니라 플래그. 복원 시 소유권 재취득을 시도하고 실패하면 사유를 알립니다.
- **Anchor 지정 화면** — 위 참조.
- **내보내기** — 차단 조건 검사 후 `NSSavePanel`. Feature id는 **RFC 4122 v4 UUID**로 발급하며, 재내보내기 시 동일 UUID를 유지하고(`MUST be retained across distinct deliveries`) 폐기된 UUID는 재사용하지 않습니다(`MUST NOT be re-assigned`).

---

## 아키텍처 문서와의 차이 (파일 합침)

프로토타입 범위에 맞춰 아래를 합쳤습니다. 타입명과 함수명은 문서를 따랐습니다.

| 아키텍처 문서 | 이 프로토타입 |
|---|---|
| `Model/VectorObject·VectorStyle·PathGeometry·LocalPoint·GeoPoint·DrawingDocument` | `Model/Geometry.swift` + `Model/VectorObject.swift` |
| `Store/` 9개 파일 | `Store/Stores.swift` 한 파일 |
| `Geometry/SegmentIntersector·GeometryClassifier` | `Geometry/VertexExtractor.swift`·`SegmentationValidator.swift`에 흡수 |
| `Export/ExportValidator·IDAssigner·FeatureSerializer·GeoJSONDocumentBuilder·GeoJSONWriter` | `Export/GeoJSONExporter.swift` + `IDAssigner`는 `Store/Stores.swift` |
| `UI/` 하위 5개 폴더 | `UI/*.swift` 평면 + `UI/Anchor/` |
| `ViewModel/` 5개 | `App/AppEnvironment.swift`에 통합 |
| `App/AppEnvironment` | 동일 (모든 Store를 `@Published` 값 타입으로 보유) |

`Resources/FeatureSchemas.json`·`CategoryCatalog.json`은 JSON 대신 `Model/PropertySchema.swift`의 Swift 리터럴로 넣었습니다. 표를 고칠 때 이 파일 한 곳만 고치면 됩니다.

`SimilarityTransform`은 문서대로 폐기하고 `GeoAffineTransform`(어파인, 3쌍)을 주 변환으로 씁니다.
다만 2쌍 겹쳐보기 미리보기를 위해 `GeoAffineTransform.fitSimilarity(from:)`를 **미리보기 전용**으로 추가했습니다.

---

## 미구현으로 남긴 것과 이유

| 항목 | 이유 |
|---|---|
| **프로젝트 파일 자동 저장/불러오기 (`.imdfrnt`)** | 프로젝트마다 `새 도면_YYMMDD_HHmm.imdfrnt` 파일 하나에 자동 저장하고, `.imdfrnt 불러오기…`로 자동 저장 폴더에서 다시 엽니다. 직접 저장 기능은 없습니다. 임시 개체 이동 좌표·화면 선택·실행취소 기록은 파일에 저장하지 않습니다. |
| **속성 필터 레이어의 부분 표시** | 레이어 생성과 목록 표시까지만 구현했고, 캔버스가 그 레이어의 부분집합만 그리는 렌더링은 미구현입니다. 현재는 필터 조건이 무엇인지 레이어 이름으로만 보입니다. |
| **CSS `<style>` 블록 셀렉터** | 인라인 `style` 속성과 프레젠테이션 속성만 해석합니다. 아키텍처 문서 0.2절의 미해결 항목 그대로. |
| **`manifest.json` 생성** | property type 목록에 `manifest`가 있으나 피처 파일이 아니라 세트 메타데이터라, 개별 geojson 내보내기와 흐름이 다릅니다. |
| **`category` 허용값 전수 대조** | `PropertySchema.categoryOptions`의 값은 대표값만 넣었습니다. IMDF 스펙 CATEGORY 열거형과 전량 대조되지 않았습니다(아키텍처 0.2절). |
| **선분화 tolerance 기본값 근거** | 0.6으로 두고 슬라이더(0.1–4)로 조절하게 했습니다. 도면 축척별 적정값은 미검증. |
| **흩어진 선분의 폴리곤 링 정렬** | 닫힌 단일 경로는 경로 순서를 그대로 쓰지만, 흩어진 선분 집합에서 뽑은 점은 중심 기준 각도로 정렬합니다. 오목 다각형에서 링 순서가 틀어질 수 있습니다. |

---

## 파일 구성

```
IM-DFrnt/
├── IM-DFrnt.xcodeproj/              Xcode macOS 앱 타깃·공유 Scheme
├── Configuration/Info.plist         두 빌드 방식이 공유하는 앱·문서 연결 정보
├── Package.swift
├── build-app.sh                     .app 번들 생성
├── README.md
├── Sample/sample-floorplan.svg      테스트 도면 (개체 27개, 곡선 5개)
└── Sources/IMDFrnt/
    ├── App/         IMDFrntApp · AppEnvironment · RootView · SelfTest
    ├── SVG/         SVGParser · PathDataParser · StyleResolver · SampleFloorplan
    ├── Model/       Geometry · VectorObject · IMDFFeatureType · PropertySchema
    │                FeatureGroup · EditorLayer · Segmentation · AnchorPair
    ├── Store/       Stores.swift (소유권·feature·레이어·선택·선분화·이동·Anchor·일련번호·UUID)
    ├── Geometry/    CurveFlattener · SegmentationValidator · VertexExtractor · HitTester
    ├── Georeference/ AffineTransform · ResidualCalculator · Georeferencer
    ├── Export/      GeoJSONExporter (+ ExportValidator)
    └── UI/          CanvasView · SelectionToolbar · LeftSidebar · RightSidebar
                     SelectModifierMonitor · Anchor/AnchorScreen · Anchor/AnchorDrawingPane
```

## 샘플 도면

`Sample/sample-floorplan.svg` — 1000×700 viewBox, 개체 27개.

- 벽 5개(`path`), 방 5개 + 집기 2개(`rect`), 문 6개(`line`), 다각형 집기 1개, 치수선 3개(`polyline`)
- 곡선 5개: `circle`, `ellipse`, 3차 베지어 `path`, 호(`A`) `path`, `Q`+`T` `path` — 선분화 시험용
- 문 6개는 stroke·두께가 동일해 `같은 속성의 벡터만 모아보기` 시험에 쓸 수 있습니다

앱 안에서는 좌측 `샘플` 버튼 또는 `⌘⇧O`로 엽니다. SVG 내용은 실행 파일에 함께 넣어 두어
리소스 번들 경로에 의존하지 않습니다.

## 캔버스 조작 (2026-08-24 추가)

### 확대·축소 — 커서가 초점

| 입력 | 동작 |
|---|---|
| 마우스 휠 | 커서 위치를 초점으로 확대/축소 |
| 트랙패드 두 손가락 | 상하좌우 이동(팬) |
| 트랙패드 핀치 | 커서 위치를 초점으로 확대/축소 |
| ⌘ + 스크롤 | 입력 장치와 무관하게 확대/축소 |
| 화면 좌하단 ± 버튼 | 캔버스 중앙을 초점으로 확대/축소 |

커서 아래에 있던 도면 지점이 확대 후에도 그 자리에 남는다. 화면 중앙 고정 확대와 달리 보고 있던 곳을 놓치지 않는다.

구현은 `UI/ZoomEventMonitor.swift`. SwiftUI `MagnificationGesture`는 확대 중심 좌표를 주지 않아 커서 기준 확대를 만들 수 없어서, `NSEvent` 로컬 모니터로 `.scrollWheel`·`.magnify`를 받아 `locationInWindow`를 함께 쓴다. **로컬 모니터이므로 입력 모니터링 권한이 필요 없고**, 앱이 최전면일 때만 동작한다. 캔버스 영역 밖 이벤트는 그대로 흘려보내 사이드바 스크롤을 막지 않는다.

메인 캔버스와 Anchor 지정 화면의 도면 패널 양쪽에 적용된다. Anchor 화면은 건물 모서리처럼 좁은 지점을 찍어야 해서 최대 배율이 더 높다(20배 / 메인 8배).

### 배경 밝게·어둡게

화면 좌하단 줌 컨트롤 묶음 안의 `밝게`/`어둡게` 버튼으로 전환한다.

단순 색 교체가 아니다. **검은 선으로 그려진 도면을 어두운 배경에서 열면 아무것도 보이지 않으므로**, `CanvasBackground.resolve(_:)`가 선 색의 상대 휘도를 배경 휘도와 비교해 차이가 0.28 미만이면 반전시킨다. 채움 색(`resolveFill`)도 같은 규칙을 탄다 — 흰색으로 칠해진 방이 밝은 배경에서, 검게 칠해진 방이 어두운 배경에서 사라지는 것을 막는다. SVG 원본 색은 보존되고 표시할 때만 반전하므로 '같은 속성 모아보기'의 비교 기준에는 영향이 없다.

#### 캔버스 위 요소는 시스템 색을 쓰지 않는다

`Color.secondary`·`.primary`·`.accentColor`는 캔버스 배경이 아니라 **시스템 외관**을 따라간다. 시스템이 라이트인데 캔버스만 어둡게 두면 이 색들이 배경에 묻힌다. 그래서 캔버스 위에 그려지는 요소는 전부 `CanvasBackground`의 전용 색을 쓴다.

| 요소 | 프로퍼티 | 이전 |
|---|---|---|
| 기본 선(stroke 미지정) | `defaultStroke` | `.primary` |
| 비활성(타 type 소유) 개체 | `disabledStroke` | `.secondary` |
| 선택 강조·바운딩박스 | `selection` | `.accentColor` |
| 하위 기본 레이어(고스트) | `ghostStroke` | `.gray` |
| Anchor 마커 / 이상치 / 대기 | `marker(.normal/.outlier/.pending)` | `.blue` / `.red` / `.purple` |
| display point | `marker(.displayPoint)` | `.orange` |
| 빈 화면 안내 문구·아이콘 | `primaryText` / `mutedText` | `.secondary` |

머터리얼 배경을 깐 UI(줌 컨트롤, 선택 상단바, 모드 칩, Anchor 화면 헤더)는 캔버스가 아니라 앱 크롬이므로 시스템 외관을 그대로 따른다.

고스트 레이어는 명세가 20% opacity를 요구해서 특히 묻히기 쉽다. 그 20%를 통과하고도 배경과 구분되도록 색을 배경 반대쪽으로 충분히 밀어뒀다(밝은 배경 0.25 / 어두운 배경 0.85).

#### 대비 자동 검증

`--selftest`가 두 배경 × 14개 항목의 휘도차를 실제로 계산해 검사한다. 극단 색(검정·흰색)과 배경에 가까운 회색이 반전 규칙을 타는지, 나머지 요소가 최소 대비를 확보하는지 확인한다. 색을 바꾸다 대비가 무너지면 여기서 잡힌다.
