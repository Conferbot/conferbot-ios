//
//  MascotMotion.swift
//  Conferbot
//
//  The greeting card's figure, alive (conferbot-widget src/ts/home/mascotMotion.ts
//  and css/polish-home.css .cb-mm): how the bot's figure on the greeting
//  card moves. The figure is the owner's mascot (mascotInGreeting) or the
//  bot's avatar; everything here moves it as a whole.
//
//  customizations.mascotMotion: "lively" (absent), "subtle" or "off".
//
//  Lively, from the moment the card shows (it springs up, cb-greet-spring):
//      0ms  the greeting's words start fading up, one after another (< 1s)
//    140ms  the figure pops in: stretch, squash, settle (620ms)
//    760ms  a friendly wave, rocking about its feet (900ms)
//    900ms  the "Online" dot sends out one soft ping
//   1660ms  a blink-like double squash (380ms)
//   1900ms  idle: a slow breath (2px), and a small gesture every 8-12s,
//           three at most; 3s after the last one the breath ends on its
//           next exhale and the figure stands still for good.
//  Subtle: a gentle rise, the ping, the breath and a single head tilt; the
//  card comes in as it always did (cb-greet-in). Off: nothing moves.
//
//  Leaving: opening the chat from the card hands off (the figure shrinks
//  toward the launcher as the card collapses, cb-greet-collapse); the x
//  sends it off with a small bow (the card cb-greet-out). A voice note makes
//  it talk (a rhythmic squash) while its waveform plays.
//
//  Calm by design: no gesture while the app is in the background, nothing
//  that loops for ever, and under reduced motion just a fade. Hovering has
//  no counterpart on a touch screen, as on the web.
//
//  The director has no view: it calls a stage, on an FxScheduler (a fake
//  one in tests). The gestures are Web Animations keyframes (Keyframes
//  evaluates them); the card's own moves are CSS @keyframes, as the web
//  wrote them. Ported from the React Native SDK's core/mascotMotion.ts,
//  line for line. Pure.
//

import Foundation

/// What the director asks of the view. Every call is safe without a figure.
public protocol MascotStage: AnyObject {
    /// Play a one-off gesture on the figure (replacing one in flight).
    func play(_ g: String, amp: Double, delay: Double)
    /// Start the slow breath, or let it end on its next exhale.
    func breathe(_ on: Bool)
    /// Talk (a rhythmic squash) while a voice note plays.
    func talk(_ on: Bool, amp: Double)
    /// Lean toward the pointer: -1 (left) .. 1 (right), 0 upright.
    func lean(_ x: Double, amp: Double)
    /// The "Online" dot's single ping.
    func ping(_ on: Bool)
    /// The greeting's words fading up one by one.
    func words()
    /// Stop everything now, the figure as drawn.
    func reset()
}

public enum MascotMotion {
    public static let modes = ["lively", "subtle", "off"]
    public static let defaultMode = "lively"

    public static func normalize(_ value: Any?) -> String {
        (value as? String).flatMap { modes.contains($0) ? $0 : nil } ?? defaultMode
    }

    /// When each part of the entrance plays, ms after the card shows.
    public enum Entrance {
        public static let livelyPop: Double = 140
        public static let livelyWave: Double = 760
        public static let livelyPing: Double = 900
        public static let livelyNod: Double = 1660
        public static let livelyIdle: Double = 1900
        public static let subtleRise: Double = 80
        public static let subtlePing: Double = 600
        public static let subtleIdle: Double = 900
    }

    /// Idle gestures: one every 8-12s, at most this many, then still.
    public static let idleGapMin: Double = 8000
    public static let idleGapSpread: Double = 4000
    public static let idleGestures: [String: [String]] = ["lively": ["tilt", "wave", "tilt"], "subtle": ["tilt"]]
    /// After the last idle gesture, the breath ends this much later.
    public static let settleAfter: Double = 3000
    /// The "Online" ping's class stays this long (one ring).
    public static let pingMs: Double = 1300
    /// Hover hops no closer together than this.
    public static let hopGap: Double = 1500

    /// The web's director (mascotMotion.ts createMascotDirector), line for line.
    public final class Director {
        public enum State: String { case hidden, entering, living, settled, destroyed }

        private let mode: String
        private weak var stage: MascotStage?
        private let scheduler: FxScheduler
        private let reducedFn: () -> Bool
        private let ampFn: () -> Double
        private let ownText: () -> Bool
        private let random: () -> Double
        private let alive: (() -> Bool)?

