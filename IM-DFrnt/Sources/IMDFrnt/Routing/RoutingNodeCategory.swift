import SwiftUI

/// Presentation choices; the project and client export keep the original category strings.
enum RoutingNodeCategory: String, CaseIterable {
    case waypoint, entrance, stairs, elevator, destination

    var title: String {
        switch self {
        case .waypoint: "통로·교차점"
        case .entrance: "출입구"
        case .stairs: "계단"
        case .elevator: "엘리베이터"
        case .destination: "목적지"
        }
    }

    var color: Color {
        switch self {
        case .waypoint: .blue
        case .entrance: .green
        case .stairs: .orange
        case .elevator: .purple
        case .destination: .pink
        }
    }

    static func color(for category: String) -> Color {
        Self(rawValue: category)?.color ?? .blue
    }
}
