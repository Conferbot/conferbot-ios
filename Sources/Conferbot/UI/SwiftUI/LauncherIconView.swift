//
//  LauncherIconView.swift
//  Conferbot
//
//  A launcher icon (Core/Customization/LauncherIcons) drawn on a Canvas, in
//  the launcher's ink with its cut-outs in the launcher's own colour, at
//  rest: parts that only show while animating stay hidden. Gradients sit in
//  each shape's own bounding box (SVG objectBoundingBox), as on the web.
//

import SwiftUI

@available(iOS 15.0, *)
struct LauncherIconView: View {
    let iconId: String?
    let ink: Color
    let bg: Color
    let size: CGFloat
    /// Mid-moment (LauncherMotion.iconFrame): the moving parts in place.
    var frame: [OpFrame?]? = nil

    var body: some View {
        let icon = LauncherIcons.byId(iconId)
        Canvas { context, canvasSize in
            guard let icon = icon else { return }
            var ctx = context
            ctx.scaleBy(x: canvasSize.width / 24, y: canvasSize.height / 24)
            drawRange(Array(icon.ops.indices), depth: 0, in: ctx, icon: icon)
        }
        .frame(width: size, height: size)
    }

    /// The group layers an op sits in (an animated opacity fades its whole
    /// group as one layer, as CSS opacity does), its own layer left out.
    private func groupLayers(_ i: Int, _ icon: LauncherIcon) -> [LayerOpacity] {
        let layers = frame?[safe: i]??.layers ?? []
        let o = icon.ops[i]
        let ownGroup = o.`self` == 1 ? o.parts?.last?.g : nil
        if let last = layers.last, last.g == ownGroup { return Array(layers.dropLast()) }
        return layers
    }

    /// Ops in runs that share a layer at this depth, each run drawn inside it.
    private func drawRange(_ indices: [Int], depth: Int, in ctx: GraphicsContext, icon: LauncherIcon) {
        var k = 0
        while k < indices.count {
            let i = indices[k]
            let layers = groupLayers(i, icon)
            guard depth < layers.count else {
                draw(i, in: ctx, icon: icon)
                k += 1
                continue
            }
            let layer = layers[depth]
            var run: [Int] = []
            while k < indices.count {
                let l = groupLayers(indices[k], icon)
                guard depth < l.count, l[depth].g == layer.g else { break }
                run.append(indices[k])
                k += 1
            }
            var inner = ctx
            inner.opacity = layer.o
            inner.drawLayer { layerCtx in drawRange(run, depth: depth + 1, in: layerCtx, icon: icon) }
        }
    }

    private func color(_ c: String) -> Color {
        switch c {
        case "ink": return ink
        case "bg": return bg
        default: return Color(hex: c)
        }
    }

    private static func invert(_ m: [Double]) -> [Double] {
        let det = m[0] * m[3] - m[1] * m[2]
        if det == 0 { return [1, 0, 0, 1, 0, 0] }
        return [m[3] / det, -m[1] / det, -m[2] / det, m[0] / det, (m[2] * m[5] - m[3] * m[4]) / det, (m[1] * m[4] - m[0] * m[5]) / det]
    }

    private static func affine(_ m: [Double]) -> CGAffineTransform {
        CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5])
    }

    private func draw(_ i: Int, in base: GraphicsContext, icon: LauncherIcon) {
        let o = icon.ops[i]
        let f = frame?[safe: i] ?? nil
        let layers = f?.layers ?? []
        let ownGroup = o.`self` == 1 ? o.parts?.last?.g : nil
        let ownLayer = layers.last.flatMap { $0.g == ownGroup ? $0 : nil }
        // At rest op; moving, an animated part's opacity replaces its own.
        var opacity = o.op ?? 1
        if !layers.isEmpty {
            let animated = Set(layers.map { $0.g })
            opacity = o.opRest ?? ((o.parts ?? []).contains { $0.o != nil } ? 1 : (o.op ?? 1))
            for p in o.parts ?? [] where !animated.contains(p.g) { if let po = p.o { opacity *= po } }
            if let own = ownLayer { opacity *= own.o }
        }
        if opacity == 0 { return }
        var ctx = base
        let m = f?.m ?? o.m
        if let clip = o.clip, let clipM = f?.clipM, let m = m {
            // The clip in its own space, then the shape's transform.
            ctx.concatenate(Self.affine(clipM))
            ctx.clip(to: Path.fromSVG(clip))
            ctx.concatenate(Self.affine(LauncherMotion.mul(Self.invert(clipM), m)))
        } else {
            if let m = m, m.count == 6 { ctx.concatenate(Self.affine(m)) }
            if let clip = o.clip { ctx.clip(to: Path.fromSVG(clip)) }
        }
        ctx.opacity = opacity
        let path = Path.fromSVG(o.d)
        let style = FillStyle(eoFill: o.rule == "evenodd")

        let fill = {
            guard let p = o.fill else { return }
            if let g = p.g, g < icon.grads.count {
                fillGradient(path, icon.grads[g], paint: p, in: ctx, style: style)
            } else {
                ctx.fill(path, with: .color(color(p.c ?? "#000000").opacity(p.a)), style: style)
            }
        }
        let stroke = {
            guard let p = o.stroke else { return }
            let s = StrokeStyle(
                lineWidth: CGFloat(o.sw ?? 1),
                lineCap: o.cap == "round" ? .round : o.cap == "square" ? .square : .butt,
                lineJoin: o.join == "round" ? .round : o.join == "bevel" ? .bevel : .miter)
            ctx.stroke(path, with: .color(color(p.c ?? "#000000").opacity(p.a)), style: s)
        }
        if o.strokeFirst == true { stroke(); fill() } else { fill(); stroke() }
    }

    /// The gradient in a unit box mapped onto the shape's bounds, so a radial
    /// gradient on a wide shape is an ellipse.
    private func fillGradient(_ path: Path, _ g: IconGradient, paint: IconPaint, in base: GraphicsContext, style: FillStyle) {
        let b = path.boundingRect
        guard b.width > 0, b.height > 0 else { return }
        var ctx = base
        ctx.translateBy(x: b.minX, y: b.minY)
        ctx.scaleBy(x: b.width, y: b.height)
        let unit = path.applying(CGAffineTransform(translationX: -b.minX, y: -b.minY).concatenating(CGAffineTransform(scaleX: 1 / b.width, y: 1 / b.height)))
        let gradient = Gradient(stops: g.stops.map { Gradient.Stop(color: color($0.c).opacity($0.a * paint.a), location: $0.o) })
        let shading: GraphicsContext.Shading = g.t == "r"
            ? .radialGradient(gradient, center: CGPoint(x: g.cx ?? 0.5, y: g.cy ?? 0.5), startRadius: 0, endRadius: g.r ?? 0.5)
            : .linearGradient(gradient, startPoint: CGPoint(x: g.x1 ?? 0, y: g.y1 ?? 0), endPoint: CGPoint(x: g.x2 ?? 1, y: g.y2 ?? 0))
        ctx.fill(unit, with: shading, style: style)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
