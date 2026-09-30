import CoreGraphics
import Foundation

/// '문 임시로 닫기' 창에서 찍을 수 있는 점(신기능 3-2: "모든 개체는 '끝점'과 '교차점'을 선택 가능").
///
/// **아무 데나 찍게 두지 않는 것이 요점이다.** 문 자리를 닫는 선분은 벽선의 실제 끝에서
/// 시작해 반대쪽 벽선의 실제 끝에서 끝나야 한다. 눈대중으로 근처를 찍으면 몇 단위씩 어긋나고,
/// 그 틈으로 폴리곤이 다시 열린다 — 화면에서는 닫힌 것처럼 보이는데 내보내기에서 실패한다.
enum SnapPointExtractor {

    /// 찍을 수 있는 점 하나.
    struct SnapPoint: Identifiable, Hashable {
        enum Kind: String { case endpoint, vertex, crossing }
        /// - `endpoint`: 열린 경로가 **끝난** 자리. 문 자리를 닫을 때 겨냥하는 것이 대개 이것이다.
        /// - `vertex`: 경로가 **꺾이는** 자리. 사각형 모서리처럼 닫힌 경로에도 있다.
        /// - `crossing`: 서로 다른 개체가 **가로지르는** 자리.

        let id: String
        let point: LocalPoint
        let kind: Kind

        /// 이 점을 만들어 낸 개체들. 교차점은 둘, 끝점은 하나다.
        let owners: Set<VectorObjectID>
    }

    /// 좌표를 이 크기로 반올림해 같은 자리의 점을 하나로 본다.
    /// 도면은 벽선 두 개가 꼭짓점에서 만나도 좌표가 소수점 아래에서 어긋나 있는 일이 흔하다.
    static let mergeTolerance: Double = 0.05

    /// 후보 점 전부.
    ///
    /// **같은 자리에 여러 종류가 성립하면 끝점 > 교차점 > 꼭짓점 순으로 이긴다.**
    /// 뜻이 좁은 것이 이긴다는 규칙이다 — "벽이 끝난 자리"가 가장 좁고,
    /// "두 개체가 가로지른 자리"가 그다음이며, "한 개체가 꺾인 자리"는 도면 어디에나 있다.
    /// 벽선이 사각형 모서리에서 끝나면 그 점은 셋 다 성립할 수 있는데, 사용자가 겨냥한 것은 끝점이다.
    static func points(in objects: [VectorObject],
                       segmentation: SegmentationStore) -> [SnapPoint] {
        let geometries = objects.map {
            ($0.id, segmentation.effectiveGeometry(for: $0.id, fallback: $0.geometry))
        }

        var seen: [GridKey: SnapPoint] = [:]

        // 1) 꼭짓점 — 경로가 꺾이는 모든 자리. **닫힌 경로에도 있다**(사각형 모서리 등).
        // 가장 흔하고 뜻이 넓으므로 먼저 담아, 뒤에 오는 교차점·끝점이 덮어쓸 수 있게 한다.
        for (id, geo) in geometries {
            for sp in geo.subpaths {
                for p in sp.points {
                    add(SnapPoint(id: "v-\(key(p))", point: p, kind: .vertex, owners: [id]),
                        into: &seen)
                }
            }
        }

        // 2) 교차점 — 서로 다른 개체의 선분이 실제로 가로지르는 자리.
        // 같은 개체 안의 자기 교차는 보지 않는다. 도면 한 개체가 스스로를 가로지르는 것은
        // 작도 흔적일 때가 많고, 문 자리를 닫는 데 쓸 점이 아니다.
        //
        // **경계 상자로 먼저 걸러내는 것이 이 절의 전부다.** 모든 개체 쌍 × 모든 선분 쌍을
        // 그대로 돌면 계산이 개체 수의 제곱에 붙어, 실도면(개체 수천 개)에서 앱이 멈춘다.
        // 도면에서 실제로 겹치는 개체 쌍은 전체의 아주 일부라, 상자만 먼저 봐도 대부분이 걸러진다.
        let entries: [(id: VectorObjectID, box: CGRect, segments: [(LineSegment, CGRect)])] =
            geometries.map { id, geo in
                let segs = geo.lineSegments().map { ($0, $0.boundingBox) }
                return (id, geo.boundingBox, segs)
            }

        for i in entries.indices {
            let a = entries[i]
            for j in (i + 1)..<entries.count {
                let b = entries[j]
                guard a.box.intersects(b.box) else { continue }
                // 개체 상자가 안 겹치면 그 안의 선분도 안 겹친다. 여기서 대부분이 끝난다.

                for (segA, boxA) in a.segments {
                    guard boxA.intersects(b.box) else { continue }
                    for (segB, boxB) in b.segments {
                        guard boxA.intersects(boxB) else { continue }
                        guard let p = OverlapDetector.crossing(segA, segB) else { continue }
                        add(SnapPoint(id: "x-\(key(p))", point: p, kind: .crossing,
                                      owners: [a.id, b.id]), into: &seen)
                    }
                }
            }
        }

        // 3) 끝점 — 열린 경로의 양 끝. 가장 좁은 뜻이라 마지막에 담아 다른 종류를 덮는다.
        for (id, geo) in geometries {
            for sp in geo.subpaths where !sp.isClosed {
                for p in [sp.start, sp.points.last].compactMap({ $0 }) {
                    add(SnapPoint(id: "e-\(key(p))", point: p, kind: .endpoint, owners: [id]),
                        into: &seen)
                }
            }
        }

        return seen.values.sorted {
            $0.point.y == $1.point.y ? $0.point.x < $1.point.x : $0.point.y < $1.point.y
        }
        // 정렬은 화면 표시가 아니라 **결과를 재현 가능하게** 만들기 위한 것이다.
        // 딕셔너리 순서를 그대로 내보내면 실행할 때마다 목록이 달라져 자체점검이 흔들린다.
    }

