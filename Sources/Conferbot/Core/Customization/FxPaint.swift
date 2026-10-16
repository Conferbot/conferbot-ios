//
//  FxPaint.swift
//  Conferbot
//
//  The paints the launcher effects use on the web (CSS radial / linear /
//  conic gradients, as in conferbot-widget src/ts/launcher/entrance.ts and
//  attention.ts), written as SVG markup (drawn by UI/SwiftUI/FxSvg.swift);
//  and a motion path (CSS offset-path) as points along it. Ported from the
//  React Native SDK's core/fxPaint.ts. Pure.
//

import Foundation

public enum FxPaint {
    /// A CSS colour: #rgb, #rrggbb, rgb(), rgba(), "transparent" (nil: unknown). [r, g, b, a].
    public static func parseCssColor(_ c: String) -> [Double]? {
        let s = c.trimmingCharacters(in: .whitespaces).lowercased()
        if s == "transparent" { return [0, 0, 0, 0] }
        if let m = Keyframes.firstMatch("^#([0-9a-f]{3}|[0-9a-f]{6})$", s) {
            let g = m[1]
            let h = g.count == 3 ? g.map { "\($0)\($0)" }.joined() : g
            let v = Array(h)
            func byte(_ i: Int) -> Double { Double(Int(String(v[i...i + 1]), radix: 16) ?? 0) }
            return [byte(0), byte(2), byte(4), 1]
        }
        if let m = Keyframes.firstMatch("^rgba?\\(\\s*([\\d.]+)[\\s,]+([\\d.]+)[\\s,]+([\\d.]+)(?:[\\s,/]+([\\d.]+))?\\s*\\)$", s) {
            return [Double(m[1]) ?? 0, Double(m[2]) ?? 0, Double(m[3]) ?? 0, m[4].isEmpty ? 1 : (Double(m[4]) ?? 1)]
        }
        return nil
    }

    /// One colour stop; `at` 0...1, missing positions spread evenly as CSS does.
    public struct Stop: ExpressibleByStringLiteral {
        public var color: String
        public var at: Double?

        public init(_ color: String, _ at: Double? = nil) {
            self.color = color
            self.at = at
        }

        public init(stringLiteral value: String) { self.init(value) }

        /// "colour p%".
        public static func at(_ color: String, _ percent: Double) -> Stop { Stop(color, percent / 100) }
    }

    private struct S {
        var c: [Double]
        var at: Double?
    }

    private static func spread(_ list: [Stop]) -> [S] {
        var out = list.map { S(c: parseCssColor($0.color) ?? [0, 0, 0, 0], at: $0.at) }
        if out[0].at == nil { out[0].at = 0 }
        if out[out.count - 1].at == nil { out[out.count - 1].at = 1 }
        if out.count > 2 {
            for i in 1..<(out.count - 1) where out[i].at == nil {
                var j = i
                while out[j].at == nil { j += 1 }
                let a = out[i - 1].at!, b = out[j].at!
                for k in i..<j { out[k].at = a + ((b - a) * Double(k - i + 1)) / Double(j - i + 1) }
            }
        }
        // A fully transparent stop fades its neighbour's colour (CSS interpolates
        // premultiplied; SVG does not, so the colour is borrowed).
        return out.enumerated().map { i, s in
            if s.c[3] > 0 { return s }
            let prev = i > 0 ? out[i - 1] : nil
            let next = i < out.count - 1 ? out[i + 1] : nil
            let near = (prev.map { $0.c[3] > 0 } ?? false) ? prev : (next.map { $0.c[3] > 0 } ?? false) ? next : (prev ?? next)
            let n = near?.c ?? s.c
            return S(c: [n[0], n[1], n[2], s.c[3]], at: s.at)
        }
    }

