import CoreGraphics
import Foundation

/// `d="M10 10 C ..."` 문자열을 Subpath 배열로 파싱한다.
/// 2차 베지어(Q/T)와 호(A)는 여기서 전부 3차 베지어로 환산하므로,
/// 하류 코드는 line과 cubic 두 가지만 다루면 된다.
enum PathDataParser {

    struct ParseError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    static func parse(_ d: String) throws -> [Subpath] {
        var scanner = Tokenizer(d)
        var subpaths: [Subpath] = []

        var current: LocalPoint = LocalPoint(0, 0)
        var subpathStart: LocalPoint = LocalPoint(0, 0)
        var segments: [PathSegment] = []
        var haveOpenSubpath = false
        var lastCubicControl: LocalPoint?
        var lastQuadControl: LocalPoint?
        var lastCommand: Character = " "

        func flush(closed: Bool) {
            if haveOpenSubpath && !segments.isEmpty {
                subpaths.append(Subpath(start: subpathStart, segments: segments, isClosed: closed))
            }
            segments = []
            haveOpenSubpath = false
        }

        while let cmd = scanner.nextCommand() {
            let isRelative = cmd.isLowercase
            let c = Character(cmd.uppercased())

            switch c {
            case "M":
                var first = true
                repeat {
                    let p = try scanner.point(relativeTo: isRelative ? current : nil)
                    if first {
                        flush(closed: false)
                        subpathStart = p
                        haveOpenSubpath = true
                        first = false
                    } else {
                        segments.append(.line(to: p))
                    }
                    current = p
                } while scanner.peekIsNumber()
                lastCubicControl = nil; lastQuadControl = nil

            case "L":
                repeat {
                    let p = try scanner.point(relativeTo: isRelative ? current : nil)
                    segments.append(.line(to: p)); current = p
                } while scanner.peekIsNumber()
                lastCubicControl = nil; lastQuadControl = nil

            case "H":
                repeat {
                    let x = try scanner.number()
                    let p = LocalPoint(isRelative ? current.x + x : x, current.y)
                    segments.append(.line(to: p)); current = p
                } while scanner.peekIsNumber()
                lastCubicControl = nil; lastQuadControl = nil

            case "V":
                repeat {
                    let y = try scanner.number()
                    let p = LocalPoint(current.x, isRelative ? current.y + y : y)
                    segments.append(.line(to: p)); current = p
                } while scanner.peekIsNumber()
                lastCubicControl = nil; lastQuadControl = nil

            case "C":
                repeat {
                    let c1 = try scanner.point(relativeTo: isRelative ? current : nil)
                    let c2 = try scanner.point(relativeTo: isRelative ? current : nil)
                    let p = try scanner.point(relativeTo: isRelative ? current : nil)
                    segments.append(.cubic(c1: c1, c2: c2, to: p))
                    lastCubicControl = c2; lastQuadControl = nil
                    current = p
                } while scanner.peekIsNumber()

            case "S":
                repeat {
                    let reflected = reflect(lastCubicControl, about: current,
                                            validAfter: lastCommand, allowed: "CS")
                    let c2 = try scanner.point(relativeTo: isRelative ? current : nil)
                    let p = try scanner.point(relativeTo: isRelative ? current : nil)
                    segments.append(.cubic(c1: reflected, c2: c2, to: p))
                    lastCubicControl = c2; lastQuadControl = nil
                    current = p
                } while scanner.peekIsNumber()

            case "Q":
                repeat {
                    let q = try scanner.point(relativeTo: isRelative ? current : nil)
                    let p = try scanner.point(relativeTo: isRelative ? current : nil)
                    segments.append(quadToCubic(from: current, control: q, to: p))
                    lastQuadControl = q; lastCubicControl = nil
                    current = p
                } while scanner.peekIsNumber()

            case "T":
                repeat {
                    let q = reflect(lastQuadControl, about: current,
                                    validAfter: lastCommand, allowed: "QT")
                    let p = try scanner.point(relativeTo: isRelative ? current : nil)
                    segments.append(quadToCubic(from: current, control: q, to: p))
                    lastQuadControl = q; lastCubicControl = nil
                    current = p
                } while scanner.peekIsNumber()

            case "A":
                repeat {
                    let rx = try scanner.number()
                    let ry = try scanner.number()
                    let rot = try scanner.number()
                    let largeArc = try scanner.flag()
                    let sweep = try scanner.flag()
                    let p = try scanner.point(relativeTo: isRelative ? current : nil)
                    segments.append(contentsOf: arcToCubic(
                        from: current, to: p, rx: rx, ry: ry,
                        xAxisRotationDeg: rot, largeArc: largeArc, sweep: sweep))
                    current = p
                } while scanner.peekIsNumber()
                lastCubicControl = nil; lastQuadControl = nil

            case "Z":
                if haveOpenSubpath && !segments.isEmpty {
                    subpaths.append(Subpath(start: subpathStart, segments: segments, isClosed: true))
                }
                segments = []
                haveOpenSubpath = true
                current = subpathStart
                lastCubicControl = nil; lastQuadControl = nil

            default:
                throw ParseError(message: "알 수 없는 path 명령: \(cmd)")
            }
            lastCommand = c
        }
        flush(closed: false)
        return subpaths
    }

