//
//  MascotView.swift
//  Conferbot
//
//  The owner's mascot drawn (the React Native SDK's components/Mascot):
//  its layers (Core/Customization/MascotArt.swift) stacked back to front in
//  a size x size box, each moving part its own layer turned about its joint
//  (MascotArt.origins), the transform list in its own order. No filters, as
//  in RN. SwiftUI Canvas through FxSvg (iOS 15), each frame evaluated from
//  the keyframes (Keyframes.swift) at the time since the mood began.
//
//    - `MascotView` (public): the mascot in a mood (idle, wave, think,
//      happy), for an app's own screens (the home screen's `mascot:` slot).
//    - `LauncherMascotView`: the "mascot" launcher style, the bust on the
//      button, blinking; a reply landing while closed makes it hop and smile.
//    - `TypingMascotView`, `TypingPencilView`, `TypingShimmerView`: the
//      typing bubble's mascot, pencil and shimmer styles.
//
//  Reduce Motion: everything still, the happy smile kept.
//

import SwiftUI

@available(iOS 15.0, *)
enum MascotDraw {
    /// A part's values and the order its transform list draws in.
    struct Part {
        var v: FxValues
        var order = "trs"
    }

    /// Turns `c` about `pivot` (pt in the box): translate (drawing units × k), rotate, scale, in `order`.
    static func turn(_ c: inout GraphicsContext, _ p: Part, pivot: (Double, Double), k: Double) {
        let v = p.v
        c.translateBy(x: pivot.0, y: pivot.1)
        for op in p.order {
            switch op {
            case "t": if v.tx != 0 || v.ty != 0 { c.translateBy(x: v.tx * k, y: v.ty * k) }
            case "r": if v.r != 0 { c.rotate(by: .degrees(v.r)) }
            case "s": if v.sx != 1 || v.sy != 1 { c.scaleBy(x: v.sx, y: v.sy) }
            default: break
            }
        }
        c.translateBy(x: -pivot.0, y: -pivot.1)
    }

    /// The figure in a size x size box at the context's origin. `part(name)`
    /// gives a moving part's values (shadow, body, arm, look, lid, brow,
    /// smile, o, grin), nil at rest; the blinking lids, the o and the grin are
    /// drawn only when they move (the lids rest open), the grin also with `grin`.
    static func figure(_ ctx: GraphicsContext, _ layers: MascotArt.Layers, size n: Double, bust: Bool, shape: String,
                       grin: Bool = false, part: (String) -> Part? = { _ in nil }) {
        let k = MascotArt.unit(n, bust: bust)
        let joints = MascotArt.origins(MascotArt.Look(shape: shape))
        func pt(_ p: (Double, Double)) -> (Double, Double) { MascotArt.point(p, n, bust: bust) }
        func layer(_ c: GraphicsContext, _ svg: String?, _ name: String? = nil, _ pivot: (Double, Double) = (50, 50), opacity: Double = 1) {
            guard let svg = svg else { return }
            var s = c
            if let name = name, let p = part(name) {
                if p.v.o <= 0.002 || p.v.sx == 0 || p.v.sy == 0 { return }
                turn(&s, p, pivot: pt(pivot), k: k)
                s.opacity *= p.v.o
            }
            s.opacity *= opacity
            if s.opacity <= 0.002 { return }
            FxSvg.draw(s, svg, n, n)
        }
        layer(ctx, layers.shadow, "shadow", (50, shape == "ghost" ? 99 : 95))
        var b = ctx
        if let p = part("body") {
            turn(&b, p, pivot: pt(joints.body), k: k)
            b.opacity *= p.v.o
        }
        layer(b, layers.tail)
        layer(b, layers.armBack, "arm", joints.arm)
        layer(b, layers.body)
        layer(b, layers.look, "look", joints.look)
        layer(b, layers.face)
        // The blinking lids rest open (scaleY 0 on the web): not drawn until a blink moves them.
        if part("lid") != nil { layer(b, layers.lids, "lid", joints.lid) }
        layer(b, layers.cover)
        layer(b, layers.brows, "brow", joints.brow)
        layer(b, layers.armFront, "arm", joints.arm)
        layer(b, layers.smile, "smile", opacity: part("smile") == nil && grin ? 0 : 1)
        if part("o") != nil { layer(b, layers.o, "o") }
        if part("grin") != nil || grin { layer(b, layers.grin, "grin") }
        layer(b, layers.top)
    }

