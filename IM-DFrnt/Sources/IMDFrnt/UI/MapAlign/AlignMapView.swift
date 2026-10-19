import AppKit
import MapKit
import SwiftUI
import WebKit

/// 지도 정렬 화면의 지도(신기능 11항, #31). **네이버 지도 Web Dynamic Map v3**를 WKWebView에 띄운다(2026-10-19 사용자 결정,
/// 종전 MapKit 대체). 장소 검색은 종전 MapKit 검색을 그대로 쓴다.
///
/// **도면은 지도 안(JS 오버레이)에서 그린다.** 처음 MapKit 때 SwiftUI Canvas를 지도 위에 얹었더니 카메라 알림이 한 박자
/// 늦어 지도를 끌면 도면이 움찔거렸다(2026-10-15 사용자 확인). 네이버 지도의 `OverlayView`는 지도 타일과 같은 판(pane)에
/// 붙어 함께 움직이므로 흔들리지 않는다. 도면 선은 처음 한 번만 SVG 경로로 넘기고, 정렬이 바뀌면 변환 행렬만 바꾼다.
///
/// **화면 좌표 변환은 Swift에서 바로 계산한다.** JS에 물으면 답이 비동기라 손 동작에 쓸 수 없다. 지도가 움직일 때마다
/// 보이는 범위(남서·북동 위경도)와 화면 크기를 받아 두고, 웹 메르카토르 식으로 오간다(`NaverMapViewport`).
struct AlignMapView: NSViewRepresentable {
    let controller: MapAlignMapController
    let mapKind: NaverMapKind
    let layers: [AlignOverlay]
    let clientID: String

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: NaverMapPage.messageName)
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsMagnification = false
        // 핀치는 앱이 지도 확대로 바꿔 넘긴다. 웹 페이지 확대가 켜져 있으면 지도가 아니라 화면 전체가 커진다.
        web.navigationDelegate = context.coordinator
        controller.webView = web
        controller.startForwardingZoom()
        context.coordinator.load(web, clientID: clientID, mapKind: mapKind)
        return web
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.controller.stopForwardingZoom()
        web.configuration.userContentController.removeScriptMessageHandler(forName: NaverMapPage.messageName)
        // 메시지 처리기는 WebKit이 붙잡고 있어 떼지 않으면 Coordinator가 풀리지 않는다.
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        if c.loadedClientID != clientID {
            c.load(web, clientID: clientID, mapKind: mapKind)
        }
        c.setMapKind(mapKind)
        c.sync(layers)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let controller: MapAlignMapController
        private(set) var loadedClientID: String?
        private var mapKind: NaverMapKind?
        private var wanted: [AlignOverlay] = []
        private var shown: [String: AlignOverlay] = [:]
        private var shownOrder: [String] = []
        /// 층마다 JS에 넘긴 도면 경로·꼭짓점 목록의 키. 같으면 다시 넘기지 않는다 — 도면 경로는 수 MB라 정렬을 바꿀 때마다
        /// 넘기면 끄는 동안 버벅인다.
        private var sentPathKeys: [String: String] = [:]
        private var sentSnapKeys: [String: Int] = [:]
        private var svgCache: [String: String] = [:]
        private var svgBuilding: Set<String> = []

        init(controller: MapAlignMapController) { self.controller = controller }

        func load(_ web: WKWebView, clientID: String, mapKind: NaverMapKind) {
            loadedClientID = clientID
            self.mapKind = mapKind
            resetSent()
            controller.mapWillLoad(hasClientID: !clientID.isEmpty)
            guard !clientID.isEmpty else {
                web.loadHTMLString(NaverMapPage.blankHTML, baseURL: NaverMapPage.baseURL)
                return
            }
            web.loadHTMLString(NaverMapPage.html(clientID: clientID, mapKind: mapKind), baseURL: NaverMapPage.baseURL)
        }

        private func resetSent() {
            shown = [:]; shownOrder = []
            sentPathKeys = [:]; sentSnapKeys = [:]
        }

        func setMapKind(_ kind: NaverMapKind) {
            guard kind != mapKind else { return }
            mapKind = kind
            controller.run("IMDF.setMapType('\(kind.naverID)')")
        }

        /// 바뀐 겹만 JS로 보낸다. 투명도만 바뀌면 투명도만 바꾼다 — 슬라이더를 끄는 동안 도면을 다시 넘기면 버벅인다.
        func sync(_ layers: [AlignOverlay]) {
            wanted = layers
            guard controller.status == .ready else { return }
            // 지도가 준비되기 전 값은 들고 있다가 준비되면 한 번에 보낸다.
            var script: [String] = []
            let order = layers.map(\.id)
            for layer in layers {
                if let old = shown[layer.id], old.signature == layer.signature {
                    if old.opacity != layer.opacity {
                        script.append("IMDF.setOpacity(\(Self.json(layer.id)),\(layer.opacity))")
                    }
                } else {
                    script.append("IMDF.putLayer(\(payload(for: layer)))")
                }
                shown[layer.id] = layer
            }
            for id in shownOrder where !order.contains(id) {
                shown[id] = nil
                sentPathKeys[id] = nil
                sentSnapKeys[id] = nil
            }
            if order != shownOrder || !script.isEmpty {
                script.append("IMDF.setOrder(\(Self.json(order)))")
                // 쌓는 순서를 맞추고, 목록에 없는 겹은 지도에서 뗀다.
            }
            shownOrder = order
            guard !script.isEmpty else { return }
            controller.run(script.joined(separator: ";"))
        }

        private func payload(for layer: AlignOverlay) -> String {
            let sig = layer.signature
            let a = sig.alignment
            let c = a.canvasCenter, k = 100.0
            let o = a.geoPoint(for: c)
            let x = a.geoPoint(for: LocalPoint(c.x + k, c.y))
            let y = a.geoPoint(for: LocalPoint(c.x, c.y + k))
            var out: [String: Any] = [
                "id": layer.id,
                "kind": sig.kind.rawValue,
                "frame": ["o": [o.longitude, o.latitude], "x": [x.longitude, x.latitude],
                          "y": [y.longitude, y.latitude], "k": k, "c": [c.x, c.y]],
                // 도면 중심과 x·y 방향 100단위 점의 위경도. JS가 이 세 점을 지도 판 좌표로 바꿔 어파인 행렬을 만든다 —
                // 건물 하나 범위에서는 지도 투영이 사실상 평면이라 세 점으로 충분하다.
                "w": Double(layer.canvasSize.width), "h": Double(layer.canvasSize.height),
                "opacity": layer.opacity,
                "stroke": sig.isStandardMap ? "#000000" : "#ffffff",
                "handles": sig.showHandles,
                "anchors": sig.anchors.map { ["x": $0.point.x, "y": $0.point.y, "f": $0.isFeature,
                                              "s": $0.isSelected, "p": $0.isPaired] },
            ]
            if sig.kind == .drawing, sentPathKeys[layer.id] != sig.pathKey {
                if let d = svgPath(layer.path, key: sig.pathKey) {
                    out["d"] = d
                    sentPathKeys[layer.id] = sig.pathKey
                } else {
                    out["d"] = ""
                    // 경로를 만드는 동안은 이전 도면 선을 지운다. 다 되면 다시 보낸다.
                }
            }
            if sig.kind == .decoration, sentSnapKeys[layer.id] != sig.snapKey {
                out["snaps"] = (layer.snaps?.points ?? []).flatMap { [$0.point.x, $0.point.y] }
                sentSnapKeys[layer.id] = sig.snapKey
            }
            return Self.json(out)
        }

        /// 도면 경로의 SVG 문자열. 없으면 백그라운드에서 만들고 nil을 돌려준다 — 개체 6만 개 도면은 문자열 만들기만
        /// 수백 ms라 메인 스레드에서 하면 화면이 멈춘다. 다 되면 그 겹을 다시 보낸다.
        private func svgPath(_ path: Path, key: String) -> String? {
            if let hit = svgCache[key] { return hit }
            guard !svgBuilding.contains(key) else { return nil }
            svgBuilding.insert(key)
            Task.detached(priority: .userInitiated) {
                let d = NaverMapPage.svgPathData(path)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.svgBuilding.remove(key)
                    if self.svgCache.count > 8 { self.svgCache = [:] }
                    self.svgCache[key] = d
                    for (id, layer) in self.shown where layer.signature.pathKey == key { self.shown[id] = nil }
                    self.sync(self.wanted)
                }
            }
            return nil
        }

        static func json(_ value: Any) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
                  let s = String(data: data, encoding: .utf8) else { return "null" }
            return s
        }

        // MARK: JS → Swift

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                resetSent()
                controller.mapReady()
                sync(wanted)
            case "bounds":
                if let v = NaverMapViewport(message: body) { controller.viewportChanged(v) }
            case "authFailure":
                controller.mapFailed(.authFailed)
            case "loadError":
                controller.mapFailed(.loadFailed)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            controller.mapFailed(.loadFailed)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            controller.mapFailed(.loadFailed)
        }
    }
}

