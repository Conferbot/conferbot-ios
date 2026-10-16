//
//  MascotMoods.swift
//  Conferbot
//
//  The mascot's moods and the typing mascot, as the web plays them: CSS
//  @keyframes on the drawing's parts, kept here as the web wrote them and
//  turned into tracks for the evaluator (Keyframes.cssKeyframes).
//
//  Moods (conferbot-widget src/ts/launcher/art3d.ts MASCOT_ANIM_CSS,
//  mascotState): a class on the drawing.
//    idle   a natural blink now and then (cb-m--blink, always on)
//    wave   the arm waves; a resting arm ("down") lifts first. Repeats, or
//           `waveCount` times (the greeting card: 2) and rests
//    think  a gentle bob with a head tilt, eyes looking around, brows up
//    happy  a happy bounce (twice) and a big smile, kept while the mood is
//  Each part turns about its own joint (MascotArt.origins). Reduced motion
//  turns every movement off; the happy smile, which is not motion, stays.
//
//  Typing ("mascot" typing style, src/css/polish.css .cb-typing--mascot):
//  the bust, 32 x 32, swaying about 50% 90% of its box, blinking and
//  glancing at three thought dots rising beside it. The pencil writes its
//  line. Both still under reduced motion.
//
//  Ported from the React Native SDK's core/mascotMoods.ts. Pure.
//

import Foundation

public enum MascotMoods {
    public static let moods = ["idle", "wave", "think", "happy"]
    /// How long the happy bounce plays (two hops).
    public static let happyMs: Double = 1800
    /// The launcher's mascot keeps its smile this long after a reply (launcherStyle.ts cheerLauncherMascot).
    public static let cheerMs: Double = happyMs + 600

    /// The web's @keyframes bodies (art3d.ts MASCOT_ANIM_CSS, polish.css), verbatim.
    public static let keyframes: [String: String] = [
        "cb-m-blink": "0%,41%,44.4%,86%,88.4%,90.4%,92.8%,100%{transform:scaleY(0)}42.6%,87.2%,91.6%{transform:scaleY(1)}",
        "cb-m-wave": "0%,52%,100%{transform:rotate(0)}60%{transform:rotate(-18deg)}68%{transform:rotate(8deg)}76%{transform:rotate(-16deg)}84%{transform:rotate(6deg)}92%{transform:rotate(-4deg)}",
        "cb-m-wave-up": "0%,100%{transform:rotate(0)}14%{transform:rotate(-118deg)}24%{transform:rotate(-132deg)}34%{transform:rotate(-104deg)}44%{transform:rotate(-132deg)}54%{transform:rotate(-108deg)}62%{transform:rotate(-118deg)}78%{transform:rotate(0)}",
        "cb-m-bob": "0%,100%{transform:translateY(0) rotate(0)}25%{transform:translateY(-1.6px) rotate(-3deg)}50%{transform:translateY(0) rotate(0)}75%{transform:translateY(-1.2px) rotate(2deg)}",
        "cb-m-glance": "0%,8%,92%,100%{transform:translate(0,0)}16%,38%{transform:translate(-2px,-1.6px)}46%,70%{transform:translate(2px,-1.8px)}78%,86%{transform:translate(.6px,.8px)}",
        "cb-m-ponder": "0%,100%{transform:translateY(-1px)}25%{transform:translateY(-2.4px)}",
        "cb-m-hop": "0%,100%{transform:translateY(0) scale(1,1)}18%{transform:translateY(0) scale(1.07,.92)}45%{transform:translateY(-8px) scale(.96,1.05)}70%{transform:translateY(0) scale(1.05,.95)}85%{transform:translateY(0) scale(.99,1.01)}",
        "cb-m-hop-shadow": "0%,18%,70%,100%{transform:scale(1);opacity:1}45%{transform:scale(.78);opacity:.55}",
        "cb-m-cheer": "0%,100%{transform:rotate(0)}45%{transform:rotate(-24deg)}",
        "cb-typing-sway": "0%, 100% { transform: rotate(-4deg) translateY(0.5px); } 50% { transform: rotate(4deg) translateY(-1px); }",
        "cb-typing-glance": "0%, 35%, 100% { transform: translate(0, 0); } 45%, 85% { transform: translate(2.2px, -1.6px); }",
        "cb-typing-blink": "0%, 92%, 100% { transform: scaleY(0); } 95% { transform: scaleY(1); }",
        "cb-typing-dot": "0%, 100% { opacity: 0.25; } 50% { opacity: 1; }",
        "cb-typing-write": "0% { stroke-dashoffset: 60; opacity: 1; } 75% { stroke-dashoffset: 0; opacity: 1; } 90% { stroke-dashoffset: 0; opacity: 1; } 100% { stroke-dashoffset: 0; opacity: 0; }",
        "cb-typing-pencil":
            "0% { transform: translate(2px, 11px); } 9% { transform: translate(6px, 6.5px); } 19% { transform: translate(11px, 10px); } 28% { transform: translate(16px, 13px); } 37% { transform: translate(19px, 9px); } 46% { transform: translate(24px, 5px); } 54% { transform: translate(27px, 10px); } 64% { transform: translate(32px, 12.5px); } 75%, 90% { transform: translate(36px, 8px); } 100% { transform: translate(2px, 11px); }",
    ]

    /// A CSS animation (name duration timing iterations delay) as a track.
    public static func cssTrack(_ name: String, _ duration: Double, _ timing: String, iterations: Double = 1, delay: Double = 0) -> Track {
        Track(Keyframes.cssKeyframes(keyframes[name] ?? "", timing: timing), TrackOptions(duration: duration, delay: delay, iterations: iterations))
    }

