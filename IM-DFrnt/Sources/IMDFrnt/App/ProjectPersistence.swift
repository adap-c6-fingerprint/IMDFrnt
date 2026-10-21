import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension AppEnvironment {
    static let autosaveInterval: TimeInterval = 30
    static let lastProjectPathKey = "IMDFrnt.lastProjectPath"

    /// 프로젝트마다 `새 도면_YYMMDD_HHmm.imdfrnt` 파일 하나가 이 폴더에 생긴다.
    static var defaultAutosaveFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IM-DFrnt", isDirectory: true)
    }

    var autosaveFolder: URL {
        if let autosaveFolderOverride { return autosaveFolderOverride }
        if Self.isRunningSelfTests {
            return FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntSelfTestAutosave", isDirectory: true)
        }
        return Self.defaultAutosaveFolder
        // 검사가 사용자의 실제 자동 저장 폴더에 파일을 만들지 않게 한다.
    }

    /// 프로젝트별 파일로 바꾸기 전, 앱 전체가 함께 쓰던 복구본 자리.
    var legacyAutosaveURLs: [URL] {
        [ProjectFile.fileExtension, ProjectFile.interimFileExtension].map {
            autosaveFolder.appendingPathComponent("autosave." + $0)
        }
    }

    /// 같은 분에 프로젝트를 두 번 만들면 `_2`, `_3`을 붙여 기존 파일을 덮어쓰지 않는다.
    func nextAutosaveURL(at date: Date = Date()) -> URL {
        let base = Self.defaultProjectFileName(at: date)
        var candidate = autosaveFolder.appendingPathComponent(base + "." + ProjectFile.fileExtension)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = autosaveFolder.appendingPathComponent("\(base)_\(suffix).\(ProjectFile.fileExtension)")
            suffix += 1
        }
        return candidate
    }

    func startAutosaveLoop() {
        guard autosaveTimer == nil, !Self.isRunningSelfTests else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.autosaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autosaveTick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        autosaveTimer = timer
    }

    func stopAutosaveLoop() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }

    func autosaveTick() {
        guard !isProjectBusy, hasUnsavedChanges else { return }
        persist(showingBanner: false)
    }

    var hasSomethingToPersist: Bool { hasCreatedProject || document != nil || !routing.floors.isEmpty }

    /// 프로젝트의 단일 파일(`projectURL`)에 덮어쓴다. 아직 파일이 없으면 자동 저장 폴더에 새로 만든다.
    @discardableResult
    func persist(showingBanner: Bool) -> Bool {
        guard let file = makeProjectFile() else { return false }
        if isUnwrittenEmptyProject { return true }
        let url = projectURL ?? nextAutosaveURL()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.encoded().write(to: url, options: .atomic)
            // 쓰기가 성공한 뒤에만 파일 위치와 완료 상태를 갱신한다.
            projectURL = url
            projectDefaults.set(url.path, forKey: Self.lastProjectPathKey)
            lastRecoveryProject = file
            if showingBanner { notify("작업을 자동 저장했습니다: \(url.lastPathComponent)") }
            return true
        } catch {
            notify("자동 저장 실패: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    func makeProjectFile() -> ProjectFile? {
        guard hasSomethingToPersist, document == nil || loadedSVGText != nil else { return nil }
        var file = ProjectFile.empty()
        file.projectID = projectID
        file.assignment = assignment
        file.buildingProject = projectContents
        return file
    }

    /// 파싱이 성공한 뒤에만 현재 작업을 교체한다.
    func adopt(_ file: ProjectFile, from url: URL?) throws {
        try file.validateLegacyRouting()
        var project = file.commonProject()
        try project.validate()
        try project.refreshIMDFDisplays()
        // Parse every embedded drawing before resetting the previous project.
        let prepared = try project.levels.map { try PreparedLevelDrawing.make(LevelDrawingInput($0)) }
        resetProjectState(id: file.projectID)
        buildingProject = project
        for drawing in prepared { levelDrawingCache.insert(drawing) }
        try loadLevelEditor(file.assignment?.levelID ?? project.levels.first?.id)
        showRoutingScreen = project.imdfSourceName != nil
        assignment = file.assignment
        projectURL = url
        lastRecoveryProject = makeProjectFile()
    }

    /// 마지막으로 작업한 프로젝트 파일. 프로젝트 선택 창에서 '지난 작업'으로 표시한다.
    /// 예전 공용 복구본(`autosave.imdfrnt`)이 남아 있으면 새 이름 파일로 옮긴다.
    func lastWorkedProjectURL() throws -> URL? {
        let fm = FileManager.default
        if let legacy = legacyAutosaveURLs.first(where: { fm.fileExists(atPath: $0.path) }) {
            let migrated = nextAutosaveURL()
            try fm.moveItem(at: legacy, to: migrated)
            return migrated
            // 예전 구조에서는 이 복구본이 늘 가장 최신이었다. 지우지 않고 이름만 바꾼다.
        }
        guard let path = projectDefaults.string(forKey: Self.lastProjectPathKey),
              fm.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func confirmTermination() -> Bool {
        guard !isProjectBusy, NSApp.modalWindow == nil else { return false }
        guard autosaveBeforeLeaving(action: "앱 종료") else { return false }
        stopAutosaveLoop()
        return true
    }

    // MARK: 작업 공유 — 내보내기 (신기능 1-2-2)

    var canShareAssignment: Bool { document != nil && !selection.isEmpty && assignment == nil }
    /// 배정본을 다시 배정하지 않는다. 몫을 또 쪼개면 합칠 때 어느 조각이 어디 속하는지가 흐려진다.

    /// 지금 고른 개체를 한 사람 몫으로 잘라 `.imdfrnt`로 내보낸다.
    func shareSelectionAsAssignment() {
        guard let doc = document else { return }
        guard assignment == nil else {
            notify("받은 배정본은 다시 배정할 수 없습니다.", isError: true)
            return
        }
        guard !selection.isEmpty else {
            notify("먼저 넘길 개체를 고르세요.", isError: true)
            return
        }

        let who = askForAssignee()
        guard let assignee = who else { return }

        var file = makeProjectFile()
        guard file != nil else {
            notify("먼저 SVG 도면을 여세요.", isError: true)
            return
        }
        let ids = selection.selected
        file!.assignment = Assignment(id: UUID(), projectID: projectID,
                                      drawingFingerprint: doc.fingerprint,
                                      assignee: assignee,
                                      objectIDs: ids,
                                      bounds: Assignment.bounds(of: ids, in: doc),
                                      createdAt: Date())
        file!.assignment?.levelID = routingFloorID

        let panel = NSSavePanel()
        let base = (doc.sourceName as NSString).deletingPathExtension
        let tag = assignee.trimmingCharacters(in: .whitespaces)
        panel.nameFieldStringValue =
            "\(base)-\(tag.isEmpty ? "배정" : tag).\(ProjectFile.fileExtension)"
        panel.canCreateDirectories = true
        panel.title = "다른 사람에게 넘길 작업 몫 저장"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try file!.encoded().write(to: url)
            notify("개체 \(ids.count)개를 \(assignee) 몫으로 내보냈습니다: \(url.lastPathComponent)")
        } catch {
            notify("배정본 저장 실패: \(error.localizedDescription)", isError: true)
        }
    }

    private func askForAssignee() -> String? {
        let alert = NSAlert()
        alert.messageText = "누구에게 넘기나요?"
        alert.informativeText = "합칠 때 어느 몫이 들어왔는지 알려주는 이름입니다."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "예: 김도면"
        alert.accessoryView = field
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    // MARK: 작업 공유 — 합치기 (신기능 1-2-5)

    /// 나눠 준 몫들을 다시 하나로 모은다.
    ///
    /// **좌표를 맞추는 계산이 여기 없다는 점이 핵심이다.** 배정본은 도면을 잘라 간 것이 아니라
    /// 원본 도면 전체를 그대로 들고 갔고, 개체 id는 도면 좌표에서 결정적으로 뽑히므로(1-2-6)
    /// 양쪽의 같은 개체는 처음부터 같은 이름을 갖는다. 그래서 붙일 때 맞출 것이 없다.
    func mergeAssignments() {
        guard let doc = document else {
            notify("먼저 원본 작업을 여세요.", isError: true)
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ProjectFile.fileExtension) ?? .json,
                                     UTType(filenameExtension: ProjectFile.interimFileExtension) ?? .json]
        panel.allowsMultipleSelection = true
        panel.title = "합칠 배정본 선택"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        var report = MergeReport()
        perform("배정본 합치기") {
            for url in panel.urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                merge(url: url, into: doc, report: &report)
            }
        }
        mergeReportMessage = report.isEmpty ? nil : report.message
    }

    private func merge(url: URL, into doc: DrawingDocument, report: inout MergeReport) {
        let name = url.lastPathComponent
        do {
            let file = try ProjectFile.decoded(from: try Data(contentsOf: url))
            merge(file: file, named: name, into: doc, report: &report)
        } catch {
            report.rejectedFiles.append((name, error.localizedDescription))
        }
    }

    /// 파일 읽기와 분리한 병합 본체.
    /// **떼어낸 이유는 검증 때문이다** — 합치기는 잘못되면 남의 작업이 소리 없이 사라지거나
    /// 내 작업을 덮는 종류의 기능인데, 디스크를 거치면 `--selftest`가 확인할 방법이 없다.
    func merge(file: ProjectFile, named name: String,
               into doc: DrawingDocument, report: inout MergeReport) {
        guard let a = file.assignment else {
            report.rejectedFiles.append((name, "배정본이 아니라 일반 작업 파일입니다."))
            return
        }
        guard a.projectID == projectID else {
            report.rejectedFiles.append((name, "다른 작업에서 나온 파일입니다. 합치면 남의 태깅이 섞입니다."))
            return
        }
        guard a.drawingFingerprint == doc.fingerprint else {
            report.rejectedFiles.append((name, "도면이 달라졌습니다. 배정한 뒤 원본 도면을 바꿔 열면 개체가 서로 어긋납니다."))
            return
        }
        if let levelID = a.levelID, levelID != routingFloorID {
            report.rejectedFiles.append((name, "현재 선택된 층의 배정본이 아닙니다."))
            return
        }
        let file = file.legacyEditorView(levelID: a.levelID)

        var accepted = 0
        for f in file.features.features where !f.isInTrash {
            guard f.memberIDs.isSubset(of: a.objectIDs) else {
                report.outOfScopeFeatures.append(f.serialNumber)
                continue
                // 담당 몫 밖을 태깅한 것이다. 받아들이면 다른 사람 몫과 충돌한다.
            }
            guard f.memberIDs.isDisjoint(with: ownership.claimedObjectIDs) else {
                report.conflictingFeatures.append(f.serialNumber)
                continue
                // 이쪽에서 이미 주인이 정해진 개체다. **덮어쓰지 않는다** —
                // 어느 쪽이 맞는지는 사람이 판단할 일이지 합치기가 정할 일이 아니다.
            }

            if features.feature(f.id) != nil { continue }
            var incoming = f
            incoming.isInTrash = false
            serials.reserve(f.serialNumber)
            // 같은 번호가 두 번 발급되지 않게 예약한다. 안 하면 다음 저장에서 번호가 겹친다.
            features.insert(incoming)
            try? ownership.claim(incoming.memberIDs, for: incoming.id)
            if let issued = file.ids.peek(f.id) { ids.adopt(f.id, id: issued) }
            // **발급된 UUID를 그대로 물려받는다.** 여기서 새로 뽑으면 IMDF 스펙의
            // "distinct deliveries 사이에 같은 id를 유지" 요건이 담당자 몫에서만 깨진다.
            let borrowed = file.borrow.objects(borrowedBy: f.id).intersection(a.objectIDs)
            if !borrowed.isEmpty { borrow.borrow(borrowed, by: f.id) }
            accepted += 1
        }

        let exclusions = file.auxiliary.excluded.intersection(a.objectIDs).subtracting(auxiliary.excluded)
        auxiliary.exclude(exclusions)

        var segCount = 0
        for id in file.segmentation.segmentedObjectIDs where a.objectIDs.contains(id) {
            guard !segmentation.isSegmented(id), let obj = doc.object(id) else { continue }
            _ = segmentation.segmentize(id, geometry: obj.geometry,
                                        tolerance: segmentationTolerance)
            segCount += 1
            // 결과를 그대로 옮기지 않고 **같은 개체를 여기서 다시 선분화한다.**
            // 선분화는 원본 도형에서 결정적으로 나오므로 결과가 같고,
            // 남의 파일에서 온 좌표 배열을 그대로 믿는 것보다 안전하다.
        }

        report.acceptedFiles.append(name)
        report.acceptedFeatures += accepted
        report.acceptedExclusions += exclusions.count
        report.acceptedSegmentations += segCount

        // 합쳐진 feature를 담을 레이어가 없으면 우측 사이드바가 비어 보인다.
        for type in Set(features.features.map(\.featureType)) where layers.layer(for: type) == nil {
            _ = layers.addPropertyTypeLayer(type)
        }
    }

    // MARK: 배정본을 연 쪽의 제약 (신기능 1-2-4)

    /// 이 개체를 지금 고를 수 있는가. 배정본에서는 **담당 몫만** 고를 수 있다.
    /// 도면 전체가 보이는 것은 맥락 때문이고, 고를 수 있는 것과는 다른 문제다.
    func isWithinAssignment(_ id: VectorObjectID) -> Bool {
        guard let a = assignment else { return true }
        return a.objectIDs.contains(id)
    }
}
