import Foundation

@MainActor
enum DrawingLoadingSelfTest {
    static func runIfRequested() async {
        guard CommandLine.arguments.contains("--drawing-loading-selftest") else { return }
        var total = 0, failures = 0
        func check(_ name: String, _ valid: Bool) {
            total += 1; if !valid { failures += 1 }
            print("[\(valid ? "PASS" : "FAIL")] \(name)")
        }
        func argument(_ flag: String) -> String? {
            guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[i + 1]
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntDrawingTest-\(UUID())")
        let suite = "IMDFrntDrawingTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        func environment() -> AppEnvironment { AppEnvironment(autosaveFolder: directory, projectDefaults: defaults) }
        do {
            var file = ProjectFile.empty()
            if let path = argument("--drawing-test-project") {
                file = try ProjectFile.decoded(from: Data(contentsOf: URL(fileURLWithPath: path)))
            } else if let path = argument("--drawing-test-svg") {
                let url = URL(fileURLWithPath: path)
                let svg = try DrawingImageImporter.embedLocalImages(in: Data(contentsOf: url), relativeTo: url)
                file.buildingProject = BuildingProject(levels: (0..<2).map { ordinal in
                    ProjectLevel(info: ProjectLevelInfo(name: "\(ordinal + 1)층", ordinal: ordinal,
                        sourceName: url.lastPathComponent, svg: String(decoding: svg, as: UTF8.self)))
                })
            } else if let path = argument("--imdf-test-input") {
                file.buildingProject = try BuildingProject.importing(IMDFImporter.load(URL(fileURLWithPath: path)))
            } else {
                file.buildingProject = BuildingProject(levels: (0..<2).map { ordinal in
                    ProjectLevel(info: ProjectLevelInfo(name: "\(ordinal + 1)층", ordinal: ordinal,
                        sourceName: "\(ordinal).svg", svg: SampleFloorplan.svg))
                })
            }
            let env = environment()
            try await env.adoptProjectAsync(file, from: nil)
            check("도면 준비 전 층 메타데이터·선택 즉시 표시", env.buildingProject.levels.count == file.commonProject().levels.count && env.routingFloorID != nil && env.document == nil && env.loadingLevelID == env.routingFloorID)
            var ticks = 0
            let heartbeat = Task { @MainActor in
                while !Task.isCancelled {
                    ticks += 1
                    do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
                }
            }
            let cold = ContinuousClock.now
            await env.waitForLevelDrawing()
            heartbeat.cancel()
            print("[MEASURE] initial-background-load=\(cold.duration(to: .now)) main-actor-ticks=\(ticks) objects=\(env.document?.objects.count ?? 0)")
            check("로딩 중 메인 액터 응답·도면과 선택된 층 일치", ticks > 0 && env.document?.sourceName == env.currentRoutingFloor?.sourceName && env.loadingLevelID == nil && env.drawingLoadError == nil)
            for round in 0..<2 {
                for level in env.buildingProject.levels.reversed() {
                    let beforeCount = env.levelDrawingCache.preparationCount
                    let start = ContinuousClock.now
                    env.selectProjectLevel(level.id)
                    let callTime = start.duration(to: .now)
                    let readyImmediately = env.loadingLevelID == nil
                    await env.waitForLevelDrawing()
                    print("[MEASURE] round=\(round) level=\(level.info.name) objects=\(env.document?.objects.count ?? 0) selection-call=\(callTime) total=\(start.duration(to: .now)) cached=\(readyImmediately)")
                    check("선택한 층 도면 표시 \(round)/\(level.info.name)", env.routingFloorID == level.id && env.document?.sourceName == level.info.sourceName && env.drawingLoadError == nil)
                    if round == 1 { check("재전환 파싱·파생 계산 반복 없음 \(level.info.name)", readyImmediately && env.levelDrawingCache.preparationCount == beforeCount) }
                }
            }
            env.lastRecoveryProject = env.makeProjectFile()
            check("층 선택·캐시는 저장 데이터 변경 없음", !env.hasUnsavedChanges && env.projectContents.semanticContents == file.commonProject().semanticContents)
            env.cancelLevelDrawingLoads()

            let test = environment()
            let a = UUID(), b = UUID(), c = UUID()
            var fixture = ProjectFile.empty()
            fixture.buildingProject = BuildingProject(levels: [a, b, c].enumerated().map { i, id in
                ProjectLevel(info: ProjectLevelInfo(id: id, name: "\(i + 1)층", ordinal: i, sourceName: "\(i).svg", svg: SampleFloorplan.svg))
            })
            try await test.adoptProjectAsync(fixture, from: nil)
            test.selectProjectLevel(b); test.selectProjectLevel(c)
            check("연속 전환 시 마지막 층 메타데이터 즉시 선택", test.routingFloorID == c && test.currentRoutingFloor?.sourceName == "2.svg")
            await test.waitForLevelDrawing()
            check("연속 로딩의 이전 결과가 마지막 도면을 덮지 않음", test.document?.sourceName == "2.svg" && test.drawingLoadError == nil)
            test.levelDrawingCache.invalidate(a)
            test.selectProjectLevel(a)
            check("새 층 로딩 중 이전 도면의 색인·보조 개체 목록을 표시하지 않음", test.loadingLevelID == a && test.twinGroups.isEmpty && test.spatialIndex.isEmpty && test.objectIDsByAttributeKey.isEmpty)
            await test.waitForLevelDrawing()
            test.selectProjectLevel(c); await test.waitForLevelDrawing()
            test.enterRoutingScreen()
            test.handleRoutingClick(at: LocalPoint(100, 100), tolerance: 1, modifiers: .command)
            let node = test.routingSelectedNodeID!
            test.updateRoutingNode(node, field: "metadata") { $0.metadataJSON = "{\"test\":42}" }
            test.selectProjectLevel(a); test.selectProjectLevel(c)
            await test.waitForLevelDrawing()
            check("미저장 노드·메타데이터는 층 전환 후 보존", test.routing.node(node)?.metadataJSON == "{\"test\":42}" && test.buildingProject.levels.first { $0.id == c }?.nodes.count == 1)
            test.removeProjectLevel(c); test.undo()
            await test.waitForLevelDrawing()
            check("층 삭제·Undo 후 도면·노드·ID 복원", test.document?.sourceName == "2.svg" && test.routing.node(node)?.floorID == c)
            let replacement = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"500\" height=\"400\"><rect x=\"20\" y=\"20\" width=\"100\" height=\"100\"/></svg>"
            try test.setRoutingDrawing(c, data: Data(replacement.utf8), name: "replacement.svg")
            test.selectProjectLevel(a); test.selectProjectLevel(c)
            await test.waitForLevelDrawing()
            check("도면 교체는 이전 캐시 대신 새 좌표·크기 표시", test.document?.sourceName == "replacement.svg" && test.document?.objects.count == 1 && test.document?.canvasSize.width == 500 && test.routing.node(node) != nil)
            test.undo(); await test.waitForLevelDrawing()
            check("도면 교체 Undo는 이전 도면 복원", test.document?.sourceName == "2.svg")
            test.levelDrawingCache.reset(); test.beginLevelDrawingLoad(a)
            await Task.yield()
            test.resetProjectState()
            await Task.yield()
            check("프로젝트 교체 후 이전 비동기 도면이 적용되지 않음", test.document == nil && test.routingFloorID == nil && test.levelDrawingCache.count == 0)

            let cache = LevelDrawingCache(capacity: 2)
            let input = LevelDrawingInput(levelID: UUID(), svg: replacement, sourceName: "shared.svg")
            let first = Task { try await cache.load(input) }
            let second = Task { try await cache.load(input) }
            let values = try await (first.value, second.value)
            check("같은 도면의 동시 요청은 작업 한 번으로 공유", cache.preparationCount == 1 && values.0.document?.fingerprint == values.1.document?.fingerprint)
            for i in 0..<3 { _ = try await cache.load(LevelDrawingInput(levelID: UUID(), svg: replacement, sourceName: "\(i).svg")) }
            check("캐시 보관 개수 제한", cache.count == 2)

            let layers = environment()
            var imdfFile = fixture
            imdfFile.buildingProject!.levels[0].info.imdfCoordinates = IMDFCoordinateSpace(west: 129, north: 36, unitsPerLongitudeDegree: 90_000, unitsPerLatitudeDegree: 111_000, padding: 0)
            try await layers.adoptProjectAsync(imdfFile, from: nil)
            await layers.waitForLevelDrawing()
            let before = layers.projectContents
            try layers.setRoutingDrawing(a, data: Data(replacement.utf8), name: "reference.svg")
            await layers.waitForLevelDrawing()
            check("IMDF 참고 SVG 입력은 원본 도형·투영·주 도면 보존", layers.activeLevel?.referenceDrawing?.sourceName == "reference.svg" && layers.activeLevel?.info == before.levels[0].info && layers.activeLevel?.geoJSON == before.levels[0].geoJSON && layers.canvasReferences?.reference?.sourceName == "reference.svg")
            layers.updateDrawingLayer("reference", opacity: 0.25)
            layers.updateDrawingLayer("footprint", visible: false)
            let roundTrip = try ProjectFile.decoded(from: layers.makeProjectFile()!.encoded())
            let reopened = environment()
            try await reopened.adoptProjectAsync(roundTrip, from: nil)
            await reopened.waitForLevelDrawing()
            check("참고 SVG 원문·파일명·층별 불투명도·Footprint 표시 저장 복원", reopened.activeLevel?.referenceDrawing?.svg == replacement && reopened.activeLevel?.referenceDrawing?.presentation.opacity == 0.25 && !reopened.footprintPresentation.isVisible && !reopened.hasUnsavedChanges)
            reopened.requestReferenceDrawingDeletion()
            check("참고 도면 삭제 확인 전 데이터 유지", reopened.pendingDeletion != nil && reopened.activeLevel?.referenceDrawing != nil)
            reopened.cancelDeletion(); reopened.requestReferenceDrawingDeletion(); reopened.confirmDeletion(reopened.pendingDeletion!.id)
            check("확인 후 참고 도면만 삭제", reopened.activeLevel?.referenceDrawing == nil && reopened.document?.fingerprint == layers.document?.fingerprint)
            reopened.undo(); await reopened.waitForLevelDrawing()
            check("참고 도면 삭제 Undo", reopened.activeLevel?.referenceDrawing?.sourceName == "reference.svg")
            try await reopened.adoptProjectAsync(fixture, from: nil); await reopened.waitForLevelDrawing()
            reopened.updateDrawingLayer("svg", visible: false)
            check("숨긴 SVG 개체는 편집 선택 대상에서 제외", reopened.document != nil && reopened.selectableObjects(in: reopened.document!).isEmpty)
            reopened.updateDrawingLayer("svg", visible: true)
            check("SVG를 다시 표시하면 기존 선택 대상으로 복원", !reopened.selectableObjects(in: reopened.document!).isEmpty)
            let beforeBroken = reopened.makeProjectFile()!
            var broken = fixture; broken.buildingProject!.levels[1].info.svg = "<svg>broken</svg>"
            do { try await reopened.adoptProjectAsync(broken, from: nil); check("손상된 도면은 기존 작업 보존", false) }
            catch { check("손상된 도면은 기존 작업 보존", reopened.makeProjectFile()!.hasSameContents(as: beforeBroken)) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("async-open.imdfrnt")
            let badURL = directory.appendingPathComponent("broken.imdfrnt")
            try fixture.encoded().write(to: url); try Data("broken".utf8).write(to: badURL)
            let opened = environment()
            let result = await opened.openDocumentAsync(at: url)
            check("실제 비동기 파일 열기 경로는 메타데이터를 먼저 적용", result == .opened && opened.document == nil && opened.projectURL == url && !opened.hasUnsavedChanges)
            await opened.waitForLevelDrawing()
            opened.updateProjectLevel(a) { $0.name = "미저장 이름" }
            let unsaved = opened.makeProjectFile()!
            let otherURL = directory.appendingPathComponent("other.imdfrnt")
            try ProjectFile.empty().encoded().write(to: otherURL)
            let cancelled = await opened.openDocumentAsync(at: otherURL, confirmingChanges: { false })
            check("비동기 열기 취소는 미저장 작업 유지", cancelled == .cancelled && opened.makeProjectFile()!.hasSameContents(as: unsaved))
            var asked = false
            let failed = await opened.openDocumentAsync(at: badURL, confirmingChanges: { asked = true; return true })
            check("비동기 손상 파일은 교체 질문 없이 작업 보존", failed == .failed && !asked && opened.makeProjectFile()!.hasSameContents(as: unsaved))
            // #21: 면·점은 백그라운드에서 계산하고, 레이어를 열 때 다시 계산하지 않는다.
            let bg = environment()
            bg.derivedGeometryInline = false
            try await bg.adoptProjectAsync(file, from: nil)
            await bg.waitForLevelDrawing()
            if let doc = bg.document, !doc.objects.isEmpty {
                check("#21 층을 불러오면 면·점이 함께 준비된다", !bg.snapPoints.isEmpty && bg.totalPointCount > 0 && bg.derivedKey != nil)
                bg.selectPropertyType(.opening); bg.declareOpeningComplete()
                let layerStart = ContinuousClock.now
                bg.selectPropertyType(.unit)
                let layerTime = layerStart.duration(to: .now)
                print("[MEASURE] unit-layer-open=\(layerTime) points=\(bg.snapPoints.count)")
                check("#21 unit 레이어 생성은 면을 다시 계산하지 않는다", !bg.isComputingDerivedGeometry && layerTime < .milliseconds(200))
                let free = doc.objects.filter { !bg.auxiliary.isExcluded($0.id) }.map(\.id)
                // 실제 프로젝트는 이미 제외한 개체가 많다. 이미 제외된 개체를 다시 빼면 상태가 안 바뀌어
                // 재계산도 일어나지 않으므로, 아직 제외하지 않은 개체를 고른다.
                if let victim = free.first {
                    let excludeStart = ContinuousClock.now
                    bg.auxiliary.exclude([victim])
                    let excludeCall = excludeStart.duration(to: .now)
                    check("#21 보조 개체 제외는 메인 액터를 막지 않고 백그라운드로 다시 센다", bg.isComputingDerivedGeometry && excludeCall < .milliseconds(200))
                    var waited = 0
                    while bg.isComputingDerivedGeometry && waited < 3000 { try await Task.sleep(for: .milliseconds(10)); waited += 1 }
                    print("[MEASURE] derived-refresh-after-exclude=\(excludeStart.duration(to: .now)) excluded-points=\(bg.excludedPointCount)")
                    check("#21 백그라운드 결과가 지금 상태와 맞게 반영된다",
                          !bg.isComputingDerivedGeometry && bg.derivedKey == bg.currentDerivedKey && bg.excludedPointCount > 0)
                } else {
                    print("[SKIP] #21 보조 개체 제외 검사 — 제외하지 않은 개체가 없다")
                }

                if let level = bg.activeLevel, let base = bg.levelDrawingCache.cached(LevelDrawingInput(level)),
                   let extra = doc.objects.first(where: { !LevelDrawingInput(level).excluded.contains($0.id) }) {
                    var changed = LevelDrawingInput(level)
                    changed.excluded.insert(extra.id)
                    let reuseStart = ContinuousClock.now
                    let reused = try PreparedLevelDrawing.make(changed, reusing: base)
                    let reuseTime = reuseStart.duration(to: .now)
                    let full = try PreparedLevelDrawing.make(changed)
                    print("[MEASURE] reuse-parse=\(reuseTime) full=\(full.preparationSeconds)s")
                    check("#21 제외만 바뀌면 파싱을 다시 하지 않고 같은 결과를 낸다",
                          reused.document?.fingerprint == base.document?.fingerprint
                          && reused.derived.snapPoints.count == full.derived.snapPoints.count
                          && reused.derived.totalPointCount == full.derived.totalPointCount)
                }

                let before = try DerivedGeometry.make(document: doc, key: bg.currentDerivedKey)
                // 2026-10-20: opening 선은 열쇠에 없다. opening을 저장해도 점·면을 다시 계산하지 않는다(엔진 디버깅 7번).
                bg.selectPropertyType(.opening)
                if let p0 = bg.snapPoints.first?.point,
                   let p1 = bg.snapPoints.dropFirst().first(where: { $0.point.distance(to: p0) > 1 })?.point {
                    let keyBefore = bg.currentDerivedKey
                    let saveStart = ContinuousClock.now
                    bg.handlePointClick(at: p0, tolerance: 0.5, freePoint: false)
                    bg.handlePointClick(at: p1, tolerance: 0.5, freePoint: false)
                    print("[MEASURE] opening-save=\(saveStart.duration(to: .now))")
                    check("opening 저장은 점·면을 다시 계산하지 않는다",
                          bg.currentDerivedKey == keyBefore && !bg.isComputingDerivedGeometry)
                }
                var withExclude = bg.currentDerivedKey
                if let extra = doc.objects.first(where: { !withExclude.excluded.contains($0.id) }) {
                    withExclude.excluded.insert(extra.id)
                    let a = try DerivedGeometry.make(document: doc, key: withExclude, reusing: before)
                    let b = try DerivedGeometry.make(document: doc, key: withExclude)
                    check("보조 제외만 바뀌면 전체 점 수만 재사용하고 점은 새로 센다",
                          a.snapPoints.count == b.snapPoints.count && a.totalPointCount == b.totalPointCount)
                }
            }
            try await DrawingLoadingReviewSelfTest.run(environment: environment, check: check)
        } catch { check("도면 로딩 검증", false); print(error) }
        print("== Drawing Loading: \(total - failures)/\(total) PASS ==")
        exit(failures == 0 ? 0 : 1)
    }
}
