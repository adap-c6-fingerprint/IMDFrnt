import AppKit
import CoreLocation
import MapKit
import SwiftUI

/// 지도 정렬 화면의 지도(신기능 11항, #31).
///
/// **도면을 지도의 오버레이로 그린다.** 처음에는 SwiftUI `Map` 위에 Canvas를 얹고 지도가 움직일 때마다
/// 다시 그렸는데, 카메라 변경 알림이 지도 그리기보다 한 박자 늦게 와서 지도를 끌면 도면이 움찔거렸다
/// (2026-10-15 사용자 확인). MKMapView 오버레이는 지도 타일과 같은 순간에 그려지므로 흔들리지 않는다.
///
/// **확대 한계를 1m까지 푼다.** 매우 정밀한 정렬이 필요하다는 요청이다. 위성 사진 해상도보다 더 들어가면
/// 사진은 흐려지지만 도면 선은 그대로 선명해서, 선끼리·선과 지붕 모서리를 맞추는 데는 쓸 수 있다.
struct AlignMapView: NSViewRepresentable {
    let controller: MapAlignMapController
    let mapType: MKMapType
    let layers: [AlignOverlay]

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsZoomControls = true
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 1)
        map.mapType = mapType
        controller.mapView = map
        controller.startForwardingZoom()
        return map
    }

    static func dismantleNSView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.controller.stopForwardingZoom()
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        if map.mapType != mapType { map.mapType = mapType }
        context.coordinator.sync(map, layers: layers)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        let controller: MapAlignMapController
        private var shown: [AlignOverlay] = []

        init(controller: MapAlignMapController) { self.controller = controller }

        /// 바뀐 것이 있을 때만 오버레이를 갈아 끼운다. 투명도만 바뀌면 다시 그리지 않고 렌더러 투명도만 바꾼다 —
        /// 슬라이더를 끄는 동안 도면 전체를 다시 그리면 버벅인다.
        func sync(_ map: MKMapView, layers: [AlignOverlay]) {
            let sameShape = shown.count == layers.count
                && zip(shown, layers).allSatisfy { $0.signature == $1.signature }
            if sameShape {
                for (old, new) in zip(shown, layers) where old.opacity != new.opacity {
                    (map.renderer(for: old) as? AlignOverlayRenderer)?.alpha = new.opacity
                    old.opacity = new.opacity
                }
                return
            }
            map.removeOverlays(shown)
            map.addOverlays(layers, level: .aboveLabels)
            shown = layers
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let o = overlay as? AlignOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let r = AlignOverlayRenderer(overlay: o)
            r.alpha = o.opacity
            return r
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            controller.regionChanged(mapView.region)
        }
    }
}

/// SwiftUI 쪽에서 지도 좌표와 화면 좌표를 오갈 때 쓰는 손잡이.
@MainActor
final class MapAlignMapController: ObservableObject {
    weak var mapView: MKMapView?
    @Published private(set) var region: MKCoordinateRegion?
    /// 지도가 움직이면 올라간다. 손 동작 영역(보이지 않는 층)만 이 값을 따라 다시 계산한다.
    @Published private(set) var tick = 0

    fileprivate func regionChanged(_ r: MKCoordinateRegion) {
        region = r
        tick &+= 1
    }

    func setRegion(_ r: MKCoordinateRegion) {
        mapView?.setRegion(r, animated: false)
    }

    /// 끌기 시작할 때의 지도 중심에서 화면 이동량만큼 지도를 옮긴다. 확대 배율은 그대로다.
    func pan(from startCenter: CLLocationCoordinate2D, by translation: CGSize) {
        guard let map = mapView, let start = screenPoint(GeoPoint(longitude: startCenter.longitude,
                                                                   latitude: startCenter.latitude)),
              let next = coordinate(CGPoint(x: start.x - translation.width, y: start.y - translation.height))
        else { return }
        map.setCenter(next.clCoordinate, animated: false)
    }

    private var zoomMonitor: Any?

