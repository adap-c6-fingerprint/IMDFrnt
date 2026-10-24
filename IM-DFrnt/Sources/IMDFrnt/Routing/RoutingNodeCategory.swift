import SwiftUI

/// Presentation choices; the project and client export keep the original category strings.
enum RoutingNodeCategory: String, CaseIterable {
    case waypoint, entrance, stairs, elevator, escalator, destination

    var title: String {
        switch self {
        case .waypoint: "통로·교차점"
        case .entrance: "출입구"
        case .stairs: "계단"
        case .elevator: "엘리베이터"
        case .escalator: "에스컬레이터"
        case .destination: "목적지"
        }
    }

    var color: Color {
        switch self {
        case .waypoint: .blue
        case .entrance: .green
        case .stairs: .orange
        case .elevator: .purple
        case .escalator: .teal
        case .destination: .pink
        }
    }

    /// 기준 노드 하나로 모든 층에 같은 좌표의 노드를 만들 수 있는 수직 이동 시설.
    var isVertical: Bool { self == .stairs || self == .elevator || self == .escalator }

    static func color(for category: String) -> Color {
        Self(rawValue: category)?.color ?? .blue
    }
}