    private static func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    private static func stopTags(_ list: [Stop]) -> String {
        spread(list).map { s in
            "<stop offset=\"\(Keyframes.fixed(s.at!, 4))\" stop-color=\"rgb(\(jsRound(s.c[0])),\(jsRound(s.c[1])),\(jsRound(s.c[2])))\" stop-opacity=\"\(Keyframes.fixed(s.c[3], 3))\"/>"
        }.joined()
    }

    private static func n(_ x: Double) -> String { Keyframes.jsNum(x) }

    private static func svg(_ w: Double, _ h: Double, _ inner: String, vb: String? = nil) -> String {
        let fw = Keyframes.fixed(w, 2), fh = Keyframes.fixed(h, 2)
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(fw)\" height=\"\(fh)\" viewBox=\"\(vb ?? "0 0 \(fw) \(fh)")\">\(inner)</svg>"
    }

    /// radial-gradient(closest-side, ...) filling an ellipse in a w x h box.
    public static func radialDisc(_ w: Double, _ h: Double, _ list: [Stop]) -> String {
        svg(w, h, "<defs><radialGradient id=\"g\" cx=\"0.5\" cy=\"0.5\" r=\"0.5\">\(stopTags(list))</radialGradient></defs><ellipse cx=\"\(n(w / 2))\" cy=\"\(n(h / 2))\" rx=\"\(n(w / 2))\" ry=\"\(n(h / 2))\" fill=\"url(#g)\"/>")
    }

    /// radial-gradient(ellipse rx ry at cx cy, ...) over a w x h box (a page wash): the ellipse's radii in px.
    public static func radialWash(_ w: Double, _ h: Double, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ list: [Stop]) -> String {
        svg(w, h, "<defs><radialGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" cx=\"\(n(cx))\" cy=\"\(n(cy))\" r=\"\(n(rx))\" gradientTransform=\"translate(\(n(cx)) \(n(cy))) scale(1 \(n(ry / rx))) translate(\(n(-cx)) \(n(-cy)))\">\(stopTags(list))</radialGradient></defs><rect width=\"\(n(w))\" height=\"\(n(h))\" fill=\"url(#g)\"/>")
    }

    /// linear-gradient(<angle>, ...) in a w x h box with rounded corners (CSS angles: 180deg = to bottom). `radius`: one number, or [tl, tr, br, bl].
    public static func linearBox(_ w: Double, _ h: Double, _ angle: Double, _ list: [Stop], radius: [Double] = [0]) -> String {
        let a = angle * Double.pi / 180
        // The CSS gradient line: through the centre, long enough that the corners get the end colours.
        let len = abs(w * sin(a)) + abs(h * cos(a))
        let dx = (sin(a) * len) / 2
        let dy = (-cos(a) * len) / 2
        let r = radius.count >= 4 ? radius : Array(repeating: radius[0], count: 4)
        let tl = r[0], tr = r[1], br = r[2], bl = r[3]
        let shape = (tl != 0 || tr != 0 || br != 0 || bl != 0)
            ? "<path d=\"M\(n(tl)) 0 H\(n(w - tr)) A\(n(tr)) \(n(tr)) 0 0 1 \(n(w)) \(n(tr)) V\(n(h - br)) A\(n(br)) \(n(br)) 0 0 1 \(n(w - br)) \(n(h)) H\(n(bl)) A\(n(bl)) \(n(bl)) 0 0 1 0 \(n(h - bl)) V\(n(tl)) A\(n(tl)) \(n(tl)) 0 0 1 \(n(tl)) 0 Z\" fill=\"url(#g)\"/>"
            : "<rect width=\"\(n(w))\" height=\"\(n(h))\" fill=\"url(#g)\"/>"
        return svg(w, h, "<defs><linearGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" x1=\"\(n(w / 2 - dx))\" y1=\"\(n(h / 2 - dy))\" x2=\"\(n(w / 2 + dx))\" y2=\"\(n(h / 2 + dy))\">\(stopTags(list))</linearGradient></defs>\(shape)")
    }

