import Foundation

/// 점·면 작업에 쓰는 파생 기하(#21, 2026-10-15).
///
/// **도면·선분화·보조 제외·닫는 선분 넷이 같으면 결과도 같다.** 그래서 이 넷을 열쇠로 삼고,
/// 열쇠가 바뀔 때만 다시 계산한다. 계산은 백그라운드에서 하고 결과만 메인 액터에 넘긴다.
/// 예전에는 면 찾기를 레이어를 만들 때마다 메인 스레드에서 돌려 C5 도면에서 앱이 약 5초 멈췄다
/// (`04) 엔진 디버깅.md` 3장).
struct DerivedGeometryKey: Equatable, Sendable {
    var segmentation: SegmentationStore
    var excluded: Set<VectorObjectID>
    /// 도면에 없는데 면을 닫는 데 쓰는 선분. 임시 문과 저장된 opening의 선이다.
    var closingSegments: [LineSegment]
}

struct DerivedGeometry: Sendable {
    /// 보조 제외를 뺀 선분과 닫는 선분으로 찾은 면.
    let faces: [ClosedPolygonFinder.Face]
    /// 고를 수 있는 점(꼭짓점·끝점·교차점). **보조 개체로 제외한 개체의 점은 뺀다** —
    /// 치수선·해치의 점까지 고를 수 있으면 방 모서리 근처에서 엉뚱한 점이 잡힌다.
    let snapPoints: [SnapPointExtractor.SnapPoint]
    /// 진행률 분모. 보조 개체까지 포함한 전체 점 수다.
    let totalPointCount: Int

    static let empty = DerivedGeometry(faces: [], snapPoints: [], totalPointCount: 0)

    static func make(document: DrawingDocument?, key: DerivedGeometryKey) throws -> DerivedGeometry {
        guard let doc = document else { return .empty }
        try Task.checkCancellation()
        let all = SnapPointExtractor.points(in: doc.objects, segmentation: key.segmentation)
        try Task.checkCancellation()
        let remaining = key.excluded.isEmpty ? doc.objects : doc.objects.filter { !key.excluded.contains($0.id) }
        let snaps = key.excluded.isEmpty ? all : SnapPointExtractor.points(in: remaining, segmentation: key.segmentation)
        try Task.checkCancellation()

        var sources: [ClosedPolygonFinder.SourceSegment] = []
        for o in remaining {
            let geometry = key.segmentation.effectiveGeometry(for: o.id, fallback: o.geometry)
            for s in geometry.lineSegments() { sources.append(.init(segment: s, objectID: o.id)) }
        }
        for s in key.closingSegments { sources.append(.init(segment: s, objectID: nil)) }
        let faces = ClosedPolygonFinder.faces(in: sources)
        try Task.checkCancellation()
        return DerivedGeometry(faces: faces, snapPoints: snaps, totalPointCount: all.count)
    }

    /// 면을 닫는 선분. **임시 문뿐 아니라 저장된 opening의 선도 넣는다** — 점 단위로 그린
    /// opening은 도면에 개체가 없는 선이라, 넣지 않으면 문 자리에서 방이 닫히지 않는다.
    static func closingSegments(doors: [TemporaryDoor], features: [FeatureGroup]) -> [LineSegment] {
        var out = doors.map { LineSegment(start: $0.start, end: $0.end) }
        for f in features where f.featureType == .opening && !f.isInTrash {
            if let c = f.closureSegment { out.append(c); continue }
            guard let v = f.drawnVertices, v.count >= 2 else { continue }
            for i in 0..<(v.count - 1) { out.append(LineSegment(start: v[i], end: v[i + 1])) }
        }
        return out
    }
}

extension LevelEditingState {
    var derivedKey: DerivedGeometryKey {
        DerivedGeometryKey(segmentation: segmentation, excluded: auxiliary.excluded,
                           closingSegments: DerivedGeometry.closingSegments(
                               doors: doorClosures.doors, features: features.features))
    }
}

@MainActor
extension AppEnvironment {

    /// 지금 편집 상태의 열쇠.
    var currentDerivedKey: DerivedGeometryKey {
        DerivedGeometryKey(segmentation: segmentation, excluded: auxiliary.excluded,
                           closingSegments: DerivedGeometry.closingSegments(
                               doors: doorClosures.doors, features: features.features))
    }

