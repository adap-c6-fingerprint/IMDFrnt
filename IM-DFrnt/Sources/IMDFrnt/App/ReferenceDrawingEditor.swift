import AppKit
import UniformTypeIdentifiers

@MainActor
extension AppEnvironment {
    var referenceDrawingAlignment: ReferenceDrawingAlignment {
        referenceDrawingPreview ?? activeLevel?.referenceDrawing?.alignment ?? ReferenceDrawingAlignment()
    }

    func importReferenceDrawing() {
        guard let level = activeLevel, !isProjectBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "\(level.info.name) 참고 도면 불러오기"
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml, .png, .jpeg]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importDrawingAsync(at: url, asReference: true) }
    }

    func updateReferenceDrawingAlignment(_ value: ReferenceDrawingAlignment, coalescingKey: String? = nil) {
        guard value.isValid, !isProjectBusy,
              let i = buildingProject.levels.firstIndex(where: { $0.id == routingFloorID }),
              buildingProject.levels[i].referenceDrawing != nil else { return }
        perform("참고 도면 정렬", coalescingKey: coalescingKey) {
            buildingProject.levels[i].referenceDrawing?.alignment = value
        }
    }

    func referenceDrawingTransform(canvas: CGSize) -> CGAffineTransform? {
        guard let prepared = canvasReferences, prepared.input.levelID == routingFloorID,
              let doc = prepared.reference else { return nil }
        return referenceDrawingAlignment.transform(source: doc.canvasSize, canvas: canvas)
    }

    /// Reference owners never enter the primary SVG ownership/progress registries.
    func nearestDrawingSnap(to point: LocalPoint, within radius: Double) -> SnapPointExtractor.SnapPoint? {
        let primary = snapPointIndex.nearest(to: point, within: radius)
        guard let reference = activeLevel?.referenceDrawing,
              reference.presentation.isVisible, reference.presentation.opacity > 0,
              let doc = document, let prepared = canvasReferences,
              let transform = referenceDrawingTransform(canvas: doc.canvasSize) else { return primary }
        let local = point.cg.applying(transform.inverted())
        let scale = hypot(transform.a, transform.b)
        guard let raw = prepared.snapIndex.nearest(to: LocalPoint(local.x, local.y), within: radius / scale) else { return primary }
        let mapped = raw.point.cg.applying(transform)
        let candidate = SnapPointExtractor.SnapPoint(id: "reference:\(prepared.input.levelID):\(raw.id)",
            point: LocalPoint(mapped.x, mapped.y), kind: raw.kind, owners: [])
        if let primary, primary.point.distance(to: point) <= candidate.point.distance(to: point) { return primary }
        return candidate
    }
}