        public private(set) var state: State = .hidden
        /// Idle gestures played since the card last showed.
        public private(set) var gestures = 0
        private var live: [ObjectIdentifier: FxTimer] = [:]
        private var talking = false
        private var wantTalk = false
        private var reduced = false
        private var amp = 1.0
        private var lastHop = -Double.infinity
        private var hidden = false
        private var idleTimer: FxTimer?
        private var talkTimer: FxTimer?

        private var lively: Bool { mode == "lively" }
        private var moving: Bool { mode != "off" && !reduced }

        public init(mode: String, stage: MascotStage, scheduler: FxScheduler = LauncherFxSession.scheduler,
                    reduced: @escaping () -> Bool = { false }, amp: @escaping () -> Double = { 1 },
                    ownText: @escaping () -> Bool = { false }, random: @escaping () -> Double = { Double.random(in: 0..<1) },
                    alive: (() -> Bool)? = nil) {
            self.mode = mode
            self.stage = stage
            self.scheduler = scheduler
            self.reducedFn = reduced
            self.ampFn = amp
            self.ownText = ownText
            self.random = random
            self.alive = alive
        }

        @discardableResult
        private func after(_ ms: Double, _ fn: @escaping () -> Void) -> FxTimer {
            var key: ObjectIdentifier?
            let t = scheduler.after(ms) { [weak self] in
                guard let self = self else { return }
                if let k = key { self.live[k] = nil }
                if let alive = self.alive, !alive() {
                    self.destroy()
                    return
                }
                fn()
            }
            key = ObjectIdentifier(t)
            live[key!] = t
            return t
        }

        private func cancel(_ t: FxTimer?) {
            guard let t = t else { return }
            t.cancel()
            live[ObjectIdentifier(t)] = nil
        }

        private func cancelAll() {
            for t in live.values { t.cancel() }
            live.removeAll()
            idleTimer = nil
            talkTimer = nil
        }

        private func startTalking() {
            if talking { return }
            talking = true
            stage?.talk(true, amp: lively ? amp : amp * 0.5)
        }

        private func stopTalking() {
            if !talking { return }
            talking = false
            stage?.talk(false, amp: amp)
        }

        private var gestureList: [String] { idleGestures[lively ? "lively" : "subtle"]! }

        private func scheduleIdle() {
            cancel(idleTimer)
            idleTimer = nil
            if state != .living || hidden { return }
            if gestures >= gestureList.count {
                idleTimer = after(settleAfter) { [weak self] in
                    self?.idleTimer = nil
                    self?.settle()
                }
                return
            }
            idleTimer = after(idleGapMin + (random() * idleGapSpread).rounded(.down)) { [weak self] in
                guard let self = self else { return }
                self.idleTimer = nil
                // Talking: the gesture waits for a quiet moment (not counted).
                if !self.talking {
                    self.stage?.play(self.gestureList[self.gestures], amp: self.amp, delay: 0)
                    self.gestures += 1
                }
                self.scheduleIdle()
            }
        }

        private func settle() {
            if state != .living { return }
            state = .settled
            stage?.breathe(false)
        }

        private func goLive() {
            if state != .entering { return }
            state = .living
            stage?.breathe(true)
            if wantTalk { startTalking() }
            scheduleIdle()
        }

        private func ping() {
            stage?.ping(true)
            after(pingMs) { [weak self] in self?.stage?.ping(false) }
        }

        public func show() {
            if state == .destroyed { return }
            cancelAll()
            stage?.reset()
            talking = false
            gestures = 0
            lastHop = -.infinity
            reduced = reducedFn()
            amp = max(0, min(1, ampFn()))
            if mode == "off" {
                state = .settled
                return
            }
            if reduced {
                // A plain fade, and nothing after it.
                stage?.play("fadeIn", amp: 0, delay: 0)
                state = .settled
                return
            }
            state = .entering
            if lively {
                if !ownText() { stage?.words() }
                stage?.play("pop", amp: amp, delay: Entrance.livelyPop)
                after(Entrance.livelyWave) { [weak self] in
                    guard let self = self else { return }
                    if self.wantTalk { self.startTalking() } else { self.stage?.play("wave", amp: self.amp, delay: 0) }
                }
                after(Entrance.livelyPing) { [weak self] in self?.ping() }
                after(Entrance.livelyNod) { [weak self] in
                    guard let self = self else { return }
                    if !self.talking { self.stage?.play("nod", amp: self.amp, delay: 0) }
                }
                after(Entrance.livelyIdle) { [weak self] in self?.goLive() }
            } else {
                stage?.play("rise", amp: amp, delay: Entrance.subtleRise)
                after(Entrance.subtlePing) { [weak self] in self?.ping() }
                after(Entrance.subtleIdle) { [weak self] in self?.goLive() }
            }
        }

