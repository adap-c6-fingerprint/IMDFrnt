import CoreLocation
import MapKit

/// Anchor 지도의 좌표 계산. GUI 없이 `--selftest`로 검증할 수 있도록 뷰에서 떼어 놓는다.
enum AnchorMapMath {

    /// 마커를 집은 순간의 "집은 지점 → 마커 중심" 차이(도 단위).
    ///
    /// 이 값을 기억하지 않고 마커를 커서 좌표에 그대로 대입하면, **집는 순간 마커가 커서 자리로
    /// 순간이동한다.** 집기 허용 반경이 22pt인데 넓게 축소한 지도에서 22pt는 실제로 몇 km다 —
    /// 사용자에게는 "작게 움직였는데 몇 km 튀었다"로 보인다. 축척과 무관하게 **집은 자리 그대로**
    /// 끌리게 하려면 차이를 유지해야 한다.
    static func grabOffset(cursor: CLLocationCoordinate2D,
                           marker: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: marker.latitude - cursor.latitude,
                               longitude: marker.longitude - cursor.longitude)
    }

    /// 드래그 중 마커가 놓일 좌표. 커서 좌표에 집은 순간의 차이를 그대로 더한다.
    static func draggedCoordinate(cursor: CLLocationCoordinate2D,
                                  grab: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: cursor.latitude + grab.latitude,
                               longitude: cursor.longitude + grab.longitude)
    }

    /// Anchor 전부가 들어오는 지도 범위.
    ///
    /// 화면을 이 범위로 **못 박아 두는 것**이 목적이다. `MapCameraPosition.automatic`으로 두면
    /// 지도가 표시 중인 내용(마커·겹쳐 놓은 도면)에 맞춰 스스로 화면을 다시 잡는다.
    /// 그 상태로 마커를 끌면 마커가 움직일 때마다 지도가 다시 맞춰지고, 커서 아래 좌표가
    /// 매 프레임 달라져 **마커가 점점 멀리 달아난다.** 축척이 반영되지 않는 것처럼 보이는
    /// 두 번째 원인이 이것이다.
    static let minimumSpanMeters: CLLocationDistance = 300
    static let paddingRatio = 1.6

    static func regionFitting(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates.dropFirst() {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let minLatDelta = minimumSpanMeters / 111_000
        let minLonDelta = minLatDelta / max(0.2, cos(center.latitude * .pi / 180))
        // 경도 1도의 실제 거리는 위도가 높을수록 짧아진다. 위도와 같은 값을 쓰면
        // 고위도에서 가로로 지나치게 넓은 화면이 된다.

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * paddingRatio, minLatDelta),
                longitudeDelta: max((maxLon - minLon) * paddingRatio, minLonDelta)))
    }
}
