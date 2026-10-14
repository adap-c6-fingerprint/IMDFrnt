import AppKit
import CryptoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Image pixels stay visible in drawing coordinates; they are never converted
/// to invented vector shapes. The original image is embedded in project SVG.
struct DrawingRasterImage: Sendable {
    let image: CGImage
    let rect: CGRect
    let transform: CGAffineTransform
    let digest: String
}

enum DrawingImageImporter {
    static func decode(_ data: Data) throws -> CGImage {
        guard data.count <= 64_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width)*Double(height) <= 40_000_000 else {
            throw SVGParser.Failure(message: "이미지를 읽지 못했습니다. 64 MB·4천만 픽셀 이하의 PNG/JPG를 사용하세요.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw SVGParser.Failure(message: "이미지 디코딩에 실패했습니다.")
        }
        return image
    }

    static func embeddedSVG(from data: Data) throws -> Data {
        let image = try decode(data)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else {
            throw SVGParser.Failure(message: "이미지 형식을 읽지 못했습니다.")
        }
        let identifier = type as String
        guard identifier == UTType.png.identifier || identifier == UTType.jpeg.identifier else {
            throw SVGParser.Failure(message: "PNG 또는 JPG 이미지를 사용하세요.")
        }
        let mime = identifier == UTType.png.identifier ? "image/png" : "image/jpeg"
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(image.width)" height="\(image.height)" viewBox="0 0 \(image.width) \(image.height)">
        <image x="0" y="0" width="\(image.width)" height="\(image.height)" href="data:\(mime);base64,\(data.base64EncodedString())"/>
        </svg>
        """
        return Data(svg.utf8)
    }

    static func embedLocalImages(in data: Data, relativeTo sourceURL: URL?) throws -> Data {
        let document = try XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever)
        var changed = false
        for case let element as XMLElement in try document.nodes(forXPath: "//*[local-name()='image']") {
            guard let attribute = element.attribute(forName: "href") ?? element.attribute(forName: "xlink:href"),
                  let href = attribute.stringValue, !href.hasPrefix("data:") else { continue }
            guard let sourceURL, let url = URL(string: href, relativeTo: sourceURL.deletingLastPathComponent()), url.isFileURL else {
                throw SVGParser.Failure(message: "연결 이미지의 로컬 파일을 찾지 못했습니다. 이미지 파일을 직접 열어 주세요.")
            }
            let imageData = try Data(contentsOf: url.absoluteURL)
            let embedded = try XMLDocument(data: embeddedSVG(from: imageData), options: .nodeLoadExternalEntitiesNever)
            let node = try embedded.nodes(forXPath: "//*[local-name()='image']").first as? XMLElement
            attribute.stringValue = node?.attribute(forName: "href")?.stringValue
            changed = true
        }
        return changed ? document.xmlData : data
    }

    static func embeddedImage(_ href: String) throws -> (CGImage, String) {
        guard href.hasPrefix("data:image/"), let comma = href.firstIndex(of: ","),
              href[..<comma].contains(";base64"),
              let data = Data(base64Encoded: String(href[href.index(after: comma)...]), options: .ignoreUnknownCharacters) else {
            throw SVGParser.Failure(message: "SVG의 연결 이미지는 내장된 PNG/JPG여야 합니다. 이미지 파일을 직접 열어 주세요.")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (try decode(data), digest)
    }
}

extension DrawingDocument {
    func drawImages(in context: GraphicsContext) {
        for raster in rasterImages {
            var layer = context
            layer.concatenate(raster.transform)
            layer.draw(Image(decorative: raster.image, scale: 1), in: raster.rect)
        }
    }
}