    private static func reflect(_ control: LocalPoint?, about current: LocalPoint,
                                validAfter last: Character, allowed: String) -> LocalPoint {
        guard let control, allowed.contains(last) else { return current }
        return LocalPoint(2 * current.x - control.x, 2 * current.y - control.y)
        // 직전 명령이 같은 계열이 아니면 반사 제어점은 현재점과 같다(SVG 스펙).
    }

    private static func quadToCubic(from p0: LocalPoint, control q: LocalPoint,
                                    to p1: LocalPoint) -> PathSegment {
        let c1 = LocalPoint(p0.x + 2.0 / 3.0 * (q.x - p0.x), p0.y + 2.0 / 3.0 * (q.y - p0.y))
        let c2 = LocalPoint(p1.x + 2.0 / 3.0 * (q.x - p1.x), p1.y + 2.0 / 3.0 * (q.y - p1.y))
        return .cubic(c1: c1, c2: c2, to: p1)
    }

    /// SVG 호(A) 파라미터를 3차 베지어 여러 개로 환산한다(SVG 1.1 부록 F.6 구현).
    static func arcToCubic(from p0: LocalPoint, to p1: LocalPoint,
                           rx rxIn: Double, ry ryIn: Double,
                           xAxisRotationDeg: Double, largeArc: Bool, sweep: Bool) -> [PathSegment] {
        if rxIn == 0 || ryIn == 0 || (p0.x == p1.x && p0.y == p1.y) {
            return [.line(to: p1)]
        }
        var rx = abs(rxIn), ry = abs(ryIn)
        let phi = xAxisRotationDeg * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx2 = (p0.x - p1.x) / 2, dy2 = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
        }

        let sign: Double = (largeArc != sweep) ? 1 : -1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = sign * sqrt(den == 0 ? 0 : num / den)
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx

        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(max(-1, min(1, len == 0 ? 1 : dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                          (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let count = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / Double(count)
        let alpha = 4.0 / 3.0 * tan(step / 4)

        var result: [PathSegment] = []
        var t1 = theta1
        var from = p0
        for _ in 0..<count {
            let t2 = t1 + step
            func point(_ t: Double) -> LocalPoint {
                let x = cosPhi * rx * cos(t) - sinPhi * ry * sin(t) + cx
                let y = sinPhi * rx * cos(t) + cosPhi * ry * sin(t) + cy
                return LocalPoint(x, y)
            }
            func derivative(_ t: Double) -> (Double, Double) {
                let dx = -cosPhi * rx * sin(t) - sinPhi * ry * cos(t)
                let dy = -sinPhi * rx * sin(t) + cosPhi * ry * cos(t)
                return (dx, dy)
            }
            let to = point(t2)
            let d1 = derivative(t1), d2 = derivative(t2)
            let c1 = LocalPoint(from.x + alpha * d1.0, from.y + alpha * d1.1)
            let c2 = LocalPoint(to.x - alpha * d2.0, to.y - alpha * d2.1)
            result.append(.cubic(c1: c1, c2: c2, to: to))
            from = to
            t1 = t2
        }
        return result
    }

    // MARK: - 토크나이저

    private struct Tokenizer {
        private let chars: [Character]
        private var i = 0

        init(_ s: String) { chars = Array(s) }

        private mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n"
                    || chars[i] == "\t" || chars[i] == "\r" {
                i += 1
            }
        }

        mutating func nextCommand() -> Character? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            guard c.isLetter else { return nil }
            i += 1
            return c
        }

        mutating func peekIsNumber() -> Bool {
            skipSeparators()
            guard i < chars.count else { return false }
            let c = chars[i]
            return c.isNumber || c == "-" || c == "+" || c == "."
        }

        mutating func number() throws -> Double {
            skipSeparators()
            var s = ""
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            var seenDot = false, seenExp = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { s.append(c); i += 1 }
                else if c == "." && !seenDot && !seenExp { seenDot = true; s.append(c); i += 1 }
                else if (c == "e" || c == "E") && !seenExp {
                    seenExp = true; s.append(c); i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
                } else { break }
            }
            guard let v = Double(s) else {
                throw ParseError(message: "숫자를 읽지 못했습니다 (위치 \(i))")
            }
            return v
        }

        /// 호(A)의 large-arc-flag / sweep-flag. 공백 없이 "11" 처럼 붙어 올 수 있어 1글자만 읽는다.
        mutating func flag() throws -> Bool {
            skipSeparators()
            guard i < chars.count, let v = chars[i].wholeNumberValue else {
                throw ParseError(message: "arc flag를 읽지 못했습니다 (위치 \(i))")
            }
            i += 1
            return v != 0
        }

        mutating func point(relativeTo base: LocalPoint?) throws -> LocalPoint {
            let x = try number()
            let y = try number()
            if let base { return LocalPoint(base.x + x, base.y + y) }
            return LocalPoint(x, y)
        }
    }
}
