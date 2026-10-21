import CoreGraphics
import Foundation
import SwiftUI

/// 지도 정렬 화면의 상태와 명령(신기능 11항, #31).
///
/// 화면(`UI/MapAlign/`)은 그리기와 손 동작만 맡고, 정렬값을 바꾸는 일은 전부 여기를 지난다 —
/// 그래야 실행취소·저장·자체점검이 화면 없이도 같은 규칙을 본다.
@MainActor
extension AppEnvironment {

    // MARK: 화면 열고 닫기

    func enterMapAlignScreen() {
        selection.clear()
        cancelPointDraft()
        showMapAlignScreen = true
        prepareMapAlignDrawings()
    }

    func exitMapAlignScreen() {
        showMapAlignScreen = false
        mapAlignPrepareTask?.cancel(); mapAlignPrepareTask = nil
    }

    // MARK: 층

    /// 도면이 있는 층, 층 번호 순.
    var mapAlignLevels: [ProjectLevel] {
        buildingProject.levels.filter { !$0.info.svg.isEmpty }.sorted { $0.info.ordinal < $1.info.ordinal }
    }

    func mapAlignment(of levelID: UUID) -> MapAlignment? {
        buildingProject.levels.first { $0.id == levelID }?.info.mapAlignment
    }

    /// 지도 위에 올라간 층을 그리는 순서(아래 → 위).
    var mapAlignStack: [ProjectLevel] {
        mapAlignLevels.filter { $0.info.mapAlignment != nil }
            .sorted { ($0.info.mapAlignment?.stackOrder ?? 0, $0.info.ordinal) < ($1.info.mapAlignment?.stackOrder ?? 0, $1.info.ordinal) }
    }

    /// 정렬을 마친 층 수 / 도면이 있는 층 수.
    var mapAlignProgress: (done: Int, total: Int) {
        let levels = mapAlignLevels
        return (levels.filter { $0.info.mapAlignment?.isConfirmed == true }.count, levels.count)
    }

    /// 정렬값을 바꾼다. **실행취소 한 칸**이다. 드래그 중에는 화면이 미리보기만 그리고 놓을 때 한 번 부른다 —
    /// 프레임마다 부르면 스냅샷 비교가 도면 원문 전체를 매번 훑어 끄는 동안 버벅인다.
    func commitMapAlignment(_ levelID: UUID, _ next: MapAlignment, name: String = "지도 정렬") {
        guard let i = buildingProject.levels.firstIndex(where: { $0.id == levelID }),
              buildingProject.levels[i].info.mapAlignment != next else { return }
        perform(name) {
            buildingProject.levels[i].info.mapAlignment = next
            resyncAlignmentAnchors(levelIndex: i)
        }
    }

    func updateMapAlignment(_ levelID: UUID, name: String, _ change: (inout MapAlignment) -> Void) {
        guard var a = mapAlignment(of: levelID) else { return }
        change(&a)
        commitMapAlignment(levelID, a, name: name)
    }

    /// 정렬로 만든 Anchor 쌍의 위경도를 지금 정렬에 맞춘다. 손으로 짝지은 쌍은 건드리지 않는다.
    private func resyncAlignmentAnchors(levelIndex i: Int) {
        guard let a = buildingProject.levels[i].info.mapAlignment else { return }
        if buildingProject.levels[i].id == routingFloorID {
            for k in anchors.pairs.indices where anchors.pairs[k].fromAlignment == true {
                anchors.pairs[k].geo = a.geoPoint(for: anchors.pairs[k].local)
            }
        } else {
            for k in buildingProject.levels[i].info.anchors.pairs.indices
            where buildingProject.levels[i].info.anchors.pairs[k].fromAlignment == true {
                let local = buildingProject.levels[i].info.anchors.pairs[k].local
                buildingProject.levels[i].info.anchors.pairs[k].geo = a.geoPoint(for: local)
            }
        }
    }

