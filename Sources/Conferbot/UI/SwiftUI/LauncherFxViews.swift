//
//  LauncherFxViews.swift
//  Conferbot
//
//  The launcher effects drawn (the React Native SDK's FxSprites.tsx and
//  IdleCallView.tsx): an entrance's sprites on their stage, the idle call's
//  mascot with its moving parts and rings, the attention loop's extra
//  pieces, and the idle call's speech bubble. Each is drawn at a time t (ms)
//  the launcher's clock gives it, in the launcher's own box (pt, its
//  top-left at 0, 0); sprites reach past it. SwiftUI Canvas (iOS 15).
//

import SwiftUI

@available(iOS 15.0, *)
enum LauncherFxDraw {
    /// The orbit's spark and the gloss band (attention.ts ATTENTION_CSS).
    static let orbitDot = 8.0
    static let glossWidth = 0.45
    static let glossTop = -0.3
    static let glossHeight = 1.6

    /// The waving hand's box (a 20px emoji), turning about 70% 80%.
    static let handW = 22.0
    static let handH = 20.0

    /// A box's transform as the web moves it: about `origin` (px in the box), translate, rotate, scale.
    static func transform(_ c: inout GraphicsContext, _ ox: Double, _ oy: Double, _ tx: Double, _ ty: Double, _ r: Double, _ sx: Double, _ sy: Double) {
        c.translateBy(x: ox + tx, y: oy + ty)
        if r != 0 { c.rotate(by: .degrees(r)) }
        if sx != 1 || sy != 1 { c.scaleBy(x: sx, y: sy) }
        c.translateBy(x: -ox, y: -oy)
    }

    static func css(_ s: String, _ opacity: Double = 1) -> Color {
        FxSvg.color(FxPaint.parseCssColor(s) ?? [0, 0, 0, 0], opacity)
    }

