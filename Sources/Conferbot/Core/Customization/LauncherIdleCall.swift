//
//  LauncherIdleCall.swift
//  Conferbot
//
//  Idle call, as the web widget plays it (conferbot-widget
//  src/ts/launcher/idleCall.ts and idlePacing.ts): when the chat has sat
//  unopened a while, the mascot slips out from behind the launcher and
//  calls the visitor over.
//
//    customizations.launcherIdleCall:
//      "off"   (default) nothing;
//      "psst"  it sidles out, cups a hand to its mouth: "Psst!";
//      "peek"  its head rises over the button, looks round, blinks;
//      "wave"  it hops out and waves;
//      "knock" it knocks on the button three times;
//      "tap"   it taps the button twice, which dips.
//    launcherIdleCallDelay: seconds before the call (5-120, default 12);
//    launcherIdleCallText: the speech bubble's line (24 characters; default
//      per style). Tapping the bubble opens the chat.
//
//  The rules (LauncherFxControllers.swift keeps them): one call per screen
//  at most; two per app session, 3 minutes apart; a visitor who opened the
//  chat, or let both calls go by, is left alone for 3 days; closing the
//  greeting means no more calls this session. A call waits (4s, then looks
//  again) while the chat is open, the app is in the background, the
//  keyboard is up, an entrance is landing, or the greeting has been up less
//  than 15s; with the greeting up the mascot only calls (no bubble).
//  Nothing with Reduce Motion.
//
//  Ported from the React Native SDK's core/launcherIdleCall.ts. Pure.
//

import Foundation

public enum LauncherIdleCall {
    public static let modes = ["off", "psst", "peek", "wave", "knock", "tap"]
    public static let defaultDelay = 12
    public static let textMax = 24

    /// A blocked call looks again after this long.
    public static let retryMs = 4000.0

    /// A greeting on screen gets this long alone before the mascot may call.
    public static let greetingFirstMs = 15000.0

    /// The bubble's line per style, in the active language (web i18n idle.*).
    public static var lines: [String: String] {
        Dictionary(uniqueKeysWithValues: ["psst", "peek", "wave", "knock", "tap"].map { ($0, I18n.t("idle.\($0)")) })
    }

    public static func normalize(_ value: Any?) -> String {
        if let s = value as? String, modes.contains(s) { return s }
        return "off"
    }

    public static func normalizeDelay(_ value: Any?) -> Int {
        var n: Double?
        if let s = value as? String {
            let t = s.trimmingCharacters(in: .whitespaces)
            n = t.isEmpty ? nil : Double(t)
        } else {
            n = Keyframes.number(value)
        }
        guard let v = n, v.isFinite else { return defaultDelay }
        // Math.round: halves go up.
        return min(max(Int((v + 0.5).rounded(.down)), 5), 120)
    }

    /// The bubble's line: the owner's, trimmed and capped, else the style's.
    public static func line(_ mode: String, _ text: Any?) -> String {
        if mode == "off" { return "" }
        var own = Keyframes.split((text as? String) ?? "", "\\s+").joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if own.count > textMax { own = String(own.prefix(textMax)) }
        return own.isEmpty ? (lines[mode] ?? "") : own
    }

    // MARK: - Pacing (idlePacing.ts): calling without nagging

    public static let minGapMs = 3.0 * 60 * 1000
    public static let sessionMax = 2
    public static let restMs = 3.0 * 24 * 60 * 60 * 1000

    /// The calls this session: how many played, when the last did (ms since 1970), and "not now" (the greeting was closed).
    public struct VisitState: Equatable {
        public var n = 0
        public var at = 0.0
        public var quiet = false
        public init(n: Int = 0, at: Double = 0, quiet: Bool = false) {
            self.n = n
            self.at = at
            self.quiet = quiet
        }
    }

    /// May a call play now?
    public static func callAllowed(_ visit: VisitState, restUntil: Double, now: Double) -> Bool {
        !visit.quiet && now >= restUntil && visit.n < sessionMax && (visit.at == 0 || now - visit.at >= minGapMs)
    }

