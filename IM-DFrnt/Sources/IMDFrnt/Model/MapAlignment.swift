import CoreGraphics
import Foundation

/// 지도 위에 직접 맞춘 층 도면의 자리(신기능 11항, #31).
///
/// **왜 필요한가:** 종전 Anchor는 도면 점과 위성사진 점을 하나씩 짝지었다. 도면 쪽 점은 꼭짓점·교점이라
/// 정확하지만, 위성사진 쪽은 사용자가 눈대중으로 찍어 건물 모양이 비뚤어질 수 있다. 여기서는 도면을 통째로
/// 지도 위에 올려 이동·회전·크기만 조절해 맞춘다. 도면 모양은 그대로이므로 비뚤어질 여지가 없다.
///
/// **이동·회전·비율 고정 크기만 둔다(닮음 변환).** 가로·세로를 따로 늘리면 도면이 찌그러져, 정렬이 맞아
/// 보여도 방의 모양이 실제와 달라진다(사용자 결정, 2026-10-15).
struct MapAlignment: Codable, Equatable, Sendable {
    /// 도면 캔버스 중심이 놓인 위경도.
    var center: GeoPoint
    /// 도면 캔버스 중심(도면 좌표). 회전·크기 조절의 축이다. 정렬값만으로 좌표를 바꿀 수 있게 함께 담는다 —
    /// 그래야 도면을 불러오지 않은 층의 Anchor 위경도도 다시 계산할 수 있다.
    var canvasCenter: LocalPoint
    /// 도면 1단위가 몇 m인가. 크기 조절이 이 값을 바꾼다.
    var metersPerUnit: Double
    /// 시계 방향 회전각(도). 0이면 도면 위쪽이 북쪽이다.
    var rotationDegrees: Double = 0
    var opacity: Double = 0.6
    var isVisible = true
    /// 잠근 층은 끌거나 돌릴 수 없다. 아래층을 맞춘 뒤 잠가 두고 위층을 맞추는 흐름이다.
    var isLocked = false
    /// '이 층 정렬 완료'를 눌렀는가. 진행 표시(N / M층 정렬됨)가 이 값을 센다.
    var isConfirmed = false
    /// 쌓는 순서. 클수록 위에 그린다.
    var stackOrder: Int = 0

    /// 도면 좌표 → 위경도. 건물 하나 크기에서는 평면 근사로 충분하다(오차는 수 cm 수준).
    func geoPoint(for p: LocalPoint) -> GeoPoint {
        let (east, north) = meters(for: p)
        return GeoPoint(longitude: center.longitude + east / metersPerDegreeLongitude,
                        latitude: center.latitude + north / Self.metersPerDegreeLatitude)
    }

    /// 위경도 → 도면 좌표. 지도에서 누른 자리를 도면 점으로 되돌릴 때 쓴다.
    func localPoint(for g: GeoPoint) -> LocalPoint? {
        let c = canvasCenter
        guard metersPerUnit > 0 else { return nil }
        let east = (g.longitude - center.longitude) * metersPerDegreeLongitude
        let north = (g.latitude - center.latitude) * Self.metersPerDegreeLatitude
        let r = rotationDegrees * .pi / 180
        // 화면 좌표(y 아래) 기준 시계 방향 회전의 역변환.
        let sx = east, sy = -north
        let x = (sx * cos(r) + sy * sin(r)) / metersPerUnit
        let y = (-sx * sin(r) + sy * cos(r)) / metersPerUnit
        return LocalPoint(c.x + x, c.y + y)
    }

    /// 같은 변환을 Anchor 계산용 어파인 계수로 낸다. 정렬로 만든 Anchor 쌍을 이 식에 넣으면 잔차가 0이다.
    var affine: GeoAffineTransform {
        let c = canvasCenter
        let o = geoPoint(for: c)
        let ex = geoPoint(for: LocalPoint(c.x + 1, c.y))
        let ey = geoPoint(for: LocalPoint(c.x, c.y + 1))
        let a = ex.longitude - o.longitude, b = ey.longitude - o.longitude
        let d = ex.latitude - o.latitude, e = ey.latitude - o.latitude
        return GeoAffineTransform(a: a, b: b, c: o.longitude - a * c.x - b * c.y,
                                  d: d, e: e, f: o.latitude - d * c.x - e * c.y)
    }

    private func meters(for p: LocalPoint) -> (east: Double, north: Double) {
        let c = canvasCenter
        let dx = (p.x - c.x) * metersPerUnit, dy = (p.y - c.y) * metersPerUnit
        let r = rotationDegrees * .pi / 180
        // 도면은 y가 아래로 커진다. 화면에서 시계 방향으로 돌린 뒤 y를 뒤집어 북쪽을 얻는다.
        let sx = dx * cos(r) - dy * sin(r)
        let sy = dx * sin(r) + dy * cos(r)
        return (sx, -sy)
    }

    static let metersPerDegreeLatitude = 111_320.0
    var metersPerDegreeLongitude: Double { Self.metersPerDegreeLatitude * max(0.0001, cos(center.latitude * .pi / 180)) }

    /// 처음 올릴 때의 자리. 지도 가운데에 도면 폭이 보이는 지도 폭의 절반쯤 되게 놓는다.
    static func initial(center: GeoPoint, visibleWidthMeters: Double, canvasSize: CGSize) -> MapAlignment {
        let width = max(1, Double(max(canvasSize.width, canvasSize.height)))
        return MapAlignment(center: center,
                            canvasCenter: LocalPoint(Double(canvasSize.width) / 2, Double(canvasSize.height) / 2),
                            metersPerUnit: clampedMetersPerUnit(visibleWidthMeters * 0.5 / width, canvasSize: canvasSize))
    }

    /// 도면 긴 변이 실제로 몇 m까지 될 수 있는가. 건물 한 동 범위다.
    static let longestSideMeters: ClosedRange<Double> = 1...10_000

    /// 크기를 건물 범위 안으로 묶는다. **묶지 않으면** 모서리를 중심까지 끌었을 때 도면이 한 점으로 뭉쳐 다시 잡을 수 없고,
    /// 세계 지도 배율에서 올리면 모서리 위도가 90°를 넘어 지도 좌표가 무효가 된다.
    static func clampedMetersPerUnit(_ value: Double, canvasSize: CGSize) -> Double {
        let width = max(1, Double(max(canvasSize.width, canvasSize.height)))
        let range = longestSideMeters
        guard value.isFinite else { return range.lowerBound / width }
        return min(max(value * width, range.lowerBound), range.upperBound) / width
    }
}
