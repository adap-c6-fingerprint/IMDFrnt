import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 개체 하나를 그릴 때 필요한 파생 상태. Store는 원자적 사실만 들고,
/// "지금 이 개체가 회색인가"는 전부 여기서 계산한다.
struct ObjectRenderState {
    var opacity: Double
    var isVisible: Bool
    var isSelected: Bool
    var isDisabled: Bool
    // 다른 property type이 이미 소유한 개체 — 선택 불가
    var isBorrowed: Bool = false
    // 지금 레이어가 opening에서 빌려 쓰는 개체(명세 10-2-2). 소유하지 않았다는 것을 색으로 알린다.
    var isHighlighted: Bool = false
    // 강조 중인 feature(펼친 카드·눈으로 띄운 것)의 구성원.
    var isTaggedHere: Bool = false
    // 지금 레이어(property type)에서 태깅한 개체.
    var isTaggedOtherLayer: Bool = false
    // 다른 레이어(property type)에서 태깅한 개체. 옅은 초록으로 그린다 — 고를 수 없는 것(`isDisabled`)은 그대로다.
}

/// 캔버스 배경 전환. 선 색이 배경에 묻히면 자동으로 반전시킨다.
enum MarkerRole { case normal, outlier, pending, displayPoint }

enum CanvasBackground: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }

    var label: String { self == .light ? "밝게" : "어둡게" }
    var symbol: String { self == .light ? "sun.max" : "moon" }

    var fill: Color { self == .light ? Color(white: 0.98) : Color(white: 0.11) }
    /// 배경 자체의 상대 휘도. 선 색이 배경에 묻히는지 판정하는 기준값이다.
    var luminance: Double { self == .light ? 0.98 : 0.11 }

    /// stroke가 지정되지 않은 개체에 쓰는 기본 선 색.
    var defaultStroke: Color { self == .light ? Color(white: 0.1) : Color(white: 0.92) }

    /// 하위 기본 레이어(원위치 고스트). 명세가 50% opacity를 요구하므로(2026-08-25 사노 요청,
    /// 20%→50%), 그 옅기를 통과하고도 배경과 구분되도록 배경 반대쪽으로 충분히 밀어둔다.
    var ghostStroke: Color { self == .light ? Color(white: 0.25) : Color(white: 0.85) }

    /// 다른 property type이 이미 소유해 선택할 수 없는 개체.
    /// `Color.secondary`는 캔버스 배경이 아니라 시스템 외관을 따라가므로 쓰면 안 된다
    /// — 시스템이 라이트인데 캔버스를 어둡게 두면 회색이 배경에 묻힌다.
    var disabledStroke: Color { self == .light ? Color(white: 0.62) : Color(white: 0.5) }


    /// 선택 강조. 시스템 강조색이 배경에 묻힐 수 있어 밝기를 배경에 맞춰 보정한다.
    var selection: Color { self == .light ? Color(red: 0.0, green: 0.42, blue: 0.9)
                                          : Color(red: 0.42, green: 0.72, blue: 1.0) }

    /// 보조 개체로 제외된 개체. 비활성(회색)과 구분되어야 한다 —
    /// 비활성은 "다른 type이 이미 가져갔다", 제외는 "아무도 안 가져간다"로 뜻이 정반대다.
    var excludedStroke: Color { self == .light ? Color(red: 0.78, green: 0.44, blue: 0.05)
                                               : Color(red: 1.00, green: 0.72, blue: 0.30) }

    /// ✅ 2026-08-30 신설 — '똑같이 생긴 개체 모두 지정'을 누르면 함께 빠질 쌍둥이(요청 2-1).
    ///
    /// **왜 보라인가.** 이 창에는 이미 파랑(직접 고른 것)과 주황(이미 제외된 것)이 있다.
    /// 쌍둥이는 그 둘 중 어느 쪽도 아닌 세 번째 상태 — "아직 아무 일도 안 일어났지만,
    /// 버튼을 누르면 빠질 것" — 이라 제 색이 있어야 한다. 보라는 앱의 다른 곳에서도
    /// `marker(.pending)`(아직 확정되지 않은 Anchor)에 쓰는 색이라 뜻이 어긋나지 않는다.
    var twinStroke: Color { self == .light ? Color(red: 0.52, green: 0.20, blue: 0.75)
                                           : Color(red: 0.78, green: 0.56, blue: 1.00) }

    /// 겹침 윤곽. 사용자가 색을 #FF00D9로 지정했으므로 `resolve(_:)`의 자동 반전을 태우지 않는다
    /// — 반전시키면 지정색이 아닌 다른 색이 되어버린다. 밝은/어두운 배경 어느 쪽에도
    /// 도면 선색(무채색)과 겹치지 않는 채도라 대비 대신 색상으로 구분된다.
    var overlapOutline: Color { Color(.sRGB, red: 1.0, green: 0.0, blue: 0.851, opacity: 1) }

    // MARK: 상단바 (명세 디버깅 10번)
    //
    // 상단바는 **도면 위에 뜬 요소**라 캔버스 배경을 따라야 한다.
    // 전에는 `.regularMaterial` + `.primary`로 시스템 외관을 따라가게 뒀는데,
    // 머터리얼은 반투명이라 뒤에 깔린 캔버스 색을 그대로 빨아들인다.
    // 시스템이 어두운데 캔버스를 밝게 두면 **흰 글씨가 흰 카드 위에** 얹혀 사라진다 —
    // 그게 "흰색 배경에서 버튼이 안 보인다"의 진짜 원인이다.
    // 그래서 카드도 글자도 불투명하게, 캔버스 배경 하나에서만 뽑는다.

    /// 상단바 카드의 바탕. 불투명이라 뒤 도면이 비쳐 색이 흔들리지 않는다.
    var toolbarFill: Color { self == .light ? Color(white: 0.90) : Color(white: 0.24) }

    /// 상단바 글자·아이콘. `toolbarFill`과 짝이라 대비가 항상 보장된다.
    var toolbarForeground: Color { self == .light ? Color(white: 0.10) : Color(white: 0.98) }

    /// 카드 테두리. 바탕과 캔버스의 휘도차가 작아도 카드 경계가 보이게 한다.
    var toolbarStroke: Color { self == .light ? Color(white: 0.66) : Color(white: 0.44) }

    /// Anchor 마커 등 의미색. 어두운 배경에서는 한 단계 밝은 값을 쓴다.
    func marker(_ role: MarkerRole) -> Color {
        switch (role, self) {
        case (.normal, .light):  return Color(red: 0.10, green: 0.36, blue: 0.85)
        case (.normal, .dark):   return Color(red: 0.45, green: 0.72, blue: 1.00)
        case (.outlier, .light): return Color(red: 0.80, green: 0.15, blue: 0.15)
        case (.outlier, .dark):  return Color(red: 1.00, green: 0.45, blue: 0.42)
        case (.pending, .light): return Color(red: 0.52, green: 0.20, blue: 0.75)
        case (.pending, .dark):  return Color(red: 0.78, green: 0.56, blue: 1.00)
        case (.displayPoint, .light): return Color(red: 0.85, green: 0.45, blue: 0.0)
        case (.displayPoint, .dark):  return Color(red: 1.00, green: 0.68, blue: 0.25)
        }
    }

    /// SVG 채움 색도 선과 같은 규칙으로 반전한다.
    /// 흰색으로 칠해진 방이 밝은 배경에서, 검게 칠해진 방이 어두운 배경에서 사라지는 것을 막는다.
    func resolveFill(_ color: RGBAColor) -> Color { resolve(color) }

    /// SVG 원본 색을 그대로 쓰되, 배경과 휘도가 너무 가까워 보이지 않으면 반전한다.
    /// 검은 선 도면을 어두운 배경에서 열면 아무것도 안 보이는 문제를 막는다.
    func resolve(_ color: RGBAColor?) -> Color {
        guard let c = color else { return defaultStroke }
        let lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        if abs(lum - luminance) < 0.28 {
            return Color(.sRGB, red: 1 - c.r, green: 1 - c.g, blue: 1 - c.b, opacity: c.a)
        }
        return c.swiftUI
    }
}

/// 강조 여부 → 표시 배율. 뷰에서 떼어낸 이유는 검증 때문이다 —
/// 명세의 75% 수치가 뷰 안에 박혀 있으면 `--selftest`가 확인할 방법이 없다.
enum AuxiliaryOpacity {
    static let focused: Double = 1.0
    static let dimmed: Double = 0.75

    static func value(for id: VectorObjectID, highlighted: Set<VectorObjectID>?) -> Double {
        guard let highlighted else { return focused }
        // 강조가 꺼져 있으면 흐릴 대상 자체가 없다. 이때 전부 0.75로 만들면
        // "기준이 되는 100%"가 화면에서 사라져 대비가 의미를 잃는다.
        return highlighted.contains(id) ? focused : dimmed
    }
}

@MainActor
final class AppEnvironment: ObservableObject {

    @Published var buildingProject = BuildingProject()
    @Published var showBuildingManager = false
    var routing: RoutingGraph {
        get { projectContents.routingGraph }
        set {
            var project = projectContents
            project.applyRouting(newValue)
            buildingProject = project
            if let floor = newValue.floor(routingFloorID) { anchors = floor.anchors }
        }
    }
    @Published var showRoutingScreen = false
    @Published var routingFloorID: UUID?
    @Published var routingSelectedNodeID: UUID?
    @Published var routingSelectedEdgeID: UUID?
    @Published var routingTool: RoutingTool = .place
    @Published var routingConnectStart: UUID?
    @Published var routingConnectionDrag: RoutingConnectionDrag?
    @Published var routingPendingAnchor: LocalPoint?
    @Published var routingExportError: String?
    /// 출입구 노드 자동 배치의 마지막 결과(제외 사유 표시용, #69). 저장하지 않는다.
    @Published var lastEntrancePlacement: EntrancePlacementPlan?
    @Published var pendingDeletion: DeletionRequest?
    var routingContextMenuIsOpen = false
    @Published var isImportingIMDF = false
    let levelDrawingCache = LevelDrawingCache()
    var levelDrawingTask: Task<Void, Never>?
    var levelPrefetchTask: Task<Void, Never>?
    var levelDrawingRequest = UUID()
    @Published var loadingLevelID: UUID?
    @Published var drawingLoadError: String?
    var isInstallingLevelDrawing = false
    @Published var canvasReferences: PreparedCanvasReferences?
    var canvasReferenceCache: [UUID: PreparedCanvasReferences] = [:]
    var canvasReferenceTask: Task<Void, Never>?

    // MARK: 문서와 상태

    @Published var document: DrawingDocument? {
        didSet { geometryRevision &+= 1; if !isInstallingLevelDrawing { rebuildDocumentIndexes() } }
    }

    /// 도면·feature·선분화가 바뀔 때마다 오르는 번호. 화면을 그릴 때마다 읽는 캐시가 이 번호로 유효한지 먼저 본다.
    /// 번호가 같으면 링·선분 전체를 다시 모아 비교하지 않는다 — 면 하나마다 그 비교를 하던 것이 버벅임의 원인이었다.
    private(set) var geometryRevision = 0

    /// 개체별 파생 데이터(Path · 선분 · 경계 상자). 제안 2.
    let renderCache = RenderCacheStore()

    /// 도면 대부분이 보일 때 캔버스가 묶어 그리는 경로(`CanvasBatches`). 표시 상태·도형이 바뀌면 다음 프레임에 다시 만든다.
    let canvasBatchStore = CanvasBatchStore()

    /// 드래그 중 이동량. **`@Published`가 아니다** — 이 객체가 바뀌어도 `AppEnvironment`는
    /// 알림을 보내지 않으므로, 좌우 사이드바처럼 이동과 무관한 화면이 다시 그려지지 않는다(제안 4).
    let moves = MoveSession()

    /// 속성 필터 레이어의 후보를 즉시 찾기 위한 색인(제안 6). 복사가 아니라 색인이다 —
    /// 레이어가 개체 목록을 한 벌씩 들고 있으면 태깅할 때마다 그 전부를 고쳐야 한다.
    private(set) var objectIDsByAttributeKey: [String: [VectorObjectID]] = [:]

    /// 이 속성으로 필터 레이어를 만들면 몇 개가 걸리는지. 색인 조회 한 번으로 끝난다 —
    /// 이전에는 이런 물음마다 도면 전체의 `attributeKey`를 다시 비교해야 했다.
    func objectsMatchingAttribute(_ key: String) -> [VectorObjectID] {
        objectIDsByAttributeKey[key] ?? []
    }

    /// 클릭·사각형 선택·겹침 후보를 도면 전체가 아니라 해당 칸에서만 찾기 위한 격자(제안 5).
    private(set) var spatialIndex = SpatialIndex()

    let autosaveFolderOverride: URL?
    let projectDefaults: UserDefaults

    init(autosaveFolder: URL? = nil, projectDefaults: UserDefaults = .standard) {
        autosaveFolderOverride = autosaveFolder
        self.projectDefaults = projectDefaults
        moves.onSettled = { [weak self] in self?.objectWillChange.send() }
        // 드래그가 끝난 시점에 한 번만 환경 전체에 알린다 — `도구` 메뉴의 '모든 개체 원위치'
        // 활성 여부처럼 `AppEnvironment`만 보는 화면을 위해서다.
    }
    @Published var layers = LayerStore() { didSet { invalidateRenderStates() } }
    @Published var features = FeatureStore() {
        didSet {
            if let changed = FeatureStore.propertyOnlyChanges(from: oldValue, to: features) {
                refreshRenderStates(owners: changed)
                return
            }
            // 속성(category·name 등)만 바뀌었으면 도형·점·면·진행률은 그대로다(2026-10-19 이름표 편집 창 렉).
            // 예전에는 글자 하나마다 아래를 전부 돌아, 진행률 다시 세기 하나로 포스텍 도서관에서 한 글자 300 ms였다.
            // category는 필터 통과 여부를 바꾸므로 그 feature의 구성원 개체만 다시 판정한다.
            geometryRevision &+= 1
            invalidateRenderStates(); refreshOverlap(); refreshOpenRingGaps()
            scheduleDerivedGeometryRefresh()
            // 저장된 opening의 선이 면을 닫는 선분이라 면이 달라질 수 있다(#21). 열쇠가 같으면 바로 돌아온다.
            refreshPointProgress()
        }
    }
    @Published var ownership = OwnershipRegistry() { didSet { invalidateRenderStates(); refreshPointProgress() } }
    @Published var selection = SelectionStore() {
        didSet {
            invalidateRenderStates()
            refreshOverlap()
            if selection.isEmpty, marqueeSubtracts { marqueeSubtracts = false }
            // ✅ 2026-08-30 — 선택이 비면 상단바가 사라진다. 빼기 모드를 켜 둔 채로 두면
            // 켜져 있는데 끌 버튼이 없는 상태가 된다(아래 `auxiliarySelection`과 같은 함정).
        }
    }
    @Published var segmentation = SegmentationStore() {
        didSet {
            geometryRevision &+= 1
            invalidateSegmentationCaches(since: oldValue); refreshOverlap(); refreshOpenRingGaps()
            scheduleDerivedGeometryRefresh()
        }
    }
    @Published var auxiliary = AuxiliaryStore() {
        didSet {
            invalidateRenderStates()
            refreshOverlap()
            if auxiliary != oldValue, !showAuxiliaryScreen { scheduleDerivedGeometryRefresh() }
            // 보조 개체를 빼면 그 선분이 이루던 면과 점이 없어진다. 다시 세지 않으면 화면과 실제가 어긋난다.
            // **계산은 백그라운드에서 한다(#21).** 예전에는 여기서 면 찾기를 메인 스레드로 돌려
            // 폴리곤 레이어에서 제외를 바꿀 때마다 앱이 멈췄다(`04) 엔진 디버깅.md` 3장).
            // 보조 개체 제외 창 안에서는 미룬다 — 클릭마다 다시 셀 이유가 없다. 창을 닫을 때 한 번 센다.
        }
    }
    @Published var doorClosures = DoorClosureStore() {
        didSet { refreshOpenRingGaps(); scheduleDerivedGeometryRefresh(); refreshPointProgress() }
        // 임시 문 자리 안의 문짝·호도 진행률의 '저장'에 들어간다(`pointCoveredObjects`).
    }
    /// '문 임시로 닫기'로 만들어 둔, 아직 Openings 레이어에 반영하지 않은 문(신기능 3항).
    @Published var openingGate = OpeningGateStore()
    @Published var borrow = BorrowRegistry() {
        didSet { invalidateRenderStates(); refreshOpenRingGaps() }
    }
    @Published var anchors = AnchorStore() {
        didSet { if !isInstallingLevelDrawing { refreshCanvasReferences() } }
    }
    @Published var serials = SerialNumberAllocator()
    @Published var ids = IDAssigner()
    @Published var mode: InteractionMode = .idle { didSet { invalidateRenderStates() } }

    /// ✅ 2026-08-30 신설 — 드래그 사각형이 '빼기'로 동작하는가(2026-08-30 요청 1-2).
    ///
    /// **왜 토글인가.** 클릭은 뒤집기(토글)라 선택 해제가 되지만, 드래그 사각형은 모든 화면에서
    /// 더하기 전용이었다 — `formUnion`만 하고 `subtract`를 하지 않았다. 드래그를 클릭처럼
    /// 뒤집기로 바꾸면 수십 개가 한꺼번에 뒤집혀 결과를 예측할 수 없고(신기능 5-4 3번에서
    /// 이미 거부한 방식), 별도 수식키를 쓰면 보조 개체 창의 ⌥드래그(화면 이동)와 부딪힌다.
    /// 그래서 **상단바에 모드를 두고, 지금 드래그가 무엇을 하는지 화면에 드러낸다.**
    ///
    /// 폴리곤 면 선택 화면은 이 값을 쓰지 않는다 — 그 화면의 포함/제외 모드가 이미 같은 일을 한다.
    @Published var marqueeSubtracts = false

