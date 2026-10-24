import Foundation

/// opening 한 곳이 노드로 바뀌지 못한 이유. 사용자가 화면에서 그대로 읽는다.
struct EntranceSkip: Equatable {
    var openingID: String
    var floorName: String
    var reason: String
}

/// 자동 배치 한 번의 결과. 만들 노드, 이미 처리된 개수, 제외 사유를 함께 담는다.
struct EntrancePlacementPlan: Equatable {
    var nodes: [RoutingNode] = []
    /// 같은 opening에서 이미 만든 노드가 있어 건너뛴 개수(사용자가 옮겼어도 덮어쓰지 않는다).
    var alreadyPlaced = 0
    /// 사용자가 직접 찍은 노드가 이미 중앙에 있어 건너뛴 개수.
    var coveredByExisting = 0
    var skipped: [EntranceSkip] = []
    /// 검사 대상이 된 opening 수(층 참조가 없는 것은 제외).
    var openingCount = 0
}

enum OpeningEntrancePlacer {
    /// 수동으로 찍은 노드가 중앙에서 이 거리(도면 단위, IMDF에서는 0.1 m) 안이면 같은 자리로 본다.
    static let duplicateTolerance = 3.0

    enum CenterError: LocalizedError {
        case missingGeometry, unsupported(String), badCoordinate, zeroLength
        var errorDescription: String? {
            switch self {
            case .missingGeometry: "geometry가 없습니다."
            case .unsupported(let type): "지원하지 않는 geometry(\(type))입니다. LineString만 중앙을 계산합니다."
            case .badCoordinate: "좌표가 누락되었거나 유효하지 않습니다."
            case .zeroLength: "선의 길이가 0이라 중앙을 정할 수 없습니다."
            }
        }
    }

