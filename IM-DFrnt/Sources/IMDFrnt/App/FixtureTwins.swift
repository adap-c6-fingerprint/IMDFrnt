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
        if f.polygonRings.isEmpty, !f.memberIDs.isEmpty { return applyTaggingToFixtureMemberTwins(id) }
        // 선 단위로 저장한 fixture는 도형 대신 도면 개체를 가진다. 자리도 개체로 찾는다.
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

/// 선 단위로 고른 개체 묶음과 똑같이 생긴 자리 하나(2026-10-19 요청).
///
/// 점 단위는 그린 도형을 평행이동해 저장하지만, 선 단위는 **그 자리의 도면 개체를 구성원으로** 저장한다.
/// 그래서 자리마다 fixture의 윤곽선이 그 자리 도면을 그대로 따른다.
struct FixtureMemberTwin: Equatable {
    let dx: Double
    let dy: Double
    let memberIDs: Set<VectorObjectID>
}

@MainActor
extension AppEnvironment {

    /// 고른 개체 묶음 전체가 위치만 바꿔 되풀이되는 자리. 묶음의 개체 **하나하나가** 같은 만큼 옮긴 자리에
    /// 쌍둥이를 가져야 한 자리로 친다. 보조 개체로 뺀 개체와 고른 개체 자신은 자리에 넣지 않는다.
    /// 다른 feature가 가진 개체도 자리에는 넣는다 — 새로 저장할지, 속성만 맞출지는 부르는 쪽이 정한다.
    func fixtureMemberTwins(of ids: Set<VectorObjectID>) -> [FixtureMemberTwin] {
        guard let doc = document, !ids.isEmpty else { return [] }
        func cell(_ x: Double, _ y: Double) -> SIMD2<Int> { SIMD2(Int((x * 100).rounded()), Int((y * 100).rounded())) }
        // `twinKey`와 같은 0.01 단위 격자다.

        var origin: [VectorObjectID: CGPoint] = [:]
        var byCell: [VectorObjectID: [SIMD2<Int>: VectorObjectID]] = [:]
        for id in ids {
            guard let box = doc.object(id)?.boundingBox else { return [] }
            origin[id] = box.origin
            var cells: [SIMD2<Int>: VectorObjectID] = [:]
            for t in twins(of: [id]) where !ids.contains(t) && !auxiliary.isExcluded(t) {
                guard let b = doc.object(t)?.boundingBox else { continue }
                cells[cell(b.minX, b.minY)] = t
            }
            byCell[id] = cells
        }
        guard let anchor = ids.min(by: { (byCell[$0]?.count ?? 0) < (byCell[$1]?.count ?? 0) }),
              let anchorOrigin = origin[anchor], let anchorCells = byCell[anchor], !anchorCells.isEmpty else { return [] }
        // 쌍둥이가 가장 적은 개체를 기준으로 삼는다. 후보 자리가 가장 적어 확인이 빠르다.

        func find(_ id: VectorObjectID, dx: Double, dy: Double) -> VectorObjectID? {
            guard let o = origin[id], let cells = byCell[id] else { return nil }
            let c = cell(Double(o.x) + dx, Double(o.y) + dy)
            for ix in -1...1 { for iy in -1...1 { if let t = cells[c &+ SIMD2(ix, iy)] { return t } } }
            return nil
            // 반올림 경계에 걸린 부동소수 오차를 위해 이웃 칸까지 본다.
        }

        var used = Set<VectorObjectID>()
        var out: [FixtureMemberTwin] = []
        for t in anchorCells.values {
            guard let b = doc.object(t)?.boundingBox else { continue }
            let dx = Double(b.minX - anchorOrigin.x), dy = Double(b.minY - anchorOrigin.y)
            var members = Set<VectorObjectID>()
            for id in ids {
                guard let m = find(id, dx: dx, dy: dy), !used.contains(m) else { members = []; break }
                members.insert(m)
            }
            guard members.count == ids.count else { continue }
            used.formUnion(members)
            out.append(FixtureMemberTwin(dx: dx, dy: dy, memberIDs: members))
        }
        return out.sorted { ($0.dy, $0.dx) < ($1.dy, $1.dx) }
    }

    /// 아직 아무 feature도 갖지 않은 자리만. 선 단위 저장 때 함께 저장할 자리다.
    func freeFixtureMemberTwins(of ids: Set<VectorObjectID>) -> [FixtureMemberTwin] {
        fixtureMemberTwins(of: ids).filter { $0.memberIDs.allSatisfy { ownership.ownerOf($0) == nil } }
    }

    /// 자리마다 구성원 fixture를 만든다. `perform` 안에서 부른다. 소유가 겹치면 그 자리는 건너뛴다.
    @discardableResult
    func insertFixtureMemberTwins(_ twins: [FixtureMemberTwin], properties: [String: PropertyValue]) -> Int {
        var added = 0
        for t in twins {
            var f = FeatureGroup(featureType: .fixture, serialNumber: serials.next(for: .fixture), memberIDs: t.memberIDs)
            f.properties = properties
            guard (try? ownership.claim(t.memberIDs, for: f.id)) != nil else { continue }
            features.insert(f)
            added += 1
        }
        return added
    }

    /// 우측 패널: 선 단위로 저장한 fixture와 똑같이 생긴 자리마다 같은 태깅을 둔다.
    /// 빈 자리는 새로 저장하고, 이미 fixture 하나가 그 자리 개체를 그대로 가진 곳은 속성만 맞춘다.
    func applyTaggingToFixtureMemberTwins(_ id: FeatureGroupID) {
        guard let f = features.feature(id) else { return }
        let twins = fixtureMemberTwins(of: f.memberIDs)
        guard !twins.isEmpty else {
            notify("\(f.serialNumber)과 똑같이 생긴 개체가 없습니다.", isError: true)
            return
        }
        var added = 0, updated = 0, skipped = 0
        perform("\(f.serialNumber) 같은 태깅 \(twins.count)곳") {
            var free: [FixtureMemberTwin] = []
            for t in twins {
                let owners = Set(t.memberIDs.compactMap { ownership.ownerOf($0) })
                if owners.isEmpty { free.append(t); continue }
                guard owners.count == 1, let oid = owners.first, let old = features.feature(oid),
                      old.featureType == .fixture, old.memberIDs == t.memberIDs else { skipped += 1; continue }
                // 다른 type이 가졌거나, 여러 feature에 나뉘었거나, 더 많은 개체를 가진 feature는 건드리지 않는다.
                if old.properties != f.properties {
                    features.update(oid) { $0.properties = f.properties }
                    updated += 1
                }
            }
            added = insertFixtureMemberTwins(free, properties: f.properties)
        }
        let same = twins.count - added - updated - skipped
        notify("똑같이 생긴 \(twins.count)곳: 새로 \(added)개 저장, 속성 맞춤 \(updated)개"
               + (same > 0 ? ", 이미 같음 \(same)개" : "") + (skipped > 0 ? ", 다른 feature가 가져 건너뜀 \(skipped)개" : "") + ".")
    }
}
