import SwiftUI

/// 캔버스 이동 렉·이름표 편집 창 렉(2026-10-19) 자체점검. `--selftest`가 견본 도면으로 부른다.
@MainActor
enum CanvasLagSelfTest {
    static func run(_ env: AppEnvironment, _ doc: DrawingDocument, _ check: (String, Bool, String) -> Void) {
        let savedFeatures = env.features, savedFilters = env.categoryFilters
        let savedExpanded = env.expandedFeature, savedOwnership = env.ownership, savedUndo = env.undoStack

        // 1. 속성만 바뀌면 도형 번호가 오르지 않고(면·겹침·진행률 계산 생략), 도형이 바뀌면 오른다.
        var g = FeatureGroup(featureType: .unit, serialNumber: "unit-렉점검", memberIDs: [])
        g.polygonRings = [[LocalPoint(1, 1), LocalPoint(9, 1), LocalPoint(9, 9), LocalPoint(1, 9)]]
        if let free = doc.objects.first(where: { env.ownership.ownerOf($0.id) == nil }) {
            g.memberIDs = [free.id]
            try? env.ownership.claim([free.id], for: g.id)
        }
        // 구성원 개체가 있어야 category 필터가 개체 표시 상태를 바꾼다.
        env.features.insert(g)
        let before = env.geometryRevision
        env.updateProperty("category", value: .string("office"), in: g.id)
        env.updateProperty("name", value: .localized(en: "Office", ko: "사무실"), in: g.id)
        let propertyOnly = env.geometryRevision == before
        var moved = env.features
        moved.update(g.id) { $0.polygonRings[0][1] = LocalPoint(9.5, 1) }
        let changes = FeatureStore.propertyOnlyChanges(from: env.features, to: moved)
        var renamed = env.features
        renamed.update(g.id) { $0.properties["category"] = .string("lobby") }
        check("이름표 편집 렉: category·name만 바꾸면 도형 계산(면·겹침·진행률)을 다시 하지 않고, 도형을 바꾸면 한다",
              propertyOnly && changes == nil
                  && FeatureStore.propertyOnlyChanges(from: env.features, to: renamed) == [g.id]
                  && FeatureStore.propertyOnlyChanges(from: env.features, to: env.features) == [],
              "도형 번호 \(before) → \(env.geometryRevision)")
        check("이름표 name 표시: ko·en이 다 있으면 `한국어(영어)`, 하나만 있으면 그것",
              env.features.feature(g.id).map(AppEnvironment.nameText) == "사무실(Office)"
                  && { var h = g; h.properties["name"] = .localized(en: "", ko: "로비"); return AppEnvironment.nameText(of: h) == "로비" }()
                  && AppEnvironment.nameText(of: FeatureGroup(featureType: .unit, serialNumber: "x", memberIDs: [])) == "", "")

        // 2. 속성만 바꿨을 때 그 feature 구성원만 다시 판정한 표시 상태가 통째로 다시 만든 것과 같다(category 필터 포함).
        func statesText() -> [String] { doc.objects.map { String(describing: env.renderState(for: $0)) } }
        _ = env.renderStates()
        env.categoryFilters[.unit] = ["lobby"]
        env.updateProperty("category", value: .string("lobby"), in: g.id)
        let partial = statesText()
        let memberShown = g.memberIDs.first.flatMap { doc.object($0) }.map { env.renderState(for: $0).isVisible } ?? false
        env.updateProperty("category", value: .string("office"), in: g.id)
        let partialHidden = statesText()
        let memberHidden = g.memberIDs.first.flatMap { doc.object($0) }.map { !env.renderState(for: $0).isVisible } ?? false
        env.invalidateRenderStates()
        let full = statesText()
        check("이름표 편집 렉: category 저장 뒤 일부만 다시 판정한 표시 상태가 통째로 다시 만든 것과 같다(필터에 걸리고 풀림)",
              partialHidden == full && partial != partialHidden && memberShown && memberHidden && !g.memberIDs.isEmpty,
              "구성원 \(g.memberIDs.count)")
        env.categoryFilters = savedFilters

        // 3. 묶어 그리기: 보이는 개체가 빠짐없이 한 번씩 묶음에 들고, 자기 색·굵기 묶음에 든다. 상태가 같으면 다시 만들지 않는다.
        let batches = env.canvasObjectBatches(document: doc, primaryOpacity: 1)
        let background = env.canvasBackground
        var expected: [CanvasBatches.Stroke: Int] = [:]
        var fills = 0
        for o in doc.objects {
            let st = env.renderState(for: o)
            guard st.isVisible, st.opacity > 0.01 else { continue }
            let key = CanvasBatches.Stroke(color: CanvasView.strokeColor(st, style: o.style, background: background).opacity(st.opacity),
                                           width: o.style.strokeWidth,
                                           emphasized: st.isSelected || st.isBorrowed || st.isHighlighted,
                                           borrowed: st.isBorrowed, dash: st.isBorrowed ? [] : o.style.dashPattern)
            expected[key, default: 0] += subpaths(env.renderCache.entry(for: o, segmentation: env.segmentation).path)
            if o.style.fill != nil { fills += 1 }
        }
        let got = Dictionary(batches.strokes.map { ($0.0, subpaths($0.1)) }, uniquingKeysWith: +)
        let revision = env.renderStateRevision
        env.hoveredFeature = savedFeatures.features.first(where: { $0.memberIDs.isEmpty })?.id
        // 구성원 개체가 없는(점으로 그린) feature에 마우스를 올려도 표시 상태 사전은 그대로다.
        let again = env.canvasObjectBatches(document: doc, primaryOpacity: 1)
        env.hoveredFeature = nil
        check("화면 이동 렉: 묶어 그리는 경로가 보이는 개체를 빠짐없이 자기 색·굵기 묶음에 담고, 상태가 같으면 다시 만들지 않는다",
              got == expected && batches.fills.count == fills && again.key == batches.key
                  && env.renderStateRevision == revision && !expected.isEmpty,
              "묶음 \(batches.strokes.count)개 · 면 \(fills)")
        env.selection.toggle(doc.objects[0].id)
        let selected = env.canvasObjectBatches(document: doc, primaryOpacity: 1)
        check("화면 이동 렉: 선택이 바뀌면 묶음을 다시 만들고 선택 상자를 단다",
              selected.key != batches.key && selected.selectedBoxes.count == 1, "")
        env.selection.clear()

        // 4. 도면 대부분이 보이면 격자 후보를 모으지 않고 바로 전체로 답한다.
        let grid = SpatialIndex(objects: doc.objects, canvasSize: doc.canvasSize)
        let all = CGRect(origin: .zero, size: doc.canvasSize)
        check("화면 이동 렉: 화면이 도면 범위의 절반 넘게 덮으면 격자 후보 없이 전체를 그린다",
              grid.drawIndices(in: all, moved: [], count: doc.objects.count) == nil
                  && grid.drawIndices(in: all.insetBy(dx: all.width * 0.2, dy: all.height * 0.2), moved: [], count: doc.objects.count) == nil,
              "")

        // 5. 문 자리 안 개체 찾기는 격자로 근처만 봐도 전부 훑은 결과와 같다.
        if let o = doc.objects.first(where: { let b = $0.boundingBox; return b.width > 1 && b.height < b.width }) {
            let b = o.boundingBox
            var door = FeatureGroup(featureType: .opening, serialNumber: "opening-렉점검", memberIDs: [])
            door.drawnVertices = [LocalPoint(b.minX, b.midY), LocalPoint(b.maxX, b.midY)]
            env.features.insert(door)
            let tagged = Set(env.snapPoints.indices)
            let fast = env.pointCoveredObjects(tagged: []), slow = env.pointCoveredObjects(tagged: [], usingGrid: false)
            let fastAll = env.pointCoveredObjects(tagged: tagged), slowAll = env.pointCoveredObjects(tagged: tagged, usingGrid: false)
            check("이름표 편집 렉: 문 자리 안 개체를 격자로 찾은 결과가 전부 훑은 결과와 같다",
                  fast == slow && fastAll == slowAll && fast.contains(o.id), "문 자리 안 \(fast.count)개")
        }

        env.features = savedFeatures
        env.ownership = savedOwnership
        env.expandedFeature = savedExpanded
        env.undoStack = savedUndo
    }

    private static func subpaths(_ p: Path) -> Int {
        var n = 0
        p.forEach { if case .move = $0 { n += 1 } }
        return n
    }
}
