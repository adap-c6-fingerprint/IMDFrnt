import Foundation

/// unit 레이어 점 단위의 도구(2026-10-18 요청).
///
/// - 그리기: 종전처럼 꼭짓점을 찍어 다각형을 닫는다.
/// - 보조 선분: 두 점을 찍어 선분을 긋는다. feature가 아니라 내보내지 않고, 면 단위에서 면을 나누는 경계다.
/// - 자르기: 선을 그어 그 선이 가로지른 unit을 조각마다 따로 나눈다. 조각은 원래 unit의 속성을 그대로 가진다.
/// - 점 끼우기: 저장된 unit의 변 위를 누르면 그 자리에 꼭짓점을 넣는다.
enum UnitPointTool: String, CaseIterable {
    case draw
    case guide
    case cut
    case insertVertex

    var title: String {
        switch self {
        case .draw: return "그리기"
        case .guide: return "보조 선분"
        case .cut: return "자르기"
        case .insertVertex: return "점 끼우기"
        }
    }

    var help: String {
        switch self {
        case .draw: return "꼭짓점을 찍어 unit 다각형을 그립니다."
        case .guide: return "두 점을 찍어 보조 선분을 긋습니다. 내보내지 않고, 면 단위에서 면을 나누는 경계로만 씁니다. Control+클릭으로 지웁니다."
        case .cut: return "선을 그어 그 선이 가로지른 unit을 나눕니다. 나뉜 조각은 원래 unit의 속성을 그대로 가집니다."
        case .insertVertex: return "저장된 unit의 변 위를 누르면 그 자리에 꼭짓점을 넣습니다."
        }
    }

    func hint(points n: Int) -> String {
        switch self {
        case .draw: return ""
        case .guide:
            return n == 0 ? "보조 선분의 시작점을 찍으세요. 꼭짓점·교점·변 위에 붙습니다. Control+클릭으로 선분을 지웁니다."
                          : "끝점을 찍으면 보조 선분이 생깁니다."
        case .cut:
            return n < 2 ? "자를 선을 따라 점을 찍으세요. unit 바깥에서 시작해 반대편 바깥까지 가로지르세요."
                         : "Return(또는 마지막 점을 다시 누르기)으로 선이 지나간 unit을 자릅니다."
        case .insertVertex:
            return "unit의 변 위를 누르면 그 자리에 꼭짓점을 끼웁니다. 맞닿은 이웃 unit의 같은 변에도 함께 넣습니다."
        }
    }
}

@MainActor
extension AppEnvironment {

    /// 지금 쓰는 unit 도구. unit 레이어 점 단위에서 '그리기'가 아닐 때만 값이 있다.
    var unitToolInUse: UnitPointTool? {
        layers.activePropertyType == .unit && unitPointTool != .draw ? unitPointTool : nil
    }

    func handleUnitToolClick(_ tool: UnitPointTool, at point: LocalPoint, radius: Double,
                             freePoint: Bool, editing: Bool) {
        switch tool {
        case .draw:
            return
        case .guide:
            if editing, pointDraft.isEmpty, let i = guideIndex(near: point, radius: radius) {
                perform("보조 선분 지우기") { features.removeGuide(at: i) }
                notify("보조 선분을 지웠습니다.")
                return
            }
            if let idx = pointDraft.points.firstIndex(where: { $0.distance(to: point) <= radius }) {
                perform("점 삭제") { pointDraft.remove(at: idx) }
                return
            }
            guard let target = pointTarget(near: point, radius: radius, freePoint: freePoint, edges: true) else { return }
            guard let start = pointDraft.points.first else {
                perform("점 추가") { pointDraft.points.append(target) }
                return
            }
            guard start.distance(to: target) > SnapPointExtractor.mergeTolerance else { return }
            perform("보조 선분 긋기") {
                features.addGuide(LineSegment(start: start, end: target))
                pointDraft = PointDraft()
            }
            notify("보조 선분을 그었습니다. 면 단위에서 면을 나누는 경계로 씁니다. (Control+클릭으로 지우기)")
        case .cut:
            if let idx = pointDraft.points.firstIndex(where: { $0.distance(to: point) <= radius }) {
                if idx == pointDraft.points.count - 1, pointDraft.points.count >= 2 { cutUnitsAlongDraft(); return }
                perform("점 삭제") { pointDraft.remove(at: idx) }
                return
            }
            guard let target = pointTarget(near: point, radius: radius, freePoint: true, edges: true) else { return }
            perform("점 추가") { pointDraft.points.append(target) }
            // 자르는 선은 unit 바깥 아무 데서나 시작해도 된다. 꼭짓점·변 근처면 그 점에 붙는다.
        case .insertVertex:
            insertVertexOnUnitEdge(at: point, radius: radius)
        }
    }

