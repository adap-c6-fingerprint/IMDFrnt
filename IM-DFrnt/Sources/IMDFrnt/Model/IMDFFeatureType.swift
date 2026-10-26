import Foundation

/// Apple IMDF 1.0.0의 Feature 16종과 별도 manifest 편집 항목.
enum IMDFFeatureType: String, CaseIterable, Identifiable, Codable, Hashable {
    case address, amenity, anchor, building, detail, fixture, footprint, geofence, kiosk
    case level, manifest, occupant, opening, relationship, section, unit, venue

    var id: String { rawValue }

    var displayName: String { rawValue }

    var serialPrefix: String { rawValue }

    /// `01) geojson 파일별 properties 구조.md`의 geometry 열 그대로.
    var requiredGeometry: GeoJSONGeometryKind {
        switch self {
        case .address, .occupant, .building, .manifest, .relationship: return .none
        case .amenity, .anchor: return .point
        case .opening, .detail: return .lineString
        case .fixture: return .multiPolygon
        case .footprint, .geofence, .kiosk, .level, .section, .unit, .venue: return .polygon
        }
    }

    /// display point 찍기 버튼 노출 조건(명세 7-3-4).
    var hasDisplayPoint: Bool {
        switch self {
        case .amenity, .building, .fixture, .geofence, .kiosk, .level, .opening, .section, .unit, .venue: return true
        default: return false
        }
    }

    /// 명세 10-2-4) 문 빌려주기 대상 — 닫힌 폴리곤이 필요한 type만 해당한다.
    /// Point(amenity·anchor)·null(address·occupant·building)·LineString(opening 자신)은 제외.
    /// 닫힌 폴리곤이 필요한 type인가. 빌려주기 대상 판정(명세 10-2-4)과 링 검증(10-4)이 함께 쓴다.
    var requiresClosedRing: Bool {
        requiredGeometry == .polygon || requiredGeometry == .multiPolygon
    }

    /// 면 단위 선택을 쓸 수 있는가(#21). polygon·multipolygon type만 되고 footprint는 뺀다 —
    /// 건물 외곽은 도면의 면 하나로 떨어지지 않는 경우가 많아 점으로 직접 그린다(10번 지침).
    var allowsFaceSelection: Bool { requiresClosedRing && self != .footprint }

    /// 도형 없이 정보(속성)만 갖는 type인가. 레이어를 만들지 않고 입력 창에서 값을 넣는다(2026-10-19 요청).
    var isMetadataOnly: Bool { requiredGeometry == .none }

    /// 선 단위(도면 개체를 골라 feature로 묶기)를 쓸 수 있는가. fixture만이다(2026-10-19 요청).
    var allowsObjectSelection: Bool { self == .fixture }

    var canBorrowOpenings: Bool {
        switch requiredGeometry {
        case .polygon, .multiPolygon: return true
        default: return false
        }
    }

    var note: String {
        switch self {
        case .geofence:
            return "OGC 스펙에 \"A Geofence models the extent of a geofence.\" 외 설명이 없다. 용도는 category 열거값으로 추정."
        case .section:
            return "테마의 대략적 범위. 경계가 물리적 벽이 아닐 수 있고, 아래 walkway가 보이도록 gap을 둘 수 있다."
        case .anchor:
            return "주소·입주자의 대표 표시 지점. 지오레퍼런싱 Anchor과 무관하다."
        case .manifest:
            return "피처 파일이 아니라 세트 메타데이터."
        default:
            return ""
        }
    }
}
