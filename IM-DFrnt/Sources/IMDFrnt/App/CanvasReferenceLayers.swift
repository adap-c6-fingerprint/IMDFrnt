import Foundation
import SwiftUI

struct CanvasReferenceInput: Equatable, Sendable {
    let levelID: UUID
    let svg: String
    let sourceName: String
    let footprints: [ProjectJSON]
    let coordinates: IMDFCoordinateSpace?
    let anchors: [AnchorPair]
}

struct PreparedCanvasReferences: Sendable {
    let input: CanvasReferenceInput
    let reference: DrawingDocument?
    let paths: [Path]
    let footprintPaths: [Path]

    static func make(_ input: CanvasReferenceInput) throws -> Self {
        let doc = try input.svg.isEmpty ? nil : SVGParser.parse(data: Data(input.svg.utf8), sourceName: input.sourceName)
        let transform = try? GeoAffineTransform.fit(from: input.anchors)
        func local(_ pair: [Double]) -> LocalPoint? {
            guard pair.count >= 2 else { return nil }
            if let coordinates = input.coordinates { return coordinates.localPoint(longitude: pair[0], latitude: pair[1]) }
            guard let t = transform else { return nil }
            let determinant = t.a * t.e - t.b * t.d
            guard determinant.isFinite, abs(determinant) > Double.leastNormalMagnitude else { return nil }
            let lon = pair[0] - t.c, lat = pair[1] - t.f
            let point = LocalPoint((t.e * lon - t.b * lat) / determinant, (t.a * lat - t.d * lon) / determinant)
            return point.x.isFinite && point.y.isFinite ? point : nil
        }
        var footprints: [Path] = []
        for feature in input.footprints {
            try Task.checkCancellation()
            guard let geometry = feature["geometry"] else { continue }
            var path = Path()
            for ring in try FootprintGeometry.rings(geometry) {
                let points = ring.compactMap(local)
                guard points.count == ring.count, points.count >= 4 else { continue }
                path.addLines(points.map(\.cg)); path.closeSubpath()
            }
            if !path.isEmpty { footprints.append(path) }
        }
        try Task.checkCancellation()
        return Self(input: input, reference: doc, paths: doc?.objects.map { $0.geometry.swiftUIPath } ?? [], footprintPaths: footprints)
    }
}

@MainActor
extension AppEnvironment {
    var primarySVGPresentation: DrawingLayerPresentation {
        activeLevel?.svgPresentation ?? DrawingLayerPresentation(isVisible: true, opacity: 1)
    }
    var footprintPresentation: DrawingLayerPresentation {
        buildingProject.footprintPresentation ?? DrawingLayerPresentation()
    }
    var referenceInput: CanvasReferenceInput? {
        guard let level = activeLevel else { return nil }
        return CanvasReferenceInput(levelID: level.id, svg: level.referenceDrawing?.svg ?? "",
            sourceName: level.referenceDrawing?.sourceName ?? "", footprints: globalFeatures("footprint"),
            coordinates: level.info.imdfCoordinates, anchors: anchors.pairs)
    }

    func refreshCanvasReferences() {
        guard let input = referenceInput else {
            canvasReferenceTask?.cancel(); canvasReferenceTask = nil; canvasReferences = nil
            return
        }
        if canvasReferences?.input == input { return }
        canvasReferenceTask?.cancel()
        canvasReferences = nil
        if let cached = canvasReferenceCache[input.levelID], cached.input == input {
            canvasReferences = cached; return
        }
        let project = projectID
        canvasReferenceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let worker = Task.detached(priority: .userInitiated) { try PreparedCanvasReferences.make(input) }
                let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, projectID == project, referenceInput == input else { return }
                canvasReferences = prepared
                canvasReferenceCache[input.levelID] = prepared
                if canvasReferenceCache.count > 6, let id = canvasReferenceCache.keys.first(where: { $0 != input.levelID }) { canvasReferenceCache.removeValue(forKey: id) }
            } catch {
                guard !Task.isCancelled, projectID == project, referenceInput == input else { return }
                notify("참고 레이어를 표시하지 못했습니다: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func applyReferenceDrawing(_ prepared: PreparedLevelDrawing) {
        guard let i = buildingProject.levels.firstIndex(where: { $0.id == prepared.input.levelID }) else { return }
        perform("층 참고 도면 불러오기") {
            buildingProject.levels[i].referenceDrawing = LevelReferenceDrawing(svg: prepared.input.svg, sourceName: prepared.input.sourceName)
        }
        notify("\(prepared.input.sourceName)을 \(buildingProject.levels[i].info.name)의 참고 도면으로 불러왔습니다.")
    }

    func updateDrawingLayer(_ kind: String, visible: Bool? = nil, opacity: Double? = nil) {
        guard let i = buildingProject.levels.firstIndex(where: { $0.id == routingFloorID }) else { return }
        let value = opacity.map { min(1, max(0, $0)) }
        perform("도면 레이어 표시 변경", coalescingKey: "drawing-layer:\(routingFloorID!):\(kind)") {
            if kind == "footprint" {
                var presentation = footprintPresentation
                if let visible { presentation.isVisible = visible }; if let value { presentation.opacity = value }
                buildingProject.footprintPresentation = presentation
            } else if kind == "reference", var reference = buildingProject.levels[i].referenceDrawing {
                if let visible { reference.presentation.isVisible = visible }; if let value { reference.presentation.opacity = value }
                buildingProject.levels[i].referenceDrawing = reference
            } else if kind == "svg" {
                var presentation = primarySVGPresentation
                if let visible { presentation.isVisible = visible }; if let value { presentation.opacity = value }
                buildingProject.levels[i].svgPresentation = presentation
            }
        }
        invalidateRenderStates()
    }

    func requestReferenceDrawingDeletion() {
        guard let id = routingFloorID, let reference = activeLevel?.referenceDrawing else { return }
        requestDeletion(title: "참고 도면을 삭제할까요?", message: "\(reference.sourceName)을 이 층에서 제거합니다. IMDF 도형과 노드·연결은 유지됩니다.") { env in
            env.perform("층 참고 도면 삭제") {
                if let i = env.buildingProject.levels.firstIndex(where: { $0.id == id }) { env.buildingProject.levels[i].referenceDrawing = nil }
            }
        }
    }
}