    /// A mood's parts at t ms (MascotMoods.plan), the lids from their open rest.
    static func moodParts(_ plan: MascotMoods.Plan, _ t: Double) -> [String: Part] {
        var out: [String: Part] = [:]
        for (name, tracks) in plan.parts where !tracks.isEmpty {
            out[name] = Part(v: Keyframes.evaluate(tracks, t, base: name == "lid" ? ["sy": 0] : nil), order: Keyframes.transformOrder(tracks[0]))
        }
        return out
    }

    /// The layers for a look, worked out once per look, pose, colour and framing.
    private static var cache: [String: MascotArt.Layers] = [:]
    static func layers(_ accent: String, arm: String, look: MascotArt.Look, bust: Bool) -> MascotArt.Layers {
        let key = "\(accent)|\(arm)|\(look.shape)|\(look.eyes)|\(look.accessory)|\(look.color)|\(bust)"
        if let l = cache[key] { return l }
        let l = MascotArt.layers(accent, arm: arm, look: look, bust: bust)
        if cache.count > 64 { cache.removeAll() }
        cache[key] = l
        return l
    }

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
}

/// The owner's mascot (web art3d.ts mascot()), for an app's own screens -
/// the home screen's `mascot:` slot, say - in one of its moods: idle
/// (blinks), wave, think or happy. Reduce Motion: still, the happy smile kept.
///
///     HomeScreenView(mascot: AnyView(MascotView(ConferBot.shared.home.model!.mascot, size: 72, mood: "wave")))
@available(iOS 15.0, *)
public struct MascotView: View {
    let look: MascotArt.Look
    let accent: String
    let size: Double
    let mood: String
    let arm: String
    let bust: Bool
    let waveCount: Double?
    @State private var start = Date()

    /// `look` the owner's mascot (ConferBot.shared.customizations.mascot, or Home.Model.mascot.look);
    /// `accent` the colour it is drawn in when the owner chose none (the launcher's).
    public init(look: MascotArt.Look, accent: String, size: Double = 64, mood: String = "idle", arm: String? = nil, bust: Bool = false, waveCount: Double? = nil) {
        self.look = look
        self.accent = accent
        self.size = size
        self.mood = MascotMoods.moods.contains(mood) ? mood : "idle"
        self.arm = arm ?? (mood == "wave" ? "wave" : "down")
        self.bust = bust
        self.waveCount = waveCount
    }

    /// The home model's mascot.
    public init(_ mascot: Home.Mascot, size: Double = 64, mood: String = "idle", arm: String? = nil, bust: Bool = false) {
        self.init(look: mascot.look, accent: mascot.accent, size: size, mood: mood, arm: arm, bust: bust)
    }

    public var body: some View {
        let plan = MascotMoods.plan(mood, arm: arm, bust: bust, waveCount: waveCount, reduced: MascotDraw.reduceMotion)
        let layers = MascotDraw.layers(accent, arm: arm, look: look, bust: bust)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: plan.parts.isEmpty)) { tl in
            let t = tl.date.timeIntervalSince(start) * 1000
            Canvas { ctx, _ in
                let parts = MascotDraw.moodParts(plan, t)
                MascotDraw.figure(ctx, layers, size: size, bust: bust, shape: look.shape, grin: plan.grin) { parts[$0] }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onChange(of: mood) { _ in start = Date() }
    }
}

