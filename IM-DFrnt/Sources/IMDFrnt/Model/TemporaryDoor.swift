import CoreGraphics
import Foundation

/// '문 임시로 닫기'로 만든 opening 하나(신기능 3항).
///
/// **왜 이 기능이 필요한가:** 실제 도면의 방은 문 자리에서 벽이 끊겨 있다. 그 상태로는
/// unit·footprint 같은 닫힌 폴리곤을 만들 수 없다(명세 10-1). 종전에는 opening 개체를
/// 다른 feature가 **빌려서**(`BorrowRegistry`) 링을 닫았는데, 그건 도면에 문선이 그려져 있을 때 얘기다.
/// 문이 **열린 상태로** 그려진 도면에는 닫는 데 쓸 선분 자체가 없다 — 문짝과 회전 궤적(호)만 있다.
///
/// 그래서 사용자가 **끊긴 자리의 두 점을 직접 찍어** 없는 선분을 만든다. 그게 `start`~`end`다.
/// 그 선분이 곧 IMDF opening의 LineString 좌표가 된다(opening의 geometry는 LineString).
struct TemporaryDoor: Identifiable, Codable, Equatable {

    let id: UUID

    var start: LocalPoint
    var end: LocalPoint
    /// 사용자가 찍은 점 쌍. **도면에 없는 선분이라 개체 id로 가리킬 수 없다.**
    /// 좌표를 직접 들고 있는 것은 그래서다.

    var doorObjectID: VectorObjectID
    /// 열린 상태로 그려진 문짝.

    var arcObjectID: VectorObjectID
    /// 그 문의 회전 궤적(호).

    var createdAt: Date

    /// 문짝과 호. 이 둘은 opening feature의 구성원이 되어 진행률에 기여한다(신기능 3-7).
    var consumedObjectIDs: Set<VectorObjectID> { [doorObjectID, arcObjectID] }

    var segment: LineSegment { LineSegment(start: start, end: end) }

    var length: Double { start.distance(to: end) }

    var label: String {
        String(format: "문 %.0f×%.0f — 길이 %.1f",
               abs(end.x - start.x), abs(end.y - start.y), length)
    }
}

/// 아직 Openings 레이어에 반영하지 않은 임시 문 목록(신기능 3-5·3-6).
///
/// **레이어 반영을 한 번 더 나눈 이유는 명세가 그렇게 요구하기 때문이고, 그게 맞기도 하다.**
/// 문 하나를 만들 때마다 레이어에 바로 들어가면, 도면 전체를 훑으며 수십 개를 찍는 동안
/// 우측 인스펙터가 계속 흔들리고 실행취소 칸이 문 개수만큼 쌓인다.
/// 여기 모아 두고 마지막에 한 번에 넘긴다.
struct DoorClosureStore: Equatable, Codable {

    private(set) var doors: [TemporaryDoor] = []

    var isEmpty: Bool { doors.isEmpty }
    var count: Int { doors.count }

    /// 임시 문들이 쓰고 있는 개체 전부. 진행률과 중복 선택 판정이 이 값을 본다.
    var consumedObjectIDs: Set<VectorObjectID> {
        doors.reduce(into: Set<VectorObjectID>()) { $0.formUnion($1.consumedObjectIDs) }
    }

    func door(_ id: UUID) -> TemporaryDoor? { doors.first { $0.id == id } }

    /// 이 개체를 이미 어떤 임시 문이 쓰고 있는가.
    /// 같은 문짝을 두 opening이 나눠 갖는 상황은 도면상 있을 수 없다.
    func user(of object: VectorObjectID) -> TemporaryDoor? {
        doors.first { $0.consumedObjectIDs.contains(object) }
    }

    mutating func insert(_ door: TemporaryDoor) { doors.append(door) }

    mutating func remove(_ id: UUID) { doors.removeAll { $0.id == id } }

    mutating func clear() { doors.removeAll() }
}

/// '문 임시로 닫기' 창의 표시 수치(신기능 3-1).
/// 뷰에서 떼어낸 이유는 검증 때문이다 — 명세가 요구한 20%가 뷰 안에 박혀 있으면
/// `--selftest`가 확인할 방법이 없다.
enum DoorClosureAppearance {

    static let excludedOpacity: Double = 0.2
    /// 제외된 보조 개체(신기능 3-1). **`EditorLayer.baseOpacity`를 빌려 쓰면 안 된다** —
    /// 그 값은 하위 기본 레이어용이고 2026-08-25에 사노 요청으로 20% → 50%로 바뀌었다.
    /// 두 수치가 우연히 같았다고 한 곳에 묶으면, 한쪽 요구가 바뀔 때 다른 쪽이 조용히 끌려간다.

    static let activeOpacity: Double = 1.0
}