        /// open: the chat opened (from the card or not); close: its x; away: gone without a move.
        public func hide(_ reason: String = "open") {
            if state == .destroyed || state == .hidden { return }
            cancelAll()
            let wasMoving = moving
            stage?.reset()
            talking = false
            wantTalk = false
            state = .hidden
            if wasMoving && reason != "away" { stage?.play(reason == "close" ? "bow" : "handoff", amp: lively ? amp : amp * 0.6, delay: 0) }
        }

        public func hover(_ on: Bool) {
            if !moving || (state != .living && state != .settled && state != .entering) { return }
            if !on {
                stage?.lean(0, amp: amp)
                return
            }
            if lively && state != .entering && !talking && scheduler.now() - lastHop >= hopGap {
                lastHop = scheduler.now()
                stage?.play("hop", amp: amp, delay: 0)
            }
        }

        public func point(_ x: Double) {
            if !moving || state == .hidden || state == .destroyed { return }
            let clamped = max(-1, min(1, x.isFinite ? x : 0))
            stage?.lean(clamped, amp: lively ? amp : amp * 0.6)
        }

        public func talk(_ on: Bool) {
            wantTalk = on
            if !on {
                cancel(talkTimer)
                talkTimer = nil
                stopTalking()
                return
            }
            if !moving || state == .hidden || state == .destroyed { return }
            // During the entrance it waits for the pop to land.
            if state == .entering { return }
            startTalking()
        }

        /// Talk for `ms`, then stop (a voice note of known length).
        public func talkFor(_ ms: Double) {
            if !moving || state == .hidden || state == .destroyed { return }
            talk(true)
            cancel(talkTimer)
            talkTimer = after(max(0, ms)) { [weak self] in
                self?.talkTimer = nil
                self?.talk(false)
            }
        }

        /// The app went to the background / came back.
        public func pageHidden(_ isHidden: Bool) {
            if hidden == isHidden { return }
            hidden = isHidden
            if state != .living { return }
            if hidden {
                cancel(idleTimer)
                idleTimer = nil
            } else {
                scheduleIdle()
            }
        }

        public func destroy() {
            if state == .destroyed { return }
            cancelAll()
            stage?.reset()
            talking = false
            state = .destroyed
        }

        /// Timers waiting (tests: none may outlive a hide / settle / destroy).
        public var pending: Int { live.count }
    }

    // MARK: - The gestures: Web Animations on the figure

    private static func sc(_ a: Double, _ x: Double) -> String { Keyframes.fixed(1 + (x - 1) * a, 4) }
    private static func dg(_ a: Double, _ x: Double) -> String { "\(Keyframes.fixed(x * a, 2))deg" }
    private static func px(_ a: Double, _ x: Double) -> String { "\(Keyframes.fixed(x * a, 2))px" }

