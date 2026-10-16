//
//  FxSvg.swift
//  Conferbot
//
//  A small SVG renderer for the launcher effects' drawings (the markup built
//  by Core/Customization/LauncherEntrance.swift, MascotArt.swift and
//  FxPaint.swift, the same markup the React Native SDK hands to
//  react-native-svg). It covers what those drawings use: svg (viewBox,
//  preserveAspectRatio none), g (transform, clip-path, opacity), path,
//  ellipse, circle, rect (rx), polygon; fill / stroke as a colour, none or a
//  linear / radial gradient (object bounding box or user space, with a
//  gradientTransform), their opacities, stroke width, caps, joins and
//  dashes; and
//  clipPath. No filters, as in RN. Draws into a SwiftUI GraphicsContext
//  (Canvas, iOS 15).
//

import SwiftUI

@available(iOS 15.0, *)
enum FxSvg {
    final class Node {
        let tag: String
        let a: [String: String]
        var kids: [Node] = []
        init(_ tag: String, _ a: [String: String]) {
            self.tag = tag
            self.a = a
        }
    }

    final class Doc {
        let root: Node
        let ids: [String: Node]
        let viewBox: CGRect
        let stretch: Bool
        var paths: [String: Path] = [:]
        init(root: Node, ids: [String: Node], viewBox: CGRect, stretch: Bool) {
            self.root = root
            self.ids = ids
            self.viewBox = viewBox
            self.stretch = stretch
        }
    }

    private static var docs: [String: Doc] = [:]
    private static var order: [String] = []

    private static func doc(_ svg: String) -> Doc {
        if let d = docs[svg] { return d }
        let d = parse(svg)
        docs[svg] = d
        order.append(svg)
        if order.count > 400 { docs[order.removeFirst()] = nil }
        return d
    }

    private static func parse(_ svg: String) -> Doc {
        let root = Node("#root", [:])
        var stack = [root]
        var ids: [String: Node] = [:]
        for m in Keyframes.allMatches("<(/?)([a-zA-Z][\\w-]*)((?:\\s+[\\w:-]+=\"[^\"]*\")*)\\s*(/?)>", svg) {
            if m[1] == "/" {
                if stack.count > 1 { stack.removeLast() }
                continue
            }
            var attrs: [String: String] = [:]
            for a in Keyframes.allMatches("([\\w:-]+)=\"([^\"]*)\"", m[3]) { attrs[a[1]] = a[2] }
            let n = Node(m[2], attrs)
            stack.last!.kids.append(n)
            if let id = attrs["id"] { ids[id] = n }
            if m[4] != "/" { stack.append(n) }
        }
        let svgNode = root.kids.first { $0.tag == "svg" } ?? root
        let vb = Keyframes.split((svgNode.a["viewBox"] ?? "").trimmingCharacters(in: .whitespaces), "[\\s,]+").compactMap { Double($0) }
        let w = svgNode.a["width"].flatMap { Double($0) }
        let h = svgNode.a["height"].flatMap { Double($0) }
        let box = vb.count == 4 ? CGRect(x: vb[0], y: vb[1], width: vb[2], height: vb[3]) : CGRect(x: 0, y: 0, width: w ?? 100, height: h ?? 100)
        return Doc(root: svgNode, ids: ids, viewBox: box, stretch: svgNode.a["preserveAspectRatio"] == "none")
    }

    private static func d(_ a: [String: String], _ k: String, _ fallback: Double = 0) -> Double {
        a[k].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? fallback
    }

    /// "rotate(a cx cy) translate(x y) scale(x y)", applied in order.
    static func transform(_ t: String?) -> CGAffineTransform {
        var m = CGAffineTransform.identity
        guard let t = t else { return m }
        for f in Keyframes.allMatches("(\\w+)\\(([^)]*)\\)", t) {
            let n = Keyframes.split(f[2].trimmingCharacters(in: .whitespaces), "[\\s,]+").map { Double($0) ?? 0 }
            switch f[1] {
            case "translate": m = m.translatedBy(x: n[0], y: n.count > 1 ? n[1] : 0)
            case "scale": m = m.scaledBy(x: n[0], y: n.count > 1 ? n[1] : n[0])
            case "rotate":
                let a = n[0] * .pi / 180
                if n.count > 2 {
                    m = m.translatedBy(x: n[1], y: n[2]).rotated(by: a).translatedBy(x: -n[1], y: -n[2])
                } else {
                    m = m.rotated(by: a)
                }
            default: break
            }
        }
        return m
    }

