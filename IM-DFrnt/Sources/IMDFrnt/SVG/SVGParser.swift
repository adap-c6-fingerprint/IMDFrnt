import CoreGraphics
import Foundation

/// XMLParser로 SVG를 순회하며 그리기 요소를 개별 `VectorObject`로 평탄화한다.
/// `<g>`는 좌표계 누적과 스타일 상속에만 쓰고 개체로 만들지 않는다 —
/// 명세의 "그룹화"는 사용자가 직접 하는 것이지 SVG의 `<g>`가 아니기 때문이다.
final class SVGParser: NSObject, XMLParserDelegate {

    struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    private var objects: [VectorObject] = []
    private var rasterImages: [DrawingRasterImage] = []
    private var transformStack: [CGAffineTransform] = [.identity]
    private var styleStack: [StyleResolver.Inherited] = [StyleResolver.Inherited()]
    private var canvasSize = CGSize(width: 1000, height: 800)
    private var ordinal = 0
    private var failure: Failure?

    private static let drawableElements: Set<String> = [
        "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
    ]

    static func parse(data: Data, sourceName: String) throws -> DrawingDocument {
        let p = SVGParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        guard xml.parse() else {
            throw p.failure ?? Failure(message: "SVG XML을 읽지 못했습니다: \(xml.parserError?.localizedDescription ?? "알 수 없는 오류")")
        }
        if let f = p.failure { throw f }
        guard !p.objects.isEmpty || !p.rasterImages.isEmpty else {
            throw Failure(message: "그릴 수 있는 벡터 개체를 찾지 못했습니다.")
        }
        return DrawingDocument(objects: p.objects, canvasSize: p.canvasSize, sourceName: sourceName, rasterImages: p.rasterImages)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()

        if name == "svg" { readCanvasSize(attributeDict) }

        let parentTransform = transformStack.last ?? .identity
        let local = parseTransform(attributeDict["transform"])
        let combined = local.concatenating(parentTransform)
        transformStack.append(combined)

        let mergedStyle = StyleResolver.merge(styleStack.last ?? .init(), attributes: attributeDict)
        styleStack.append(mergedStyle)

        if name == "image" {
            do {
                guard let href = attributeDict["href"] ?? attributeDict["xlink:href"] else {
                    throw Failure(message: "SVG 이미지에 원본 경로가 없습니다.")
                }
                let (image, digest) = try DrawingImageImporter.embeddedImage(href)
                func number(_ key: String, fallback: Double = 0) -> Double {
                    Double(attributeDict[key]?.replacingOccurrences(of: "px", with: "") ?? "") ?? fallback
                }
                let rect = CGRect(x: number("x"), y: number("y"),
                                  width: number("width", fallback: Double(image.width)),
                                  height: number("height", fallback: Double(image.height)))
                guard rect.width > 0, rect.height > 0 else { throw Failure(message: "SVG 이미지 크기가 올바르지 않습니다.") }
                rasterImages.append(DrawingRasterImage(image: image, rect: rect, transform: combined, digest: digest))
            } catch {
                failure = Failure(message: String(describing: error))
                parser.abortParsing()
            }
            return
        }

        guard Self.drawableElements.contains(name) else { return }

        do {
            guard let raw = try geometry(for: name, attributes: attributeDict), !raw.isEmpty else { return }
            let baked = bake(raw, with: combined)
            let style = StyleResolver.resolve(mergedStyle)
            ordinal += 1
            // id는 도면 내용에서 결정적으로 뽑는다. 매번 새 `UUID()`를 발급하면 같은 SVG를
            // 두 사람이 각자 열었을 때 개체 id가 갈려 작업을 도로 붙일 수 없다(신기능 1-2-6).
            let id = StableObjectID.make(ordinal: ordinal, element: name,
                                         styleKey: style.attributeKey, geometry: baked)
            objects.append(VectorObject(id: id, geometry: baked, style: style,
                                        sourceElement: name, ordinal: ordinal))
        } catch let e as PathDataParser.ParseError {
            failure = Failure(message: "path 파싱 실패: \(e.message)")
            parser.abortParsing()
        } catch {
            failure = Failure(message: "\(name) 요소 파싱 실패: \(error)")
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if transformStack.count > 1 { transformStack.removeLast() }
        if styleStack.count > 1 { styleStack.removeLast() }
    }

    // MARK: - 요소별 형상

    private func geometry(for name: String, attributes a: [String: String]) throws -> PathGeometry? {
        func num(_ k: String, _ fallback: Double = 0) -> Double {
            Double(a[k]?.replacingOccurrences(of: "px", with: "") ?? "") ?? fallback
        }

        switch name {
        case "path":
            guard let d = a["d"], !d.isEmpty else { return nil }
            return PathGeometry(subpaths: try PathDataParser.parse(d))

        case "rect":
            let x = num("x"), y = num("y"), w = num("width"), h = num("height")
            guard w > 0, h > 0 else { return nil }
            let pts = [LocalPoint(x, y), LocalPoint(x + w, y), LocalPoint(x + w, y + h), LocalPoint(x, y + h)]
            return PathGeometry(subpaths: [Subpath(start: pts[0],
                                                   segments: pts.dropFirst().map { .line(to: $0) },
                                                   isClosed: true)])

        case "circle":
            let cx = num("cx"), cy = num("cy"), r = num("r")
            guard r > 0 else { return nil }
            return ellipse(cx: cx, cy: cy, rx: r, ry: r)

        case "ellipse":
            let cx = num("cx"), cy = num("cy"), rx = num("rx"), ry = num("ry")
            guard rx > 0, ry > 0 else { return nil }
            return ellipse(cx: cx, cy: cy, rx: rx, ry: ry)

        case "line":
            let p0 = LocalPoint(num("x1"), num("y1"))
            let p1 = LocalPoint(num("x2"), num("y2"))
            if p0 == p1 { return nil }
            return PathGeometry(subpaths: [Subpath(start: p0, segments: [.line(to: p1)], isClosed: false)])

        case "polyline", "polygon":
            let pts = parsePoints(a["points"] ?? "")
            guard pts.count >= 2 else { return nil }
            return PathGeometry(subpaths: [Subpath(start: pts[0],
                                                   segments: pts.dropFirst().map { .line(to: $0) },
                                                   isClosed: name == "polygon")])
        default:
            return nil
        }
    }

    /// 원·타원은 4개의 3차 베지어로 근사한다(케이스 상수 0.5522847498).
    private func ellipse(cx: Double, cy: Double, rx: Double, ry: Double) -> PathGeometry {
        let k = 0.5522847498307936
        let ox = rx * k, oy = ry * k
        let start = LocalPoint(cx + rx, cy)
        let segs: [PathSegment] = [
            .cubic(c1: LocalPoint(cx + rx, cy + oy), c2: LocalPoint(cx + ox, cy + ry), to: LocalPoint(cx, cy + ry)),
            .cubic(c1: LocalPoint(cx - ox, cy + ry), c2: LocalPoint(cx - rx, cy + oy), to: LocalPoint(cx - rx, cy)),
            .cubic(c1: LocalPoint(cx - rx, cy - oy), c2: LocalPoint(cx - ox, cy - ry), to: LocalPoint(cx, cy - ry)),
            .cubic(c1: LocalPoint(cx + ox, cy - ry), c2: LocalPoint(cx + rx, cy - oy), to: start),
        ]
        return PathGeometry(subpaths: [Subpath(start: start, segments: segs, isClosed: true)])
    }

    private func parsePoints(_ s: String) -> [LocalPoint] {
        let nums = s.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
            .compactMap { Double($0) }
        var out: [LocalPoint] = []
        var i = 0
        while i + 1 < nums.count { out.append(LocalPoint(nums[i], nums[i + 1])); i += 2 }
        return out
    }

    // MARK: - transform

    private func readCanvasSize(_ a: [String: String]) {
        if let vb = a["viewBox"] {
            let n = vb.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            if n.count == 4, n[2] > 0, n[3] > 0 {
                canvasSize = CGSize(width: n[2], height: n[3])
                return
            }
        }
        let w = Double(a["width"]?.replacingOccurrences(of: "px", with: "") ?? "") ?? 0
        let h = Double(a["height"]?.replacingOccurrences(of: "px", with: "") ?? "") ?? 0
        if w > 0, h > 0 { canvasSize = CGSize(width: w, height: h) }
    }

    private func parseTransform(_ raw: String?) -> CGAffineTransform {
        guard let raw, !raw.isEmpty else { return .identity }
        var result = CGAffineTransform.identity
        var scanner = raw[...]
        while let open = scanner.firstIndex(of: "("), let close = scanner.firstIndex(of: ")") {
            let name = scanner[scanner.startIndex..<open]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
            let args = scanner[scanner.index(after: open)..<close]
                .split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            var t = CGAffineTransform.identity
            switch name {
            case "translate": t = CGAffineTransform(translationX: args.first ?? 0, y: args.count > 1 ? args[1] : 0)
            case "scale": t = CGAffineTransform(scaleX: args.first ?? 1, y: args.count > 1 ? args[1] : (args.first ?? 1))
            case "rotate":
                let a = (args.first ?? 0) * .pi / 180
                if args.count >= 3 {
                    t = CGAffineTransform(translationX: args[1], y: args[2])
                        .rotated(by: a)
                        .translatedBy(x: -args[1], y: -args[2])
                } else {
                    t = CGAffineTransform(rotationAngle: a)
                }
            case "matrix":
                if args.count >= 6 {
                    t = CGAffineTransform(a: args[0], b: args[1], c: args[2], d: args[3], tx: args[4], ty: args[5])
                }
            case "skewx": t = CGAffineTransform(a: 1, b: 0, c: tan((args.first ?? 0) * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewy": t = CGAffineTransform(a: 1, b: tan((args.first ?? 0) * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default: break
            }
            result = t.concatenating(result)
            scanner = scanner[scanner.index(after: close)...]
        }
        return result
    }

    /// 파싱 시점에 좌표를 최종 좌표계로 굽는다(런타임 변환 비용 제거).
    private func bake(_ g: PathGeometry, with t: CGAffineTransform) -> PathGeometry {
        if t == .identity { return g }
        func map(_ p: LocalPoint) -> LocalPoint {
            let q = p.cg.applying(t)
            return LocalPoint(q.x, q.y)
        }
        return PathGeometry(subpaths: g.subpaths.map { sp in
            Subpath(start: map(sp.start),
                    segments: sp.segments.map { seg in
                        switch seg {
                        case .line(let p): return .line(to: map(p))
                        case .cubic(let a, let b, let p): return .cubic(c1: map(a), c2: map(b), to: map(p))
                        }
                    },
                    isClosed: sp.isClosed)
        })
    }
}
