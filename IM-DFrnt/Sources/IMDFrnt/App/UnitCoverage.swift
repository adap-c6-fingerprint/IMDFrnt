import CoreGraphics
import SwiftUI

/// 같은 층 unit 사이의 **빈틈과 겹침**을 찾는다.
///
/// IMDF는 같은 Level을 가리키는 unit끼리 겹치거나 틈이 있으면 안 되고, unit 전체를 합친 영역이
/// Level과 같아야 한다고 정한다(MUST NOT symmetrical difference, 위키 src10). 화면에서는 붙어 보여도
/// 0.03만큼 어긋난 변은 눈으로 찾을 수 없어 계산으로 찾아 도면 위에 표시한다.
///
/// - 겹침: unit 두 개의 교집합.
/// - 빈틈: 이 층에 level 다각형이 있으면 level에서 unit 전체를 뺀 나머지.
///   없으면 unit들로 빙 둘러싸였는데 비어 있는 곳(합친 영역의 안쪽 구멍)이다.
enum UnitCoverage {
    struct Result {
        var gaps: [CGPath] = []
        var overlaps: [CGPath] = []
        var isEmpty: Bool { gaps.isEmpty && overlaps.isEmpty }
    }

    /// 이보다 넓이가 작은 조각은 계산 오차로 본다. 0.03 어긋난 변의 틈(길이 100이면 넓이 3)은 남는다.
    static let minimumArea: Double = 1e-4

    /// `units`·`levels`는 feature마다 링 목록이다. MultiPolygon의 구멍은 짝홀 규칙으로 빠진다.
    static func analyze(units: [[[LocalPoint]]], levels: [[[LocalPoint]]]) -> Result {
        let paths = units.map(path).filter { !$0.isEmpty }
        var result = Result()

        for i in paths.indices {
            for j in paths.indices where j > i {
                guard paths[i].boundingBoxOfPath.intersects(paths[j].boundingBoxOfPath) else { continue }
                let shared = paths[i].intersection(paths[j], using: .evenOdd)
                result.overlaps += pieces(of: shared)
            }
        }

        guard !paths.isEmpty else { return result }
        let covered = paths.dropFirst().reduce(paths[0]) { $0.union($1, using: .evenOdd) }
        let levelPaths = levels.map(path).filter { !$0.isEmpty }
        if let first = levelPaths.first {
            let level = levelPaths.dropFirst().reduce(first) { $0.union($1, using: .evenOdd) }
            result.gaps = pieces(of: level.subtracting(covered, using: .evenOdd))
        } else {
            for component in covered.componentsSeparated(using: .evenOdd) {
                let outer = subpaths(of: component).max { area($0) < area($1) }
                guard let outer else { continue }
                result.gaps += pieces(of: outer.subtracting(component, using: .evenOdd))
                // 덩어리의 바깥 테두리 안을 채운 것에서 실제로 덮인 곳을 빼면 안쪽 구멍만 남는다.
            }
        }
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

    /// 경로를 이동(moveTo)마다 끊은 하위 경로들.
    private static func subpaths(of path: CGPath) -> [CGPath] {
        var out: [CGMutablePath] = []
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                let p = CGMutablePath(); p.move(to: e.points[0]); out.append(p)
            case .addLineToPoint: out.last?.addLine(to: e.points[0])
            case .addQuadCurveToPoint: out.last?.addQuadCurve(to: e.points[1], control: e.points[0])
            case .addCurveToPoint: out.last?.addCurve(to: e.points[2], control1: e.points[0], control2: e.points[1])
            case .closeSubpath: out.last?.closeSubpath()
            @unknown default: break
            }
        }
        return out
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
        let units = features.features(ofType: .unit).filter { !$0.isInTrash && !$0.polygonRings.isEmpty }.map(\.polygonRings)
        let levels = features.features(ofType: .level).filter { !$0.isInTrash && !$0.polygonRings.isEmpty }.map(\.polygonRings)
        if let cache = unitCoverageCache, cache.units == units, cache.levels == levels { return cache.result }
        let result = UnitCoverage.analyze(units: units, levels: levels)
        unitCoverageCache = UnitCoverageCache(units: units, levels: levels, result: result)
        return result
    }

    /// unit 레이어를 보고 있고 토글이 켜져 있을 때만 표시한다.
    var isShowingUnitCoverage: Bool { showUnitCoverage && layers.activePropertyType == .unit }
}

struct UnitCoverageCache {
    var units: [[[LocalPoint]]]
    var levels: [[[LocalPoint]]]
    var result: UnitCoverage.Result
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
            .help("같은 층 unit 사이의 빈틈(빨간 점무늬)과 겹침(빨간 빗금)을 도면에 표시합니다.")
            if env.showUnitCoverage {
                let r = env.unitCoverage
                Text(r.isEmpty ? "없음" : "빈틈 \(r.gaps.count) · 겹침 \(r.overlaps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(r.isEmpty ? Color.secondary : Color.red)
                    .fixedSize()
            }
        }
    }
}
