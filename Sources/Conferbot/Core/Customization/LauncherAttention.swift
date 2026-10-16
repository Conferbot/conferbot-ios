//
//  LauncherAttention.swift
//  Conferbot
//
//  Launcher attention, as the web widget plays it (conferbot-widget
//  src/ts/launcher/attention.ts): an opt-in, continuous "look here" motion
//  on the closed launcher or the greeting card.
//
//    customizations.launcherAttention:
//      "off"    (default) nothing;
//      "pulse"  a soft ring grows out of the launcher every 3s;
//      "wobble" a jelly squash and twist every 5.5s;
//      "bounce" a hop with a contact shadow every 5s;
//      "wave"   the greeting card bobs and a waving hand waves on it, 6s;
//      "float"  the greeting card floats up and down, 4s;
//      "shine"  a gloss sweeps across the button every 5s;
//      "heartbeat" two beats (lub-dub) every 3s;
//      "orbit"  a spark runs two laps round the button every 5.2s.
//
//  The rules (LauncherFxControllers.swift keeps them): the first beat 1.5s
//  after the launcher (or the card) shows; only while the chat is closed;
//  paused while the launcher plays an idle or message moment; over for the
//  app session once the chat is opened (and not started when it was opened
//  in the last 30 minutes); nothing with Reduce Motion. While a
//  launcher-moving mode runs, the launcher's idle moments hold off and the
//  three ripples after load give way (a new message's ripple still plays).
//  Nothing moves while an entrance is landing.
//
//  Ported from the React Native SDK's core/launcherAttention.ts. Pure.
//

import Foundation

public enum LauncherAttention {
    public static let modes = ["off", "pulse", "wobble", "bounce", "wave", "float", "shine", "heartbeat", "orbit"]

    public static func normalize(_ value: Any?) -> String {
        if let s = value as? String, modes.contains(s) { return s }
        return "off"
    }

    /// Which element a mode moves: "launcher", "greeting", or nil.
    public static func target(_ mode: String) -> String? {
        if mode == "off" { return nil }
        return mode == "wave" || mode == "float" ? "greeting" : "launcher"
    }

    /// The first beat waits this long after the launcher (or the card) shows.
    public static let startMs = 1500.0

    /// While an entrance lands, attention looks again this often.
    public static let retryMs = 400.0

    /// The waving hand: the web's sticker, unless the card's own text has one.
    public static let wavingHand = "👋"

    private static func loop(_ part: String, _ kf: [Keyframe], _ duration: Double, delay: Double = startMs) -> Track {
        Track.of(kf, duration: duration, delay: delay, iterations: .infinity, easing: "linear", part: part)
    }

    /// The pulse ring (ATTENTION_CSS cb-attn-ring / cb-attn-ring-wide): a CSS animation, so its timing function eases each step. The second ring is 350ms behind.
    private static let ringEase = "cubic-bezier(0,0,.2,1)"

    private static func ring(_ part: String, _ wide: Bool) -> Track {
        loop(part,
             wide ? [
                ["offset": 0, "scale": "1", "opacity": 0.42, "easing": ringEase],
                ["offset": 0.55, "scale": "1.12 1.6", "opacity": 0, "easing": ringEase],
                ["offset": 1, "scale": "1.12 1.6", "opacity": 0],
             ] : [
                ["offset": 0, "scale": "1", "opacity": 0.85, "easing": ringEase],
                ["offset": 0.6, "scale": "1.85", "opacity": 0, "easing": ringEase],
                ["offset": 1, "scale": "1.85", "opacity": 0],
             ],
             3000,
             delay: part == "ring" ? startMs : startMs + 350)
    }