    /// 아직 지도에 없는 층을 올린다. **2층부터는 바로 아래 정렬된 층의 자리에서 시작한다** —
    /// 위층은 지도가 아니라 이미 맞춘 아래층에 맞추는 것이라(11항 2번), 같은 자리에서 시작하면 조금만 옮기면 된다.
    @discardableResult
    func placeOnMapIfNeeded(_ levelID: UUID, canvasSize: CGSize, mapCenter: GeoPoint,
                            visibleWidthMeters: Double) -> Bool {
        guard let level = buildingProject.levels.first(where: { $0.id == levelID }),
              level.info.mapAlignment == nil, canvasSize.width > 0, canvasSize.height > 0 else { return false }
        let below = mapAlignLevels.filter { $0.info.ordinal < level.info.ordinal && $0.info.mapAlignment != nil }
            .max { $0.info.ordinal < $1.info.ordinal }?.info.mapAlignment
        var a = MapAlignment.initial(center: mapCenter, visibleWidthMeters: visibleWidthMeters, canvasSize: canvasSize)
        if let below {
            a.center = below.center
            a.metersPerUnit = below.metersPerUnit
            a.rotationDegrees = below.rotationDegrees
        }
        a.stackOrder = (mapAlignStack.compactMap { $0.info.mapAlignment?.stackOrder }.max() ?? -1) + 1
        // 새로 올린 층은 맨 위에 둔다. 지금 맞추는 층이 다른 층에 가려지면 손잡이를 잡을 수 없다.
        commitMapAlignment(levelID, a, name: "\(level.info.name) 지도에 올리기")
        return true
    }

    /// 지도에 올리거나 가운데로 가져올 수 있는 가장 넓은 화면 폭(m). 이보다 넓으면(전국 보기 등) 막는다 —
    /// 도면 크기를 화면 폭에 맞춰 정하므로, 전국 보기에서 올리면 도면이 수 km 크기로 엉뚱한 곳에 놓인다(2026-10-18 실제 발생).
    static let maxPlacingWidthMeters = 3_000.0

    /// 이미 올린 층을 **지금 보는 지도 가운데로** 다시 가져온다. 크기도 지금 화면 폭에 맞춘다.
    /// 회전·쌓는 순서·표시·투명도는 그대로이고, 확정은 풀린다(실행취소 한 칸).
    func bringToMapCenter(_ levelID: UUID, canvasSize: CGSize, mapCenter: GeoPoint, visibleWidthMeters: Double) {
        guard let level = buildingProject.levels.first(where: { $0.id == levelID }),
              var a = level.info.mapAlignment, canvasSize.width > 0, canvasSize.height > 0 else { return }
        let fresh = MapAlignment.initial(center: mapCenter, visibleWidthMeters: visibleWidthMeters, canvasSize: canvasSize)
        a.center = fresh.center
        a.canvasCenter = fresh.canvasCenter
        a.metersPerUnit = fresh.metersPerUnit
        a.isConfirmed = false
        commitMapAlignment(levelID, a, name: "\(level.info.name) 지도 가운데로 가져오기")
    }

    enum StackMove { case front, back, forward, backward }

    /// 맨앞으로 / 맨뒤로 / 앞으로 / 뒤로 보내기. 순서를 0부터 다시 매겨 저장한다(실행취소 한 칸).
    func moveOnMapStack(_ levelID: UUID, _ move: StackMove) {
        var order = mapAlignStack.map(\.id)
        guard let i = order.firstIndex(of: levelID) else { return }
        order.remove(at: i)
        switch move {
        case .front: order.append(levelID)
        case .back: order.insert(levelID, at: 0)
        case .forward: order.insert(levelID, at: min(order.count, i + 1))
        case .backward: order.insert(levelID, at: max(0, i - 1))
        }
        perform("층 쌓는 순서") {
            for (rank, id) in order.enumerated() {
                guard let k = buildingProject.levels.firstIndex(where: { $0.id == id }) else { continue }
                buildingProject.levels[k].info.mapAlignment?.stackOrder = rank
            }
        }
    }

    // MARK: (가) 정렬로 만드는 지오레퍼런싱 Anchor

    /// 정렬된 도면의 한 점을 Anchor 쌍으로 저장한다. 위경도는 정렬에서 계산한다.
    /// **지금 편집 중인 층에만** 찍는다 — Anchor와 그 층의 꼭짓점·교점은 편집 중인 층 기준으로 들고 있다.
    @discardableResult
    func addAlignmentAnchor(at local: LocalPoint) -> AnchorPair? {
        guard let id = routingFloorID, let a = mapAlignment(of: id) else {
            notify("먼저 이 층 도면을 지도에 올려 정렬하세요.", isError: true)
            return nil
        }
        if anchors.pairs.contains(where: { $0.local.distance(to: local) <= SnapPointExtractor.mergeTolerance }) {
            notify("이미 Anchor로 찍은 점입니다.")
            return nil
        }
        var pair = AnchorPair(local: local, geo: a.geoPoint(for: local),
                              label: "정렬 Anchor \(anchors.pairs.count + 1)")
        pair.fromAlignment = true
        perform("정렬 Anchor 추가") { anchors.pairs.append(pair) }
        return pair
    }

