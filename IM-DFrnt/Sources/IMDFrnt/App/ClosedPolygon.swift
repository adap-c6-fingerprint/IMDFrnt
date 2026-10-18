import CoreGraphics
import Foundation

/// 다각형 선택 작업(신기능 5항 + 5-4 전환).
///
/// **폴리곤 type의 레이어에서는 선분이 아니라 면을 고른다.** 벽선을 하나씩 골라 묶던 경로는
/// 링이 열린 것을 저장한 뒤에야 알려 줬다(명세 10-4). 이제 도면에서 **이미 닫혀 있는 면을
/// 먼저 찾아 보여주고**, 사용자는 고르기만 한다.
///
/// **선분 선택이 사라지는 것은 아니다.** LineString(opening)·Point(amenity) type은 종전 경로를
/// 그대로 쓴다(5-4 1번 결정). 어느 type의 레이어를 열었느냐로 캔버스가 두 모드로 갈린다.
@MainActor
extension AppEnvironment {

    /// 지금 화면이 면을 고르는 모드인가.
    ///
    /// #21(2026-10-15): 폴리곤 type 레이어에서 **점 단위와 면 단위를 오가며** 쓴다. 상단바에서
    /// '면 단위'를 골랐을 때만 면을 고른다. footprint는 면 단위 대상에서 뺀다(10번 지침).
    var isPolygonWorkMode: Bool {
        document != nil && (layers.activePropertyType?.allowsFaceSelection ?? false) && layerEditMode == .face
    }

    // MARK: 면 찾기
    //
    // 면은 `DerivedGeometry`가 백그라운드에서 찾아 `closedPolygonFaces`에 넣는다(#21).
    // 예전의 `rebuildClosedPolygons()`는 레이어를 열 때마다 메인 스레드에서 면을 다시 찾아
    // C5 도면에서 앱이 약 5초 멈췄다(`04) 엔진 디버깅.md` 3장). 층을 불러올 때 찾은 면을 그대로 쓴다.

    // MARK: 고르기

    var selectedFaces: [ClosedPolygonFinder.Face] {
        faceModeFaces.filter { faceSelection.contains($0.id) }
    }

    func isFaceSelected(_ id: String) -> Bool { faceSelection.contains(id) }

    /// 아직 고를 수 있는 면의 수. 이미 저장된 면은 뺀다.
    var selectableFaceCount: Int {
        faceModeFaces.filter { !closedPolygonIsSaved($0) }.count
    }

    /// 이미 어떤 feature가 가져간 면인가. 면으로 저장한 기록이 있거나, 지금 레이어에 같은 모양의 다각형이 있으면 저장된 것이다.
    func closedPolygonIsSaved(_ face: ClosedPolygonFinder.Face) -> Bool {
        savedPolygonFaceIDs.contains(face.id) || faceOwner(face) != nil
    }

    var savedPolygonFaceIDs: Set<String> {
        features.features.reduce(into: Set<String>()) { out, f in
            guard !f.isInTrash else { return }
            out.formUnion(f.polygonFaceIDs)
        }
    }

    /// 캔버스 클릭. 두 모드 모두 **고른 것을 뒤집는다** — 포함 모드는 빈 상태에서 더해 가고,
    /// 제외 모드는 전부 고른 상태에서 빼 나간다. 클릭 한 번의 뜻은 같다.
    func handleFaceClick(at point: LocalPoint) {
        guard let hit = faceModeFaces
            .filter({ !closedPolygonIsSaved($0) && faceContains($0, point) })
            .min(by: { $0.area < $1.area })
        else { return }
        // **겹친 면이 있으면 작은 쪽을 고른다.** 방은 건물 외곽 안에 들어 있어 늘 겹치는데,
        // 큰 쪽을 고르면 방을 클릭할 때마다 건물 전체가 잡혀 아무것도 못 고른다.

        if faceSelection.contains(hit.id) { faceSelection.remove(hit.id) }
        else { faceSelection.insert(hit.id) }
    }

    /// 드래그 사각형(5-4 3번). 포함 모드는 더하고, 제외 모드는 뺀다 —
    /// **드래그는 클릭과 달리 뒤집지 않는다.** 수십 개가 한꺼번에 뒤집히면 결과를 예측할 수 없다
    /// (선분 드래그 선택과 같은 규칙).
    func handleFaceMarquee(rect: CGRect, mode: HitTester.MarqueeMode) {
        let hits = faceModeFaces.filter { face in
            guard !closedPolygonIsSaved(face) else { return false }
            switch mode {
            case .enclose: return rect.contains(face.boundingBox)
            case .crossing: return rect.intersects(face.boundingBox)
            }
        }
        guard !hits.isEmpty else { return }

        var next = faceSelection
        switch polygonWorkMode {
        case .include: next.formUnion(hits.map(\.id))
        case .exclude: next.subtract(hits.map(\.id))
        }
        faceSelection = next
        // 한 번에 대입한다. 하나씩 고치면 `didSet`이 그만큼 돌아 선택 개수의 제곱으로 느려진다
        // (`03) 뷰 디버깅.md` 17번에서 겪은 자리).
        notify(polygonWorkMode == .include
               ? "다각형 \(hits.count)개를 선택에 더했습니다."
               : "다각형 \(hits.count)개를 선택에서 뺐습니다.")
    }

    func selectAllFaces() {
        faceSelection = Set(faceModeFaces.filter { !closedPolygonIsSaved($0) }.map(\.id))
    }

    func clearFaceSelection() { faceSelection = [] }

