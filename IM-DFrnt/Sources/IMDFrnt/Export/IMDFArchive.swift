import AppKit
import Foundation
import UniformTypeIdentifiers

/// 층마다 나뉜 작업을 **type별 파일 하나**로 합쳐 IMDF 아카이브(ZIP)로 만든다(#38).
///
/// IMDF는 층마다 파일을 나누지 않는다. `unit.geojson` 하나에 모든 층의 unit이 들어가고,
/// 어느 층인지는 각 feature의 `level_id`가 말한다. 그래서 층별 `.geojson` 내보내기와 별도로 모아 담는 단계가 필요하다.
///
/// 규격(OGC 20-094 Archives·Manifest 절, 위키 src18)과 C5 예제를 따른다.
/// - ZIP 최상위에 `manifest.json`과 `{type}.geojson`을 둔다. 하위 폴더를 만들지 않는다(C5 예제와 같다).
/// - `manifest.json`·`address.geojson`·`venue.geojson`은 필수 파일이라 feature가 없어도 빈 FeatureCollection으로 넣는다.
/// - 각 층의 level feature는 **그 층의 UUID를 id로 쓴다.** 같은 층의 다른 feature의 `level_id`가 비어 있으면 이 값으로 채운다.
enum IMDFArchive {

    /// 아카이브에 들어갈 수 있는 feature 파일. manifest는 feature가 아니라 `manifest.json`이다.
    static let featureTypes: [IMDFFeatureType] = IMDFFeatureType.allCases.filter { $0 != .manifest }
    static let requiredFiles = ["address.geojson", "venue.geojson"]

    struct Output: Sendable {
        /// 파일 이름 → 내용(UTF-8 JSON).
        var files: [String: Data]
        /// 층별로 새로 발급한 id까지 담은 대장. 다음 내보내기에서 같은 id를 쓰도록 프로젝트에 되돌려 넣는다.
        var ids: [UUID: IDAssigner]
        var featureCounts: [String: Int]
        var warnings: [String]
    }

    struct Blocked: Error, Sendable { let messages: [String] }

    // MARK: 조립

