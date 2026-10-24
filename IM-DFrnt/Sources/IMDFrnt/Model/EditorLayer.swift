import Foundation

/// 명세 2항·4항의 레이어 네 종류를 하나의 타입으로 표현.
enum LayerKind: Hashable {
    case baseTop
    case baseGhost
    case attributeFilter(key: String, label: String)
    case propertyType(IMDFFeatureType)
}

struct EditorLayer: Identifiable, Hashable {
    let id: UUID
    let kind: LayerKind
    var isHidden: Bool = false
    var extraObjectIDs: Set<VectorObjectID> = []
    // 속성 필터 레이어에 사용자가 직접 추가한 개체(명세 2항)

    private var customOpacity: Double?
    /// 사용자가 조절한 투명도(2026-08-27 요청). `nil`이면 그 레이어의 기본값을 쓴다.
    ///
    /// **기본값을 덮어쓰지 않고 따로 두는 이유**는 하위 기본 레이어 때문이다.
    /// 그 레이어의 기본값(50%)은 사노 결정으로 정해진 수치라(명세 2-3, 2026-08-25),
    /// 사용자가 만졌다는 사실과 "기본이 얼마인가"를 섞으면 되돌릴 기준을 잃는다.

    init(id: UUID = UUID(), kind: LayerKind) {
        self.id = id
        self.kind = kind
    }

    var title: String {
        switch kind {
        case .baseTop: return "상위 기본 레이어"
        case .baseGhost: return "하위 기본 레이어 (원위치)"
        case .attributeFilter(_, let label): return "속성 필터 — \(label)"
        case .propertyType(let t): return t == .footprint ? "\(t.displayName) 레이어 · 전역" : "\(t.displayName) 레이어"
        }
    }

    var isClosable: Bool {
        switch kind {
        case .baseTop, .baseGhost: return false
        default: return true
        }
    }

    var isHidable: Bool {
        // 명세 2-3 원문은 "숨기기 불가능"이었으나 2026-08-25 뷰 디버깅 15번으로 뒤집었다 —
        // 이동이 재도입된 뒤로 하위 기본 레이어를 늘 띄워 두면 위치를 옮기지 않는 개체까지
        // 50%로 겹쳐 그려져 화면이 붐빈다. 숨기기·닫기 중 **숨기기만** 열었다 — 닫기(`isClosable`)는
        // 여전히 막는다. 이 레이어는 다른 레이어처럼 새로 만들거나 없앨 수 있는 대상이 아니라
        // 항상 존재해야 하는 기준 레이어이고, 그 성격은 "닫을 수 없다"로 지켜야 하기 때문이다.
        return true
    }

    var allowsObjectActions: Bool {
        if case .baseGhost = kind { return false }
        return true
    }

    /// 화면에 그릴 때 쓰는 투명도. 사용자가 조절했으면 그 값, 아니면 기본값.
    var opacity: Double { customOpacity ?? baseOpacity }

    /// 사용자가 조절했는가. '기본값으로' 버튼을 보일지 정하는 데 쓴다.
    var hasCustomOpacity: Bool { customOpacity != nil }

    mutating func setOpacity(_ value: Double?) {
        customOpacity = value.map { min(1.0, max(EditorLayer.minimumOpacity, $0)) }
        // **완전히 투명하게는 두지 않는다.** 0%로 내려가면 레이어가 사라진 것과 같은데,
        // 그건 '숨기기'가 할 일이다. 숨긴 것은 눈 아이콘으로 되돌릴 수 있지만
        // 투명도 0은 화면에서 이유를 알 수 없다.
    }

    static let minimumOpacity: Double = 0.05

    var baseOpacity: Double {
        // 사노 요청(2026-08-25, 03) 뷰 디버깅 4번)으로 20% → 50%.
        // 위치 이동을 다시 허용하면서, 원위치와 현재 위치가 갈라질 때 이 레이어로
        // 원위치를 확인하는 목적이 되살아났다 — 20%로는 옅어서 잘 안 보였다.
        if case .baseGhost = kind { return 0.5 }
        return 1.0
    }

    var propertyType: IMDFFeatureType? {
        if case .propertyType(let t) = kind { return t }
        return nil
    }
}

/// 캔버스의 상호작용 모드. 모드가 바뀌면 가능한 제스처가 통째로 달라진다.
enum InteractionMode: Hashable {
    case idle
    case displayPointPicking(FeatureGroupID)
    case ungroupedOnly
    case curvedOnly(showSegmentedOnly: Bool)
    case anchorPicking

    var blocksSelection: Bool {
        switch self {
        case .displayPointPicking, .anchorPicking: return true
        default: return false
        }
    }
    // 구 `blocksDragging`은 개체 이동과 함께 없앴다(2026-08-25).
    // 이제 드래그는 화면 팬뿐이라 어느 모드에서도 막을 이유가 없다.
}
