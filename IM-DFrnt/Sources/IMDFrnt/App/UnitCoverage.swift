import CoreGraphics
import SwiftUI

/// 같은 층 unit 사이의 **빈틈과 겹침**을 찾는다.
///
/// IMDF는 같은 Level을 가리키는 unit끼리 겹치거나 틈이 있으면 안 되고, unit 전체를 합친 영역이
/// Level과 같아야 한다고 정한다(MUST NOT symmetrical difference, 위키 src10). 화면에서는 붙어 보여도
/// 0.03만큼 어긋난 변은 눈으로 찾을 수 없어 계산으로 찾아 도면 위에 표시한다.
///
/// - 겹침: unit 두 개의 교집합.
/// - 빈틈: **level 기준**이다. 이 층 level 다각형에서 unit 전체를 뺀 나머지(2026-10-18 요청).
///   level 다각형이 없으면 기준이 없어 빈틈을 계산하지 않는다(`hasLevel` false).
///   예전에는 unit에 둘러싸인 빈 곳을 빈틈으로 봤는데, 건물 바깥 테두리의 빈 곳을 놓쳤다.
enum UnitCoverage {
    struct Result {
        var gaps: [CGPath] = []
        var overlaps: [CGPath] = []
        /// 겹침 조각마다 서로 겹친 두 unit(`units`에서의 순번). `overlaps`와 순서가 같다.
        var overlapPairs: [(Int, Int)] = []
        /// 빈틈을 잴 level 다각형이 있었는가.
        var hasLevel = false
        var isEmpty: Bool { gaps.isEmpty && overlaps.isEmpty }
    }

    /// 빈틈은 노랑, 겹침은 빨강이다. 무늬(점·빗금)와 색을 함께 달리해 한눈에 구분되게 한다.
    static let gapColor = Color(red: 0.92, green: 0.68, blue: 0.0)
    static let overlapColor = Color.red

    /// 이보다 넓이가 작은 조각은 계산 오차로 본다. 0.03 어긋난 변의 틈(길이 100이면 넓이 3)은 남는다.
    static let minimumArea: Double = 1e-4

    /// `units`·`levels`는 feature마다 링 목록이다. MultiPolygon의 구멍은 짝홀 규칙으로 빠진다.
    static func analyze(units: [[[LocalPoint]]], levels: [[[LocalPoint]]]) -> Result {
        let indexed = units.enumerated().map { ($0.offset, path($0.element)) }.filter { !$0.1.isEmpty }
        let paths = indexed.map(\.1)
        var result = Result()

        for i in paths.indices {
            for j in paths.indices where j > i {
                guard paths[i].boundingBoxOfPath.intersects(paths[j].boundingBoxOfPath) else { continue }
                let shared = paths[i].intersection(paths[j], using: .evenOdd)
                for piece in pieces(of: shared) {
                    result.overlaps.append(piece)
                    result.overlapPairs.append((indexed[i].0, indexed[j].0))
                }
            }
        }

        let levelPaths = levels.map(path).filter { !$0.isEmpty }
        guard let first = levelPaths.first else { return result }
        result.hasLevel = true
        let level = levelPaths.dropFirst().reduce(first) { $0.union($1, using: .evenOdd) }
        guard !paths.isEmpty else {
            result.gaps = pieces(of: level)
            return result
        }
        let covered = paths.dropFirst().reduce(paths[0]) { $0.union($1, using: .evenOdd) }
        result.gaps = pieces(of: level.subtracting(covered, using: .evenOdd))
        return result
    }

    static func path(_ rings: [[LocalPoint]]) -> CGPath {
        let p = CGMutablePath()
        for ring in rings where ring.count >= 3 {
            p.addLines(between: ring.map(\.cg))
            p.closeSubpath()
        }
        return p
    }

    /// 떨어진 조각마다 하나씩. 계산 오차로 생긴 넓이 없는 조각은 버린다.
    private static func pieces(of path: CGPath) -> [CGPath] {
        guard !path.isEmpty else { return [] }
        return path.componentsSeparated(using: .evenOdd).filter { abs(area($0)) >= minimumArea }
    }

    /// 짝홀 규칙의 넓이. 하위 경로마다 신발끈 공식의 절댓값을 더하고 구멍은 뺀다(바깥보다 작은 것을 구멍으로 본다).
    static func area(_ path: CGPath) -> Double {
        var polygons: [[CGPoint]] = []
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: polygons.append([e.points[0]])
            case .addLineToPoint: polygons[polygons.count - 1].append(e.points[0])
            case .addQuadCurveToPoint: polygons[polygons.count - 1].append(e.points[1])
            case .addCurveToPoint: polygons[polygons.count - 1].append(e.points[2])
            default: break
            }
        }
        let areas = polygons.map { pts -> Double in
            guard pts.count >= 3 else { return 0 }
            var s = 0.0
            for i in pts.indices {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                s += Double(a.x * b.y - b.x * a.y)
            }
            return abs(s) / 2
        }
        guard let largest = areas.max() else { return 0 }
        return largest - (areas.reduce(0, +) - largest)
    }
}

