import SwiftUI

@MainActor
extension AppEnvironment {
    func drawReferenceDrawing(in context: GraphicsContext, canvas: CGSize, zoom: CGFloat,
                              showSnaps: Bool = false, visible: CGRect? = nil) {
        guard let prepared = canvasReferences, prepared.input.levelID == routingFloorID,
              let doc = prepared.reference, let reference = activeLevel?.referenceDrawing,
              reference.presentation.isVisible, reference.presentation.opacity > 0,
              let transform = referenceDrawingTransform(canvas: canvas) else { return }
        var layer = context
        layer.concatenate(transform)
        layer.opacity *= reference.presentation.opacity
        let rawVisible = visible?.applying(transform.inverted())
        layer.drawLayer { ctx in
            doc.drawImages(in: ctx)
            for (i, object) in doc.objects.enumerated() {
                let path = prepared.paths[i]
                if let rawVisible, !prepared.bounds[i].insetBy(dx: -object.style.strokeWidth, dy: -object.style.strokeWidth).intersects(rawVisible) { continue }
                if let fill = object.style.fill {
                    ctx.fill(path, with: .color(canvasBackground.resolveFill(fill)), style: FillStyle(eoFill: true))
                }
                ctx.stroke(path, with: .color(canvasBackground.resolve(object.style.stroke)),
                           style: StrokeStyle(lineWidth: object.style.strokeWidth, dash: object.style.dashPattern.map { CGFloat($0) }))
            }
        }
        guard showSnaps else { return }
        let radius = 2 / max(zoom * hypot(transform.a, transform.b), 1e-9)
        let indices = rawVisible.map { prepared.snapIndex.indices(in: $0) } ?? Array(prepared.snapIndex.points.indices)
        for i in indices {
            let p = prepared.snapIndex.points[i].point
            layer.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                       with: .color(.yellow))
        }
    }
}