    public static func linearBox(_ w: Double, _ h: Double, _ angle: Double, _ list: [Stop], radius: Double) -> String {
        linearBox(w, h, angle, list, radius: [radius])
    }

    private static func mixAt(_ list: [S], _ p: Double) -> [Double] {
        if p <= list[0].at! { return list[0].c }
        for i in 0..<(list.count - 1) {
            let a = list[i], b = list[i + 1]
            if p <= b.at! {
                let f = b.at! > a.at! ? (p - a.at!) / (b.at! - a.at!) : 1
                // Premultiplied, as CSS gradients interpolate.
                let al = a.c[3] + (b.c[3] - a.c[3]) * f
                func ch(_ k: Int) -> Double { al > 0 ? (a.c[k] * a.c[3] + (b.c[k] * b.c[3] - a.c[k] * a.c[3]) * f) / al : 0 }
                return [ch(0), ch(1), ch(2), al]
            }
        }
        return list[list.count - 1].c
    }

    /// conic-gradient(from <from>deg, ...) in a circle of diameter d, as thin
    /// wedges; `ring` keeps only the band between two shares of the radius
    /// (the portal's ring mask).
    public static func conicDisc(_ d: Double, _ from: Double, _ list: [Stop], ring: (Double, Double)? = nil, slices: Int = 48) -> String {
        let s = spread(list)
        let r = d / 2
        let ri = ring.map { $0.0 * r } ?? 0
        let ro = ring.map { $0.1 * r } ?? r
        var out = ""
        for i in 0..<slices {
            let p = (Double(i) + 0.5) / Double(slices)
            let c = mixAt(s, p)
            if c[3] <= 0.003 { continue }
            // CSS: 0deg points up, clockwise.
            let a0 = ((from + (Double(i) / Double(slices)) * 360 - 90) * Double.pi) / 180
            let a1 = ((from + ((Double(i) + 1.04) / Double(slices)) * 360 - 90) * Double.pi) / 180
            func pt(_ rad: Double, _ a: Double) -> String { "\(Keyframes.fixed(r + rad * cos(a), 2)) \(Keyframes.fixed(r + rad * sin(a), 2))" }
            let path = ri > 0
                ? "M\(pt(ro, a0)) A\(n(ro)) \(n(ro)) 0 0 1 \(pt(ro, a1)) L\(pt(ri, a1)) A\(n(ri)) \(n(ri)) 0 0 0 \(pt(ri, a0)) Z"
                : "M\(n(r)) \(n(r)) L\(pt(ro, a0)) A\(n(ro)) \(n(ro)) 0 0 1 \(pt(ro, a1)) Z"
            out += "<path d=\"\(path)\" fill=\"rgb(\(jsRound(c[0])),\(jsRound(c[1])),\(jsRound(c[2])))\" fill-opacity=\"\(Keyframes.fixed(c[3], 3))\"/>"
        }
        return svg(d, d, out)
    }

    // MARK: - A motion path (offset-path: path("M ... C ... a ..."))

    public struct P: Equatable {
        public var x: Double
        public var y: Double
    }

