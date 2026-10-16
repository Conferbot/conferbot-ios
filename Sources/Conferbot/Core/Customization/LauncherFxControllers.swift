//
//  LauncherFxControllers.swift
//  Conferbot
//
//  The rules round the launcher's entrance, attention loop and idle call
//  (LauncherEntrance.swift, LauncherAttention.swift, LauncherIdleCall.swift),
//  as the React Native SDK's hooks keep them (FloatingWidget/
//  useLauncherEntrance.ts, useLauncherAttention.ts, useLauncherIdleCall.ts).
//  Each controller owns its clock and timers on an `FxScheduler` (a fake one
//  in tests) and reports what to draw at a time; the launcher
//  (UI/SwiftUI/ConferBotWidgetView.swift) feeds them the chat's state and
//  draws. Plain Swift: nothing here touches SwiftUI. Main thread only.
//

import Foundation

/// A cancellable timer.
public protocol FxTimer: AnyObject {
    func cancel()
}

/// The clock and timers the controllers run on (ms).
public protocol FxScheduler: AnyObject {
    /// Milliseconds since 1970.
    func now() -> Double
    func after(_ ms: Double, _ fn: @escaping () -> Void) -> FxTimer
}

/// The wall clock and main-queue timers.
public final class RealFxScheduler: FxScheduler {
    public static let shared = RealFxScheduler()

    private final class Item: FxTimer {
        let work: DispatchWorkItem
        init(_ work: DispatchWorkItem) { self.work = work }
        func cancel() { work.cancel() }
    }

    public func now() -> Double { Date().timeIntervalSince1970 * 1000 }

    public func after(_ ms: Double, _ fn: @escaping () -> Void) -> FxTimer {
        let w = DispatchWorkItem(block: fn)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, ms) / 1000, execute: w)
        return Item(w)
    }
}

/// What the launcher remembers for the app session (the web's sessionStorage).
public enum LauncherFxSession {
    /// When the chat was last opened (ms; 0: not yet). Idle moments, attention and calls rest after it.
    public static var openedAt = 0.0

    /// The entrance each bot played this session (a different one plays once more).
    public static var entrancePlayed: [String: String] = [:]

    /// The calls each bot made this session.
    public static var visits: [String: LauncherIdleCall.VisitState] = [:]

    /// The clock the launcher's controllers run on (a test can set its own).
    public static var scheduler: FxScheduler = RealFxScheduler.shared

    public static func openedRecently(_ now: Double) -> Bool {
        openedAt != 0 && now - openedAt < LauncherMotion.openedRestMs
    }

    static func reset() {
        openedAt = 0
        entrancePlayed = [:]
        visits = [:]
    }
}

/// What the launcher and the greeting look like at a moment of the entrance.
public struct EntranceLook: Equatable {
    /// The launcher's opacity and transform (about its centre), and how much of it shows from the top (the ufo's beam: 1 = all).
    public var o = 1.0
    public var tx = 0.0
    public var ty = 0.0
    public var r = 0.0
    public var sx = 1.0
    public var sy = 1.0
    public var shown = 1.0
    /// The greeting card's opacity and drop.
    public var greetingO = 1.0
    public var greetingTy = 0.0
}

/// How the launcher arrives: decided when the bot's settings arrive, once
/// per app session per bot and entrance, never over an open chat or with
/// Reduce Motion. The launcher is held invisible until the effect reveals
/// it; the greeting stays hidden until it has landed, then fades up 150ms
/// later. Opening the chat ends it at once. `busy` (it has not landed yet)
/// holds the attention loop and the idle call.
public final class LauncherEntranceController {
    /// If the effect has not started by then, the launcher simply appears.
    public static let revealFailsafeMs = 6000.0

    /// Called whenever what it draws changes (not every frame).
    public var onChange: (() -> Void)?

    /// none, hold, play, done.
    public private(set) var phase = "none"
    public private(set) var plan: EntrancePlan?
    public private(set) var busy = false
    private var startedAt = 0.0
    private var decided = false
    private var laying = false
    private var timers: [FxTimer] = []
    private var mode = "classic"
    private var botId = ""
    private let clock: FxScheduler