    /// Each gesture's keyframes at a given amplitude (1 = the mascot's full swing), as the web passes them to element.animate().
    public static func gestureFrames(_ g: String, _ a: Double, toward: (x: Double, y: Double) = (0, 30)) -> (frames: [Keyframe], ms: Double, easing: String) {
        switch g {
        case "pop":
            return ([
                ["transform": "translateY(\(px(a, 6))) scale(0.3)", "opacity": 0, "offset": 0],
                ["transform": "translateY(\(px(a, -3))) scale(\(sc(a, 0.92)), \(sc(a, 1.14)))", "opacity": 1, "offset": 0.42],
                ["transform": "translateY(0px) scale(\(sc(a, 1.1)), \(sc(a, 0.9)))", "offset": 0.64],
                ["transform": "translateY(\(px(a, -1))) scale(\(sc(a, 0.97)), \(sc(a, 1.03)))", "offset": 0.82],
                ["transform": "none", "opacity": 1, "offset": 1],
            ], 620, "cubic-bezier(.3,.7,.4,1)")
        case "rise":
            return ([
                ["transform": "translateY(4px) scale(0.85)", "opacity": 0],
                ["transform": "none", "opacity": 1],
            ], 420, "cubic-bezier(.22,1,.36,1)")
        case "fadeIn":
            return ([["opacity": 0], ["opacity": 1]], 220, "ease-out")
        case "wave":
            return ([
                ["transform": "rotate(0deg)", "offset": 0],
                ["transform": "rotate(\(dg(a, -10)))", "offset": 0.2],
                ["transform": "rotate(\(dg(a, 8)))", "offset": 0.42],
                ["transform": "rotate(\(dg(a, -6)))", "offset": 0.62],
                ["transform": "rotate(\(dg(a, 3)))", "offset": 0.8],
                ["transform": "rotate(0deg)", "offset": 1],
            ], 900, "ease-in-out")
        case "tilt":
            return ([
                ["transform": "none", "offset": 0],
                ["transform": "rotate(\(dg(a, -7))) translateX(\(px(a, -1)))", "offset": 0.25],
                ["transform": "rotate(\(dg(a, -6))) translateX(\(px(a, -1)))", "offset": 0.7],
                ["transform": "none", "offset": 1],
            ], 1300, "cubic-bezier(.45,0,.25,1)")
        case "nod":
            return ([
                ["transform": "none", "offset": 0],
                ["transform": "scale(\(sc(a, 1.03)), \(sc(a, 0.9)))", "offset": 0.3],
                ["transform": "none", "offset": 0.55],
                ["transform": "scale(\(sc(a, 1.02)), \(sc(a, 0.93)))", "offset": 0.75],
                ["transform": "none", "offset": 1],
            ], 380, "ease-in-out")
        case "hop":
            return ([
                ["transform": "none", "offset": 0],
                ["transform": "scale(\(sc(a, 1.08)), \(sc(a, 0.92)))", "offset": 0.18],
                ["transform": "translateY(\(px(a, -6))) scale(\(sc(a, 0.96)), \(sc(a, 1.05)))", "offset": 0.45],
                ["transform": "scale(\(sc(a, 1.05)), \(sc(a, 0.95)))", "offset": 0.72],
                ["transform": "none", "offset": 1],
            ], 560, "cubic-bezier(.3,.7,.4,1)")
        case "handoff":
            // Toward the launcher, shrinking, gone as the card collapses.
            return ([
                ["transform": "none", "opacity": 1],
                ["transform": "translate(\(px(a, toward.x * 0.2)), \(px(a, toward.y * 0.12))) scale(\(sc(a, 1.08)), \(sc(a, 0.94)))", "opacity": 1, "offset": 0.25],
                ["transform": "translate(\(px(a, toward.x * 0.6)), \(px(a, toward.y * 0.6))) scale(0.25)", "opacity": 0],
            ], 280, "cubic-bezier(.5,0,.75,0)")
        default:
            // bow
            return ([
                ["transform": "none", "opacity": 1],
                ["transform": "rotate(\(dg(a, 6))) translateY(\(px(a, 1))) scale(\(sc(a, 1.02)), \(sc(a, 0.9)))", "opacity": 1, "offset": 0.4],
                ["transform": "rotate(\(dg(a, 6))) scale(0.5)", "opacity": 0],
            ], 300, "ease-in")
        }
    }

    /// A gesture as the track the web plays (fill backwards; forwards for the two that leave).
    public static func gestureTrack(_ g: String, _ amp: Double, delay: Double = 0, toward: (x: Double, y: Double)? = nil) -> Track {
        let f = toward.map { gestureFrames(g, amp, toward: $0) } ?? gestureFrames(g, amp)
        let leaving = g == "handoff" || g == "bow"
        return Track(f.frames, TrackOptions(duration: f.ms, delay: delay, iterations: 1, easing: f.easing, fill: leaving ? "forwards" : "backwards"))
    }

    public static let talkMs: Double = 640

    public static func talkFrames(_ a: Double) -> [Keyframe] {
        [
            ["transform": "none", "offset": 0],
            ["transform": "scale(\(sc(a, 1.025)), \(sc(a, 0.965)))", "offset": 0.2],
            ["transform": "scale(\(sc(a, 0.99)), \(sc(a, 1.03)))", "offset": 0.45],
            ["transform": "scale(\(sc(a, 1.03)), \(sc(a, 0.96)))", "offset": 0.7],
            ["transform": "none", "offset": 1],
        ]
    }

    /// The talk, one syllable per lap.
    public static func talkTrack(_ a: Double) -> Track {
        Track(talkFrames(a), TrackOptions(duration: talkMs, iterations: .infinity, easing: "ease-in-out"))
    }

    public static let breathMs: Double = 3400
    /// The slow breath, on the individual translate / scale (it sits under the gestures' transform).
    public static let breath = Track(
        [["translate": "0 0", "scale": "1"], ["translate": "0 -2px", "scale": "1.012"], ["translate": "0 0", "scale": "1"]],
        TrackOptions(duration: breathMs, iterations: .infinity, easing: "ease-in-out"))
    /// How far the figure leans toward the pointer at full amplitude.
    public static let leanDeg: Double = 6

    /// How far each figure moves: the mascot all the way, a photo 0.75, initials 0.55.
    public static func figureAmp(_ figure: String?) -> Double {
        figure == "initials" ? 0.55 : figure == "avatar" ? 0.75 : 1
    }