@MainActor
extension AppEnvironment {

    /// 지금 층 unit의 빈틈·겹침. 화면을 그릴 때마다 읽으므로 unit·level 링이 같으면 다시 계산하지 않는다.
    var unitCoverage: UnitCoverage.Result {
        if let cache = unitCoverageCache, cache.revision == geometryRevision { return cache.result }
        // feature가 그대로면 링을 다시 모아 비교하지 않는다.
        let units = coverageUnits.map(\.polygonRings)
        let levels = features.features(ofType: .level).filter { !$0.isInTrash && !$0.polygonRings.isEmpty }.map(\.polygonRings)
        if var cache = unitCoverageCache, cache.units == units, cache.levels == levels {
            cache.revision = geometryRevision
            unitCoverageCache = cache
            return cache.result
        }
        let result = UnitCoverage.analyze(units: units, levels: levels)
        unitCoverageCache = UnitCoverageCache(units: units, levels: levels, result: result, revision: geometryRevision)
        return result
    }

    /// 빈틈·겹침 계산에 넣는 unit. `overlapPairs`의 순번이 이 목록의 순번이다.
    var coverageUnits: [FeatureGroup] {
        features.features(ofType: .unit).filter { !$0.isInTrash && !$0.polygonRings.isEmpty }
    }

    /// 빈틈·겹침 조각의 이름표. 위에서 아래, 왼쪽에서 오른쪽 순으로 번호를 매긴다.
    /// 겹침은 서로 겹친 두 unit의 일련번호를 함께 단다(예: `겹침-02 unit-012×unit-031`).
    var unitCoverageLabels: [(path: CGPath, text: String, isGap: Bool)] {
        let r = unitCoverage
        let serials = coverageUnits.map(\.serialNumber)
        func order(_ a: CGPath, _ b: CGPath) -> Bool {
            let p = a.boundingBoxOfPath, q = b.boundingBoxOfPath
            return (p.minY, p.minX) < (q.minY, q.minX)
        }
        let gaps = r.gaps.sorted(by: order).enumerated().map { i, g in
            (path: g, text: String(format: "빈틈-%02d · %.1f", i + 1, abs(UnitCoverage.area(g))), isGap: true)
        }
        let overlaps = zip(r.overlaps, r.overlapPairs).sorted { order($0.0, $1.0) }.enumerated().map { i, item in
            let (o, pair) = item
            let names = [pair.0, pair.1].map { serials.indices.contains($0) ? serials[$0] : "?" }.joined(separator: "×")
            return (path: o, text: String(format: "겹침-%02d %@ · %.2f", i + 1, names, abs(UnitCoverage.area(o))), isGap: false)
        }
        return gaps + overlaps
    }

    /// unit 레이어를 보고 있고 토글이 켜져 있을 때만 표시한다.
    var isShowingUnitCoverage: Bool { showUnitCoverage && layers.activePropertyType == .unit }
}

struct UnitCoverageCache {
    var units: [[[LocalPoint]]]
    var levels: [[[LocalPoint]]]
    var result: UnitCoverage.Result
    var revision = -1
}

/// 상단바 토글. unit 레이어에서만 보인다. 켜면 빈틈·겹침 개수도 함께 보여 준다.
struct UnitCoverageToggle: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        if env.layers.activePropertyType == .unit {
            ToolbarDivider().frame(height: 16)
            Toggle(isOn: $env.showUnitCoverage) {
                Text("빈틈·겹침").font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("level 다각형 안에서 unit이 덮지 않은 빈틈(노란 점무늬)과 unit끼리의 겹침(빨간 빗금)을 도면에 표시하고, 조각마다 이름표를 답니다.")
            if env.showUnitCoverage {
                let r = env.unitCoverage
                HStack(spacing: 6) {
                    if r.hasLevel {
                        Text("빈틈 \(r.gaps.count)").foregroundStyle(r.gaps.isEmpty ? Color.secondary : UnitCoverage.gapColor)
                    } else {
                        Text("level 없어 빈틈 미계산").foregroundStyle(.secondary)
                    }
                    Text("겹침 \(r.overlaps.count)").foregroundStyle(r.overlaps.isEmpty ? Color.secondary : UnitCoverage.overlapColor)
                }
                .font(.caption.monospacedDigit())
                .fixedSize()
                .help("빈틈은 이 층 level 다각형에서 unit이 덮지 않은 곳, 겹침은 unit 두 개가 함께 덮은 곳입니다.")
            }
        }
    }
}