    /// 모드 전환. **모드가 바뀌면 시작 상태도 바뀐다**(5-4 1·2번) —
    /// 포함 모드는 아무것도 고르지 않은 상태에서, 제외 모드는 전부 고른 상태에서 시작한다.
    func setPolygonWorkMode(_ mode: PolygonWorkMode) {
        guard mode != polygonWorkMode else { return }
        polygonWorkMode = mode
        switch mode {
        case .include: clearFaceSelection()
        case .exclude: selectAllFaces()
        }
    }

    // MARK: 저장

    /// '선택한 다각형 모두 저장'(5-4 1·2번). 두 모드 모두 이 버튼으로 끝난다 —
    /// 모드는 **선택을 만드는 방법**이 다를 뿐, 결과는 "고른 면을 feature로 만든다"로 같다.
    func saveSelectedFaces() {
        guard let type = layers.activePropertyType, type.requiresClosedRing else { return }
        let picked = selectedFaces.filter { !closedPolygonIsSaved($0) }
        guard !picked.isEmpty else { return }
        if let target = multiPolygonTarget(for: type) {
            let added = picked.filter {
                let ok = addRingToMultiPolygon($0.ring, target: target, faceID: $0.memberIDs.isEmpty ? nil : $0.id, members: $0.memberIDs)
                if ok { for hole in faceHoles($0) { addRingToMultiPolygon(hole, target: target) } }
                return ok
            }
            if !added.isEmpty { faceSelection = [] }
            return
            // 우측 패널에서 MultiPolygon으로 지정한 feature가 있으면 고른 면을 그 feature에 하나씩 더한다.
        }

        let batches: [[ClosedPolygonFinder.Face]] = type.requiredGeometry == .multiPolygon
            ? ClosedPolygonFinder.connectedGroups(of: picked)
            : picked.map { [$0] }
        // **fixture(MultiPolygon)는 선분을 나눠 쓰는 면들을 한 feature로 묶는다**(5-4 2번).
        // 폴리곤 type은 면 하나가 feature 하나다 — 방 둘이 벽을 나눠 쓴다고 한 방이 되면 안 된다.

        var madeSerials: [String] = []
        var movedTotal = 0
        var shared: [String] = []
        perform("다각형 \(picked.count)개 저장") {
            for batch in batches {
                let members = batch.reduce(into: Set<VectorObjectID>()) { $0.formUnion($1.memberIDs) }
                let free = members.filter { ownership.ownerOf($0) == nil }
                // **주인 없는 개체만 소유를 주장한다.** 옆방과 맞닿은 벽선을 두 방이 나눠 쓰는 것은
                // 도면에서 정상인데 소유권은 배타적이라(명세 4-1) 두 번째 방이 저장되지 않는다.
                // 좌표는 아래 `polygonRings`가 정본이므로 소유하지 않아도 링이 열리지 않는다.

                let serial = serials.next(for: type)
                var f = FeatureGroup(featureType: type, serialNumber: serial, memberIDs: members)
                for field in PropertySchema.fields(for: type) { f.properties[field.key] = .null }
                f.polygonRings = batch.map(\.ring)
                let holes = batch.flatMap { faceHoles($0) }
                if !holes.isEmpty, type.requiredGeometry == .polygon {
                    f.polygonRings += holes
                    f.multiPolygon = true
                }
                // level 기준 면은 안쪽에 떠 있는 unit 자리를 구멍으로 갖는다. 링 관계로 구멍을 정하는 MultiPolygon으로 저장한다.
                if type.requiredGeometry == .polygon {
                    let (aligned, moved) = alignRings(f.polygonRings, type: type, excluding: nil)
                    f.polygonRings = aligned
                    movedTotal += moved
                }
                // 면의 꼭짓점도 이웃 도형의 꼭짓점·변에 맞춘다. 도면 선으로 찾은 면은 이웃과 0.01~0.05씩 어긋나기 쉽다.
                if !members.isEmpty { f.polygonFaceIDs = Set(batch.map(\.id)) }
                // 저장된 feature 경계로 찾은 면은 도면 개체가 없다. 면 기록 없이 링만 두면 점으로 그린 도형처럼
                // 꼭짓점 이동·Control 개체 편집이 되고, 같은 면을 다시 고르는 것은 같은 모양 검사가 막는다.

                try? ownership.claim(free, for: f.id)
                features.insert(f)
                if type.requiredGeometry == .polygon {
                    shared += insertSharedVertices(of: f.polygonRings, type: type, excluding: f.id)
                }
                madeSerials.append(serial)
            }
            faceSelection = []
        }

        notify((madeSerials.count == 1
               ? "\(madeSerials[0]) 로 저장했습니다."
               : "\(type.displayName) feature \(madeSerials.count)개를 저장했습니다(면 \(picked.count)개).")
               + Self.alignmentNote(moved: movedTotal, shared: Array(Set(shared)).sorted()))
    }

    // 다각형 기준 진행률(5-5-2)은 점 기준으로 바뀌었다(#21, `PointEditing.swift`).
}

/// 다각형을 고르는 두 가지 방법(5-4 1·2번).
enum PolygonWorkMode: String, CaseIterable {
    /// 아무것도 고르지 않은 상태에서 **더해 간다.**
    case include
    /// 전부 고른 상태에서 **빼 나간다.** 저장할 것이 대부분일 때 훨씬 빠르다.
    case exclude

    var title: String {
        switch self {
        case .include: return "선택한 다각형 포함"
        case .exclude: return "선택한 다각형 제외"
        }
    }

    var help: String {
        switch self {
        case .include: return "누른 다각형을 선택에 더합니다. 저장할 면이 적을 때 빠릅니다."
        case .exclude: return "모든 다각형이 선택된 상태로 시작합니다. 누른 다각형을 선택에서 뺍니다."
        }
    }
}
