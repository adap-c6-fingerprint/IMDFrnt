import AppKit
import Foundation

/// Navigation data only. Never builds/parses IMDF geometry, SVG or an IMDF archive.
enum NavigationDataset {
    static let manifestFile = "navigation.json"

    struct Output: Sendable {
        var files: [String: Data]
        var ids: [UUID: IDAssigner]
        var nodeCount: Int
        var edgeCount: Int
        var linkCount: Int
    }

    static func build(project: BuildingProject) throws -> Output {
        try project.validate()
        let graph = project.routingGraph
        let routing = try RoutingExporter.encoded(graph)
        var ids: [UUID: IDAssigner] = [:]
        for level in project.levels {
            var assigner = level.editing.ids
            for node in level.nodes {
                for ref in node.featureLinks ?? [] {
                    if let feature = ref.authored(in: level) { _ = assigner.id(for: feature.id) }
                }
            }
            ids[level.id] = assigner
        }
        let records = try NavigationFeatureLinks.records(project: project, ids: ids)
        let identities = records.map { ($0["feature_type"]?.string ?? "") + ":" + ($0["feature_id"]?.string ?? "") }
        guard Set(identities).count == records.count else {
            throw RoutingExporter.Failure(messages: ["장소 UUID가 중복됩니다. 장소 하나에는 노드 하나만 연결할 수 있습니다."])
        }
        let links = try NavigationFeatureLinks.encoded(records: records, layoutVersion: graph.layoutVersion)
        let levels: [ProjectJSON] = graph.floors.map {
            .object(["id": .string($0.id.uuidString.lowercased()), "name": .string($0.name),
                     "ordinal": .number(Decimal($0.ordinal)), "short_name": $0.shortName.map(ProjectJSON.string) ?? .null])
        }
        let groups: [ProjectJSON] = (graph.edgeGroups ?? []).map {
            .object(["id": .string($0.id.uuidString.lowercased()), "name": .string($0.name)])
        }
        let manifest = try ProjectJSON.object([
            "schema_version": .number(1), "kind": .string("navigation-only"),
            "layout_version": .string(graph.layoutVersion), "levels": .array(levels), "edge_groups": .array(groups),
            "routing_file": .string(ClientDataset.routingFile), "routing_sha256": .string(ClientDataset.sha256(routing)),
            "feature_links_file": .string(NavigationFeatureLinks.fileName), "feature_links_sha256": .string(ClientDataset.sha256(links))
        ]).data()
        return Output(files: [manifestFile: manifest, ClientDataset.routingFile: routing, NavigationFeatureLinks.fileName: links],
                      ids: ids, nodeCount: graph.nodes.count, edgeCount: graph.edges.count, linkCount: records.count)
    }
}

@MainActor
extension AppEnvironment {
    func exportNavigationDataset() {
        guard !isProjectBusy else { return }
        let panel = NSSavePanel()
        panel.title = "노드/엣지 내보내기"
        panel.nameFieldStringValue = projectDisplayName + "-navigation"
        panel.canCreateDirectories = true
        panel.message = "노드·엣지·그룹·Unit/Fixture 연결 JSON을 폴더로 저장합니다. IMDF 도형은 내보내거나 검사하지 않습니다."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var replacing = false
        if FileManager.default.fileExists(atPath: url.path) {
            let alert = NSAlert()
            alert.messageText = "‘\(url.lastPathComponent)’ 폴더를 교체할까요?"
            alert.informativeText = "기존 폴더 안의 파일 전체가 새 길안내 데이터로 바뀝니다."
            alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "교체")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            replacing = true
        }
        let output: NavigationDataset.Output
        do { output = try NavigationDataset.build(project: projectContents) }
        catch let blocked as ClientDataset.Blocked { notify(blocked.messages.joined(separator: "\n"), isError: true); return }
        catch { notify("길안내 데이터 내보내기 실패: \(error.localizedDescription)", isError: true); return }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try ClientDataset.write(output.files, to: url, replacing: replacing)
            adoptExportedIDs(output.ids)
            notify("길안내 데이터 저장 완료 — 노드 \(output.nodeCount)개 · 엣지 \(output.edgeCount)개 · 장소 연결 \(output.linkCount)개")
        } catch { notify("저장 실패: \(error.localizedDescription)", isError: true) }
    }
}