/// 지도 종류. 네이버 지도 `MapTypeId` 값과 짝을 이룬다.
enum NaverMapKind: String, CaseIterable, Sendable {
    case standard, imagery, hybrid

    var title: String {
        switch self {
        case .standard: return "일반 지도"
        case .imagery: return "위성"
        case .hybrid: return "위성+이름"
        }
    }

    var naverID: String {
        switch self {
        case .standard: return "NORMAL"
        case .imagery: return "SATELLITE"
        case .hybrid: return "HYBRID"
        }
    }
}

/// 네이버 클라우드 Maps의 Client ID. 사용자마다 콘솔에서 발급받아 넣는다 — 레포에 키를 넣지 않는다.
enum NaverMapSettings {
    static let clientIDKey = "naverMapsClientID"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: clientIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientIDKey) }
    }
}

/// 네이버 지도가 알려 준 지금 화면 범위. 웹 메르카토르 지도라 화면 x는 경도에, y는 메르카토르 y에 비례한다.
/// 지도를 돌리지 않으므로(네이버 웹 지도는 회전이 없다) 남서·북동 두 점과 화면 크기로 화면 ↔ 위경도가 정확히 정해진다.
struct NaverMapViewport: Equatable, Sendable {
    var southWest: GeoPoint
    var northEast: GeoPoint
    var size: CGSize