    /// Anchor 쌍을 지운다. 그 점으로 지정한 IMDF anchor feature가 있으면 함께 휴지통으로 보낸다 —
    /// 남겨 두면 (가)에 없는 점을 가리키는 (나)가 생긴다.
    func removeAlignmentAnchor(_ id: AnchorID) {
        guard let pair = anchors.pairs.first(where: { $0.id == id }) else { return }
        let linked = imdfAnchorFeature(for: pair)
        perform("Anchor 삭제") {
            anchors.remove(id)
            if let f = linked {
                ownership.releaseAll(of: f.id)
                features.update(f.id) { $0.isInTrash = true }
            }
        }
    }

    // MARK: anchor 레이어에 저장된 점

    /// anchor 레이어(메인 화면)에서 찍어 둔 점. **편집 중인 층** 기준이며 일련번호 순이다.
    /// 점 편집으로 그린 점과 도면 개체를 묶어 만든 점을 내보내기와 같은 계산으로 낸다 —
    /// 그래야 Anchor 화면·지도 정렬 화면에 보이는 자리가 anchor.geojson의 Point와 같다.
    var anchorLayerPoints: [AnchorLayerPoint] {
        features.features(ofType: .anchor).compactMap { f in
            let point = document.flatMap {
                VertexExtractor.vertices(for: f, document: $0, segmentation: segmentation, kind: .point).first
            } ?? f.drawnVertices?.first
            return point.map { AnchorLayerPoint(feature: f, point: $0) }
        }
    }

    /// 이 자리에서 가장 가까운 anchor 레이어 점. 반경을 주지 않으면 같은 점으로 볼 거리만 본다.
    func anchorLayerPoint(near p: LocalPoint,
                          within radius: Double = SnapPointExtractor.mergeTolerance) -> AnchorLayerPoint? {
        anchorLayerPoints.filter { $0.point.distance(to: p) <= radius }
            .min { $0.point.distance(to: p) < $1.point.distance(to: p) }
    }

    /// 이 자리를 도면 쪽 점으로 쓰는 Anchor 쌍.
    func anchorPair(at p: LocalPoint) -> AnchorPair? {
        anchors.pairs.first { $0.local.distance(to: p) <= SnapPointExtractor.mergeTolerance }
    }

    /// anchor 레이어의 점 중 아직 Anchor 쌍이 아닌 점을 쌍으로 불러온다. 위경도는 지금 정렬에서 계산한다.
    /// `ids`를 주면 그 점만 불러온다. **실행취소 한 칸**이다.
    @discardableResult
    func importAnchorLayerPoints(_ ids: Set<FeatureGroupID>? = nil) -> [AnchorPair] {
        guard let id = routingFloorID, let a = mapAlignment(of: id) else {
            notify("먼저 이 층 도면을 지도에 올려 정렬하세요.", isError: true)
            return []
        }
        let targets = anchorLayerPoints.filter { ids?.contains($0.feature.id) ?? true }
            .filter { anchorPair(at: $0.point) == nil }
        guard !targets.isEmpty else {
            notify("불러올 anchor 레이어 점이 없습니다. 이미 모두 Anchor 쌍입니다.")
            return []
        }
        let pairs = targets.map { t -> AnchorPair in
            var pair = AnchorPair(local: t.point, geo: a.geoPoint(for: t.point), label: t.feature.serialNumber)
            pair.fromAlignment = true
            return pair
        }
        perform("anchor 레이어 점 불러오기") { anchors.pairs.append(contentsOf: pairs) }
        notify("anchor 레이어 점 \(pairs.count)개를 Anchor 쌍으로 불러왔습니다.")
        return pairs
    }

    // MARK: (나) IMDF anchor feature

    /// 이 Anchor 쌍의 점으로 지정한 IMDF anchor feature.
    func imdfAnchorFeature(for pair: AnchorPair) -> FeatureGroup? {
        anchorLayerPoint(near: pair.local)?.feature
    }

