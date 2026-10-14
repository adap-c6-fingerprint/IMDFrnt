import Foundation

struct DrawingLayerPresentation: Equatable, Codable, Sendable {
    var isVisible = true
    var opacity = 0.5
}

struct LevelReferenceDrawing: Equatable, Codable, Sendable {
    var svg: String
    var sourceName: String
    var presentation = DrawingLayerPresentation()
}