    /// The styles that reveal their own words (typewriter, the text message): no word fade.
    public static func ownsText(_ style: String) -> Bool { style == "typewriter" || style == "imessage" }

    // MARK: - The card (polish-home.css), as the web wrote it

    public static let cardKeyframes: [String: String] = [
        "cb-greet-in": "from { opacity: 0; transform: translateY(10px) scale(0.98); } to { opacity: 1; transform: none; }",
        "cb-greet-out": "from { opacity: 1; transform: none; } to { opacity: 0; transform: translateY(6px) scale(0.98); }",
        "cb-greet-spring": "0% { opacity: 0; transform: translateY(14px) scale(0.94); } 55% { opacity: 1; transform: translateY(-3px) scale(1.01); } 78% { transform: translateY(1px) scale(0.998); } 100% { opacity: 1; transform: none; }",
        "cb-greet-collapse": "from { opacity: 1; transform: none; } to { opacity: 0; transform: translateY(16px) scale(0.86); }",
        "cb-mm-word": "from { opacity: 0; transform: translateY(5px); filter: blur(2px); } to { opacity: 1; transform: none; filter: none; }",
        "cb-mm-dot": "0%, 100% { transform: scale(1); } 40% { transform: scale(1.35); }",
        "cb-mm-ring": "from { opacity: 0.55; transform: scale(1); } to { opacity: 0; transform: scale(3.2); }",
    ]

    private static func cardTrack(_ name: String, _ duration: Double, _ timing: String, delay: Double = 0, fill: String = "forwards") -> Track {
        Track(Keyframes.cssKeyframes(cardKeyframes[name]!, timing: timing), TrackOptions(duration: duration, delay: delay, iterations: 1, fill: fill))
    }

    /// How the card comes in: lively springs up (cb-greet-spring 0.62s), the
    /// others as always (cb-greet-in 0.45s). The notification and neon keep
    /// their own entrance, as does reduced motion (none): nil.
    public static func cardEnterTrack(_ mode: String, _ style: String, reduced: Bool = false) -> Track? {
        if reduced || style == "notification" || style == "neon" { return nil }
        return mode == "lively"
            ? cardTrack("cb-greet-spring", 620, "cubic-bezier(0.2, 0.9, 0.3, 1)")
            : cardTrack("cb-greet-in", 450, "cubic-bezier(0.22, 1, 0.36, 1)")
    }

    /// How the card goes: opened with the figure moving, it collapses toward
    /// the launcher (cb-greet-collapse 0.24s after 0.04s); otherwise it fades
    /// down (cb-greet-out 0.22s). Reduced motion: at once (nil).
    public static func cardLeaveTrack(_ mode: String, _ reason: String, reduced: Bool = false) -> Track? {
        if reduced { return nil }
        return reason == "open" && mode != "off"
            ? cardTrack("cb-greet-collapse", 240, "cubic-bezier(0.55, 0, 0.75, 0.2)", delay: 40)
            : cardTrack("cb-greet-out", 220, "ease-in")
    }

    /// The "Online" dot's ping: the dot swells once (cb-mm-dot 0.5s) and one ring goes out (cb-mm-ring 1.1s).
    public enum Ping {
        public static let dot = cardTrack("cb-mm-dot", 500, "cubic-bezier(0.3, 1.6, 0.5, 1)", fill: "none")
        public static let ring = cardTrack("cb-mm-ring", 1100, "cubic-bezier(0.2, 0.7, 0.3, 1)")
        /// No ring on the notification and postcard.
        public static func ringed(_ style: String) -> Bool { style != "notification" && style != "postcard" }
    }

    /// The greeting's words fading up (mascotMotion.ts stage.words): each word
    /// 0.32s, from 380ms, a step apart that shrinks for a longer message so
    /// all of it is up within about a second. Nil for fewer than two words.
    public static func wordFade(_ text: String) -> (words: [String], step: Double, tracks: [Track])? {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count < 2 { return nil }
        let step = min(55, (520 / Double(words.count - 1)).rounded(.down))
        return (words, step, words.indices.map { cardTrack("cb-mm-word", 320, "cubic-bezier(0.22, 1, 0.36, 1)", delay: 380 + Double($0) * step, fill: "both") })
    }

    /// How long a voice note "plays" as the card shows: 22 bars, each 1.2s twice, 60ms apart (polish-home.css cb-wave).
    public static func voicePlayMs(_ bars: Int = 22) -> Double { Double(bars - 1) * 60 + 1200 * 2 }
}