    /// 열쇠가 바뀌었으면 다시 계산한다. **같으면 아무것도 하지 않는다** — `features`는 속성 입력칸의
    /// 글자 하나마다 바뀌는데, 그때마다 면을 다시 찾으면 입력이 버벅인다.
    func scheduleDerivedGeometryRefresh() {
        guard !isInstallingLevelDrawing else { return }
        guard let doc = document else {
            derivedTask?.cancel(); derivedTask = nil
            applyDerivedGeometry(.empty, key: nil)
            return
        }
        let key = currentDerivedKey
        guard key != derivedKey else { return }
        derivedTask?.cancel()
        if derivedGeometryInline {
            applyDerivedGeometry((try? DerivedGeometry.make(document: doc, key: key)) ?? .empty, key: key)
            return
        }
        let token = UUID()
        derivedToken = token
        isComputingDerivedGeometry = true
        derivedTask = Task { [weak self] in
            let result = try? await Task.detached(priority: .userInitiated) {
                try DerivedGeometry.make(document: doc, key: key)
            }.value
            guard let self, !Task.isCancelled, self.derivedToken == token, let result else { return }
            guard self.document?.fingerprint == doc.fingerprint, self.currentDerivedKey == key else {
                self.isComputingDerivedGeometry = false
                self.scheduleDerivedGeometryRefresh()
                return
                // 계산하는 사이 상태가 또 바뀌었으면 낡은 결과를 버리고 다시 계산한다.
            }
            self.applyDerivedGeometry(result, key: key)
        }
    }

    func applyDerivedGeometry(_ g: DerivedGeometry, key: DerivedGeometryKey?) {
        derivedKey = key
        isComputingDerivedGeometry = false
        closedPolygonFaces = g.faces
        let ids = Set(g.faces.map(\.id))
        if !faceSelection.isSubset(of: ids) { faceSelection.formIntersection(ids) }
        // 사라진 면의 선택을 들고 있으면 저장 버튼의 개수와 화면이 어긋난다.
        snapPoints = g.snapPoints
        totalPointCount = g.totalPointCount
        doorSnapCache = g.snapPoints
        snapPointIndex = SnapPointGrid(points: g.snapPoints)
        refreshPointProgress()
        invalidateRenderStates()
    }
}

/// 점을 칸으로 나눠 둔 색인. 클릭 근처의 점 찾기와 화면에 보이는 점만 그리기에 쓴다 —
/// C5 도면은 점이 약 4만 8천 개라 매번 전부 훑으면 그리기가 느려진다.
struct SnapPointGrid {
    private var cells: [Int64: [Int]] = [:]
    private(set) var points: [SnapPointExtractor.SnapPoint] = []
    private var cellSize: Double = 1
    private var keys: [GridKey: Int] = [:]

    struct GridKey: Hashable {
        let x: Int64
        let y: Int64
        init(_ p: LocalPoint) {
            x = Int64((p.x / SnapPointExtractor.mergeTolerance).rounded())
            y = Int64((p.y / SnapPointExtractor.mergeTolerance).rounded())
        }
    }

    init() {}

    init(points: [SnapPointExtractor.SnapPoint]) {
        self.points = points
        guard !points.isEmpty else { return }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for p in points {
            minX = min(minX, p.point.x); maxX = max(maxX, p.point.x)
            minY = min(minY, p.point.y); maxY = max(maxY, p.point.y)
        }
        cellSize = max(sqrt(max(1, (maxX - minX) * (maxY - minY)) / Double(points.count)) * 4, 1)
        for (i, p) in points.enumerated() {
            cells[key(p.point.x, p.point.y), default: []].append(i)
            keys[GridKey(p.point)] = i
        }
    }

    private func cell(_ v: Double) -> Int64 { Int64((v / cellSize).rounded(.down)) }
    private func key(_ x: Double, _ y: Double) -> Int64 { (cell(x) << 32) ^ (cell(y) & 0xFFFF_FFFF) }

    /// 사각형 안의 점 번호.
    func indices(in rect: CGRect) -> [Int] {
        guard !points.isEmpty, rect.width.isFinite, rect.height.isFinite else { return Array(points.indices) }
        var out: [Int] = []
        let x0 = cell(Double(rect.minX)), x1 = cell(Double(rect.maxX))
        let y0 = cell(Double(rect.minY)), y1 = cell(Double(rect.maxY))
        guard (x1 - x0 + 1) * (y1 - y0 + 1) < Int64(points.count) else {
            return points.indices.filter { rect.contains(points[$0].point.cg) }
            // 칸이 점보다 많으면 칸을 훑는 쪽이 더 느리다.
        }
        for x in x0...x1 {
            for y in y0...y1 {
                guard let members = cells[(x << 32) ^ (y & 0xFFFF_FFFF)] else { continue }
                for i in members where rect.contains(points[i].point.cg) { out.append(i) }
            }
        }
        return out
    }

    /// 반경 안에서 가장 가까운 점.
    func nearest(to p: LocalPoint, within radius: Double) -> SnapPointExtractor.SnapPoint? {
        let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        var best: (Int, Double)?
        for i in indices(in: rect) {
            let d = points[i].point.distance(to: p)
            guard d <= radius else { continue }
            if best == nil || d < best!.1 { best = (i, d) }
        }
        return best.map { points[$0.0] }
    }

    /// 이 좌표에 있는 점의 번호(같은 자리로 볼 거리 안).
    func index(at p: LocalPoint) -> Int? { keys[GridKey(p)] }
}