    /// 선의 **길이 기준 중간점**. 점이 두 개면 중점과 같다.
    /// 확대율·화면 회전은 입력에 들어오지 않고, 점 나열 방향을 뒤집어도 같은 점이 나온다.
    static func midpoint(of points: [LocalPoint]) -> LocalPoint? {
        var total = 0.0
        for (a, b) in zip(points, points.dropFirst()) { total += a.distance(to: b) }
        guard total.isFinite, total > 0 else { return nil }
        // 방향에 상관없이 같은 값이 나오도록 좌표가 작은 쪽 끝에서부터 잰다.
        let ordered = canonicalOrder(points)
        var remaining = total / 2
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            let length = a.distance(to: b)
            if length >= remaining && length > 0 {
                let t = remaining / length
                return LocalPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
            }
            remaining -= length
        }
        return ordered.last
    }

    private static func canonicalOrder(_ points: [LocalPoint]) -> [LocalPoint] {
        guard let first = points.first, let last = points.last else { return points }
        let forward = (first.x, first.y) <= (last.x, last.y)
        return forward ? points : points.reversed()
    }

    /// opening geometry(LineString)에서 도면 좌표 중앙을 구한다.
    static func center(of geometry: ProjectJSON?, in floor: ProjectLevelInfo) -> Result<LocalPoint, CenterError> {
        guard let geometry, geometry != .null else { return .failure(.missingGeometry) }
        let type = geometry["type"]?.string ?? ""
        guard type == "LineString" else { return .failure(.unsupported(type.isEmpty ? "알 수 없음" : type)) }
        var points: [LocalPoint] = []
        for pair in geometry["coordinates"]?.array ?? [] {
            let values = pair.array.compactMap { value -> Double? in
                if case .number(let number) = value { return NSDecimalNumber(decimal: number).doubleValue }
                return nil
            }
            guard values.count >= 2, values.count == pair.array.count,
                  values[0].isFinite, values[1].isFinite, abs(values[0]) <= 180, abs(values[1]) <= 90,
                  let space = floor.imdfCoordinates, space.isValid else {
                return .failure(.badCoordinate)
            }
            let local = space.localPoint(longitude: values[0], latitude: values[1])
            guard local.x.isFinite, local.y.isFinite else { return .failure(.badCoordinate) }
            points.append(local)
        }
        guard points.count >= 2 else { return .failure(.badCoordinate) }
        guard let center = midpoint(of: points) else { return .failure(.zeroLength) }
        return .success(center)
    }

    static func plan(for project: BuildingProject) -> EntrancePlacementPlan {
        var plan = EntrancePlacementPlan()
        var unitLevels: [String: UUID] = [:]
        for level in project.levels {
            for unit in level.geoJSON["unit.geojson"] ?? [] {
                if let id = unit["id"]?.string { unitLevels[id.lowercased()] = level.id }
            }
        }
        let existing = project.levels.flatMap(\.nodes)
        var planned: [RoutingNode] = []
        for level in project.levels {
            let shared = (project.globalGeoJSON["opening.geojson"] ?? []).filter {
                BuildingProject.levelReferences($0, unitLevels: unitLevels).contains(level.id)
            }
            for feature in (level.geoJSON["opening.geojson"] ?? []) + shared {
                plan.openingCount += 1
                let openingID = feature["id"]?.string?.lowercased() ?? ""
                guard !openingID.isEmpty else {
                    plan.skipped.append(EntranceSkip(openingID: "(ID 없음)", floorName: level.info.name,
                                                     reason: "opening의 id가 없어 노드와 짝지을 수 없습니다."))
                    continue
                }
                if existing.contains(where: { $0.sourceOpeningID == openingID && $0.floorID == level.id }) {
                    plan.alreadyPlaced += 1; continue
                }
                switch center(of: feature["geometry"], in: level.info) {
                case .failure(let error):
                    plan.skipped.append(EntranceSkip(openingID: openingID, floorName: level.info.name,
                                                     reason: error.localizedDescription))
                case .success(let point):
                    let sameSpot = { (node: RoutingNode) in
                        node.floorID == level.id && node.point.distance(to: point) <= duplicateTolerance
                    }
                    if existing.contains(where: sameSpot) || planned.contains(where: sameSpot) {
                        plan.coveredByExisting += 1; continue
                    }
                    let node = RoutingNode(floorID: level.id, point: point, category: "entrance",
                                           sourceOpeningID: openingID)
                    planned.append(node)
                }
            }
        }
        plan.nodes = planned
        return plan
    }
}

@MainActor
extension AppEnvironment {
    /// 이 프로젝트에 opening이 하나라도 있는지. 버튼 활성화에 쓴다.
    var hasOpeningFeatures: Bool {
        buildingProject.levels.contains { !($0.geoJSON["opening.geojson"] ?? []).isEmpty }
            || !(buildingProject.globalGeoJSON["opening.geojson"] ?? []).isEmpty
    }

    /// IMDF opening 중앙에 `entrance` 노드를 한꺼번에 놓는다. 실행취소 한 칸으로 되돌아간다.
    @discardableResult
    func placeEntranceNodes() -> EntrancePlacementPlan {
        let plan = OpeningEntrancePlacer.plan(for: projectContents)
        lastEntrancePlacement = plan
        if !plan.nodes.isEmpty {
            perform("출입구 노드 자동 배치") { routing.nodes.append(contentsOf: plan.nodes) }
        }
        var parts = ["출입구 노드 \(plan.nodes.count)개를 배치했습니다."]
        if plan.alreadyPlaced > 0 { parts.append("이미 배치된 \(plan.alreadyPlaced)곳은 건너뜀") }
        if plan.coveredByExisting > 0 { parts.append("기존 노드가 있는 \(plan.coveredByExisting)곳은 건너뜀") }
        if !plan.skipped.isEmpty { parts.append("제외 \(plan.skipped.count)곳(사유는 오른쪽 패널)") }
        if plan.openingCount == 0 { parts = ["배치할 opening이 없습니다."] }
        notify(parts.joined(separator: " · "), isError: plan.nodes.isEmpty && !plan.skipped.isEmpty)
        return plan
    }
}
