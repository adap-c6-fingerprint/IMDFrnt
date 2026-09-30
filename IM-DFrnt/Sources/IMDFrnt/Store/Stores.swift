import CoreGraphics
import Foundation

// MARK: - OwnershipRegistry

/// 아키텍처의 핵심. 개체 → feature 그룹의 전역 유일 사상을 지킨다(명세 4-1, 6-1).
struct OwnershipRegistry: Equatable, Codable {
    private(set) var owner: [VectorObjectID: FeatureGroupID] = [:]

    enum OwnershipError: Error {
        case alreadyOwned(objectID: VectorObjectID, by: FeatureGroupID)
    }

    func ownerOf(_ id: VectorObjectID) -> FeatureGroupID? { owner[id] }

    var claimedCount: Int { owner.count }

    var claimedObjectIDs: Set<VectorObjectID> { Set(owner.keys) }

    mutating func claim(_ ids: Set<VectorObjectID>, for feature: FeatureGroupID) throws {
        for id in ids {
            if let existing = owner[id], existing != feature {
                throw OwnershipError.alreadyOwned(objectID: id, by: existing)
            }
        }
        for id in ids { owner[id] = feature }
    }

    mutating func release(_ ids: Set<VectorObjectID>) {
        for id in ids { owner.removeValue(forKey: id) }
    }

    mutating func releaseAll(of feature: FeatureGroupID) {
        owner = owner.filter { $0.value != feature }
    }
}

// MARK: - FeatureStore

struct FeatureStore: Equatable, Codable {
    private(set) var features: [FeatureGroup] = []

    /// id → 배열 위치. 조회를 한 번에 끝내기 위한 색인이다(`07) 성능 최적화 제안.md` 제안 3).
    /// 이전에는 `features.first { $0.id == id }`로 목록을 앞에서부터 훑었는데,
    /// `renderState`가 개체마다 이 함수를 부르므로 개체 2,000개 × feature 300개면
    /// 프레임당 60만 번 비교가 여기서만 나왔다.
    private var indexByID: [FeatureGroupID: Int] = [:]

    init() {}

    enum CodingKeys: String, CodingKey { case features }
    // 색인은 저장하지 않는다 — 배열에서 언제든 다시 만들 수 있고,
    // 파일에 넣으면 이전에 저장한 프로젝트 파일과 형식이 갈린다.

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        features = try c.decode([FeatureGroup].self, forKey: .features)
        rebuildIndex()
    }

    static func == (l: FeatureStore, r: FeatureStore) -> Bool { l.features == r.features }
    // 색인은 배열에서 파생된 값이라 비교 대상이 아니다. 넣으면 실행취소의
    // "바뀐 게 없다" 판정(`AppEnvironment.perform`)이 엉뚱하게 달라질 수 있다.

    func feature(_ id: FeatureGroupID) -> FeatureGroup? {
        guard let i = indexByID[id], features.indices.contains(i) else { return nil }
        return features[i]
    }

    private mutating func rebuildIndex() {
        indexByID = Dictionary(uniqueKeysWithValues: features.enumerated().map { ($1.id, $0) })
    }

    func features(ofType type: IMDFFeatureType, includingTrashed: Bool = false) -> [FeatureGroup] {
        features
            .filter { $0.featureType == type && (includingTrashed || !$0.isInTrash) }
            .sorted { $0.serialNumber < $1.serialNumber }
    }

    func count(ofType type: IMDFFeatureType) -> Int {
        features.filter { $0.featureType == type && !$0.isInTrash }.count
    }

    mutating func insert(_ f: FeatureGroup) {
        features.append(f)
        indexByID[f.id] = features.count - 1
    }

    mutating func remove(_ id: FeatureGroupID) {
        features.removeAll { $0.id == id }
        rebuildIndex()
        // 지우면 뒤 항목의 자리가 앞으로 당겨지므로 색인을 다시 만든다.
        // `update`는 자리를 바꾸지 않으므로 다시 만들지 않는다.
    }

    mutating func update(_ id: FeatureGroupID, _ body: (inout FeatureGroup) -> Void) {
        guard let i = indexByID[id], features.indices.contains(i) else { return }
        body(&features[i])
    }
}

// MARK: - LayerStore

struct LayerStore: Equatable {
    private(set) var layers: [EditorLayer] = []
    private(set) var activeLayerID: EditorLayer.ID?
    // 대입을 막고 `activate(_:)`로만 바꾼다. 하위 기본 레이어가 활성이 되면
    // 그 위에서 개체를 선택·저장할 수 있게 되는데, 그 레이어는 원위치 확인용이라
    // 어떤 액션도 허용되지 않는다(명세 2-3). 막을 곳을 한 군데로 모은다.

