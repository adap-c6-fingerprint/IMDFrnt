import Foundation

/// "같은 속성의 벡터만 모아보기"(명세 2항)의 근거가 되는 파일.
/// 프레젠테이션 속성 + `style` 속성 + 부모 상속을 합쳐 최종 스타일을 만든다.
/// CSS `<style>` 블록 셀렉터는 1차 범위 밖(확인 필요).
enum StyleResolver {

    struct Inherited {
        var stroke: String?
        var fill: String?
        var strokeWidth: String?
        var dash: String?
        var opacity: String?
    }

    static func merge(_ parent: Inherited, attributes: [String: String]) -> Inherited {
        var out = parent
        let inline = parseStyleAttribute(attributes["style"] ?? "")
        func pick(_ key: String) -> String? { inline[key] ?? attributes[key] }
        if let v = pick("stroke") { out.stroke = v }
        if let v = pick("fill") { out.fill = v }
        if let v = pick("stroke-width") { out.strokeWidth = v }
        if let v = pick("stroke-dasharray") { out.dash = v }
        if let v = pick("opacity") { out.opacity = v }
        return out
    }

    static func resolve(_ inherited: Inherited, defaultStrokeIfNone: Bool = true) -> VectorStyle {
        let alpha = inherited.opacity.flatMap(Double.init) ?? 1.0
        var stroke = color(inherited.stroke, alpha: alpha)
        let fill = color(inherited.fill, alpha: alpha)
        if stroke == nil && fill == nil && defaultStrokeIfNone {
            stroke = VectorStyle.default.stroke
            // stroke도 fill도 없으면 화면에서 사라지므로 기본 선을 준다.
        }
        let width = inherited.strokeWidth.flatMap { Double($0.replacingOccurrences(of: "px", with: "")) } ?? 1
        let dash = (inherited.dash ?? "").split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Double($0) }
        return VectorStyle(stroke: stroke, fill: fill, strokeWidth: width, dashPattern: dash)
    }

    private static func parseStyleAttribute(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for decl in s.split(separator: ";") {
            let parts = decl.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            out[parts[0].trimmingCharacters(in: .whitespaces)] =
                parts[1].trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    static func color(_ raw: String?, alpha: Double = 1) -> RGBAColor? {
        guard var s = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        if s == "none" || s == "transparent" { return nil }
        if let named = namedColors[s] { s = named }
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
            return RGBAColor(r: Double((v >> 16) & 0xFF) / 255,
                             g: Double((v >> 8) & 0xFF) / 255,
                             b: Double(v & 0xFF) / 255,
                             a: alpha)
        }
        if s.hasPrefix("rgb") {
            let nums = s.drop(while: { $0 != "(" }).dropFirst().dropLast()
                .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if nums.count >= 3 {
                return RGBAColor(r: nums[0] / 255, g: nums[1] / 255, b: nums[2] / 255,
                                 a: nums.count > 3 ? nums[3] : alpha)
            }
        }
        return nil
    }

    private static let namedColors: [String: String] = [
        "black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000",
        "blue": "#0000ff", "gray": "#808080", "grey": "#808080", "silver": "#c0c0c0",
        "orange": "#ffa500", "purple": "#800080", "brown": "#a52a2a", "navy": "#000080",
        "teal": "#008080", "olive": "#808000", "maroon": "#800000", "lime": "#00ff00",
        "aqua": "#00ffff", "cyan": "#00ffff", "magenta": "#ff00ff", "fuchsia": "#ff00ff",
        "yellow": "#ffff00", "pink": "#ffc0cb", "gold": "#ffd700",
    ]
}
