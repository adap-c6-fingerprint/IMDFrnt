import CoreLocation
import MapKit
import SwiftUI

/// Anchor 지도의 장소 검색(2026-08-26 요청).
///
/// 지도에서 건물을 찾으려면 지도를 손으로 끌어 목표 지점까지 가야 한다.
/// 도면 하나를 지오레퍼런싱할 때마다 반복되는 이동이라, 이름으로 한 번에 가는 길을 연다.
/// **검색은 지도를 옮기기만 한다** — Anchor 쌍을 만드는 것은 지금처럼 사용자의 클릭뿐이다.
/// 검색 결과 좌표를 곧바로 Anchor로 넣지 않는 이유는, MapKit이 돌려주는 점이
/// 건물 대표점(입구·중심)이라 도면의 특정 모서리와 대응하는 점이 아니기 때문이다.
@MainActor
final class PlaceSearchModel: ObservableObject {

    struct PlaceResult: Identifiable {
        let id = UUID()
        let name: String
        let subtitle: String
        let coordinate: CLLocationCoordinate2D
        let boundingRegion: MKCoordinateRegion
    }

    @Published var query = ""
    @Published private(set) var results: [PlaceResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var message: String?

    private var running: MKLocalSearch?

    var hasResults: Bool { !results.isEmpty }

    /// 결과 목록을 띄울지. 검색어를 지우거나 결과를 고르면 닫힌다.
    var isShowingResults: Bool { !results.isEmpty || message != nil }

    // MARK: 검색

    /// - Parameter region: 지금 지도가 보고 있는 범위. 같은 이름의 장소가 전국에 여러 개일 때
    ///   화면 근처를 먼저 돌려주게 하는 편향값이다. 없으면 편향 없이 검색한다.
    func search(around region: MKCoordinateRegion?) {
        guard let text = Self.normalized(query) else {
            clear()
            return
        }

        running?.cancel()
        // 앞선 검색이 끝나기 전에 다시 누르면 두 응답이 순서 없이 도착해 옛 결과가 나중에 덮어쓴다.
        // 새 검색을 시작하기 전에 이전 것을 반드시 취소한다.

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let region { request.region = region }

        isSearching = true
        message = nil
        let search = MKLocalSearch(request: request)
        running = search

        search.start { [weak self] response, error in
            Task { @MainActor in
                guard let self, self.running === search else { return }
                // 취소된 검색의 응답은 버린다 — `cancel()`도 콜백을 부른다.
                self.running = nil
                self.isSearching = false

                if let response {
                    self.results = response.mapItems.compactMap(Self.makeResult)
                    self.message = self.results.isEmpty ? "검색 결과가 없습니다." : nil
                    return
                }
                self.results = []
                self.message = Self.failureMessage(for: error)
            }
        }
    }

    func clear() {
        running?.cancel()
        running = nil
        isSearching = false
        results = []
        message = nil
    }

    /// 결과를 골랐을 때. 목록만 닫고 검색어는 남긴다 — 같은 검색어로 다른 후보를 다시 볼 수 있다.
    func dismissResults() {
        results = []
        message = nil
    }

    // MARK: 순수 계산 (GUI 없이 `--selftest`로 검증하는 부분)

    /// 공백뿐인 검색어를 걸러낸다. 빈 검색은 MapKit 호출 자체를 하지 않는다.
    static func normalized(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func makeResult(_ item: MKMapItem) -> PlaceResult? {
        let placemark = item.placemark
        guard CLLocationCoordinate2DIsValid(placemark.coordinate) else { return nil }

        var meters = defaultMeters
        if let circle = placemark.region as? CLCircularRegion {
            meters = circle.radius * 2
        }
        // MapKit이 장소의 크기를 원으로 알려줄 때만 그 크기를 쓴다.
        // 지름(반지름 × 2)이어야 그 장소가 화면에 다 들어온다.

        return PlaceResult(name: item.name ?? placemark.name ?? "이름 없는 장소",
                           subtitle: subtitle(for: placemark),
                           coordinate: placemark.coordinate,
                           boundingRegion: MKCoordinateRegion(center: placemark.coordinate,
                                                              latitudinalMeters: clampMeters(meters),
                                                              longitudinalMeters: clampMeters(meters)))
    }

    /// 주소 줄. `title`은 이름과 겹치는 경우가 많아 쓰지 않는다.
    static func subtitle(for placemark: MKPlacemark) -> String {
        let parts = [placemark.administrativeArea, placemark.locality,
                     placemark.thoroughfare, placemark.subThoroughfare]
        let joined = parts.compactMap { $0 }.joined(separator: " ")
        return joined.isEmpty ? String(format: "%.5f, %.5f",
                                       placemark.coordinate.longitude,
                                       placemark.coordinate.latitude)
                              : joined
    }

    /// 고른 장소로 이동할 때 쓸 지도 범위.
    /// **건물 모서리를 찍을 수 있을 만큼 가깝게** 맞춘다 — MapKit이 주는 범위를 그대로 쓰면
    /// 넓은 부지(대학·병원)에서는 캠퍼스 전체가 잡혀 다시 확대해야 하고,
    /// 점 하나짜리 관심지점에서는 지나치게 당겨져 주변을 잃는다.
    static let defaultMeters: CLLocationDistance = 300
    static let minimumMeters: CLLocationDistance = 150
    static let maximumMeters: CLLocationDistance = 1200

    static func focusRegion(for result: PlaceResult) -> MKCoordinateRegion {
        let span = result.boundingRegion.span
        let latMeters = clampMeters(span.latitudeDelta * 111_000)
        let lonMeters = clampMeters(span.longitudeDelta * 111_000
                                    * cos(result.coordinate.latitude * .pi / 180))
        return MKCoordinateRegion(center: result.coordinate,
                                  latitudinalMeters: latMeters,
                                  longitudinalMeters: lonMeters)
    }

    static func clampMeters(_ m: CLLocationDistance) -> CLLocationDistance {
        guard m.isFinite, m > 0 else { return defaultMeters }
        return min(maximumMeters, max(minimumMeters, m))
    }

    /// 실패 문구. 네트워크가 끊긴 경우와 결과가 없는 경우를 구분한다 —
    /// 사용자가 검색어를 고칠 일인지, 인터넷을 확인할 일인지가 다르다.
    static func failureMessage(for error: Error?) -> String {
        guard let error else { return "검색에 실패했습니다." }
        if let mk = error as? MKError {
            switch mk.code {
            case .placemarkNotFound: return "검색 결과가 없습니다."
            case .loadingThrottled: return "검색이 잠시 제한되었습니다. 잠시 뒤 다시 시도하세요."
            case .serverFailure: return "지도 서버에 연결하지 못했습니다. 인터넷 연결을 확인하세요."
            default: break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "인터넷에 연결되어 있지 않아 장소를 검색할 수 없습니다."
        }
        return "검색에 실패했습니다. (\(ns.localizedDescription))"
    }
}
