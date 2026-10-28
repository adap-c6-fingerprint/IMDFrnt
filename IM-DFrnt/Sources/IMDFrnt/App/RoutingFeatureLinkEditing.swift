import SwiftUI

struct RoutingFeatureReplacement {
    var projectID: UUID
    var drawingRequestID: UUID
    var levelID: UUID
    var reference: RoutingFeatureReference
    var previousNodeID: UUID
    var nodeID: UUID
}

@MainActor
extension AppEnvironment {
    func clearRoutingFeatureSelection() {
        routingSelectedFeature = nil; routingFeatureCandidates = []; routingFeatureReplacement = nil
    }

    func handleRoutingFeatureClick(at point: LocalPoint, tolerance: Double) {
        guard let doc = routingDocument else { return }
        if let node = nearestRoutingNode(to: point, tolerance: tolerance) {
            selectRoutingNode(node.id); return
        }
        let candidates = routingMapDrawingCache.value(env: self, document: doc)?.features(at: point, settings: currentRoutingMapLayerSettings) ?? []
        routingFeatureCandidates = candidates.count > 1 ? candidates : []
        if candidates.count == 1 { chooseRoutingFeature(candidates[0]) }
        else if candidates.isEmpty { routingSelectedFeature = nil }
    }

    func chooseRoutingFeature(_ ref: RoutingFeatureReference) {
        routingFeatureCandidates = []; routingSelectedFeature = ref
        if let node = selectedRoutingNode { linkRoutingFeature(ref, to: node.id) }
    }

    /// 1 장소:1 노드, 1 노드:N 장소. 교체는 확인 후 한 번의 Undo로 처리한다.
    func linkRoutingFeature(_ ref: RoutingFeatureReference, to nodeID: UUID, replacing: Bool = false) {
        let project = projectContents
        guard !isImportingIMDF, loadingLevelID == nil,
              let level = project.levels.first(where: { $0.id == routingFloorID }),
              let node = level.nodes.first(where: { $0.id == nodeID }),
              ref.isAvailable(in: project, levelID: level.id) else {
            notify("현재 층의 살아 있는 장소와 노드를 선택하세요.", isError: true); return
        }
        let owner = RoutingFeatureLinks.owner(of: ref, on: level.id, in: project)
        if owner?.id == node.id { return }
        if let owner, !replacing {
            routingFeatureReplacement = RoutingFeatureReplacement(projectID: projectID, drawingRequestID: levelDrawingRequest, levelID: level.id,
                reference: ref, previousNodeID: owner.id, nodeID: nodeID)
            return
        }
        let identity = ref.identity(in: level)
        perform("장소와 노드 연결") {
            var graph = routing
            for i in graph.nodes.indices {
                if let floor = project.levels.first(where: { $0.id == graph.nodes[i].floorID }) {
                    let remaining = (graph.nodes[i].featureLinks ?? []).filter { $0.identity(in: floor) != identity }
                    graph.nodes[i].featureLinks = remaining.isEmpty ? nil : remaining
                }
                if graph.nodes[i].id == nodeID { graph.nodes[i].featureLinks = (graph.nodes[i].featureLinks ?? []) + [ref] }
            }
            routing = graph
        }
        notify("\(ref.kind.title)을 \(node.label)에 연결했습니다.")
    }

    func confirmRoutingFeatureReplacement(_ captured: RoutingFeatureReplacement? = nil) {
        guard let request = captured ?? routingFeatureReplacement else { return }
        routingFeatureReplacement = nil
        guard showRoutingScreen, routingTool == .featureLinks,
              request.projectID == projectID, request.drawingRequestID == levelDrawingRequest, request.levelID == routingFloorID,
              RoutingFeatureLinks.owner(of: request.reference, on: request.levelID, in: projectContents)?.id == request.previousNodeID else {
            notify("연결 상태가 바뀌었습니다. 장소를 다시 선택하세요.", isError: true); return
        }
        linkRoutingFeature(request.reference, to: request.nodeID, replacing: true)
    }

    func unlinkRoutingFeature(_ ref: RoutingFeatureReference, from nodeID: UUID) {
        guard let node = routing.node(nodeID), node.featureLinks?.contains(ref) == true else { return }
        perform("장소와 노드 연결 해제") {
            var graph = routing
            guard let index = graph.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            let remaining = (graph.nodes[index].featureLinks ?? []).filter { $0 != ref }
            graph.nodes[index].featureLinks = remaining.isEmpty ? nil : remaining
            routing = graph
        }
    }
}

struct RoutingFeatureLinksPanel: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let project = env.projectContents
        VStack(alignment: .leading, spacing: 8) {
            Text("노드 ↔ Unit/Fixture").font(.headline)
            Button("노드와 장소 연결하기") { env.setRoutingTool(.featureLinks) }
            if env.routingTool == .featureLinks {
                Text("노드를 클릭한 뒤 면 안쪽을 클릭하세요. 장소 하나에는 노드 하나만 연결됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !env.routingFeatureCandidates.isEmpty, let levelID = env.routingFloorID {
                Text("겹친 장소 중 선택").font(.caption.bold())
                ForEach(env.routingFeatureCandidates) { ref in
                    Button(ref.label(in: project, levelID: levelID)) { env.chooseRoutingFeature(ref) }.font(.caption)
                }
            }
            if let ref = env.routingSelectedFeature, let levelID = env.routingFloorID {
                Text(ref.label(in: project, levelID: levelID)).font(.caption.bold())
                if let node = RoutingFeatureLinks.owner(of: ref, on: levelID, in: project) {
                    Text("연결 노드: \(node.label) · \(node.shortID)").font(.caption)
                    Button("연결 노드 선택") {
                        if env.routingFloorID != node.floorID { env.selectRoutingFloor(node.floorID) }
                        env.selectRoutingNode(node.id)
                    }
                } else { Text("연결된 노드 없음").font(.caption).foregroundStyle(.secondary) }
            }
            if let node = env.selectedRoutingNode {
                Text("\(node.label)의 장소 \(node.featureLinks?.count ?? 0)개").font(.caption.bold())
                ForEach(node.featureLinks ?? []) { ref in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(ref.label(in: project, levelID: node.floorID)).font(.caption)
                            if !ref.isAvailable(in: project, levelID: node.floorID) {
                                Text("도형이 삭제/휴지통 상태입니다. 연결을 해제하세요.").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button { env.unlinkRoutingFeature(ref, from: node.id) } label: { Image(systemName: "link.badge.minus") }
                            .help("장소 연결 해제 (도형·노드는 유지)")
                    }
                }
            }
        }
    }
}