    public init(clock: FxScheduler = LauncherFxSession.scheduler) {
        self.clock = clock
    }

    /// Once, when the settings arrive.
    public func decide(_ mode: String, botId: String, reduced: Bool, chatOpen: Bool) {
        if decided { return }
        decided = true
        self.mode = mode
        self.botId = botId.isEmpty ? "bot" : botId
        guard LauncherEntrance.shouldPlay(mode, reducedMotion: reduced, chatOpen: chatOpen, played: LauncherFxSession.entrancePlayed[self.botId] == mode) else { return }
        phase = "hold"
        busy = true
        timers.append(clock.after(Self.revealFailsafeMs) { [weak self] in
            if self?.phase == "hold" { self?.finish() }
        })
        onChange?()
    }

    /// The launcher is laid out (its size and place): the stage, the effect, the phases.
    public func laidOut(_ stage: @escaping () -> EntranceStage) {
        if phase != "hold" || laying { return }
        laying = true
        timers.append(clock.after(LauncherEntrance.startMs) { [weak self] in
            guard let self = self, self.phase == "hold" else { return }
            guard let p = LauncherEntrance.plan(self.mode, stage()) else { return self.finish() }
            LauncherFxSession.entrancePlayed[self.botId] = self.mode
            let tl = LauncherEntrance.timeline(p)
            self.plan = p
            self.phase = "play"
            self.startedAt = self.clock.now()
            self.timers.append(self.clock.after(tl.endAt.rounded(.up)) { [weak self] in self?.finish() })
            self.timers.append(self.clock.after(tl.settleAt.rounded(.up)) { [weak self] in
                self?.busy = false
                self?.onChange?()
            })
            self.onChange?()
        })
    }

    /// Opening the chat by any route ends it at once.
    public func chatOpened() {
        if phase == "hold" || phase == "play" { finish() }
    }

    public func finish() {
        timers.forEach { $0.cancel() }
        timers.removeAll()
        let was = phase
        busy = false
        phase = "done"
        if was != "done" { onChange?() }
    }

    public var active: Bool { phase == "hold" || phase == "play" }

    /// Milliseconds into the effect.
    public var elapsed: Double { phase == "play" ? clock.now() - startedAt : 0 }

    /// The launcher and the card at t ms (nil: nothing to change).
    public func lookAt(_ t: Double) -> EntranceLook? {
        if phase == "hold" { return EntranceLook(o: 0, greetingO: 0) }
        guard phase == "play", let p = plan else { return nil }
        let tl = LauncherEntrance.timeline(p)
        let settle = Keyframes.evaluate([LauncherEntrance.settleReveal.withDelay(tl.settleAt)], t)
        if t < p.revealAt { return EntranceLook(o: 0, greetingO: settle.o, greetingTy: settle.ty) }
        let arrive = p.arrive.withDelay(p.revealAt)
        let v = Keyframes.evaluate([arrive], t)
        let f = LauncherEntrance.spriteFrame(FxSprite(x: 0, y: 0, w: 0, h: 0, tracks: [arrive]), t, values: v)
        return EntranceLook(o: f.o, tx: f.tx, ty: f.ty, r: f.r, sx: f.sx, sy: f.sy, shown: 1 - v.clip / 100, greetingO: settle.o, greetingTy: settle.ty)
    }

    public func dispose() {
        timers.forEach { $0.cancel() }
        timers.removeAll()
        onChange = nil
    }
}

/// The opt-in "look here" loop: the first beat 1.5s after the launcher (or
/// the greeting card) shows, then a beat and stillness per lap while the
/// chat stays closed; paused while the launcher plays an idle or message
/// moment; not while an entrance lands; over once the chat is opened (and
/// not started when it was opened in the last 30 minutes); nothing with
/// Reduce Motion.
public final class LauncherAttentionController {
    public var onChange: (() -> Void)?