    /// `projectData`는 지금 층까지 반영한 프로젝트 파일(`ProjectFile.encoded()`)이다.
    /// 백그라운드에서 돌리기 위해 값 대신 데이터로 받는다.
    static func build(projectData: Data, documents: [UUID: DrawingDocument],
                      now: Date = Date(), reporter: LongTaskReporter? = nil) throws -> Output {
        let file = try ProjectFile.decoded(from: projectData)
        let project = file.commonProject()
        let levels = project.levels.sorted { $0.info.ordinal < $1.info.ordinal }
        let imported = project.imdfFiles()
        var blockers: [String] = []
        if let shared = project.sharedFootprint, shared.geographicFeatures().count != shared.features.filter({ !$0.isInTrash }).count {
            blockers.append("전역 Footprint의 GPS Anchor를 먼저 설정하세요. 서로 일직선이 아닌 대응점 최소 3쌍이 필요합니다.")
        }
        var warnings: [String] = []

        // 1. 층별 준비 — 도면(구성원 개체를 쓰는 예전 feature만 필요), 좌표 변환, 살아 있는 feature.
        struct Prepared {
            var level: ProjectLevel
            var features: [FeatureGroup]
            var document: DrawingDocument
            var georeferencer: Georeferencer
            var ids: IDAssigner
        }
        var prepared: [Prepared] = []
        for (n, level) in levels.enumerated() {
            reporter?.report(0.6 * Double(n) / Double(max(1, levels.count)), "\(level.info.name) 확인 중")
            let live = level.editing.features.features.filter { !$0.isInTrash && $0.featureType != .manifest }
            let needsDrawing = live.contains { !$0.memberIDs.isEmpty || !level.editing.borrow.objects(borrowedBy: $0.id).isEmpty }
            let document: DrawingDocument
            if let cached = documents[level.id] {
                document = cached
            } else if needsDrawing, !level.info.svg.isEmpty {
                document = try SVGParser.parse(data: Data(level.info.svg.utf8), sourceName: level.info.sourceName)
            } else {
                document = DrawingDocument(objects: [], canvasSize: .zero, sourceName: level.info.sourceName)
                // 점으로 그린 feature는 좌표를 스스로 갖고 있어 도면을 읽지 않아도 된다.
            }
            prepared.append(Prepared(level: level, features: live, document: document,
                                     georeferencer: Georeferencer(pairs: level.info.footprintGeoAnchors ?? level.info.anchors.pairs), ids: level.editing.ids))
        }

        // 2. 막는 조건 — 층 이름을 붙여 어느 층을 고쳐야 하는지 알린다.
        for p in prepared where !p.features.isEmpty {
            let name = p.level.info.name
            let validator = ExportValidator(document: p.document, features: p.features, anchors: p.level.info.anchors,
                                            georeferencer: p.georeferencer, segmentation: p.level.editing.segmentation,
                                            borrow: p.level.editing.borrow)
            var seen = Set<String>()
            for type in Set(p.features.map(\.featureType)).sorted(by: { $0.rawValue < $1.rawValue }) {
                for blocker in validator.validate(type: type) where blocker != .noFeatures {
                    let message = "\(name): \(blocker.message)"
                    if seen.insert(message).inserted { blockers.append(message) }
                }
            }
            let levelFeatures = p.features.filter { $0.featureType == .level }
            let importedLevels = p.level.geoJSON["level.geojson"]?.count ?? 0
            if levelFeatures.count > 1 {
                blockers.append("\(name): level 다각형이 \(levelFeatures.count)개입니다. 층 하나에 level은 하나여야 합니다.")
            } else if levelFeatures.isEmpty && importedLevels == 0 {
                blockers.append("\(name): level 다각형이 없습니다. level 레이어에서 층의 외곽을 그려야 다른 개체가 이 층을 가리킬 수 있습니다.")
            }
        }
        for p in prepared {
            let metadata = p.level.editing.features.features.filter { !$0.isInTrash && $0.featureType.isMetadataOnly }
            for f in metadata {
                for (key, problem) in PropertyRules.problems(in: f) {
                    let message = "\(p.level.info.name): \(f.serialNumber) \(key) — \(problem.message)"
                    if problem.severity == .violation { blockers.append(message) } else { warnings.append(message) }
                }
            }
        }
        // 정보 type 칸 점검(2026-10-20). Apple 검증의 Violation은 받아 주지 않으니 내보내기를 막고, Warning은 알리기만 한다.
        guard blockers.isEmpty else { throw Blocked(messages: blockers) }

        // 3. id 먼저 발급 — 건물·주소 id를 알아야 building_ids·address_id를 채운다.
        //    level feature의 id는 그 층의 UUID다(가져온 IMDF의 층 id와도 같다).
        func featureID(_ f: FeatureGroup, _ i: Int) -> UUID {
            f.featureType == .level ? prepared[i].level.id : prepared[i].ids.id(for: f.id)
        }
        var globalSerials: [String: [UUID]] = [:]
        var levelSerials: [[String: UUID]] = Array(repeating: [:], count: prepared.count)
        var buildingIDs: [UUID] = [], addressIDs: [UUID] = []
        for i in prepared.indices {
            for f in prepared[i].features {
                let id = featureID(f, i)
                globalSerials[f.serialNumber, default: []].append(id)
                levelSerials[i][f.serialNumber] = id
                if f.featureType == .building { buildingIDs.append(id) }
                if f.featureType == .address { addressIDs.append(id) }
            }
        }
        for feature in imported["building.geojson"]?["features"]?.array ?? [] { if let id = feature["id"]?.uuid { buildingIDs.append(id) } }
        for feature in imported["address.geojson"]?["features"]?.array ?? [] { if let id = feature["id"]?.uuid { addressIDs.append(id) } }

        // 4. 직렬화 — type별로 모든 층의 feature를 한 목록에 모은다.
        var collections: [String: [Any]] = [:]
        for name in featureTypes.map({ $0.rawValue + ".geojson" }) {
            if let features = imported[name]?["features"]?.array, !features.isEmpty {
                collections[name] = features.map(\.anyValue)
                // 가져온 IMDF의 feature는 id·속성을 바꾸지 않고 그대로 싣는다.
            }
        }
        for i in prepared.indices {
            reporter?.report(0.6 + 0.35 * Double(i) / Double(max(1, prepared.count)), "\(prepared[i].level.info.name) 개체 모으는 중")
            let p = prepared[i]
            var serialToUUID = globalSerials.compactMapValues { $0.count == 1 ? $0[0] : nil }
            serialToUUID.merge(levelSerials[i]) { _, sameLevel in sameLevel }
            // 일련번호는 층마다 따로 매겨져 'unit-001'이 층마다 있다. 같은 층의 것을 먼저 찾고,
            // 다른 층에서 하나뿐인 것(건물·주소처럼 한 번만 그리는 것)은 그대로 이어 준다.
            let exporter = GeoJSONExporter(document: p.document, segmentation: p.level.editing.segmentation,
                                           georeferencer: p.georeferencer, borrow: p.level.editing.borrow,
                                           levelID: p.level.id)
            var ids = p.ids
            for f in p.features {
                var feature = exporter.serialize(f, ids: &ids, serialToUUID: serialToUUID)
                var props = feature["properties"] as? [String: Any] ?? [:]
                let levelID = p.level.id.uuidString.lowercased()
                if f.featureType == .level {
                    feature["id"] = levelID
                    if props["ordinal"] is NSNull || props["ordinal"] == nil { props["ordinal"] = p.level.info.ordinal }
                    if props["name"] is NSNull || props["name"] == nil { props["name"] = ["ko": p.level.info.name] }
                    if props["short_name"] is NSNull, let short = p.level.info.shortName, !short.isEmpty {
                        props["short_name"] = ["ko": short]
                    }
                    // 층 이름·순서는 건물·층 관리에서 이미 정했다. 비어 있으면 그 값을 쓴다.
                }
                if props["level_id"] is NSNull { props["level_id"] = levelID }
                if props["building_ids"] is NSNull || (props["building_ids"] as? [Any])?.isEmpty == true,
                   buildingIDs.count == 1, f.featureType != .building {
                    props["building_ids"] = [buildingIDs[0].uuidString.lowercased()]
                }
                if props["address_id"] is NSNull, addressIDs.count == 1,
                   [.venue, .building, .level].contains(f.featureType) {
                    props["address_id"] = addressIDs[0].uuidString.lowercased()
                }
                // 건물·주소가 하나뿐이면 그것을 가리킨다(C5 예제의 level·building·venue가 이렇게 되어 있다).
                feature["properties"] = props
                collections[f.featureType.rawValue + ".geojson", default: []].append(feature)
            }
            prepared[i].ids = ids
        }

        // 5. 파일로.
        var files: [String: Data] = [:]
        var counts: [String: Int] = [:]
        for name in Set(collections.keys).union(requiredFiles) {
            var header = imported[name]?.anyValue as? [String: Any] ?? [:]
            header["type"] = "FeatureCollection"
            header["features"] = collections[name] ?? []
            files[name] = try encode(header)
            counts[name] = collections[name]?.count ?? 0
        }
        for name in requiredFiles where counts[name] == 0 {
            warnings.append("\(name)에 feature가 없어 빈 파일로 넣었습니다(필수 파일).")
        }
        let manifestFeature = prepared.lazy.flatMap { p in p.level.editing.features.features }
            .first { $0.featureType == .manifest && !$0.isInTrash }
        files["manifest.json"] = try encode(manifest(imported: imported["manifest.json"], feature: manifestFeature, now: now))
        for (name, value) in imported where files[name] == nil && !name.hasSuffix(".geojson") && name != "manifest.json" {
            files[name] = try encode(value.anyValue)
            // 가져온 아카이브에 있던 다른 파일(LICENSE 등)도 버리지 않는다.
        }
        reporter?.report(1, "완료")
        return Output(files: files, ids: Dictionary(uniqueKeysWithValues: prepared.map { ($0.level.id, $0.ids) }),
                      featureCounts: counts, warnings: warnings)
    }