    init(southWest: GeoPoint, northEast: GeoPoint, size: CGSize) {
        self.southWest = southWest
        self.northEast = northEast
        self.size = size
    }

    init?(message body: [String: Any]) {
        func pair(_ key: String) -> GeoPoint? {
            guard let a = body[key] as? [Double], a.count == 2 else { return nil }
            return GeoPoint(longitude: a[0], latitude: a[1])
        }
        guard let sw = pair("sw"), let ne = pair("ne"),
              let w = body["w"] as? Double, let h = body["h"] as? Double, w > 0, h > 0,
              ne.longitude > sw.longitude, ne.latitude > sw.latitude else { return nil }
        self.init(southWest: sw, northEast: ne, size: CGSize(width: w, height: h))
    }

    /// 경도·위도 → 0...1 메르카토르 좌표(y는 북쪽이 작다).
    static func mercator(_ g: GeoPoint) -> (x: Double, y: Double) {
        let lat = min(max(g.latitude, -85.051_128_78), 85.051_128_78) * .pi / 180
        return ((g.longitude + 180) / 360, (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2)
    }

    static func geo(mercatorX x: Double, y: Double) -> GeoPoint {
        let lat = atan(sinh(.pi * (1 - 2 * y))) * 180 / .pi
        return GeoPoint(longitude: x * 360 - 180, latitude: lat)
    }

    /// 위경도 → 화면 좌표(지도 뷰 왼쪽 위 원점).
    func screenPoint(_ g: GeoPoint) -> CGPoint {
        let a = Self.mercator(southWest), b = Self.mercator(northEast), p = Self.mercator(g)
        return CGPoint(x: (p.x - a.x) / (b.x - a.x) * size.width,
                       y: (p.y - b.y) / (a.y - b.y) * size.height)
        // 북동 점의 메르카토르 y가 더 작다(위쪽).
    }

    /// 화면 좌표 → 위경도.
    func coordinate(_ s: CGPoint) -> GeoPoint {
        let a = Self.mercator(southWest), b = Self.mercator(northEast)
        return Self.geo(mercatorX: a.x + Double(s.x / size.width) * (b.x - a.x),
                        y: b.y + Double(s.y / size.height) * (a.y - b.y))
    }

    var center: GeoPoint { coordinate(CGPoint(x: size.width / 2, y: size.height / 2)) }

    /// 장소 검색·화면 폭 계산이 쓰는 MapKit 형식의 범위.
    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: center.clCoordinate,
                           span: MKCoordinateSpan(latitudeDelta: northEast.latitude - southWest.latitude,
                                                  longitudeDelta: northEast.longitude - southWest.longitude))
    }
}