    /// 가까운 보조 선분.
    func guideIndex(near p: LocalPoint, radius: Double) -> Int? {
        features.guides.indices
            .map { ($0, Self.projection(of: p, onto: features.guides[$0].start, features.guides[$0].end)) }
            .filter { $0.1.distance(to: p) <= radius }
            .min { $0.1.distance(to: p) < $1.1.distance(to: p) }?.0
    }

    static func projection(of p: LocalPoint, onto a: LocalPoint, _ b: LocalPoint) -> LocalPoint {
        let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
        guard len2 > 0 else { return a }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return LocalPoint(a.x + t * dx, a.y + t * dy)
    }

    /// 이 층에 저장된 개체(모든 레이어)의 변·보조 선분 위에서 가장 가까운 점.
    func savedEdgePoint(near p: LocalPoint, radius: Double) -> LocalPoint? {
        var best: (LocalPoint, Double)?
        func consider(_ a: LocalPoint, _ b: LocalPoint) {
            let q = Self.projection(of: p, onto: a, b)
            let d = q.distance(to: p)
            if d <= radius, d < (best?.1 ?? .infinity) { best = (q, d) }
        }
        for f in features.features where !f.isInTrash {
            for ring in f.polygonRings where ring.count >= 2 {
                for i in ring.indices { consider(ring[i], ring[(i + 1) % ring.count]) }
            }
            if let v = f.drawnVertices, v.count >= 2 { for i in 0..<(v.count - 1) { consider(v[i], v[i + 1]) } }
            if let c = f.closureSegment { consider(c.start, c.end) }
        }
        for g in features.guides { consider(g.start, g.end) }
        return best?.0
    }

    // MARK: 자르기

    /// 작성 중인 선(두 점 이상)이 가로지른 unit을 나눈다. 선이 닿지 않은 다각형(MultiPolygon의 다른 섬)은 원래 unit에 남는다.
    func cutUnitsAlongDraft() {
        let line = pointDraft.points
        guard line.count >= 2 else {
            notify("자를 선의 점을 두 개 이상 찍으세요.", isError: true)
            return
        }
        let cuts = zip(line, line.dropFirst()).map { LineSegment(start: $0, end: $1) }
        let lineBox = ClosedPolygonFinder.boundingBox(line)
        var plans: [(FeatureGroup, keep: [[LocalPoint]], new: [[[LocalPoint]]])] = []
        for u in features.features(ofType: .unit) where !u.polygonRings.isEmpty {
            let uBox = ClosedPolygonFinder.boundingBox(u.polygonRings.flatMap { $0 })
            guard uBox.insetBy(dx: -1e-6, dy: -1e-6).intersects(lineBox) else { continue }
            var segments = cuts
            for ring in u.polygonRings where ring.count >= 3 {
                for i in ring.indices { segments.append(LineSegment(start: ring[i], end: ring[(i + 1) % ring.count])) }
            }
            let uPath = UnitCoverage.path(u.polygonRings)
            var touched: [[[LocalPoint]]] = [], untouched: [[[LocalPoint]]] = []
            for face in ClosedPolygonFinder.faces(in: segments.map { .init(segment: $0, objectID: nil) }, minimumArea: 0.5) {
                let region = UnitCoverage.path([face.ring]).intersection(uPath, using: .evenOdd)
                for piece in region.componentsSeparated(using: .evenOdd) {
                    var rings = Self.rings(of: piece).map { ring in
                        ring.map { Self.restore($0, from: u.polygonRings + [face.ring], polylines: [line]) }
                    }
                    guard abs(UnitCoverage.area(UnitCoverage.path(rings))) >= 0.5 else { continue }
                    rings.sort { abs(ClosedPolygonFinder.signedArea($0)) > abs(ClosedPolygonFinder.signedArea($1)) }
                    // 바깥 링을 앞에, 구멍을 뒤에 둔다.
                    let onLine = rings.contains { ring in
                        ring.contains { p in cuts.contains { Self.projection(of: p, onto: $0.start, $0.end).distance(to: p) < 1e-6 } }
                    }
                    if onLine { touched.append(rings) } else { untouched.append(rings) }
                }
            }
            guard touched.count >= 2 else { continue }
            touched.sort { UnitCoverage.area(UnitCoverage.path($0)) > UnitCoverage.area(UnitCoverage.path($1)) }
            plans.append((u, keep: touched[0] + untouched.flatMap { $0 }, new: Array(touched.dropFirst())))
        }
        guard !plans.isEmpty else {
            notify("선이 가로질러 둘 이상으로 나뉘는 unit이 없습니다. unit 바깥에서 시작해 반대편 바깥까지 그으세요.", isError: true)
            return
        }
        var made: [String] = []
        perform("unit 자르기") {
            for plan in plans {
                features.update(plan.0.id) {
                    $0.polygonRings = plan.keep
                    $0.polygonFaceIDs = []
                    if RingNesting.polygons(plan.keep).count > 1 || plan.keep.count > 1 { $0.multiPolygon = true }
                }
                for rings in plan.new {
                    var f = FeatureGroup(featureType: .unit, serialNumber: serials.next(for: .unit), memberIDs: [])
                    f.properties = plan.0.properties
                    f.polygonRings = rings
                    if rings.count > 1 { f.multiPolygon = true }
                    features.insert(f)
                    made.append(f.serialNumber)
                }
            }
            pointDraft = PointDraft()
        }
        notify("\(plans.map(\.0.serialNumber).joined(separator: ", "))을 잘랐습니다. 새 unit: \(made.joined(separator: ", ")) (속성은 원래 unit과 같습니다)")
    }