    /// 도면 위의 스크롤·핀치를 지도로 넘긴다. 도면 위에는 손 동작 겹이 있어 이벤트가 지도까지 가지 않았고,
    /// 도면이 화면을 덮으면 어디서도 확대·축소가 되지 않았다(2026-10-18). 지도가 직접 받는 자리는 건드리지 않는다.
    func startForwardingZoom() {
        guard zoomMonitor == nil else { return }
        zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return event }
            return self.forwardToMap(event) ? nil : event
        }
    }

    private func forwardToMap(_ event: NSEvent) -> Bool {
        guard let map = mapView, let window = map.window, event.window === window else { return false }
        guard map.bounds.contains(map.convert(event.locationInWindow, from: nil)) else { return false }
        if let hit = window.contentView?.hitTest(event.locationInWindow),
           hit === map || hit.isDescendant(of: map) { return false }
        // 지도가 직접 받는 자리다. 넘기면 두 번 확대된다.
        if event.type == .magnify { map.magnify(with: event) } else { map.scrollWheel(with: event) }
        return true
    }

    func stopForwardingZoom() {
        if let zoomMonitor { NSEvent.removeMonitor(zoomMonitor) }
        zoomMonitor = nil
    }

    /// 위경도 → SwiftUI 좌표(왼쪽 위 원점).
    func screenPoint(_ g: GeoPoint) -> CGPoint? {
        guard let map = mapView else { return nil }
        let p = map.convert(g.clCoordinate, toPointTo: map)
        return map.isFlipped ? p : CGPoint(x: p.x, y: map.bounds.height - p.y)
    }

    /// SwiftUI 좌표 → 위경도.
    func coordinate(_ p: CGPoint) -> GeoPoint? {
        guard let map = mapView else { return nil }
        let q = map.isFlipped ? p : CGPoint(x: p.x, y: map.bounds.height - p.y)
        let c = map.convert(q, toCoordinateFrom: map)
        guard CLLocationCoordinate2DIsValid(c) else { return nil }
        return GeoPoint(longitude: c.longitude, latitude: c.latitude)
    }
}

/// 지도에 얹는 한 겹. 도면 선(`.drawing`) 또는 편집 중인 층의 테두리·손잡이·Anchor(`.decoration`).
///
/// **값은 만들 때 정해지고 바뀌지 않는다(투명도 제외).** 렌더러가 백그라운드 스레드에서 읽기 때문이다.
/// 정렬이 바뀌면 새로 만들어 갈아 끼운다.
final class AlignOverlay: NSObject, MKOverlay, @unchecked Sendable {
    enum Kind: Equatable { case drawing, decoration }

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
    let path: CGPath
    let canvasSize: CGSize
    let snaps: SnapPointGrid?
    var opacity: Double
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(signature: Signature, path: CGPath, canvasSize: CGSize, snaps: SnapPointGrid?, opacity: Double) {
        self.signature = signature
        self.path = path
        self.canvasSize = canvasSize
        self.snaps = snaps
        self.opacity = opacity
        let a = signature.alignment
        coordinate = a.center.clCoordinate
        let corners = [LocalPoint(0, 0), LocalPoint(Double(canvasSize.width), 0),
                       LocalPoint(Double(canvasSize.width), Double(canvasSize.height)),
                       LocalPoint(0, Double(canvasSize.height))]
            .map { MKMapPoint(a.geoPoint(for: $0).clCoordinate) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        let w = (xs.max() ?? 0) - minX, h = (ys.max() ?? 0) - minY
        let pad = max(w, h) * 0.2 + 50
        // 손잡이·Anchor 표시가 도면 테두리 밖으로 조금 나가므로 여유를 둔다.
        boundingMapRect = MKMapRect(x: minX - pad, y: minY - pad, width: w + pad * 2, height: h + pad * 2)
    }
}

/// 오버레이 렌더러. MapKit이 타일마다 백그라운드에서 부른다 — 오버레이의 바뀌지 않는 값만 읽는다.
final class AlignOverlayRenderer: MKOverlayRenderer, @unchecked Sendable {

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        guard let o = overlay as? AlignOverlay else { return }
        let a = o.signature.alignment
        let c = a.canvasCenter
        let k = 100.0
        let p0 = point(for: MKMapPoint(a.geoPoint(for: c).clCoordinate))
        let px = point(for: MKMapPoint(a.geoPoint(for: LocalPoint(c.x + k, c.y)).clCoordinate))
        let py = point(for: MKMapPoint(a.geoPoint(for: LocalPoint(c.x, c.y + k)).clCoordinate))
        let ax = (px.x - p0.x) / k, bx = (px.y - p0.y) / k
        let cy = (py.x - p0.x) / k, dy = (py.y - p0.y) / k
        let t = CGAffineTransform(a: ax, b: bx, c: cy, d: dy,
                                  tx: p0.x - ax * c.x - cy * c.y, ty: p0.y - bx * c.x - dy * c.y)
        // 도면 좌표 → 이 렌더러 좌표. 건물 하나 범위에서는 지도 투영이 사실상 평면이라 세 점으로 충분하다.
        let screenPoint = 1 / zoomScale
        // 렌더러 좌표에서 화면 1pt의 길이. 선 굵기·표시 크기를 확대와 무관하게 일정하게 만든다.