/// SwiftUI 쪽에서 지도 좌표와 화면 좌표를 오갈 때 쓰는 손잡이.
@MainActor
final class MapAlignMapController: ObservableObject {
    enum Status: Equatable { case noClientID, loading, ready, authFailed, loadFailed }

    weak var webView: WKWebView?
    @Published private(set) var status: Status = .loading
    @Published private(set) var viewport: NaverMapViewport?
    /// 지도가 움직이면 올라간다. 손 동작 영역(보이지 않는 층)만 이 값을 따라 다시 계산한다.
    @Published private(set) var tick = 0
    /// 지도가 준비되기 전에 요청한 화면 범위. 준비되면 옮긴다.
    private var pendingRegion: MKCoordinateRegion?

    var region: MKCoordinateRegion? { viewport?.region }

    fileprivate func mapWillLoad(hasClientID: Bool) {
        if pendingRegion == nil, let v = viewport { pendingRegion = v.region }
        // Client ID를 바꿔 다시 불러와도 보던 자리를 잇는다.
        status = hasClientID ? .loading : .noClientID
        viewport = nil
    }

    fileprivate func mapReady() {
        status = .ready
        if let r = pendingRegion { pendingRegion = nil; setRegion(r) }
    }

    fileprivate func mapFailed(_ s: Status) {
        status = s
    }

    fileprivate func viewportChanged(_ v: NaverMapViewport) {
        viewport = v
        tick &+= 1
    }

    fileprivate func run(_ script: String) {
        webView?.evaluateJavaScript(script) { _, error in
            if let error { NSLog("IMDFrnt 네이버 지도 스크립트 오류: \(error)") }
        }
    }

    func setRegion(_ r: MKCoordinateRegion) {
        guard status == .ready else { pendingRegion = r; return }
        let s = r.center.latitude - r.span.latitudeDelta / 2, n = r.center.latitude + r.span.latitudeDelta / 2
        let w = r.center.longitude - r.span.longitudeDelta / 2, e = r.center.longitude + r.span.longitudeDelta / 2
        run("IMDF.fitBounds(\(s),\(w),\(n),\(e))")
    }

    /// 끌기 시작할 때의 화면 범위에서 화면 이동량만큼 지도를 옮긴다. 확대 배율은 그대로다.
    /// 시작 범위로 계산한다 — 지도가 알려 주는 새 범위는 한 박자 늦게 오므로 그것으로 계산하면 끌수록 어긋난다.
    func pan(from start: NaverMapViewport, by translation: CGSize) {
        let c = start.coordinate(CGPoint(x: start.size.width / 2 - translation.width,
                                         y: start.size.height / 2 - translation.height))
        run("IMDF.setCenter(\(c.latitude),\(c.longitude))")
    }

    private var zoomMonitor: Any?
    private var pinchAccumulated: CGFloat = 0

