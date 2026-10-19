import Foundation
import SwiftUI

/// 지도 정렬 화면에 띄우는 네이버 지도 웹 페이지(신기능 11항, #31).
///
/// **인증:** 네이버 클라우드 콘솔의 Application에서 Dynamic Map을 켜고, Web 서비스 URL에 `http://localhost`를 등록해야 한다.
/// 페이지를 `baseURL`(`http://localhost/`)로 띄우므로 지도 스크립트 요청의 출처가 이 주소가 된다. 서비스 URL에는 포트·경로를
/// 넣지 않는다(넣으면 인증 오류, 네이버 클라우드 Maps 문제 해결 문서).
enum NaverMapPage {
    static let messageName = "imdfrnt"
    static let baseURL = URL(string: "http://localhost/")!
    /// 콘솔에 등록할 Web 서비스 URL. 안내 문구가 쓴다.
    static let serviceURL = "http://localhost"

    static let blankHTML = "<!doctype html><html><body style=\"margin:0;background:#e5e5e5\"></body></html>"

    static func html(clientID: String, mapKind: NaverMapKind) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        let key = clientID.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return pageTemplate
            .replacingOccurrences(of: "__CLIENT_ID__", with: key)
            .replacingOccurrences(of: "__MAP_TYPE__", with: mapKind.naverID)
    }

    /// SwiftUI 경로 → SVG `d`. 소수 셋째 자리까지만 쓴다 — 도면 1단위가 1cm 남짓이라 0.001단위는 화면에서 구분되지 않고,
    /// 자릿수를 줄이면 넘기는 문자열이 절반 가까이 준다.
    static func svgPathData(_ path: Path) -> String {
        var s = ""
        func n(_ v: CGFloat) -> String {
            let r = (Double(v) * 1000).rounded() / 1000
            guard r.isFinite else { return "0" }
            if r == r.rounded(), abs(r) < 1e15 { return String(Int(r)) }
            return String(r)
        }
        func pt(_ p: CGPoint) -> String { n(p.x) + " " + n(p.y) }
        path.forEach { e in
            switch e {
            case .move(let p): s += "M" + pt(p)
            case .line(let p): s += "L" + pt(p)
            case .quadCurve(let p, let c): s += "Q" + pt(c) + " " + pt(p)
            case .curve(let p, let c1, let c2): s += "C" + pt(c1) + " " + pt(c2) + " " + pt(p)
            case .closeSubpath: s += "Z"
            }
        }
        return s
    }

    /// 지도와 겹을 다루는 JS. Swift는 `IMDF.*` 함수만 부르고, JS는 `imdfrnt` 메시지로 상태를 알린다.
    ///
    /// 겹 하나가 `OverlayView` 하나이고 SVG 하나를 지도 판(overlayLayer)에 붙인다. 판은 지도를 끄는 동안 타일과 함께
    /// 움직이므로 다시 그리지 않아도 흔들리지 않는다. 도면 선은 도면 좌표 그대로 두고 `matrix(...)`만 바꾼다(선 굵기는
    /// `non-scaling-stroke`로 확대와 무관). 테두리·손잡이·Anchor·꼭짓점은 화면 크기가 일정해야 해서 판 좌표로 다시 그린다.
    private static let pageTemplate = #"""
    <!doctype html>
    <html><head><meta charset="utf-8">
    <style>html,body,#map{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#e5e5e5}</style>
    <script>
    const NS = 'http://www.w3.org/2000/svg';
    const IMDF = { map: null, layers: {}, Layer: null, decorPending: false };
    function post(m) { try { window.webkit.messageHandlers.imdfrnt.postMessage(m); } catch (e) {} }
    window.navermap_authFailure = function () { post({ type: 'authFailure' }); };

    IMDF.postBounds = function () {
      const map = IMDF.map; if (!map) return;
      const b = map.getBounds(), sw = b.getSW(), ne = b.getNE(), s = map.getSize();
      post({ type: 'bounds', sw: [sw.lng(), sw.lat()], ne: [ne.lng(), ne.lat()], w: s.width, h: s.height });
    };
    IMDF.redraw = function (onlyDecor) {
      for (const id in IMDF.layers) {
        const l = IMDF.layers[id];
        if (!onlyDecor || l.spec.kind === 'decoration') l.draw();
      }
    };
    IMDF.scheduleDecor = function () {
      if (IMDF.decorPending) return;
      IMDF.decorPending = true;
      requestAnimationFrame(function () { IMDF.decorPending = false; IMDF.redraw(true); });
      // 끄는 동안 새로 드러난 자리의 꼭짓점을 채운다. 프레임마다 한 번만.
    };
    IMDF.putLayer = function (spec) {
      if (!IMDF.map) return;
      let l = IMDF.layers[spec.id];
      if (!l) { l = new IMDF.Layer(); IMDF.layers[spec.id] = l; l.setMap(IMDF.map); l.update(spec); }
      else l.update(spec);
    };
    IMDF.setOpacity = function (id, v) {
      const l = IMDF.layers[id]; if (!l) return;
      l.spec.opacity = v; l.svg.style.opacity = v;
    };
    IMDF.setOrder = function (ids) {
      for (const id in IMDF.layers) {
        if (ids.indexOf(id) < 0) { IMDF.layers[id].setMap(null); delete IMDF.layers[id]; }
      }
      for (const id of ids) {
        const l = IMDF.layers[id];
        if (l && l.svg.parentNode) l.svg.parentNode.appendChild(l.svg);
      }
    };
    IMDF.fitBounds = function (s, w, n, e) {
      if (!IMDF.map) return;
      IMDF.map.fitBounds(new naver.maps.LatLngBounds(new naver.maps.LatLng(s, w), new naver.maps.LatLng(n, e)));
    };
    IMDF.setCenter = function (lat, lng) {
      if (IMDF.map) IMDF.map.setCenter(new naver.maps.LatLng(lat, lng));
    };
    IMDF.zoomBy = function (step, lat, lng) {
      const map = IMDF.map; if (!map) return;
      if (typeof map.zoomBy === 'function') map.zoomBy(step, new naver.maps.LatLng(lat, lng), true);
      else map.setZoom(map.getZoom() + step, true);
    };
    IMDF.setMapType = function (t) {
      if (IMDF.map) IMDF.map.setMapTypeId(naver.maps.MapTypeId[t]);
    };

    function el(name, attrs) {
      const e = document.createElementNS(NS, name);
      for (const k in attrs) e.setAttribute(k, attrs[k]);
      return e;
    }

    function IMDF_init() {
      const map = new naver.maps.Map('map', {
        center: new naver.maps.LatLng(36.5, 127.8), zoom: 7,
        mapTypeId: naver.maps.MapTypeId['__MAP_TYPE__'],
        zoomControl: true, zoomControlOptions: { position: naver.maps.Position.TOP_RIGHT },
        scaleControl: true, mapDataControl: false, mapTypeControl: false
      });
      IMDF.map = map;

      function Layer() {
        naver.maps.OverlayView.call(this);
        this.spec = {}; this.d = ''; this.snaps = [];
        this.svg = el('svg', { width: 1, height: 1 });
        this.svg.style.cssText = 'position:absolute;left:0;top:0;overflow:visible;pointer-events:none';
        this.g = el('g', {});
        this.svg.appendChild(this.g);
      }
      Layer.prototype = new naver.maps.OverlayView();
      Layer.prototype.constructor = Layer;
      Layer.prototype.onAdd = function () { this.getPanes().overlayLayer.appendChild(this.svg); };
      Layer.prototype.onRemove = function () { if (this.svg.parentNode) this.svg.parentNode.removeChild(this.svg); };
      Layer.prototype.update = function (spec) {
        if (spec.d !== undefined) { this.d = spec.d; delete spec.d; }
        if (spec.snaps !== undefined) { this.snaps = spec.snaps; delete spec.snaps; }
        this.spec = spec;
        this.svg.style.opacity = spec.opacity;
        if (spec.kind === 'drawing') {
          if (!this.path) {
            this.path = el('path', { fill: 'none', 'stroke-width': 0.8, 'vector-effect': 'non-scaling-stroke' });
            this.g.appendChild(this.path);
          }
          this.path.setAttribute('d', this.d);
          this.path.setAttribute('stroke', spec.stroke);
        }
        if (this.proj()) this.draw();
      };
      // 지도에 붙기 전에는 투영이 없다. 붙으면 지도가 draw를 부른다.
      Layer.prototype.proj = function () {
        try { return this.getProjection() || null; } catch (e) { return null; }
      };
      // 도면 좌표 → 지도 판 좌표 어파인 행렬.
      Layer.prototype.transform = function () {
        const proj = this.proj(), f = this.spec.frame;
        if (!proj || !f) return null;
        // 지도는 붙이자마자 draw를 부를 수 있다. 그때는 아직 겹 값이 없다.
        const off = function (g) { return proj.fromCoordToOffset(new naver.maps.LatLng(g[1], g[0])); };
        const o = off(f.o), px = off(f.x), py = off(f.y), k = f.k, cx = f.c[0], cy = f.c[1];
        const a = (px.x - o.x) / k, b = (px.y - o.y) / k, c = (py.x - o.x) / k, d = (py.y - o.y) / k;
        return { a: a, b: b, c: c, d: d, e: o.x - a * cx - c * cy, f: o.y - b * cx - d * cy };
      };
      Layer.prototype.draw = function () {
        const t = this.transform(); if (!t) return;
        if (this.spec.kind === 'drawing') {
          this.g.setAttribute('transform', 'matrix(' + [t.a, t.b, t.c, t.d, t.e, t.f].join(' ') + ')');
          return;
        }
        this.drawDecoration(t);
      };
      Layer.prototype.drawDecoration = function (t) {
        const s = this.spec, g = this.g;
        while (g.firstChild) g.removeChild(g.firstChild);
        const ap = function (x, y) { return [t.a * x + t.c * y + t.e, t.b * x + t.d * y + t.f]; };
        const corners = [ap(0, 0), ap(s.w, 0), ap(s.w, s.h), ap(0, s.h)];
        const poly = corners.map(function (p) { return p.join(','); }).join(' ');
        g.appendChild(el('polygon', { points: poly, fill: 'none', stroke: '#007AFF', 'stroke-width': 2 }));

        if (s.handles) {
          for (const p of corners) {
            g.appendChild(el('rect', { x: p[0] - 5, y: p[1] - 5, width: 10, height: 10,
                                       fill: '#ffffff', stroke: '#007AFF', 'stroke-width': 2 }));
          }
          // 회전 손잡이: Swift `AlignHandles.rotate`와 같은 식(위쪽 변 가운데에서 바깥으로 28pt).
          const top = [(corners[0][0] + corners[1][0]) / 2, (corners[0][1] + corners[1][1]) / 2];
          const mid = [(corners[0][0] + corners[2][0]) / 2, (corners[0][1] + corners[2][1]) / 2];
          const dx = top[0] - mid[0], dy = top[1] - mid[1], len = Math.max(1e-12, Math.hypot(dx, dy));
          const knob = [top[0] + dx / len * 28, top[1] + dy / len * 28];
          g.appendChild(el('line', { x1: top[0], y1: top[1], x2: knob[0], y2: knob[1], stroke: '#007AFF', 'stroke-width': 2 }));
          g.appendChild(el('circle', { cx: knob[0], cy: knob[1], r: 7, fill: '#ffffff', stroke: '#007AFF', 'stroke-width': 2 }));
        }

        const pts = this.snaps;
        if (pts.length) {
          const b = IMDF.map.getBounds(), proj = this.proj();
          const sw = proj.fromCoordToOffset(b.getSW()), ne = proj.fromCoordToOffset(b.getNE());
          const minX = Math.min(sw.x, ne.x), maxX = Math.max(sw.x, ne.x);
          const minY = Math.min(sw.y, ne.y), maxY = Math.max(sw.y, ne.y);
          let d = '', n = 0;
          for (let i = 0; i < pts.length && n <= 6000; i += 2) {
            const p = ap(pts[i], pts[i + 1]);
            if (p[0] < minX || p[0] > maxX || p[1] < minY || p[1] > maxY) continue;
            d += 'M' + (p[0] - 2.5) + ' ' + p[1] + 'a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0 -5 0';
            n++;
          }
          // 화면에 너무 많으면 그리지 않는다. 확대하면 나타난다.
          if (n > 0 && n <= 6000) g.appendChild(el('path', { d: d, fill: 'none', stroke: '#FFCC00', 'stroke-width': 1 }));
        }

        for (const m of s.anchors) {
          if (m.p) continue;
          const p = ap(m.x, m.y);
          g.appendChild(el('circle', { cx: p[0], cy: p[1], r: 6, fill: 'none', stroke: '#ffffff', 'stroke-width': 4 }));
          g.appendChild(el('circle', { cx: p[0], cy: p[1], r: 6, fill: 'none', stroke: '#AF52DE', 'stroke-width': 2 }));
          // 흰 테두리를 먼저 그려 위성사진 위에서도 보라색 고리가 묻히지 않게 한다.
        }
        for (const m of s.anchors) {
          if (!m.p) continue;
          const p = ap(m.x, m.y);
          g.appendChild(el('circle', { cx: p[0], cy: p[1], r: 7, fill: m.f ? '#AF52DE' : '#FF9500',
                                       stroke: m.s ? '#007AFF' : '#ffffff', 'stroke-width': m.s ? 3 : 1.5 }));
        }
      };
      IMDF.Layer = Layer;

      const ev = naver.maps.Event;
      ev.addListener(map, 'bounds_changed', function () { IMDF.postBounds(); IMDF.scheduleDecor(); });
      ev.addListener(map, 'size_changed', function () { IMDF.postBounds(); });
      ev.addListener(map, 'idle', function () { IMDF.postBounds(); IMDF.redraw(false); });
      post({ type: 'ready' });
      IMDF.postBounds();
    }
    </script>
    <script src="https://oapi.map.naver.com/openapi/v3/maps.js?ncpKeyId=__CLIENT_ID__&callback=IMDF_init"
            onerror="post({ type: 'loadError' })"></script>
    </head><body><div id="map"></div></body></html>
    """#
}