    /// `version`은 1.0.0만 허용되고, `created`는 패키징 시각으로 매번 새로 쓴다(SHOULD).
    static func manifest(imported: ProjectJSON?, feature: FeatureGroup?, now: Date) -> [String: Any] {
        var m = imported?.anyValue as? [String: Any] ?? [:]
        if let feature {
            for key in ["generated_by", "language"] {
                if case .string(let s) = feature.value(key), !s.isEmpty { m[key] = s }
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // 스펙의 DATE-TIME은 yyyy-MM-ddTHH:mm:ss±hh:mm(또는 Z)이다. 소수 초는 형식에 없다.
        m["version"] = "1.0.0"
        m["created"] = formatter.string(from: now)
        if (m["generated_by"] as? String ?? "").isEmpty { m["generated_by"] = "IM-DFrnt" }
        if (m["language"] as? String ?? "").isEmpty { m["language"] = "ko-KR" }
        return m
    }

    private static func encode(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: ZIP

    /// 파일들을 ZIP으로 묶는다. 불러오기가 `/usr/bin/unzip`을 쓰는 것과 짝을 맞춰 `/usr/bin/zip`을 쓴다.
    /// `-j`로 경로를 떼어 모든 파일을 ZIP 최상위에 둔다.
    static func writeZip(_ files: [String: Data], to destination: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("IMDFrntArchive-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let names = files.keys.sorted()
        for name in names { try files[name]!.write(to: staging.appendingPathComponent(name)) }
        let output = staging.appendingPathComponent("archive.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-X", "-j", "-q", output.path] + names.map { staging.appendingPathComponent($0).path }
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Blocked(messages: ["ZIP을 만들지 못했습니다. \(message)"])
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: output, to: destination)
    }
}

extension ProjectJSON {
    /// JSONSerialization에 넘길 값.
    var anyValue: Any {
        switch self {
        case .object(let v): return v.mapValues(\.anyValue)
        case .array(let v): return v.map(\.anyValue)
        case .string(let v): return v
        case .number(let v): return NSDecimalNumber(decimal: v)
        case .bool(let v): return v
        case .null: return NSNull()
        }
    }
}

@MainActor
extension AppEnvironment {

    /// 모든 층을 합쳐 IMDF 아카이브로 내보낸다. 층 도면을 읽어야 할 수 있어 백그라운드에서 진행률과 함께 만든다.
    func exportIMDFArchive() {
        guard !isProjectBusy else { return }
        guard !buildingProject.levels.isEmpty else {
            notify("층이 없습니다. 건물·층 관리에서 층을 만든 뒤 내보내세요.", isError: true)
            return
        }
        guard var file = makeProjectFile() else { return }
        file.buildingProject = projectContents
        let projectData: Data
        do { projectData = try file.encoded() } catch {
            notify("프로젝트를 정리하지 못했습니다: \(error.localizedDescription)", isError: true)
            return
        }
        var documents: [UUID: DrawingDocument] = [:]
        for level in projectContents.levels {
            if level.id == routingFloorID, let document { documents[level.id] = document }
            else if let cached = levelDrawingCache.cached(LevelDrawingInput(level))?.document { documents[level.id] = cached }
        }
        let drawings = documents
        isProjectActionInProgress = true
        let task = beginLongTask("IMDF 아카이브 만드는 중", detail: "층 확인 중")
        let reporter = longTaskReporter(task)
        Task {
            defer { isProjectActionInProgress = false; endLongTask(task) }
            let output: IMDFArchive.Output
            do {
                output = try await Task.detached(priority: .userInitiated) {
                    try IMDFArchive.build(projectData: projectData, documents: drawings, reporter: reporter)
                }.value
            } catch let blocked as IMDFArchive.Blocked {
                endLongTask(task)
                archiveExportBlockers = blocked.messages
                return
            } catch {
                notify("IMDF 아카이브를 만들지 못했습니다: \(error.localizedDescription)", isError: true)
                return
            }
            endLongTask(task)
            adoptExportedIDs(output.ids)
            // 새로 발급한 id를 프로젝트에 남긴다. 다음 내보내기에서 같은 feature가 같은 id를 갖는다(IMDF 요건).

            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(projectDisplayName).zip"
            panel.allowedContentTypes = [.zip]
            panel.canCreateDirectories = true
            panel.title = "IMDF 아카이브 저장"
            panel.message = "IMDF 규격은 ZIP(.zip)으로 전달하도록 정합니다."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try IMDFArchive.writeZip(output.files, to: url)
                let total = output.featureCounts.values.reduce(0, +)
                let summary = "\(url.lastPathComponent) 저장 완료 — feature \(total)개, 파일 \(output.files.count)개"
                notify(output.warnings.isEmpty ? summary : summary + " · " + output.warnings.joined(separator: " "),
                       isError: !output.warnings.isEmpty)
            } catch let blocked as IMDFArchive.Blocked {
                notify(blocked.messages.joined(separator: " "), isError: true)
            } catch {
                notify("저장 실패: \(error.localizedDescription)", isError: true)
            }
        }
    }

    /// 층별 id 대장을 되돌려 넣는다. 지금 층은 편집 중인 값에도 반영한다.
    func adoptExportedIDs(_ assigners: [UUID: IDAssigner]) {
        for i in buildingProject.levels.indices {
            if let assigner = assigners[buildingProject.levels[i].id] { buildingProject.levels[i].editing.ids = assigner }
        }
        if let id = routingFloorID, let assigner = assigners[id] { ids = assigner }
    }
}
