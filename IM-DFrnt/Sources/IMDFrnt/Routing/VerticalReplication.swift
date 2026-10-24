import Foundation

/// 신기능 13항(B안): 기준 층에서 한 번 찍은 계단·엘리베이터·에스컬레이터 노드를 같은 실제 좌표로 다른 층에 복제한다.
struct VerticalReplicationResult: Equatable {
    var created: [UUID] = []
    /// 같은 시설의 노드가 이미 있어 건드리지 않은 층.
    var existing: [UUID] = []
    /// 좌표 변환이 없거나 도면 밖이라 만들지 않은 층.
    var skipped: [UUID] = []
    var connected = 0

    func summary(_ graph: RoutingGraph) -> String {
        func names(_ ids: [UUID]) -> String { ids.compactMap { graph.floor($0)?.name }.joined(separator: ", ") }
        var parts = ["\(created.count)개 층에 노드를 만들었습니다"]
        if connected > 0 { parts.append("층간 연결 \(connected)개 추가") }
        if !existing.isEmpty { parts.append("이미 있어 유지: \(names(existing))") }
        if !skipped.isEmpty { parts.append("좌표 문제로 건너뜀: \(names(skipped))") }
        return parts.joined(separator: " · ")
    }
}

extension RoutingGraph {
    /// 같은 층의 같은 종류 노드가 이 거리(미터) 안에 있으면 같은 시설로 보고 새로 만들지 않는다.
    static let verticalAdoptionMeters = 1.0

    /// 같은 시설 노드들을 층 번호 순으로 모은다.
    func verticalGroup(_ id: UUID) -> [RoutingNode] {
        nodes.filter { $0.verticalGroupID == id }
            .sorted { (floor($0.floorID)?.ordinal ?? 0) < (floor($1.floorID)?.ordinal ?? 0) }
    }

    /// 기준 노드를 `targetFloorIDs`(nil이면 모든 층)에 복제한다. 여러 번 실행해도 중복이 생기지 않고,
    /// 이미 있는 노드의 위치·이름·연결은 바꾸지 않는다. 엘리베이터만 인접 층끼리 연결한다.
    mutating func replicateVerticalNode(_ sourceID: UUID, to targetFloorIDs: [UUID]? = nil) -> VerticalReplicationResult? {
        guard let source = node(sourceID), RoutingNodeCategory(rawValue: source.category)?.isVertical == true,
              let sourceFloor = floor(source.floorID), let geo = sourceFloor.geoPoint(for: source.point) else { return nil }
        var result = VerticalReplicationResult()
        let group = source.verticalGroupID ?? UUID()
        if let index = nodes.firstIndex(where: { $0.id == sourceID }) { nodes[index].verticalGroupID = group }

        let targets = floors.filter { $0.id != source.floorID && (targetFloorIDs?.contains($0.id) ?? true) }
        for target in targets {
            if nodes.contains(where: { $0.floorID == target.id && $0.verticalGroupID == group }) {
                result.existing.append(target.id); continue
            }
            guard let local = target.localPoint(for: geo), local.x >= 0, local.y >= 0 else {
                result.skipped.append(target.id); continue
            }
            // 사람이 이미 같은 자리에 찍어 둔 노드는 옮기지 않고 같은 시설로만 묶는다.
            if let index = nodes.firstIndex(where: {
                $0.floorID == target.id && $0.category == source.category && $0.verticalGroupID == nil
                    && target.geoPoint(for: $0.point).map { ResidualCalculator.metersBetween($0, geo) <= Self.verticalAdoptionMeters } == true
            }) {
                nodes[index].verticalGroupID = group
                result.existing.append(target.id); continue
            }
            let copy = RoutingNode(floorID: target.id, point: local, name: source.name,
                                   category: source.category, metadataJSON: source.metadataJSON,
                                   verticalGroupID: group)
            nodes.append(copy)
            result.created.append(target.id)
        }
        if source.category == RoutingNodeCategory.elevator.rawValue { result.connected = connectElevatorGroup(group) }
        return result
    }

    /// 층 번호가 이웃한 엘리베이터 노드끼리만 잇는다. 이미 있는 연결은 그대로 둔다.
    mutating func connectElevatorGroup(_ group: UUID) -> Int {
        let members = verticalGroup(group).filter { $0.category == RoutingNodeCategory.elevator.rawValue }
        var added = 0
        for (a, b) in zip(members, members.dropFirst()) where a.floorID != b.floorID {
            let before = edges.count
            _ = connect(a.id, b.id)
            added += edges.count - before
        }
        return added
    }
}

@MainActor
extension AppEnvironment {
    /// 한 번의 실행취소로 복제와 연결을 함께 되돌린다.
    @discardableResult
    func replicateVerticalNode(_ id: UUID, to floorIDs: [UUID]? = nil) -> VerticalReplicationResult? {
        guard let node = routing.node(id), RoutingNodeCategory(rawValue: node.category)?.isVertical == true else {
            notify("계단·엘리베이터·에스컬레이터 노드를 선택하세요.", isError: true); return nil
        }
        guard routing.floor(node.floorID)?.hasGeographicCoordinates == true else {
            notify("이 층에 실제 좌표(IMDF 또는 좌표 기준점)가 없어 복제할 수 없습니다.", isError: true); return nil
        }
        var result: VerticalReplicationResult?
        perform("층별 노드 복제") { result = routing.replicateVerticalNode(id, to: floorIDs) }
        if let result { notify(result.summary(routing), isError: result.created.isEmpty && !result.skipped.isEmpty) }
        return result
    }
}