    /// The path flattened to points (M, L, C and a / A arcs, absolute or relative).
    public static func flattenPath(_ d: String, steps: Int = 24) -> [P] {
        let tok = Keyframes.allMatches("[a-zA-Z]|-?\\d*\\.?\\d+(?:e[-+]?\\d+)?", d).map { $0[0] }
        var pts: [P] = []
        var i = 0
        var cur = P(x: 0, y: 0)
        var cmd = ""
        func n() -> Double {
            let v = i < tok.count ? (Double(tok[i]) ?? 0) : 0
            i += 1
            return v
        }
        func isCmd(_ s: String) -> Bool { s.count == 1 && s.first!.isLetter }
        while i < tok.count {
            if isCmd(tok[i]) { cmd = tok[i]; i += 1 }
            let rel = cmd == cmd.lowercased()
            let c = cmd.uppercased()
            if c == "M" || c == "L" {
                let x = n() + (rel ? cur.x : 0)
                let y = n() + (rel ? cur.y : 0)
                cur = P(x: x, y: y)
                pts.append(cur)
                if c == "M" { cmd = rel ? "l" : "L" }
            } else if c == "C" {
                let o = rel ? cur : P(x: 0, y: 0)
                let p1 = P(x: n() + o.x, y: n() + o.y)
                let p2 = P(x: n() + o.x, y: n() + o.y)
                let p3 = P(x: n() + o.x, y: n() + o.y)
                let p0 = cur
                for k in 1...steps {
                    let t = Double(k) / Double(steps)
                    let u = 1 - t
                    pts.append(P(x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                                 y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y))
                }
                cur = p3
            } else if c == "A" {
                var rx = abs(n())
                var ry = abs(n())
                let phi = (n() * Double.pi) / 180
                let large = n() != 0
                let sweep = n() != 0
                let x2 = n() + (rel ? cur.x : 0)
                let y2 = n() + (rel ? cur.y : 0)
                let x1 = cur.x, y1 = cur.y
                // Endpoint to centre parameterisation (SVG implementation notes F.6.5).
                let cp = cos(phi), sp = sin(phi)
                let dx = (x1 - x2) / 2, dy = (y1 - y2) / 2
                let x1p = cp * dx + sp * dy
                let y1p = -sp * dx + cp * dy
                let lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
                if lam > 1 {
                    rx *= lam.squareRoot()
                    ry *= lam.squareRoot()
                }
                let num0 = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
                let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
                var co = max(0, num0 / den).squareRoot()
                if large == sweep { co = -co }
                let cxp = (co * rx * y1p) / ry
                let cyp = (-co * ry * x1p) / rx
                let cx = cp * cxp - sp * cyp + (x1 + x2) / 2
                let cy = sp * cxp + cp * cyp + (y1 + y2) / 2
                func ang(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double { atan2(ux * vy - uy * vx, ux * vx + uy * vy) }
                let t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
                var dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
                if !sweep && dt > 0 { dt -= 2 * Double.pi }
                if sweep && dt < 0 { dt += 2 * Double.pi }
                let k = max(steps, Int(((abs(dt) / (2 * Double.pi)) * Double(steps) * 3).rounded(.up)))
                for j in 1...k {
                    let t = t1 + (dt * Double(j)) / Double(k)
                    pts.append(P(x: cx + rx * cos(t) * cp - ry * sin(t) * sp, y: cy + rx * cos(t) * sp + ry * sin(t) * cp))
                }
                cur = P(x: x2, y: y2)
            } else {
                i += 1
            }
        }
        return pts
    }

    public struct Along {
        public var x: Double
        public var y: Double
        public var angle: Double
    }

    /// A point at a share (0...1) of a flattened path's length, and the path's direction there (deg).
    public static func pointAlong(_ pts: [P], _ share: Double) -> Along {
        var seg: [Double] = []
        var total = 0.0
        if pts.count > 1 {
            for i in 1..<pts.count {
                let dx = pts[i].x - pts[i - 1].x, dy = pts[i].y - pts[i - 1].y
                let l = (dx * dx + dy * dy).squareRoot()
                seg.append(l)
                total += l
            }
        }
        var d = min(1, max(0, share)) * total
        for i in seg.indices {
            if d <= seg[i] || i == seg.count - 1 {
                let f = seg[i] > 0 ? min(1, d / seg[i]) : 0
                let a = pts[i], b = pts[i + 1]
                return Along(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f, angle: (atan2(b.y - a.y, b.x - a.x) * 180) / Double.pi)
            }
            d -= seg[i]
        }
        let last = pts.last ?? P(x: 0, y: 0)
        return Along(x: last.x, y: last.y, angle: 0)
    }
}
