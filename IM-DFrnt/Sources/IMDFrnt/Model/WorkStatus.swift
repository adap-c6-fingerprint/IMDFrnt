import SwiftUI

/// feature type 레이어의 작업 상태(신기능 12항). 사용자가 직접 고른다 — "검토 중"처럼 앱이 판단할 수 없는 값이 있다.
///
/// 층에 귀속되는 type은 층마다, 정보만 입력하는 type(address·building·manifest·occupant)은 프로젝트에 하나씩 둔다.
enum LayerWorkStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case complete, inReview, inProgress, todo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .complete: return "Complete"
        case .inReview: return "In Review"
        case .inProgress: return "In Progress"
        case .todo: return "Todo"
        }
    }

    var systemImage: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        case .inReview: return "magnifyingglass"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .todo: return "circle"
        }
    }

    var color: Color {
        switch self {
        case .complete: return .green
        case .inReview: return .blue
        case .inProgress: return .yellow
        case .todo: return .red
        }
    }

    /// 완료에 가까운 순서. 완료 순·미완료 순 정렬의 기준이다.
    var progressRank: Int {
        switch self {
        case .complete: return 0
        case .inReview: return 1
        case .inProgress: return 2
        case .todo: return 3
        }
    }
}

/// 좌측 Feature Type 목록의 정렬 기준. `custom`은 사용자가 드래그로 정한 순서다.
enum FeatureTypeSort: String, CaseIterable, Identifiable {
    case custom, completeFirst, incompleteFirst, recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom: return "사용자 지정"
        case .completeFirst: return "완료 순"
        case .incompleteFirst: return "미완료 순"
        case .recent: return "최근 작업 순"
        }
    }
}
