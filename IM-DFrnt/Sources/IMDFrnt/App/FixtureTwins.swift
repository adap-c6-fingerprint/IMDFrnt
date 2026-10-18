import Foundation

/// fixture의 '똑같이 생긴 개체에 같은 태깅'(2026-10-18 요청).
///
/// 변기·세면대처럼 같은 fixture는 도면에 같은 모양이 위치만 달리해 반복된다. 하나를 점으로 그리면
/// '보조 개체 제외'의 쌍둥이 판정(`VectorObject.twinKey`)으로 같은 모양의 도면 개체를 찾고,
/// 그린 도형을 그 자리로 평행이동해 **자리마다 개별 Polygon fixture**로 저장한다.
/// 쌍둥이 키가 위치만 빼고 비교하므로 회전·반전된 모양은 쌍둥이가 아니다.
struct FixtureTwinPlacement: Equatable {
    /// 그 자리의 도면 개체.
    let objectID: VectorObjectID
    let dx: Double
    let dy: Double

    func moved(_ ring: [LocalPoint]) -> [LocalPoint] { ring.map { LocalPoint($0.x + dx, $0.y + dy) } }
}

struct FixtureTwinCache {
    var points: [LocalPoint]
    var snapCount: Int
    var fingerprint: String?
    var placements: [FixtureTwinPlacement]
}

@MainActor
extension AppEnvironment {

    /// 작성 중인 fixture 도형과 똑같이 생긴 자리. 찍은 점이 하나라도 있으면 바로 보인다.
    var draftFixtureTwins: [FixtureTwinPlacement] {
        guard isPointWorkMode, layers.activePropertyType == .fixture,
              pointDraft.source == nil, !pointDraft.isEmpty else { return [] }
        return fixtureTwinPlacements(for: pointDraft.points)
    }

    /// 저장된 fixture와 똑같이 생긴 자리.
    func fixtureTwinPlacements(of f: FeatureGroup) -> [FixtureTwinPlacement] {
        guard f.featureType == .fixture, !f.polygonRings.isEmpty else { return [] }
        return fixtureTwinPlacements(for: f.polygonRings.flatMap { $0 })
    }

    /// 점들이 놓인 도면 개체를 기준으로 그 쌍둥이 자리를 찾는다.
    func fixtureTwinPlacements(for points: [LocalPoint]) -> [FixtureTwinPlacement] {
        if let c = fixtureTwinCache, c.points == points, c.snapCount == snapPoints.count,
           c.fingerprint == document?.fingerprint { return c.placements }
        let placements = findFixtureTwinPlacements(for: points)
        fixtureTwinCache = FixtureTwinCache(points: points, snapCount: snapPoints.count,
                                            fingerprint: document?.fingerprint, placements: placements)
        return placements
    }

    private func findFixtureTwinPlacements(for points: [LocalPoint]) -> [FixtureTwinPlacement] {
        guard let doc = document else { return [] }
        let tol = SnapPointExtractor.mergeTolerance
        var hits: [VectorObjectID: Int] = [:]
        var snapped: [LocalPoint] = []
        for p in points {
            guard let sp = snapPointIndex.nearest(to: p, within: tol) else { continue }
            snapped.append(p)
            for o in sp.owners where twins(of: [o]).count > 1 { hits[o, default: 0] += 1 }
        }
        // ⌥로 만든 점은 도면 점이 아니라 기준을 정하는 데도, 쌍둥이 자리를 확인하는 데도 쓰지 않는다.
        guard let source = hits.max(by: { a, b in
            if a.value != b.value { return a.value < b.value }
            return area(of: a.key, in: doc) > area(of: b.key, in: doc)
        })?.key, let sourceBox = doc.object(source)?.boundingBox else { return [] }
        // 점을 가장 많이 가진 개체가 기준이다. 같으면 작은 쪽 — 벽선보다 가구가 작다.

        var out: [FixtureTwinPlacement] = []
        for id in twins(of: [source]) where id != source {
            guard let box = doc.object(id)?.boundingBox else { continue }
            let t = FixtureTwinPlacement(objectID: id, dx: box.minX - sourceBox.minX, dy: box.minY - sourceBox.minY)
            guard t.moved(snapped).allSatisfy({ snapPointIndex.nearest(to: $0, within: tol * 2) != nil }) else { continue }
            // 옮긴 자리에도 도면 점이 있어야 한다. 기준 개체 밖의 점(옆 벽 등)이 섞였거나
            // 보조 개체로 뺀 쌍둥이면 여기서 빠진다.
            out.append(t)
        }
        return out.sorted { ($0.dy, $0.dx) < ($1.dy, $1.dx) }
    }

    private func area(of id: VectorObjectID, in doc: DrawingDocument) -> Double {
        guard let b = doc.object(id)?.boundingBox else { return .infinity }
        return Double(b.width * b.height)
    }

    /// 그 자리에 같은 모양으로 이미 저장된 fixture. 다시 만들지 않고 태깅만 맞춘다.
    private func existingFixture(with rings: [[LocalPoint]], except: FeatureGroupID?) -> FeatureGroup? {
        features.features(ofType: .fixture).first { f in
            !f.isInTrash && f.id != except && f.polygonRings.count == rings.count
                && zip(f.polygonRings, rings).allSatisfy { RingNesting.relation($0, to: $1) == .duplicate }
        }
    }

    /// 쌍둥이 자리마다 fixture를 만든다(이미 있으면 속성만 맞춘다). `perform` 안에서 부른다.
    @discardableResult
    func insertFixtureTwins(rings: [[LocalPoint]], properties: [String: PropertyValue],
                            placements: [FixtureTwinPlacement], except: FeatureGroupID?) -> (added: Int, updated: Int) {
        var added = 0, updated = 0
        for t in placements {
            let moved = rings.map(t.moved)
            if let old = existingFixture(with: moved, except: except) {
                if old.properties != properties {
                    features.update(old.id) { $0.properties = properties }
                    updated += 1
                }
                continue
            }
            var f = FeatureGroup(featureType: .fixture, serialNumber: serials.next(for: .fixture), memberIDs: [])
            f.properties = properties
            f.polygonRings = moved
            features.insert(f)
            added += 1
        }
        return (added, updated)
    }

    /// 우측 패널: 이 fixture와 똑같이 생긴 자리마다 같은 태깅(속성)의 fixture를 둔다.
    func applyTaggingToFixtureTwins(_ id: FeatureGroupID) {
        guard let f = features.feature(id) else { return }
        let placements = fixtureTwinPlacements(of: f)
        guard !placements.isEmpty else {
            notify("\(f.serialNumber)과 똑같이 생긴 개체가 없습니다.", isError: true)
            return
        }
        var result = (added: 0, updated: 0)
        perform("\(f.serialNumber) 같은 태깅 \(placements.count)곳") {
            result = insertFixtureTwins(rings: f.polygonRings, properties: f.properties,
                                        placements: placements, except: f.id)
        }
        let same = placements.count - result.added - result.updated
        notify("똑같이 생긴 \(placements.count)곳: 새로 \(result.added)개 저장, 속성 맞춤 \(result.updated)개"
               + (same > 0 ? ", 이미 같음 \(same)개" : "") + ".")
    }
}
