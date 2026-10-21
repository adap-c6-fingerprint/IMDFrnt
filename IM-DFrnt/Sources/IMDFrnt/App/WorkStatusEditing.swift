import Foundation

/// feature type 상태·순서·최근 작업(신기능 12항, 2026-10-20).
///
/// 상태는 사용자가 고른다. 층에 귀속되는 type(좌측 사이드바)은 층마다, 정보 type(상단바)은 프로젝트에 하나씩이다.
/// **층의 완료는 고르지 않고 계산한다** — 좌측 사이드바의 type이 모두 Complete이면 그 층이 Complete다.
@MainActor
extension AppEnvironment {

    /// 좌측 사이드바의 type. 층에 귀속된다.
    static let levelFeatureTypes = IMDFFeatureType.allCases.filter { !$0.isMetadataOnly }
    /// 상단바로 옮긴 정보 type. 층과 무관하다.
    static let metadataFeatureTypes = IMDFFeatureType.allCases.filter(\.isMetadataOnly)

    func workStatus(_ type: IMDFFeatureType, level: ProjectLevel? = nil) -> LayerWorkStatus {
        if type.isMetadataOnly { return buildingProject.metadataWorkStatus?[type.rawValue] ?? .todo }
        return (level ?? activeLevel)?.workStatus?[type.rawValue] ?? .todo
    }

    func setWorkStatus(_ status: LayerWorkStatus, for type: IMDFFeatureType) {
        if type.isMetadataOnly {
            perform("\(type.displayName) 상태: \(status.title)") {
                buildingProject.metadataWorkStatus = (buildingProject.metadataWorkStatus ?? [:])
                    .merging([type.rawValue: status]) { _, new in new }
            }
            return
        }
        guard let i = buildingProject.levels.firstIndex(where: { $0.id == routingFloorID }) else { return }
        perform("\(buildingProject.levels[i].info.name) \(type.displayName) 상태: \(status.title)") {
            buildingProject.levels[i].workStatus = (buildingProject.levels[i].workStatus ?? [:])
                .merging([type.rawValue: status]) { _, new in new }
        }
    }

    func isLevelComplete(_ level: ProjectLevel) -> Bool {
        Self.levelFeatureTypes.allSatisfy { workStatus($0, level: level) == .complete }
    }

    // MARK: 순서

    /// 상단바의 층 순서. 저장된 화면 순서를 따르고, 거기 없는 층(새로 만든 층)은 층 번호 순으로 뒤에 붙인다.
    var displayedLevels: [ProjectLevel] {
        let byOrdinal = buildingProject.levels.sorted { $0.info.ordinal < $1.info.ordinal }
        guard let order = buildingProject.levelDisplayOrder else { return byOrdinal }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return byOrdinal.enumerated().sorted { a, b in
            (rank[a.element.id] ?? order.count + a.offset, a.offset) < (rank[b.element.id] ?? order.count + b.offset, b.offset)
        }.map(\.element)
    }

    /// 층 `id`를 `target` 자리로 옮긴다. 화면 순서만 바뀌고 층 번호는 그대로다.
    func moveLevel(_ id: UUID, to target: UUID) {
        guard id != target else { return }
        var ids = displayedLevels.map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        perform("층 순서 변경") { buildingProject.levelDisplayOrder = ids }
    }

    /// 사용자 지정 순서. 저장된 순서에 없는 type은 기본 순서로 뒤에 붙인다.
    var customFeatureTypeOrder: [IMDFFeatureType] {
        let saved = (buildingProject.featureTypeOrder ?? []).compactMap(IMDFFeatureType.init(rawValue:))
            .filter { !$0.isMetadataOnly }
        return saved + Self.levelFeatureTypes.filter { !saved.contains($0) }
    }

    func sortedFeatureTypes(_ sort: FeatureTypeSort) -> [IMDFFeatureType] {
        let base = customFeatureTypeOrder
        let position = Dictionary(uniqueKeysWithValues: base.enumerated().map { ($1, $0) })
        switch sort {
        case .custom:
            return base
        case .completeFirst, .incompleteFirst:
            let sign = sort == .completeFirst ? 1 : -1
            return base.sorted {
                let a = workStatus($0).progressRank * sign, b = workStatus($1).progressRank * sign
                return a != b ? a < b : position[$0]! < position[$1]!
            }
        case .recent:
            let edited = activeLevel?.lastEdited ?? [:]
            return base.sorted {
                let a = edited[$0.rawValue], b = edited[$1.rawValue]
                switch (a, b) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return position[$0]! < position[$1]!
                }
                // 고친 적 없는 type은 사용자 지정 순서대로 뒤에 둔다.
            }
        }
    }

    /// `type`을 `target` 자리로 옮긴다. `shown`은 지금 화면에 보이는 순서다 —
    /// 다른 기준으로 정렬된 채 끌어도 보이는 그대로에서 옮긴 결과가 사용자 지정 순서가 된다.
    func moveFeatureType(_ type: IMDFFeatureType, to target: IMDFFeatureType, shown: [IMDFFeatureType]) {
        var order = shown
        guard type != target, let from = order.firstIndex(of: type), let to = order.firstIndex(of: target) else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        perform("Feature Type 순서 변경") { buildingProject.featureTypeOrder = order.map(\.rawValue) }
    }

    // MARK: 최근 작업

    /// `perform` 전후의 feature를 비교해, 바뀐 type의 '마지막으로 고친 시각'을 지금 층에 남긴다.
    /// 레이어를 열거나 고르기만 한 것은 feature가 그대로라 남지 않는다.
    func stampEditedTypes(before: FeatureStore) {
        guard before != features,
              let i = buildingProject.levels.firstIndex(where: { $0.id == routingFloorID }) else { return }
        let old = Dictionary(before.features.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = Set<IMDFFeatureType>()
        var seen = Set<FeatureGroupID>()
        for f in features.features {
            seen.insert(f.id)
            if old[f.id] != f { changed.insert(f.featureType) }
        }
        for (id, f) in old where !seen.contains(id) { changed.insert(f.featureType) }
        guard !changed.isEmpty else { return }
        let now = Date()
        var edited = buildingProject.levels[i].lastEdited ?? [:]
        for type in changed { edited[type.rawValue] = now }
        buildingProject.levels[i].lastEdited = edited
    }
}