    /// The shape of an element, or nil when it is not a shape.
    private static func shape(_ doc: Doc, _ n: Node) -> Path? {
        let a = n.a
        switch n.tag {
        case "path":
            let s = a["d"] ?? ""
            if let p = doc.paths[s] { return p }
            let p = Path.fromSVG(s)
            doc.paths[s] = p
            return p
        case "ellipse":
            let cx = d(a, "cx"), cy = d(a, "cy"), rx = d(a, "rx"), ry = d(a, "ry")
            return Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        case "circle":
            let cx = d(a, "cx"), cy = d(a, "cy"), r = d(a, "r")
            return Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        case "rect":
            let x = d(a, "x"), y = d(a, "y"), w = d(a, "width"), h = d(a, "height")
            let rx = min(d(a, "rx", d(a, "ry")), w / 2)
            let ry = min(d(a, "ry", rx), h / 2)
            let r = CGRect(x: x, y: y, width: w, height: h)
            return rx > 0 || ry > 0 ? Path(roundedRect: r, cornerSize: CGSize(width: rx, height: ry)) : Path(r)
        case "polygon":
            let p = Keyframes.split((a["points"] ?? "").trimmingCharacters(in: .whitespaces), "[\\s,]+").map { Double($0) ?? 0 }
            var path = Path()
            var i = 0
            while i + 1 < p.count {
                let pt = CGPoint(x: p[i], y: p[i + 1])
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                i += 2
            }
            path.closeSubpath()
            return path
        default:
            return nil
        }
    }

    static func color(_ c: [Double], _ opacity: Double) -> Color {
        Color(.sRGB, red: c[0] / 255, green: c[1] / 255, blue: c[2] / 255, opacity: min(1, max(0, c[3] * opacity)))
    }

    /// Fills `area` (already the shape, or a stroke's outline) with a fill / stroke value.
    private static func paint(_ ctx: inout GraphicsContext, _ doc: Doc, _ value: String?, _ opacity: Double, area: Path, bounds: CGRect) {
        let v = (value ?? "").trimmingCharacters(in: .whitespaces)
        if v.isEmpty || v == "none" { return }
        if let url = Keyframes.firstMatch("^url\\(#([^)]+)\\)$", v) {
            guard let g = doc.ids[url[1]] else { return }
            var stops: [Gradient.Stop] = []
            var last = 0.0
            for s in g.kids where s.tag == "stop" {
                let c = FxPaint.parseCssColor(s.a["stop-color"] ?? "#000") ?? [0, 0, 0, 1]
                let at = max(last, min(1, max(0, d(s.a, "offset"))))
                last = at
                stops.append(Gradient.Stop(color: color(c, d(s.a, "stop-opacity", 1) * opacity), location: at))
            }
            if stops.isEmpty { return }
            if stops.count == 1 { stops.append(Gradient.Stop(color: stops[0].color, location: 1)) }
            let user = g.a["gradientUnits"] == "userSpaceOnUse"
            // Object bounding box units: the unit square stretched over the shape.
            let m = user ? transform(g.a["gradientTransform"])
                : transform(g.a["gradientTransform"]).concatenating(
                    CGAffineTransform(a: max(bounds.width, 1e-4), b: 0, c: 0, d: max(bounds.height, 1e-4), tx: bounds.minX, ty: bounds.minY))
            let gradient = Gradient(stops: stops)
            let shading: GraphicsContext.Shading
            if g.tag == "linearGradient" {
                shading = .linearGradient(gradient, startPoint: CGPoint(x: d(g.a, "x1"), y: d(g.a, "y1")),
                                          endPoint: CGPoint(x: d(g.a, "x2", user ? 0 : 1), y: d(g.a, "y2")))
            } else {
                shading = .radialGradient(gradient, center: CGPoint(x: d(g.a, "cx", 0.5), y: d(g.a, "cy", 0.5)),
                                          startRadius: 0, endRadius: max(d(g.a, "r", 0.5), 1e-4))
            }
            // The gradient drawn in its own space, clipped to the area.
            var c = ctx
            c.clip(to: area)
            c.concatenate(m)
            let cover = bounds.insetBy(dx: -2, dy: -2).applying(m.inverted())
            c.fill(Path(cover), with: shading)
            return
        }
        guard let c = FxPaint.parseCssColor(v) else { return }
        ctx.fill(area, with: .color(color(c, opacity)))
    }

