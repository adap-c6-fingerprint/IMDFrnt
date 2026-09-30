import Foundation

/// 어파인 변환(자유도 6). 상사 변환(자유도 4)이 아니라 어파인을 쓰는 이유는
/// 도면이 가로세로 다른 비율로 저장됐거나 기울어져 있을 가능성을 배제할 수 없기 때문이다.
struct GeoAffineTransform: Hashable {
    let a: Double, b: Double, c: Double
    // lon = a·x + b·y + c
    let d: Double, e: Double, f: Double
    // lat = d·x + e·y + f

    enum FitError: Error, CustomStringConvertible {
        case insufficientPairs(have: Int, need: Int)
        case degenerateConfiguration

        var description: String {
            switch self {
            case .insufficientPairs(let have, let need):
                return "Anchor이 \(have)쌍뿐입니다. 최소 \(need)쌍이 필요합니다."
            case .degenerateConfiguration:
                return "Anchor이 한 직선 위에 몰려 있어 변환식을 계산할 수 없습니다. 서로 떨어진 위치로 다시 찍어 주세요."
            }
        }
    }

    static let minimumPairs = 3
    // 어파인 자유도 6 ÷ 2. 명세 9-3-1)
    static let recommendedPairs = 4
    // 잔차가 나오기 시작하는 최소치. 명세 9-3-2)

    static func fit(from pairs: [AnchorPair]) throws -> GeoAffineTransform {
        guard pairs.count >= minimumPairs else {
            throw FitError.insufficientPairs(have: pairs.count, need: minimumPairs)
        }
        // 정규방정식 Mᵀ M β = Mᵀ y 를 lon·lat 각각에 대해 푼다.
        // 두 계열이 같은 3x3 행렬을 공유하므로 한 번만 만든다.
        var m = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var rhsLon = [Double](repeating: 0, count: 3)
        var rhsLat = [Double](repeating: 0, count: 3)

        for p in pairs {
            let v = [p.local.x, p.local.y, 1.0]
            for i in 0..<3 {
                for j in 0..<3 { m[i][j] += v[i] * v[j] }
                rhsLon[i] += v[i] * p.geo.longitude
                rhsLat[i] += v[i] * p.geo.latitude
            }
        }

        guard let lon = solve3x3(m, rhsLon), let lat = solve3x3(m, rhsLat) else {
            throw FitError.degenerateConfiguration
        }
        return GeoAffineTransform(a: lon[0], b: lon[1], c: lon[2],
                                  d: lat[0], e: lat[1], f: lat[2])
    }

    /// 2쌍만으로 만드는 **미리보기 전용** 상사 변환(자유도 4).
    /// 어파인(3쌍)이 성립하기 전에 "도면 겹쳐보기"로 정합을 눈으로 확인하기 위한 것이며,
    /// 좌표 확정·내보내기에는 절대 쓰지 않는다.
    static func fitSimilarity(from pairs: [AnchorPair]) -> GeoAffineTransform? {
        guard pairs.count >= 2 else { return nil }
        let p1 = pairs[0], p2 = pairs[1]

        let lat0 = (p1.geo.latitude + p2.geo.latitude) / 2
        let cosLat = max(0.0001, cos(lat0 * .pi / 180))
        // 경도 1도의 실거리는 위도에 따라 줄어든다. 보정하지 않으면 도면이 옆으로 늘어난다.

        // SVG는 y가 아래로 증가하고 위도는 위로 증가하므로 부호를 뒤집어 맞춘다.
        let q1 = (x: p1.local.x, y: -p1.local.y)
        let q2 = (x: p2.local.x, y: -p2.local.y)
        let cap1 = (x: p1.geo.longitude * cosLat, y: p1.geo.latitude)
        let cap2 = (x: p2.geo.longitude * cosLat, y: p2.geo.latitude)

        let dqx = q2.x - q1.x, dqy = q2.y - q1.y
        let denom = dqx * dqx + dqy * dqy
        guard denom > 1e-12 else { return nil }
        let dQx = cap2.x - cap1.x, dQy = cap2.y - cap1.y

        let u = (dQx * dqx + dQy * dqy) / denom
        let v = (dQy * dqx - dQx * dqy) / denom
        let tx = cap1.x - (u * p1.local.x + v * p1.local.y)
        let ty = cap1.y - (v * p1.local.x - u * p1.local.y)

        return GeoAffineTransform(a: u / cosLat, b: v / cosLat, c: tx / cosLat,
                                  d: v, e: -u, f: ty)
    }

    func apply(_ p: LocalPoint) -> GeoPoint {
        GeoPoint(longitude: a * p.x + b * p.y + c,
                 latitude: d * p.x + e * p.y + f)
    }

    /// 부분 피벗 가우스 소거. 특이행렬이면 nil.
    private static func solve3x3(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var m = matrix
        var v = rhs
        for col in 0..<3 {
            var pivot = col
            for r in (col + 1)..<3 where abs(m[r][col]) > abs(m[pivot][col]) { pivot = r }
            if abs(m[pivot][col]) < 1e-12 { return nil }
            if pivot != col { m.swapAt(pivot, col); v.swapAt(pivot, col) }
            for r in (col + 1)..<3 {
                let factor = m[r][col] / m[col][col]
                if factor == 0 { continue }
                for k in col..<3 { m[r][k] -= factor * m[col][k] }
                v[r] -= factor * v[col]
            }
        }
        var out = [Double](repeating: 0, count: 3)
        for r in stride(from: 2, through: 0, by: -1) {
            var s = v[r]
            for k in (r + 1)..<3 { s -= m[r][k] * out[k] }
            out[r] = s / m[r][r]
        }
        return out.allSatisfy { $0.isFinite } ? out : nil
    }
}
