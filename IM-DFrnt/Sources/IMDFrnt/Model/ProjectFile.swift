import Foundation

/// 작업 상태를 파일 하나로 담는다(명세 7-3-2, 9-7).
///
/// **이 파일이 없으면 IMDF 스펙을 지킬 수 없다.** 스펙은 Feature의 id에 대해
/// "MUST be retained to identify the target feature during the lifetime of its existence
/// across distinct deliveries"를 요구한다 — 즉 두 번째 내보내기에서도 **같은 UUID**가 나와야 한다.
/// 앱을 닫을 때 `IDAssigner`가 사라지면 다시 열었을 때 새 UUID가 발급되어 그 요건이 깨진다.
/// 폐기 UUID 대장(`retired`)도 같은 이유로 함께 저장한다 — "MUST NOT be re-assigned".
struct ProjectFile: Codable, Equatable {

    /// v9 adds node/place links. Older readers must reject instead of silently dropping them.
    static let currentVersion = 9
    static let fileExtension = "imdfrnt"
    /// 버전 2에서 바뀐 것은 **개체를 가리키는 방식**이다 — id를 도면 내용에서 결정적으로 뽑는다(신기능 1-2-6).
    /// 이건 형식이 아니라 **뜻**을 바꾸므로 버전 1 파일은 열지 않고 거절한다(아래 `decoded`).
    ///
    /// 확장자는 한때 `imdfproj`로 바꿨다가 **사용자 지시로 `imdfrnt`로 되돌렸다**(2026-08-25).
    /// 그래서 버전 1과 버전 2가 **같은 확장자를 쓴다** — 파일 이름만으로는 구분되지 않고,
    /// `version` 필드가 유일한 판별 수단이다. 확장자를 보고 안심하면 안 된다.

    static let interimFileExtension = "imdfproj"
    /// 되돌리기 전 잠깐 쓰였던 확장자. 그 사이에 저장한 파일도 열 수 있어야 하므로
    /// 열기 창에서 함께 고를 수 있게 남긴다. 새로 저장할 때는 쓰지 않는다.

    var version: Int = ProjectFile.currentVersion
    // 형식이 바뀌었을 때 옛 파일을 알아보기 위한 것. 없으면 조용히 깨진 상태로 열린다.

    var savedAt: Date = Date()

    var projectID: UUID = UUID()
    /// 이 작업의 신원(신기능 1-2). 배정본은 전부 이 값을 물려받고, 합칠 때 같은 값인지 본다.
    /// 다른 작업에서 온 파일을 합치면 남의 태깅이 내 도면에 섞인다.

    var assignment: Assignment?
    /// 이 파일이 **남에게 넘긴 몫**이면 채워져 있다. 원본 작업 파일에서는 `nil`이다.

    var sourceName: String
    var svg: String
    /// nil은 기존 파일의 도면 있음, false는 아직 도면을 넣지 않은 새 프로젝트다.
    var hasDrawing: Bool?
    /// **SVG 원본을 통째로 담는다. 경로만 참조하지 않는다.**
    /// 도면 파일이 옮겨지거나 이름이 바뀌면 프로젝트가 통째로 열리지 않게 되는데,
    /// 이 앱의 작업 결과(수십~수백 개의 태깅)는 도면 파일 하나보다 훨씬 비싸다.
    /// SVG는 텍스트라 함께 담아도 파일이 크게 늘지 않는다.

    var features: FeatureStore
    var ownership: OwnershipRegistry
    var segmentation: SegmentationStore
    var auxiliary: AuxiliaryStore
    var anchors: AnchorStore
    var serials: SerialNumberAllocator
    var ids: IDAssigner
    var openingGate: OpeningGateStore
    var borrow: BorrowRegistry

    var doorClosures: DoorClosureStore = DoorClosureStore()
    /// 아직 레이어에 반영하지 않은 임시 문(신기능 3항). **반드시 저장해야 한다** —
    /// 도면 전체를 훑으며 수십 개를 찍는 작업이라, 앱을 닫았다고 사라지면
    /// 그 작업량이 통째로 날아간다. 기본값을 둬서 이 필드가 없는 파일도 그대로 열린다.

    var drawingFingerprint: String?
    /// Optional so existing version 2 projects decode without losing their work.
    var buildingProject: BuildingProject?
    /// Versions 2–4 only; v5 stores routing within common Levels.
    var routing: RoutingGraph?
    /// 저장 시점 도면의 지문. 합칠 때 같은 도면인지 확인하는 두 번째 자물쇠다(신기능 1-2-6).

    // 담지 않는 것: 선택 상태·펼친 feature·레이어 목록·사이드바 폭·실행취소 스택.
    // 전부 "지금 화면을 어떻게 보고 있는가"이지 작업 결과가 아니다. 저장하면 파일을 열 때마다
    // 남의 화면 상태가 따라와 오히려 방해가 되고, 실행취소 스택은 다른 세션의 칸을 되살려
    // 지금 문서에 없는 상태로 덮어쓸 위험이 있다.

