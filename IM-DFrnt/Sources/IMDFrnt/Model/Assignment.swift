import CoreGraphics
import Foundation

/// 다른 사람에게 넘긴 작업 몫(신기능 1-2). `.imdfrnt` 안에 함께 담긴다.
///
/// **이 구조체가 신기능 1-2-6의 요구를 담는 자리다.**
/// "기존 도면을 어떤 방향으로 잘랐는지, 다시 붙일 때는 어떻게 붙일지"를 기억해야 한다는 것인데,
/// 잘린 조각을 따로 들고 다니는 방식이 아니라 **원본 도면 전체 + 담당 구역 표시**로 푼다.
///
/// - 조각을 잘라 보내면 B는 주변 맥락을 잃는다. 방 하나를 태깅하려면 옆방 벽선이 보여야 한다.
/// - 잘라 보낸 조각을 다시 붙이려면 좌표를 맞추는 계산이 필요하고, 그 계산이 틀리면 조용히 어긋난다.
/// - 도면 전체를 보내고 "여기부터 여기까지가 당신 몫"만 표시하면, 좌표계가 처음부터 하나뿐이라
///   붙일 때 맞출 것이 없다. **가장 안전한 재조립은 재조립을 안 하는 것이다.**
struct Assignment: Codable, Equatable, Identifiable {

    var id: UUID
    /// 이 배정본 자체의 식별자. 같은 파일을 두 번 합치는 것을 막는다.

    var projectID: UUID
    /// 원본 작업의 식별자. 배정본은 전부 이 값을 물려받는다 —
    /// 다른 작업에서 온 파일을 합치면 남의 태깅이 내 도면에 섞인다.

    var drawingFingerprint: String
    /// 도면 지문(`DrawingDocument.fingerprint`). `projectID`가 같아도 도면을 바꿔 열었으면
    /// 개체 id가 통째로 달라진다. 그 경우를 걸러내는 두 번째 자물쇠다.

    var assignee: String
    /// 담당자 표시용 이름. 합칠 때 "누구 몫이 들어왔는지" 알려주는 데만 쓴다.

    var objectIDs: Set<VectorObjectID>
    /// 담당 개체. 배정본을 연 사람은 **이 안의 개체만** 고를 수 있다.

    var bounds: CGRect
    /// 담당 개체를 감싸는 도면 좌표 범위. 화면에 담당 구역을 표시하는 데 쓴다.
    /// `objectIDs`가 정본이고 이 값은 그로부터 유도된다 — 둘이 어긋나면 `objectIDs`를 따른다.

    var createdAt: Date
    /// Nil for old single-drawing assignments.
    var levelID: UUID?

    var isEmpty: Bool { objectIDs.isEmpty }

    var summary: String {
        let who = assignee.trimmingCharacters(in: .whitespaces)
        return "\(who.isEmpty ? "담당자 미지정" : who) · 개체 \(objectIDs.count)개"
    }

    static func bounds(of ids: Set<VectorObjectID>, in doc: DrawingDocument) -> CGRect {
        let boxes = ids.compactMap { doc.object($0)?.boundingBox }
        guard let first = boxes.first else { return .zero }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
}

/// 배정본을 합친 결과. 사용자에게 무엇이 들어오고 무엇이 막혔는지 그대로 보여준다.
///
/// **조용히 넘어가지 않는 것이 이 구조체의 존재 이유다.** 합치기는 남의 작업을 내 작업에
/// 섞는 일이라, 뭔가 빠졌는데 아무 말도 없으면 나중에 내보내기 단계에서야 발견하게 된다.
struct MergeReport {
    var acceptedFiles: [String] = []
    var acceptedFeatures = 0
    var acceptedExclusions = 0
    var acceptedSegmentations = 0

    /// 배정 범위 밖을 건드린 feature. 담당 몫이 아닌 개체를 태깅한 것이라 받지 않는다.
    var outOfScopeFeatures: [String] = []
    /// 이미 이쪽에서 주인이 정해진 개체를 태깅한 feature.
    var conflictingFeatures: [String] = []
    /// 아예 열지 못한 파일과 이유.
    var rejectedFiles: [(name: String, reason: String)] = []

    var isEmpty: Bool {
        acceptedFiles.isEmpty && rejectedFiles.isEmpty
    }

    var message: String {
        var lines: [String] = []
        if !acceptedFiles.isEmpty {
            lines.append("합친 파일 \(acceptedFiles.count)개 — feature \(acceptedFeatures)개, 보조 개체 \(acceptedExclusions)개, 선분화 \(acceptedSegmentations)개를 가져왔습니다.")
        }
        if !conflictingFeatures.isEmpty {
            lines.append("이미 이쪽에서 저장된 개체를 쓰고 있어 건너뛴 feature \(conflictingFeatures.count)개: \(conflictingFeatures.prefix(5).joined(separator: ", "))")
        }
        if !outOfScopeFeatures.isEmpty {
            lines.append("담당 구역 밖 개체를 쓰고 있어 건너뛴 feature \(outOfScopeFeatures.count)개: \(outOfScopeFeatures.prefix(5).joined(separator: ", "))")
        }
        for r in rejectedFiles {
            lines.append("\(r.name): \(r.reason)")
        }
        return lines.joined(separator: "\n\n")
    }
}