    /// (가)로 저장한 점을 IMDF anchor feature(Point)로 지정하거나 해제한다.
    /// **(가)에 없는 점은 (나)가 될 수 없다**(사용자 결정, 2026-10-15) — 그래서 Anchor 쌍 id로만 부른다.
    func toggleIMDFAnchor(_ id: AnchorID) {
        guard let pair = anchors.pairs.first(where: { $0.id == id }) else { return }
        if let f = imdfAnchorFeature(for: pair) {
            trash(f.id)
            // 휴지통 보내기와 같은 경로를 탄다 — 펼친 카드 정리와 알림이 한 곳에서 일관된다.
            return
        }
        let serial = serials.next(for: .anchor)
        var f = FeatureGroup(featureType: .anchor, serialNumber: serial, memberIDs: [])
        for field in PropertySchema.fields(for: .anchor) { f.properties[field.key] = .null }
        f.drawnVertices = [pair.local]
        perform("\(serial) anchor 지정") { features.insert(f) }
        notify("\(serial) 로 지정했습니다. address_id·unit_id는 anchor 레이어의 우측 사이드바에서 채우세요.")
    }

    // MARK: 지도에 그릴 도면

    /// 다른 층의 도면도 지도에 올려야 하므로 미리 준비해 둔다. 이미 준비된 층은 건너뛴다.
    /// **한 층씩 차례로 불러온다.** `LevelDrawingCache.load`는 동시에 두 층까지만 받고 그보다 오래된 요청을
    /// 취소하므로, 한꺼번에 요청하면 층이 4개 이상일 때 일부 층이 지도에 나타나지 않는다.
    func prepareMapAlignDrawings() {
        storeActiveLevel()
        mapAlignPrepareTask?.cancel()
        mapAlignPrepareTask = Task { [weak self] in
            for _ in 0..<3 {
                // 편집 층 전환이 끼어들어 취소된 층이 있으면 다시 시도한다.
                guard let self, !Task.isCancelled else { return }
                let remaining = self.mapAlignLevels.filter { $0.id != self.routingFloorID }
                    .map(LevelDrawingInput.init).filter { self.levelDrawingCache.cached($0) == nil }
                guard !remaining.isEmpty else { return }
                for input in remaining {
                    guard !Task.isCancelled else { return }
                    if (try? await self.levelDrawingCache.load(input)) != nil { self.objectWillChange.send() }
                }
            }
        }
    }

    /// 지도에 그릴 한 층의 선 전체(도면 좌표). **보조 개체로 제외한 개체는 넣지 않는다**(11항 작업 목록 1번).
    /// 개체마다 따로 그리면 지도를 움직일 때마다 수천 번 그리므로, 한 묶음으로 만들어 층마다 한 번만 그린다.
    func mapAlignDrawing(for level: ProjectLevel) -> (path: Path, canvasSize: CGSize, objectCount: Int, key: String)? {
        let isActive = level.id == routingFloorID
        let doc: DrawingDocument?
        let excluded: Set<VectorObjectID>
        var entries: [VectorObjectID: ObjectRenderCache] = [:]
        if isActive {
            doc = document
            excluded = auxiliary.excluded
        } else {
            guard let prepared = levelDrawingCache.cached(LevelDrawingInput(level)) else { return nil }
            doc = prepared.document
            excluded = level.editing.auxiliary.excluded
            entries = prepared.renderEntries
        }
        guard let doc else { return nil }
        let key = "\(doc.fingerprint)|\(excluded.hashValue)|\(excluded.count)|\(segmentation.segmentedObjectIDs.count)"
        if let hit = mapAlignPathCache[level.id], hit.key == key {
            return (hit.path, doc.canvasSize, hit.count, key)
        }
        var path = Path()
        var count = 0
        for o in doc.objects where !excluded.contains(o.id) {
            let p = isActive ? renderCache.entry(for: o, segmentation: segmentation).path
                             : (entries[o.id]?.path ?? o.geometry.swiftUIPath)
            path.addPath(p)
            count += 1
        }
        mapAlignPathCache[level.id] = MapAlignPathEntry(key: key, path: path, count: count)
        return (path, doc.canvasSize, count, key)
    }
}

/// anchor 레이어에 저장된 점 하나와 그 도면 좌표.
struct AnchorLayerPoint {
    let feature: FeatureGroup
    let point: LocalPoint
}

/// 층마다 한 번 만든 선 묶음.
struct MapAlignPathEntry {
    let key: String
    let path: Path
    let count: Int
}