    /// 레이어를 연다. 액션이 허용되지 않는 레이어는 열리지 않는다.
    @discardableResult
    mutating func activate(_ id: EditorLayer.ID) -> Bool {
        guard let l = layers.first(where: { $0.id == id }), l.allowsObjectActions else { return false }
        activeLayerID = id
        return true
    }

    /// 명세 7-2-2·3)의 "이 feature만 보기 / 빼고 보기"
    var isolatedFeature: FeatureGroupID?
    var excludedFeature: FeatureGroupID?

    mutating func bootstrap() {
        let ghost = EditorLayer(kind: .baseGhost)
        let top = EditorLayer(kind: .baseTop)
        layers = [ghost, top]
        activeLayerID = top.id
        isolatedFeature = nil
        excludedFeature = nil
    }

    var activeLayer: EditorLayer? {
        layers.first { $0.id == activeLayerID }
    }

    var activePropertyType: IMDFFeatureType? {
        activeLayer?.propertyType
    }

    func layer(for type: IMDFFeatureType) -> EditorLayer? {
        layers.first { $0.propertyType == type }
    }

    @discardableResult
    mutating func addPropertyTypeLayer(_ type: IMDFFeatureType) -> EditorLayer {
        if let existing = layer(for: type) {
            activeLayerID = existing.id
            return existing
        }
        let l = EditorLayer(kind: .propertyType(type))
        layers.append(l)
        activeLayerID = l.id
        return l
    }

    @discardableResult
    mutating func addAttributeFilterLayer(key: String, label: String) -> EditorLayer {
        if let existing = layers.first(where: {
            if case .attributeFilter(let k, _) = $0.kind { return k == key }
            return false
        }) {
            activeLayerID = existing.id
            return existing
        }
        let l = EditorLayer(kind: .attributeFilter(key: key, label: label))
        layers.append(l)
        activeLayerID = l.id
        return l
    }

    mutating func close(_ id: EditorLayer.ID) {
        guard let l = layers.first(where: { $0.id == id }), l.isClosable else { return }
        layers.removeAll { $0.id == id }
        if activeLayerID == id { activeLayerID = layers.last(where: { $0.isClosable })?.id ?? layers.first(where: { if case .baseTop = $0.kind { return true }; return false })?.id }
    }

    /// 레이어별 투명도(2026-08-27 요청). `nil`을 넣으면 기본값으로 되돌린다.
    mutating func setOpacity(_ value: Double?, for id: EditorLayer.ID) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[i].setOpacity(value)
    }

    mutating func setHidden(_ hidden: Bool, for id: EditorLayer.ID) {
        guard let i = layers.firstIndex(where: { $0.id == id }), layers[i].isHidable else { return }
        layers[i].isHidden = hidden
    }

    mutating func addObjects(_ ids: Set<VectorObjectID>, to id: EditorLayer.ID) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[i].extraObjectIDs.formUnion(ids)
    }
}

// MARK: - SelectionStore

struct SelectionStore: Equatable {
    var selected: Set<VectorObjectID> = []

    /// 곡선 개체만 보기 창에서 선택된 "선분화 이전의 곡선 개체" 집합.
    var curvedSelection: Set<VectorObjectID> = []

    mutating func toggle(_ id: VectorObjectID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    mutating func clear() { selected.removeAll() }

    var isEmpty: Bool { selected.isEmpty }

    /// 선택이 하나라도 있으면 나머지를 70% opacity 처리(명세 5항).
    var dimsOthers: Bool { !selected.isEmpty }
}

// MARK: - SegmentationStore

/// 선분화 상태. `DrawingDocument.objects`는 절대 건드리지 않는다.
struct SegmentationStore: Equatable, Codable {
    private(set) var segmentations: [VectorObjectID: Segmentation] = [:]

    func isSegmented(_ id: VectorObjectID) -> Bool { segmentations[id] != nil }

    var segmentedObjectIDs: Set<VectorObjectID> { Set(segmentations.keys) }

    func segmentation(for id: VectorObjectID) -> Segmentation? { segmentations[id] }

    /// 선분화됐으면 선분 집합, 아니면 원본.
    func effectiveGeometry(for id: VectorObjectID, fallback: PathGeometry) -> PathGeometry {
        segmentations[id]?.geometry ?? fallback
    }