    /// 커서에서 가장 가까운 후보. 허용 반경 밖이면 아무것도 안 준다 —
    /// 억지로 가장 가까운 점을 주면 사용자가 의도하지 않은 자리에 선분이 걸린다.
    static func nearest(to p: LocalPoint, among points: [SnapPoint],
                        within radius: Double) -> SnapPoint? {
        var best: (SnapPoint, Double)?
        for c in points {
            let d = c.point.distance(to: p)
            if d <= radius, d < (best?.1 ?? .greatestFiniteMagnitude) { best = (c, d) }
        }
        return best?.0
    }

    // MARK: 같은 자리 합치기

    private struct GridKey: Hashable { let x: Int; let y: Int }

    private static func gridKey(_ p: LocalPoint) -> GridKey {
        GridKey(x: Int((p.x / mergeTolerance).rounded()),
                y: Int((p.y / mergeTolerance).rounded()))
    }

    private static func key(_ p: LocalPoint) -> String {
        String(format: "%.2f,%.2f", p.x, p.y)
    }

    /// 뜻이 좁을수록 큰 값. 같은 자리에서는 이 값이 큰 쪽이 남는다.
    private static func rank(_ kind: SnapPoint.Kind) -> Int {
        switch kind {
        case .vertex:   return 0
        case .crossing: return 1
        case .endpoint: return 2
        }
    }

    private static func add(_ point: SnapPoint, into seen: inout [GridKey: SnapPoint]) {
        let k = gridKey(point.point)
        guard let existing = seen[k] else { seen[k] = point; return }

        // **주인은 언제나 합친다.** 어느 종류로 남든 "이 점을 누가 만들었는가"는 다 알아야 한다 —
        // 벽선 두 개가 한 점에서 끝나거나 모서리를 공유하는 것은 도면에서 흔하다.
        let owners = existing.owners.union(point.owners)
        let winner = rank(point.kind) > rank(existing.kind) ? point : existing
        seen[k] = SnapPoint(id: winner.id, point: winner.point, kind: winner.kind, owners: owners)
    }
}
