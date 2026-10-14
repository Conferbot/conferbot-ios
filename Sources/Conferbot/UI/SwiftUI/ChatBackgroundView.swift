//
//  ChatBackgroundView.swift
//  Conferbot
//
//  The bot's chat background behind the messages, as the web widget draws it
//  (Core/Customization/ChatBackground): solid, gradient (linear, radial, mesh,
//  blur), image with its mask, or a pattern tile repeated. Patterns draw on a
//  Canvas (iOS 15+); before that they fall back to their base colour.
//

import SwiftUI

struct ChatBackgroundView: View {
    let background: ChatBackground

    var body: some View {
        switch background {
        case .solid(let color):
            Color(hex: color)
        case .image(let color, let url, let maskColor, let maskAlpha):
            ZStack {
                Color(hex: color)
                if #available(iOS 15.0, *), let u = URL(string: url) {
                    AsyncImage(url: u) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                }
                if let mask = maskColor { Color(hex: mask).opacity(maskAlpha) }
            }
            .clipped()
        case .gradient(_, let stops, let angle, let style):
            GeometryReader { geo in gradient(stops.map { Color(hex: $0) }, angle: Double(angle), style: style, size: geo.size) }
        case .pattern(let color, let pattern, let ink, let alpha):
            ZStack {
                Color(hex: color)
                if #available(iOS 15.0, *) {
                    PatternCanvas(tile: ChatBackgrounds.patterns[pattern] ?? ChatBackgrounds.patterns["dots"]!, ink: Color(hex: ink), alpha: alpha)
                }
            }
        }
    }

    @ViewBuilder
    private func gradient(_ stops: [Color], angle: Double, style: String, size: CGSize) -> some View {
        let w = max(size.width, 1), h = max(size.height, 1)
        switch style {
        case "radial":
            let (x, y) = ChatBackgrounds.rimPoint(angle, reach: 35)
            let far = [hypot(x, y), hypot(1 - x, y), hypot(x, 1 - y), hypot(1 - x, 1 - y)].max() ?? 1
            RadialGradient(colors: stops, center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: CGFloat(far) * max(w, h))
        case "mesh", "blur":
            // Soft colour fields over a base: the web's mesh (and, approximately, its blur).
            let mesh = style == "mesh"
            let fields = mesh ? stops : (stops.count > 1 ? Array(stops.dropFirst()) : stops)
            ZStack {
                (mesh ? stops.last : stops.first) ?? Color.white
                ForEach(Array(fields.enumerated()), id: \.offset) { i, c in
                    let (x, y) = ChatBackgrounds.rimPoint(angle + Double(i) * 360 / Double(fields.count) + (mesh ? 0 : 20), reach: mesh ? 50 : 34)
                    RadialGradient(colors: [c, c.opacity(0)], center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: (mesh ? 0.6 : 0.75) * max(w, h))
                }
            }
        default:
            // The CSS angle (0 = to top, 180 = to bottom) across the box.
            let a = angle * .pi / 180
            let dx = sin(a) / 2, dy = -cos(a) / 2
            LinearGradient(colors: stops, startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
        }
    }
}

@available(iOS 15.0, *)
private struct PatternCanvas: View {
    let tile: PatternTile
    let ink: Color
    let alpha: Double

    var body: some View {
        let paths: [Path?] = tile.shapes.map { $0.d.map { Path.fromSVG($0) } }
        Canvas { context, size in
            var y = 0.0
            while y < size.height {
                var x = 0.0
                while x < size.width {
                    var tileContext = context
                    tileContext.translateBy(x: x, y: y)
                    draw(in: &tileContext, paths: paths)
                    x += tile.w
                }
                y += tile.h
            }
        }
    }

    private func draw(in context: inout GraphicsContext, paths: [Path?]) {
        let shading = GraphicsContext.Shading.color(ink.opacity(alpha))
        if tile.noise {
            for p in ChatBackgrounds.paperSpeckles {
                let r = p[2]
                context.fill(Path(ellipseIn: CGRect(x: p[0] - r, y: p[1] - r, width: 2 * r, height: 2 * r)), with: .color(ink.opacity(min(1, alpha * 1.6 * p[3]))))
            }
            return
        }
        for (i, s) in tile.shapes.enumerated() {
            var path: Path
            switch s.t {
            case "circle": path = Path(ellipseIn: CGRect(x: s.cx - s.r, y: s.cy - s.r, width: 2 * s.r, height: 2 * s.r))
            case "rect": path = Path(roundedRect: CGRect(x: s.x, y: s.y, width: s.w, height: s.h), cornerRadius: s.rx)
            default: path = paths[i] ?? Path()
            }
            if let rot = s.rot, rot.count == 3 {
                let t = CGAffineTransform(translationX: rot[1], y: rot[2]).rotated(by: rot[0] * .pi / 180).translatedBy(x: -rot[1], y: -rot[2])
                path = path.applying(t)
            }
            if s.fill {
                context.fill(path, with: shading)
            } else {
                context.stroke(path, with: shading, style: StrokeStyle(lineWidth: s.sw, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