    @discardableResult
    mutating func segmentize(_ id: VectorObjectID, geometry: PathGeometry,
                             tolerance: Double) -> [SegmentationDefect] {
        let segs = CurveFlattener.flatten(geometry, tolerance: tolerance)
        let defects = SegmentationValidator.validate(segs, epsilon: 1e-4)
        guard defects.isEmpty else { return defects }
        segmentations[id] = Segmentation(sourceObjectID: id, segments: segs,
                                         tolerance: tolerance, createdAt: Date())
        return []
    }

    mutating func desegmentize(_ id: VectorObjectID) {
        segmentations.removeValue(forKey: id)
    }
}

// MARK: - AuxiliaryStore

/// '보조 개체 제외'(명세 디버깅 6번). 치수 숫자·보조선처럼 어떤 property type에도 속하지 않는
/// 개체를 태깅 대상에서 빼둔다.
///
/// **`OwnershipRegistry`와 섞지 않는다.** 제외는 소유가 아니다 — 소유는 배타적이고 되돌리려면
/// feature를 해제해야 하지만, 제외는 언제든 개별 해제할 수 있고 feature와 무관하다.
/// 같은 딕셔너리에 넣으면 진행률 분자가 두 종류를 구분하지 못해 색을 나눌 수 없다.
struct AuxiliaryStore: Equatable, Codable {
    private(set) var excluded: Set<VectorObjectID> = []

    func isExcluded(_ id: VectorObjectID) -> Bool { excluded.contains(id) }

    var count: Int { excluded.count }

    mutating func exclude(_ ids: Set<VectorObjectID>) { excluded.formUnion(ids) }

    mutating func include(_ ids: Set<VectorObjectID>) { excluded.subtract(ids) }

    mutating func clear() { excluded.removeAll() }
}

// 개체 임시 이동(구 `TransientOffsetStore`)은 2026-08-25에 제거했다.
// 이동의 목적이 "아래에 뭐가 깔렸는지 확인"이었는데, 원본 좌표와 표시 좌표가 갈리는
// 위험(추출 좌표가 이동값을 따라가면 도면이 통째로 어긋난다)에 비해 얻는 게 적었다.
// 대신 `OverlapDetector`가 겹치는 곳의 윤곽을 제자리에 표시한다.

// MARK: - AnchorStore

struct AnchorStore: Equatable, Codable {
    var pairs: [AnchorPair] = []

    static let minimumPairs = GeoAffineTransform.minimumPairs
    static let recommendedPairs = GeoAffineTransform.recommendedPairs

    var isConfigured: Bool { pairs.count >= Self.minimumPairs }

    /// false면 잔차가 항상 0이므로 UI가 "판정 불가"를 표시한다.
    var isOverDetermined: Bool { pairs.count > Self.minimumPairs }

    mutating func add(local: LocalPoint, geo: GeoPoint, label: String) {
        pairs.append(AnchorPair(local: local, geo: geo, label: label))
    }

    mutating func remove(_ id: AnchorID) {
        pairs.removeAll { $0.id == id }
    }
}

// MARK: - SerialNumberAllocator

/// 명세 7-1-2)의 `unit-001` 형식 발급.
/// 휴지통에 간 번호는 재사용하지 않는다(복원 시 번호 충돌 방지).
struct SerialNumberAllocator: Equatable, Codable {
    private var counters: [IMDFFeatureType: Int] = [:]

    mutating func next(for type: IMDFFeatureType) -> String {
        let n = (counters[type] ?? 0) + 1
        counters[type] = n
        return String(format: "%@-%03d", type.serialPrefix, n)
    }

    mutating func reserve(_ serial: String) {
        let parts = serial.split(separator: "-")
        guard parts.count == 2, let t = IMDFFeatureType(rawValue: String(parts[0])),
              let n = Int(parts[1]) else { return }
        counters[t] = max(counters[t] ?? 0, n)
    }
}

// MARK: - IDAssigner

/// 명세 7-3-2)의 "변환 단계에서 한번에 자동 입력".
/// 공식 스펙이 강제하는 두 제약 때문에 단순 발급기가 아니라 영속 대장이다.
struct IDAssigner: Equatable, Codable {
    private(set) var assigned: [FeatureGroupID: UUID] = [:]
    private(set) var retired: Set<UUID> = []

    /// 이미 발급된 게 있으면 그것을 그대로 반환한다.
    /// "MUST be retained across distinct deliveries" 요건이 여기서 지켜진다.
    mutating func id(for feature: FeatureGroupID) -> UUID {
        if let existing = assigned[feature] { return existing }
        var new = UUID()
        while retired.contains(new) || assigned.values.contains(new) { new = UUID() }
        assigned[feature] = new
        return new
    }

    func peek(_ feature: FeatureGroupID) -> UUID? { assigned[feature] }