    /// 도면 위의 스크롤을 지도로 넘기고, 핀치는 어디서든 지도 확대로 바꾼다. 도면 위에는 손 동작 겹이 있어 이벤트가
    /// 지도까지 가지 않았고, 도면이 화면을 덮으면 어디서도 확대·축소가 되지 않았다(2026-10-18).
    func startForwardingZoom() {
        guard zoomMonitor == nil else { return }
        zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return event }
            return self.forwardToMap(event) ? nil : event
        }
    }

    private func forwardToMap(_ event: NSEvent) -> Bool {
        guard let web = webView, let window = web.window, event.window === window else { return false }
        let local = web.convert(event.locationInWindow, from: nil)
        guard web.bounds.contains(local) else { return false }
        if event.type == .magnify {
            pinch(event, at: web.isFlipped ? local : CGPoint(x: local.x, y: web.bounds.height - local.y))
            return true
        }
        if let hit = window.contentView?.hitTest(event.locationInWindow),
           hit === web || hit.isDescendant(of: web) { return false }
        // 지도가 직접 받는 자리다. 넘기면 두 번 확대된다.
        web.scrollWheel(with: event)
        return true
    }

    /// 트랙패드 핀치를 지도 확대 단계로 바꾼다. 네이버 웹 지도는 정수 단계로 확대하므로 쌓아 두었다가 한 단계씩 넘긴다.
    private func pinch(_ event: NSEvent, at point: CGPoint) {
        if event.phase == .began { pinchAccumulated = 0 }
        pinchAccumulated += event.magnification
        guard abs(pinchAccumulated) >= 0.25, let v = viewport else { return }
        let step = pinchAccumulated > 0 ? 1 : -1
        pinchAccumulated = 0
        let g = v.coordinate(point)
        run("IMDF.zoomBy(\(step),\(g.latitude),\(g.longitude))")
    }

    func stopForwardingZoom() {
        if let zoomMonitor { NSEvent.removeMonitor(zoomMonitor) }
        zoomMonitor = nil
    }

    /// 위경도 → SwiftUI 좌표(왼쪽 위 원점).
    func screenPoint(_ g: GeoPoint) -> CGPoint? { viewport?.screenPoint(g) }

    /// SwiftUI 좌표 → 위경도.
    func coordinate(_ p: CGPoint) -> GeoPoint? { viewport?.coordinate(p) }
}

/// 지도에 얹는 한 겹. 도면 선(`.drawing`) 또는 편집 중인 층의 테두리·손잡이·Anchor(`.decoration`).
/// 정렬이 바뀌면 새로 만들고, `signature`가 같으면 투명도 말고는 다시 보내지 않는다.
struct AlignOverlay {
    enum Kind: String, Equatable { case drawing, decoration }

    struct AnchorMark: Equatable {
        let point: LocalPoint
        let isFeature: Bool
        let isSelected: Bool
        /// 거짓이면 anchor 레이어에만 있고 아직 Anchor 쌍이 아닌 점이다. 속 빈 보라색 고리로 그린다.
        let isPaired: Bool
    }

    struct Signature: Equatable {
        let levelID: UUID
        let kind: Kind
        let alignment: MapAlignment
        let pathKey: String
        let isStandardMap: Bool
        let showHandles: Bool
        let anchors: [AnchorMark]
        let snapKey: Int
    }

    let signature: Signature
    let path: Path
    let canvasSize: CGSize
    let snaps: SnapPointGrid?
    var opacity: Double

    var id: String { "\(signature.levelID.uuidString)-\(signature.kind.rawValue)" }
}

/// 손잡이 자리. 그리기(JS)와 손 동작(SwiftUI)이 같은 계산을 쓴다 — JS 쪽 `rotateHandle`도 이 식이다.
enum AlignHandles {
    /// 회전 손잡이: 도면 위쪽 변의 가운데에서 바깥쪽으로 `outward`만큼.
    static func rotate(corners: [CGPoint], outward: CGFloat) -> (base: CGPoint, knob: CGPoint) {
        let top = CGPoint(x: (corners[0].x + corners[1].x) / 2, y: (corners[0].y + corners[1].y) / 2)
        let mid = CGPoint(x: (corners[0].x + corners[2].x) / 2, y: (corners[0].y + corners[2].y) / 2)
        let dx = top.x - mid.x, dy = top.y - mid.y
        let len = max(1e-12, hypot(dx, dy))
        return (top, CGPoint(x: top.x + dx / len * outward, y: top.y + dy / len * outward))
    }
}
