import CoreGraphics
import Foundation
import SwiftUI

typealias VectorObjectID = UUID

struct RGBAColor: Hashable, Sendable {
    var r: Double, g: Double, b: Double, a: Double

    var swiftUI: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    /// "같은 속성 모아보기" 비교용 양자화 키. 부동소수 오차를 흡수한다.
    var key: String {
        String(format: "%.0f-%.0f-%.0f-%.2f", r * 255, g * 255, b * 255, a)
    }
}

struct VectorStyle: Hashable, Sendable {
    var stroke: RGBAColor?
    var fill: RGBAColor?
    var strokeWidth: Double
    var dashPattern: [Double]

    static let `default` = VectorStyle(
        stroke: RGBAColor(r: 0.15, g: 0.15, b: 0.18, a: 1),
        fill: nil,
        strokeWidth: 1,
        dashPattern: []
    )

    /// 이 값이 같은 개체끼리 하나의 속성 필터 레이어로 묶인다(명세 2항).
    var attributeKey: String {
        let s = stroke?.key ?? "none"
        let f = fill?.key ?? "none"
        let d = dashPattern.map { String(format: "%.1f", $0) }.joined(separator: ",")
        return "s:\(s)|f:\(f)|w:\(String(format: "%.2f", strokeWidth))|d:\(d)"
    }

    var humanDescription: String {
        var parts: [String] = []
        if let stroke { parts.append("선 \(stroke.hex)") }
        if let fill { parts.append("면 \(fill.hex)") }
        parts.append("두께 \(String(format: "%.1f", strokeWidth))")
        if !dashPattern.isEmpty { parts.append("점선") }
        return parts.joined(separator: " · ")
    }
}

extension RGBAColor {
    var hex: String {
        String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

/// SVG에서 읽은 개체 하나. **불변** — 어떤 코드도 문서에서 이 원소를 제거하지 않는다(명세 2항).
struct VectorObject: Identifiable, Hashable, Sendable {
    let id: VectorObjectID
    let geometry: PathGeometry
    let style: VectorStyle
    let sourceElement: String
    let ordinal: Int
    // 파싱 순서. 화면 표시 이름(#12)에 쓴다.

    var boundingBox: CGRect { geometry.boundingBox }
    var isCurved: Bool { geometry.isCurved }
    var displayName: String { "#\(ordinal) \(sourceElement)" }

    /// "똑같이 생긴 개체" 판정 키(명세 디버깅 6번).
    /// 도면의 보조 개체(치수 숫자, 해칭, 방위 표시)는 같은 모양이 위치만 달리해 수십 개씩 흩어져 있다.
    /// 그래서 **위치는 빼고** 모양과 스타일만 본다 — bounding box 원점으로 평행이동한 뒤의 좌표를 쓴다.
    var twinKey: String {
        let box = boundingBox
        var parts: [String] = ["e:\(sourceElement)", "s:\(style.attributeKey)"]
        for sp in geometry.subpaths {
            parts.append(sp.isClosed ? "Z" : "O")
            for p in sp.points {
                parts.append(String(format: "%.2f,%.2f", p.x - box.minX, p.y - box.minY))
            }
        }
        return parts.joined(separator: "|")
        // 좌표를 0.01 단위로 반올림하는 이유는 SVG 파서가 만든 부동소수 오차 때문이다.
        // 눈으로 같은 모양이면 같은 키가 나와야 한다.
    }

    /// 목록에 보여줄 짧은 모양 설명.
    var shapeSummary: String {
        let box = boundingBox
        return String(format: "%@ · %.0f×%.0f", sourceElement, box.width, box.height)
    }
}

struct DrawingDocument: Sendable {
    let objects: [VectorObject]
    let canvasSize: CGSize
    let sourceName: String
    let rasterImages: [DrawingRasterImage]
    let fingerprint: String

    private let index: [VectorObjectID: Int]

    init(objects: [VectorObject], canvasSize: CGSize, sourceName: String, rasterImages: [DrawingRasterImage] = []) {
        self.objects = objects
        self.canvasSize = canvasSize
        self.sourceName = sourceName
        self.rasterImages = rasterImages
        self.fingerprint = Self.makeFingerprint(objects: objects, rasterImages: rasterImages)
        var map: [VectorObjectID: Int] = [:]
        for (i, o) in objects.enumerated() { map[o.id] = i }
        self.index = map
    }

    func object(_ id: VectorObjectID) -> VectorObject? {
        guard let i = index[id] else { return nil }
        return objects[i]
    }

    var curvedObjectIDs: Set<VectorObjectID> {
        Set(objects.filter(\.isCurved).map(\.id))
    }
}