    /// A call just played: the new session state, and whether the visitor now rests (the last call).
    public static func afterCall(_ visit: VisitState, now: Double) -> (VisitState, Bool) {
        var v = visit
        v.n += 1
        v.at = now
        return (v, v.n >= sessionMax)
    }

    // MARK: - The performances

    /// The geometry, from the launcher: its short side (unit), which way the
    /// screen is (-1: the launcher is on the right), the x of its edge facing
    /// the screen and its height, in the stage (the launcher's own box); and
    /// whether the greeting card is up.
    public struct Geometry {
        public var unit: Double
        public var inward: Double
        public var edgeX: Double
        public var width: Double
        public var height: Double
        public var card: Bool
    }

    /// The idle call's geometry for a launcher of this size on this side.
    public static func geometry(_ width: Double, _ height: Double, _ position: String, _ card: Bool) -> Geometry {
        let inward: Double = position == "right" ? -1 : 1
        return Geometry(unit: min(width, height), inward: inward, edgeX: inward == -1 ? 0 : width, width: width, height: height, card: card)
    }

    /// Where the mascot sits (box top-left and size), its arm pose (MascotArt), and its base (mirrored when the launcher is on the left).
    public struct Mascot {
        public var x: Double
        public var y: Double
        public var size: Double
        public var arm: String
        public var base: [String: Double]
    }

    public struct Ripple {
        public var x: Double
        public var y: Double
        public var d: Double
        public var track: Track
    }

    public struct Performance {
        public var total: Double
        /// When the speech bubble shows, and where it points (stage px).
        public var bubbleAt: Double
        public var sayX: Double
        public var sayY: Double
        public var mascot: Mascot
        /// The box's own movement, and each part's (in the drawing's 100 x 100 units).
        public var selfTracks: [Track]
        public var parts: [String: [Track]]
        /// The launcher's jolt (knock, tap).
        public var launcher: [Track] = []
        /// White rings where a knock / tap lands (stage px, centre and diameter).
        public var ripples: [Ripple] = []
        /// The bubble's pop and fade (from bubbleAt).
        public var bubble: Track
        /// It speaks (a bubble) only when the greeting is not up.
        public var talks: Bool
        /// Drawn in front of the launcher (its paw lands on the button); else just behind it.
        public var front: Bool
    }

    private static let pop = "cubic-bezier(0.34, 1.56, 0.64, 1)"

    private static func px(_ x: Double, _ y: Double) -> String { "\(Keyframes.jsNum(x))px \(Keyframes.jsNum(y))px" }

    /// Slide out past the facing edge, hold, slide back - fading in from behind.
    private static func slide(_ inward: Double, _ dx: Double, _ dy: Double, _ total: Double, rotate: String = "0deg") -> Track {
        let inAt = 380 / total
        // The animated scale replaces the mirror (base sx -1) a left-hand
        // launcher's mascot is drawn with, so the mirror rides along in it.
        let small: Any = inward == 1 ? "-0.7 0.7" : 0.7
        let full: Any = inward == 1 ? "-1 1" : 1
        return Track.of([
            ["translate": "0 0", "rotate": "0deg", "opacity": 0, "scale": small, "easing": pop],
            ["translate": px(dx, dy), "rotate": rotate, "opacity": 1, "scale": full, "offset": inAt],
            ["translate": px(dx, dy), "rotate": rotate, "opacity": 1, "scale": full, "offset": 1 - inAt, "easing": "ease-in"],
            ["translate": "0 0", "rotate": "0deg", "opacity": 0, "scale": small],
        ], duration: total, easing: "linear", fill: "forwards")
    }

    private static func ripple(_ unit: Double, _ x: Double, _ y: Double, _ delay: Double) -> Ripple {
        Ripple(x: x, y: y, d: unit * 0.55, track: Track.of([
            ["opacity": 0.95, "scale": 0.35],
            ["opacity": 0, "scale": 1.7],
        ], duration: 520, delay: delay, easing: "ease-out", fill: "forwards"))
    }

    /// Blink (the lids are closed for ~70ms each time).
    private static func blink(_ total: Double, _ at: [Double]) -> Track {
        var k: [Keyframe] = [["transform": "scaleY(0)"]]
        for o in at {
            k.append(["transform": "scaleY(0)", "offset": o - 0.02])
            k.append(["transform": "scaleY(1)", "offset": o])
            k.append(["transform": "scaleY(0)", "offset": o + 0.02])
        }
        k.append(["transform": "scaleY(0)"])
        return Track.of(k, duration: total, fill: "forwards")
    }

