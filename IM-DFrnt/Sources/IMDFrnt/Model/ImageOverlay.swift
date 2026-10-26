import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 이미지 레이어의 원본 바이트(신기능 15항, #84). 가져올 때 한 번 줄이고 다시 인코딩한 JPEG·PNG다.
///
/// **같음은 `id`로만 판정한다.** 바이트는 만든 뒤 바뀌지 않는다. 실행취소는 편집마다 프로젝트 전체를
/// 앞뒤로 비교하는데(`perform`), 바이트를 비교하면 그때마다 수 MB를 훑는다.
struct ImageOverlayData: Codable, Sendable, Equatable {
    let id: UUID
    let bytes: Data

    init(id: UUID = UUID(), bytes: Data) {
        self.id = id
        self.bytes = bytes
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

/// 층의 feature type 레이어 하나에 얹는 이미지(신기능 15항, #84).
/// 위치는 도면 좌표로 둔다. 이미지 중심이 `center`에 오고, 그 둘레로 `rotation`(도)만큼 돌린 뒤
/// 이미지 1픽셀을 도면 길이 `scale`로 늘린다. 화면 확대·캔버스 회전은 이 값을 바꾸지 않는다.
struct LevelImageOverlay: Equatable, Codable, Sendable {
    var image: ImageOverlayData
    var sourceName: String
    var pixelWidth: Double
    var pixelHeight: Double
    var centerX: Double
    var centerY: Double
    var scale: Double
    var rotation: Double = 0
    var presentation = DrawingLayerPresentation()

    static let scaleRange: ClosedRange<Double> = 1e-4...1e4

    var center: LocalPoint {
        get { LocalPoint(centerX, centerY) }
        set { centerX = newValue.x; centerY = newValue.y }
    }

    var pixelRect: CGRect { CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight) }

    /// 이미지 픽셀(왼쪽 위 원점) → 도면 좌표.
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: centerX, y: centerY)
            .rotated(by: rotation * .pi / 180)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -pixelWidth / 2, y: -pixelHeight / 2)
    }

    /// 도면 영역(`canvas`)의 90%에 들어가는 배율. 처음 놓을 때와 '도면에 맞추기'에 쓴다.
    func fitScale(in canvas: CGSize) -> Double {
        guard pixelWidth > 0, pixelHeight > 0, canvas.width > 0, canvas.height > 0 else { return 1 }
        return min(canvas.width / pixelWidth, canvas.height / pixelHeight) * 0.9
    }

    mutating func fit(in canvas: CGSize) {
        scale = fitScale(in: canvas)
        rotation = 0
        center = LocalPoint(canvas.width / 2, canvas.height / 2)
    }

    mutating func setScale(_ value: Double) {
        scale = min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, value))
    }

    mutating func setRotation(_ degrees: Double) {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d <= -180 { d += 360 }
        rotation = d
        // -180~180으로 접는다. 같은 방향이 여러 수치로 저장되면 슬라이더가 끝에 붙어 움직이지 않는다.
    }
}

/// 사진 파일을 이미지 레이어 바이트로 바꾼다. 화면을 막지 않도록 백그라운드에서 부른다.
enum ImageOverlayImport {
    static let maxPixelSize = 4096
    // 긴 변을 이 길이로 줄인다. 휴대폰 사진(4032px)은 거의 그대로이고, 스캔한 대형 도면만 줄어든다.
    // 그리기·저장 비용이 픽셀 수에 비례해 상한이 없으면 프로젝트 파일과 캔버스가 함께 무거워진다.

    static let allowedTypes: [UTType] = [.jpeg, .png, .heic]

    struct Prepared: @unchecked Sendable {
        let data: ImageOverlayData
        let image: CGImage
        let sourceName: String
    }
    // CGImage는 만든 뒤 바뀌지 않으므로 스레드를 넘겨도 안전하다.

    enum Failure: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self { case .unreadable(let name): return "\(name)을 이미지로 읽지 못했습니다." }
        }
    }

    static func prepare(url: URL) throws -> Prepared {
        let name = url.lastPathComponent
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable(name) }
        return try prepare(data: data, sourceName: name)
    }

    static func prepare(data: Data, sourceName: String) throws -> Prepared {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { throw Failure.unreadable(sourceName) }
        // 썸네일 경로로 읽으면 축소와 EXIF 방향 반영이 한 번에 된다. 휴대폰 사진은 대개
        // 옆으로 누운 픽셀에 "90° 돌려 보라"는 표시만 붙어 있어, 반영하지 않으면 누워서 보인다.
        let isPNG = (CGImageSourceGetType(source) as String?).flatMap(UTType.init)?.conforms(to: .png) == true
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let hasAlpha = isPNG && ((properties?[kCGImagePropertyHasAlpha] as? Bool)
            ?? ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo))
        // 투명한 부분은 PNG에서만 지킨다. HEIC는 불투명한 사진도 풀면 알파 채널이 붙어 나오고
        // 알파 여부 표시도 없어서, 풀린 이미지만 보면 휴대폰 사진이 전부 PNG(몇 배 큰 파일)로 저장된다.
        let type = hasAlpha ? UTType.png : UTType.jpeg
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)
        else { throw Failure.unreadable(sourceName) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable(sourceName) }
        // HEIC를 그대로 두지 않고 JPEG·PNG로 바꿔 저장한다. 프로젝트를 여는 쪽 환경과 무관하게 열리고,
        // 투명한 부분이 있는 PNG만 PNG로 남긴다.
        return Prepared(data: ImageOverlayData(bytes: out as Data), image: image, sourceName: sourceName)
    }

    static func decode(_ data: ImageOverlayData) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data.bytes as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