    /// 남이 이미 발급받은 id를 그대로 물려받는다(신기능 1-2-5, 배정본 합치기).
    /// 여기서 새로 뽑으면 담당자 몫의 feature만 id가 갈려, IMDF 스펙의
    /// "distinct deliveries 사이에 같은 id를 유지" 요건이 조용히 깨진다.
    mutating func adopt(_ feature: FeatureGroupID, id: UUID) {
        guard assigned[feature] == nil, !retired.contains(id) else { return }
        assigned[feature] = id
    }

    /// "MUST NOT be re-assigned to another Feature" 요건.
    mutating func retire(_ feature: FeatureGroupID) {
        if let id = assigned.removeValue(forKey: feature) { retired.insert(id) }
    }
}

// MARK: - OpeningGateStore (명세 10-1)

/// opening 선행 태깅 게이트.
/// unit·footprint 등은 닫힌 폴리곤이 필요한데 실제 도면의 방은 문 자리에서 벽이 끊겨 있다.
/// 문을 먼저 확정해야 그 선분으로 링을 닫을 수 있으므로, opening을 다른 type보다 앞에 세운다.
struct OpeningGateStore: Equatable, Codable {

    private(set) var isDeclaredComplete = false
    /// 완료 **선언**이지 완료 **판정**이 아니다. 도면에 문이 몇 개인지는 프로그램이 알 수 없으므로
    /// 자동 판정이 불가능하고, 사용자가 직접 선언하는 수밖에 없다(명세 10-1-3).

    private(set) var emptyDeclarationWarned = false
    /// 문 없는 도면도 허용하되 경고는 한 번만 띄운다(명세 10-1-5). 매번 띄우면 통과 의례가 된다.

    /// opening 이외의 property type 메뉴를 열 수 있는가.
    var allowsOtherTypes: Bool { isDeclaredComplete }

    mutating func declareComplete(hasAnyOpening: Bool) {
        isDeclaredComplete = true
        if !hasAnyOpening { emptyDeclarationWarned = true }
    }

    mutating func reopen() {
        isDeclaredComplete = false
        // 되돌릴 수 있어야 한다(명세 10-1-4). 작업 도중 빠뜨린 문을 발견하면 돌아와 추가해야 하고,
        // 이때 이미 저장한 다른 feature는 건드리지 않는다 — 게이트는 메뉴만 잠근다.
    }

    mutating func clear() {
        isDeclaredComplete = false
        emptyDeclarationWarned = false
    }
}

// MARK: - BorrowRegistry (명세 10-2)

/// 문 빌려주기 장부. **소유권과 같은 자료구조에 섞지 않는다.**
/// 소유는 배타적이고(개체 하나에 주인 하나) 대여는 비배타적이다 — 방 A와 방 B 사이의 문은
/// 양쪽 폴리곤을 모두 닫아야 하므로 두 feature가 같은 문을 동시에 빌린다(명세 10-2-5).
/// 한 딕셔너리에 넣으면 배타성 검사가 무너져 opening이 흡수되고 파일에서 사라진다.
struct BorrowRegistry: Equatable, Codable {

    private var borrowed: [FeatureGroupID: Set<VectorObjectID>] = [:]
    // feature → 그 feature가 빌린 opening 개체들. 반대 방향은 두지 않는다(명세 10-2-6, 단방향).

    func objects(borrowedBy feature: FeatureGroupID) -> Set<VectorObjectID> {
        borrowed[feature] ?? []
    }

    /// 이 opening을 빌려 쓰는 feature 전부. 휴지통 경고(명세 10-4-4)가 이 목록을 쓴다.
    func borrowers(of object: VectorObjectID) -> Set<FeatureGroupID> {
        Set(borrowed.filter { $0.value.contains(object) }.keys)
    }

    func isBorrowed(_ object: VectorObjectID) -> Bool {
        borrowed.values.contains { $0.contains(object) }
    }

    mutating func borrow(_ ids: Set<VectorObjectID>, by feature: FeatureGroupID) {
        borrowed[feature, default: []].formUnion(ids)
    }

    mutating func giveBack(_ ids: Set<VectorObjectID>, from feature: FeatureGroupID) {
        borrowed[feature]?.subtract(ids)
        if borrowed[feature]?.isEmpty == true { borrowed.removeValue(forKey: feature) }
        // 빈 항목을 남기면 '빌린 게 있는 feature' 판정이 참이 되어 인스펙터에 빈 섹션이 뜬다.
    }

    mutating func giveBackAll(of feature: FeatureGroupID) {
        borrowed.removeValue(forKey: feature)
    }

    mutating func clear() { borrowed.removeAll() }
}
