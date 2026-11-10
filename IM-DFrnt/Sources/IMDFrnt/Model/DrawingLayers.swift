import CoreGraphics
import Foundation

struct DrawingLayerPresentation: Equatable, Codable, Sendable {
    var isVisible = true
    var opacity = 0.5
}

struct LevelReferenceDrawing: Equatable, Codable, Sendable {
    var svg: String
    var sourceName: String
    var presentation = DrawingLayerPresentation()
    // Optional so projects saved before #121 retain their original fit-to-canvas placement.
    var alignment: ReferenceDrawingAlignment?
}

struct ReferenceDrawingAlignment: Equatable, Codable, Sendable {
    var x = 0.0
    var y = 0.0
    var rotation = 0.0
    var scale = 1.0

    init(x: Double = 0, y: Double = 0, rotation: Double = 0, scale: Double = 1) {
        self.x = x; self.y = y; self.rotation = rotation; self.scale = scale
    }

    private enum CodingKeys: String, CodingKey { case x, y, rotation, scale }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        rotation = try c.decode(Double.self, forKey: .rotation)
        scale = try c.decode(Double.self, forKey: .scale)
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .scale, in: c, debugDescription: "Invalid reference drawing alignment")
        }
    }

    var isValid: Bool {
        x.isFinite && y.isFinite && abs(x) <= 1e9 && abs(y) <= 1e9 &&
        rotation.isFinite && abs(rotation) <= 360 && scale.isFinite && (0.001...1000).contains(scale)
    }

    /// Rendering and snapping share exactly the same fit, centre pivot and user transform.
    func transform(source: CGSize, canvas: CGSize) -> CGAffineTransform? {
        guard isValid, source.width.isFinite, source.height.isFinite,
              canvas.width.isFinite, canvas.height.isFinite,
              source.width > 0, source.height > 0, canvas.width > 0, canvas.height > 0 else { return nil }
        let fit = min(canvas.width / source.width, canvas.height / source.height) * scale
        guard fit.isFinite, fit > 0 else { return nil }
        return CGAffineTransform(translationX: canvas.width / 2 + x, y: canvas.height / 2 + y)
            .rotated(by: rotation * .pi / 180)
            .scaledBy(x: fit, y: fit)
            .translatedBy(x: -source.width / 2, y: -source.height / 2)
    }
}
