import AppKit
import Foundation

@MainActor
enum DrawingLoadingReviewSelfTest {
    static func run(environment: () -> AppEnvironment, check: (String, Bool) -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntDrawingReview-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let replacement = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"400\" height=\"300\"><rect x=\"10\" y=\"10\" width=\"200\" height=\"200\"/></svg>"
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.red, atX: x, y: y) } }
        let drawings: [(String, Data)] = [
            ("replacement.svg", Data(replacement.utf8)),
            ("replacement.png", bitmap.representation(using: .png, properties: [:])!),
            ("replacement.jpg", bitmap.representation(using: .jpeg, properties: [:])!)
        ]
        func anchorOnlyEnvironment() -> AppEnvironment {
            let env = environment()
            env.openSample()
            env.lastExplicitSavedProject = env.makeProjectFile()
            env.perform("기준점 추가") {
                env.anchors.add(local: LocalPoint(0, 0), geo: GeoPoint(longitude: 129, latitude: 36), label: "origin")
                env.anchors.add(local: LocalPoint(100, 0), geo: GeoPoint(longitude: 129.001, latitude: 36), label: "east")
                env.anchors.add(local: LocalPoint(0, 100), geo: GeoPoint(longitude: 129, latitude: 35.999), label: "south")
            }
            _ = env.persist(showingBanner: false)
            return env
        }
        for (name, data) in drawings {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            let env = anchorOnlyEnvironment()
            check("Finder \(name): Feature·노드 없이 기준점만 미저장인 입력", env.hasUnsavedChanges && env.anchors.pairs.count == 3 && env.features.features.isEmpty && env.routing.nodes.isEmpty)
            let before = env.snapshot
            let undo = env.undoStack.undoEntries, redo = env.undoStack.redoEntries
            let recovery = try Data(contentsOf: env.recoveryURL)
            var asked = false
            let result = await env.openDocumentAsync(at: url, confirmingChanges: { asked = true; return false })
            let recoveryAfter = try Data(contentsOf: env.recoveryURL)
            check("Finder \(name): 기준점만 수정한 경우에도 확인 요청·취소", asked && result == .cancelled)
            check("Finder \(name): 취소는 기준점·도면·복구본·Undo 보존",
                env.snapshot == before && env.undoStack.undoEntries == undo && env.undoStack.redoEntries == redo
                && recoveryAfter == recovery && !env.isProjectBusy)
        }
        let svgURL = directory.appendingPathComponent(drawings[0].0)
        let saveCancelled = anchorOnlyEnvironment()
        let beforeSaveCancel = saveCancelled.snapshot
        let saveCancelResult = await saveCancelled.openDocumentAsync(at: svgURL, confirmingChanges: {
            saveCancelled.resolveUnsavedChanges(.save, saving: { false })
        })
        check("Finder 도면 열기의 저장 창 취소는 교체도 취소", saveCancelResult == .cancelled && saveCancelled.snapshot == beforeSaveCancel)

        let saved = anchorOnlyEnvironment()
        let originalURL = directory.appendingPathComponent("before-replacement.imdfrnt")
        let originalAnchors = saved.anchors
        let saveResult = await saved.openDocumentAsync(at: svgURL, confirmingChanges: {
            saved.resolveUnsavedChanges(.save, saving: { saved.saveProject(to: originalURL) })
        })
        let original = try? ProjectFile.decoded(from: Data(contentsOf: originalURL))
        check("Finder 교체 전 저장 승인은 기존 기준점을 파일에 보존",
            saveResult == .opened && original?.commonProject().levels.first?.info.anchors == originalAnchors
            && saved.document?.sourceName == drawings[0].0 && saved.anchors.pairs.isEmpty)

        let discarded = anchorOnlyEnvironment()
        let discardResult = await discarded.openDocumentAsync(at: svgURL, confirmingChanges: {
            discarded.resolveUnsavedChanges(.discard, saving: { false })
        })
        check("Finder 변경 폐기 승인 후에만 도면과 기준점을 교체", discardResult == .opened && discarded.document?.sourceName == drawings[0].0 && discarded.anchors.pairs.isEmpty)
        discarded.undo(); await discarded.waitForLevelDrawing()
        check("Finder 승인된 도면 교체 Undo는 기준점 복원", discarded.anchors.pairs.count == 3 && discarded.document?.sourceName == SampleFloorplan.name)

        let brokenURL = directory.appendingPathComponent("broken.svg")
        try Data("<svg>broken</svg>".utf8).write(to: brokenURL)
        let broken = anchorOnlyEnvironment()
        let beforeBroken = broken.snapshot
        var askedForBroken = false
        let brokenResult = await broken.openDocumentAsync(at: brokenURL, confirmingChanges: { askedForBroken = true; return true })
        check("손상 SVG는 확인 질문 없이 거절하고 기준점을 보존", brokenResult == .failed && !askedForBroken && broken.snapshot == beforeBroken)

        let ring = environment()
        let openSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"200\"><path d=\"M 0 0 L 100 0 L 100 100 L 0 100\"/></svg>"
        ring.load(data: Data(openSVG.utf8), name: "open-ring.svg")
        let levelID = ring.routingFloorID!
        let feature = FeatureGroup(featureType: .unit, serialNumber: "unit-review", memberIDs: Set(ring.document!.objects.map(\.id)))
        ring.perform("열린 링 저장") {
            ring.features.insert(feature)
            ring.expandedFeature = feature.id
        }
        let expectedGaps = ring.ringClosure(of: feature)!.gaps
        check("열린 링 회귀 입력: 실제 틈 2곳과 경고 표시", expectedGaps.count == 2 && ring.openRingGaps.count == 2)
        _ = ring.addProjectLevel()
        ring.levelPrefetchTask?.cancel()
        ring.levelDrawingCache.invalidate(levelID)
        ring.undo()
        check("캐시 없는 층 Undo는 펼친 feature를 유지한 채 비동기 로딩", ring.routingFloorID == levelID && ring.loadingLevelID == levelID && ring.document == nil && ring.expandedFeature == feature.id)
        await ring.waitForLevelDrawing()
        let actualGaps = ring.ringClosure(of: feature)?.gaps ?? []
        check("캐시 없는 Undo 로딩 완료 후 실제 틈 2곳의 경고 복원",
            actualGaps.count == 2 && ring.openRingGaps.count == 2
            && Set(ring.openRingGaps.map(\.point)) == Set(actualGaps.map(\.point)))
        ring.redo()
        check("다른 빈 층으로 Redo하면 이전 링 경고 제거", ring.routingFloorID != levelID && ring.openRingGaps.isEmpty)
        ring.undo(); await ring.waitForLevelDrawing()
        check("캐시된 층 Undo도 열린 링 경고 2곳 유지", ring.document != nil && ring.openRingGaps.count == expectedGaps.count)
    }
}