/// The soft light button behind the launcher's mascot (launcherStyle.ts): white at 35% 30%, to the launcher colour at 14% on white.
@available(iOS 15.0, *)
func mascotButtonXml(_ light: String) -> String {
    ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" preserveAspectRatio="none"><defs><radialGradient id="g" cx="0.35" cy="0.3" r="0.955"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="\##(light)"/></radialGradient></defs><rect width="100" height="100" fill="url(#g)"/></svg>"##
}

/// The "mascot" launcher style (launcherStyle.ts): the owner's mascot, its
/// bust at `scale`% of the button, centred and lifted (translate -50% -56%)
/// so its ears and hat peek over the rim, blinking now and then. A reply
/// landing while the chat is closed makes it hop for joy and smile
/// (cheerLauncherMascot), then it goes back to blinking; a reply mid-hop
/// starts it again. Reduce Motion keeps only the smile.
@available(iOS 15.0, *)
struct LauncherMascotView: View {
    let mascot: LauncherMascotLook
    let width: Double
    let height: Double
    /// The unread count: a rise while closed is a reply landing.
    let unread: Int
    let chatOpen: Bool
    @State private var lastUnread: Int?
    @State private var cheerAt: Date?
    @State private var start = Date()

    var body: some View {
        let n = min(width, height) * mascot.scale / 100
        let layers = MascotDraw.layers(mascot.accent, arm: "down", look: mascot.look, bust: true)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: chatOpen)) { tl in
            let happy = cheerAt.map { tl.date.timeIntervalSince($0) * 1000 < MascotMoods.cheerMs } ?? false
            let plan = MascotMoods.plan(happy ? "happy" : "idle", bust: true, reduced: MascotDraw.reduceMotion)
            let t = tl.date.timeIntervalSince(happy ? cheerAt! : start) * 1000
            Canvas { ctx, _ in
                let parts = chatOpen ? [:] : MascotDraw.moodParts(plan, t)
                var c = ctx
                c.translateBy(x: width / 2 - n / 2, y: height / 2 - n * 0.56)
                MascotDraw.figure(c, layers, size: n, bust: true, shape: mascot.look.shape, grin: plan.grin) { parts[$0] }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { lastUnread = unread }
        .onChange(of: unread) { u in
            let rose = u > (lastUnread ?? u)
            lastUnread = u
            // A fresh mood (the hop starts again), then back to blinking.
            if rose && !chatOpen { cheerAt = Date() }
        }
    }
}

/// The "mascot" typing style (chatChrome.ts, polish.css .cb-typing--mascot):
/// the bot's mascot, its head framed tight (32 x 32), gently swaying about
/// 50% 90% of its box, blinking and glancing at three thought dots rising
/// beside it in the bubble's text colour. Still under Reduce Motion.
@available(iOS 15.0, *)
struct TypingMascotView: View {
    let look: MascotArt.Look
    let accent: String
    let ink: Color
    @State private var start = Date()

    var body: some View {
        let T = MascotMoods.Typing.self
        let n = T.size
        let reduced = MascotDraw.reduceMotion
        let layers = MascotDraw.layers(accent, arm: "down", look: look, bust: true)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduced)) { tl in
            let t = reduced ? 0 : tl.date.timeIntervalSince(start) * 1000
            HStack(alignment: .center, spacing: 6) {
                Canvas { ctx, _ in
                    var c = ctx
                    if !reduced {
                        let sway = Keyframes.evaluate([T.sway], t)
                        MascotDraw.turn(&c, MascotDraw.Part(v: sway, order: "rts"), pivot: T.origin, k: 1)
                    }
                    let lid = reduced ? nil : MascotDraw.Part(v: Keyframes.evaluate([T.blink], t, base: ["sy": 0]), order: "trs")
                    let look = reduced ? nil : MascotDraw.Part(v: Keyframes.evaluate([T.glance], t), order: Keyframes.transformOrder(T.glance))
                    MascotDraw.figure(c, layers, size: n, bust: true, shape: self.look.shape) { $0 == "lid" ? lid : $0 == "look" ? look : nil }
                }
                .frame(width: n, height: n)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<T.dots.count, id: \.self) { i in
                        let d = T.dots[i]
                        Circle().fill(ink)
                            .frame(width: d.d, height: d.d)
                            .opacity(reduced ? 0.25 : Keyframes.evaluate([d.track], t, base: ["o": 0.25]).o)
                            .padding(.bottom, d.up)
                    }
                }
                .frame(height: 16, alignment: .bottom)
            }
        }
    }
}