    /// The movement for a mode, as the web's tracks. Parts: "self" = the target
    /// (launcher or card), "hand" = the card's waving hand, "shadow" = the
    /// bounce's contact shadow, "shine" = the gloss band, "orbit" = the spark,
    /// "ring" / "ring2" = the pulse's two rings. `clipped`: the button clips its
    /// own outline, so the pulse throbs the button instead of a ring. `wide`:
    /// the label pill, whose ring grows less sideways.
    public static func tracks(_ mode: String, clipped: Bool = false, wide: Bool = false) -> [Track] {
        let e = "ease-in-out"
        switch mode {
        case "pulse":
            if clipped {
                return [loop("self", [
                    ["scale": "1", "offset": 0, "easing": e],
                    ["scale": "1.08", "offset": 0.1, "easing": e],
                    ["scale": "1", "offset": 0.2, "easing": e],
                    ["scale": "1.05", "offset": 0.28, "easing": e],
                    ["scale": "1", "offset": 0.36],
                    ["scale": "1", "offset": 1],
                ], 3000)]
            }
            return [ring("ring", wide), ring("ring2", wide)]
        case "wobble":
            return [loop("self", [
                ["scale": "1", "rotate": "0deg", "offset": 0, "easing": e],
                ["scale": "1.14 0.86", "rotate": "-4deg", "offset": 0.04, "easing": e],
                ["scale": "0.88 1.12", "rotate": "4deg", "offset": 0.08, "easing": e],
                ["scale": "1.07 0.94", "rotate": "-2.5deg", "offset": 0.12, "easing": e],
                ["scale": "0.96 1.04", "rotate": "1.5deg", "offset": 0.16, "easing": e],
                ["scale": "1.02 0.98", "rotate": "0deg", "offset": 0.2, "easing": e],
                ["scale": "1", "rotate": "0deg", "offset": 0.24],
                ["scale": "1", "rotate": "0deg", "offset": 1],
            ], 5500)]
        case "bounce":
            return [
                loop("self", [
                    ["translate": "0 0", "scale": "1", "offset": 0],
                    ["translate": "0 0", "scale": "1.12 0.88", "offset": 0.04, "easing": "cubic-bezier(.2,.7,.3,1)"],
                    ["translate": "0 -14px", "scale": "0.92 1.1", "offset": 0.1, "easing": "cubic-bezier(.3,0,.7,1)"],
                    ["translate": "0 -18px", "scale": "1 1", "offset": 0.13, "easing": "cubic-bezier(.6,0,.8,.4)"],
                    ["translate": "0 0", "scale": "1.16 0.84", "offset": 0.19, "easing": "cubic-bezier(.2,.7,.3,1)"],
                    ["translate": "0 -5px", "scale": "0.97 1.03", "offset": 0.24, "easing": "cubic-bezier(.6,0,.8,.4)"],
                    ["translate": "0 0", "scale": "1.04 0.96", "offset": 0.28],
                    ["translate": "0 0", "scale": "1", "offset": 0.31],
                    ["translate": "0 0", "scale": "1", "offset": 1],
                ], 5000),
                loop("shadow", [
                    ["scale": "1", "opacity": 0.35, "offset": 0],
                    ["scale": "1.12 1", "opacity": 0.4, "offset": 0.04],
                    ["scale": "0.55 0.7", "opacity": 0.14, "offset": 0.13],
                    ["scale": "1.2 1", "opacity": 0.42, "offset": 0.19],
                    ["scale": "0.9 0.9", "opacity": 0.3, "offset": 0.24],
                    ["scale": "1", "opacity": 0.35, "offset": 0.31],
                    ["scale": "1", "opacity": 0.35, "offset": 1],
                ], 5000),
            ]
        case "wave":
            return [
                loop("self", [
                    ["translate": "0 0", "offset": 0, "easing": e],
                    ["translate": "0 -6px", "offset": 0.08, "easing": e],
                    ["translate": "0 0", "offset": 0.17, "easing": e],
                    ["translate": "0 -2px", "offset": 0.23, "easing": e],
                    ["translate": "0 0", "offset": 0.3],
                    ["translate": "0 0", "offset": 1],
                ], 6000),
                loop("hand", [
                    ["rotate": "0deg", "offset": 0, "easing": e],
                    ["rotate": "16deg", "offset": 0.05, "easing": e],
                    ["rotate": "-10deg", "offset": 0.1, "easing": e],
                    ["rotate": "16deg", "offset": 0.15, "easing": e],
                    ["rotate": "-6deg", "offset": 0.2, "easing": e],
                    ["rotate": "10deg", "offset": 0.25, "easing": e],
                    ["rotate": "0deg", "offset": 0.3],
                    ["rotate": "0deg", "offset": 1],
                ], 6000),
            ]
        case "float":
            return [loop("self", [
                ["translate": "0 0", "offset": 0, "easing": e],
                ["translate": "0 -5px", "offset": 0.5, "easing": e],
                ["translate": "0 0", "offset": 1],
            ], 4000)]
        case "shine":
            return [
                loop("shine", [
                    ["translate": "-160% 0", "offset": 0],
                    ["translate": "-160% 0", "offset": 0.02, "easing": "cubic-bezier(.4,0,.2,1)"],
                    ["translate": "260% 0", "offset": 0.16],
                    ["translate": "260% 0", "offset": 1],
                ], 5000),
                loop("self", [
                    ["scale": "1", "offset": 0],
                    ["scale": "1.04", "offset": 0.08, "easing": e],
                    ["scale": "1", "offset": 0.18],
                    ["scale": "1", "offset": 1],
                ], 5000),
            ]
        case "heartbeat":
            return [loop("self", [
                ["scale": "1", "offset": 0],
                ["scale": "1.14", "offset": 0.06, "easing": e],
                ["scale": "1", "offset": 0.12, "easing": e],
                ["scale": "1.08", "offset": 0.18, "easing": e],
                ["scale": "1", "offset": 0.28],
                ["scale": "1", "offset": 1],
            ], 3000)]
        case "orbit":
            return [loop("orbit", [
                ["offsetDistance": "0%", "opacity": 0, "offset": 0],
                ["offsetDistance": "8%", "opacity": 1, "offset": 0.05],
                ["offsetDistance": "192%", "opacity": 1, "offset": 0.4, "easing": "cubic-bezier(.4,0,.6,1)"],
                ["offsetDistance": "200%", "opacity": 0, "offset": 0.45],
                ["offsetDistance": "200%", "opacity": 0, "offset": 1],
            ], 5200)]
        default:
            return []
        }
    }

