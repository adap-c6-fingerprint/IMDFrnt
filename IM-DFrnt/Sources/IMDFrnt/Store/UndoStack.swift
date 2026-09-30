import Foundation

/// 실행취소 한 걸음이 되돌리는 상태 전부(명세 디버깅 8번).
///
/// **명령별 역연산 대신 통째 스냅샷을 고른 이유:** 이 앱의 작업 단위는 서로 얽혀 있다.
/// feature 하나를 저장하면 `features`·`ownership`·`serials`·`selection`·`expandedFeature`가
/// 함께 바뀌고, 그룹 해제는 거기에 `ids`(폐기 UUID 대장)까지 건드린다.
/// 역연산을 명령마다 따로 쓰면 새 명령을 추가할 때마다 되돌리기를 빠뜨리게 되고,
/// 그 실패는 "되돌렸는데 소유권만 남아 있다" 같은 조용한 상태 붕괴로 나타난다.
///
/// 스냅샷이 감당 가능한 이유는 **`DrawingDocument`가 여기 없기 때문**이다.
/// 개체 원본(좌표·스타일)은 불변이라 절대 바뀌지 않으므로 스냅샷에서 제외한다.
/// 남는 것은 개체 수에 비례하는 작은 사전·집합뿐이다.
struct EditorSnapshot: Equatable {
    var layers: LayerStore
    var features: FeatureStore
    var ownership: OwnershipRegistry
    var selection: SelectionStore
    var segmentation: SegmentationStore
    var auxiliary: AuxiliaryStore
    var openingGate: OpeningGateStore
    var borrow: BorrowRegistry
    // 게이트와 대여도 되돌아가야 한다. 대여가 안 돌아오면 실행취소 뒤 폴리곤이 열린 채 남는다.
    var anchors: AnchorStore
    var doorClosures: DoorClosureStore
    /// 임시 문도 되돌림 대상이다(신기능 3항). **빠뜨리면 `perform`이 "바뀐 게 없다"고 판단해
    /// 실행취소 칸을 도로 버린다** — cmd+z를 눌러도 아무 일이 안 일어나는 종류의 버그다.
    var serials: SerialNumberAllocator
    var ids: IDAssigner
    var expandedFeatures: Set<FeatureGroupID>
    var focusedFeature: FeatureGroupID?
    var faceSelection: Set<String>
    /// 고른 면(신기능 5-4). 저장하면 선택이 비워지므로, 되돌렸을 때 고르던 것이
    /// 그대로 돌아와야 "저장을 취소했다"가 성립한다.
    // 카드를 여러 개 펼 수 있게 된 뒤로 한 칸이 아니라 집합이다(2026-08-26).
}

/// cmd+z / cmd+shift+z(명세 디버깅 8번).
struct UndoStack {

    struct Entry: Equatable {
        let name: String
        let coalescingKey: String?
        let snapshot: EditorSnapshot
        // 이 명령을 **실행하기 직전**의 상태다. 되돌린다는 건 이 값으로 돌아간다는 뜻.
    }

    /// 스냅샷이 상태 전체라 무한정 쌓으면 큰 도면에서 메모리를 먹는다.
    /// 60이면 한 세션에서 실수를 되짚기에 충분하면서 상한이 예측 가능하다.
    static let limit = 60

    private(set) var undoEntries: [Entry] = []
    private(set) var redoEntries: [Entry] = []

    var canUndo: Bool { !undoEntries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }

    var undoName: String? { undoEntries.last?.name }
    var redoName: String? { redoEntries.last?.name }

    /// `coalescingKey`가 직전 항목과 같으면 새로 쌓지 않는다.
    /// 속성 입력칸은 **글자 하나마다** `updateProperty`가 불리므로, 합치지 않으면
    /// "unit-001 이름" 한 번 입력에 실행취소가 10칸 쌓여 스택이 쓸모없어진다.
    /// 직전 항목이 이미 입력 시작 전 상태를 들고 있으므로, 합쳐도 되돌아갈 지점은 정확하다.
    mutating func record(_ name: String, coalescingKey: String?, before: EditorSnapshot) {
        if let key = coalescingKey, undoEntries.last?.coalescingKey == key {
            redoEntries.removeAll()
            return
        }
        undoEntries.append(Entry(name: name, coalescingKey: coalescingKey, snapshot: before))
        if undoEntries.count > Self.limit { undoEntries.removeFirst() }
        redoEntries.removeAll()
        // 새 작업을 하면 다시실행 가지는 버린다. 갈라진 미래를 남겨두면 어느 쪽으로 가는지 알 수 없다.
    }

    /// 방금 쌓은 항목을 취소한다. 명령이 아무것도 바꾸지 않았을 때 쓴다 —
    /// 빈 실행취소 칸이 쌓이면 cmd+z를 눌러도 화면이 안 바뀌는 것처럼 보인다.
    mutating func discardLast() {
        _ = undoEntries.popLast()
    }

    mutating func undo(current: EditorSnapshot) -> Entry? {
        guard let entry = undoEntries.popLast() else { return nil }
        redoEntries.append(Entry(name: entry.name, coalescingKey: nil, snapshot: current))
        return entry
    }

    mutating func redo(current: EditorSnapshot) -> Entry? {
        guard let entry = redoEntries.popLast() else { return nil }
        undoEntries.append(Entry(name: entry.name, coalescingKey: nil, snapshot: current))
        return entry
    }

    mutating func clear() {
        undoEntries.removeAll()
        redoEntries.removeAll()
    }
}
