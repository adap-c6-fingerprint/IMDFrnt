import CryptoKit
import Foundation

/// 개체 id를 **도면 내용에서 결정적으로** 뽑는다(신기능 1-2-6).
///
/// **이것이 작업 공유의 전제다.** 예전에는 파싱할 때마다 `UUID()`를 새로 발급했다.
/// 그러면 같은 SVG를 A와 B가 각자 열어도 개체 id가 서로 달라, B가 태깅한 결과를
/// A의 작업에 도로 붙일 방법이 없다 — 어느 개체를 태깅한 것인지 가리킬 이름이 없기 때문이다.
///
/// 신기능 1-2-6이 요구하는 "**어떤 좌표들을 기준으로** 벡터가 할당되었는지 기억해야 한다"가
/// 바로 이 뜻이다. 그래서 id를 좌표에서 뽑는다. 같은 도면이면 누가 언제 열어도 같은 id가 나온다.
///
/// - 좌표를 넣는 이유: 같은 모양이라도 자리가 다르면 다른 개체다.
/// - `ordinal`을 함께 넣는 이유: 완전히 같은 자리에 같은 도형이 두 번 그려진 도면(작도 실수)에서도
///   둘을 갈라야 한다. 파싱 순서는 같은 SVG라면 항상 같으므로 결정성이 깨지지 않는다.
/// - 좌표를 0.001까지만 쓰는 이유: 파서가 만드는 부동소수 끝자리 오차를 흡수한다.
///   같은 파일을 같은 코드로 읽으면 어차피 같은 값이 나오지만, 나중에 파서가
///   미세하게 바뀌어도 id가 통째로 갈리지 않도록 여유를 둔다.
enum StableObjectID {

    static func make(ordinal: Int, element: String, styleKey: String,
                     geometry: PathGeometry) -> VectorObjectID {
        var text = "\(ordinal)|\(element)|\(styleKey)"
        for sp in geometry.subpaths {
            text += sp.isClosed ? "|Z" : "|O"
            for p in sp.points {
                text += String(format: "|%.3f,%.3f", p.x, p.y)
            }
        }
        return uuid(from: text)
    }

    /// 문자열 → UUID. SHA-256 앞 16바이트를 쓰고 UUID 형식 비트만 맞춘다.
    /// 해시를 쓰는 이유는 길이가 제각각인 도형 설명을 고정 길이 이름으로 바꾸기 위해서다.
    static func uuid(from text: String) -> UUID {
        var b = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x40
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

extension DrawingDocument {
    /// 도면 지문. 두 파일이 **같은 도면**을 두고 작업한 것인지 확인하는 데 쓴다(신기능 1-2-6).
    /// 개체 id 전체에서 뽑으므로, 도면이 조금이라도 다르면 값이 달라진다.
    var fingerprint: String {
        let joined = objects.map(\.id.uuidString).joined(separator: ",")
        return SHA256.hash(data: Data(joined.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