    // MARK: 점 끼우기

    /// 변 위의 점을 unit 링에 끼운다. 같은 변을 나눠 쓰는 이웃 unit에도 넣어 꼭짓점을 함께 쓰게 한다.
    func insertVertexOnUnitEdge(at p: LocalPoint, radius: Double) {
        let units = features.features(ofType: .unit).filter { !$0.polygonRings.isEmpty }
        var best: (LocalPoint, Double)?
        for u in units {
            for ring in u.polygonRings where ring.count >= 3 {
                for i in ring.indices {
                    let a = ring[i], b = ring[(i + 1) % ring.count]
                    let q = Self.projection(of: p, onto: a, b)
                    let d = q.distance(to: p)
                    guard d <= radius, q.distance(to: a) > radius, q.distance(to: b) > radius else { continue }
                    if d < (best?.1 ?? .infinity) { best = (q, d) }
                }
            }
        }
        guard var q = best?.0 else {
            notify("unit의 변 위(꼭짓점에서 떨어진 자리)를 누르세요.", isError: true)
            return
        }
        if let snap = snapPointIndex.nearest(to: q, within: radius)?.point,
           units.contains(where: { $0.polygonRings.contains { ring in
               ring.indices.contains { Self.projection(of: snap, onto: ring[$0], ring[($0 + 1) % ring.count]).distance(to: snap) < 1e-6 } } }) {
            q = snap
            // 변 위에 도면 꼭짓점·교점이 있으면 그 좌표를 쓴다. 벽선이 꺾이는 자리를 정확히 맞추기 쉽다.
        }
        var hit: [String] = []
        perform("점 끼우기") {
            for u in units {
                var rings = u.polygonRings
                var changed = false
                for r in rings.indices {
                    guard let i = rings[r].indices.first(where: { i in
                        let a = rings[r][i], b = rings[r][(i + 1) % rings[r].count]
                        return Self.projection(of: q, onto: a, b).distance(to: q) < 1e-6
                            && a.distance(to: q) > 1e-9 && b.distance(to: q) > 1e-9
                    }) else { continue }
                    rings[r].insert(q, at: i + 1)
                    changed = true
                }
                if changed {
                    features.update(u.id) { $0.polygonRings = rings; $0.polygonFaceIDs = [] }
                    hit.append(u.serialNumber)
                }
            }
        }
        notify("\(hit.joined(separator: ", "))의 변에 꼭짓점을 끼웠습니다. 꼭짓점 이동으로 옮길 수 있습니다.")
    }
}