    enum CodingKeys: String, CodingKey {
        case version, savedAt, projectID, assignment, sourceName, svg, hasDrawing,
             features, ownership, segmentation, auxiliary, anchors, serials, ids,
             openingGate, borrow, doorClosures, drawingFingerprint, routing, buildingProject
    }

    func hasSameContents(as other: ProjectFile) -> Bool {
        projectID == other.projectID && assignment == other.assignment && commonProject().semanticContents == other.commonProject().semanticContents
    }

    enum LoadError: LocalizedError {
        case unsupportedVersion(Int)
        case legacyObjectIDs

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "이 프로젝트 파일은 더 새로운 형식입니다(버전 \(v)). 앱을 업데이트하세요."
            case .legacyObjectIDs:
                return "옛 버전(버전 1) 작업 파일입니다. 그때는 개체를 가리키는 방식이 달라, 지금 버전에서 열면 저장된 태깅이 도면의 어느 개체도 가리키지 못합니다. 화면에는 정상처럼 보이므로 열지 않습니다. 도면(SVG)을 다시 열어 작업해 주세요."
            }
        }
    }

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        // 정렬해서 쓰면 같은 상태를 두 번 저장했을 때 파일이 동일해진다.
        // 사용자가 버전 관리 도구에 넣었을 때 의미 없는 변경이 쌓이지 않는다.
        return try e.encode(self)
        // 날짜 전략을 지정하지 않고 기본(참조일 기준 실수 초)을 쓴다.
        // ISO8601은 사람이 읽기 좋지만 **초 미만을 잘라** 저장했다 여는 것만으로 값이 달라진다.
        // "저장하고 다시 열면 같은 상태"라는 보장이 읽기 편함보다 중요하다.
    }

    static func decoded(from data: Data) throws -> ProjectFile {
        let d = JSONDecoder()
        let file = try d.decode(ProjectFile.self, from: data)
        guard file.version <= currentVersion else {
            throw LoadError.unsupportedVersion(file.version)
            // 앞선 버전을 억지로 읽으면 모르는 필드가 조용히 버려진다.
            // 그 상태로 저장하면 사용자의 작업이 소리 없이 사라진다.
        }
        guard file.version >= 2 else {
            throw LoadError.legacyObjectIDs
            // **읽을 수는 있지만 읽으면 안 된다.** 버전 1은 개체 id를 파싱할 때마다
            // 새로 발급했으므로, 지금 코드로 그 SVG를 다시 읽으면 완전히 다른 id가 나온다.
            // 저장된 태깅이 가리키는 개체가 도면에 하나도 없는 상태로 열리는데, 화면에는
            // "feature는 있는데 아무 개체도 안 잡힌 상태"로 보인다 — 조용한 데이터 손실이다.
        }
        try file.validateLegacyRouting()
        return file
    }
}

extension ProjectFile {
    func validateLegacyRouting() throws {
        guard buildingProject == nil, let graph = routing else { return }
        try graph.validateEdgeGroups()
        let floors = Set(graph.floors.map(\.id)), nodes = Set(graph.nodes.map(\.id))
        guard floors.count == graph.floors.count,
              nodes.count == graph.nodes.count, graph.nodes.allSatisfy({ floors.contains($0.floorID) }),
              Set(graph.edges.map(\.id)).count == graph.edges.count,
              graph.edges.allSatisfy({ nodes.contains($0.from) && nodes.contains($0.to) }) else {
            throw IMDFImporter.Failure(message: "기존 프로젝트의 층·노드·연결 참조가 올바르지 않습니다. 현재 작업은 유지됩니다.")
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version <= Self.currentVersion else { throw LoadError.unsupportedVersion(version) }
        guard version >= 2 else { throw LoadError.legacyObjectIDs }
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        projectID = try c.decode(UUID.self, forKey: .projectID)
        assignment = try c.decodeIfPresent(Assignment.self, forKey: .assignment)
        sourceName = try c.decode(String.self, forKey: .sourceName)
        svg = try c.decode(String.self, forKey: .svg)
        hasDrawing = try c.decodeIfPresent(Bool.self, forKey: .hasDrawing)
        features = try c.decode(FeatureStore.self, forKey: .features)
        ownership = try c.decode(OwnershipRegistry.self, forKey: .ownership)
        segmentation = try c.decode(SegmentationStore.self, forKey: .segmentation)
        auxiliary = try c.decode(AuxiliaryStore.self, forKey: .auxiliary)
        anchors = try c.decode(AnchorStore.self, forKey: .anchors)
        serials = try c.decode(SerialNumberAllocator.self, forKey: .serials)
        ids = try c.decode(IDAssigner.self, forKey: .ids)
        openingGate = try c.decode(OpeningGateStore.self, forKey: .openingGate)
        borrow = try c.decode(BorrowRegistry.self, forKey: .borrow)
        doorClosures = try c.decodeIfPresent(DoorClosureStore.self, forKey: .doorClosures) ?? DoorClosureStore()
        drawingFingerprint = try c.decodeIfPresent(String.self, forKey: .drawingFingerprint)
        routing = try c.decodeIfPresent(RoutingGraph.self, forKey: .routing)
        buildingProject = try c.decodeIfPresent(BuildingProject.self, forKey: .buildingProject)
    }
}