    public private(set) var mode = "off"
    private var enabled = false
    private var reduced = false
    private var cardShown = false
    private var moment = false
    private var entranceBusy = false
    private var hasSize = false
    private var wide = false
    private var over: Bool
    private var tracks: [Track] = []
    private let clock: FxScheduler

    // The clock: ms run so far, and since when it has been running (nil: stopped or paused).
    private var ran = 0.0
    private var since: Double?

    public init(clock: FxScheduler = LauncherFxSession.scheduler) {
        self.clock = clock
        over = LauncherFxSession.openedRecently(clock.now())
    }

    public var target: String? { LauncherAttention.target(mode) }
    public var active: Bool { enabled && target != nil && !reduced && !over }

    /// Moving the launcher: its idle moments hold off and the load ripples give way.
    public var onLauncher: Bool { active && target == "launcher" }
    public var running: Bool { active && !entranceBusy && hasSize && (target == "launcher" || cardShown) }

    public func update(mode: String, enabled: Bool, reduced: Bool, chatOpen: Bool, cardShown: Bool, moment: Bool, entranceBusy: Bool, hasSize: Bool, wide: Bool) {
        let wasRunning = running
        let wasActive = active
        let changed = mode != self.mode || wide != self.wide
        if changed {
            self.mode = mode
            self.wide = wide
            tracks = LauncherAttention.tracks(mode, clipped: false, wide: wide)
        }
        self.enabled = enabled
        self.reduced = reduced
        if chatOpen { over = true }
        self.cardShown = cardShown
        self.entranceBusy = entranceBusy
        self.hasSize = hasSize
        let now = clock.now()
        if running && (!wasRunning || changed) {
            // Run (again, from the start: the card showing again restarts it).
            ran = 0
            since = moment ? nil : now
        } else if !running && wasRunning {
            ran = 0
            since = nil
        } else if running && moment != self.moment {
            // A launcher moment (idle / message) pauses it.
            if moment, let s = since {
                ran += now - s
                since = nil
            } else if !moment && since == nil {
                since = now
            }
        }
        self.moment = moment
        if running != wasRunning || active != wasActive { onChange?() }
    }

    /// Milliseconds on the loop's clock: the intro, then lap after lap.
    public var elapsed: Double {
        guard running, let first = tracks.first else { return 0 }
        let t = ran + (since.map { clock.now() - $0 } ?? 0)
        let intro = tracks.map { $0.options.delay }.max() ?? 0
        let period = first.options.duration
        return t < intro ? t : intro + (t - intro).truncatingRemainder(dividingBy: period)
    }

    /// A part's values at t ms (nil when the mode has no such part or it is not running).
    public func part(_ name: String, _ t: Double) -> FxValues? {
        guard running, let tr = tracks.first(where: { $0.part == name }) else { return nil }
        return Keyframes.evaluate([tr], t, base: LauncherAttention.base[name])
    }

    public func has(_ name: String) -> Bool { running && tracks.contains { $0.part == name } }
}

/// Where the 3-day rest is kept.
public protocol IdleCallRestStore {
    func read(_ botId: String) -> Double
    func write(_ botId: String, until: Double)
}

/// The rest in UserDefaults, per bot, as `{"until": ms}` (the web's localStorage entry).
public struct DefaultsIdleCallRestStore: IdleCallRestStore {
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public static func key(_ botId: String) -> String { "conferbot_idlecall_rest_\(botId.isEmpty ? "default" : botId)" }

    public func read(_ botId: String) -> Double {
        guard let s = defaults.string(forKey: Self.key(botId)), let d = s.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return 0 }
        return Keyframes.number(j["until"]) ?? 0
    }

    public func write(_ botId: String, until: Double) {
        defaults.set("{\"until\":\(Int64(until))}", forKey: Self.key(botId))
    }
}

/// The idle call: after the owner's delay, if the visitor has not opened the
/// chat, the mascot slips out from behind the launcher and calls them over,
/// with a speech bubble that opens the chat. One call per screen, two per
/// app session 3 minutes apart, then 3 days' rest (also after an opening);
/// closing the greeting means none for the session. A call waits while the
/// chat is open, the app is in the background, the keyboard is up, an
/// entrance lands, or the greeting has had less than 15s alone.
public final class LauncherIdleCallController {
    public var onChange: (() -> Void)?

