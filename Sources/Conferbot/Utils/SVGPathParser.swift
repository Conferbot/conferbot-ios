//
//  SVGPathParser.swift
//  Conferbot
//
//  An SVG path's "d" attribute as move / line / cubic / close segments, for
//  drawing the launcher icons (the web widget's SVGs) without a vector
//  library. Covers every command: M L H V C S Q T A Z, absolute and
//  relative; quadratics and elliptical arcs become cubics. Pure.
//

import Foundation

public enum SVGSegment: Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint) // control 1, control 2, end
    case close
}

public enum SVGPathParser {

    /// The segments of a path's "d" attribute; an unreadable tail is dropped.
    public static func parse(_ d: String) -> [SVGSegment] {
        var out: [SVGSegment] = []
        var tokens = Tokenizer(d)
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?        // for S / s
        var lastQuadControl: CGPoint?    // for T / t
        var command: Character?

        while let next = tokens.peekCommandOrNumber() {
            if case .command(let c) = next {
                tokens.consumeCommand()
                command = c
            } else if command == nil {
                break
            }
            guard let cmd = command else { break }
            let relative = cmd.isLowercase
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y) }

            switch cmd.uppercased().first! {
            case "M":
                guard let x = tokens.number(), let y = tokens.number() else { return out }
                current = pt(x, y)
                start = current
                out.append(.move(current))
                // Following pairs are implicit line-tos.
                command = relative ? "l" : "L"
                lastControl = nil
                lastQuadControl = nil
            case "L":
                guard let x = tokens.number(), let y = tokens.number() else { return out }
                current = pt(x, y)
                out.append(.line(current))
                lastControl = nil
                lastQuadControl = nil
            case "H":
                guard let x = tokens.number() else { return out }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                out.append(.line(current))
                lastControl = nil
                lastQuadControl = nil
            case "V":
                guard let y = tokens.number() else { return out }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                out.append(.line(current))
                lastControl = nil
                lastQuadControl = nil
            case "C":
                guard let x1 = tokens.number(), let y1 = tokens.number(), let x2 = tokens.number(), let y2 = tokens.number(),
                      let x = tokens.number(), let y = tokens.number() else { return out }
                let c1 = pt(x1, y1), c2 = pt(x2, y2), end = pt(x, y)
                out.append(.cubic(c1, c2, end))
                current = end
                lastControl = c2
                lastQuadControl = nil
            case "S":
                guard let x2 = tokens.number(), let y2 = tokens.number(), let x = tokens.number(), let y = tokens.number() else { return out }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = pt(x2, y2), end = pt(x, y)
                out.append(.cubic(c1, c2, end))
                current = end
                lastControl = c2
                lastQuadControl = nil
            case "Q":
                guard let x1 = tokens.number(), let y1 = tokens.number(), let x = tokens.number(), let y = tokens.number() else { return out }
                let q = pt(x1, y1), end = pt(x, y)
                out.append(quad(from: current, control: q, to: end))
                current = end
                lastQuadControl = q
                lastControl = nil
            case "T":
                guard let x = tokens.number(), let y = tokens.number() else { return out }
                let q = lastQuadControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let end = pt(x, y)
                out.append(quad(from: current, control: q, to: end))
                current = end
                lastQuadControl = q
                lastControl = nil
            case "A":
                guard let rx = tokens.number(), let ry = tokens.number(), let rotation = tokens.number(),
                      let large = tokens.flag(), let sweep = tokens.flag(),
                      let x = tokens.number(), let y = tokens.number() else { return out }
                let end = pt(x, y)
                out.append(contentsOf: arc(from: current, to: end, rx: rx, ry: ry, rotation: rotation, largeArc: large, sweep: sweep))
                current = end
                lastControl = nil
                lastQuadControl = nil
            case "Z":
                out.append(.close)
                current = start
                lastControl = nil
                lastQuadControl = nil
                command = nil
            default:
                return out
            }
        }
        return out
    }

    private static func quad(from p0: CGPoint, control q: CGPoint, to p: CGPoint) -> SVGSegment {
        let c1 = CGPoint(x: p0.x + 2 / 3 * (q.x - p0.x), y: p0.y + 2 / 3 * (q.y - p0.y))
        let c2 = CGPoint(x: p.x + 2 / 3 * (q.x - p.x), y: p.y + 2 / 3 * (q.y - p.y))
        return .cubic(c1, c2, p)
    }

    /// An elliptical arc as cubic Béziers (SVG implementation notes, F.6).
    static func arc(from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                    rotation: CGFloat, largeArc: Bool, sweep: Bool) -> [SVGSegment] {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 || p0 == p1 { return p0 == p1 ? [] : [.line(p1)] }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let parts = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(parts)
        let t = 4 / 3 * tan(step / 4)
        var out: [SVGSegment] = []
        var a1 = theta1
        func point(_ a: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi, y: cy + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi)
        }
        func derivative(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(a) * cosPhi - ry * cos(a) * sinPhi, y: -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi)
        }
        for i in 0..<parts {
            let a2 = a1 + step
            let s = point(a1), e = i == parts - 1 ? p1 : point(a2)
            let d1 = derivative(a1), d2 = derivative(a2)
            out.append(.cubic(CGPoint(x: s.x + t * d1.x, y: s.y + t * d1.y), CGPoint(x: e.x - t * d2.x, y: e.y - t * d2.y), e))
            a1 = a2
        }
        return out
    }

    // MARK: - Tokens

    private enum Token { case command(Character), number }

    private struct Tokenizer {
        private let chars: [Character]
        private var i = 0
        init(_ s: String) { chars = Array(s) }

        private mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" || chars[i] == "\r" { i += 1 }
        }

        mutating func peekCommandOrNumber() -> Token? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            if "MmLlHhVvCcSsQqTtAaZz".contains(c) { return .command(c) }
            if c.isNumber || c == "-" || c == "+" || c == "." { return .number }
            return nil
        }

        mutating func consumeCommand() { i += 1 }

        /// An arc flag: a single 0 or 1, which may be written with no separator.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { return nil }
            let v = chars[i] == "1"
            i += 1
            return v
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            guard i < chars.count else { return nil }
            var s = ""
            if chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            var seenDot = false, seenExp = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { s.append(c); i += 1 }
                else if c == "." && !seenDot && !seenExp { seenDot = true; s.append(c); i += 1 }
                else if (c == "e" || c == "E") && !seenExp && !s.isEmpty {
                    seenExp = true; s.append(c); i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
                }
                else { break }
            }
            guard let d = Double(s) else { return nil }
            return CGFloat(d)
        }
    }
}
