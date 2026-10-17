import Foundation

typealias FeatureGroupID = UUID

/// 사용자가 묶은 개체 묶음 = 장차 GeoJSON Feature 하나.
struct FeatureGroup: Identifiable, Hashable, Codable {
    let id: FeatureGroupID
    let featureType: IMDFFeatureType
    var serialNumber: String
    // 명세 7-1-2) "unit-001" 형식. id와 다른, 사용자 편의용 임시 일련번호.
    var memberIDs: Set<VectorObjectID>
    var properties: [String: PropertyValue]
    var displayPoint: LocalPoint?
    var isInTrash: Bool
    var createdAt: Date

    var closureSegment: LineSegment?
    /// '문 임시로 닫기'로 만든 opening의 선분(신기능 3항).
    ///
    /// **도면에 없는 선분이라 `memberIDs`로는 표현할 수 없다.** 열린 상태로 그려진 문에는
    /// 닫는 데 쓸 선이 아예 없어서 사용자가 두 점을 직접 찍는데, 그 결과는 개체가 아니라 좌표다.
    /// 이 값이 있으면 opening의 LineString 좌표는 **구성원이 아니라 이 선분**에서 나온다
    /// (`VertexExtractor` 참조). 구성원(문짝·호)은 "이 opening이 도면의 무엇을 소비했는가"를
    /// 남기는 쪽으로만 쓰인다 — 소유권과 진행률이 거기 걸린다.

    var polygonRings: [[LocalPoint]] = []
    /// 다각형 선택으로 고른 면들의 경계(신기능 5항).
    ///
    /// **여러 개인 이유는 fixture 때문이다.** fixture는 MultiPolygon이라 면 여러 개가 한 feature다.
    /// 폴리곤 type은 이 배열이 하나짜리다.
    ///
    /// 아래는 링을 정본으로 삼는 이유(단수였을 때의 설명 그대로다).
    ///
    /// **구성원 개체로 링을 다시 조립하지 않는 이유**는 옆방과 벽을 나눠 쓰기 때문이다.
    /// 맞닿은 벽선 하나를 두 방이 함께 쓰는 것은 도면에서 정상인데 소유권은 배타적이라
    /// (명세 4-1), 두 번째 방은 그 벽선을 구성원으로 가질 수 없다. 그 상태로 구성원만 이으면
    /// 벽 하나가 빠진 열린 링이 된다. 화면에서 이미 닫혀 있다고 확인하고 고른 면이므로
    /// **그때 본 좌표를 그대로 정본으로 삼는다**(`VertexExtractor` 참조).

    var polygonFaceIDs: Set<String> = []
    /// 그 면들의 신원. 같은 면을 두 번 저장하는 것을 막는 데만 쓴다.

    var drawnVertices: [LocalPoint]?
    /// 점 단위 편집으로 그린 Point·LineString의 좌표(#21). Point는 하나, LineString은 둘 이상이다.
    /// 폴리곤은 `polygonRings`에 담는다 — 링 정본이 이미 거기 있어서 내보내기 경로를 하나로 유지한다.
    ///
    /// **선택적(Optional)인 이유**는 이전에 저장한 프로젝트 파일에 이 키가 없기 때문이다.
    /// 기본값을 둔 비선택 필드는 키가 없으면 해독에 실패한다.

    var multiPolygon: Bool?
    /// 우측 패널에서 MultiPolygon으로 지정한 면 feature. 링들의 포함 관계로 구멍을 정한다(`RingNesting`).
    /// fixture는 type 자체가 MultiPolygon이라 이 값 없이도 MultiPolygon이다. 이전 파일을 위해 선택적이다.

    /// 원본 SVG 개체와 무관하게 점으로 그린 feature인가.
    var isPointDrawn: Bool { memberIDs.isEmpty && (drawnVertices != nil || (!polygonRings.isEmpty && polygonFaceIDs.isEmpty)) }

    init(id: FeatureGroupID = UUID(),
         featureType: IMDFFeatureType,
         serialNumber: String,
         memberIDs: Set<VectorObjectID>) {
        self.id = id
        self.featureType = featureType
        self.serialNumber = serialNumber
        self.memberIDs = memberIDs
        self.properties = [:]
        self.displayPoint = nil
        self.isInTrash = false
        self.createdAt = Date()
        self.closureSegment = nil
        self.polygonRings = []
        self.polygonFaceIDs = []
    }

    func value(_ key: String) -> PropertyValue {
        properties[key] ?? .null
        // 기본값 null(명세 7-3-3).
    }
}

/// 명세 4-1) 경고창에 넣을 정보.
struct ConflictInfo {
    let objectID: VectorObjectID
    let ownerFeature: FeatureGroupID
    let ownerType: IMDFFeatureType
    let ownerSerial: String
}
