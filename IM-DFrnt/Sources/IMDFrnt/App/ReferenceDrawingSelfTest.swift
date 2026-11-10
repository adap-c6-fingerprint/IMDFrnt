import AppKit
import SwiftUI

@MainActor
enum ReferenceDrawingSelfTest {
    static func run(environment: () -> AppEnvironment, check: (String, Bool) -> Void) async throws {
        let env = environment()
        let base = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"200\"><path d=\"M10 10L90 10L90 90Z\"/></svg>"
        let reference = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\"><rect x=\"10\" y=\"20\" width=\"30\" height=\"40\" fill=\"red\"/><path d=\"M0 50L100 50M50 0L50 100\" stroke=\"red\"/></svg>"
        env.load(data: Data(base.utf8), name: "primary.svg")
        env.anchors.add(local: LocalPoint(0, 0), geo: GeoPoint(longitude: 129, latitude: 36), label: "keep")
        let feature = FeatureGroup(featureType: .unit, serialNumber: "unit-keep", memberIDs: [])
        env.features.insert(feature)
        env.enterRoutingScreen()
        env.handleRoutingClick(at: LocalPoint(30, 30), tolerance: 1, modifiers: .command)
        env.showRoutingScreen = false
        let floorID = env.routingFloorID!, primaryInfo = env.projectContents.levels[0].info
        let features = env.features, anchors = env.anchors, routing = env.routing
        let total = env.totalPointCount
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntReference-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("reference.svg")
        try Data(reference.utf8).write(to: url)
        let result = await env.importDrawingAsync(at: url, asReference: true)
        await env.canvasReferenceTask?.value
        check("#121 SVG 층에 기본 도면 교체 없이 참고 SVG 추가", result == .opened && env.activeLevel?.referenceDrawing?.svg == reference && env.projectContents.levels[0].info == primaryInfo)
        check("#121 참고 추가는 IMDF 도형·Anchor·노드·진행률 유지", env.features == features && env.anchors == anchors && env.routing == routing && env.totalPointCount == total)
        check("#121 참고 SVG의 꼭짓점·교차점 캐시 준비", env.canvasReferences?.snapIndex.points.contains { $0.kind == .crossing } == true)

        let legacy = LevelReferenceDrawing(svg: reference, sourceName: "old.svg")
        let decodedLegacy = try JSONDecoder().decode(LevelReferenceDrawing.self, from: JSONEncoder().encode(legacy))
        check("#121 정렬 필드 없는 기존 참고 도면 호환", decodedLegacy.alignment == nil)
        let fit = ReferenceDrawingAlignment().transform(source: CGSize(width: 100, height: 50), canvas: CGSize(width: 200, height: 200))!
        check("#121 기존 중앙 맞춤 유지", CGPoint.zero.applying(fit) == CGPoint(x: 0, y: 50) && CGPoint(x: 100, y: 50).applying(fit) == CGPoint(x: 200, y: 150))
        let alignment = ReferenceDrawingAlignment(x: 1000, y: 500, rotation: 90, scale: 0.5)
        let input = env.referenceInput
        env.updateReferenceDrawingAlignment(alignment)
        check("#121 정렬은 SVG 재파싱/자석 재계산 입력을 바꾸지 않음", env.referenceInput == input)
        let transform = env.referenceDrawingTransform(canvas: env.document!.canvasSize)!
        let mapped = CGPoint(x: 10, y: 20).applying(transform)
        check("#121 중심 기준 이동·회전·크기 조합", abs(mapped.x - 1130) < 1e-8 && abs(mapped.y - 560) < 1e-8)
        let point = LocalPoint(mapped.x, mapped.y)
        let snap = env.nearestDrawingSnap(to: LocalPoint(point.x + 0.1, point.y), within: 0.5)
        check("#121 변환된 화면 위치와 자석 일치·기본 도면 소유권 분리", snap?.point.distance(to: point) ?? 1 < 1e-8 && snap?.owners.isEmpty == true)
        check("#121 반경 밖 참고 점은 잡지 않음", env.nearestDrawingSnap(to: LocalPoint(point.x + 0.6, point.y), within: 0.5) == nil)
        env.undo()
        check("#121 정렬 Undo", env.activeLevel?.referenceDrawing?.alignment == nil)
        env.redo()
        check("#121 정렬 Redo", env.referenceDrawingAlignment == alignment)
        let countBeforePreview = env.undoStack.undoEntries.count
        env.referenceDrawingPreview = ReferenceDrawingAlignment(x: 100, y: 200)
        check("#121 드래그 미리보기는 저장 상태·Undo 변경 없음", env.activeLevel?.referenceDrawing?.alignment == alignment && env.undoStack.undoEntries.count == countBeforePreview)
        env.referenceDrawingPreview = nil

        env.updateDrawingLayer("reference", visible: false)
        check("#121 숨긴 참고 SVG에는 자석 없음", env.nearestDrawingSnap(to: point, within: 0.5) == nil)
        env.updateDrawingLayer("reference", visible: true, opacity: 0)
        check("#121 불투명도 0% 참고 SVG에는 자석 없음", env.nearestDrawingSnap(to: point, within: 0.5) == nil)
        env.updateDrawingLayer("reference", opacity: 0.35)
        env.updateDrawingLayer("svg", opacity: 0.8)
        let file = try ProjectFile.decoded(from: env.makeProjectFile()!.encoded())
        let saved = file.commonProject().levels.first { $0.id == floorID }!
        check("#121 층별 도면·정렬·독립 불투명도 저장/재열기", saved.referenceDrawing?.alignment == alignment && saved.referenceDrawing?.presentation.opacity == 0.35 && saved.svgPresentation?.opacity == 0.8 && saved.info == primaryInfo)
        let other = env.addProjectLevel()
        env.isAligningReferenceDrawing = true
        env.referenceDrawingPreview = alignment
        env.selectProjectLevel(floorID)
        await env.waitForLevelDrawing()
        await env.canvasReferenceTask?.value
        check("#121 층 전환 시 정렬 모드·미리보기 초기화 및 원래 설정 복원", !env.isAligningReferenceDrawing && env.referenceDrawingPreview == nil && env.referenceDrawingAlignment == alignment && other != floorID)
        check("#121 정렬 후에도 원본 좌표와 작업 데이터 불변", env.projectContents.levels.first { $0.id == floorID }!.info == primaryInfo && env.features == features && env.anchors == anchors && env.routing.nodes == routing.nodes && env.routing.edges == routing.edges)
        let beforeInvalid = env.makeProjectFile()!
        env.updateReferenceDrawingAlignment(ReferenceDrawingAlignment(scale: 0))
        env.updateReferenceDrawingAlignment(ReferenceDrawingAlignment(x: .infinity))
        check("#121 잘못된 배율·비유한 좌표 거절", env.makeProjectFile()!.hasSameContents(as: beforeInvalid))
        let invalid = Data("{\"x\":0,\"y\":0,\"rotation\":0,\"scale\":-1}".utf8)
        check("#121 손상된 저장 정렬 거절", (try? JSONDecoder().decode(ReferenceDrawingAlignment.self, from: invalid)) == nil)
        try Data("broken".utf8).write(to: url)
        let invalidResult = await env.importDrawingAsync(at: url, asReference: true)
        check("#121 손상 참고 파일은 기존 도면/설정/작업 유지", invalidResult == .failed && env.makeProjectFile()!.hasSameContents(as: beforeInvalid))

        for type in [NSBitmapImageRep.FileType.png, .jpeg] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let imageURL = folder.appendingPathComponent(type == .png ? "image.png" : "image.jpg")
            try bitmap.representation(using: type, properties: [:])!.write(to: imageURL)
            let imported = await env.importDrawingAsync(at: imageURL, asReference: true)
            await env.canvasReferenceTask?.value
            check("#121 \(imageURL.pathExtension) 참고 이미지 내장·교체 시 정렬 초기화·자석 없음", imported == .opened && env.canvasReferences?.reference?.rasterImages.count == 1 && env.canvasReferences?.snapIndex.points.isEmpty == true && env.activeLevel?.referenceDrawing?.alignment == nil && env.activeLevel?.info == primaryInfo)
        }
        env.requestReferenceDrawingDeletion()
        if let request = env.pendingDeletion { env.confirmDeletion(request.id) }
        check("#121 참고만 삭제·기본/작업 데이터 유지", env.activeLevel?.referenceDrawing == nil && env.features == features && env.anchors == anchors)
        env.undo()
        check("#121 참고 삭제 Undo", env.activeLevel?.referenceDrawing != nil)
        try await pixels(environment: environment, check: check)
        let tagged = environment()
        tagged.openSample()
        tagged.selectPropertyType(.opening)
        tagged.selection.selected = [tagged.document!.objects[0].id]
        tagged.createFeature()
        let doc = tagged.document!
        let all = tagged.canvasObjectBatches(document: doc, primaryOpacity: 1)
        let background = tagged.canvasObjectBatches(document: doc, primaryOpacity: 1, workOnly: false)
        let work = tagged.canvasObjectBatches(document: doc, primaryOpacity: 1, workOnly: true)
        func count(_ batches: CanvasBatches) -> Int {
            var n = 0
            for (_, path) in batches.strokes { path.forEach { if case .move = $0 { n += 1 } } }
            return n
        }
        // Use path commands rather than SVG object counts: one SVG object can have several subpaths.
        check("#121 기본 SVG/태깅 작업 분리는 중복·누락 없이 합성", count(work) > 0 && count(background) + count(work) == count(all))
    }

    private static func pixels(environment: () -> AppEnvironment, check: (String, Bool) -> Void) async throws {
        let env = environment()
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\"><rect width=\"20\" height=\"20\" fill=\"red\"/></svg>"
        env.load(data: Data(svg.utf8), name: "pixel.svg")
        let input = LevelDrawingInput(levelID: env.routingFloorID!, svg: svg, sourceName: "reference.svg")
        env.applyReferenceDrawing(try PreparedLevelDrawing.make(input))
        await env.canvasReferenceTask?.value
        func pixel() -> NSColor? {
            let renderer = ImageRenderer(content: Canvas { ctx, _ in
                env.drawReferenceDrawing(in: ctx, canvas: CGSize(width: 20, height: 20), zoom: 1)
            }.frame(width: 20, height: 20))
            return renderer.cgImage.flatMap { NSBitmapImageRep(cgImage: $0).colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB) }
        }
        env.updateDrawingLayer("reference", opacity: 0.4)
        check("#121 참고 도면 실제 픽셀에 불투명도 적용", pixel().map { abs($0.alphaComponent - 0.4) < 0.03 } == true)
        env.updateDrawingLayer("reference", visible: false)
        check("#121 참고 숨김 실제 픽셀 투명", pixel().map { $0.alphaComponent < 0.01 } == true)
        env.updateDrawingLayer("reference", visible: true, opacity: 1)
        env.updateReferenceDrawingAlignment(ReferenceDrawingAlignment(x: 30))
        check("#121 이동한 참고 도면은 원래 자리에서 사라짐", pixel().map { $0.alphaComponent < 0.01 } == true)
    }
}