    // MARK: 입력

    @Published var selectModifierDown = false
    // fn+shift+z 물리 키 상태
    @Published var forceSelectMode = false

    @Published var showLeftSidebar = true
    @Published var showRightSidebar = true
    @Published var leftSidebarWidth: CGFloat = 268
    @Published var rightSidebarWidth: CGFloat = 360
    @Published var auxiliarySidebarWidth: CGFloat = 320
    @Published var doorSidebarWidth: CGFloat = 320

    // MARK: 사이드바 항목 접기 (2026-08-25, "모두 접기" 요청)

    @Published var collapsedSections: Set<String> = []
    /// 접어 둔 사이드바 항목. **"지금 화면을 어떻게 보고 있는가"이지 작업 결과가 아니다** —
    /// 사이드바 폭과 같은 이유로 `ProjectFile`에도 `EditorSnapshot`에도 넣지 않는다.
    /// 넣으면 cmd+z 한 번에 항목이 접혔다 펴지고, 남의 파일을 열 때 남의 화면 상태가 따라온다.

    func isSectionCollapsed(_ id: SidebarSectionID) -> Bool {
        collapsedSections.contains(id.rawValue)
    }

    func toggleSection(_ id: SidebarSectionID) {
        if collapsedSections.contains(id.rawValue) { collapsedSections.remove(id.rawValue) }
        else { collapsedSections.insert(id.rawValue) }
    }

    func collapseSections(_ ids: [SidebarSectionID]) {
        collapsedSections.formUnion(ids.map(\.rawValue))
    }

    func expandSections(_ ids: [SidebarSectionID]) {
        collapsedSections.subtract(ids.map(\.rawValue))
    }

    /// '모두 접기'가 실제로 부르는 것. 사이드바마다 **접을 것이 섹션만이 아니다** —
    /// 우측 사이드바에서 자리를 가장 많이 차지하는 것은 펼쳐 놓은 feature 카드이고,
    /// 그것들은 섹션이 아니라 `expandedFeatures`로 관리된다.
    /// 이 버튼은 **카드마다 달린 개별 토글을 한꺼번에 움직이는 것**이지,
    /// 카드 전부를 감싸는 상위 트리를 접는 것이 아니다(2026-08-26 요청).
    func collapseAllSections(in owner: SidebarSectionID.Owner) {
        collapseSections(SidebarSectionID.all(in: owner))
        if owner == .right { collapseAllFeatures() }
    }

    func expandAllSections(in owner: SidebarSectionID.Owner) {
        expandSections(SidebarSectionID.all(in: owner))
        if owner == .right { expandAllFeatures() }
        // 카드를 여러 개 펼 수 있게 된 뒤로 '모두 펼치기'가 뜻을 갖는다.
        // 이전에는 한 번에 하나만 펼 수 있어 어느 것을 골라야 할지 정할 근거가 없었다.
    }

    /// 그 사이드바의 항목이 **하나도 남김없이** 접혀 있는가.
    /// 버튼이 '모두 펼치기'로 바뀌는 조건이다 — 하나라도 펼쳐져 있으면 아직 접을 것이 남았다.
    func areAllSectionsCollapsed(in owner: SidebarSectionID.Owner) -> Bool {
        let ids = SidebarSectionID.all(in: owner)
        guard !ids.isEmpty, ids.allSatisfy({ isSectionCollapsed($0) }) else { return false }
        // 우측은 섹션(휴지통)과 카드를 함께 본다. 아래 줄이 카드 몫이다.
        if owner == .right, hasExpandedFeature { return false }
        // 카드 하나가 펼쳐져 있으면 아직 접을 것이 남았다.
        return true
    }
    /// 보조 개체 제외 창의 사이드바 폭. 메인과 따로 두는 이유는 담는 내용이 다르기 때문이다 —
    /// 그쪽은 feature 인스펙터, 이쪽은 쌍둥이 그룹 목록이라 편한 폭이 서로 다르다.

    /// 층별 도면 표시 회전(90° 단위). 층 도면마다 놓인 방향이 달라 층마다 따로 기억한다(2026-10-19 요청).
    /// 층이 없는 단일 도면은 `nil` 열쇠를 쓴다. 화면 상태라 프로젝트 파일에는 저장하지 않는다.
    @Published var canvasRotationByLevel: [UUID?: Int] = [:]

    var canvasRotation: Int {
        get { canvasRotationByLevel[routingFloorID] ?? 0 }
        set { canvasRotationByLevel[routingFloorID] = newValue == 0 ? nil : newValue }
    }
    /// 지금 층의 도면 표시 회전. 표시 전용이며 도면 좌표는 바뀌지 않는다 —
    /// Anchor 쌍과 추출 좌표가 회전에 영향받으면 안 되기 때문이다.

    @Published var canvasBackground: CanvasBackground = .light
    /// 도면 배경. CAD SVG는 대개 검은 선이라 밝은 배경이 기본이지만,
    /// 흰 선으로 그려진 도면이나 장시간 작업에는 어두운 배경이 낫다.
    // fn이 OS에 가로채질 때를 위한 화면 토글

    func rotateCanvas(_ quarterTurns: Int) {
        canvasRotation = ((canvasRotation + quarterTurns) % 4 + 4) % 4
    }

    var rotationDegrees: Double { Double(canvasRotation) * 90 }

    var isCurvedOnlyMode: Bool {
        if case .curvedOnly = mode { return true }
        return false
    }

    /// 보기 모드를 바꾼다. **모드를 나갈 때 선택을 비운다.**
    /// 곡선 창의 선택은 소유권을 무시하고 이루어지므로, 그대로 들고 나가면
    /// 남의 개체를 고른 채 'Feature로 저장'을 누를 수 있다(저장은 실패하지만 이유가 안 보인다).
    func setMode(_ new: InteractionMode) {
        guard new != mode else { return }
        let leavingCurved = isCurvedOnlyMode
        perform("보기 모드") {
            mode = new
            if leavingCurved { selection.clear() }
        }
    }

    var isSelectModeActive: Bool {
        (selectModifierDown || forceSelectMode || isObjectWorkMode) && !mode.blocksSelection
        // 선 단위에서는 키를 누르지 않아도 클릭·드래그가 개체를 고른다.
    }

    // MARK: UI 상태

    /// 펼쳐 놓은 feature 카드들. **여러 개를 동시에 펼 수 있다**(2026-08-26 요청).
    /// 이전에는 한 칸(`FeatureGroupID?`)이라 카드가 늘 하나만 펼쳐졌고, 그래서 우측 사이드바가
    /// 카드 전부를 감싸는 최상위 트리(`FEATURES` 섹션) 하나로 접혔다 — 사용자가 원한 것은
    /// **카드마다 따로 접고 펴되, 버튼 하나로 그 개별 토글을 한꺼번에 움직이는 것**이다.
    @Published private(set) var expandedFeatures: Set<FeatureGroupID> = [] {
        didSet { refreshRenderStates(owners: oldValue.symmetricDifference(expandedFeatures)); refreshOpenRingGaps() }
        // 펼침은 그 feature의 개체 색(강조·빌림)만 바꾼다. 도면 전체를 다시 판정하지 않는다.
    }

    /// 지금 '주로 보고 있는' 카드. 상단바의 display point 찍기처럼 **대상이 하나여야 하는**
    /// 동작이 이 값을 쓴다. 여러 개가 펼쳐져 있을 때 무엇을 겨냥하는지 모호해지면 안 된다.
    @Published private(set) var focusedFeature: FeatureGroupID?
    // 개체 표시 상태는 펼친 카드 전부(`expandedFeatures`)를 보고, 이 값은 보지 않는다.

    /// 기존 호출부를 위한 창구. 대입하면 그 하나만 펼친 상태가 된다.
    var expandedFeature: FeatureGroupID? {
        get { focusedFeature }
        set {
            expandedFeatures = newValue.map { [$0] } ?? []
            focusedFeature = newValue
        }
    }

    func isFeatureExpanded(_ id: FeatureGroupID) -> Bool { expandedFeatures.contains(id) }

    /// 캔버스에서 다른 색으로 강조할 feature인가 — 우측 사이드바에서 펼친(고른) 카드이거나
    /// '이 feature만 보이게 하기'(눈)로 띄운 것.
    func isFeatureHighlighted(_ id: FeatureGroupID) -> Bool {
        layers.isolatedFeature == id || expandedFeatures.contains(id) || hoveredFeature == id
    }

    /// 캔버스의 일련번호 태그(unit-014 등) 위에 마우스가 올라가 있는 feature. 떼면 nil이 되어 원래 색으로 돌아간다.
    @Published var hoveredFeature: FeatureGroupID? {
        didSet {
            if oldValue != hoveredFeature { refreshRenderStates(owners: Set([oldValue, hoveredFeature].compactMap { $0 })) }
        }
        // 이름표 위를 지날 때마다 바뀐다. 도면 개체 6만 개를 매번 다시 판정하면 마우스를 움직일 때마다 멈췄다.
    }

    /// 캔버스에 category·name 편집 창을 열어 달라는 요청. 창의 자리(이름표 위치)는 캔버스만 알므로
    /// 여기서는 대상만 남기고, 캔버스가 받아 창을 연 뒤 비운다.
    @Published var tagEditorRequest: FeatureGroupID?

    /// 우측 패널의 category 필터(#52). type마다 고른 category 값이고, 비어 있으면 전부 보인다.
    /// category가 null인 feature는 빈 문자열로 고른다. 화면 상태라 실행취소 대상인 `LayerStore`에 두지 않는다.
    @Published var categoryFilters: [IMDFFeatureType: Set<String>] = [:] {
        didSet {
            let changed = Set(oldValue.keys).union(categoryFilters.keys).filter { oldValue[$0] != categoryFilters[$0] }
            refreshRenderStates(owners: Set(features.features.filter { changed.contains($0.featureType) }.map(\.id)))
        }
        // 필터가 바뀐 type의 feature 구성원만 숨김 여부가 달라진다.
    }

    /// feature의 category 값. null이면 빈 문자열이다.
    static func categoryValue(of f: FeatureGroup) -> String {
        if case .string(let s) = f.value("category") { return s }
        return ""
    }

    /// feature의 name을 이름표 위에 다는 글자. ko·en이 다 있으면 category와 같은 `한국어(영어)`, 하나만 있으면 그것, 없으면 빈 문자열이다.
    static func nameText(of f: FeatureGroup) -> String {
        guard case .localized(let en, let ko) = f.value("name") else { return "" }
        let e = en.trimmingCharacters(in: .whitespaces), k = ko.trimmingCharacters(in: .whitespaces)
        if !k.isEmpty, !e.isEmpty { return "\(k)(\(e))" }
        return k.isEmpty ? e : k
    }

    /// category 필터를 통과하는가. 걸러진 feature는 카드 목록과 캔버스(도형·이름표)에서 빠진다.
    func passesCategoryFilter(_ f: FeatureGroup) -> Bool {
        guard let picked = categoryFilters[f.featureType], !picked.isEmpty else { return true }
        return picked.contains(Self.categoryValue(of: f))
    }

    /// 카드 하나의 개별 토글.
    func toggleFeatureExpansion(_ id: FeatureGroupID) {
        if expandedFeatures.contains(id) {
            expandedFeatures.remove(id)
            if focusedFeature == id { focusedFeature = expandedFeatures.first }
            // 접은 카드가 초점이었다면 남아 있는 카드로 옮긴다. 초점을 비워 두면
            // 다른 카드가 펼쳐져 있는데도 상단바의 대상별 동작이 사라진다.
        } else {
            expandedFeatures.insert(id)
            focusedFeature = id
        }
    }

    /// 카드 하나를 펼친 채로 만든다(다른 카드는 건드리지 않는다).
    func expandFeature(_ id: FeatureGroupID) {
        expandedFeatures.insert(id)
        focusedFeature = id
    }

    func collapseAllFeatures() {
        expandedFeatures = []
        focusedFeature = nil
    }

    /// 지금 열린 property type의 카드를 모두 편다(휴지통 항목은 제외).
    func expandAllFeatures() {
        guard let type = layers.activePropertyType else { return }
        let live = features.features(ofType: type)
        expandedFeatures = Set(live.map(\.id))
        focusedFeature = focusedFeature.flatMap { expandedFeatures.contains($0) ? $0 : nil }
            ?? live.first?.id
    }

    var hasExpandedFeature: Bool { !expandedFeatures.isEmpty }
    @Published var conflict: ConflictInfo?
    @Published var exportBlockers: [ExportBlocker] = []
    /// IMDF 아카이브를 막은 이유. 층 이름을 붙인 문장 목록이다.
    @Published var archiveExportBlockers: [String] = []
    /// 클라이언트용 묶음(#54)을 막은 이유. 지도·길찾기·통합 검증 문장 목록이다.
    @Published var clientDatasetBlockers: [String] = []
    @Published var banner: Banner?
    @Published var showAnchorScreen = false
    @Published var showLevelFootprintScreen = false
    /// 지도 정렬 화면(신기능 11항, #31). Anchor 화면과 같은 전체 화면 전환이다.
    @Published var showMapAlignScreen = false
    /// 지도에 그릴 층별 선 묶음. 화면 상태가 아니라 계산 캐시라 `@Published`가 아니다.
    var mapAlignPathCache: [UUID: MapAlignPathEntry] = [:]
    /// 다른 층 도면을 차례로 불러오는 작업. 새로 부르면 이전 것을 끊는다.
    var mapAlignPrepareTask: Task<Void, Never>?
    @Published var segmentationTolerance: Double = CurveFlattener.defaultTolerance
    /// 메인 캔버스에서 제외된 보조 개체의 진하기(0이면 숨김). 기본 0.4는 종전 고정값이다.
    /// 화면 취향이라 프로젝트 파일이 아니라 이 Mac에 기억한다.
    @Published var excludedAuxiliaryOpacity: Double =
        UserDefaults.standard.object(forKey: AppEnvironment.excludedOpacityKey) as? Double ?? 0.4 {
        didSet {
            invalidateRenderStates()
            UserDefaults.standard.set(excludedAuxiliaryOpacity, forKey: Self.excludedOpacityKey)
        }
    }
    static let excludedOpacityKey = "IMDFrnt.excludedAuxiliaryOpacity"

    struct Banner: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    func notify(_ text: String, isError: Bool = false) {
        banner = Banner(text: text, isError: isError)
    }

    // MARK: 지오레퍼런싱

    /// Read synchronized active-level anchors without rebuilding the project on every coordinate lookup.
    var georeferencer: Georeferencer {
        if let pairs = activeLevel?.info.footprintGeoAnchors { return Georeferencer(pairs: pairs) }
        // A first, uncommitted Footprint has no GPS yet, even if its drawing used old anchors.
        if buildingProject.sharedFootprint == nil, features.features.contains(where: { $0.featureType == .footprint }) {
            return Georeferencer(pairs: [])
        }
        return Georeferencer(pairs: anchors.pairs)
    }

    var residuals: [Double] { georeferencer.residuals(for: anchors.pairs) }

    var rms: Double { ResidualCalculator.rms(residuals) }

    var outlierIndices: Set<Int> { ResidualCalculator.outliers(residuals) }

    /// 지도 위 "도면 겹쳐보기"에 쓰는 변환.
    /// 3쌍 이상이면 확정 어파인, 2쌍이면 미리보기용 상사 변환을 쓴다.
    var overlayTransform: GeoAffineTransform? {
        if let t = try? GeoAffineTransform.fit(from: anchors.pairs) { return t }
        return GeoAffineTransform.fitSimilarity(from: anchors.pairs)
    }

    var overlayIsPreviewOnly: Bool {
        anchors.pairs.count == 2
    }

    // MARK: 문서 열기

    func resetProjectState(id: UUID = UUID()) {
        cancelLevelDrawingLoads()
        levelDrawingCache.reset()
        canvasReferenceTask?.cancel(); canvasReferenceTask = nil
        canvasReferenceCache = [:]; canvasReferences = nil
        document = nil
        loadedSVG = nil
        projectID = id
        projectURL = nil
        hasCreatedProject = true
        showProjectPicker = false
        // Finder 열기·새 프로젝트처럼 다른 경로로 프로젝트가 바뀌어도 선택 창이 남지 않게 한다.
        lastRecoveryProject = nil
        features = FeatureStore()
        ownership = OwnershipRegistry()
        selection = SelectionStore()
        segmentation = SegmentationStore()
        auxiliary = AuxiliaryStore()
        openingGate = OpeningGateStore()
        borrow = BorrowRegistry()
        doorClosures = DoorClosureStore()
        anchors = AnchorStore()
        serials = SerialNumberAllocator()
        ids = IDAssigner()
        assignment = nil
        layers = LayerStore()
        layers.bootstrap()
        categoryFilters = [:]
        buildingProject = BuildingProject()
        showBuildingManager = false
        routingFloorID = nil
        routingSelectedNodeID = nil
        routingSelectedEdgeID = nil
        routingConnectStart = nil
        routingConnectionDrag = nil
        routingPendingAnchor = nil
        routingExportError = nil
        routingTool = .place
        routingContextMenuIsOpen = false
        pendingDeletion = nil
        pendingClearSelection = nil
        conflict = nil
        exportBlockers = []
        mergeReportMessage = nil
        banner = nil
        mode = .idle
        expandedFeature = nil
        undoStack.clear()
        moves.reset(nil)
        isMoveEnabled = false
        canvasRotationByLevel = [:]
        marqueeSubtracts = false
        auxiliarySelection = []
        focusedTwinKey = nil
        showTwinsOnly = false
        faceSelection = []
        derivedTask?.cancel(); derivedTask = nil
        applyDerivedGeometry(.empty, key: nil)
        pointDraft = PointDraft()
        closedPolygonNotice = nil
        polygonWorkMode = .include
        doorDraftPoints = []
        showRoutingScreen = false
        showAnchorScreen = false
        showLevelFootprintScreen = false
        showMapAlignScreen = false
        mapAlignPathCache = [:]
        mapAlignPrepareTask?.cancel(); mapAlignPrepareTask = nil
        showDoorClosureScreen = false
        showCurvedScreen = false
        showAuxiliaryScreen = false
    }