/// The "pencil" typing style (polish.css .cb-typing--pencil): a 44 x 16 line
/// that writes itself in 2s (stroke-dashoffset 60 to 0, then fades), the
/// pencil in the launcher colour riding its tip. Still under Reduce Motion
/// (the line drawn, the pencil at its end).
@available(iOS 15.0, *)
struct TypingPencilView: View {
    let accent: String
    let ink: Color
    let inkHex: String
    @State private var start = Date()

    private var pencilXml: String {
        ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 -6 20 20"><path d="M0 0 L4 -4 L14 6 L10 10 Z" fill="\##(accent)"/><path d="M0 0 L2.6 -2.6 L1.2 1.2 Z" fill="\##(inkHex)"/><path d="M10 10 L14 6 L15.6 7.6 L11.6 11.6 Z" fill="#f59e9e"/></svg>"##
    }

    var body: some View {
        let P = MascotMoods.Pencil.self
        let reduced = MascotDraw.reduceMotion
        let line = Path.fromSVG(P.line)
        let xml = pencilXml
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduced)) { tl in
            let t = tl.date.timeIntervalSince(start) * 1000
            Canvas { ctx, _ in
                let w = reduced ? FxValues.rest() : Keyframes.evaluate([P.write], t, base: ["dash": P.dash])
                var lc = ctx
                lc.opacity = w.o
                lc.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [P.dash, P.dash], dashPhase: reduced ? 0 : w.dash))
                let pen = reduced ? nil : Keyframes.evaluate([P.pencil], t)
                var pc = ctx
                pc.translateBy(x: pen?.tx ?? P.rest.0, y: pen?.ty ?? P.rest.1)
                pc.translateBy(x: -2, y: -6)
                FxSvg.draw(pc, xml, 20, 20)
            }
            .frame(width: 44, height: 16)
        }
    }
}

/// The "shimmer" typing style (polish.css .cb-typing--shimmer): "Typing"
/// with a light sweeping across it (1.6s), its three dots pulsing 0.2s
/// apart. Still under Reduce Motion.
@available(iOS 15.0, *)
struct TypingShimmerView: View {
    let ink: Color
    @State private var start = Date()

    var body: some View {
        let reduced = MascotDraw.reduceMotion
        let dot = MascotMoods.Typing.dots[0].track
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduced)) { tl in
            let t = tl.date.timeIntervalSince(start) * 1000
            HStack(spacing: 0) {
                Text("Typing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(reduced ? ink : .clear)
                    .overlay {
                        if !reduced {
                            GeometryReader { g in
                                // background-size 260%, its position 100% to 0 over 1.6s: the dim band crosses the word.
                                let w = g.size.width
                                let bw = w * 2.6
                                let p = 1 - (t.truncatingRemainder(dividingBy: 1600) / 1600)
                                LinearGradient(stops: [
                                    .init(color: ink, location: 0), .init(color: ink, location: 0.38),
                                    .init(color: ink.opacity(0.35), location: 0.5),
                                    .init(color: ink, location: 0.62), .init(color: ink, location: 1),
                                ], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: bw, height: g.size.height)
                                    .offset(x: (w - bw) * p)
                            }
                            .mask(Text("Typing").font(.system(size: 13, weight: .semibold)))
                        }
                    }
                ForEach(0..<3, id: \.self) { i in
                    Text(".")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ink)
                        .opacity(reduced ? 1 : Keyframes.evaluate([dot.withDelay(Double(i) * 200)], t, base: ["o": 0.25]).o)
                }
            }
        }
    }
}