    // What the launcher reports.
    public var chatOpen = false
    public var appActive = true
    public var keyboard = false
    public var entranceBusy = false
    public var width: Double?
    public var height: Double?
    public var position = "right"
    private var cardSince = 0.0
    public var cardShown = false {
        didSet {
            if cardShown && !oldValue { cardSince = clock.now() }
            if !cardShown { cardSince = 0 }
        }
    }

    public private(set) var perf: LauncherIdleCall.Performance?
    private var startedAt = 0.0
    private var started = false
    private var destroyed = false
    private var playing = false
    private var mode = "off"
    private var botId = ""
    private var restUntil = 0.0
    private var timers: [FxTimer] = []
    private let clock: FxScheduler
    private let store: IdleCallRestStore

    public init(clock: FxScheduler = LauncherFxSession.scheduler, store: IdleCallRestStore) {
        self.clock = clock
        self.store = store
    }

    private func later(_ ms: Double, _ fn: @escaping () -> Void) { timers.append(clock.after(ms, fn)) }

    private var visit: LauncherIdleCall.VisitState { LauncherFxSession.visits[botId] ?? LauncherIdleCall.VisitState() }
    private func allowed() -> Bool {
        !LauncherFxSession.openedRecently(clock.now()) && LauncherIdleCall.callAllowed(visit, restUntil: restUntil, now: clock.now())
    }
    private func blocked() -> Bool {
        let greetingHasTheFloor = cardShown && clock.now() - cardSince < LauncherIdleCall.greetingFirstMs
        return chatOpen || !appActive || keyboard || greetingHasTheFloor || entranceBusy || width == nil || height == nil
    }

    /// Once, when the settings arrive.
    public func start(_ mode: String, delay: Int, botId: String, reduced: Bool) {
        if started { return }
        started = true
        self.mode = mode
        self.botId = botId
        if mode == "off" || reduced { return }
        restUntil = store.read(botId)
        if destroyed || !allowed() { return }
        later(Double(delay) * 1000) { [weak self] in self?.attempt() }
    }

    private func attempt() {
        if destroyed { return }
        if !allowed() { return destroy() }
        if playing || blocked() { return later(LauncherIdleCall.retryMs) { [weak self] in self?.attempt() } }
        let now = clock.now()
        let (next, rest) = LauncherIdleCall.afterCall(visit, now: now)
        LauncherFxSession.visits[botId] = next
        // After the last call this session, rest for a few days.
        if rest { store.write(botId, until: now + LauncherIdleCall.restMs) }
        let p = LauncherIdleCall.performance(mode, LauncherIdleCall.geometry(width!, height!, position, cardShown))
        playing = true
        perf = p
        startedAt = now
        later(p.total.rounded(.up) + 80) { [weak self] in self?.stop() }
        onChange?()
    }

    /// The call over (or cut short by a tap on its bubble).
    public func stop() {
        playing = false
        if perf != nil {
            perf = nil
            onChange?()
        }
    }

    private func destroy() {
        destroyed = true
        timers.forEach { $0.cancel() }
        timers.removeAll()
        stop()
    }

    /// Opening the chat: the call ends, and they are left alone for a few days.
    public func chatOpened() {
        chatOpen = true
        if destroyed || mode == "off" || !started { return }
        store.write(botId, until: clock.now() + LauncherIdleCall.restMs)
        destroy()
    }

    /// The greeting was closed ("not now"): no more calls this session.
    public func greetingClosed() {
        if mode == "off" { return }
        var v = visit
        v.quiet = true
        LauncherFxSession.visits[botId] = v
        destroy()
    }

    /// Milliseconds into the call.
    public var elapsed: Double { perf == nil ? 0 : clock.now() - startedAt }

    public func dispose() {
        destroyed = true
        timers.forEach { $0.cancel() }
        timers.removeAll()
        onChange = nil
    }
}
