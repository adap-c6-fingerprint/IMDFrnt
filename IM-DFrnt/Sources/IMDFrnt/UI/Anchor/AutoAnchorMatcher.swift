import Foundation

/// 도면 외곽과 지도 외곽을 윤곽 모양으로 맞춘 결과. 쌍은 사용자가 적용하기 전까지 저장하지 않는다.
struct AutoAnchorProposal {
    let pairs: [AnchorPair]
    let rmsMeters: Double
    let relativeError: Double

    /// 외곽이 크게 다른데 앵커를 적용하면 그럴듯한 잔차가 잘못된 위치를 감출 수 있다.
    var canApply: Bool { relativeError <= 0.06 && rmsMeters <= 3 }
}

enum AutoAnchorMatcher {
    private struct Point {
        var x: Double
        var y: Double
    }

    private struct Fit {
        let rms: Double
        let shift: Int
        let reversed: Bool
    }

    static func propose(localOutline: [LocalPoint], building: BuildingFootprint) -> AutoAnchorProposal? {
        let local = clean(localOutline.map { Point(x: $0.x, y: -$0.y) })
        let geo = building.coordinates
        guard local.count >= 4, geo.count >= 4 else { return nil }
        let center = building.center
        let metersPerLongitude = 111_000 * cos(center.latitude * .pi / 180)
        let target = clean(geo.map {
            Point(x: ($0.longitude - center.longitude) * metersPerLongitude,
                  y: ($0.latitude - center.latitude) * 111_000)
        })
        let count = 32
        guard let localSample = resample(local, count: count),
              let targetForward = resample(target, count: count),
              let targetReverse = resample(Array(target.reversed()), count: count) else { return nil }

        var best: Fit?
        for reversed in [false, true] {
            let targetSample = reversed ? targetReverse : targetForward
            for shift in 0..<count {
                let paired = (0..<count).map { targetSample[($0 + shift) % count] }
                guard let rms = similarityRMS(from: localSample, to: paired) else { continue }
                if rms < (best?.rms ?? .infinity) {
                    best = Fit(rms: rms, shift: shift, reversed: reversed)
                }
            }
        }
        guard let best else { return nil }
        let targetSample = best.reversed ? targetReverse : targetForward
        let selected = [0, 8, 16, 24]
        let pairs = selected.enumerated().map { index, sampleIndex in
            let source = localSample[sampleIndex]
            let destination = targetSample[(sampleIndex + best.shift) % count]
            return AnchorPair(
                local: LocalPoint(source.x, -source.y),
                geo: GeoPoint(longitude: center.longitude + destination.x / metersPerLongitude,
                              latitude: center.latitude + destination.y / 111_000),
                label: "외곽 후보 \(index + 1)")
        }
        let minX = target.map(\.x).min()!, maxX = target.map(\.x).max()!
        let minY = target.map(\.y).min()!, maxY = target.map(\.y).max()!
        let diagonal = hypot(maxX - minX, maxY - minY)
        guard diagonal > 1 else { return nil }
        return AutoAnchorProposal(pairs: pairs, rmsMeters: best.rms,
                                  relativeError: best.rms / diagonal)
    }

    private static func clean(_ points: [Point]) -> [Point] {
        var result: [Point] = []
        for p in points where p.x.isFinite && p.y.isFinite {
            if let last = result.last, hypot(p.x - last.x, p.y - last.y) < 1e-8 { continue }
            result.append(p)
        }
        if result.count > 1, let first = result.first, let last = result.last,
           hypot(first.x - last.x, first.y - last.y) < 1e-8 { result.removeLast() }
        return result
    }

    private static func resample(_ ring: [Point], count: Int) -> [Point]? {
        guard ring.count >= 3 else { return nil }
        var lengths: [Double] = []
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            lengths.append(hypot(b.x - a.x, b.y - a.y))
        }
        let perimeter = lengths.reduce(0, +)
        guard perimeter > 1e-6 else { return nil }
        var result: [Point] = []
        var edge = 0
        var passed = 0.0
        for i in 0..<count {
            let distance = perimeter * Double(i) / Double(count)
            while edge < lengths.count - 1 && passed + lengths[edge] < distance {
                passed += lengths[edge]
                edge += 1
            }
            let fraction = lengths[edge] > 0 ? (distance - passed) / lengths[edge] : 0
            let a = ring[edge], b = ring[(edge + 1) % ring.count]
            result.append(Point(x: a.x + fraction * (b.x - a.x),
                                y: a.y + fraction * (b.y - a.y)))
        }
        return result
    }

    private static func similarityRMS(from source: [Point], to target: [Point]) -> Double? {
        let n = Double(source.count)
        let sourceX = source.map(\.x).reduce(0, +) / n
        let sourceY = source.map(\.y).reduce(0, +) / n
        let targetX = target.map(\.x).reduce(0, +) / n
        let targetY = target.map(\.y).reduce(0, +) / n
        var denominator = 0.0, dot = 0.0, cross = 0.0
        for i in source.indices {
            let px = source[i].x - sourceX, py = source[i].y - sourceY
            let qx = target[i].x - targetX, qy = target[i].y - targetY
            denominator += px * px + py * py
            dot += px * qx + py * qy
            cross += px * qy - py * qx
        }
        guard denominator > 1e-12 else { return nil }
        let a = dot / denominator, b = cross / denominator
        let error = source.indices.reduce(0.0) { sum, i in
            let px = source[i].x - sourceX, py = source[i].y - sourceY
            let dx = a * px - b * py + targetX - target[i].x
            let dy = b * px + a * py + targetY - target[i].y
            return sum + dx * dx + dy * dy
        }
        return sqrt(error / n)
    }
}