        switch o.signature.kind {
        case .drawing:
            ctx.saveGState()
            ctx.concatenate(t)
            ctx.addPath(o.path)
            let localScale = sqrt(abs(t.a * t.d - t.b * t.c))
            ctx.setLineWidth(0.8 * screenPoint / max(localScale, 1e-12))
            ctx.setStrokeColor(o.signature.isStandardMap ? NSColor.black.cgColor : NSColor.white.cgColor)
            ctx.strokePath()
            ctx.restoreGState()

        case .decoration:
            let corners = [CGPoint(x: 0, y: 0), CGPoint(x: o.canvasSize.width, y: 0),
                           CGPoint(x: o.canvasSize.width, y: o.canvasSize.height),
                           CGPoint(x: 0, y: o.canvasSize.height)].map { $0.applying(t) }
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(2 * screenPoint)
            ctx.addLines(between: corners); ctx.closePath(); ctx.strokePath()

            if o.signature.showHandles {
                let s = 5 * screenPoint
                for p in corners {
                    let r = CGRect(x: p.x - s, y: p.y - s, width: s * 2, height: s * 2)
                    ctx.setFillColor(NSColor.white.cgColor); ctx.fill(r)
                    ctx.stroke(r)
                }
                let h = AlignHandles.rotate(corners: corners, outward: 28 * screenPoint)
                ctx.move(to: h.base); ctx.addLine(to: h.knob); ctx.strokePath()
                let knob = CGRect(x: h.knob.x - 7 * screenPoint, y: h.knob.y - 7 * screenPoint,
                                  width: 14 * screenPoint, height: 14 * screenPoint)
                ctx.setFillColor(NSColor.white.cgColor); ctx.fillEllipse(in: knob); ctx.strokeEllipse(in: knob)
            }

            if let snaps = o.snaps {
                let localRect = rect(for: mapRect).applying(t.inverted())
                let indices = snaps.indices(in: localRect)
                if indices.count <= 6000 {
                    // 타일 하나에 너무 많으면 그리지 않는다. 확대하면 나타난다.
                    ctx.setStrokeColor(NSColor.systemYellow.cgColor)
                    ctx.setLineWidth(1 * screenPoint)
                    let r = 2.5 * screenPoint
                    for i in indices {
                        let p = snaps.points[i].point.cg.applying(t)
                        ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    }
                }
            }

            for m in o.signature.anchors where !m.isPaired {
                let p = m.point.cg.applying(t)
                let ring = CGRect(x: p.x - 6 * screenPoint, y: p.y - 6 * screenPoint,
                                  width: 12 * screenPoint, height: 12 * screenPoint)
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(4 * screenPoint)
                ctx.strokeEllipse(in: ring)
                ctx.setStrokeColor(NSColor.systemPurple.cgColor)
                ctx.setLineWidth(2 * screenPoint)
                ctx.strokeEllipse(in: ring)
                // 흰 테두리를 먼저 그려 위성사진 위에서도 보라색 고리가 묻히지 않게 한다.
            }

            for m in o.signature.anchors where m.isPaired {
                let p = m.point.cg.applying(t)
                let r = 7 * screenPoint
                let dot = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                ctx.setFillColor((m.isFeature ? NSColor.systemPurple : NSColor.systemOrange).cgColor)
                ctx.fillEllipse(in: dot)
                ctx.setStrokeColor((m.isSelected ? NSColor.systemBlue : NSColor.white).cgColor)
                ctx.setLineWidth((m.isSelected ? 3 : 1.5) * screenPoint)
                ctx.strokeEllipse(in: dot)
            }
        }
    }
}

/// 손잡이 자리. 그리기(렌더러)와 손 동작(SwiftUI)이 같은 계산을 쓴다.
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
