import Foundation

/// 명세 9-3-4)의 잔차·RMS 계산.
/// 사용자가 Anchor을 잘못 찍었는지 알려주는 유일한 수단이다.
enum ResidualCalculator {

    /// 쌍별 잔차(m). 변환식을 적용한 결과와 사용자가 지정한 위경도 사이의 지표 거리.
    static func residuals(of transform: GeoAffineTransform,
                          against pairs: [AnchorPair]) -> [Double] {
        pairs.map { pair in
            let predicted = transform.apply(pair.local)
            return metersBetween(predicted, pair.geo)
        }
    }

    static func rms(_ residuals: [Double]) -> Double {
        guard !residuals.isEmpty else { return 0 }
        let sumSq = residuals.reduce(0) { $0 + $1 * $1 }
        return (sumSq / Double(residuals.count)).squareRoot()
    }

    /// 평균에서 크게 벗어난 쌍의 인덱스. UI가 이 쌍을 붉게 표시한다.
    static func outliers(_ residuals: [Double], sigma: Double = 2.0) -> Set<Int> {
        guard residuals.count > 3 else { return [] }
        let mean = residuals.reduce(0, +) / Double(residuals.count)
        let variance = residuals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(residuals.count)
        let sd = variance.squareRoot()
        guard sd > 1e-9 else { return [] }
        var out: Set<Int> = []
        for (i, r) in residuals.enumerated() where (r - mean) / sd > sigma { out.insert(i) }
        return out
    }

    /// 등거리 원통 근사. 실내 지도 규모(수백 m)에서는 충분하다.
    static func metersBetween(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let latRad = (a.latitude + b.latitude) / 2 * .pi / 180
        let dx = (a.longitude - b.longitude) * 111_320 * cos(latRad)
        let dy = (a.latitude - b.latitude) * 110_540
        return hypot(dx, dy)
    }
}