    /// Where the pupils look: (offset, x, y) in drawing units.
    private static func look(_ total: Double, _ path: [(Double, Double, Double)]) -> Track {
        var k: [Keyframe] = [["translate": "0 0"]]
        for (o, x, y) in path { k.append(["translate": px(x, y), "offset": o, "easing": "ease-in-out"]) }
        k.append(["translate": "0 0"])
        return Track.of(k, duration: total, fill: "forwards")
    }

    /// One mouth ("smile" rests) between two offsets.
    private static func mouth(_ total: Double, _ name: String, _ from: Double, _ to: Double) -> [String: [Track]] {
        [
            name: [Track.of([
                ["opacity": 0],
                ["opacity": 0, "offset": from],
                ["opacity": 1, "offset": from + 0.02],
                ["opacity": 1, "offset": to],
                ["opacity": 0, "offset": to + 0.02],
                ["opacity": 0],
            ], duration: total, fill: "forwards")],
            "smile": [Track.of([
                ["opacity": 1],
                ["opacity": 1, "offset": from],
                ["opacity": 0, "offset": from + 0.02],
                ["opacity": 0, "offset": to],
                ["opacity": 1, "offset": to + 0.02],
                ["opacity": 1],
            ], duration: total, fill: "forwards")],
        ]
    }

    private static func brows(_ total: Double, _ from: Double, _ to: Double) -> Track {
        Track.of([
            ["translate": "0 0"],
            ["translate": "0 0", "offset": from],
            ["translate": "0 -3.5px", "offset": from + 0.05],
            ["translate": "0 -3.5px", "offset": to],
            ["translate": "0 0", "offset": to + 0.05],
            ["translate": "0 0"],
        ], duration: total, fill: "forwards")
    }

    private static func bubbleTrack(_ total: Double, _ at: Double) -> Track {
        Track.of([
            ["opacity": 0, "scale": 0.6, "translate": "0 8px", "easing": pop],
            ["opacity": 1, "scale": 1, "translate": "0 0", "offset": 0.12],
            ["opacity": 1, "scale": 1, "translate": "0 0", "offset": 0.88, "easing": "ease-in"],
            ["opacity": 0, "scale": 0.9, "translate": "0 4px"],
        ], duration: total - at, delay: at, fill: "forwards")
    }

    /// The parts each mascot part starts from: closed-lid rest, the o and grin mouths hidden.
    public static let partBase: [String: [String: Double]] = [
        "lid": ["sy": 0],
        "o": ["o": 0],
        "grin": ["o": 0],
    ]

    private static func merge(_ a: [String: [Track]], _ b: [String: [Track]]) -> [String: [Track]] {
        a.merging(b) { _, new in new }
    }

