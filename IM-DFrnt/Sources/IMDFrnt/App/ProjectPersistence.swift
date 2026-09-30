import AppKit
import Foundation
import UniformTypeIdentifiers

/// 저장 루프 · 종료 처리 · 작업 공유(신기능 1항).
///
/// `AppEnvironment` 본체와 파일을 나눈 이유는 이 세 가지가 **하나의 이야기**이기 때문이다.
/// 30초마다 저장하고, 닫을 때 마저 저장하고, 그 저장 형식(`.imdfrnt`)을 그대로 남에게 넘긴다.
@MainActor
extension AppEnvironment {

    // MARK: 자동 저장 (신기능 1-1-1)

    /// 30초. 명세가 정한 값이라 여기 한 곳에만 쓴다.
    static let autosaveInterval: TimeInterval = 30

    /// 앱이 알아서 쥐고 있는 안전망 파일. 사용자가 저장 위치를 한 번도 안 정해도 여기 쌓인다.
    /// **이것이 "cmd+Q로 끄면 도면이 다 없어진다"의 답이다** — 명시적 저장을 안 한 사용자가
    /// 대다수인데, 저장 위치가 있어야만 저장한다면 안전망이 정작 필요한 사람에게 없다.
    static var autosaveURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IM-DFrnt", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("autosave." + ProjectFile.fileExtension)
    }

    /// 확장자를 되돌리기 전(`.imdfproj`)에 쌓인 자동 저장본.
    /// **이 자리를 안 봐주면 확장자를 바꾼 그 순간 사용자의 마지막 작업이 사라진다** —
    /// 파일은 멀쩡히 있는데 앱이 다른 이름만 찾으니 "저장했다더니 없어졌다"가 된다.
    static var interimAutosaveURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IM-DFrnt", isDirectory: true)
            .appendingPathComponent("autosave." + ProjectFile.interimFileExtension)
    }

    /// 자동 저장본이 원래 어느 파일에 속했는지. 복원한 뒤 `저장`이 엉뚱한 곳에 쓰지 않게 한다.
    private static let lastProjectPathKey = "IMDFrnt.lastProjectPath"

    func startAutosaveLoop() {
        guard autosaveTimer == nil else { return }
        guard !CommandLine.arguments.contains("--selftest") else { return }
        // 같은 이유로 점검 중에는 저장 루프도 돌리지 않는다 — 점검이 사용자 파일을 덮어쓰면 안 된다.
        let t = Timer.scheduledTimer(withTimeInterval: Self.autosaveInterval, repeats: true) { _ in
            Task { @MainActor in self.autosaveTick() }
        }
        t.tolerance = 5
        // 정확히 30.000초일 필요가 없다. 여유를 주면 시스템이 다른 타이머와 묶어 깨워 전력을 아낀다.
        RunLoop.main.add(t, forMode: .common)
        autosaveTimer = t
    }

    func stopAutosaveLoop() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }

    /// 루프 한 번. **화면에 아무것도 띄우지 않는다**(신기능 1-1-1: "저장 상황을 별도 표시하지 않음").
    /// 30초마다 배너가 뜨면 그것만으로 작업이 방해된다.
    func autosaveTick() {
        guard hasSomethingToPersist else { return }
        guard snapshot != lastSavedSnapshot else { return }
        // 바뀐 게 없으면 쓰지 않는다. 파일 시각만 계속 갱신되면
        // 사용자가 파일 목록에서 "언제 뭘 했는지"를 읽을 수 없다.
        persist(showingBanner: false)
    }

    /// 저장할 값이 있는가. `hasProjectContent`(태깅 결과가 있는가)보다 **넓다** —
    /// 도면만 열어 둔 상태도 잃으면 안 되기 때문이다. 도면을 다시 찾아 여는 것 자체가 작업이다.
    var hasSomethingToPersist: Bool { document != nil }

    /// 지금 상태를 파일로 굳힌다. 안전망(자동 저장본)에는 **항상** 쓰고,
    /// 사용자가 저장 위치를 정해 뒀으면 그쪽에도 같이 쓴다.
    ///
    /// 두 곳에 쓰는 이유: 안전망만 쓰면 사용자가 정한 파일이 낡고, 사용자 파일만 쓰면
    /// 위치를 안 정한 사람에게 안전망이 없다. 둘 다 쓰면 어느 쪽으로 열어도 최신이다.
    @discardableResult
    func persist(showingBanner: Bool) -> Bool {
        guard let file = makeProjectFile() else { return false }
        do {
            let data = try file.encoded()
            try data.write(to: Self.autosaveURL)
            if let url = projectURL { try data.write(to: url) }

            UserDefaults.standard.set(projectURL?.path, forKey: Self.lastProjectPathKey)
            lastSavedSnapshot = snapshot
            if showingBanner {
                notify(projectURL.map { "작업을 저장했습니다: \($0.lastPathComponent)" }
                       ?? "작업을 저장했습니다.")
            }
            return true
        } catch {
            // 자동 저장 실패는 조용히 넘기면 안 된다. 안전망이 없는 줄 모르고 계속 작업하게 된다.
            notify("저장 실패: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    func makeProjectFile() -> ProjectFile? {
        guard let doc = document, let svg = loadedSVGText else { return nil }
        var file = ProjectFile(sourceName: doc.sourceName, svg: svg,
                               features: features, ownership: ownership,
                               segmentation: segmentation, auxiliary: auxiliary,
                               anchors: anchors, serials: serials, ids: ids,
                               openingGate: openingGate, borrow: borrow)
        file.projectID = projectID
        file.assignment = assignment
        file.doorClosures = doorClosures
        file.drawingFingerprint = doc.fingerprint
        return file
    }

    // MARK: 파일 → 화면 (열기·복원이 함께 쓴다)

    /// `ProjectFile` 하나를 지금 화면 상태로 갈아 끼운다.
    /// **열기와 복원이 같은 코드를 타야 한다** — 둘이 갈리면 한쪽만 되살리는 항목이 생기고,
    /// 그 차이는 "어제 작업이 일부만 돌아왔다"는 형태로 나중에야 드러난다.
    func adopt(_ file: ProjectFile, from url: URL?) throws {
        guard let svgData = file.svg.data(using: .utf8) else {
            throw NSError(domain: "IMDFrnt", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "프로젝트에 담긴 도면을 읽지 못했습니다."])
        }
        let doc = try SVGParser.parse(data: svgData, sourceName: file.sourceName)

        document = doc
        loadedSVG = file.svg
        layers.bootstrap()
        // 레이어 목록은 저장하지 않으므로 기본 상태에서 다시 시작한다.
        features = file.features
        ownership = file.ownership
        segmentation = file.segmentation
        auxiliary = file.auxiliary
        anchors = file.anchors
        serials = file.serials
        ids = file.ids
        openingGate = file.openingGate
        borrow = file.borrow
        doorClosures = file.doorClosures

        projectID = file.projectID
        assignment = file.assignment
        // 배정본이면 여기서 담당 몫이 켜진다. 이후 선택 판정이 전부 이 값을 본다.

        selection = SelectionStore()
        mode = .idle
        expandedFeature = nil
        undoStack.clear()
        // 다른 세션의 실행취소 칸을 되살리면 지금 문서에 없는 상태로 덮인다.
        resetPositions()
        projectURL = url

        // 저장된 property type 레이어를 되살린다. 안 그러면 feature는 있는데
        // 그것을 담을 레이어가 없어 우측 사이드바가 비어 보인다.
        for type in Set(file.features.features.map(\.featureType)).sorted(by: {
            $0.rawValue < $1.rawValue
        }) {
            _ = layers.addPropertyTypeLayer(type)
        }

        lastSavedSnapshot = snapshot
        // 방금 연 상태는 곧 저장된 상태다. 이걸 안 채우면 30초 뒤 루프가
        // "바뀐 게 있다"고 오해해 아무 일도 안 했는데 파일 시각을 갱신한다.
    }

    // MARK: 복원 (신기능 1-1-3의 "종료해도 작업이 모두 저장돼요"가 성립하려면 필요하다)

    /// 앱을 켤 때 자동 저장본을 되살린다.
    /// **저장만 하고 복원하지 않으면 사용자 입장에서는 저장이 없는 것과 같다.**
    func restoreAutosaveIfAvailable() {
        guard document == nil else { return }
        guard !CommandLine.arguments.contains("--selftest") else { return }
        // 자체점검은 **사용자의 실제 작업을 건드리면 안 된다.** SwiftUI의 `onAppear`가
        // `applicationDidFinishLaunching`보다 먼저 도는 경우가 있어, 막지 않으면
        // 점검을 돌릴 때마다 진짜 자동 저장본을 읽어 들인다. 점검 결과가 그날 작업 내용에
        // 따라 달라지면 점검이 아니다.

        // 새 이름을 먼저 보고, 없으면 확장자를 되돌리기 전 이름을 본다.
        let fm = FileManager.default
        let url: URL
        if fm.fileExists(atPath: Self.autosaveURL.path) {
            url = Self.autosaveURL
        } else if fm.fileExists(atPath: Self.interimAutosaveURL.path) {
            url = Self.interimAutosaveURL
            // 다음 저장부터는 새 이름으로 쌓인다(`persist`가 `autosaveURL`에 쓴다).
        } else {
            return
        }

        do {
            let file = try ProjectFile.decoded(from: try Data(contentsOf: url))
            try adopt(file, from: nil)

            // 저장 위치를 정해 뒀던 작업이면 그 자리를 되찾아 준다.
            // 안 그러면 복원 직후의 `저장`이 "다른 이름으로 저장" 창을 띄운다.
            if let path = UserDefaults.standard.string(forKey: Self.lastProjectPathKey),
               FileManager.default.fileExists(atPath: path) {
                projectURL = URL(fileURLWithPath: path)
            }
            notify("지난 작업을 이어서 엽니다 — \(file.sourceName)")
        } catch {
            // 복원 실패로 앱이 안 뜨면 안 된다. 빈 화면으로 시작하되 이유는 알린다.
            notify("지난 작업을 불러오지 못했습니다: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: 종료 (신기능 1-1-2, 1-1-3)

    /// 종료 확인 팝업. 예/아니오만 있고, '저장 안 함'은 **일부러 두지 않았다** —
    /// 명세가 "종료해도 작업이 모두 저장돼요"라고 약속하므로 저장을 건너뛰는 길이 있으면 거짓말이 된다.
    /// 되돌리고 싶으면 cmd+z가 있고, 다른 결과를 남기고 싶으면 '다른 이름으로 저장'이 있다.
    func confirmTermination() -> Bool {
        if isTerminationConfirmed { return true }
        guard hasSomethingToPersist else { return true }
        // 열어 둔 도면이 없으면 물을 것이 없다. 빈 앱을 닫는 데 확인을 받으면 성가시기만 하다.

        let alert = NSAlert()
        alert.messageText = "IM-DFrnt를 종료하시겠어요?"
        alert.informativeText = "종료해도 작업이 모두 저장돼요."
        alert.addButton(withTitle: "예")
        alert.addButton(withTitle: "아니오")
        let answer = alert.runModal()
        guard answer == .alertFirstButtonReturn else { return false }

        isTerminationConfirmed = true
        persist(showingBanner: false)
        notify("IM-DFrnt: 작업이 모두 저장되었어요!")
        // 사라지는 알림으로 보여준다. 실제 종료는 `AppDelegate`가 잠깐 미뤄 이 배너를 읽을 시간을 준다.
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
