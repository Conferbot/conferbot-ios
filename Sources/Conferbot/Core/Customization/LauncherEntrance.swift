//
//  LauncherEntrance.swift
//  Conferbot
//
//  Launcher entrance, as the web widget plays it (conferbot-widget
//  src/ts/launcher/entrance.ts): how the launcher arrives the first time it
//  shows, instead of simply being there.
//
//    customizations.launcherEntrance:
//      "classic"   (default) it just appears;
//      "lightning" a bolt strikes the corner, and the launcher is in the flash;
//      "rocket"    a rocket comes down, burns to land, and becomes the launcher;
//      "portal"    a ring of light opens and the launcher rises out of it;
//      "ufo"       a saucer flies in and beams the launcher down;
//      "drop"      it falls in, squashes on landing, and bounces;
//      "confetti"  it pops in with a burst of confetti;
//      "coin"      it flips in like a coin and catches the light;
//      "meteor", "magic", "parachute", "plane", "egg" (newer, same rules).
//
//  The rules (LauncherFxControllers.swift keeps them): once per app session
//  per bot and entrance; never when the chat is open; nothing with Reduce
//  Motion. The launcher is held invisible until the effect reveals it (it
//  still takes a tap, which ends the entrance and opens the chat). While it
//  lands the greeting card stays hidden; 150ms after it has landed the card
//  fades up (0.9s). Attention and the idle call wait for it.
//
//  Each effect is a set of sprites (drawings with their Web Animations
//  tracks) on a stage laid over the launcher, plus the launcher's own
//  arrival track. Filters (brightness, glows, blur) are left out, as in RN;
//  the movement, timing and opacity are the web's. Ported from the React
//  Native SDK's core/launcherEntrance.ts. Pure: the launcher drives the clock.
//

import Foundation

/// The stage laid over the launcher. Sizes come from `unit`, the button's
/// short side; (cx, cy) is its centre; `above` the distance from its bottom
/// to the top of the screen; `inward` -1 when it sits on the right. `left`,
/// `top`: the launcher's top-left on the screen; `winW`, `winH`: the screen.
public struct EntranceStage {
    public var w: Double
    public var h: Double
    public var unit: Double
    public var cx: Double
    public var cy: Double
    public var above: Double
    public var inward: Double
    public var accent: String
    public var left: Double
    public var top: Double
    public var winW: Double
    public var winH: Double
}

/// One drawing on the stage, with its animations. Children sit in its box and move with it.
public struct FxSprite {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    /// The drawing (svg markup for w x h), or a plain box of a colour.
    public var svg: String?
    public var fill: String?
    public var radius: Double?
    /// The pivot, in px inside the box (default: its centre).
    public var origin: (Double, Double)?
    /// Its own static values (an opacity of 0 until it plays, a fixed rotate...).
    public var base: [String: Double]?
    public var tracks: [Track]
    /// offset-path: the box's centre follows this path (px from the box's own top-left), turning with it.
    public var path: String?
    /// A stroke drawn on (stroke-dashoffset 100 -> 0), shown as a wipe of the drawing: "down" or "right".
    public var wipe: String?
    /// Children are clipped to the box, with this corner radius.
    public var clip: Double?
    /// `left` animates as a share of this width (px).
    public var leftOf: Double?
    public var children: [FxSprite]

    public init(x: Double, y: Double, w: Double, h: Double, svg: String? = nil, fill: String? = nil, radius: Double? = nil,
                origin: (Double, Double)? = nil, base: [String: Double]? = nil, tracks: [Track] = [], path: String? = nil,
                wipe: String? = nil, clip: Double? = nil, leftOf: Double? = nil, children: [FxSprite] = []) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.svg = svg
        self.fill = fill
        self.radius = radius
        self.origin = origin
        self.base = base
        self.tracks = tracks
        self.path = path
        self.wipe = wipe
        self.clip = clip
        self.leftOf = leftOf
        self.children = children
    }
}

public struct EntrancePlan {
    /// When the launcher itself appears (ms from the start), and how.
    public var revealAt: Double
    public var arrive: Track
    /// When the whole effect is over and the stage goes.
    public var total: Double
    public var sprites: [FxSprite]
    /// Drawn just behind the launcher (it rises out of it).
    public var behind = false
}

/// A sprite's drawn values at t ms: its translate (px, the box's own share
/// and an animated `left` folded in, and a motion path's point), rotate, the
/// scale (a 3D turn about x / y, unlit and without perspective as on the
/// web, is the cosine of its angle), opacity and how much of a wipe shows.
public struct SpriteFrame {
    public var tx: Double
    public var ty: Double
    public var r: Double
    public var sx: Double
    public var sy: Double
    public var o: Double
    public var reveal: Double
}

public enum LauncherEntrance {
    public static let modes = ["classic", "lightning", "rocket", "portal", "ufo", "drop", "confetti", "coin", "meteor", "magic", "parachute", "plane", "egg"]

    public static func normalize(_ value: Any?) -> String {
        if let s = value as? String, modes.contains(s) { return s }
        return "classic"
    }

    /// Whether this mount plays an entrance.
    public static func shouldPlay(_ mode: String, reducedMotion: Bool, chatOpen: Bool, played: Bool) -> Bool {
        mode != "classic" && !reducedMotion && !chatOpen && !played
    }

    /// After the launcher lands: a beat, then the rest fades up.
    public static let settleBeatMs = 150.0
    public static let settleFadeMs = 900.0

    /// The launcher must be laid out this long before the effect starts.
    public static let startMs = 60.0

    /// The greeting (and anything else beside the launcher) fading up after the landing (cb-ent-reveal).
    public static let settleReveal = Track.of([
        ["opacity": 0, "translate": "0 10px"],
        ["opacity": 1, "translate": "0 0"],
    ], duration: settleFadeMs, easing: "cubic-bezier(0.22, 1, 0.36, 1)", fill: "both")

    public static func stage(width: Double, height: Double, position: String, screenWidth: Double, screenHeight: Double, side: Double, bottom: Double, accent: String) -> EntranceStage {
        let left = position == "right" ? screenWidth - side - width : side
        let top = screenHeight - bottom - height
        return EntranceStage(w: width, h: height, unit: min(width, height), cx: width / 2, cy: height / 2, above: top + height,
                             inward: left + width / 2 > screenWidth / 2 ? -1 : 1, accent: accent, left: left, top: top,
                             winW: screenWidth, winH: screenHeight)
    }

    public struct Timeline {
        public var landAt: Double
        public var landedAt: Double
        public var settleAt: Double
        public var endAt: Double
    }

    /// When each phase starts: the landing, the rest fading up, the end.
    public static func timeline(_ p: EntrancePlan) -> Timeline {
        let landedAt = p.revealAt + p.arrive.options.duration
        return Timeline(landAt: p.revealAt, landedAt: landedAt, settleAt: landedAt + settleBeatMs,
                        endAt: max(p.total, landedAt + settleBeatMs + settleFadeMs) + 60)
    }

    private static let colors = ["#f59e0b", "#ec4899", "#22c55e", "#3b82f6", "#a855f7", "#ef4444"]

    /// The web's seeded random (a small LCG), 0...1.
    public static func seeded(_ seed: Int) -> () -> Double {
        var r = seed == 0 ? 1 : seed
        return {
            r = (r * 9301 + 49297) % 233280
            return Double(r) / 233280
        }
    }

    public typealias Pt = (Double, Double)

    /// A lightning channel by midpoint displacement: points, top to bottom.
    public static func boltPoints(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ spread: Double, _ rand: () -> Double, depth: Int = 6) -> [Pt] {
        var pts: [Pt] = [(x1, y1), (x2, y2)]
        var disp = spread
        for _ in 0..<depth {
            var next: [Pt] = [pts[0]]
            for i in 1..<pts.count {
                let (ax, ay) = pts[i - 1]
                let (bx, by) = pts[i]
                let mx = (ax + bx) / 2 + (rand() - 0.5) * disp
                let my = (ay + by) / 2 + (rand() - 0.5) * disp * 0.25
                next.append((mx, my))
                next.append(pts[i])
            }
            pts = next
            disp *= 0.55
        }
        return pts
    }

    private static func n(_ x: Double) -> String { Keyframes.jsNum(x) }
    private static func px(_ x: Double) -> String { "\(Keyframes.jsNum(x))px" }
    private static func deg(_ x: Double) -> String { "\(Keyframes.jsNum(x))deg" }
    private static func tr(_ x: Double, _ y: Double) -> String { "\(px(x)) \(px(y))" }