    /// The performance for a mode in this geometry (PERFORMANCES): the mascot,
    /// a touch bigger than the button, is centred just inside the facing edge
    /// (behind the button) and moves out from there.
    public static func performance(_ mode: String, _ g: Geometry) -> Performance {
        let w = g.unit * 1.2
        func place(_ dy: Double, _ arm: String) -> Mascot {
            Mascot(x: g.edgeX - g.inward * (min(w, g.width) / 2) - w / 2, y: g.height / 2 + dy - w / 2, size: w, arm: arm,
                   base: ["sx": g.inward == 1 ? -1 : 1])
        }
        let front = mode == "tap" || mode == "knock"
        let talks = !g.card
        switch mode {
        case "psst":
            let total = 3600.0
            let dx = g.inward * (w * 0.5)
            return Performance(
                total: total, bubbleAt: 360, sayX: g.edgeX + dx, sayY: g.height / 2 - g.unit * 0.1 - w * 0.42,
                mascot: place(-g.unit * 0.1, "whisper"),
                selfTracks: [slide(g.inward, dx, -g.unit * 0.06, total, rotate: "\(Keyframes.jsNum(g.inward * -6))deg")],
                parts: merge(mouth(total, "o", 0.14, 0.82), [
                    "brow": [brows(total, 0.14, 0.8)],
                    "look": [look(total, [(0.16, 0, 0), (0.32, -2.5, -0.5), (0.44, -2.5, -0.5), (0.52, 1.5, 0), (0.72, 0, 0.5)])],
                    "arm": [Track.of([
                        ["rotate": "0deg"],
                        ["rotate": "0deg", "offset": 0.3],
                        ["rotate": "-8deg", "offset": 0.36],
                        ["rotate": "0deg", "offset": 0.42],
                        ["rotate": "-8deg", "offset": 0.48],
                        ["rotate": "0deg", "offset": 0.54],
                        ["rotate": "0deg"],
                    ], duration: total, fill: "forwards")],
                    "lid": [blink(total, [0.62])],
                ]),
                bubble: bubbleTrack(total, 360), talks: talks, front: front)
        case "peek":
            let total = 3800.0
            let dx = g.card ? g.inward * (w * 0.55) : -g.inward * w * 0.15
            let dy = g.card ? -g.unit * 0.05 : -(g.height * 0.5 + w * 0.08)
            return Performance(
                total: total, bubbleAt: 560, sayX: g.edgeX + dx, sayY: g.height / 2 + dy - w * 0.35,
                mascot: place(g.card ? 0 : g.height * 0.05, "down"),
                selfTracks: [Track.of([
                    ["translate": "0 0", "opacity": 0, "easing": "cubic-bezier(0.34, 1.56, 0.64, 1)"],
                    ["translate": px(dx, dy), "opacity": 1, "offset": 0.12],
                    ["translate": px(dx, dy + 3), "offset": 0.5],
                    ["translate": px(dx, dy), "opacity": 1, "offset": 0.86, "easing": "ease-in"],
                    ["translate": "0 0", "opacity": 0],
                ], duration: total, fill: "forwards")],
                parts: [
                    "look": [look(total, [(0.18, 0, 0), (0.28, -3, 0), (0.4, -3, 0), (0.5, 3, 0), (0.62, 3, 0), (0.7, 0, 1)])],
                    "brow": [brows(total, 0.2, 0.36)],
                    "lid": [blink(total, [0.46, 0.76])],
                ],
                bubble: bubbleTrack(total, 560), talks: talks, front: front)
        case "wave":
            let total = 3500.0
            let dx = g.inward * (w * 0.62 + g.unit * 0.05)
            return Performance(
                total: total, bubbleAt: 320, sayX: g.edgeX + dx, sayY: g.height / 2 - g.unit * 0.1 - w * 0.46,
                mascot: place(-g.unit * 0.08, "wave"),
                selfTracks: [slide(g.inward, dx, -g.unit * 0.1, total)],
                parts: merge(merge([
                    "body": [Track.of([
                        ["scale": "1 1"],
                        ["scale": "1.12 0.88", "offset": 0.06],
                        ["scale": "0.92 1.1", "offset": 0.12],
                        ["scale": "1.04 0.96", "offset": 0.18],
                        ["scale": "1 1", "offset": 0.24],
                        ["scale": "1 1"],
                    ], duration: total, fill: "forwards")],
                ], mouth(total, "grin", 0.12, 0.84)), [
                    "arm": [Track.of([
                        ["rotate": "0deg"],
                        ["rotate": "0deg", "offset": 0.14],
                        ["rotate": "-24deg", "offset": 0.24],
                        ["rotate": "18deg", "offset": 0.36],
                        ["rotate": "-24deg", "offset": 0.48],
                        ["rotate": "18deg", "offset": 0.6],
                        ["rotate": "-10deg", "offset": 0.7],
                        ["rotate": "0deg", "offset": 0.78],
                        ["rotate": "0deg"],
                    ], duration: total, fill: "forwards")],
                    "look": [look(total, [(0.2, 0, 1)])],
                    "lid": [blink(total, [0.66])],
                ]),
                bubble: bubbleTrack(total, 320), talks: talks, front: front)
        case "knock":
            let total = 3500.0
            let dx = g.inward * (w * 0.9)
            let beats = [0.3, 0.41, 0.52]
            var arm: [Keyframe] = [["translate": "0 0", "rotate": "0deg"]]
            var body: [Keyframe] = [["rotate": "0deg"]]
            var lid: [Keyframe] = [["transform": "scaleY(0)"]]
            for o in beats {
                arm.append(["translate": "0 0", "rotate": "0deg", "offset": o - 0.045])
                arm.append(["translate": "4px 0.5px", "rotate": "5deg", "offset": o, "easing": "cubic-bezier(.5,0,.9,.4)"])
                arm.append(["translate": "0 0", "rotate": "0deg", "offset": o + 0.05, "easing": "cubic-bezier(.2,.8,.4,1)"])
                body.append(["rotate": "0deg", "offset": o - 0.045])
                body.append(["rotate": "2.5deg", "offset": o])
                body.append(["rotate": "0deg", "offset": o + 0.05])
                lid.append(["transform": "scaleY(0)", "offset": o - 0.03])
                lid.append(["transform": "scaleY(0.5)", "offset": o])
                lid.append(["transform": "scaleY(0)", "offset": o + 0.04])
            }
            arm.append(["translate": "0 0", "rotate": "0deg"])
            body.append(["rotate": "0deg"])
            lid.append(["transform": "scaleY(0)"])
            return Performance(
                total: total, bubbleAt: 320, sayX: g.edgeX + dx, sayY: g.height / 2 - g.unit * 0.08 - w * 0.42,
                mascot: place(-g.unit * 0.04, "knock"),
                selfTracks: [slide(g.inward, dx, -g.unit * 0.08, total)],
                parts: merge(merge([
                    "arm": [Track.of(arm, duration: total, fill: "forwards")],
                    "body": [Track.of(body, duration: total, fill: "forwards")],
                    "lid": [Track.of(lid, duration: total, fill: "forwards")],
                ], mouth(total, "grin", 0.26, 0.8)), [
                    "look": [look(total, [(0.2, 0, 1)])],
                ]),
                launcher: beats.map { o in
                    Track.of([
                        ["translate": "0 0"],
                        ["translate": "\(Keyframes.jsNum(-g.inward * 2))px 0", "offset": 0.35],
                        ["translate": "0 0"],
                    ], duration: 200, delay: o * total, easing: "ease-out")
                },
                ripples: beats.map { o in ripple(g.unit, g.edgeX - g.inward * g.unit * 0.08, g.height / 2 - g.unit * 0.12, o * total) },
                bubble: bubbleTrack(total, 320), talks: talks, front: front)
        default:
            // tap
            let total = 3300.0
            let dx = g.inward * (w * 0.98)
            let taps = [0.32, 0.46]
            var arm: [Keyframe] = [["translate": "0 0"]]
            for o in taps {
                arm.append(["translate": "0 0", "offset": o - 0.05])
                arm.append(["translate": "5px 1px", "offset": o, "easing": "cubic-bezier(.5,0,.9,.4)"])
                arm.append(["translate": "0 0", "offset": o + 0.06, "easing": "cubic-bezier(.2,.8,.4,1)"])
            }
            arm.append(["translate": "0 0"])
            return Performance(
                total: total, bubbleAt: 320, sayX: g.edgeX + dx, sayY: g.height / 2 - w * 0.42,
                mascot: place(-g.unit * 0.02, "reach"),
                selfTracks: [slide(g.inward, dx, 0, total)],
                parts: merge(merge([
                    "arm": [Track.of(arm, duration: total, fill: "forwards")],
                    "look": [look(total, [(0.16, 3, 1), (0.52, 3, 1), (0.62, 0, 0)])],
                ], mouth(total, "grin", 0.58, 0.84)), [
                    "lid": [blink(total, [0.7])],
                ]),
                launcher: taps.map { o in
                    Track.of([
                        ["scale": 1],
                        ["scale": 0.92, "offset": 0.4],
                        ["scale": 1],
                    ], duration: 240, delay: o * total, easing: "ease-out")
                },
                ripples: taps.map { o in ripple(g.unit, g.edgeX - g.inward * g.unit * 0.18, g.height / 2, o * total) },
                bubble: bubbleTrack(total, 320), talks: talks, front: front)
        }
    }
}