    private static func draw(_ ctx: GraphicsContext, _ doc: Doc, _ n: Node, _ inherited: Double) {
        let a = n.a
        if ["defs", "clipPath", "linearGradient", "radialGradient", "stop"].contains(n.tag) { return }
        let own = d(a, "opacity", 1)
        var c = ctx
        if let t = a["transform"] { c.concatenate(transform(t)) }
        if let clip = Keyframes.firstMatch("^url\\(#([^)]+)\\)$", a["clip-path"] ?? ""), let cp = doc.ids[clip[1]] {
            var p = Path()
            for k in cp.kids {
                guard let s = shape(doc, k) else { continue }
                if let t = k.a["transform"] { p.addPath(s, transform: transform(t)) } else { p.addPath(s) }
            }
            c.clip(to: p)
        }
        if let s = shape(doc, n) {
            let o = inherited * own
            let bounds = s.boundingRect
            paint(&c, doc, a["fill"] ?? "#000", o * d(a, "fill-opacity", 1), area: s, bounds: bounds)
            if let stroke = a["stroke"], stroke != "none" {
                let cap: CGLineCap = a["stroke-linecap"] == "round" ? .round : a["stroke-linecap"] == "square" ? .square : .butt
                let join: CGLineJoin = a["stroke-linejoin"] == "round" ? .round : a["stroke-linejoin"] == "bevel" ? .bevel : .miter
                let dash = Keyframes.split((a["stroke-dasharray"] ?? "").trimmingCharacters(in: .whitespaces), "[\\s,]+").compactMap { Double($0) }.map { CGFloat($0) }
                let outline = s.strokedPath(StrokeStyle(lineWidth: d(a, "stroke-width", 1), lineCap: cap, lineJoin: join,
                                                        dash: dash.contains { $0 > 0 } ? (dash.count % 2 == 1 ? dash + dash : dash) : [],
                                                        dashPhase: d(a, "stroke-dashoffset")))
                paint(&c, doc, stroke, o * d(a, "stroke-opacity", 1), area: outline, bounds: bounds)
            }
        } else if !n.kids.isEmpty {
            // A group's opacity fades its drawing as one.
            if own < 1 && n.tag == "g" {
                c.opacity *= own
                c.drawLayer { l in
                    for k in n.kids { draw(l, doc, k, inherited) }
                }
            } else {
                for k in n.kids { draw(c, doc, k, inherited * own) }
            }
        }
    }

    /// Draws `svg` filling a w x h box at the context's origin.
    static func draw(_ ctx: GraphicsContext, _ svg: String, _ w: Double, _ h: Double) {
        let doc = doc(svg)
        let vb = doc.viewBox
        if vb.width <= 0 || vb.height <= 0 || w <= 0 || h <= 0 { return }
        var sx = w / vb.width, sy = h / vb.height
        var dx = 0.0, dy = 0.0
        if !doc.stretch {
            // xMidYMid meet.
            let s = min(sx, sy)
            dx = (w - vb.width * s) / 2
            dy = (h - vb.height * s) / 2
            sx = s
            sy = s
        }
        var c = ctx
        c.translateBy(x: dx, y: dy)
        c.scaleBy(x: sx, y: sy)
        c.translateBy(x: -vb.minX, y: -vb.minY)
        for k in doc.root.kids { draw(c, doc, k, 1) }
    }
}