    /// The bits each part starts from (CSS): the shadow at .35, the ring and spark hidden, the gloss parked off the button.
    public static let base: [String: [String: Double]] = [
        "shadow": ["o": 0.35],
        "ring": ["o": 0],
        "ring2": ["o": 0],
        "orbit": ["o": 0],
        "shine": ["txp": -160, "r": 18],
    ]

    /// The orbit's track: a rounded rectangle 7px outside the button (a circle
    /// round a round launcher, a stadium round a pill), clockwise from the top
    /// edge's left end - the web's orbitPath, as a point at a share of its
    /// length (wrapping, so 2 is two laps). Relative to the button's top-left.
    public static func orbitPoint(_ w: Double, _ h: Double, _ fraction: Double, margin: Double = 7) -> CGPoint {
        let x0 = -margin, y0 = -margin
        let bw = w + margin * 2, bh = h + margin * 2
        let r = min(bw, bh) / 2
        let sw = bw - 2 * r, sh = bh - 2 * r
        let arc = (Double.pi * r) / 2
        let total = 2 * sw + 2 * sh + 4 * arc
        // JavaScript's % keeps the sign; ((f % 1) + 1) % 1 is the share into the lap.
        var d = (fraction.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * total
        if fraction > 0 && fraction.truncatingRemainder(dividingBy: 1) == 0 { d = 0 }
        func corner(_ cx: Double, _ cy: Double, _ from: Double, _ len: Double) -> CGPoint {
            let a = from + len / r
            return CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
        }
        // Top edge, top-right corner, right edge, bottom-right, bottom, bottom-left, left, top-left.
        if d <= sw { return CGPoint(x: x0 + r + d, y: y0) }
        d -= sw
        if d <= arc { return corner(x0 + bw - r, y0 + r, -Double.pi / 2, d) }
        d -= arc
        if d <= sh { return CGPoint(x: x0 + bw, y: y0 + r + d) }
        d -= sh
        if d <= arc { return corner(x0 + bw - r, y0 + bh - r, 0, d) }
        d -= arc
        if d <= sw { return CGPoint(x: x0 + bw - r - d, y: y0 + bh) }
        d -= sw
        if d <= arc { return corner(x0 + r, y0 + bh - r, Double.pi / 2, d) }
        d -= arc
        if d <= sh { return CGPoint(x: x0, y: y0 + bh - r - d) }
        d -= sh
        return corner(x0 + r, y0 + r, Double.pi, d)
    }
}
