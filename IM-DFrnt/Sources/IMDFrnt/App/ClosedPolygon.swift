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
    var isPolygonWorkMode: Bool {
        document != nil && (layers.activePropertyType?.requiresClosedRing ?? false)
    }

    // MARK: 면 찾기

    /// 활성 레이어가 폴리곤 type으로 바뀌거나 보조 개체 제외가 바뀔 때 다시 만든다.
    ///
    /// **매 프레임은 물론 도면을 열 때도 만들지 않는다.** 계산이 선분 수의 제곱에 붙어서,
    /// 적재 시점에 만들면 실도면에서 앱 시작이 멈춘다(`04) 엔진 디버깅.md` 1-1).
    func rebuildClosedPolygons() {
        guard let doc = document else {
            closedPolygonFaces = []
            faceSelection = []
            return
        }
        closedPolygonFaces = ClosedPolygonFinder.faces(in: faceSources(in: doc, includeAuxiliary: false))
        faceSelection.formIntersection(Set(closedPolygonFaces.map(\.id)))
        // 사라진 면의 선택을 들고 있으면 저장 버튼의 개수와 화면이 어긋난다.
        if polygonWorkMode == .exclude { selectAllFaces() }
        // 제외 모드는 '전부 고른 상태에서 빼 나가는' 모드다(5-4 2번). 면 목록이 새로 만들어졌으면
        // 다시 전부 고른 상태에서 시작해야 한다.
    }

    /// 면을 이루는 선분들. `includeAuxiliary`가 참이면 보조 개체로 제외한 선분까지 넣는다 —
    /// 다각형 진행률 막대의 **분모**가 그 상태의 면 수다(5-5-2).
    func faceSources(in doc: DrawingDocument,
                     includeAuxiliary: Bool) -> [ClosedPolygonFinder.SourceSegment] {
        var sources: [ClosedPolygonFinder.SourceSegment] = []
        for o in doc.objects where includeAuxiliary || !auxiliary.isExcluded(o.id) {
            let entry = renderCache.entry(for: o, segmentation: segmentation)
            for s in entry.segments { sources.append(.init(segment: s, objectID: o.id)) }
        }
        for door in doorClosures.doors {
            sources.append(.init(segment: LineSegment(start: door.start, end: door.end),
                                 objectID: nil))
            // 신기능 5-2: "openings에서 임시로 닫은 문을 포함하여".
        }
        return sources
    }

    /// 다각형 진행률의 분모. **도면을 열 때 한 번만 센다**(5-5-2, 사노 확정) —
    /// 보조 개체를 제외해도 분모는 그대로 두고, 사라진 면을 **분자에** 얹는다.
    /// 분모가 조작할 때마다 흔들리면 막대가 이유 없이 늘었다 줄었다 한다.
    func rebuildTotalPolygonCount() {
        guard let doc = document else { totalPolygonCount = 0; return }
        totalPolygonCount = ClosedPolygonFinder.faces(
            in: faceSources(in: doc, includeAuxiliary: true)).count
    }

    // MARK: 고르기

    var selectedFaces: [ClosedPolygonFinder.Face] {
        closedPolygonFaces.filter { faceSelection.contains($0.id) }
    }

    func isFaceSelected(_ id: String) -> Bool { faceSelection.contains(id) }

    /// 아직 고를 수 있는 면의 수. 이미 저장된 면은 뺀다.
    var selectableFaceCount: Int {
        let saved = savedPolygonFaceIDs
        return closedPolygonFaces.filter { !saved.contains($0.id) }.count
    }

    /// 이미 어떤 feature가 가져간 면인가.
    func closedPolygonIsSaved(_ face: ClosedPolygonFinder.Face) -> Bool {
        savedPolygonFaceIDs.contains(face.id)
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
        guard let hit = closedPolygonFaces
            .filter({ !closedPolygonIsSaved($0) && $0.contains(point) })
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
        let hits = closedPolygonFaces.filter { face in
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
        faceSelection = Set(closedPolygonFaces.filter { !closedPolygonIsSaved($0) }.map(\.id))
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

        let batches: [[ClosedPolygonFinder.Face]] = type.requiredGeometry == .multiPolygon
            ? ClosedPolygonFinder.connectedGroups(of: picked)
            : picked.map { [$0] }
        // **fixture(MultiPolygon)는 선분을 나눠 쓰는 면들을 한 feature로 묶는다**(5-4 2번).
        // 폴리곤 type은 면 하나가 feature 하나다 — 방 둘이 벽을 나눠 쓴다고 한 방이 되면 안 된다.

        var madeSerials: [String] = []
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
                f.polygonFaceIDs = Set(batch.map(\.id))

                try? ownership.claim(free, for: f.id)
                features.insert(f)
                madeSerials.append(serial)
            }
            faceSelection = []
        }

        notify(madeSerials.count == 1
               ? "\(madeSerials[0]) 로 저장했습니다."
               : "\(type.displayName) feature \(madeSerials.count)개를 저장했습니다(면 \(picked.count)개).")
    }

    // MARK: 진행률 (5-5)

    /// 다각형 기준 진행률에서 **태깅한 면**의 몫.
    var taggedPolygonCount: Int { savedPolygonFaceIDs.count }

    /// **제외된 개체 때문에 사라진 면**의 몫. 분모(전체 면)에서 지금 남아 있는 면을 뺀 값이다.
    /// 보조 개체를 빼면 그 선분이 이루던 면이 없어지거나 옆면과 합쳐지는데, 어느 쪽이든
    /// "손을 대서 처리된 면"이므로 진척으로 셈한다(5-5-2).
    ///
    /// ✅ 2026-08-30 — 계산 프로퍼티에서 **세어 두는 값**(`AppEnvironment.vanishedPolygonCount`)으로
    /// 바꿨다. 옛 식 `totalPolygonCount - closedPolygonFaces.count`는 `closedPolygonFaces`가
    /// 항상 최신이라는 전제를 깔고 있는데, 그 목록은 성능 때문에 **폴리곤 type 레이어를 열 때만**
    /// 채운다. 도면을 막 열면 빈 배열이므로 `전체 - 0 = 전체`, 즉 100%가 됐다.
    ///
    /// **제외가 하나도 없으면 세지 않는다.** 제외가 없으면 `includeAuxiliary`가 참이든 거짓이든
    /// 같은 면 집합이 나오므로 사라진 면은 정의상 0이다 — 무거운 면 찾기를 돌릴 이유가 없다.
    func rebuildVanishedPolygonCount() {
        guard let doc = document, !auxiliary.excluded.isEmpty else {
            vanishedPolygonCount = 0
            return
        }
        let remaining = ClosedPolygonFinder.faces(
            in: faceSources(in: doc, includeAuxiliary: false)).count
        vanishedPolygonCount = max(0, totalPolygonCount - remaining)
    }

    var polygonProgressFraction: Double {
        guard totalPolygonCount > 0 else { return 0 }
        return Double(min(totalPolygonCount, taggedPolygonCount + vanishedPolygonCount))
            / Double(totalPolygonCount)
    }

    var taggedPolygonFraction: Double {
        guard totalPolygonCount > 0 else { return 0 }
        return Double(min(totalPolygonCount, taggedPolygonCount)) / Double(totalPolygonCount)
    }

    var vanishedPolygonFraction: Double {
        guard totalPolygonCount > 0 else { return 0 }
        return Double(min(totalPolygonCount, vanishedPolygonCount)) / Double(totalPolygonCount)
    }

    var polygonProgressText: String {
        "\(taggedPolygonCount + vanishedPolygonCount) / \(totalPolygonCount)"
    }
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