    /// One sprite and its children at t ms, in the stage's coordinates.
    static func sprite(_ ctx: GraphicsContext, _ sp: FxSprite, _ t: Double) {
        let f = LauncherEntrance.spriteFrame(sp, t)
        if f.o <= 0.002 { return }
        var c = ctx
        c.translateBy(x: sp.x, y: sp.y)
        transform(&c, sp.origin?.0 ?? sp.w / 2, sp.origin?.1 ?? sp.h / 2, f.tx, f.ty, f.r, f.sx, f.sy)
        let leafFill = sp.fill != nil && sp.children.isEmpty && sp.svg == nil
        func contents(_ c: GraphicsContext) {
            if let svg = sp.svg, sp.w > 0, sp.h > 0 {
                var s = c
                if let wipe = sp.wipe {
                    // A stroke drawn on: only what has been drawn so far shows.
                    let p = min(1, max(0, f.reveal))
                    s.clip(to: Path(wipe == "down" ? CGRect(x: 0, y: 0, width: sp.w, height: sp.h * p) : CGRect(x: 0, y: 0, width: sp.w * p, height: sp.h)))
                }
                FxSvg.draw(s, svg, sp.w, sp.h)
            } else if let fill = sp.fill {
                let r = sp.radius ?? 0
                let rect = CGRect(x: 0, y: 0, width: sp.w, height: sp.h)
                c.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(css(fill, leafFill ? f.o : 1)))
            }
            if !sp.children.isEmpty {
                var s = c
                if let r = sp.clip { s.clip(to: Path(roundedRect: CGRect(x: 0, y: 0, width: sp.w, height: sp.h), cornerRadius: r)) }
                for k in sp.children { sprite(s, k, t) }
            }
        }
        if f.o < 0.998 && !leafFill {
            c.opacity *= f.o
            c.drawLayer { contents($0) }
        } else {
            contents(c)
        }
    }

    /// An entrance's sprites over the launcher.
    static func entrance(_ c: GraphicsContext, _ plan: EntrancePlan, _ t: Double) {
        for sp in plan.sprites { sprite(c, sp, t) }
    }

    /// The idle call's mascot on its stage over the launcher (idleCall.ts
    /// perform): the owner's mascot, each part of the drawing its own layer
    /// turned about that character's joints, and the white rings where a
    /// knock or tap lands.
    static func idleCall(_ ctx: GraphicsContext, _ perf: LauncherIdleCall.Performance, _ layers: MascotArt.Layers, shape: String, _ t: Double) {
        let n = perf.mascot.size
        let box = Keyframes.evaluate(perf.selfTracks, t, base: perf.mascot.base)
        if box.o > 0.002 {
            var c = ctx
            c.translateBy(x: perf.mascot.x, y: perf.mascot.y)
            transform(&c, n / 2, n / 2, box.tx, box.ty, box.r, box.sx, box.sy)
            c.opacity *= box.o
            c.drawLayer { c in
                MascotDraw.figure(c, layers, size: n, bust: false, shape: shape) { name in
                    guard let tracks = perf.parts[name] else { return nil }
                    return MascotDraw.Part(v: Keyframes.evaluate(tracks, t, base: LauncherIdleCall.partBase[name]))
                }
            }
        }
        for r in perf.ripples {
            let v = Keyframes.evaluate([r.track], t, base: ["o": 0])
            if v.o <= 0.002 { continue }
            var c = ctx
            c.translateBy(x: r.x, y: r.y)
            c.scaleBy(x: v.sx, y: v.sy)
            let rad = r.d / 2 - 1.25
            let ring = Path(ellipseIn: CGRect(x: -rad, y: -rad, width: rad * 2, height: rad * 2))
            c.stroke(ring, with: .color(css("#0f172a", 0.12 * v.o)), lineWidth: 3.5)
            c.stroke(ring, with: .color(css("#ffffff", 0.9 * v.o)), lineWidth: 2.5)
        }
    }

    /// The bounce's contact shadow on the screen under the launcher (w x h its box).
    static func bounceShadow(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ v: FxValues) {
        if v.o <= 0.002 { return }
        let sw = w * 0.76
        let sh = max(6, h * 0.2)
        var c = ctx
        c.translateBy(x: w * 0.12, y: h * 0.9)
        transform(&c, sw / 2, sh / 2, v.tx, v.ty, v.r, v.sx, v.sy)
        c.translateBy(x: sw / 2, y: sh / 2)
        c.scaleBy(x: 1, y: sh / sw)
        let r = sw / 2
        c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
               with: .radialGradient(Gradient(colors: [css("#0f172a", 0.55 * v.o), css("#0f172a", 0)]), center: .zero, startRadius: 0, endRadius: r))
    }

    /// The shine's gloss band sweeping across the button (drawn inside its clip; w x h the button).
    static func gloss(_ ctx: GraphicsContext, _ w: Double, _ h: Double, _ v: FxValues) {
        let bw = w * glossWidth
        let bh = h * glossHeight
        var c = ctx
        c.translateBy(x: 0, y: h * glossTop)
        transform(&c, bw / 2, bh / 2, v.tx + v.txp / 100 * bw, v.ty, v.r, v.sx, v.sy)
        c.fill(Path(CGRect(x: 0, y: 0, width: bw, height: bh)),
               with: .linearGradient(Gradient(colors: [css("#ffffff", 0), css("#ffffff", 0.75), css("#ffffff", 0)]), startPoint: .zero, endPoint: CGPoint(x: bw, y: 0)))
    }

    /// The orbit's spark: a white dot with a soft glow of the launcher's colour.
    static func orbit(_ c: GraphicsContext, _ w: Double, _ h: Double, _ v: FxValues, glow: String) {
        if v.o <= 0.002 { return }
        let p = LauncherAttention.orbitPoint(w, h, v.od / 100)
        let r = orbitDot / 2
        let g = r + 6
        c.fill(Path(ellipseIn: CGRect(x: p.x - g, y: p.y - g, width: g * 2, height: g * 2)),
               with: .radialGradient(Gradient(colors: [css(glow, v.o), css(glow, 0)]), center: p, startRadius: 0, endRadius: g))
        c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(css("#ffffff", v.o)))
    }
}

/// The speech bubble over the mascot (.cb-ic-bubble), its tail on the mascot `tail` pt from its left edge.
@available(iOS 15.0, *)
struct IdleCallBubble: View {
    let line: String
    let tail: CGFloat
    let onTap: () -> Void

    var body: some View {
        Text(line)
            .font(.system(size: 13.5, weight: .bold))
            .foregroundColor(Color(hex: "#0f172a"))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color(hex: "#0f172a").opacity(0.22), radius: 10, x: 0, y: 4)
            )
            // The tail: a white square turned 45deg, half under the box.
            .background(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(45))
                    .offset(x: tail - 6, y: 6)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(line) Open the chat")
            .accessibilityAddTraits(.isButton)
    }
}