    func openSample() {
        guard let data = SampleFloorplan.svg.data(using: .utf8) else { return }
        load(data: data, name: SampleFloorplan.name)
    }
    // **UI 경로는 전부 없앴다(명세 디버깅 12번). 지금 유일한 호출자는 `--selftest`다.**
    // 함수까지 지우지 않은 이유는 자체점검 148항목 전부가 이 도면을 입력으로 쓰기 때문이다.
    // 사용자가 여는 경로가 하나도 없으므로 앱에서는 샘플이 열리지 않는다.

    func openFile() {
        guard !isProjectBusy else { return }
        isProjectActionInProgress = true
        defer { isProjectActionInProgress = false }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml, .png, .jpeg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "도면 열기 (SVG·PNG·JPG)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importDrawingAsync(at: url) }
    }

    func load(data: Data, name: String, confirmingReplacement: Bool = false) {
        do {
            let doc = try SVGParser.parse(data: data, sourceName: name)
            if hasCreatedProject && buildingProject.levels.isEmpty {
                let info = ProjectLevelInfo(name: "1층", ordinal: 0, sourceName: name, svg: String(decoding: data, as: UTF8.self))
                perform("첫 층 도면 불러오기") {
                    buildingProject.levels.append(ProjectLevel(info: info))
                    try? loadLevelEditor(info.id)
                }
                notify("\(name) — 개체 \(doc.objects.count)개를 읽었습니다.")
                return
            }
            if hasCreatedProject && !buildingProject.levels.isEmpty {
                let target = routingFloorID ?? buildingProject.levels[0].id
                try setRoutingDrawing(target, data: data, name: name)
                return
            }
            if confirmingReplacement && !autosaveBeforeLeaving(action: "다른 도면 열기") { return }
            let retainingEmptyProject = canFillEmptyProject
            let previousID = projectID
            let previousURL = projectURL
            resetProjectState(id: retainingEmptyProject ? previousID : UUID())
            document = doc
            loadedSVG = String(data: data, encoding: .utf8)
            let info = ProjectLevelInfo(name: "1층", ordinal: 0, sourceName: name, svg: loadedSVG ?? "")
            buildingProject.levels = [ProjectLevel(info: info)]
            routingFloorID = info.id
            if retainingEmptyProject { projectURL = previousURL }
            notify("\(name) — 개체 \(doc.objects.count)개를 읽었습니다.")
        } catch {
            notify("SVG 파싱 실패: \(error)", isError: true)
        }
    }

    // MARK: 프로젝트 파일 (명세 7-3-2, 9-7)

    @Published var projectURL: URL?
    /// 이 프로젝트의 단일 파일. 자동 저장이 이 자리에 덮어쓴다. 아직 한 번도 저장 전이면 nil.

    // MARK: 저장 루프와 작업 공유 (신기능 1항)

    @Published var projectID = UUID()
    /// 이 작업의 신원. 배정본이 물려받아 "같은 작업에서 나온 파일인가"를 판정한다(신기능 1-2).

    @Published var assignment: Assignment? { didSet { invalidateRenderStates() } }
    /// 지금 연 파일이 **남에게서 받은 몫**이면 채워져 있다. 이때 담당 밖 개체는 고를 수 없다.

    @Published var mergeReportMessage: String?
    /// 배정본을 합친 결과. 팝업으로 그대로 보여준다 — 조용히 건너뛰면 나중에 내보내기에서야 드러난다.

    @Published var hasCreatedProject = false
    @Published var showProjectPicker = false
    /// 정보 입력 창을 연 메타데이터 type(address·building·occupant·manifest). nil이면 닫힘.
    @Published var metadataEditorType: IMDFFeatureType?
    /// 오래 걸리는 계산의 진행률 팝업(`LongTaskProgress.swift`). 끝나면 nil이 되어 저절로 닫힌다.
    @Published var longTask: LongTaskProgress?
    /// 프로젝트 선택 창. 앱 시작 때와 파일 → 프로젝트 선택…에서 뜬다.
    @Published var lastRecoveryProject: ProjectFile?
    /// 마지막으로 파일에 쓴 내용. 지금 내용과 다르면 다음 자동 저장을 기다리는 중이다.
    @Published var isProjectActionInProgress = false

    var autosaveTimer: Timer?

    var loadedSVG: String?
    // 프로젝트에 함께 담을 SVG 원문. 도면을 열 때 받아 둔다.

    /// 저장 로직(`ProjectPersistence.swift`)에서 읽는 이름. 같은 값이지만 뜻을 분명히 한다.
    var loadedSVGText: String? { loadedSVG }

    /// 저장할 것이 있는가. 도면만 열고 아무 작업도 안 했으면 저장할 이유가 없다.
    var hasProjectContent: Bool {
        !features.features.isEmpty || !anchors.pairs.isEmpty || auxiliary.count > 0
    }