    private static func toPath(_ pts: [Pt]) -> String { "M" + pts.map { "\(Keyframes.fixed($0.0, 1)),\(Keyframes.fixed($0.1, 1))" }.joined(separator: " L") }
    private static func svgOf(_ w: Double, _ h: Double, _ vb: String, _ inner: String) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(Keyframes.fixed(w, 2))\" height=\"\(Keyframes.fixed(h, 2))\" viewBox=\"\(vb)\">\(inner)</svg>"
    }

    private static func play(_ keyframes: [Keyframe], duration: Double, delay: Double? = nil, iterations: Double? = nil, easing: String? = nil, fill: String? = nil) -> Track {
        Track.of(keyframes, duration: duration, delay: delay, iterations: iterations, easing: easing, fill: fill)
    }

    private typealias Stop = FxPaint.Stop

    // MARK: - Shared pieces

    /// A soft smoke puff at (x, y), drifting by (dx, dy) as it grows and fades.
    private static func puff(_ x: Double, _ y: Double, _ d: Double, _ delay: Double, _ dx: Double, _ dy: Double, _ dur: Double = 900, _ tint: String = "rgba(203, 213, 225, 0.9)") -> FxSprite {
        FxSprite(
            x: x - d / 2, y: y - d / 2, w: d, h: d,
            svg: FxPaint.radialDisc(d, d, [Stop(tint), "rgba(148, 163, 184, 0)"]),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0, "translate": "0 0", "scale": 0.4],
                ["opacity": 0.9, "offset": 0.2],
                ["opacity": 0, "translate": tr(dx, dy), "scale": 1.9],
            ], duration: dur, delay: delay, easing: "ease-out", fill: "forwards")])
    }

    /// A ground shockwave: a flattened ring racing out from under the button.
    private static func shockwave(_ s: EntranceStage, _ delay: Double, _ color: String = "rgba(255, 255, 255, 0.9)", _ spread: Double = 2.6) -> FxSprite {
        let w = s.w + s.unit * 0.4
        let h = s.unit * 0.5
        let e = "<ellipse cx=\"\(n(w / 2))\" cy=\"\(n(h / 2))\" rx=\"\(n(w / 2 - 1))\" ry=\"\(n(h / 2 - 1))\" fill=\"none\" stroke=\"\(color)\""
        return FxSprite(
            x: s.cx - w / 2, y: s.h - s.unit * 0.25, w: w, h: h,
            // A 2px border with a soft glow (box-shadow 0 0 10px).
            svg: svgOf(w, h, "0 0 \(n(w)) \(n(h))", "\(e) stroke-width=\"6\" stroke-opacity=\"0.25\"/>\(e) stroke-width=\"2\"/>"),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0.95, "scale": 0.4],
                ["opacity": 0, "scale": spread],
            ], duration: 650, delay: delay, easing: "cubic-bezier(0.1, 0.8, 0.3, 1)", fill: "forwards")])
    }

    private static let star4 = "M6 0 L7.2 4.8 L12 6 L7.2 7.2 L6 12 L4.8 7.2 L0 6 L4.8 4.8 Z"

    /// Twinkling four-point stars round the button.
    private static func sparkles(_ s: EntranceStage, _ count: Int, _ delay: Double, _ color: String = "#fde047", _ reach: Double = 1) -> [FxSprite] {
        (0..<count).map { i in
            let a = (Double(i) / Double(count)) * Double.pi * 2 + 0.4
            let x = s.cx + cos(a) * (s.w / 2 + s.unit * 0.3 * reach)
            let y = s.cy + sin(a) * (s.h / 2 + s.unit * 0.3 * reach)
            let size = Double(9 + (i % 3) * 4)
            return FxSprite(
                x: x - size / 2, y: y - size / 2, w: size, h: size,
                svg: svgOf(size, size, "0 0 12 12", "<path d=\"\(star4)\" fill=\"\(color)\"/>"),
                base: ["o": 0],
                tracks: [play([
                    ["opacity": 0, "scale": 0, "rotate": "0deg"],
                    ["opacity": 1, "scale": 1.25, "rotate": "60deg", "offset": 0.45],
                    ["opacity": 0, "scale": 0.3, "rotate": "120deg"],
                ], duration: 620, delay: delay + Double(i) * 55, easing: "ease-out", fill: "forwards")])
        }
    }

    /// Bits thrown up from the button's base that fall back with gravity.
    private static func debris(_ s: EntranceStage, _ count: Int, _ delay: Double, _ colors: [String], _ size: Double = 5, _ height: Double = 1) -> [FxSprite] {
        (0..<count).map { i in
            let dir: Double = i % 2 == 1 ? 1 : -1
            let dx = dir * (s.w / 2 + s.unit * (0.2 + Double(i % 4) * 0.22))
            let up = s.unit * (0.5 + Double((i * 3) % 5) * 0.16) * height
            let d = size + Double(i % 3) * 2
            return FxSprite(
                x: s.cx - d / 2, y: s.h - d, w: d, h: d * 0.8,
                fill: colors[i % colors.count], radius: d * 0.35,
                base: ["o": 0],
                tracks: [play([
                    ["opacity": 1, "translate": "0 0", "rotate": "0deg", "easing": "cubic-bezier(0.2, 0.7, 0.4, 1)"],
                    ["opacity": 1, "translate": "\(px(dx * 0.6)) -\(px(up))", "rotate": deg(dir * 200), "offset": 0.4, "easing": "cubic-bezier(0.5, 0, 0.9, 0.5)"],
                    ["opacity": 0, "translate": tr(dx, s.unit * 0.2), "rotate": deg(dir * 420)],
                ], duration: 820, delay: delay, fill: "forwards")])
        }
    }

    /// A launcher arrival that lands with a jolt (for impacts).
    private static func joltArrival(_ duration: Double, _ from: Keyframe) -> Track {
        var first: Keyframe = ["opacity": 0, "scale": 0.4, "translate": "0 0"]
        for (k, v) in from { first[k] = v }
        return play([
            first,
            ["opacity": 1, "scale": 1.15, "translate": "-3px 0", "offset": 0.18],
            ["scale": 0.95, "translate": "3px 1px", "offset": 0.3],
            ["scale": 1.03, "translate": "-2px 0", "offset": 0.42],
            ["scale": 1, "translate": "1px 0", "offset": 0.54],
            ["opacity": 1, "scale": 1, "translate": "0 0", "filter": "none"],
        ], duration: duration, easing: "linear")
    }

    /// A sprite's tracks delayed (lightning: everything after the storm gathers).
    private static func later(_ sp: FxSprite, _ ms: Double) -> FxSprite {
        var out = sp
        out.tracks = sp.tracks.map { $0.withDelay($0.options.delay + ms) }
        out.children = sp.children.map { later($0, ms) }
        return out
    }

    // A storm gathers (the corner of the screen dims), then a blue-white bolt
    // with forks races down, flashes, restrikes and fades; sky light, a burst,
    // crackles and a wisp of smoke at the strike point.
    private static func lightning(_ s: EntranceStage, _ rand: () -> Double) -> EntrancePlan {
        let dark = 240.0
        let sprites = [FxSprite(
            x: -s.left, y: -s.top, w: s.winW, h: s.winH,
            svg: FxPaint.radialWash(s.winW, s.winH, s.left + s.cx, s.top, s.winW * 0.6, s.winH * 0.85,
                                    ["rgba(8, 12, 32, 0.55)", .at("rgba(8, 12, 32, 0.18)", 55), .at("rgba(8, 12, 32, 0)", 80)]),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0],
                ["opacity": 1, "offset": 0.2],
                ["opacity": 1, "offset": 0.45],
                ["opacity": 0],
            ], duration: 1150, easing: "ease-in-out", fill: "forwards")])]
        var after: [FxSprite] = []
        let h = min(s.above + s.cy, 560)
        let bw = 220.0
        let x = bw / 2
        var main = boltPoints(x, 0, x, h, max(24, h * 0.22), rand)
        main[main.count - 1] = (x, h)
        var branches: [String] = []
        for i in 0..<3 {
            let at = main[Int((Double(main.count) * (0.25 + Double(i) * 0.18 + rand() * 0.08)).rounded(.down))]
            let dir: Double = rand() > 0.5 ? 1 : -1
            let len = h * (0.18 + rand() * 0.16)
            let b = boltPoints(at.0, at.1, at.0 + dir * len * (0.4 + rand() * 0.4), at.1 + len, len * 0.35, rand, depth: 4)
            branches.append(toPath(b))
        }
        let all = [toPath(main)] + branches
        // Glow, halo and core; the blurred layers are a little fainter without the blur.
        func layer(_ d: String, _ width: Double, _ color: String, _ opacity: Double) -> String {
            "<path d=\"\(d)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"\(n(width))\" stroke-opacity=\"\(n(opacity))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
        }
        let bolt = all.indices.map { i in layer(all[i], i > 0 ? 8 : 16, "#6d9eff", (i > 0 ? 0.35 : 0.45) * 0.55) }.joined() +
            all.indices.map { i in layer(all[i], i > 0 ? 2.6 : 5, "#c7dcff", (i > 0 ? 0.7 : 0.95) * 0.85) }.joined() +
            all.indices.map { i in layer(all[i], i > 0 ? 1 : 2, "#ffffff", 1) }.joined()
        after.append(FxSprite(
            x: s.cx - x, y: s.cy - h, w: bw, h: h,
            svg: svgOf(bw, h, "0 0 \(n(bw)) \(n(h))", bolt),
            base: ["dash": 100],
            tracks: [
                // Stepped leader: every channel races down in ~110ms.
                play([["strokeDashoffset": 100], ["strokeDashoffset": 0]], duration: 110, easing: "linear", fill: "forwards"),
                // Return stroke, a dim beat, one restrike, then the channel fades.
                play([
                    ["opacity": 1],
                    ["opacity": 1, "offset": 0.2],
                    ["opacity": 0.25, "offset": 0.3],
                    ["opacity": 1, "offset": 0.38],
                    ["opacity": 0.55, "offset": 0.55],
                    ["opacity": 0],
                ], duration: 560, fill: "forwards"),
            ],
            wipe: "down"))
        // Sky light: the screen lights up blue-white round the strike, twice.
        let skyH = s.top + s.h
        after.append(FxSprite(
            x: -s.left, y: -s.top, w: s.winW, h: skyH,
            svg: FxPaint.radialWash(s.winW, skyH, s.left + s.cx, skyH * 0.55, s.winW * 0.45, skyH * 0.7, ["rgba(210, 226, 255, 0.55)", .at("rgba(210, 226, 255, 0)", 70)]),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0],
                ["opacity": 0.85, "offset": 0.2],
                ["opacity": 0.12, "offset": 0.34],
                ["opacity": 0.6, "offset": 0.42],
                ["opacity": 0],
            ], duration: 620, fill: "forwards")]))
        let d = s.unit * 3.2
        after.append(FxSprite(
            x: s.cx - d / 2, y: s.cy - d / 2, w: d, h: d,
            svg: FxPaint.radialDisc(d, d, ["#ffffff", .at("rgba(186, 212, 255, 0.9)", 30), .at("rgba(109, 158, 255, 0.35)", 55), .at("transparent", 75)]),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0, "scale": 0.2],
                ["opacity": 1, "scale": 1, "offset": 0.25],
                ["opacity": 0.3, "scale": 1.1, "offset": 0.5],
                ["opacity": 0, "scale": 1.45],
            ], duration: 640, delay: 100, easing: "ease-out", fill: "forwards")]))
        // Crackles: tiny arcs that flicker round the button.
        for i in 0..<7 {
            let a = (Double(i) / 7) * Double.pi * 2 + rand()
            let r1 = s.unit * 0.55
            let r2 = s.unit * (0.95 + rand() * 0.35)
            let pts = boltPoints(cos(a) * r1, sin(a) * r1, cos(a) * r2, sin(a) * r2, s.unit * 0.25, rand, depth: 3)
            let x0 = pts.map { $0.0 }.min()! - 2
            let y0 = pts.map { $0.1 }.min()! - 2
            let cw = pts.map { $0.0 }.max()! - x0 + 2
            let ch = pts.map { $0.1 }.max()! - y0 + 2
            after.append(FxSprite(
                x: s.cx + x0, y: s.cy + y0, w: cw, h: ch,
                svg: svgOf(cw, ch, "\(n(x0)) \(n(y0)) \(n(cw)) \(n(ch))", "<path d=\"\(toPath(pts))\" fill=\"none\" stroke=\"#e0ecff\" stroke-width=\"1.6\" stroke-linecap=\"round\"/>"),
                base: ["o": 0],
                tracks: [play([
                    ["opacity": 0],
                    ["opacity": 1, "offset": 0.1],
                    ["opacity": 0.1, "offset": 0.3],
                    ["opacity": 1, "offset": 0.45],
                    ["opacity": 0],
                ], duration: 380, delay: 110 + Double(i) * 35, fill: "forwards")]))
        }
        // A wisp of smoke once it has struck.
        for i in 0..<3 {
            let pd = s.unit * (0.5 + Double(i) * 0.15)
            after.append(FxSprite(
                x: s.cx - pd / 2 + Double(i - 1) * s.unit * 0.25, y: s.cy - pd / 2, w: pd, h: pd,
                svg: FxPaint.radialDisc(pd, pd, ["rgba(203, 213, 225, 0.85)", "rgba(148, 163, 184, 0)"]),
                base: ["o": 0],
                tracks: [play([
                    ["opacity": 0, "translate": "0 0", "scale": 0.5],
                    ["opacity": 0.55, "offset": 0.3],
                    ["opacity": 0, "translate": "0 -\(px(s.unit * 0.9))", "scale": 1.6],
                ], duration: 1100, delay: 320 + Double(i) * 90, easing: "ease-out", fill: "forwards")]))
        }
        return EntrancePlan(
            revealAt: dark + 110,
            arrive: play([
                ["opacity": 0, "scale": 0.4, "translate": "0 0", "filter": "brightness(3) drop-shadow(0 0 18px #9ec5ff)"],
                ["opacity": 1, "scale": 1.16, "translate": "-3px 0", "offset": 0.14, "filter": "brightness(2.2) drop-shadow(0 0 16px #9ec5ff)"],
                ["scale": 0.96, "translate": "3px 1px", "offset": 0.24],
                ["scale": 1.03, "translate": "-2px 0", "offset": 0.34, "filter": "brightness(1.4) drop-shadow(0 0 12px #9ec5ff)"],
                ["scale": 1, "translate": "1px 0", "offset": 0.44],
                ["opacity": 1, "scale": 1, "translate": "0 0", "filter": "brightness(1) drop-shadow(0 0 0 rgba(158, 197, 255, 0))"],
            ], duration: 1100, easing: "ease-out"),
            total: dark + 1500,
            sprites: sprites + after.map { later($0, dark) })
    }

    // A rocket comes down on a flickering flame that burns harder as it slows,
    // leaving a smoke trail; legs unfold for touchdown, a dust ring races out,
    // and the rocket becomes the button.
    private static func rocket(_ s: EntranceStage) -> EntrancePlan {
        let w = s.unit * 0.78
        let h = s.unit * 1.6
        let k = w / 40
        let accent = s.accent
        // The drawing reaches past its 40 x 82 box (the flame, the fins): drawn padded.
        func pad(_ inner: String, _ ox: Double, _ oy: Double, _ tracks: [Track] = []) -> FxSprite {
            FxSprite(x: -5 * k, y: -2 * k, w: 50 * k, h: 92 * k, svg: svgOf(50 * k, 92 * k, "-5 -2 50 92", inner), origin: ((ox + 5) * k, (oy + 2) * k), tracks: tracks)
        }
        let body = "<defs><linearGradient id=\"b\" x1=\"0\" x2=\"1\"><stop offset=\"0\" stop-color=\"#94a3b8\"/><stop offset=\"0.4\" stop-color=\"#ffffff\"/><stop offset=\"0.7\" stop-color=\"#e2e8f0\"/><stop offset=\"1\" stop-color=\"#64748b\"/></linearGradient>" +
            "<radialGradient id=\"w\" cx=\"0.35\" cy=\"0.35\" r=\"0.7\"><stop offset=\"0\" stop-color=\"#e0f2fe\"/><stop offset=\"1\" stop-color=\"\(accent)\"/></radialGradient></defs>" +
            "<path d=\"M20 1 C32 11 34 28 33 46 L33 58 L7 58 L7 46 C6 28 8 11 20 1 Z\" fill=\"url(#b)\" stroke=\"#64748b\" stroke-width=\"1\"/>" +
            "<path d=\"M7 38 L-1 54 L7 57 Z M33 38 L41 54 L33 57 Z\" fill=\"\(accent)\" stroke=\"rgba(15,23,42,0.35)\" stroke-width=\"1\"/>" +
            "<path d=\"M14 10 Q20 4 26 10\" fill=\"none\" stroke=\"\(accent)\" stroke-width=\"3\" stroke-linecap=\"round\"/>" +
            "<circle cx=\"20\" cy=\"27\" r=\"7\" fill=\"url(#w)\" stroke=\"#64748b\" stroke-width=\"1.4\"/>" +
            "<ellipse cx=\"17.5\" cy=\"24.5\" rx=\"2.4\" ry=\"1.6\" fill=\"#fff\" opacity=\"0.9\"/>" +
            "<path d=\"M12 22 V50\" stroke=\"#fff\" stroke-width=\"2\" opacity=\"0.7\" stroke-linecap=\"round\"/>"
        let flame = "<defs><radialGradient id=\"f\" cx=\"0.5\" cy=\"0.1\" r=\"0.9\"><stop offset=\"0\" stop-color=\"#fffbeb\"/><stop offset=\"0.35\" stop-color=\"#fde047\"/><stop offset=\"0.7\" stop-color=\"#fb923c\"/><stop offset=\"1\" stop-color=\"#ef4444\" stop-opacity=\"0\"/></radialGradient></defs>" +
            "<ellipse cx=\"20\" cy=\"70\" rx=\"9\" ry=\"16\" fill=\"url(#f)\"/><ellipse cx=\"20\" cy=\"66\" rx=\"5\" ry=\"10\" fill=\"#fffbeb\" opacity=\"0.9\"/>"
        let legs = "<path d=\"M9 50 L3 64 M31 50 L37 64\" stroke=\"#475569\" stroke-width=\"2.4\" stroke-linecap=\"round\"/>"
        let fall = s.above + h + 40
        let dur = 1250.0
        let decel = "cubic-bezier(0.22, 0.7, 0.3, 1)"
        let legsL = pad(legs, 20, 56, [play([
            ["scale": "1 0"],
            ["scale": "1 0", "offset": 0.7],
            ["scale": "1 1"],
        ], duration: dur, fill: "forwards")])
        let flameL = pad(flame, 20, 58, [
            play([["scale": "1 1"], ["scale": "0.85 1.15"], ["scale": "1.05 0.9"], ["scale": "1 1"]], duration: 120, iterations: (dur / 120).rounded(.up)),
            play([["opacity": 0.8], ["opacity": 1, "offset": 0.7], ["opacity": 0]], duration: dur + 100, fill: "forwards"),
        ])
        let rocket = FxSprite(
            x: s.cx - w / 2, y: s.h - h, w: w, h: h,
            tracks: [
                play([
                    ["translate": "0 -\(px(fall))", "rotate": "-3deg"],
                    ["translate": "0 -10px", "rotate": "1.5deg", "offset": 0.88],
                    ["translate": "0 0", "rotate": "0deg"],
                ], duration: dur, easing: decel, fill: "forwards"),
                play([["opacity": 1, "scale": 1], ["opacity": 0, "scale": 0.5]], duration: 260, delay: dur + 60, easing: "ease-in", fill: "forwards"),
            ],
            children: [legsL, flameL, pad(body, 20, 41)])
        var sprites: [FxSprite] = []
        // Smoke left along the path: where the rocket is at each moment.
        func ease(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
        for i in 0..<9 {
            let t = 0.1 + Double(i) * 0.09
            let y = s.h - (1 - ease(t)) * fall + s.unit * 0.1
            if y < -s.top { continue }
            sprites.append(puff(s.cx + (i % 2 == 1 ? 3 : -3), y, s.unit * (0.35 + Double(i) * 0.03), t * dur, (i % 2 == 1 ? 1 : -1) * s.unit * 0.25, -s.unit * 0.2, 1100))
        }
        sprites.append(rocket)
        // Touchdown: a dust ring, dust both ways.
        sprites.append(shockwave(s, dur - 40, "rgba(226, 232, 240, 0.95)"))
        for i in 0..<8 {
            let dir: Double = i % 2 == 1 ? 1 : -1
            sprites.append(puff(s.cx, s.h - s.unit * 0.1, s.unit * (0.35 + Double(i % 3) * 0.12), dur - 60 + Double(i) * 25, dir * (s.w / 2 + s.unit * (0.3 + Double(i >> 1) * 0.25)), -s.unit * 0.15, 900))
        }
        return EntrancePlan(revealAt: dur + 80, arrive: joltArrival(520, [:]), total: dur + 1100, sprites: sprites)
    }

    // A flat, glowing vortex opens on the ground under the button (rings
    // spinning inside a squashed frame), sparks spiral in, a column of light
    // rises; drawn BEHIND the button, which rises out of it; a flash closes it.
    private static func portal(_ s: EntranceStage) -> EntrancePlan {
        let bw = max(s.w * 1.35, s.unit * 2)
        let bh = bw * 0.32
        let cy = s.h - bh * 0.15
        func size(_ inset: Double) -> Double { bw - inset * 2 }
        func disc(_ inset: Double, _ svg: String, _ spin: Double, _ dur: Double) -> FxSprite {
            FxSprite(x: inset, y: inset, w: bw - inset * 2, h: bw - inset * 2, svg: svg,
                     tracks: spin != 0 ? [play([["rotate": "0deg"], ["rotate": deg(spin * 360)]], duration: dur, iterations: .infinity)] : [])
        }
        // The ring mask (transparent 52%, solid 60-86%, gone at 100%), as a band.
        let ring = (0.56, 0.93)
        let well = FxSprite(
            x: 0, y: 0, w: bw, h: bw,
            tracks: [play([
                ["opacity": 0, "scale": 0],
                ["opacity": 1, "scale": 1.08, "offset": 0.2, "easing": "ease-out"],
                ["opacity": 1, "scale": 1, "offset": 0.3],
                ["opacity": 1, "scale": 1, "offset": 0.76, "easing": "ease-in"],
                ["opacity": 1, "scale": 0.08, "offset": 0.92],
                ["opacity": 0, "scale": 0],
            ], duration: 1650, fill: "forwards")],
            children: [
                disc(-bw * 0.12, FxPaint.radialDisc(size(-bw * 0.12), size(-bw * 0.12), [Stop(s.accent), .at("rgba(168, 85, 247, 0.55)", 45), .at("transparent", 72)]), 0, 0),
                disc(0, FxPaint.conicDisc(size(0), 0, [Stop(s.accent), "#a855f7", "#22d3ee", "#f0abfc", Stop(s.accent)], ring: ring), 1, 1100),
                disc(bw * 0.08, FxPaint.conicDisc(size(bw * 0.08), 90, ["#22d3ee", .at("transparent", 25), .at("#a855f7", 50), .at("transparent", 75), "#22d3ee"], ring: ring), -1, 700),
                disc(bw * 0.16, FxPaint.conicDisc(size(bw * 0.16), 45, ["#ffffff", .at("transparent", 20), .at("#f0abfc", 50), .at("transparent", 70), "#ffffff"], ring: ring), 1, 520),
                disc(bw * 0.22, FxPaint.radialDisc(size(bw * 0.22), size(bw * 0.22), ["#020617", .at("#1e1b4b", 55), .at("#4c1d95", 80), "rgba(76, 29, 149, 0)"]), 0, 0),
                disc(bw * 0.3, FxPaint.conicDisc(size(bw * 0.3), 0, ["rgba(165, 243, 252, 0.7)", .at("transparent", 30), .at("rgba(240, 171, 252, 0.6)", 60), .at("transparent", 85), "rgba(165, 243, 252, 0.7)"]), 1, 900),
            ])
        // Sparks drawn in along a spiral: each on an arm spinning inside the frame.
        let arms = (0..<12).map { i -> FxSprite in
            let d = (4 + Double(i % 3) * 1.5) * (bw / bh) * 0.35
            let c = i % 2 == 1 ? "#f5d0fe" : "#cffafe"
            return FxSprite(
                x: bw / 2, y: bw / 2, w: 0, h: 0, origin: (0, 0),
                tracks: [play([["rotate": deg(Double(i) * 30)], ["rotate": deg(Double(i) * 30 + 420)]], duration: 950, delay: 180 + Double(i) * 35, easing: "ease-in", fill: "forwards")],
                children: [FxSprite(
                    x: bw * 0.62, y: -d / 2, w: d, h: d,
                    svg: FxPaint.radialDisc(d, d, [Stop(c), .at(c, 70), "transparent"]),
                    base: ["o": 0],
                    tracks: [play([
                        ["opacity": 0, "translate": "0 0"],
                        ["opacity": 1, "offset": 0.2],
                        ["opacity": 0, "translate": "-\(px(bw * 0.62)) 0"],
                    ], duration: 950, delay: 180 + Double(i) * 35, easing: "ease-in", fill: "forwards")])])
        }
        let frame = FxSprite(x: s.cx - bw / 2, y: cy - bw / 2, w: bw, h: bw, base: ["sy": bh / bw], children: [well] + arms)
        let colW = min(bw * 0.62, s.w + s.unit * 0.3)
        let colH = s.unit * 2.2
        let col = FxSprite(
            x: s.cx - colW / 2, y: cy - colH, w: colW, h: colH,
            svg: FxPaint.linearBox(colW, colH, 0, ["rgba(240, 171, 252, 0.75)", .at("rgba(165, 243, 252, 0.35)", 50), "rgba(165, 243, 252, 0)"], radius: [colW / 2, colW / 2, 0, 0]),
            origin: (colW / 2, colH),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0, "scale": "0.4 0"],
                ["opacity": 1, "scale": "1 1", "offset": 0.35],
                ["opacity": 0.6, "offset": 0.7],
                ["opacity": 0, "scale": "0.6 1.1"],
            ], duration: 1000, delay: 380, easing: "ease-out", fill: "forwards")])
        let flash = FxSprite(
            x: s.cx - bw / 2, y: cy - bh * 0.3, w: bw, h: bh * 0.6,
            svg: FxPaint.radialDisc(bw, bh * 0.6, ["#ffffff", .at("rgba(165, 243, 252, 0.7)", 40), .at("transparent", 75)]),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0, "scale": "0.3 1"],
                ["opacity": 1, "scale": "1.3 1", "offset": 0.35],
                ["opacity": 0, "scale": "0.05 0.4"],
            ], duration: 420, delay: 1250, easing: "ease-out", fill: "forwards")])
        return EntrancePlan(
            revealAt: 450,
            arrive: play([
                ["opacity": 0, "scale": 0.55, "translate": "0 \(px(s.unit * 0.7))", "filter": "brightness(2.2) drop-shadow(0 0 16px #a5f3fc)", "easing": "cubic-bezier(0.2, 0.8, 0.3, 1.2)"],
                ["opacity": 1, "scale": 1.08, "translate": "0 -\(px(s.unit * 0.18))", "offset": 0.6, "filter": "brightness(1.4) drop-shadow(0 0 10px #c084fc)"],
                ["opacity": 1, "scale": 0.98, "translate": "0 2px", "offset": 0.8],
                ["opacity": 1, "scale": 1, "translate": "0 0", "filter": "brightness(1) drop-shadow(0 0 0 rgba(192, 132, 252, 0))"],
            ], duration: 820),
            total: 1750,
            sprites: [frame, col, flash],
            behind: true)
    }

    // A saucer with chasing rim lights glides in and hovers; its tractor beam
    // lifts sparkles and draws the button down, top to bottom; then it zips off.
    private static func ufo(_ s: EntranceStage) -> EntrancePlan {
        let w = s.unit * 1.6
        let h = s.unit * 0.8
        let k = w / 60
        let lift = s.unit * 1.9
        let saucer = "<defs><radialGradient id=\"d\" cx=\"0.38\" cy=\"0.3\" r=\"0.8\"><stop offset=\"0\" stop-color=\"#ffffff\"/><stop offset=\"0.5\" stop-color=\"#bae6fd\"/><stop offset=\"1\" stop-color=\"#0ea5e9\"/></radialGradient>" +
            "<linearGradient id=\"h\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#f1f5f9\"/><stop offset=\"0.5\" stop-color=\"#94a3b8\"/><stop offset=\"1\" stop-color=\"#334155\"/></linearGradient></defs>" +
            "<ellipse cx=\"30\" cy=\"12\" rx=\"12\" ry=\"10.5\" fill=\"url(#d)\" stroke=\"#334155\" stroke-width=\"1\"/>" +
            "<ellipse cx=\"26\" cy=\"7.5\" rx=\"4\" ry=\"2.4\" fill=\"#fff\" opacity=\"0.85\"/>" +
            "<ellipse cx=\"30\" cy=\"18.5\" rx=\"29\" ry=\"8.5\" fill=\"url(#h)\" stroke=\"#1e293b\" stroke-width=\"1\"/>" +
            "<ellipse cx=\"30\" cy=\"16\" rx=\"24\" ry=\"2.2\" fill=\"\(s.accent)\" opacity=\"0.85\"/>"
        let lxs: [Double] = [8, 19, 30, 41, 52]
        let lights = lxs.indices.map { i -> FxSprite in
            let ly = i == 2 ? 22.5 : (i == 1 || i == 3) ? 21.5 : 19.5
            let r = 2.1 * k
            return FxSprite(
                x: lxs[i] * k - r, y: ly * k - r, w: r * 2, h: r * 2, fill: "#fde047", radius: r,
                tracks: [play([
                    ["opacity": 0.25],
                    ["opacity": 1, "offset": 0.2],
                    ["opacity": 0.25, "offset": 0.4],
                    ["opacity": 0.25],
                ], duration: 500, delay: Double(i) * 100, iterations: .infinity)])
        }
        let from = s.inward == -1 ? s.winW - s.left + w : -(s.left + w * 2)
        let ufo = FxSprite(
            x: s.cx - w / 2, y: -lift, w: w, h: h,
            svg: svgOf(w, h, "0 0 60 30", saucer),
            origin: (w * 0.5, h * 0.62),
            tracks: [play([
                ["translate": "\(px(from)) -70px", "rotate": deg(s.inward * -16), "easing": "cubic-bezier(0.2, 0.8, 0.3, 1)"],
                ["translate": "0 0", "rotate": deg(s.inward * 5), "offset": 0.3],
                ["translate": "0 -4px", "rotate": "0deg", "offset": 0.42],
                ["translate": "0 3px", "rotate": "0deg", "offset": 0.56],
                ["translate": "0 -2px", "rotate": "0deg", "offset": 0.7],
                ["translate": "0 0", "rotate": "0deg", "offset": 0.78, "easing": "cubic-bezier(0.6, 0, 0.9, 0.4)"],
                ["translate": "\(px(s.inward * -40)) -\(px(s.above + lift + 120))", "rotate": deg(s.inward * 20), "scale": "0.6 0.6"],
            ], duration: 2300, fill: "forwards")],
            children: lights)
        let beamTop = -lift + h * 0.8
        let beamH = s.h - beamTop
        let bw = w * 1.05
        var stripes = ""
        var y = 0
        while Double(y) < beamH {
            for o in [6, 15, 24] where Double(y + o) < beamH {
                stripes += "<rect x=\"0\" y=\"\(y + o)\" width=\"\(n(bw))\" height=\"3\" fill=\"rgb(254,249,195)\" fill-opacity=\"0.35\"/>"
            }
            y += 30
        }
        let beam = FxSprite(
            x: s.cx - bw / 2, y: beamTop, w: bw, h: beamH,
            svg: svgOf(bw, beamH, "0 0 \(n(bw)) \(n(beamH))",
                       "<defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"rgb(254,240,138)\" stop-opacity=\"0.9\"/><stop offset=\"1\" stop-color=\"rgb(254,240,138)\" stop-opacity=\"0.15\"/></linearGradient>" +
                        "<clipPath id=\"c\"><polygon points=\"\(n(bw * 0.36)),0 \(n(bw * 0.64)),0 \(n(bw)),\(n(beamH)) 0,\(n(beamH))\"/></clipPath></defs>" +
                        "<g clip-path=\"url(#c)\"><rect width=\"\(n(bw))\" height=\"\(n(beamH))\" fill=\"url(#g)\"/>\(stripes)</g>"),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0],
                ["opacity": 0.95, "offset": 0.15],
                ["opacity": 0.95, "offset": 0.8],
                ["opacity": 0],
            ], duration: 1000, delay: 760, fill: "forwards")])
        let dots = (0..<8).map { i in
            FxSprite(
                x: s.cx + (Double(i) - 3.5) * (s.unit * 0.13), y: s.h - 6, w: 4, h: 4, fill: "#fef9c3", radius: 2,
                base: ["o": 0],
                tracks: [play([
                    ["opacity": 0, "translate": "0 0"],
                    ["opacity": 1, "offset": 0.2],
                    ["opacity": 0, "translate": "0 -\(px(beamH * 0.8))"],
                ], duration: 800, delay: 820 + Double(i) * 60, easing: "ease-in", fill: "forwards")])
        }
        return EntrancePlan(
            revealAt: 900,
            arrive: play([
                ["opacity": 0.2, "scale": 0.9, "translate": "0 -\(px(s.unit * 0.35))", "clipPath": "inset(0 0 100% 0)", "filter": "brightness(1.8)"],
                ["opacity": 0.6, "offset": 0.25],
                ["opacity": 0.35, "offset": 0.35],
                ["opacity": 1, "scale": 1, "translate": "0 0", "clipPath": "inset(0 0 0% 0)", "filter": "brightness(1)", "offset": 0.8],
                ["opacity": 1, "scale": 1, "translate": "0 0", "clipPath": "inset(0 0 0% 0)", "filter": "brightness(1)"],
            ], duration: 700, easing: "ease-out"),
            total: 2350,
            sprites: [beam] + dots + [ufo])
    }

    // It falls from the sky with speed lines, stretched by the speed; hits the
    // ground in a squash with a shockwave, pebbles and a ring of cartoon stars;
    // bounces twice and settles.
    private static func drop(_ s: EntranceStage) -> EntrancePlan {
        let fall = s.above + s.h + 20
        var sprites: [FxSprite] = []
        for i in 0..<3 {
            let lh = s.unit * 0.9
            sprites.append(FxSprite(
                x: s.cx + Double(i - 1) * s.unit * 0.3, y: -s.unit * 1.1, w: 2, h: lh,
                svg: FxPaint.linearBox(2, lh, 180, ["rgba(148, 163, 184, 0)", "rgba(100, 116, 139, 0.8)"], radius: 1),
                base: ["o": 0],
                tracks: [play([
                    ["opacity": 0, "translate": "0 -\(px(fall * 0.6))"],
                    ["opacity": 0.9, "translate": "0 0", "offset": 0.85],
                    ["opacity": 0, "translate": "0 \(px(s.unit * 0.4))"],
                ], duration: 480, delay: 20 + Double(i) * 30, easing: "cubic-bezier(0.55, 0, 1, 0.45)", fill: "forwards")]))
        }
        let hit = 470.0
        sprites.append(shockwave(s, hit, "rgba(148, 163, 184, 0.9)", 2.4))
        sprites.append(contentsOf: debris(s, 6, hit, ["#94a3b8", "#64748b", "#cbd5e1"], 5, 0.9))
        sprites.append(puff(s.cx - s.w * 0.3, s.h - 4, s.unit * 0.5, hit, -s.unit * 0.6, -4, 700))
        sprites.append(puff(s.cx + s.w * 0.3, s.h - 4, s.unit * 0.5, hit, s.unit * 0.6, -4, 700))
        // Cartoon stars circling where it hit, for a moment.
        let star5 = "M6 0 L7.5 4.2 L12 4.6 L8.5 7.4 L9.7 12 L6 9.4 L2.3 12 L3.5 7.4 L0 4.6 L4.5 4.2 Z"
        for i in 0..<3 {
            sprites.append(FxSprite(
                x: s.cx, y: -s.unit * 0.15, w: 0, h: 0, origin: (0, 0),
                base: ["sy": 0.35],
                tracks: [play([["rotate": deg(Double(i) * 120)], ["rotate": deg(Double(i) * 120 + 520)]], duration: 1100, delay: hit + 60, fill: "forwards")],
                children: [FxSprite(
                    x: s.unit * 0.55, y: -6, w: 12, h: 12,
                    svg: svgOf(12, 12, "0 0 12 12", "<path d=\"\(star5)\" fill=\"#fde047\" stroke=\"#b45309\" stroke-width=\"0.8\"/>"),
                    base: ["o": 0],
                    tracks: [play([
                        ["opacity": 0],
                        ["opacity": 1, "offset": 0.15],
                        ["opacity": 1, "offset": 0.75],
                        ["opacity": 0],
                    ], duration: 1100, delay: hit + 60, fill: "forwards")])]))
        }
        return EntrancePlan(
            revealAt: 0,
            arrive: play([
                ["opacity": 1, "translate": "0 -\(px(fall))", "scale": "0.86 1.18", "easing": "cubic-bezier(0.55, 0, 1, 0.45)"],
                ["translate": "0 0", "scale": "0.9 1.12", "offset": 0.43, "easing": "ease-out"],
                ["translate": "0 \(px(s.unit * 0.1))", "scale": "1.28 0.72", "offset": 0.5, "easing": "ease-out"],
                ["translate": "0 -\(px(s.unit * 0.45))", "scale": "0.93 1.08", "offset": 0.65, "easing": "ease-in"],
                ["translate": "0 0", "scale": "1.12 0.88", "offset": 0.78, "easing": "ease-out"],
                ["translate": "0 -\(px(s.unit * 0.12))", "scale": "0.98 1.02", "offset": 0.87, "easing": "ease-in"],
                ["translate": "0 0", "scale": "1.03 0.97", "offset": 0.94],
                ["opacity": 1, "translate": "0 0", "scale": "1 1"],
            ], duration: 1100),
            total: 1700,
            sprites: sprites)
    }

    // A confetti cannon: 40 pieces blasted up and out, each tumbling as it
    // flutters down, drifting.
    private static func confetti(_ s: EntranceStage) -> EntrancePlan {
        let count = 40
        let fd = s.unit * 2.4
        var sprites = [FxSprite(
            x: s.cx - s.unit * 1.2, y: s.cy - s.unit * 1.2, w: fd, h: fd,
            svg: FxPaint.radialDisc(fd, fd, ["rgba(255, 255, 255, 0.95)", .at("rgba(253, 224, 71, 0.4)", 45), .at("transparent", 70)]),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0, "scale": 0.3],
                ["opacity": 1, "scale": 1, "offset": 0.3],
                ["opacity": 0, "scale": 1.4],
            ], duration: 420, delay: 60, fill: "forwards")])]
        for i in 0..<count {
            let kind = i % 4
            let wpx: Double = kind == 1 ? 7 : kind == 2 ? 4 : 7
            let hpx: Double = kind == 1 ? 7 : kind == 2 ? 16 : 10
            // A fan leaning into the screen (so the burst is never cut off).
            let a = (-170 + (160 * Double(i)) / Double(count - 1)) * (Double.pi / 180)
            let v = s.unit * (1.2 + Double((i * 7) % 9) * 0.18) + s.w * 0.2
            let dx = cos(a) * v * (s.inward == -1 ? -1 : 1) * -1
            let dy = sin(a) * v
            let drift = Double((i % 3) - 1) * s.unit * 0.4
            let dur = 1500 + Double(i % 5) * 140
            sprites.append(FxSprite(
                x: s.cx - wpx / 2, y: s.cy - hpx / 2, w: wpx, h: hpx,
                fill: i % 5 == 0 ? s.accent : colors[i % colors.count],
                radius: kind == 1 ? wpx / 2 : 2,
                base: ["o": 0],
                tracks: [
                    play([
                        ["opacity": 1, "translate": "0 0", "rotate": "0deg", "easing": "cubic-bezier(0.1, 0.8, 0.3, 1)"],
                        ["opacity": 1, "translate": tr(dx, dy), "rotate": deg(Double(160 + i * 23)), "offset": 0.3, "easing": "cubic-bezier(0.4, 0, 0.8, 0.6)"],
                        ["opacity": 1, "translate": tr(dx + drift, dy + s.unit * 1.1), "rotate": deg(Double(320 + i * 31)), "offset": 0.75],
                        ["opacity": 0, "translate": tr(dx - drift, dy + s.unit * 1.8), "rotate": deg(Double(420 + i * 37))],
                    ], duration: dur, delay: 60 + Double(i % 6) * 12, fill: "forwards"),
                    // The 3D tumble: the piece flips edge-on and back as it spins.
                    play([["scale": "1 1"], ["scale": "1 0.1"], ["scale": "1 1"]], duration: 260 + Double(i % 4) * 70, iterations: (dur / 300).rounded(.up)),
                ]))
        }
        return EntrancePlan(
            revealAt: 0,
            arrive: play([
                ["opacity": 0, "scale": 0, "rotate": "-14deg"],
                ["opacity": 1, "scale": 1.22, "rotate": "6deg", "offset": 0.5],
                ["scale": 0.94, "rotate": "-3deg", "offset": 0.72],
                ["scale": 1.03, "rotate": "1deg", "offset": 0.86],
                ["opacity": 1, "scale": 1, "rotate": "0deg"],
            ], duration: 700, easing: "ease-out"),
            total: 2200,
            sprites: sprites)
    }

    // Jackpot: it rises spinning like a gold coin, a shower of coins bursts
    // out and falls, it lands with a bounce and a glint sweeps across it.
    private static func coin(_ s: EntranceStage) -> EntrancePlan {
        var sprites: [FxSprite] = []
        for i in 0..<12 {
            let d = s.unit * (0.28 + Double(i % 3) * 0.06)
            let dir: Double = i % 2 == 1 ? 1 : -1
            let dx = dir * (s.w / 2 + s.unit * (0.2 + Double(i % 4) * 0.28))
            let up = s.unit * (0.9 + Double((i * 5) % 4) * 0.3)
            sprites.append(FxSprite(
                x: s.cx - d / 2, y: s.cy - d / 2, w: d, h: d,
                svg: svgOf(d, d, "0 0 20 20",
                           "<defs><radialGradient id=\"c\" cx=\"0.35\" cy=\"0.3\" r=\"0.8\"><stop offset=\"0\" stop-color=\"#fef9c3\"/><stop offset=\"0.45\" stop-color=\"#facc15\"/><stop offset=\"1\" stop-color=\"#a16207\"/></radialGradient></defs><circle cx=\"10\" cy=\"10\" r=\"9\" fill=\"url(#c)\" stroke=\"#854d0e\" stroke-width=\"1\"/><circle cx=\"10\" cy=\"10\" r=\"5.5\" fill=\"none\" stroke=\"#fef08a\" stroke-width=\"1\" opacity=\"0.8\"/>"),
                base: ["o": 0],
                tracks: [
                    play([
                        ["opacity": 1, "translate": "0 0", "easing": "cubic-bezier(0.2, 0.7, 0.4, 1)"],
                        ["opacity": 1, "translate": "\(px(dx * 0.6)) -\(px(up))", "offset": 0.4, "easing": "cubic-bezier(0.5, 0, 0.9, 0.5)"],
                        ["opacity": 0, "translate": tr(dx, s.unit * 0.6)],
                    ], duration: 1100, delay: 560 + Double(i) * 25, fill: "forwards"),
                    play([["scale": "1 1"], ["scale": "0.1 1"], ["scale": "1 1"]], duration: 240, delay: 560 + Double(i) * 25, iterations: 5),
                ]))
        }
        sprites.append(contentsOf: sparkles(s, 6, 900, "#fde047", 1.2))
        // The glint: a band that sweeps across the button (left -40% -> 115%).
        let bandW = s.w * 0.35
        sprites.append(FxSprite(
            x: 0, y: 0, w: s.w, h: s.h, clip: s.h / 2,
            children: [FxSprite(
                x: 0, y: -s.h * 0.2, w: bandW, h: s.h * 1.4,
                svg: FxPaint.linearBox(bandW, s.h * 1.4, 100, ["transparent", "rgba(255,255,255,0.75)", "transparent"]),
                tracks: [play([["left": "-40%"], ["left": "115%"]], duration: 520, delay: 1050, easing: "ease-in-out", fill: "forwards")],
                leftOf: s.w)]))
        return EntrancePlan(
            revealAt: 0,
            arrive: play([
                ["opacity": 0, "scale": 0.3, "rotate": "y 0deg", "translate": "0 \(px(s.unit * 0.8))", "filter": "brightness(1)"],
                ["opacity": 1, "rotate": "y 180deg", "filter": "brightness(1.6) sepia(0.4)", "offset": 0.15],
                ["rotate": "y 360deg", "filter": "brightness(0.8)", "offset": 0.3],
                ["rotate": "y 540deg", "translate": "0 -\(px(s.unit * 0.5))", "filter": "brightness(1.6) sepia(0.4)", "offset": 0.45, "scale": 1.1],
                ["rotate": "y 720deg", "filter": "brightness(0.85)", "offset": 0.6],
                ["rotate": "y 1080deg", "translate": "0 0", "scale": 1.06, "filter": "brightness(1.2)", "offset": 0.8, "easing": "ease-out"],
                ["translate": "0 -\(px(s.unit * 0.1))", "scale": 0.98, "offset": 0.9],
                ["opacity": 1, "rotate": "y 1080deg", "translate": "0 0", "scale": 1, "filter": "brightness(1)"],
            ], duration: 1200),
            total: 1900,
            sprites: sprites)
    }

    // A fireball streaks in from the top corner of the screen with a burning
    // tail, strikes with a flash and a shockwave, throws rocks and smoke.
    private static func meteor(_ s: EntranceStage) -> EntrancePlan {
        let dur = 560.0
        let sx = s.inward * min(s.winW * 0.35, 380)
        let sy = -(s.above + s.unit)
        let ang = (atan2(-sy, -sx) * 180) / Double.pi
        let len = (sx * sx + sy * sy).squareRoot()
        let bd = s.unit * 0.56
        let tw = min(len * 0.45, 260)
        let th = s.unit * 0.4
        var sprites = [FxSprite(
            x: s.cx, y: s.cy, w: 0, h: 0, origin: (0, 0),
            base: ["r": ang],
            tracks: [play([
                ["translate": tr(sx, sy), "opacity": 1],
                ["translate": "0 0", "opacity": 1, "offset": 0.97],
                ["translate": "0 0", "opacity": 0],
            ], duration: dur, easing: "cubic-bezier(0.5, 0, 0.9, 0.6)", fill: "forwards")],
            children: [
                FxSprite(x: -s.unit * 0.1 - tw, y: -s.unit * 0.2, w: tw, h: th,
                         svg: FxPaint.linearBox(tw, th, 270, ["rgba(253, 224, 71, 0.95)", .at("rgba(249, 115, 22, 0.6)", 30), "rgba(127, 29, 29, 0)"], radius: th / 2)),
                FxSprite(x: -bd / 2, y: -bd / 2, w: bd, h: bd, svg: FxPaint.radialDisc(bd, bd, ["#fffbeb", .at("#fde047", 30), .at("#f97316", 60), "#7c2d12"])),
            ])]
        let bu = s.unit * 3.4
        sprites.append(FxSprite(
            x: s.cx - bu / 2, y: s.cy - bu / 2, w: bu, h: bu,
            svg: FxPaint.radialDisc(bu, bu, ["#ffffff", .at("rgba(253, 224, 71, 0.95)", 25), .at("rgba(249, 115, 22, 0.6)", 50), .at("transparent", 72)]),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0, "scale": 0.2],
                ["opacity": 1, "scale": 1, "offset": 0.25],
                ["opacity": 0, "scale": 1.5],
            ], duration: 620, delay: dur - 20, easing: "ease-out", fill: "forwards")]))
        sprites.append(shockwave(s, dur, "rgba(253, 186, 116, 0.95)", 3))
        sprites.append(contentsOf: debris(s, 9, dur, ["#44403c", "#78716c", "#292524", "#f97316"], 6, 1.3))
        for i in 0..<5 {
            sprites.append(puff(s.cx + Double(i - 2) * s.unit * 0.25, s.cy, s.unit * (0.55 + Double(i % 2) * 0.2), dur + 120 + Double(i) * 60, Double(i - 2) * s.unit * 0.15, -s.unit * 1.1, 1300, "rgba(120, 113, 108, 0.75)"))
        }
        return EntrancePlan(
            revealAt: dur,
            arrive: joltArrival(1500, ["filter": "brightness(1.7) sepia(1) saturate(4) hue-rotate(-20deg) drop-shadow(0 0 14px #f97316)"]),
            total: dur + 1600,
            sprites: sprites)
    }

    // A top hat appears where the button will be, a wand taps it twice in a
    // flurry of sparkles, and the button springs out; the hat drops away.
    private static func magic(_ s: EntranceStage) -> EntrancePlan {
        let hw = s.unit * 1.2
        let hh = s.unit * 1.0
        let hatTop = s.h - hh * 0.72
        var sprites = [FxSprite(
            x: s.cx - hw / 2, y: hatTop, w: hw, h: hh,
            svg: svgOf(hw, hh, "0 0 60 50",
                       "<defs><linearGradient id=\"h\" x1=\"0\" x2=\"1\"><stop offset=\"0\" stop-color=\"#0f172a\"/><stop offset=\"0.35\" stop-color=\"#475569\"/><stop offset=\"0.6\" stop-color=\"#1e293b\"/><stop offset=\"1\" stop-color=\"#020617\"/></linearGradient></defs>" +
                        "<ellipse cx=\"30\" cy=\"44\" rx=\"29\" ry=\"6\" fill=\"#0f172a\"/><path d=\"M12 44 L14 6 Q30 1 46 6 L48 44 Z\" fill=\"url(#h)\"/><rect x=\"13\" y=\"30\" width=\"34\" height=\"7\" fill=\"\(s.accent)\"/>" +
                        "<ellipse cx=\"30\" cy=\"6\" rx=\"16\" ry=\"4\" fill=\"#334155\"/><path d=\"M19 10 L18 28\" stroke=\"#fff\" stroke-width=\"2\" opacity=\"0.25\" stroke-linecap=\"round\"/>"),
            tracks: [play([
                ["opacity": 0, "scale": 0.3, "rotate": "-10deg"],
                ["opacity": 1, "scale": 1.1, "rotate": "4deg", "offset": 0.12, "easing": "ease-out"],
                ["opacity": 1, "scale": 1, "rotate": "0deg", "offset": 0.2],
                ["opacity": 1, "scale": 1, "rotate": "0deg", "offset": 0.62],
                ["opacity": 1, "translate": "0 \(px(s.unit * 0.3))", "scale": "1.15 0.85", "offset": 0.68],
                ["opacity": 0, "translate": "0 \(px(s.unit * 0.9))", "scale": 0.6],
            ], duration: 2000, fill: "forwards")])]
        let ww = s.unit * 0.9
        let tilt: Double = s.inward == -1 ? 1 : -1
        sprites.append(FxSprite(
            x: s.inward == -1 ? s.cx - hw / 2 - ww * 0.8 : s.cx + hw / 2 - ww * 0.2,
            y: hatTop - ww * 0.2, w: ww, h: ww * 0.2,
            svg: svgOf(ww, ww * 0.2, "0 0 50 10",
                       "<rect x=\"0\" y=\"3\" width=\"42\" height=\"4\" rx=\"2\" fill=\"#111827\"/><rect x=\"38\" y=\"2.4\" width=\"12\" height=\"5.2\" rx=\"2.4\" fill=\"#f8fafc\"/><rect x=\"0\" y=\"3\" width=\"8\" height=\"4\" rx=\"2\" fill=\"#f8fafc\"/>"),
            base: s.inward == 1 ? ["o": 0, "sx": -1] : ["o": 0],
            tracks: [play([
                ["opacity": 0, "rotate": deg(tilt * -30), "translate": "\(px(-s.inward * 0)) 0"],
                ["opacity": 1, "rotate": deg(tilt * -20), "offset": 0.12],
                ["rotate": deg(tilt * 10), "offset": 0.24],
                ["rotate": deg(tilt * -20), "offset": 0.34],
                ["rotate": deg(tilt * 10), "offset": 0.44],
                ["opacity": 1, "rotate": deg(tilt * -15), "offset": 0.56],
                ["opacity": 0, "rotate": deg(tilt * -30)],
            ], duration: 1400, delay: 150, fill: "forwards")]))
        sprites.append(contentsOf: sparkles(s, 5, 480, "#fde047", 0.8))
        sprites.append(contentsOf: sparkles(s, 5, 800, "#f0abfc", 1.1))
        sprites.append(puff(s.cx, s.h - s.unit * 0.1, s.unit * 1.1, 1350, 0, -s.unit * 0.3, 900, "rgba(226, 232, 240, 0.95)"))
        return EntrancePlan(
            revealAt: 1150,
            arrive: play([
                ["opacity": 0, "translate": "0 \(px(s.unit * 0.55))", "scale": 0.5, "easing": "cubic-bezier(0.2, 0.8, 0.3, 1)"],
                ["opacity": 1, "translate": "0 -\(px(s.unit * 0.9))", "scale": 1.08, "rotate": deg(s.inward * 8), "offset": 0.45, "easing": "cubic-bezier(0.55, 0, 1, 0.45)"],
                ["translate": "0 0", "scale": "1.12 0.88", "rotate": "0deg", "offset": 0.75, "easing": "ease-out"],
                ["translate": "0 -4px", "scale": "0.98 1.02", "offset": 0.88],
                ["opacity": 1, "translate": "0 0", "scale": 1, "rotate": "0deg"],
            ], duration: 900),
            total: 2300,
            sprites: sprites)
    }

    // It drifts down under a striped parachute, swaying; touches down softly,
    // and the canopy collapses and floats away.
    private static func parachute(_ s: EntranceStage) -> EntrancePlan {
        let a = s.accent
        let cw = max(s.unit * 1.7, s.w * 0.9)
        let ch = s.unit * 1.25
        let fall = s.above + ch + s.h
        let dur = 1900.0
        let mid = s.left + s.cx
        let shift = min(0, s.winW - 6 - (mid + cw / 2)) + max(0, 6 - (mid - cw / 2))
        let sway: [Keyframe] = [
            ["translate": "0 -\(px(fall))", "rotate": "0deg"],
            ["translate": "\(px(s.unit * 0.35)) -\(px(fall * 0.72))", "rotate": "-9deg", "offset": 0.22],
            ["translate": "-\(px(s.unit * 0.35)) -\(px(fall * 0.45))", "rotate": "8deg", "offset": 0.45],
            ["translate": "\(px(s.unit * 0.2)) -\(px(fall * 0.2))", "rotate": "-5deg", "offset": 0.68],
            ["translate": "-\(px(s.unit * 0.05)) -\(px(s.unit * 0.12))", "rotate": "2deg", "offset": 0.88],
            ["translate": "0 0", "rotate": "0deg"],
        ]
        let canopy = "<defs><linearGradient id=\"s\" x1=\"0\" x2=\"1\">" +
            "<stop offset=\"0\" stop-color=\"\(a)\"/><stop offset=\"0.2\" stop-color=\"\(a)\"/><stop offset=\"0.2\" stop-color=\"#ffffff\"/><stop offset=\"0.4\" stop-color=\"#ffffff\"/>" +
            "<stop offset=\"0.4\" stop-color=\"\(a)\"/><stop offset=\"0.6\" stop-color=\"\(a)\"/><stop offset=\"0.6\" stop-color=\"#ffffff\"/><stop offset=\"0.8\" stop-color=\"#ffffff\"/>" +
            "<stop offset=\"0.8\" stop-color=\"\(a)\"/><stop offset=\"1\" stop-color=\"\(a)\"/></linearGradient>" +
            "<radialGradient id=\"l\" cx=\"0.4\" cy=\"0.2\" r=\"0.9\"><stop offset=\"0\" stop-color=\"#fff\" stop-opacity=\"0.45\"/><stop offset=\"1\" stop-color=\"#000\" stop-opacity=\"0.18\"/></radialGradient></defs>" +
            "<path d=\"M2 26 Q40 -12 78 26 Q70 22 60 26 Q50 21 40 26 Q30 21 20 26 Q10 22 2 26 Z\" fill=\"url(#s)\" stroke=\"rgba(15,23,42,0.35)\" stroke-width=\"1\"/>" +
            "<path d=\"M2 26 Q40 -12 78 26 Q70 22 60 26 Q50 21 40 26 Q30 21 20 26 Q10 22 2 26 Z\" fill=\"url(#l)\"/>" +
            "<path d=\"M4 26 L30 60 M20 26 L35 60 M40 26 L40 60 M60 26 L45 60 M76 26 L50 60\" stroke=\"rgba(71,85,105,0.8)\" stroke-width=\"0.8\"/>"
        let chute = FxSprite(
            x: s.cx - cw / 2 + shift, y: s.cy - ch - s.h * 0.35, w: cw, h: ch,
            origin: (cw / 2 - shift, ch + s.h * 0.35),
            tracks: [play(sway, duration: dur, easing: "cubic-bezier(0.3, 0.2, 0.4, 1)", fill: "forwards")],
            children: [FxSprite(
                x: 0, y: 0, w: cw, h: ch,
                svg: "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(cw))\" height=\"\(n(ch))\" viewBox=\"0 0 80 60\" preserveAspectRatio=\"none\">\(canopy)</svg>",
                origin: (cw / 2, ch),
                tracks: [play([
                    ["scale": "1 1", "opacity": 1, "translate": "0 0"],
                    ["scale": "0.8 0.35", "opacity": 1, "translate": tr(s.inward * s.unit * 0.4, ch * 0.45), "offset": 0.45],
                    ["scale": "0.4 0.2", "opacity": 0, "translate": tr(s.inward * s.unit * 1.2, ch * 0.6)],
                ], duration: 800, delay: dur + 80, fill: "forwards")])])
        let sprites = [
            chute,
            puff(s.cx - s.w * 0.3, s.h - 3, s.unit * 0.4, dur - 40, -s.unit * 0.4, -3, 600),
            puff(s.cx + s.w * 0.3, s.h - 3, s.unit * 0.4, dur - 40, s.unit * 0.4, -3, 600),
        ]
        return EntrancePlan(
            revealAt: 0,
            arrive: play(sway.enumerated().map { i, k0 in
                var k = k0
                k["opacity"] = 1
                if let o = i == 0 ? 0 : Keyframes.number(k0["offset"]) {
                    k["offset"] = o * (dur / (dur + 260))
                } else {
                    k.removeValue(forKey: "offset")
                }
                return k
            }, duration: dur + 260, easing: "cubic-bezier(0.3, 0.2, 0.4, 1)"),
            total: dur + 950,
            sprites: sprites)
    }

    // A paper plane loops the loop across the screen and glides in; at the
    // corner it unfolds into the button.
    private static func plane(_ s: EntranceStage) -> EntrancePlan {
        let pw = s.unit * 0.95
        let ph = pw * 0.55
        let l = min(s.winW * 0.55, 520) * s.inward
        let top = -min(s.top * 0.6, 260)
        let r = s.unit * 1.1
        let d = "M \(n(l * 1.1)),\(n(top)) C \(n(l * 0.6)),\(n(top + 40)) \(n(l * 0.35)),\(n(top - 30)) \(n(l * 0.25)),\(n(top + 20)) " +
            "a \(n(r)),\(n(r)) 0 1,\(s.inward == -1 ? 1 : 0) \(n(s.inward * 0.01)),0 " +
            "C \(n(l * 0.12)),\(n(top + 60)) \(n(s.inward * s.unit * 0.8)),\(n(s.cy - 30)) \(n(s.cx - s.w / 2 + s.w / 2)),\(n(s.cy))"
        let dur = 1700.0
        let ease = "cubic-bezier(0.35, 0.1, 0.4, 1)"
        var sprites = [FxSprite(
            x: -pw / 2, y: -ph / 2, w: pw, h: ph,
            svg: svgOf(pw, ph, "0 0 40 22",
                       "<defs><linearGradient id=\"p\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#ffffff\"/><stop offset=\"1\" stop-color=\"#cbd5e1\"/></linearGradient></defs>" +
                        "<path d=\"M40 11 L0 0 L10 11 Z\" fill=\"url(#p)\" stroke=\"#94a3b8\" stroke-width=\"0.8\" stroke-linejoin=\"round\"/><path d=\"M40 11 L10 11 L0 22 Z\" fill=\"#e2e8f0\" stroke=\"#94a3b8\" stroke-width=\"0.8\" stroke-linejoin=\"round\"/>" +
                        "<path d=\"M40 11 L10 11 L14 15 Z\" fill=\"#94a3b8\"/><path d=\"M40 11 L10 11\" stroke=\"\(s.accent)\" stroke-width=\"1.2\"/>"),
            tracks: [play([
                ["offsetDistance": "0%", "opacity": 1],
                ["offsetDistance": "100%", "opacity": 1, "offset": 0.96],
                ["offsetDistance": "100%", "opacity": 0],
            ], duration: dur, easing: ease, fill: "forwards")],
            path: d)]
        for i in 0..<6 {
            sprites.append(FxSprite(
                x: -2, y: -2, w: 4, h: 4, fill: "rgba(148, 163, 184, 0.7)", radius: 2,
                base: ["o": 0],
                tracks: [play([
                    ["offsetDistance": "0%", "opacity": 0],
                    ["offsetDistance": "80%", "opacity": 0.6, "offset": 0.7],
                    ["offsetDistance": "96%", "opacity": 0],
                ], duration: dur, delay: 80 + Double(i) * 70, easing: ease, fill: "forwards")],
                path: d))
        }
        sprites.append(FxSprite(
            x: 0, y: 0, w: s.w, h: s.h,
            svg: FxPaint.linearBox(s.w, s.h, 135, ["#ffffff", "#e2e8f0"], radius: min(s.w, s.h) / 2),
            base: ["o": 0],
            tracks: [play([
                ["opacity": 0, "scale": "0.2 0.2", "rotate": "-40deg"],
                ["opacity": 1, "scale": "1 1", "rotate": "0deg", "offset": 0.55],
                ["opacity": 0, "scale": "1 1", "rotate": "0deg"],
            ], duration: 520, delay: dur - 80, easing: "ease-out", fill: "forwards")]))
        return EntrancePlan(
            revealAt: dur + 150,
            arrive: play([
                ["opacity": 0, "scale": "1 0.1", "rotate": "x 80deg"],
                ["opacity": 1, "scale": "1 1.08", "rotate": "x 0deg", "offset": 0.6],
                ["opacity": 1, "scale": "1 1", "rotate": "x 0deg"],
            ], duration: 480, easing: "cubic-bezier(0.22, 1, 0.36, 1)"),
            total: dur + 700,
            sprites: sprites)
    }

    // An egg lands in the corner, wobbles, cracks, the top pops off; the button
    // hatches with a happy bounce.
    private static func egg(_ s: EntranceStage) -> EntrancePlan {
        let ew = s.unit * 0.95
        let eh = s.unit * 1.2
        let left = s.cx - ew / 2
        let top = s.h - eh
        func shell(_ part: String) -> String {
            svgOf(ew, eh, "0 0 40 50",
                  "<defs><radialGradient id=\"g\" cx=\"0.38\" cy=\"0.3\" r=\"0.85\"><stop offset=\"0\" stop-color=\"#fffdf5\"/><stop offset=\"0.6\" stop-color=\"#fdf2d8\"/><stop offset=\"1\" stop-color=\"#d6b98c\"/></radialGradient>" +
                    "<clipPath id=\"c\"><path d=\"\(part == "top" ? "M-5 -5 H45 V24 L36 20 L29 27 L21 20 L13 27 L6 21 L-5 25 Z" : "M-5 25 L6 21 L13 27 L21 20 L29 27 L36 20 L45 24 V60 H-5 Z")\"/></clipPath></defs>" +
                    "<g clip-path=\"url(#c)\"><path d=\"M20 1 C33 1 39 20 39 31 C39 43 30 49 20 49 C10 49 1 43 1 31 C1 20 7 1 20 1 Z\" fill=\"url(#g)\" stroke=\"#c9a57a\" stroke-width=\"1\"/>" +
                    "<circle cx=\"13\" cy=\"16\" r=\"1.6\" fill=\"#d6b98c\" opacity=\"0.7\"/><circle cx=\"27\" cy=\"12\" r=\"1.2\" fill=\"#d6b98c\" opacity=\"0.7\"/>" +
                    "<circle cx=\"29\" cy=\"36\" r=\"1.6\" fill=\"#d6b98c\" opacity=\"0.6\"/><circle cx=\"11\" cy=\"38\" r=\"1.2\" fill=\"#d6b98c\" opacity=\"0.6\"/>" +
                    "<ellipse cx=\"14\" cy=\"12\" rx=\"4\" ry=\"6\" fill=\"#fff\" opacity=\"0.7\"/></g>")
        }
        let land = play([
            ["translate": "0 -\(px(s.above + eh))", "rotate": "0deg", "scale": "1 1", "easing": "cubic-bezier(0.55, 0, 1, 0.45)"],
            ["translate": "0 0", "scale": "1.12 0.9", "offset": 0.22, "easing": "ease-out"],
            ["translate": "0 0", "scale": "1 1", "rotate": "0deg", "offset": 0.3],
            ["rotate": "-12deg", "offset": 0.38],
            ["rotate": "10deg", "offset": 0.46],
            ["rotate": "-8deg", "offset": 0.54],
            ["rotate": "6deg", "offset": 0.6],
            ["rotate": "0deg", "offset": 0.66],
            ["translate": "0 0", "rotate": "0deg", "scale": "1 1"],
        ], duration: 1600, fill: "forwards")
        let hatch = 1600.0
        let k = ew / 40
        let bottom = FxSprite(
            x: left, y: top, w: ew, h: eh, origin: (ew / 2, eh), tracks: [land],
            children: [FxSprite(x: 0, y: 0, w: ew, h: eh, svg: shell("bottom"), tracks: [play([
                ["opacity": 1, "scale": 1],
                ["opacity": 0, "scale": 0.7, "translate": "0 \(px(s.unit * 0.3))"],
            ], duration: 500, delay: hatch + 250, fill: "forwards")])])
        let topHalf = FxSprite(
            x: left, y: top, w: ew, h: eh, origin: (ew / 2, eh), tracks: [land],
            children: [FxSprite(
                x: 0, y: 0, w: ew, h: eh, svg: shell("top"),
                tracks: [play([
                    ["translate": "0 0", "rotate": "0deg", "opacity": 1],
                    ["translate": "\(px(-s.inward * s.unit * 0.8)) -\(px(s.unit * 1.2))", "rotate": deg(-s.inward * 160), "opacity": 1, "offset": 0.55],
                    ["translate": tr(-s.inward * s.unit * 1.2, s.unit * 0.4), "rotate": deg(-s.inward * 260), "opacity": 0],
                ], duration: 800, delay: hatch, easing: "cubic-bezier(0.2, 0.8, 0.4, 1)", fill: "forwards")],
                children: [
                    // The crack racing across the shell, as a wipe from the left.
                    FxSprite(
                        x: 2 * k, y: 19 * k, w: 37 * k, h: 9 * k,
                        svg: svgOf(37 * k, 9 * k, "2 19 37 9", "<path d=\"M3 24 L6 21 L13 27 L21 20 L29 27 L36 20 L38 22\" fill=\"none\" stroke=\"#7c5a33\" stroke-width=\"1.4\" stroke-linejoin=\"round\"/>"),
                        base: ["dash": 100],
                        tracks: [play([
                            ["strokeDashoffset": 100],
                            ["strokeDashoffset": 100, "offset": 0.4],
                            ["strokeDashoffset": 0],
                        ], duration: 1400, fill: "forwards")],
                        wipe: "right"),
                ])])
        return EntrancePlan(
            revealAt: hatch + 60,
            arrive: play([
                ["opacity": 0, "scale": 0.2, "translate": "0 \(px(s.unit * 0.25))"],
                ["opacity": 1, "scale": 1.25, "translate": "0 -\(px(s.unit * 0.35))", "offset": 0.4, "easing": "ease-in"],
                ["scale": "1.12 0.88", "translate": "0 0", "offset": 0.62, "easing": "ease-out"],
                ["scale": "0.97 1.03", "translate": "0 -3px", "offset": 0.8],
                ["opacity": 1, "scale": 1, "translate": "0 0"],
            ], duration: 820),
            total: hatch + 1000,
            sprites: [bottom, topHalf] +
                debris(s, 6, hatch + 30, ["#fdf2d8", "#f5e6c8", "#e7d3b0"], 5, 0.8) +
                sparkles(s, 5, hatch + 120, "#fde047", 0.9))
    }

    /// The entrance for a mode on this stage (nil for "classic"). `seed` picks the lightning's shape.
    public static func plan(_ mode: String, _ s: EntranceStage, seed: Int? = nil) -> EntrancePlan? {
        let rand = seeded(seed ?? (Int.random(in: 0..<100000) + 7))
        switch mode {
        case "lightning": return lightning(s, rand)
        case "rocket": return rocket(s)
        case "portal": return portal(s)
        case "ufo": return ufo(s)
        case "drop": return drop(s)
        case "confetti": return confetti(s)
        case "coin": return coin(s)
        case "meteor": return meteor(s)
        case "magic": return magic(s)
        case "parachute": return parachute(s)
        case "plane": return plane(s)
        case "egg": return egg(s)
        default: return nil
        }
    }

    private static var pathCache: [String: [FxPaint.P]] = [:]
    private static let pathLock = NSLock()

    /// A sprite's drawn values at t ms (see `SpriteFrame`); `values` when already evaluated.
    public static func spriteFrame(_ sp: FxSprite, _ t: Double, values: FxValues? = nil) -> SpriteFrame {
        let f = values ?? Keyframes.evaluate(sp.tracks, t, base: sp.base)
        var tx = f.tx + (f.txp / 100) * sp.w + (sp.leftOf.map { (f.left / 100) * $0 } ?? 0)
        var ty = f.ty + (f.typ / 100) * sp.h
        var r = f.r
        if let path = sp.path {
            pathLock.lock()
            let pts = pathCache[path] ?? FxPaint.flattenPath(path)
            pathCache[path] = pts
            pathLock.unlock()
            let at = FxPaint.pointAlong(pts, f.od / 100)
            // Chrome measures the path from the box's own top-left and puts its centre on it.
            tx += at.x - sp.w / 2
            ty += at.y - sp.h / 2
            r += at.angle
        }
        return SpriteFrame(tx: tx, ty: ty, r: r,
                           sx: f.sx * cos((f.ry * Double.pi) / 180),
                           sy: f.sy * cos((f.rx * Double.pi) / 180),
                           o: f.o,
                           reveal: sp.wipe != nil ? 1 - f.dash / 100 : 1)
    }
}
