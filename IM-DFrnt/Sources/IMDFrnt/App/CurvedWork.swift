import Foundation

/// '곡선 개체만 따로 보기' 전용 창(명세 3-3).
///
/// **왜 별도 창인가 — 2026-08-27에 창으로 바꾼 이유:**
/// 원래 이 기능은 메인 캔버스 위의 '모드'였고, 눌렀을 때의 변화가 **곡선 아닌 개체를 75%로
/// 옅게 하는 것뿐**이었다. 그 차이는 눈에 거의 띄지 않아 사용자에게는 "눌러도 아무 일이
/// 일어나지 않는" 버튼으로 읽혔다. 게다가 폴리곤 type 레이어가 면 선택 화면이 된 뒤로는
/// **클릭이 면을 고르므로 곡선 개체를 고를 수조차 없었다** — 선분화 대상을 지정하는 것이
/// 이 기능의 목적인데 그 경로가 막혀 있었다.
/// 명세 3-3의 원문도 "창이 열림"이다. 보조 개체 제외·문 임시로 닫기와 같은 전용 창으로 맞춘다.
@MainActor
extension AppEnvironment {

    var canEnterCurvedScreen: Bool { document != nil && curvedObjectCount > 0 }

    func enterCurvedScreen() {
        guard document != nil else {
            notify("먼저 도면을 여세요.", isError: true)
            return
        }
        guard curvedObjectCount > 0 else {
            notify("이 도면에는 곡선 개체가 없습니다.", isError: true)
            // 아무 일도 일어나지 않으면 고장으로 읽힌다 — 왜 안 열리는지 말해 준다.
            return
        }
        selection.clear()
        marqueeSubtracts = false // ✅ 2026-08-30 — 모드는 화면을 넘어가지 않는다.
        mode = .curvedOnly(showSegmentedOnly: false)
        // 표시 규칙(곡선 아닌 개체 75%, 선분화 여부 50/100%)은 종전 모드가 이미 갖고 있다.
        // 창은 그 규칙을 **넓은 화면에서 방해 없이** 쓰기 위한 그릇이다.
        showCurvedScreen = true
    }

    func exitCurvedScreen() {
        showCurvedScreen = false
        mode = .idle
        marqueeSubtracts = false // ✅ 2026-08-30
        selection.clear()
        // 창을 나가면서 선택을 남기면, 메인 화면에서 곡선 개체가 골라진 채로 시작한다 —
        // 그 상태에서 'Feature로 저장'을 누르면 의도하지 않은 태깅이 된다.
    }

    /// 창 안의 '선분화된 곡선 개체만 보기' 토글(명세 3-3-3).
    var curvedShowsSegmentedOnly: Bool {
        if case .curvedOnly(let only) = mode { return only }
        return false
    }

    func setCurvedShowsSegmentedOnly(_ on: Bool) {
        mode = .curvedOnly(showSegmentedOnly: on)
        // 같은 창 안의 하위 토글이라 선택을 비우지 않는다 — 창을 나가는 것이 아니다.
    }

    /// 이 창에서 고를 수 있는 것은 **곡선 개체뿐**이다(명세 3-3-2).
    /// 직선까지 고를 수 있으면 '선택 선분화'가 아무 일도 하지 않는 경우가 생겨,
    /// 사용자는 기능이 고장 난 것으로 읽는다.
    func handleCurvedScreenClick(at point: LocalPoint, tolerance: Double) {
        guard let doc = document else { return }
        let curved = doc.objects.filter { $0.isCurved && !auxiliary.isExcluded($0.id) }
        guard let hit = HitTester.hitTest(point, candidates: curved,
                                          cached: renderCache.geometryProvider(segmentation),
                                          tolerance: tolerance) else { return }
        selection.toggle(hit)
    }

    func handleCurvedScreenMarquee(rect: CGRect, mode marqueeMode: HitTester.MarqueeMode) {
        guard let doc = document else { return }
        let curved = doc.objects.filter { $0.isCurved && !auxiliary.isExcluded($0.id) }
        let hits = HitTester.objects(in: rect, mode: marqueeMode, candidates: curved,
                                     cached: renderCache.geometryProvider(segmentation))
        guard !hits.isEmpty else { return }

        // ✅ 2026-08-30 추가 — 빼기 모드.
        if marqueeSubtracts {
            let removed = hits.filter { selection.selected.contains($0) }
            guard !removed.isEmpty else {
                notify("사각형 안에 해제할 곡선 개체가 없습니다.")
                return
            }
            var next = selection.selected
            next.subtract(removed)
            selection.selected = next
            notify("곡선 개체 \(removed.count)개 선택 해제")
            return
        }

        var next = selection.selected
        next.formUnion(hits)
        selection.selected = next
        // 한 번에 대입한다(`03) 뷰 디버깅.md` 17번).
        notify("곡선 개체 \(hits.count)개를 선택했습니다.")
    }

    /// 지금 선택 중인 곡선 개체 수. 창의 상단바가 남은 일을 보여주는 근거다.
    var curvedSelectionCount: Int {
        guard let doc = document else { return 0 }
        return selection.selected.filter { doc.object($0)?.isCurved == true }.count
    }
}