    /// A mood's tracks per part (lid, arm, body, look, brow, shadow), its grin, and its clock.
    public struct Plan {
        public var parts: [String: [Track]]
        /// The big smile in place of the usual one (happy; kept under reduced motion).
        public var grin: Bool
        /// When every finite part is over (ms); the blink goes on.
        public var settle: Double
        /// The blink's period: the loop after `settle` repeats it.
        public var period: Double
    }

    static let blinkMs: Double = 6400

    /// A mood's tracks per part (mascotState: blink always, plus the mood's own).
    /// `arm`: the pose as drawn ("down" lifts before it waves); `bust`: no arm;
    /// `waveCount`: how many waves (infinity: on and on).
    public static func plan(_ mood: String, arm: String? = nil, bust: Bool = false, waveCount: Double? = nil, reduced: Bool = false) -> Plan {
        let grin = mood == "happy"
        if reduced { return Plan(parts: [:], grin: grin, settle: 0, period: 0) }
        var parts: [String: [Track]] = ["lid": [cssTrack("cb-m-blink", blinkMs, "linear", iterations: .infinity)]]
        let hasArm = !bust
        if mood == "wave" && hasArm {
            let n = waveCount ?? .infinity
            parts["arm"] = [arm == "down" || arm == nil ? cssTrack("cb-m-wave-up", 3200, "ease-in-out", iterations: n) : cssTrack("cb-m-wave", 2800, "ease-in-out", iterations: n)]
        }
        if mood == "think" {
            parts["body"] = [cssTrack("cb-m-bob", 3200, "ease-in-out", iterations: .infinity)]
            parts["look"] = [cssTrack("cb-m-glance", 4800, "ease-in-out", iterations: .infinity)]
            parts["brow"] = [cssTrack("cb-m-ponder", 3200, "ease-in-out", iterations: .infinity)]
        }
        if mood == "happy" {
            let hop = "cubic-bezier(.3,.7,.4,1)"
            parts["body"] = [cssTrack("cb-m-hop", 900, hop, iterations: 2)]
            parts["shadow"] = [cssTrack("cb-m-hop-shadow", 900, hop, iterations: 2)]
            if hasArm { parts["arm"] = [cssTrack("cb-m-cheer", 900, "ease-in-out", iterations: 2)] }
        }
        var settle = 0.0
        var loops = false
        var loopDurations: [Double] = []
        for (_, tracks) in parts {
            for t in tracks {
                if t.options.iterations == .infinity {
                    if t.options.duration != blinkMs { loops = true }
                    loopDurations.append(t.options.duration)
                } else {
                    settle = max(settle, t.options.delay + t.options.duration * t.options.iterations)
                }
            }
        }
        // Loops of their own (think, an endless wave): one lap of all of them together.
        let period = loops ? lcm(loopDurations) : blinkMs
        // The finite part done, the loop starts on a whole blink.
        return Plan(parts: parts, grin: grin, settle: (settle / blinkMs).rounded(.up) * blinkMs, period: period)
    }

    private static func gcd(_ a: Double, _ b: Double) -> Double { b == 0 ? a : gcd(b, a.truncatingRemainder(dividingBy: b)) }
    private static func lcm(_ xs: [Double]) -> Double { xs.reduce(1) { $0 * $1 / gcd($0, $1) } }

    /// The typing mascot (polish.css): the whole bust sways, the lids blink, the pupils glance; the three dots rise.
    public enum Typing {
        /// The bust's box, and its pivot (transform-origin 50% 90%).
        public static let size: Double = 32
        public static let origin: (Double, Double) = (16, 28.8)
        public static let sway = cssTrack("cb-typing-sway", 2400, "ease-in-out", iterations: .infinity)
        public static let blink = cssTrack("cb-typing-blink", 3400, "ease-in-out", iterations: .infinity)
        public static let glance = cssTrack("cb-typing-glance", 2400, "ease-in-out", iterations: .infinity)
        /// The thought dots: 4, 5 and 7 across, 0, 3 and 7 up, each 0.2s after the last.
        public static let dots: [(d: Double, up: Double, track: Track)] = [
            (4, 0, cssTrack("cb-typing-dot", 1200, "ease-in-out", iterations: .infinity)),
            (5, 3, cssTrack("cb-typing-dot", 1200, "ease-in-out", iterations: .infinity, delay: 200)),
            (7, 7, cssTrack("cb-typing-dot", 1200, "ease-in-out", iterations: .infinity, delay: 400)),
        ]
        /// One lap of all of it (the clock loops this).
        public static let period: Double = 40800
    }

    /// The pencil (polish.css .cb-typing--pencil): the line writes itself in 2s, the pencil riding its tip.
    public enum Pencil {
        public static let write = cssTrack("cb-typing-write", 2000, "linear", iterations: .infinity)
        public static let pencil = cssTrack("cb-typing-pencil", 2000, "linear", iterations: .infinity)
        public static let line = "M2 11 C 6 5, 9 5, 11 10 S 16 14, 19 9 S 25 4, 27 10 S 33 13, 36 8"
        public static let dash: Double = 60
        public static let period: Double = 2000
        /// Where the pencil rests under reduced motion (polish.css): at the line's end.
        public static let rest: (Double, Double) = (36, 8)
    }

    /// "Pip is typing" when the owner named their mascot (chatChrome.ts typingBubbleHtml), else "Typing".
    public static func typingLabel(_ style: String, _ mascotName: String) -> String {
        style == "mascot" && !mascotName.isEmpty ? "\(mascotName) is typing" : "Typing"
    }
}