    func openProject() {
        guard !isProjectBusy else { return }
        isProjectActionInProgress = true
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ProjectFile.fileExtension) ?? .json,
                                     UTType(filenameExtension: ProjectFile.interimFileExtension) ?? .json]
        // 잠깐 쓰였던 `.imdfproj`도 고를 수 있게 둔다. 그 사이에 저장한 파일이 있으면 열려야 한다.
        // 버전 1 파일은 확장자가 같아 여기서 걸러지지 않고, `ProjectFile.decoded`가 이유를 말하며 거절한다.
        panel.allowsMultipleSelection = false
        panel.directoryURL = autosaveFolder
        // 자동 저장 폴더에서 시작한다. 프로젝트마다 `새 도면_YYMMDD_HHmm.imdfrnt`가 여기 쌓인다.
        let intoLevel = importsProjectIntoActiveLevel ? activeLevel : nil
        // 빈 층에서 누르면 프로젝트를 바꾸지 않고 고른 파일의 층을 이 층에 넣는다(`LevelProjectImport.swift`).
        panel.title = intoLevel.map { "\($0.info.name)에 넣을 .imdfrnt 불러오기" } ?? ".imdfrnt 불러오기"
        panel.message = intoLevel.map { "고른 프로젝트의 층 하나를 \($0.info.name)에 넣습니다. 지금 프로젝트는 그대로입니다." }
            ?? "자동 저장된 .imdfrnt 프로젝트를 선택하세요."
        panel.prompt = "불러오기"
        let response = panel.runModal()
        isProjectActionInProgress = false
        guard response == .OK, let url = panel.url else { return }
        Task {
            if intoLevel != nil { await importProjectLevel(from: url) } else { await openDocumentAsync(at: url) }
        }
    }

    // MARK: 진행률 (명세 3-1) — 전역 하나만 둔다

    /// 제외된 보조 개체는 **분모에서 빼지 않고 분자에 더한다**(명세 디버깅 6번).
    /// 빼버리면 "전체 개체 수"가 작업 중에 줄어들어 진행률이 갑자기 뛴다.
    var totalObjectCount: Int { document?.objects.count ?? 0 }

    /// 소유와 제외는 겹치지 않는다 — 제외된 개체는 애초에 선택할 수 없어 feature에 들어갈 수 없다.
    /// 그래도 이중 계산이 진행률 100% 초과로 새는 것을 막기 위해 집합 연산으로 센다.
    /// 신기능 3-7: **임시 문이 쓰고 있는 문짝·호도 진행률에 기여한다.**
    /// 레이어에 반영하기 전이라 `ownership`에는 아직 안 잡히지만, 사용자 입장에서는
    /// 이미 처리한 개체다. 여기서 빼면 작업을 하는데 막대가 안 움직인다.
    /// 반영 뒤에는 `ownership`에도 잡히므로 **집합 합집합**으로 세어 이중 계산을 막는다.
    var claimedCount: Int {
        ownership.claimedObjectIDs
            .union(doorClosures.consumedObjectIDs)
            .union(pointCoveredObjectIDs)
            .subtracting(auxiliary.excluded)
            .count
    }
    // #21 이후 모든 레이어의 기본 작업이 점 단위라 feature가 개체를 소유하지 않는다.
    // 소유만 세면 openings를 아무리 태깅해도 '저장'이 0이었다 — 점으로 덮은 개체도 함께 센다.

    var excludedCount: Int { auxiliary.count }

    var progressFraction: Double {
        guard totalObjectCount > 0 else { return 0 }
        return Double(claimedCount + excludedCount) / Double(totalObjectCount)
    }

    /// 진행률 막대에서 제외분만 다른 색으로 그리기 위한 비율.
    var excludedFraction: Double {
        guard totalObjectCount > 0 else { return 0 }
        return Double(excludedCount) / Double(totalObjectCount)
    }

    var claimedFraction: Double {
        guard totalObjectCount > 0 else { return 0 }
        return Double(claimedCount) / Double(totalObjectCount)
    }

    var progressText: String {
        guard document != nil else { return "0 / 0" }
        if excludedCount > 0 {
            return "\(claimedCount + excludedCount) / \(totalObjectCount) (저장 \(claimedCount) · 보조 제외 \(excludedCount))"
        }
        return "\(claimedCount) / \(totalObjectCount)"
    }

    /// 명세 10-2-3: 빌려온 opening을 돌려준다. **그룹은 그대로 두고 문만 반납한다.**
    /// 그룹 해제와 다른 기능이다 — 해제는 feature 자체를 없애지만, 반납은
    /// "이 방은 그대로 두되 이 문은 안 쓰겠다"는 뜻이라 폴리곤만 다시 열린다.
    func returnBorrowedOpenings(from fid: FeatureGroupID) {
        let lent = borrow.objects(borrowedBy: fid)
        guard !lent.isEmpty, let f = features.feature(fid) else { return }
        perform("\(f.serialNumber) opening 반납") { borrow.giveBack(lent, from: fid) }
        notify("opening \(lent.count)개를 반납했습니다. 이 폴리곤은 다시 열립니다.")
        // 폴리곤이 열린다는 사실을 함께 알린다 — 반납의 결과가 곧 링 열림이라
        // 모르고 누르면 나중에 저장 경고를 보고서야 원인을 찾게 된다.
    }

    /// 지금 열려 있는 레이어가 속성 필터 레이어인가.
    var isAttributeFilterActive: Bool {
        if case .attributeFilter = layers.activeLayer?.kind { return true }
        return false
    }

    /// 명세 2항: 속성 필터 레이어에 지금 선택한 개체를 더한다.
    /// 속성이 달라 필터에 안 걸리는 개체도 같은 레이어에서 함께 다루려는 것이 이 기능의 목적이라,
    /// 필터 조건 자체는 건드리지 않고 개체 id만 따로 얹는다.
    func addSelectionToActiveFilterLayer() {
        guard let active = layers.activeLayer,
              case .attributeFilter = active.kind else {
            notify("속성 필터 레이어를 연 뒤에 쓸 수 있습니다.", isError: true)
            return
        }
        let added = selection.selected.subtracting(active.extraObjectIDs)
        guard !added.isEmpty else {
            notify("선택한 개체가 이미 이 레이어에 있습니다.")
            return
        }
        perform("속성 필터 레이어에 개체 추가") {
            layers.addObjects(added, to: active.id)
        }
        notify("개체 \(added.count)개를 이 레이어에 추가했습니다.")
    }

    // MARK: 렌더 상태

    private var renderStateCache: [VectorObjectID: ObjectRenderState]? { didSet { renderStateRevision &+= 1 } }

    /// 표시 상태 사전이 바뀔 때마다 오르는 번호. 캔버스가 묶어 그리는 경로(`CanvasBatches`)가 이 번호로 유효한지 본다.
    private(set) var renderStateRevision = 0

    /// 표시 상태를 다시 판정해야 한다고 표시한다. `@Published` 상태의 `didSet` 한 곳에서만 부른다 —
    /// 지우는 코드를 여기저기 흩으면 새 기능이 들어올 때마다 한 군데씩 빠지고,
    /// 그때 증상은 "화면이 갱신되지 않는다"로 나타나 원인을 찾기 어렵다.
    func invalidateRenderStates() { renderStateCache = nil }

    /// 몇 feature의 표시(강조·펼침·category 필터)만 바뀌었을 때, 그 구성원과 빌린 개체만 다시 판정한다.
    /// 다른 개체의 상태는 이 feature들과 무관하다. 사전이 아직 없으면 할 일이 없다(다음에 통째로 만든다).
    func refreshRenderStates(owners: Set<FeatureGroupID>) {
        guard !owners.isEmpty, renderStateCache != nil, let doc = document else { return }
        var ids = Set<VectorObjectID>()
        for owner in owners {
            ids.formUnion(borrow.objects(borrowedBy: owner))
            if let f = features.feature(owner) { ids.formUnion(f.memberIDs) }
        }
        guard !ids.isEmpty, var table = renderStateCache else { return }
        // 점으로 그린 feature는 구성원 개체가 없다. 다시 판정할 개체가 없으면 사전을 건드리지 않는다 —
        // 건드리면 번호가 올라 캔버스가 묶음 경로를 통째로 다시 만든다.
        renderStateCache = nil
        // 꺼내 두고 고친다. 원본이 사전을 함께 쥐고 있으면 고치는 순간 6만 칸이 통째로 복사된다.
        let context = renderStateContext()
        for id in ids { if let o = doc.object(id) { table[id] = computeRenderState(for: o, context: context) } }
        renderStateCache = table
    }

    /// 선분화가 바뀐 개체의 파생 데이터만 지운다(제안 2).
    func invalidateSegmentationCaches(since old: SegmentationStore) {
        for id in segmentation.changedObjects(since: old) { renderCache.invalidate(id) }
        invalidateRenderStates()
        // 선분화 여부는 `curvedOnly` 모드의 opacity 규칙에 걸려 있어 표시 상태도 달라진다.
    }

    /// 도면 전체의 표시 상태. 그리기 루프와 선택 후보 찾기가 **같은 사전 하나**를 나눠 쓴다.
    /// 이전에는 개체마다 `renderState`를 부르고, 그 안에서 feature 목록을 앞에서부터 훑었다 —
    /// 개체 2,000개 × feature 300개면 프레임당 60만 번 비교이고, 한 프레임에 두 번 이상 돌았다.
    func renderStates() -> [VectorObjectID: ObjectRenderState] {
        if let renderStateCache { return renderStateCache }
        guard let doc = document else { return [:] }
        var table: [VectorObjectID: ObjectRenderState] = [:]
        table.reserveCapacity(doc.objects.count)
        let context = renderStateContext()
        for o in doc.objects { table[o.id] = computeRenderState(for: o, context: context) }
        renderStateCache = table
        return table
    }

    /// 이름과 동작을 유지한다 — `--selftest`와 UI가 이미 이 이름으로 20곳 넘게 쓰고 있다.
    /// property type 레이어의 투명도. 그 type으로 저장된 다각형·선·점을 그릴 때 곱한다. 레이어가 없으면 100%.
    func polygonOpacity(for type: IMDFFeatureType) -> Double {
        layers.layers.first { $0.kind == .propertyType(type) }?.opacity ?? 1
    }

    func renderState(for object: VectorObject) -> ObjectRenderState {
        if let table = renderStateCache, let hit = table[object.id] { return hit }
        return renderStates()[object.id] ?? computeRenderState(for: object, context: renderStateContext())
    }

    /// 표시 상태를 판정할 때 개체마다 같은 값. 사전을 만들 때 한 번만 구한다.
    /// 예전에는 개체마다 지금 층(`activeLevel`, 층 구조체 복사)·활성 레이어를 찾고, `@Published` 저장소를
    /// 여러 번 읽었다(읽을 때마다 Combine을 거친다). 6만 개면 그것만 수백 ms였다.
    struct RenderStateContext {
        var hidesAll: Bool
        var activeLayer: EditorLayer?
        var activeType: IMDFFeatureType?
        var isolatedMembers: Set<VectorObjectID>?
        var excludedMembers: Set<VectorObjectID>
        var typeOpacity: [IMDFFeatureType: Double]
        var selected: Set<VectorObjectID>
        var ownership: OwnershipRegistry
        /// 소유 feature → (type, category 필터 통과 여부). feature 구조체(링 포함)를 개체마다 꺼내지 않는다.
        var owners: [FeatureGroupID: (type: IMDFFeatureType, passes: Bool)]
        var auxiliary: AuxiliaryStore
        var assigned: Set<VectorObjectID>?
        var mode: InteractionMode
        var segmentation: SegmentationStore
        var excludedOpacity: Double
        /// 펼친 카드들이 빌린 개체. 선택한 개체는 빌릴 수 있는 opening이면 빌림 표시다(`isBorrowedHere`).
        var borrowedByExpanded: Set<VectorObjectID>
        var canBorrowOpenings: Bool
        var highlighted: Set<FeatureGroupID>
    }

    private func renderStateContext() -> RenderStateContext {
        let features = features, layers = layers
        let activeType = layers.activePropertyType
        let expanded = expandedFeatures
        let borrow = borrow
        var highlighted = expanded
        if let id = layers.isolatedFeature { highlighted.insert(id) }
        if let id = hoveredFeature { highlighted.insert(id) }
        return RenderStateContext(
            hidesAll: currentRoutingFloor?.imdfCoordinates == nil && !primarySVGPresentation.isVisible,
            activeLayer: layers.activeLayer,
            activeType: activeType,
            isolatedMembers: layers.isolatedFeature.map { features.feature($0)?.memberIDs ?? [] },
            excludedMembers: layers.excludedFeature.flatMap { features.feature($0)?.memberIDs } ?? [],
            typeOpacity: Dictionary(uniqueKeysWithValues: IMDFFeatureType.allCases.map { ($0, polygonOpacity(for: $0)) }),
            selected: selection.selected,
            ownership: ownership,
            owners: Dictionary(features.features.map { ($0.id, ($0.featureType, passesCategoryFilter($0))) },
                              uniquingKeysWith: { first, _ in first }),
            auxiliary: auxiliary,
            assigned: assignment?.objectIDs,
            mode: mode,
            segmentation: segmentation,
            excludedOpacity: excludedAuxiliaryOpacity,
            borrowedByExpanded: expanded.reduce(into: Set<VectorObjectID>()) { $0.formUnion(borrow.objects(borrowedBy: $1)) },
            canBorrowOpenings: activeType?.canBorrowOpenings ?? false,
            highlighted: highlighted)
    }

    private func computeRenderState(for object: VectorObject, context c: RenderStateContext) -> ObjectRenderState {
        if c.hidesAll {
            return ObjectRenderState(opacity: 0, isVisible: false, isSelected: false, isDisabled: true)
        }
        var opacity = 1.0
        var visible = true
        let isSelected = c.selected.contains(object.id)

        let ownerFeature = c.ownership.ownerOf(object.id)
        let owner = ownerFeature.flatMap { c.owners[$0] }
        let ownerType = owner?.type
        let activeType = c.activeType
        let isExcluded = c.auxiliary.isExcluded(object.id)
        let isDisabled = (ownerType != nil && activeType != nil) || isExcluded
            || !(c.assigned?.contains(object.id) ?? true)
            // 담당 밖 개체는 '고를 수 없다'는 뜻에서 이미 남이 가져간 개체와 같은 상태다(신기능 1-2-4).
            // 색을 새로 만들지 않고 기존 비활성 색을 쓴다 — 사용자가 배워야 할 상태가 늘지 않는다.

        // 활성 레이어가 무엇을 보여주는 레이어인지가 표시 여부의 1차 기준이다(명세 2항).
        // 이전에는 레이어를 만들기만 하고 렌더링이 전혀 참조하지 않아, 속성 필터 레이어가
        // 목록에 이름만 생기고 화면은 그대로였다.
        if let active = c.activeLayer {
            if active.isHidden { visible = false }
            if case .propertyType = active.kind {} else { opacity *= active.opacity }
            // 레이어별 투명도(2026-08-27). 상위 기본 레이어·속성 필터 레이어에서 그려지는 개체는
            // **지금 열려 있는 레이어의 것**이므로 그 값을 곱한다.
            // property type 레이어의 투명도는 도면 개체가 아니라 그 레이어에 표시된 다각형에 건다
            // (2026-10-18 요청, `polygonOpacity(for:)`). 태깅한 개체(예전 방식 구성원)만 주인 type 값을 따른다.
            // 하위 기본 레이어(고스트)는 따로 그려지므로 캔버스가 자기 값을 직접 쓴다.
            // 숨긴 레이어의 개체는 보이지 않는다. 눈 아이콘이 상태만 바꾸고 화면이 안 바뀌면
            // 사용자는 기능이 고장 난 것으로 읽는다.

            if case .attributeFilter(let key, _) = active.kind {
                let matchesStyle = object.style.attributeKey == key
                let addedByUser = active.extraObjectIDs.contains(object.id)
                // 명세 2항: "거기에 내가 선택한 다른 벡터들도 추가 가능"
                if !matchesStyle && !addedByUser { visible = false }
            }
        }

        if let iso = c.isolatedMembers {
            visible = iso.contains(object.id)
        }
        if c.excludedMembers.contains(object.id) {
            visible = false
        }
        if owner?.passes == false {
            visible = false
        }
        // category 필터로 걸러진 feature의 구성원 개체도 숨긴다(#52). 점으로 그린 도형은 캔버스가 따로 거른다.

        switch c.mode {
        case .ungroupedOnly:
            if ownerFeature != nil { opacity = 0.75 }
        case .curvedOnly(let showSegmentedOnly):
            if !object.isCurved {
                opacity = 0.75
            } else if showSegmentedOnly {
                opacity = c.segmentation.isSegmented(object.id) ? 1.0 : 0.5
            }
        default:
            break
        }

        if isExcluded { opacity *= c.excludedOpacity }
        // 제외된 보조 개체는 계속 보이되(명세 2항: 파일에서 사라지지 않는다) 눈에 띄게 옅어진다.

        if !c.selected.isEmpty && !isSelected {
            opacity *= 0.7
            // 명세 5항: 선택된 개체 이외에는 70% opacity
        }
        if isDisabled { opacity *= 0.85 }
        if let ownerType, activeType != nil { opacity *= c.typeOpacity[ownerType] ?? 1 }
        // 예전 방식(구성원 개체)으로 태깅한 feature는 그 개체 선이 곧 표시된 도형이다. 주인 type 레이어의 투명도를 따른다.

        let isBorrowed = c.borrowedByExpanded.contains(object.id)
            || (isSelected && c.canBorrowOpenings && ownerType == .opening)
        // `isBorrowedHere`·`canBorrow`와 같은 규칙을 미리 모은 값으로 판정한다.
        return ObjectRenderState(opacity: opacity, isVisible: visible,
                                 isSelected: isSelected, isDisabled: isDisabled,
                                 isBorrowed: isBorrowed,
                                 isHighlighted: ownerFeature.map(c.highlighted.contains) ?? false,
                                 isTaggedHere: ownerType != nil && ownerType == activeType,
                                 isTaggedOtherLayer: ownerType != nil && activeType != nil && ownerType != activeType
                                     && !isExcluded)
    }

    func geometry(for object: VectorObject) -> PathGeometry {
        segmentation.effectiveGeometry(for: object.id, fallback: object.geometry)
    }

    /// 링이 열린 지점. 캔버스가 이 자리를 표시한다(명세 10-4-3).
    /// **지금 펼쳐 놓은 feature 기준**이다 — 저장 직후에는 그 feature가 펼쳐지므로 저장 경고와
    /// 자동으로 같은 곳을 가리키고, 나중에 인스펙터에서 다시 펼쳐도 같은 자리가 다시 표시된다.
    /// 별도 상태로 들고 있으면 둘이 어긋나 "경고는 뜨는데 화면에는 아무 표시도 없는" 상태가 생긴다.
    @Published private(set) var openRingGaps: [RingClosureValidator.Gap] = []

    /// 펼친 feature · feature 구성 · 대여 · 임시 문이 바뀔 때만 다시 잰다.
    /// 링이 닫혔는지는 이 넷으로만 달라지는데, 계산식으로 두면 매 프레임 다시 쟀다.
    func refreshOpenRingGaps() {
        guard !expandedFeatures.isEmpty else {
            if !openRingGaps.isEmpty { openRingGaps = [] }
            return
        }
        let open = expandedFeatures.compactMap { features.feature($0) }
            .sorted { $0.serialNumber < $1.serialNumber }
        // 펼친 카드 전부의 열린 자리를 함께 표시한다. 정렬해 두는 것은 같은 상태에서
        // 같은 순서가 나오게 하려는 것이다 — Set은 순서를 보장하지 않는다.
        openRingGaps = open.flatMap { ringClosure(of: $0)?.gaps ?? [] }
    }

    /// 명세 10-4-3의 경고 문구.
    /// **단위를 mm로 단정하지 않는다.** SVG 도면 좌표는 단위가 정해져 있지 않고,
    /// 실제 거리는 Anchor로 지오레퍼런싱한 뒤에야 알 수 있다. Anchor가 갖춰졌으면 m로,
    /// 아니면 도면 단위로 적는다 — 없는 정확도를 지어내면 사용자가 도면을 잘못 고친다.
    func gapMessage(serial: String, result: RingClosureValidator.Result) -> String {
        let n = result.gaps.count
        let g = georeferencer
        if g.isConfigured, let worst = result.gaps.first,
           let a = g.geoPoint(for: worst.point),
           let b = g.geoPoint(for: LocalPoint(worst.point.x + worst.distance, worst.point.y)) {
            // 벌어진 거리만큼 x로 옮긴 점을 함께 변환해 실제 거리를 잰다.
            // 변환에 회전·비등방 축척이 섞여 있어 도면 단위에 상수를 곱하는 식으로는 환산되지 않는다.
            let meters = ResidualCalculator.metersBetween(a, b)
            return String(format: "%@ 폴리곤이 닫히지 않았습니다. 빌려온 opening과 벽 사이에 %d곳, 최대 %.0fmm 간격이 있습니다.",
                          serial, n, meters * 1000)
        }
        return String(format: "%@ 폴리곤이 닫히지 않았습니다. %d곳이 벌어져 있습니다(최대 %.2f 도면 단위). Anchor를 지정하면 실제 거리로 표시됩니다.",
                      serial, n, result.worstGap)
    }

    // MARK: 위치 이동 (명세 2-3, 2026-08-25 사노 요청으로 재도입)
    //
    // 겹침 윤곽 표시(바로 아래)와 공존한다. 이동은 화면 전용이고 문서에 영구 저장되지
    // 않는다(명세 2-3 원문 "이동된 위치는 영구 저장되지 않음") — `EditorSnapshot`(실행취소)에도,
    // `ProjectFile`(작업 저장)에도 넣지 않는다. `VertexExtractor`·`GeoJSONExporter`는 항상
    // `DrawingDocument`의 원본 좌표를 직접 읽으므로 이동이 산출물에 영향을 주지 않는다.

    /// 개체별 화면 이동량. 비어 있으면 원위치.
    /// 실체는 `moves`(별도 관찰 객체)에 있다 — 드래그 한 프레임마다 `AppEnvironment` 전체가
    /// 알림을 보내면 사이드바·인스펙터까지 다시 그려진다(제안 4).
    var transientOffsets: [VectorObjectID: CGSize] { moves.offsets }

    func offset(for id: VectorObjectID) -> CGSize { moves.offset(for: id) }

    /// 렌더링·클릭 판정에 쓰는 화면상 지오메트리. 원본(`geometry(for:)`)에 이동량만 얹는다 —
    /// 좌표 추출·내보내기 경로는 이 함수를 거치지 않으므로 이동에 영향받지 않는다.
    func displayGeometry(for object: VectorObject) -> PathGeometry {
        let g = geometry(for: object)
        let off = offset(for: object.id)
        guard off != .zero else { return g }
        return g.translated(by: CGVector(dx: off.width, dy: off.height))
    }

    /// 드래그 시작점이 지금 선택된 개체 위인가 — 이 경우에만 드래그가 팬 대신 이동이 된다.
    /// `handleCanvasClick`과 판정 규칙(레이어·모드)은 공유하지 않는다 — 이동은 소유권과
    /// 무관하게 "이미 선택된 것을 옮기는" 동작이라 클릭의 태깅 규칙이 끼어들 이유가 없다.
    func movableHit(at point: LocalPoint, tolerance: Double) -> VectorObjectID? {
        guard isMoveEnabled else { return nil }
        // 토글이 꺼져 있으면 '옮길 대상 없음'으로 답한다(명세 2-3, 2026-08-29 사노 요청).
        // 여기서 nil을 주면 캔버스의 드래그가 그대로 화면 팬으로 흘러간다 —
        // 반응이 없는 것보다 낫고, 이동 도입 이전의 조작감과 같아진다.
        guard let doc = document, !selection.selected.isEmpty else { return nil }
        guard case .idle = mode else { return nil }
        // 다른 모드(Anchor 찍기·display point 찍기·곡선 창 등)에서는 드래그가 각자의 뜻을 갖는다.
        let selected = doc.objects.filter { selection.selected.contains($0.id) }
        guard let hit = HitTester.hitTest(point, candidates: selected,
                                          cached: renderCache.geometryProvider(segmentation),
                                          offsets: moves.offsets, tolerance: tolerance) else {
            return nil
        }
        return hit
    }

    /// 이동 시작 시점의 오프셋 스냅샷 + 지금 선택 전체. 프레임마다 여기에 델타만 더해
    /// 반복 합산으로 인한 오차를 막는다.
    func beginMove() -> [VectorObjectID: CGSize] {
        guard isMoveEnabled else { return [:] }
        // 두 번째 문(門)이다. `movableHit`만 막으면 캔버스 경로는 닫히지만, 메뉴·자체점검처럼
        // 판정을 거치지 않고 부르는 자리가 남는다. 빈 기준점을 주면 `applyMove`가 옮길 대상이
        // 없어 오프셋이 생기지 않는다 — 게이트가 한 군데 뚫려도 이동이 새지 않는다.
        return moves.begin(selection.selected)
    }

    func applyMove(_ delta: CGSize, from base: [VectorObjectID: CGSize]) {
        moves.apply(delta, from: base)
    }

    func endMove() { moves.end() }

    /// 상단바 '원위치'(선택분) / 사이드바 '모든 개체 원위치'.
    func resetPositions(_ ids: Set<VectorObjectID>? = nil) {
        moves.reset(ids)
    }

    var hasAnyOffset: Bool { moves.hasAny }
    var selectionHasOffset: Bool { selection.selected.contains { moves.offsets[$0] != nil } }

    /// 개체 드래그 이동을 허용하는가(명세 2-3, 2026-08-29 사노 요청). 기본은 꺼짐 —
    /// 이 앱의 평소 작업은 '고르고 묶는' 일이라, 실수로 도면을 흐트러뜨리는 쪽이 비용이 크다.
    /// 끌 때 이미 옮겨 둔 개체를 **되돌리지 않는다**: 안내 문구가 '모든 개체 원위치'를 눌러
    /// 복구하라고 명시하므로 복구는 사용자가 고르는 별개의 행동이고, 겹침을 확인하려고
    /// 벌려 둔 배치가 토글을 끄는 순간 사라지면 확인 자체가 끝나 버린다.
    @Published var isMoveEnabled = false {
        didSet {
            guard oldValue != isMoveEnabled else { return }
            notify(isMoveEnabled
                   ? #"겹치는 개체를 확인하기 위해 개체 이동을 허용합니다. 상단 바의 "모든 개체 원위치"를 눌러 복구하세요."#
                   : "개체 이동을 허용하지 않습니다.")
            // 안내는 상단바 버튼이 아니라 여기서 띄운다 — 나중에 메뉴·단축키가 붙어도
            // 문구가 따라오게 하려는 것이다. 1회성이 아니라 토글할 때마다 뜬다.
        }
    }

    /// 이동 드래그 중인가. 겹침 표시는 원본 좌표로 계산하므로 이동 중에는 어긋난 자리를
    /// 가리킨다 — 그 동안은 그리지 않는다(`06) 확인 필요.md` A12).
    var isMovingObjects: Bool { moves.isMoving }

    // MARK: 겹침 표시 (명세 2-3 대체, 2026-08-25)

    /// 선택한 개체가 다른 벡터와 겹치는 곳. 개체를 옮겨 보는 대신 이걸 제자리에 그린다.
    @Published var showOverlapHighlight = true { didSet { refreshOverlap() } }

    @Published private(set) var overlapHighlight = OverlapDetector.Result()

    /// 겹침을 다시 계산한다. **매 프레임이 아니라 재료가 바뀔 때만** 불린다 —
    /// 선택 · 선분화 · 표시 토글 · feature · 보조 개체 제외 · 문서, 이 여섯의 `didSet`이 전부다.
    /// 드래그 중에는 이 가운데 무엇도 바뀌지 않으므로 계산이 0번이 된다.
    /// 계산식(computed property)으로 두면 캔버스가 값을 읽는 자리에서 매 프레임 전부 다시 돌아,
    /// 개체 수천 개짜리 도면에서는 그 자체로 드래그가 멈춘다.
    func refreshOverlap() {
        guard showOverlapHighlight, !selection.selected.isEmpty, let doc = document else {
            if !overlapHighlight.isEmpty { overlapHighlight = OverlapDetector.Result() }
            return
        }
        let bounds = selection.selected.compactMap { doc.object($0)?.boundingBox }
        let hull = bounds.dropFirst().reduce(bounds.first ?? .infinite) { $0.union($1) }
            .insetBy(dx: -overlapTolerance - maxStrokePad, dy: -overlapTolerance - maxStrokePad)
        // 겹침은 **선택한 개체 주변**에서만 생긴다. 도면 반대편 개체까지 후보에 넣을 이유가 없다.
        overlapHighlight = OverlapDetector.detect(selected: selection.selected,
                                                  among: selectableObjects(in: doc, near: hull),
                                                  cached: renderCache.geometryProvider(segmentation),
                                                  tolerance: overlapTolerance)
    }

    /// 격자로 후보를 좁힐 때 넓혀 두는 여유. 개체의 경계 상자는 선의 **중심선** 기준이라,
    /// 굵은 선은 상자 밖으로 두께의 절반만큼 삐져나온다. 그만큼 넓히지 않으면
    /// 칸 경계에 걸친 굵은 벽선을 클릭해도 후보에서 빠진다.
    private var maxStrokePad: Double {
        (document?.objects.map(\.style.strokeWidth).max() ?? 0) / 2 + 2
    }

    /// 도면 크기에 비례한 허용오차. 고정값을 쓰면 큰 도면에서는 이중선이 안 잡히고
    /// 작은 도면에서는 멀쩡한 선이 겹침으로 잡힌다.
    var overlapTolerance: Double {
        guard let d = document else { return 0.5 }
        return max(0.25, min(d.canvasSize.width, d.canvasSize.height) / 2000)
    }

    // MARK: 캔버스 입력

    func handleCanvasClick(at point: LocalPoint, tolerance: Double) {
        guard let doc = document else { return }

        if case .anchorPicking = mode {
            pendingAnchorLocal = point
            mode = .idle
            showAnchorScreen = true
            notify("도면 좌표를 찍었습니다. 위경도를 입력해 쌍을 완성하세요.")
            return
        }

        if case .displayPointPicking(let fid) = mode {
            setDisplayPoint(point, for: fid)
            return
        }

        guard isSelectModeActive else { return }

        let probe = CGRect(x: point.x - tolerance, y: point.y - tolerance,
                           width: tolerance * 2, height: tolerance * 2)
        let candidates = selectableObjects(in: doc, near: probe.insetBy(dx: -maxStrokePad,
                                                                       dy: -maxStrokePad))
        guard let hit = HitTester.hitTest(point, candidates: candidates,
                                          cached: renderCache.geometryProvider(segmentation),
                                          offsets: moves.offsets,
                                          tolerance: tolerance) else {
            return
        }

        if case .curvedOnly = mode {
            guard doc.object(hit)?.isCurved == true else {
                notify("곡선 개체만 선택할 수 있는 모드입니다.")
                return
            }
        }

        if !isWithinAssignment(hit) {
            notify("내 담당 몫이 아닌 개체입니다. 도면 전체가 보이는 것은 주변을 보기 위해서입니다.",
                   isError: true)
            return
            // 신기능 1-2-4. 배정본에서는 담당 구역만 고를 수 있다.
        }

        if auxiliary.isExcluded(hit) {
            notify("보조 개체로 제외된 개체입니다. '보조 개체 제외' 창에서 제외를 풀어야 태깅할 수 있습니다.")
            return
            // 명세 디버깅 6번: 제외는 '모든 레이어로부터' 걸리므로 여기 한 곳에서 막는다.
        }

        if isCurvedOnlyMode {
            selection.toggle(hit)
            return
            // **곡선 창에서는 소유권을 보지 않는다.** 이 창의 선택은 '선분화 대상 지정'이지
            // feature 구성원 지정이 아니다. 소유권 제약은 "다른 type이 가져간 개체를 이 type으로
            // 태깅하지 마라"는 뜻이라 선분화에는 걸릴 이유가 없고, 걸리면 이미 저장된 곡선의
            // '선분화 해제'(명세 3-3-3)가 통째로 막힌다.
        }

        if let ownerID = ownership.ownerOf(hit),
           let owner = features.feature(ownerID),
           layers.activePropertyType != nil,
           owner.featureType != layers.activePropertyType {
            if canBorrow(hit) {
                selection.toggle(hit)
                return
                // 명세 10-2-1: 소유권 배타 규칙의 **유일한 예외**. 경고창을 띄우지 않는다(10-2-2).
                // 문은 방 폴리곤을 닫는 데 필요한데, 경고를 띄우면 정상 작업이 매번 막힌다.
            }
            conflict = ConflictInfo(objectID: hit, ownerFeature: ownerID,
                                    ownerType: owner.featureType, ownerSerial: owner.serialNumber)
            return
            // 명세 4-1) 경고창
        }
        if let ownerID = ownership.ownerOf(hit), let owner = features.feature(ownerID),
           owner.featureType == layers.activePropertyType {
            notify("\(owner.serialNumber)에 이미 저장된 개체입니다. 그룹 해제 후 다시 시도하세요.")
            return
        }

        selection.toggle(hit)
    }

    // MARK: 드래그 사각형 선택 (명세 디버깅 9번)
    //
    // 클릭 한 번에 하나씩 고르는 경로(`handleCanvasClick`)와 **판정 규칙은 똑같이** 두되,
    // 막힌 개체를 만났을 때의 반응만 다르다. 클릭은 하나를 겨냥한 행동이라
    // 못 고르면 경고창·안내를 띄워야 하지만, 드래그는 수십 개를 한 번에 훑는 행동이라
    // 개체마다 경고를 띄우면 작업이 멈춘다. 그래서 **막힌 것은 조용히 건너뛰고 개수만 요약**한다.

    /// 드래그로 훑은 사각형 안의 개체를 선택에 **더한다**(토글이 아니다).
    /// 여러 개를 한꺼번에 뒤집으면 이미 고른 것이 딸려서 풀려 예측이 안 된다.
    func handleMarqueeSelection(rect: CGRect, mode marqueeMode: HitTester.MarqueeMode) {
        guard let doc = document, isSelectModeActive else { return }

        let candidates = selectableObjects(in: doc, near: rect.insetBy(dx: -maxStrokePad,
                                                                       dy: -maxStrokePad))
        let hits = HitTester.objects(in: rect, mode: marqueeMode,
                                     candidates: candidates,
                                     cached: renderCache.geometryProvider(segmentation),
                                     offsets: moves.offsets)
        guard !hits.isEmpty else { return }

        // ✅ 2026-08-30 추가 — 빼기 모드에서는 걸린 것 중 **이미 선택된 것만** 뺀다.
        // 소유권·보조 제외 판정(`marqueeAdmission`)은 보지 않는다. 그 판정은 "넣어도 되는가"를
        // 묻는 것인데, 선택에 들어 있다는 사실 자체가 이미 통과했다는 뜻이기 때문이다.
        if marqueeSubtracts {
            let removed = hits.filter { selection.selected.contains($0) }
            guard !removed.isEmpty else {
                notify("사각형 안에 해제할 개체가 없습니다.")
                return
            }
            var next = selection.selected
            next.subtract(removed)
            selection.selected = next
            notify("\(removed.count)개 선택 해제")
            return
        }

        var added = 0
        var blockedByOwner = 0
        var blockedByAuxiliary = 0
        var blockedByCurvedOnly = 0
        var blockedByAssignment = 0

        var next = selection.selected
        for id in hits where !next.contains(id) {
            switch marqueeAdmission(id, in: doc) {
            case .allow:
                next.insert(id)
                added += 1
            case .curvedOnly:        blockedByCurvedOnly += 1
            case .auxiliary:         blockedByAuxiliary += 1
            case .owned:             blockedByOwner += 1
            case .outsideAssignment: blockedByAssignment += 1
            }
        }
        if added > 0 { selection.selected = next }
        // **선택을 한 번에 대입한다.** 개체마다 `selection`을 고치면 그때마다 `didSet`이 돌아
        // 표시 상태 사전이 버려지고 겹침 검사가 다시 계산된다. 겹침은 선택 개수에 비례하므로
        // 200개를 고르면 계산이 200번, 그것도 점점 무거워지며 돈다 — 드래그 선택이
        // 멎은 것처럼 느려진 원인이 이것이다(2026-08-26).

        var parts: [String] = ["\(added)개 선택"]
        if blockedByCurvedOnly > 0 { parts.append("곡선 아님 \(blockedByCurvedOnly)개 제외") }
        if blockedByAuxiliary > 0 { parts.append("보조 개체 \(blockedByAuxiliary)개 제외") }
        if blockedByOwner > 0 { parts.append("이미 저장됨 \(blockedByOwner)개 제외") }
        if blockedByAssignment > 0 { parts.append("담당 밖 \(blockedByAssignment)개 제외") }
        notify(parts.joined(separator: " · "), isError: added == 0)
    }

    /// 보조 개체 제외 창의 드래그 사각형 선택.
    /// 이 창은 소유권·레이어를 보지 않으므로(클릭 경로와 같은 이유) 거를 것이 없다 —
    /// 여기서 고르는 것은 'feature 구성원'이 아니라 '태깅 대상에서 뺄 것'이라
    /// 이미 저장된 개체도 골라야 정상이다.
    func handleAuxiliaryMarquee(rect: CGRect, mode marqueeMode: HitTester.MarqueeMode) {
        guard let doc = document else { return }
        let hits = HitTester.objects(in: rect, mode: marqueeMode,
                                     candidates: doc.objects,
                                     cached: renderCache.geometryProvider(segmentation))
        guard !hits.isEmpty else { return }

        // ✅ 2026-08-30 추가 — 빼기 모드.
        if marqueeSubtracts {
            let removed = hits.filter { auxiliarySelection.contains($0) }
            guard !removed.isEmpty else {
                notify("사각형 안에 해제할 개체가 없습니다.")
                return
            }
            auxiliarySelection.subtract(removed)
            focusedTwinKey = nil
            notify("\(removed.count)개 선택 해제")
            return
        }

        let added = hits.filter { !auxiliarySelection.contains($0) }
        auxiliarySelection.formUnion(hits)
        focusedTwinKey = nil
        // 캔버스에서 직접 고르면 목록 강조는 푼다 — 클릭 경로와 같은 규칙이다.
        notify("\(added.count)개 선택")
    }

    /// 보조 개체 제외 창에서 개체 하나를 클릭했을 때. 같은 자리에 겹친 똑같은 개체까지 함께 고르거나 함께 푼다.
    func handleAuxiliaryClick(_ hit: VectorObjectID) {
        let stack = stackedTwins(of: hit)
        // 드래그는 겹친 것을 다 담는데 클릭만 하나를 잡으면, 같은 지정이 입력 방식에 따라 결과가 갈린다.
        if auxiliarySelection.contains(hit) {
            auxiliarySelection.subtract(stack)
        } else {
            auxiliarySelection.formUnion(stack)
        }
        focusedTwinKey = nil
        // 캔버스에서 직접 고르면 목록 강조는 풀어준다 — 둘이 어긋나면 무엇이 100%인지 헷갈린다.
    }

    enum MarqueeAdmission { case allow, curvedOnly, auxiliary, owned, outsideAssignment }

    /// 개체 하나가 드래그 선택에 들어갈 수 있는가. `handleCanvasClick`의 거절 사유와 1:1로 맞춘다.
    func marqueeAdmission(_ id: VectorObjectID, in doc: DrawingDocument) -> MarqueeAdmission {
        if !isWithinAssignment(id) { return .outsideAssignment }
        if case .curvedOnly = mode, doc.object(id)?.isCurved != true { return .curvedOnly }
        if auxiliary.isExcluded(id) { return .auxiliary }

        // 곡선 창의 선택은 '선분화 대상 지정'이라 소유권을 보지 않는다(클릭 경로와 같은 이유).
        if isCurvedOnlyMode { return .allow }

        if let ownerID = ownership.ownerOf(id), let owner = features.feature(ownerID) {
            if owner.featureType == layers.activePropertyType { return .owned }
            if layers.activePropertyType != nil, owner.featureType != layers.activePropertyType {
                return canBorrow(id) ? .allow : .owned
            }
        }
        return .allow
    }

    private var pendingAnchorLocalStorage: LocalPoint?
    var pendingAnchorLocal: LocalPoint? {
        get { pendingAnchorLocalStorage }
        set { pendingAnchorLocalStorage = newValue; objectWillChange.send() }
    }

    func selectableObjects(in doc: DrawingDocument) -> [VectorObject] {
        let states = renderStates()
        return doc.objects.filter { states[$0.id]?.isVisible ?? true }
    }

    /// 격자로 후보를 좁힌 뒤 표시 여부까지 거른다(제안 5).
    /// 도면 전체를 훑던 클릭·사각형 선택이 **해당 칸에 걸친 개체만** 보게 된다.
    /// 격자가 아직 없으면(빈 문서 등) 종전처럼 전체를 넘겨 동작이 달라지지 않게 한다.
    func selectableObjects(in doc: DrawingDocument, near rect: CGRect) -> [VectorObject] {
        let states = renderStates()
        guard let ids = spatialIndex.candidates(in: rect, moved: Set(moves.offsets.keys)) else {
            return doc.objects.filter { states[$0.id]?.isVisible ?? true }
        }
        return doc.objects.filter { ids.contains($0.id) && (states[$0.id]?.isVisible ?? true) }
        // 순서를 유지하려고 `doc.objects`를 훑는다 — 히트테스트가 "위에 그려진 것 먼저"를
        // 그리기 순서로 판정하므로, 격자에서 꺼낸 순서를 그대로 쓰면 클릭 결과가 달라진다.
    }

    // MARK: 실행취소·다시실행 (명세 디버깅 8번)

    @Published var undoStack = UndoStack()

    /// 되돌릴 상태 전부를 한 덩어리로 뜬다. `document`는 불변이라 여기 없다.
    var snapshot: EditorSnapshot {
        EditorSnapshot(layers: layers, features: features, ownership: ownership,
                       selection: selection, segmentation: segmentation,
                       auxiliary: auxiliary, openingGate: openingGate, borrow: borrow,
                       anchors: anchors, doorClosures: doorClosures, serials: serials,
                       ids: ids, expandedFeatures: expandedFeatures,
                       focusedFeature: focusedFeature,
                       faceSelection: faceSelection,
                       pointDraft: pointDraft,
                       buildingProject: projectContents,
                       routing: routing, routingFloorID: routingFloorID,
                       routingSelectedNodeID: routingSelectedNodeID,
                       routingSelectedEdgeID: routingSelectedEdgeID)
    }

    private func restore(_ s: EditorSnapshot) {
        let restoredSVG = s.buildingProject.levels.first { $0.id == s.routingFloorID }?.info.svg
        let needsDocument = routingFloorID != s.routingFloorID || (loadedSVG ?? "") != (restoredSVG ?? "")
        buildingProject = s.buildingProject
        if needsDocument { beginLevelDrawingLoad(s.routingFloorID) }
        layers = s.layers
        features = s.features
        ownership = s.ownership
        selection = s.selection
        segmentation = s.segmentation
        auxiliary = s.auxiliary
        openingGate = s.openingGate
        borrow = s.borrow
        doorClosures = s.doorClosures
        anchors = s.anchors
        serials = s.serials
        ids = s.ids
        expandedFeatures = s.expandedFeatures
        focusedFeature = s.focusedFeature
        faceSelection = s.faceSelection
        pointDraft = s.pointDraft
        vertexDrag = nil
        routingFloorID = s.routingFloorID
        routingSelectedNodeID = s.routingSelectedNodeID
        routingSelectedEdgeID = s.routingSelectedEdgeID
        routingConnectStart = nil
        routingConnectionDrag = nil
        routingPendingAnchor = nil
        conflict = nil
        pendingClearSelection = nil
        pendingDeletion = nil
        // 열려 있던 경고창은 되돌린 상태와 아귀가 안 맞을 수 있으니 함께 닫는다.
        refreshCanvasReferences()
    }

    /// 되돌릴 수 있는 작업 단위 하나를 실행한다. **상태를 바꾸는 명령은 전부 이걸 거친다.**
    ///
    /// `coalescingKey`가 같은 명령이 연달아 오면 한 칸으로 합친다(속성 입력칸용).
    /// 실행 후 상태가 그대로면 쌓았던 칸을 도로 버린다 — 아무것도 안 바뀐 칸이 남으면
    /// cmd+z를 눌러도 화면이 안 변하는 것처럼 보인다.
    func perform(_ name: String, coalescingKey: String? = nil, _ body: () -> Void) {
        let before = snapshot
        undoStack.record(name, coalescingKey: coalescingKey, before: before)
        body()
        stampEditedTypes(before: before.features)
        // 고친 type의 시각을 같은 실행취소 칸에 넣는다. 되돌리면 시각도 함께 되돌아간다.
        refreshCanvasReferences()
        if snapshot == before, undoStack.undoName == name { undoStack.discardLast() }
    }

    var canUndo: Bool { undoStack.canUndo }
    var canRedo: Bool { undoStack.canRedo }

    var undoMenuTitle: String {
        undoStack.undoName.map { "실행취소 — \($0)" } ?? "실행취소"
    }

    var redoMenuTitle: String {
        undoStack.redoName.map { "다시실행 — \($0)" } ?? "다시실행"
    }

    func undo() {
        guard let entry = undoStack.undo(current: snapshot) else { return }
        restore(entry.snapshot)
        notify("실행취소: \(entry.name)")
    }

    func redo() {
        guard let entry = undoStack.redo(current: snapshot) else { return }
        restore(entry.snapshot)
        notify("다시실행: \(entry.name)")
    }

    // MARK: 전체 선택 해제 (명세 디버깅 7번)

    /// 선택 해제를 확인 없이 실행하지 않는 이유: 개체를 수십 개 골라 놓은 상태에서
    /// 한 번 누르면 전부 날아가는데, 선택에는 실행취소가 걸려 있지 않아 되돌릴 방법이 없다.
    enum ClearSelectionTarget { case main, auxiliary }

    @Published var pendingClearSelection: ClearSelectionTarget?

    /// 지금 확인 대상이 되는 선택의 개수. 팝업 문구와 버튼 활성화가 같은 값을 본다.
    func selectionCount(_ target: ClearSelectionTarget) -> Int {
        switch target {
        case .main: return selection.selected.count
        case .auxiliary: return auxiliarySelection.count
        }
    }

    func requestClearSelection(_ target: ClearSelectionTarget) {
        guard selectionCount(target) > 0 else { return }
        pendingClearSelection = target
    }

    func confirmClearSelection() {
        switch pendingClearSelection {
        case .main:
            perform("전체 선택 해제") { selection.clear() }
        case .auxiliary:
            auxiliarySelection = []
            // 보조 개체 창의 선택은 스냅샷 대상이 아니다 — 창을 닫으면 어차피 사라지는
            // 임시 상태라, 실행취소 칸을 잡아먹기만 하고 되돌릴 가치가 없다.
        case nil:
            break
        }
        pendingClearSelection = nil
    }

    func cancelClearSelection() { pendingClearSelection = nil }

    // MARK: 보조 개체 제외 (명세 디버깅 6번)

    /// 전용 창. Anchor 화면과 같은 이유로 시트가 아니라 전체 화면 전환이다 —
    /// 도면 전체를 훑으며 수십 개를 골라내는 작업이라 화면이 넓어야 한다.
    // MARK: 다각형 선택 (신기능 5항 + 5-4 전환)

    @Published var faceSelection: Set<String> = [] {
        didSet { invalidateRenderStates() }
    }

    @Published var polygonWorkMode: PolygonWorkMode = .include

    /// 점 기준 진행률의 분모(보조 개체를 포함한 전체 점 수, #21).
    @Published var totalPointCount = 0
    /// 고를 수 있는 점(보조 제외 뺀 꼭짓점·끝점·교차점). 점 단위 편집이 이 점에 붙는다.
    @Published var snapPoints: [SnapPointExtractor.SnapPoint] = []
    var snapPointIndex = SnapPointGrid()
    /// 점 기준 진행률의 분자 — 태깅된 점 수.
    @Published var taggedPointCount = 0
    /// 점 단위로 그린 feature가 덮은 도면 개체. 전체 진행률의 '저장'에 들어간다(`refreshPointProgress`).
    @Published var pointCoveredObjectIDs: Set<VectorObjectID> = []
    /// 지금 화면의 면·점이 어떤 열쇠로 계산된 것인가. `nil`이면 아직 계산 전이다.
    var derivedKey: DerivedGeometryKey?
    /// 마지막으로 반영한 면·점. 다음 계산이 점을 재사용할 수 있는지 판단하는 데 쓴다.
    var lastDerivedGeometry: DerivedGeometry = .empty
    var derivedTask: Task<Void, Never>?
    var derivedToken = UUID()
    /// 점·면 계산의 진행률 팝업 id.
    var derivedLongTask: UUID?
    @Published var isComputingDerivedGeometry = false

    // MARK: 점 단위 편집 상태 (#21)

    /// 레이어의 작업 방식. 기본은 점 단위다.
    @Published var layerEditMode: LayerEditMode = .point
    /// 작성 중인 도형. 실행취소 대상이다(점 추가·삭제·이동을 cmd+z로 되돌린다).
    @Published var pointDraft = PointDraft()
    /// 우측 패널에서 MultiPolygon으로 지정해 새 다각형을 받고 있는 feature. 화면 상태라 저장하지 않는다.
    @Published var multiPolygonTargetID: FeatureGroupID?
    /// 면 단위에서 면을 둘러싸는 경계를 지금 레이어로 볼지 모든 레이어로 볼지.
    @Published var faceBoundaryScope: FaceBoundaryScope = .currentLayer
    /// unit 레이어에서 빈틈(빨간 점무늬)·겹침(빨간 빗금)을 도면에 표시할지.
    @Published var showUnitCoverage = false
    var unitCoverageCache: UnitCoverageCache?
    /// 저장된 feature로 찾은 면. 화면을 그릴 때마다 읽으므로 경계가 같으면 다시 찾지 않는다.
    var savedFaceCache: SavedFeatureFaceCache?
    /// fixture 점 단위에서 '닫을 때 똑같이 생긴 개체에도 저장'. 켜면 쌍둥이 자리마다 개별 fixture를 함께 만든다.
    @Published var savesFixtureTwins = false
    /// 찍은 점 → 쌍둥이 자리. 화면을 그릴 때마다 읽으므로 점과 도면 점이 같으면 다시 찾지 않는다.
    var fixtureTwinCache: FixtureTwinCache?
    /// 펼친 unit과 겹치는 unit. 화면을 그릴 때마다 읽으므로 펼친 것과 unit 링이 같으면 다시 계산하지 않는다.
    var unitOverlapCache: UnitOverlapCache?
    /// unit 레이어 점 단위의 도구(그리기·보조 선분·자르기·점 끼우기). 바꾸면 작성 중인 점을 비운다.
    @Published var unitPointTool: UnitPointTool = .draw {
        didSet { if oldValue != unitPointTool { cancelPointDraft() } }
    }
    /// '꼭짓점 이동' 모드. 꺼져 있으면(고정) 드래그는 화면 이동이다.
    @Published var isVertexMoveEnabled = false
    /// 꼭짓점을 끄는 중이면 그 대상과 지금 위치. 놓을 때 한 번만 실행취소 칸을 쌓는다.
    @Published var vertexDrag: VertexDrag?
    /// 자체점검에서는 파생 기하를 그 자리에서 계산한다 — 결과를 바로 확인해야 하기 때문이다.
    /// 앱에서는 백그라운드에서 계산한다.
    var derivedGeometryInline = AppEnvironment.isRunningSelfTests


    /// 폴리곤 type 레이어에서 안내를 한 번 띄운다(신기능 5-2). 닫으면 `nil`.
    @Published var closedPolygonNotice: String?

    @Published var showCurvedScreen = false
    @Published var showAuxiliaryScreen = false

    // MARK: '문 임시로 닫기' 창 상태 (신기능 3항)

    @Published var showDoorClosureScreen = false
    @Published var doorDraftPoints: [LocalPoint] = []

    var doorSnapCache: [SnapPointExtractor.SnapPoint] = []
    /// 찍을 수 있는 점 목록. 도면이 바뀔 때만 다시 만든다 —
    /// 매 프레임 계산하면 쌍둥이 인덱스에서 겪은 정지가 그대로 재현된다(엔진 디버깅 1-1).

    /// 창 안에서만 쓰는 선택. 메인 화면의 `selection`과 섞으면 창을 닫았을 때
    /// 엉뚱한 개체가 선택된 채로 남는다.
    @Published var auxiliarySelection: Set<VectorObjectID> = [] {
        didSet {
            if !canShowTwins { showTwinsOnly = false }
            if auxiliarySelection.isEmpty, marqueeSubtracts { marqueeSubtracts = false } // ✅ 2026-08-30
            // 선택이 비어 버튼이 비활성으로 바뀌면 효과도 같이 꺼야 한다.
            // 남겨두면 켜져 있는데 끌 버튼이 없는 상태가 된다 — 「디버깅 완료」 2번(접으면 못 펴는 사이드바)과 같은 함정이다.
        }
    }

    /// '똑같이 생긴 개체 모두 표시'를 쓸 수 있는 조건.
    ///
    /// **선택이 하나라도 있으면 쓸 수 있다(엔진 디버깅 1-2번, 2026-08-25).**
    /// 뷰 디버깅 11번에서는 `count == 1`로 제한했었다 — 여럿을 고르면 서로 다른 쌍둥이 그룹이
    /// 섞여 100%로 뜨는 개체가 합집합이 되고 "무엇과 똑같은가"의 기준이 사라진다는 이유였다.
    /// **그 판단을 사용자 요청으로 뒤집었다.** 합집합이 되는 것 자체는 사실이지만, 실제 작업은
    /// "치수 숫자 3종을 한꺼번에 골라 통째로 빼기"처럼 여러 그룹을 동시에 다루는 쪽이 훨씬 흔했다.
    /// 대신 **합집합이라는 사실을 화면이 말하게** 했다 — 버튼 라벨이 `쌍둥이 N그룹 · M개 표시 중`으로
    /// 그룹 수를 함께 보여준다(`TwinToggleText`). 기준이 사라지는 게 문제라면 기준을 표시하면 된다.
    var canShowTwins: Bool { !auxiliarySelection.isEmpty }

    /// 지금 선택이 걸쳐 있는 쌍둥이 그룹의 수. 버튼 라벨이 "몇 그룹의 합집합인지"를 밝히는 데 쓴다.
    /// 선택된 개체들의 **고유 키 개수**라, 같은 그룹에서 여러 개를 골라도 1로 센다.
    var selectedTwinGroupCount: Int {
        Set(auxiliarySelection.compactMap { twinKeyByObject[$0] }).count
    }

    /// 우측 목록에서 고른 쌍둥이 그룹. 정한 그룹만 100%, 나머지는 75%로 표시한다.
    @Published var focusedTwinKey: String?

    /// 상단 바의 '똑같이 생긴 개체 모두 표시' 상태.
    @Published var showTwinsOnly = false

    struct TwinGroup: Identifiable {
        var id: String { key }
        let key: String
        let memberIDs: [VectorObjectID]
        let sample: VectorObject

        var count: Int { memberIDs.count }
        var label: String { "\(sample.shapeSummary) × \(count)" }
    }

    // MARK: 쌍둥이 인덱스 (엔진 디버깅 1-1번)
    //
    // `VectorObject.twinKey`는 **개체의 모든 점을 문자열로 이어 붙이는** 무거운 계산이다.
    // 예전에는 `twinGroups`·`twins(of:)`가 계산 프로퍼티라 불릴 때마다 도면 전체의 키를 새로 만들었고,
    // 캔버스가 `auxiliaryOpacity(for:)`를 **개체마다** 부르면서 그 안에서 또 `twins(of:)`를 불렀다.
    // 결과는 매 프레임 O(N² × 점 개수) — 개체가 수천 개인 실도면에서는 그대로 멈춘 것처럼 보인다.
    // ('똑같이 생긴 개체 모두 보기'를 누르면 커서가 로딩 상태에서 안 돌아오던 증상)
    //
    // 키는 **도면이 바뀔 때만** 바뀐다. 그래서 도면을 적재하는 순간 한 번 만들어 두고,
    // 이후에는 사전 조회만 한다.

    @Published private(set) var twinGroups: [TwinGroup] = []
    /// 모양·스타일이 완전히 같은 개체를 묶은 목록. 많은 것부터 보여준다 —
    /// 보조 개체는 대개 같은 모양이 수십 개씩 반복되므로 위쪽 몇 개가 곧 작업 대상이다.

    private(set) var twinKeyByObject: [VectorObjectID: String] = [:]
    private var twinMembersByKey: [String: Set<VectorObjectID>] = [:]

    func clearDocumentIndexesForLoading() {
        objectIDsByAttributeKey = [:]
        spatialIndex = SpatialIndex()
        twinKeyByObject = [:]; twinMembersByKey = [:]; twinGroups = []
    }

    func installPreparedIndexes(_ prepared: PreparedLevelDrawing) {
        document = prepared.document
        renderCache.install(prepared.renderEntries)
        objectIDsByAttributeKey = prepared.attributeIndex
        spatialIndex = prepared.spatialIndex
        twinKeyByObject = prepared.twinKeys
        twinGroups = prepared.twinGroups.map { TwinGroup(key: $0.key, memberIDs: $0.memberIDs, sample: $0.sample) }
        twinMembersByKey = Dictionary(uniqueKeysWithValues: prepared.twinGroups.map { ($0.key, Set($0.memberIDs)) })
        derivedTask?.cancel(); derivedTask = nil
        applyDerivedGeometry(prepared.derived, key: prepared.input.derivedKey)
        invalidateRenderStates()
    }

    /// 도면이 바뀔 때 한 번만 돈다. `document`의 `didSet`이 유일한 호출자다 —
    /// 다른 곳에서 부르면 "언제 최신인가"가 흐려져 예전의 매 프레임 재계산으로 되돌아간다.
    private func rebuildDocumentIndexes() {
        rebuildTwinIndex()
        doorSnapCache = []
        renderCache.invalidateAll()
        invalidateRenderStates()
        objectIDsByAttributeKey = Dictionary(grouping: document?.objects ?? [],
                                             by: { $0.style.attributeKey })
            .mapValues { $0.map(\.id) }
        spatialIndex = SpatialIndex(objects: document?.objects ?? [],
                                    canvasSize: document?.canvasSize ?? .zero)
        refreshOverlap()
        refreshOpenRingGaps()
        faceSelection = []
        derivedKey = nil
        scheduleDerivedGeometryRefresh()
        // 면·점은 백그라운드에서 계산한다(#21). 자체점검에서는 그 자리에서 계산한다.
        // 예전에는 끝점·교차점을 '문 임시로 닫기' 창에 들어갈 때만 메인 스레드에서 만들었다.
        // 면 자르기를 격자로 바꾸고(5초 → 0.03초) 계산을 메인 스레드에서 뺀 뒤로는
        // 도면을 열 때 함께 만들어도 앱이 멈추지 않는다.
    }

    private func rebuildTwinIndex() {
        twinKeyByObject = [:]
        twinMembersByKey = [:]
        twinGroups = []
        guard let doc = document else { return }

        var buckets: [String: [VectorObject]] = [:]
        for o in doc.objects {
            let key = o.twinKey
            twinKeyByObject[o.id] = key
            buckets[key, default: []].append(o)
        }
        twinMembersByKey = buckets.mapValues { Set($0.map(\.id)) }
        twinGroups = buckets.compactMap { key, objects -> TwinGroup? in
            guard let first = objects.first else { return nil }
            return TwinGroup(key: key, memberIDs: objects.map(\.id), sample: first)
        }
        .sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.sample.ordinal < $1.sample.ordinal
        }
    }

    /// 선택한 개체들과 똑같이 생긴 개체 전부(자기 자신 포함). 사전 조회뿐이라 값싸다.
    func twins(of ids: Set<VectorObjectID>) -> Set<VectorObjectID> {
        guard document != nil else { return ids }
        let keys = Set(ids.compactMap { twinKeyByObject[$0] })
        var out = Set<VectorObjectID>()
        for key in keys { out.formUnion(twinMembersByKey[key] ?? []) }
        return out
    }

    /// 같은 자리에 같은 모양으로 겹쳐 그려진 개체(자기 자신 포함). **스타일은 보지 않는다.**
    /// 실도면(포스텍 도서관 3층)은 PDF에서 바꾼 SVG라 면(fill만)과 테두리(stroke만)가 같은 모양의 별개 path로
    /// 겹쳐 있다(겹친 묶음 8,111개 중 6,867개가 스타일이 다르다). 면은 안쪽 클릭으로 잡히므로 면만 제외되고,
    /// 작업 화면에 보이는 테두리 path는 그대로 남아 "지정했는데 안 지워진다"로 보였다.
    func stackedTwins(of id: VectorObjectID) -> Set<VectorObjectID> {
        guard let doc = document, let target = doc.object(id) else { return [id] }
        let box = target.boundingBox
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }
        // `twinKey`와 같은 0.01 단위 허용치다. SVG 파서의 부동소수 오차를 흡수한다.
        func sameShape(_ o: VectorObject) -> Bool {
            let a = o.geometry.subpaths, b = target.geometry.subpaths
            guard a.count == b.count else { return false }
            for (s, t) in zip(a, b) {
                guard s.isClosed == t.isClosed, s.points.count == t.points.count else { return false }
                for (p, q) in zip(s.points, t.points) where !near(p.x, q.x) || !near(p.y, q.y) { return false }
            }
            return true
        }
        var out: Set<VectorObjectID> = [id]
        for o in doc.objects {
            let b = o.boundingBox
            guard near(b.minX, box.minX), near(b.minY, box.minY),
                  near(b.maxX, box.maxX), near(b.maxY, box.maxY), sameShape(o) else { continue }
            out.insert(o.id)
        }
        // 상자부터 견줘 대부분을 걸러낸다. 클릭 한 번에 한 번 도는 것이라 6만 개도 수 ms다.
        return out
    }

    // MARK: 우측 사이드바 목록 분리 (엔진 디버깅 1-3번, 2026-08-25)
    //
    // 예전 사이드바는 `twinGroups.filter { $0.count > 1 || 제외된 게 있으면 }` 하나뿐이라
    // **쌍둥이가 없는 개체(그룹 크기 1)는 아예 안 보였다.** 도면에 딱 하나만 있는 방위표·범례처럼
    // 반복되지 않는 보조 개체는 목록에서 찾을 방법이 없어 도면을 눈으로 훑어야 했다.
    //
    // 두 섹션을 위아래로 쌓는 대신 **세그먼트 전환**을 골랐다. 개별 개체는 실도면에서 수백 개까지
    // 늘어나는데, 위아래로 쌓으면 그 목록이 쌍둥이 그룹 목록을 스크롤 밖으로 밀어낸다.
    // 두 목록은 답하는 질문도 다르다 — 그룹 목록은 "무엇이 반복되는가", 개별 목록은 "무엇이 안 묶였는가".
    // 세그먼트는 한 번에 하나만 전체 높이를 쓰고, 탭 이름에 개수를 달아 반대쪽 규모도 같이 알려준다.

    enum AuxiliarySidebarTab: String, CaseIterable, Identifiable {
        case twinGroups
        case soloObjects
        var id: String { rawValue }
        var title: String {
            switch self {
            case .twinGroups:  return "똑같이 생긴 그룹"
            case .soloObjects: return "개별 개체"
            }
        }
    }

    @Published var auxiliarySidebarTab: AuxiliarySidebarTab = .twinGroups

    /// 탭별 목록. **뷰가 아니라 여기서 나눈다** — 어느 개체가 어느 탭에 뜨는지는 판정 규칙이라
    /// `--selftest`가 확인할 수 있어야 한다. 뷰의 `filter`에 박아 두면 확인할 방법이 없다.
    ///
    /// 두 목록은 서로 **겹치지 않고 합치면 전부**가 된다(크기 2 이상 / 크기 1). 겹치게 두면
    /// 같은 개체가 두 탭에 나와 "이건 그룹인가 개별인가"가 흐려진다.
    func auxiliarySidebarGroups(_ tab: AuxiliarySidebarTab) -> [TwinGroup] {
        switch tab {
        case .twinGroups:  return twinGroups.filter { $0.count > 1 }
        case .soloObjects: return twinGroups.filter { $0.count == 1 }
        }
    }

    /// 제외 대상으로 지정된 쌍둥이 그룹. '모든 보조 개체 제외'가 이 목록을 쓴다.
    var markedTwinGroups: [TwinGroup] {
        twinGroups.filter { group in
            group.memberIDs.contains { auxiliary.isExcluded($0) }
        }
    }

    func enterAuxiliaryScreen() {
        guard document != nil else {
            notify("먼저 도면을 여세요.", isError: true)
            return
        }
        selection.clear()
        auxiliarySelection = []
        focusedTwinKey = nil
        showTwinsOnly = false
        marqueeSubtracts = false // ✅ 2026-08-30 — 모드는 화면을 넘어가지 않는다.
        showAuxiliaryScreen = true
    }

    func exitAuxiliaryScreen() {
        showAuxiliaryScreen = false
        auxiliarySelection = []
        focusedTwinKey = nil
        showTwinsOnly = false
        marqueeSubtracts = false // ✅ 2026-08-30
        scheduleDerivedGeometryRefresh()
        // ✅ 2026-08-30 — 창 안에서 미뤄 둔 셈을 여기서 한 번에 치른다.
    }

    /// 상단 바 '보조 개체로 지정'. 고른 개체만 제외한다.
    func markSelectedAsAuxiliary() {
        guard !auxiliarySelection.isEmpty else { return }
        let n = auxiliarySelection.subtracting(auxiliary.excluded).count
        perform("보조 개체 지정") { auxiliary.exclude(auxiliarySelection) }
        auxiliarySelection = []
        // 지정이 끝난 개체를 골라 둔 채로 두면 다음 개체를 고를 때 이전 것이 딸려 와
        // 이미 지정된 것을 또 지정하게 된다. 지정은 이 창에서 선택의 종착점이므로 여기서 비운다.
        notify("개체 \(n)개를 보조 개체로 지정했습니다.")
    }

    /// 상단 바 '똑같이 생긴 개체 모두 지정'. 선택한 것과 같은 모양 전부를 한 번에 제외한다.
    func markTwinsAsAuxiliary() {
        guard canShowTwins else { return }
        // 표시와 같은 조건을 건다. 화면에 100%로 보이는 것과 지정되는 것이 갈라지면 안 된다.
        let all = twins(of: auxiliarySelection)
        let n = all.subtracting(auxiliary.excluded).count
        perform("똑같이 생긴 개체 보조 지정") { auxiliary.exclude(all) }
        auxiliarySelection = []
        // `markSelectedAsAuxiliary`와 같은 이유로 비운다(엔진 디버깅 1-4번) — 지정은 이 창에서
        // 선택의 종착점이다. 이쪽은 **한 번에 그룹 전체가 나가므로 더 심하다**: 방금 지정한 쌍둥이
        // 수십 개가 골라진 채 남으면 다음 개체를 고를 때 그게 전부 딸려 와 `N개 선택`이 실제 작업
        // 대상과 완전히 어긋난다. 선택이 비면 `didSet`이 `showTwinsOnly`도 같이 꺼 준다.
        //
        // `focusedTwinKey`는 **일부러 안 건드린다.** 우측 목록에서 그룹을 지목해 들어온 흐름이면
        // 방금 무엇을 지정했는지가 화면에 100%로 남아 있어야 결과를 확인할 수 있다.
        notify("똑같이 생긴 개체까지 \(n)개를 보조 개체로 지정했습니다.")
    }

    func unmarkSelectedAsAuxiliary() {
        guard !auxiliarySelection.isEmpty else { return }
        let n = auxiliarySelection.intersection(auxiliary.excluded).count
        perform("보조 지정 풀기") { auxiliary.include(auxiliarySelection) }
        notify(n > 0 ? "개체 \(n)개의 보조 지정을 풀었습니다." : "지정된 보조 개체가 없습니다.")
    }

    /// 우측 사이드바 '모든 보조 개체 제외'.
    /// 지정된 개체 하나라도 있는 쌍둥이 그룹은 **그룹 전체**를 제외한다(명세 디버깅 6번).
    func excludeAllAuxiliary() {
        let groups = markedTwinGroups
        guard !groups.isEmpty else {
            notify("먼저 보조 개체를 지정하세요.", isError: true)
            return
        }
        var all = Set<VectorObjectID>()
        for g in groups { all.formUnion(g.memberIDs) }
        let added = all.subtracting(auxiliary.excluded).count
        perform("모든 보조 개체 제외") { auxiliary.exclude(all) }
        notify("보조 개체 그룹 \(groups.count)개, 개체 \(all.count)개를 제외했습니다(신규 \(added)개).")
    }

    func clearAuxiliary() {
        perform("보조 개체 제외 전체 해제") { auxiliary.clear() }
        notify("모든 보조 개체 제외를 해제했습니다.")
    }

    /// 지금 100%로 보여야 할 개체. `nil`이면 강조 자체가 꺼져 있어 전부 100%다.
    ///
    /// **캔버스는 이 값을 그리기 루프 바깥에서 한 번만 받아 쓴다.** 개체마다 다시 물으면
    /// 개체 수만큼 집합을 새로 만들게 되고, 그것이 화면이 멈추던 원인이었다(엔진 디버깅 1-1번).
    var auxiliaryHighlightedIDs: Set<VectorObjectID>? {
        if let key = focusedTwinKey { return twinMembersByKey[key] ?? [] }
        if showTwinsOnly, canShowTwins { return twins(of: auxiliarySelection) }
        return nil
    }

    /// ✅ 2026-08-30 신설 — '똑같이 생긴 개체 모두 지정'을 누르면 **함께 보조 개체가 될** 개체들.
    ///
    /// 종전에는 쌍둥이가 opacity(100% vs 나머지 75%)로만 드러났다. 옅기 차이는 배경이 밝을 때
    /// 거의 읽히지 않아, 지금 무엇이 딸려 나가는지 눈으로 셀 수 없었다.
    ///
    /// 두 가지를 뺀다.
    /// ① **직접 고른 것** — 이미 선택색(파랑)으로 드러난다. 같은 색을 겹쳐 칠하면 '내가 고른 것'과
    ///    '딸려 오는 것'의 경계가 사라져 이 표시의 목적 자체가 없어진다.
    /// ② **이미 제외된 것** — 버튼을 눌러도 상태가 바뀌지 않으므로 '앞으로 빠질 것'이 아니다.
    ///
    /// 대상 조건(`showTwinsOnly && canShowTwins`)은 지정 버튼이 뜨는 조건과 같다.
    /// 화면에 색으로 보이는 것과 실제로 지정되는 것이 갈라지면 안 되기 때문이다.
    var auxiliaryTwinPendingIDs: Set<VectorObjectID> {
        guard showTwinsOnly, canShowTwins else { return [] }
        return twins(of: auxiliarySelection)
            .subtracting(auxiliarySelection)
            .subtracting(auxiliary.excluded)
    }

    /// 창 안 표시 배율. 75% 요구가 여러 곳에 흩어지지 않게 한 곳에서 계산한다.
    /// 한 개체만 물을 때 쓴다 — 여러 개를 그릴 때는 `auxiliaryHighlightedIDs`를 한 번 받아 쓸 것.
    func auxiliaryOpacity(for object: VectorObject) -> Double {
        AuxiliaryOpacity.value(for: object.id, highlighted: auxiliaryHighlightedIDs)
    }

    // MARK: Opening 선행 태깅과 문 빌려주기 (명세 10항)

    /// 이 개체를 지금 레이어가 '빌려' 쓸 수 있는가.
    /// 빌릴 수 있는 조건은 세 가지가 모두 참일 때뿐이다:
    /// ① 지금 연 레이어가 닫힌 폴리곤을 요구하는 type이고 ② 그 개체의 주인이 opening feature이며
    /// ③ 지금 레이어가 opening 자신이 아니다.
    func canBorrow(_ object: VectorObjectID) -> Bool {
        guard let active = layers.activePropertyType, active.canBorrowOpenings else { return false }
        guard let ownerID = ownership.ownerOf(object),
              features.feature(ownerID)?.featureType == .opening else { return false }
        return true
    }

    /// 지금 화면에서 '빌려온 것'으로 보여야 하는 개체인가(명세 10-2-2).
    /// **지금 펼친 feature가 빌린 것**과 **지금 골라 놓은 것 가운데 빌릴 수 있는 것** 둘 다 해당한다.
    /// 앞은 이미 빌린 상태, 뒤는 저장하면 빌리게 될 상태 — 사용자에게는 둘 다 "내 것이 아닌 문"이다.
    func isBorrowedHere(_ id: VectorObjectID) -> Bool {
        if expandedFeatures.contains(where: { borrow.objects(borrowedBy: $0).contains(id) }) {
            return true
        }
        // 카드를 여러 개 펼 수 있으므로 **펼친 것 전부**를 본다.
        // 하나만 보면 옆 카드가 빌린 문이 소유한 것처럼 보인다.
        return selection.selected.contains(id) && canBorrow(id)
    }

    /// 지금 선택 중인 것 가운데 빌려온 opening.
    var borrowedInSelection: Set<VectorObjectID> {
        selection.selected.filter { canBorrow($0) }
    }

    var hasAnyOpeningFeature: Bool {
        !features.features(ofType: .opening).isEmpty
    }

    /// 명세 10-1-3: 'opening 태깅 완료' 선언. 자동 판정이 불가능해 사용자가 직접 누른다.
    func declareOpeningComplete() {
        let hadOpening = hasAnyOpeningFeature
        perform("opening 태깅 완료") { openingGate.declareComplete(hasAnyOpening: hadOpening) }
        if hadOpening {
            notify("opening 태깅을 완료했습니다. 다른 property type을 열 수 있습니다.")
        } else {
            notify("opening을 하나도 만들지 않고 진행합니다. 문이 있는 도면이라면 방 폴리곤이 닫히지 않습니다.",
                   isError: true)
            // 명세 10-1-5: 문 없는 도면도 허용하되 경고를 한 번 띄운다.
        }
    }

    /// 명세 10-1-4: 완료 선언 되돌리기. 이미 저장한 다른 feature는 건드리지 않는다.
    func reopenOpeningTagging() {
        perform("opening 다시 편집") {
            openingGate.reopen()
            layers.addPropertyTypeLayer(.opening)
            selection.clear()
        }
        notify("opening 레이어를 다시 엽니다. 빠뜨린 문을 추가하세요.")
    }

    /// 이 feature의 링이 닫히는지(명세 10-4). **빌려온 opening까지 넣고 판정한다** —
    /// 문을 빌리는 목적 자체가 그 선분으로 벽의 빈자리를 메우는 것이라, 빼고 재면 늘 열려 있다.
    func ringClosure(of feature: FeatureGroup) -> RingClosureValidator.Result? {
        guard let doc = document else { return nil }
        guard feature.featureType.requiresClosedRing else { return nil }
        // 닫힌 폴리곤이 필요 없는 type은 판정 자체가 무의미하다(amenity는 점 하나다).
        guard !feature.isPointDrawn else { return nil }
        // #21: 점으로 그린 도형은 시작점을 다시 눌러 닫았으므로 링이 정의상 닫혀 있다.
        // 구성원 개체가 없어 개체로 재면 '전부 열림'으로 잘못 나온다.

        let ids = feature.memberIDs.union(borrow.objects(borrowedBy: feature.id))
        let segments = ids.compactMap { doc.object($0) }
            .flatMap { geometry(for: $0).lineSegments() }
        return RingClosureValidator.validate(segments: segments, tolerance: overlapTolerance)
        // 겹침 판정과 같은 허용 오차를 쓴다. 도면 크기에 비례하므로 큰 도면에서도 같은 기준이 된다.
    }

    /// 링이 닫히지 않은 feature. 내보내기 직후 경고가 쓴다.
    /// `type`을 주면 그 레이어 것만 본다 — 내보내기는 한 type씩 하므로
    /// 다른 레이어의 열린 링까지 알리면 지금 만든 파일과 무관한 경고가 섞인다.
    func openRingFeatures(type: IMDFFeatureType? = nil) -> [(FeatureGroup, RingClosureValidator.Result)] {
        features.features
            .filter { !$0.isInTrash && (type == nil || $0.featureType == type) }
            .compactMap { f in
                guard let r = ringClosure(of: f), !r.isClosed else { return nil }
                return (f, r)
            }
    }

    // MARK: property type 레이어

    func selectPropertyType(_ type: IMDFFeatureType) {
        if type.isMetadataOnly {
            openMetadataEditor(type)
            return
            // 도형이 없는 type은 캔버스에서 할 일이 없다. 레이어 대신 정보 입력 창을 연다.
        }
        guard type == .opening || type == .footprint || openingGate.allowsOtherTypes else {
            notify("opening을 먼저 태깅해야 합니다. 문을 먼저 확정해야 방 폴리곤을 닫을 수 있습니다.",
                   isError: true)
            // 명세 10-1-2의 안내 문구 그대로.
            return
        }
        perform("\(type.displayName) 레이어") {
            layers.addPropertyTypeLayer(type)
            selection.clear()
            layers.isolatedFeature = nil
            layers.excludedFeature = nil
        }
        enterPolygonWorkIfNeeded(type)
    }

    /// 레이어를 열 때 작업 방식을 정한다(#21).
    ///
    /// **모든 레이어의 기본은 점 단위 편집이다.** 폴리곤 type(footprint 제외)은 상단바에서
    /// 면 단위로 바꿀 수 있다. 면은 층을 불러올 때 백그라운드에서 이미 찾아 두었으므로
    /// 여기서 다시 계산하지 않는다 — 예전에는 여기서 메인 스레드가 약 5초 멈췄다.
    func enterPolygonWorkIfNeeded(_ type: IMDFFeatureType) {
        cancelPointDraft()
        layerEditMode = .point
        polygonWorkMode = .include
        faceSelection = []
        closedPolygonNotice = nil
    }

    /// 점 단위·면 단위·선 단위를 오간다. 면 단위는 polygon·multipolygon type(footprint 제외), 선 단위는 fixture에서만 된다.
    func setLayerEditMode(_ next: LayerEditMode) {
        guard next != layerEditMode else { return }
        if layerEditMode == .object { selection.clear() }
        // 선 단위에서 고른 개체는 다른 모드에서 쓸 곳이 없다. 남겨 두면 보이지 않는 선택이 다음 동작에 섞인다.
        if next == .object {
            guard let type = layers.activePropertyType, type.allowsObjectSelection else {
                notify("선 단위 선택은 fixture 레이어에서만 쓸 수 있습니다.", isError: true)
                return
            }
            cancelPointDraft()
            layerEditMode = .object
            faceSelection = []
            closedPolygonNotice = nil
            notify("선 단위: 도면 개체를 클릭하거나 드래그해 고른 뒤 'Feature로 저장'을 누르면 \(type.displayName) 하나로 저장합니다.")
        } else if next == .face {
            guard let type = layers.activePropertyType, type.allowsFaceSelection else {
                notify("면 단위 선택은 polygon·multipolygon type에서만 쓸 수 있습니다. footprint는 점으로 그립니다.",
                       isError: true)
                return
            }
            cancelPointDraft()
            layerEditMode = .face
            polygonWorkMode = .include
            faceSelection = []
            closedPolygonNotice = String(
                format: "모든 닫힌 다각형을 표시했습니다. %@의 Feature로 저장할 다각형 또는 제외할 다각형을 선택하세요. 제외할 다각형이 너무 많이 표시된다면, 보조 개체 제외 창에서 불필요한 선분을 제외해 보세요.",
                type.displayName)
            // 안내가 가리키는 처방(불필요한 선분 제외)이 이 기능의 실패 모드에 대한 답이다 —
            // 치수선·해치가 남아 있으면 방이 아닌 자투리가 수백 개 잡힌다.
        } else {
            layerEditMode = .point
            faceSelection = []
            closedPolygonNotice = nil
        }
    }

    // MARK: feature 그룹 (명세 6항)

    func createFeature() {
        guard let type = layers.activePropertyType else {
            notify("먼저 좌측에서 property type을 선택해 레이어를 만드세요.", isError: true)
            return
        }
        guard !selection.selected.isEmpty else { return }
        let lent = borrowedInSelection
        let owned = selection.selected.subtracting(lent)
        // 빌려온 opening은 **소유 주장에서 뺀다**(명세 10-3-2). 소유권이 옮겨 가면 opening 레이어에서
        // 사라지고 진행률 분자에 두 번 세어진다. 좌표 계산에만 참여시키고 주인은 그대로 둔다.
        guard !owned.isEmpty else {
            notify("빌려온 opening만으로는 feature를 만들 수 없습니다. 방을 이루는 개체를 함께 고르세요.",
                   isError: true)
            // opening만 골라 저장하면 아무것도 소유하지 않는 빈 feature가 생긴다.
            return
        }

        let serial = nextFeatureSerial(for: type)
        var f = FeatureGroup(featureType: type, serialNumber: serial, memberIDs: owned)
        for field in PropertySchema.fields(for: type) { f.properties[field.key] = .null }
        let memberTwins = type == .fixture ? freeFixtureMemberTwins(of: owned) : []
        // fixture는 똑같이 생긴 자리도 그 자리 도면 개체로 함께 저장한다(2026-10-19 요청). 윤곽선이 자리마다 도면을 따른다.
        var twinsAdded = 0
        // 일련번호는 `perform` 바깥에서 이미 뽑혔지만, 스냅샷이 `serials`도 담으므로
        // 되돌리면 번호도 함께 돌아간다 — 실행취소 후 재저장해도 번호가 건너뛰지 않는다.
        perform("\(serial) 저장") {
            do {
                try ownership.claim(owned, for: f.id)
                features.insert(f)
                if !lent.isEmpty { borrow.borrow(lent, by: f.id) }
                twinsAdded = insertFixtureMemberTwins(memberTwins, properties: f.properties)
                expandedFeature = f.id
                selection.clear()
                let together = twinsAdded > 0 ? " 똑같이 생긴 \(twinsAdded)곳도 함께 저장했습니다." : ""
                let closure = features.feature(f.id).flatMap { ringClosure(of: $0) }
                if let c = closure, !c.isClosed {
                    notify(gapMessage(serial: serial, result: c) + together, isError: true)
                    // 저장은 막지 않는다. 도면을 고쳐 다시 저장하는 것이 정상 흐름이고,
                    // 저장 자체를 막으면 작업하던 선택이 통째로 날아간다.
                } else {
                    notify((lent.isEmpty
                            ? "\(serial) 로 저장했습니다."
                            : "\(serial) 로 저장했습니다. opening \(lent.count)개를 빌려 폴리곤을 닫았습니다.") + together)
                }
            } catch {
                notify("이미 다른 feature에 속한 개체가 포함되어 있습니다.", isError: true)
            }
        }
    }

    func addToExistingFeature(_ fid: FeatureGroupID) {
        guard !selection.selected.isEmpty else { return }
        perform("기존 feature에 추가") {
            do {
                try ownership.claim(selection.selected, for: fid)
                let ids = selection.selected
                features.update(fid) { $0.memberIDs.formUnion(ids) }
                selection.clear()
                notify("기존 feature에 추가했습니다.")
            } catch {
                notify("이미 다른 feature에 속한 개체가 포함되어 있습니다.", isError: true)
            }
        }
    }

    func ungroup(_ fid: FeatureGroupID) {
        guard let f = features.feature(fid) else { return }
        perform("\(f.serialNumber) 그룹 해제") {
            ownership.releaseAll(of: fid)
            borrow.giveBackAll(of: fid)
            // 빌린 쪽이 사라지면 대여도 끝난다. 안 지우면 없는 feature가 opening을 붙잡고 있어
            // 휴지통 경고(명세 10-4-4)가 유령 일련번호를 띄운다.
            ids.retire(fid)
            features.remove(fid)
            expandedFeatures.remove(fid)
            if focusedFeature == fid { focusedFeature = expandedFeatures.first }
            if layers.isolatedFeature == fid { layers.isolatedFeature = nil }
            if layers.excludedFeature == fid { layers.excludedFeature = nil }
        }
        // `ids.retire`도 스냅샷에 들어가므로 되돌리면 폐기 대장에서 UUID가 되살아난다.
        // 그러지 않으면 실행취소 한 번에 스펙이 요구하는 "id 유지"가 깨진다.
        notify("\(f.serialNumber) 그룹을 해제했습니다.")
    }

    func trash(_ fid: FeatureGroupID) {
        guard let f = features.feature(fid) else { return }

        // 명세 10-4-4: 빌려 쓰는 쪽이 있으면 먼저 알린다. 지우고 나서 알리면 이미 폴리곤이 열렸다.
        if f.featureType == .opening {
            let affected = Set(f.memberIDs.flatMap { borrow.borrowers(of: $0) })
                .compactMap { features.feature($0)?.serialNumber }
                .sorted()
            if !affected.isEmpty {
                notify("이 opening을 \(affected.joined(separator: ", "))이 사용 중입니다. 삭제하면 해당 폴리곤이 열립니다.",
                       isError: true)
            }
        }

        perform("\(f.serialNumber) 휴지통") {
            ownership.releaseAll(of: fid)
            borrow.giveBackAll(of: fid)
            features.update(fid) { $0.isInTrash = true }
            expandedFeatures.remove(fid)
            if focusedFeature == fid { focusedFeature = expandedFeatures.first }
        }
        notify("\(f.serialNumber)를 휴지통으로 보냈습니다.")
    }

    func restore(_ fid: FeatureGroupID) {
        guard let f = features.feature(fid) else { return }
        perform("\(f.serialNumber) 복원") {
            do {
                try ownership.claim(f.memberIDs, for: fid)
                features.update(fid) { $0.isInTrash = false }
                notify("\(f.serialNumber)를 복원했습니다.")
            } catch {
                notify("복원 실패 — 그 사이 다른 feature가 개체를 가져갔습니다.", isError: true)
            }
        }
    }

    func updateProperty(_ key: String, value: PropertyValue, in fid: FeatureGroupID) {
        // 입력칸은 글자 하나마다 이 함수를 부른다. 같은 (feature, 필드)로 들어오는 연속 입력은
        // 한 칸으로 합치지 않으면 이름 한 번 치는 데 실행취소가 열 칸씩 쌓인다.
        perform("\(key) 입력", coalescingKey: "property:\(fid):\(key)") {
            features.update(fid) { $0.properties[key] = value }
        }
    }

    // MARK: display point (명세 7-3-4)

    func beginDisplayPointPicking(_ fid: FeatureGroupID) {
        metadataEditorType = nil
        showBuildingManager = false
        showRoutingScreen = false; showLevelFootprintScreen = false; showMapAlignScreen = false; showAnchorScreen = false
        cancelPointDraft()
        mode = .displayPointPicking(fid)
        selection.clear()
        notify("도형 외곽 안에서 display point를 찍으세요. 상단 취소 버튼으로 종료할 수 있습니다.")
    }

    func setDisplayPoint(_ p: LocalPoint, for fid: FeatureGroupID) {
        if setGlobalDisplayPoint(p, for: fid) { return }
        guard let f = features.feature(fid), !f.isInTrash else { return }
        guard permitsDisplayPoint(p, for: f) else {
            notify("display point는 실제 도형 외곽 안에 찍어야 합니다. 구멍과 외부는 선택할 수 없습니다.", isError: true)
            return
        }
        perform("display point 지정") { features.update(fid) { $0.displayPoint = p } }
        mode = .idle
        notify("display point를 지정했습니다.")
    }

    // MARK: 선분화 (명세 8-4, 3-3)

    var selectionHasCurve: Bool {
        guard let doc = document else { return false }
        return selection.selected.contains { doc.object($0)?.isCurved == true }
    }

    var selectionAllSegmented: Bool {
        !selection.selected.isEmpty && selection.selected.allSatisfy { segmentation.isSegmented($0) }
    }

    func segmentizeSelection() {
        segmentize(selection.selected)
    }

    func segmentize(_ targets: Set<VectorObjectID>) {
        guard let doc = document, !isProjectBusy else { return }
        let jobs = targets.compactMap { id -> (VectorObjectID, PathGeometry)? in
            guard let o = doc.object(id), o.isCurved, !segmentation.isSegmented(id) else { return nil }
            return (id, o.geometry)
        }
        guard !jobs.isEmpty else { notify("선분화할 곡선 개체가 없습니다."); return }
        let tolerance = segmentationTolerance
        guard jobs.count > 50, !Self.isRunningSelfTests else {
            applySegmentations(jobs.map { SegmentationStore.prepare($0.0, geometry: $0.1, tolerance: tolerance) })
            return
            // 몇 개 안 되면 그 자리에서 끝낸다. 백그라운드로 넘기면 오히려 화면이 한 번 잠긴다.
        }
        // 전체 곡선 선분화는 개체가 수천 개라 메인 스레드에서 돌리면 앱이 멈췄다.
        // 계산은 백그라운드에서 하고, 결과는 실행취소 칸 하나로 한 번에 반영한다.
        isProjectActionInProgress = true
        let task = beginLongTask("곡선 선분화", detail: "0 / \(jobs.count)개")
        let reporter = longTaskReporter(task)
        Task {
            defer { isProjectActionInProgress = false; endLongTask(task) }
            let results = await Task.detached(priority: .userInitiated) {
                var out: [Result<Segmentation, SegmentationStore.Rejected>] = []
                out.reserveCapacity(jobs.count)
                for (i, job) in jobs.enumerated() {
                    out.append(SegmentationStore.prepare(job.0, geometry: job.1, tolerance: tolerance))
                    reporter.report(Double(i + 1) / Double(jobs.count), "\(i + 1) / \(jobs.count)개")
                }
                return out
            }.value
            guard document?.fingerprint == doc.fingerprint else { return }
            // 계산하는 사이 다른 도면으로 바뀌었으면 반영하지 않는다.
            applySegmentations(results)
        }
    }

    /// 선분화 결과를 실행취소 칸 하나로 반영한다. 여러 개를 한 버튼으로 선분화하므로 되돌리기도 그 묶음 단위다.
    private func applySegmentations(_ results: [Result<Segmentation, SegmentationStore.Rejected>]) {
        let made = results.compactMap { try? $0.get() }.filter { !segmentation.isSegmented($0.sourceObjectID) }
        let rejected = results.count - results.filter { (try? $0.get()) != nil }.count
        if !made.isEmpty {
            perform("선분화") { for s in made { segmentation.insert(s) } }
            notify("\(made.count)개 곡선 개체를 선분화했습니다.")
        }
        if rejected > 0 {
            notify("곡선 \(rejected)개는 이어지지 않는 조각이 있어 곡선 그대로 두었습니다.")
            // 교차는 더 이상 막지 않는다(2026-10-18). 끝점이 벌어진 경우만 남으며, 오류가 아니라 안내로 짧게 알린다.
        }
        if made.isEmpty && rejected == 0 { notify("선분화할 곡선 개체가 없습니다.") }
    }

    func desegmentize(_ targets: Set<VectorObjectID>) {
        var n = 0
        perform("선분화 해제") {
            for id in targets where segmentation.isSegmented(id) {
                segmentation.desegmentize(id); n += 1
            }
        }
        notify(n > 0 ? "\(n)개 개체의 선분화를 해제했습니다." : "선분화된 개체가 없습니다.")
    }

    var curvedObjectCount: Int { document?.curvedObjectIDs.count ?? 0 }

    var segmentedCount: Int { segmentation.segmentedObjectIDs.count }

    // MARK: Anchor

    func beginAnchorPicking() {
        mode = .anchorPicking
        selection.clear()
        notify("도면에서 Anchor 위치를 클릭하세요.")
    }

    func addAnchor(longitude: Double, latitude: Double, label: String) {
        guard let local = pendingAnchorLocal else {
            notify("먼저 도면에서 Anchor 위치를 찍으세요.", isError: true)
            return
        }
        let layerSerial = anchorLayerPoint(near: local)?.feature.serialNumber
        // anchor 레이어 점을 찍었으면 라벨을 비워 둬도 그 점의 일련번호를 붙인다.
        perform("Anchor 추가") {
            anchors.add(local: local, geo: GeoPoint(longitude: longitude, latitude: latitude),
                        label: label.isEmpty ? layerSerial ?? "Anchor \(anchors.pairs.count + 1)" : label)
        }
        pendingAnchorLocal = nil
    }

    /// 검토 화면에서 확정한 건물 외곽 매칭만 한 번에 저장한다. 실행 취소도 한 단계다.
    func addAutoAnchorProposal(_ proposal: AutoAnchorProposal) {
        guard anchors.pairs.isEmpty else {
            notify("기존 Anchor가 있습니다. 자동 후보를 적용하기 전에 기존 쌍을 확인하세요.", isError: true)
            return
        }
        guard proposal.canApply, proposal.pairs.count >= AnchorStore.minimumPairs,
              (try? GeoAffineTransform.fit(from: proposal.pairs)) != nil else {
            notify("도면과 건물 외곽의 정합이 불확실해 후보를 적용할 수 없습니다.", isError: true)
            return
        }
        perform("자동 Anchor 후보 적용") {
            anchors.pairs.append(contentsOf: proposal.pairs)
        }
        pendingAnchorLocal = nil
        notify("건물 외곽을 기준으로 Anchor \(proposal.pairs.count)쌍을 추가했습니다. 지도 겹쳐보기와 잔차를 확인하세요.")
    }

    /// 도면 쪽 마커 드래그.
    func updateAnchorLocal(_ id: AnchorID, to p: LocalPoint) {
        guard let i = anchors.pairs.firstIndex(where: { $0.id == id }) else { return }
        // 드래그는 프레임마다 이 함수를 부른다. 마커 하나의 드래그 한 번이 실행취소 한 칸이 되도록 합친다.
        perform("Anchor 위치 조정", coalescingKey: "anchorLocal:\(id)") {
            anchors.pairs[i].local = p
        }
    }

    /// 지도 쪽 마커 드래그.
    func updateAnchorGeo(_ id: AnchorID, to g: GeoPoint) {
        guard let i = anchors.pairs.firstIndex(where: { $0.id == id }) else { return }
        perform("Anchor 위경도 조정", coalescingKey: "anchorGeo:\(id)") {
            anchors.pairs[i].geo = g
        }
    }

    func renameAnchor(_ id: AnchorID, to label: String) {
        guard let i = anchors.pairs.firstIndex(where: { $0.id == id }) else { return }
        perform("Anchor 이름", coalescingKey: "anchorLabel:\(id)") {
            anchors.pairs[i].label = label
        }
    }

    /// Anchor 지정 화면에 들어가면 개체 선택·이동·그룹화가 잠긴다.
    func enterAnchorScreen() {
        storeActiveLevel()
        guard buildingProject.sharedFootprint?.features.contains(where: { !$0.isInTrash }) == true else {
            notify("먼저 메인 화면의 footprint 레이어에서 건물 외곽을 그리세요.", isError: true)
            return
        }
        selection.clear()
        cancelPointDraft()
        showRoutingScreen = false
        showLevelFootprintScreen = false
        showMapAlignScreen = false
        mode = .anchorPicking
        showAnchorScreen = true
    }

    func exitAnchorScreen() {
        mode = .idle
        pendingAnchorLocal = nil
        showAnchorScreen = false
    }

    // MARK: 좌표 표 (명세 7-3-5, 7-3-6)

    func vertexRows(for fid: FeatureGroupID) -> [(LocalPoint, GeoPoint?)] {
        guard let doc = document, let f = features.feature(fid) else { return [] }
        let kind = GeometryClassifier.classify(f, document: doc)
        let locals = VertexExtractor.vertices(for: f, document: doc,
                                              segmentation: segmentation, kind: kind,
                                              borrowed: borrow.objects(borrowedBy: fid))
        // 내보내기와 **같은 인자**로 뽑는다. 화면의 좌표 표와 파일에 실리는 좌표가 갈라지면
        // 사용자가 표를 보고 확인한 것이 파일에서는 다른 값이 된다.
        if f.featureType == .footprint {
            let transform = activeLevel?.info.footprintRegistration?.transform ?? LevelFootprintTransform()
            let shared = sharedFootprint
            return locals.map { ($0, shared.geoPoint(transform.apply($0))) }
        }
        let g = georeferencer
        return locals.map { ($0, g.geoPoint(for: $0)) }
    }

    // MARK: 내보내기 (명세 7-4)

    func export() {
        if showRoutingScreen { exportRoutingGraph(); return }
        if layers.activePropertyType == .footprint {
            let shared = sharedFootprint
            guard shared.isGeoreferenced else { notify("Footprint Anchor 지정에서 GPS 대응점을 먼저 설정하세요.", isError: true); return }
            do {
                guard let data = projectContents.imdfFiles()["footprint.geojson"] else { return }
                guard let object = try JSONSerialization.jsonObject(with: data.data()) as? [String: Any] else {
                    notify("Footprint GeoJSON 형식이 올바르지 않습니다.", isError: true)
                    return
                }
                if let url = try GeoJSONExporter.write(object, suggestedName: "footprint.geojson") { notify("\(url.lastPathComponent) 저장 완료.") }
            } catch { notify(error.localizedDescription, isError: true) }
            return
        }
        guard let doc = document, let type = layers.activePropertyType else {
            notify("먼저 property type 레이어를 선택하세요.", isError: true)
            return
        }
        let validator = ExportValidator(document: doc, features: features.features,
                                        anchors: anchors,
                                        georeferencer: georeferencer, segmentation: segmentation, borrow: borrow)
        let blockers = validator.validate(type: type)
        if !blockers.isEmpty { exportBlockers = blockers; return }

        var serialToUUID: [String: UUID] = [:]
        for f in features.features where !f.isInTrash {
            serialToUUID[f.serialNumber] = ids.id(for: f.id)
        }
        let exporter = GeoJSONExporter(document: doc, segmentation: segmentation,
                                       georeferencer: georeferencer, borrow: borrow, levelID: activeLevel?.id)
        // level_id는 지금 층(층 관리)의 UUID다. IMDF 아카이브 내보내기와 같은 값이 나온다.
        var assigner = ids
        let collection = exporter.buildFeatureCollection(type: type, features: features.features,
                                                         ids: &assigner, serialToUUID: serialToUUID)
        ids = assigner
        do {
            if let url = try GeoJSONExporter.write(collection, suggestedName: "\(type.rawValue).geojson") {
                let open = openRingFeatures(type: type)
                if open.isEmpty {
                    notify("\(url.lastPathComponent) 저장 완료.")
                } else {
                    let names = open.map(\.0.serialNumber).sorted().joined(separator: ", ")
                    notify("\(url.lastPathComponent) 저장 완료 — 다만 \(names)의 폴리곤이 닫히지 않았습니다. 도면을 고쳐 다시 내보내세요.",
                           isError: true)
                    // **막지 않고 알린다.** 명세 7-4의 차단 조건에 링 열림은 없고,
                    // 내보내고 나서야 문제를 아는 것보다 파일과 함께 아는 편이 낫다.
                    // 어느 feature인지 일련번호로 짚어 줘야 인스펙터에서 찾아갈 수 있다.
                }
            }
        } catch {
            notify("저장 실패: \(error.localizedDescription)", isError: true)
        }
    }
}
