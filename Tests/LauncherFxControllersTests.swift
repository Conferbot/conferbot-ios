import XCTest
@testable import Conferbot

/// The rules round the launcher's entrance, attention loop and idle call (as the React Native SDK's hooks keep them), on a fake clock.
final class LauncherFxControllersTests: XCTestCase {
    final class FakeTimer: FxTimer {
        let at: Double
        let fn: () -> Void
        var cancelled = false
        init(_ at: Double, _ fn: @escaping () -> Void) {
            self.at = at
            self.fn = fn
        }
        func cancel() { cancelled = true }
    }

    final class FakeClock: FxScheduler {
        var t = 1_000_000_000_000.0
        private var timers: [FakeTimer] = []
        func now() -> Double { t }
        func after(_ ms: Double, _ fn: @escaping () -> Void) -> FxTimer {
            let x = FakeTimer(t + ms, fn)
            timers.append(x)
            return x
        }

        /// Moves the clock on, firing the timers due in order.
        func advance(_ ms: Double) {
            let end = t + ms
            while let x = timers.filter({ !$0.cancelled && $0.at <= end }).min(by: { $0.at < $1.at }) {
                timers.removeAll { $0 === x }
                t = x.at
                x.fn()
            }
            t = end
        }
    }

    final class MemoryRest: IdleCallRestStore {
        var until: [String: Double] = [:]
        func read(_ botId: String) -> Double { until[botId] ?? 0 }
        func write(_ botId: String, until: Double) { self.until[botId] = until }
    }

    private func stage() -> EntranceStage {
        LauncherEntrance.stage(width: 50, height: 50, position: "right", screenWidth: 390, screenHeight: 844, side: 16, bottom: 16, accent: "#4f46e5")
    }

    override func setUp() {
        super.setUp()
        LauncherFxSession.reset()
    }

    // MARK: - Entrance

    func testEntranceHoldsPlaysAndKeepsTheCardHiddenUntilItLandsThenFadesItUp150msLater() throws {
        let clock = FakeClock()
        let c = LauncherEntranceController(clock: clock)
        c.decide("rocket", botId: "b1", reduced: false, chatOpen: false)
        XCTAssertEqual(c.phase, "hold")
        XCTAssertTrue(c.busy)
        XCTAssertEqual(c.lookAt(0)?.o, 0)
        XCTAssertEqual(c.lookAt(0)?.greetingO, 0)
        c.laidOut(stage)
        clock.advance(LauncherEntrance.startMs)
        XCTAssertEqual(c.phase, "play")
        let tl = LauncherEntrance.timeline(try XCTUnwrap(c.plan))
        // Before the reveal the launcher is still hidden; the card stays hidden until the landing settles.
        XCTAssertEqual(c.lookAt(tl.landAt - 1)?.o, 0)
        XCTAssertEqual(c.lookAt(tl.landedAt)?.greetingO, 0)
        XCTAssertEqual(c.lookAt(tl.settleAt - 1)?.greetingO, 0)
        XCTAssertGreaterThan(try XCTUnwrap(c.lookAt(tl.settleAt + 450)).greetingO, 0.5)
        clock.advance(tl.settleAt.rounded(.up))
        XCTAssertFalse(c.busy)
        clock.advance((tl.endAt - tl.settleAt).rounded(.up) + 1)
        XCTAssertEqual(c.phase, "done")
        XCTAssertNil(c.lookAt(0))
    }

    func testEntrancePlaysOncePerAppSessionPerBotAndEntrance() {
        let clock = FakeClock()
        let a = LauncherEntranceController(clock: clock)
        a.decide("drop", botId: "b1", reduced: false, chatOpen: false)
        a.laidOut(stage)
        clock.advance(5000)
        XCTAssertEqual(LauncherFxSession.entrancePlayed["b1"], "drop")
        func phase(_ mode: String, _ bot: String) -> String {
            let c = LauncherEntranceController(clock: clock)
            c.decide(mode, botId: bot, reduced: false, chatOpen: false)
            return c.phase
        }
        XCTAssertEqual(phase("drop", "b1"), "none")
        XCTAssertEqual(phase("drop", "b2"), "hold")
        XCTAssertEqual(phase("coin", "b1"), "hold")
    }

    func testEntranceNeverOverAnOpenChatWithReduceMotionOrForClassicAndOpeningTheChatEndsIt() {
        let clock = FakeClock()
        func phase(_ mode: String, reduced: Bool, chatOpen: Bool) -> String {
            let c = LauncherEntranceController(clock: clock)
            c.decide(mode, botId: "x", reduced: reduced, chatOpen: chatOpen)
            return c.phase
        }
        XCTAssertEqual(phase("ufo", reduced: false, chatOpen: true), "none")
        XCTAssertEqual(phase("ufo", reduced: true, chatOpen: false), "none")
        XCTAssertEqual(phase("classic", reduced: false, chatOpen: false), "none")
        let c = LauncherEntranceController(clock: clock)
        c.decide("ufo", botId: "x", reduced: false, chatOpen: false)
        c.laidOut(stage)
        clock.advance(200)
        c.chatOpened()
        XCTAssertEqual(c.phase, "done")
        XCTAssertFalse(c.busy)
    }

    func testTheLauncherSimplyAppearsIfItIsNeverLaidOut() {
        let clock = FakeClock()
        let c = LauncherEntranceController(clock: clock)
        c.decide("egg", botId: "x", reduced: false, chatOpen: false)
        clock.advance(LauncherEntranceController.revealFailsafeMs)
        XCTAssertEqual(c.phase, "done")
    }

    func testEveryEntranceRevealsTheLauncherAndEndsAtRest() throws {
        for mode in LauncherEntrance.modes where mode != "classic" {
            let p = try XCTUnwrap(LauncherEntrance.plan(mode, stage(), seed: 7))
            let end = Keyframes.evaluate([p.arrive.withDelay(p.revealAt)], p.revealAt + p.arrive.options.duration - 0.01)
            XCTAssertEqual(end.o, 1, accuracy: 1e-3, mode)
            XCTAssertEqual(end.tx, 0, accuracy: 1e-3, mode)
            XCTAssertEqual(end.ty, 0, accuracy: 1e-3, mode)
            XCTAssertEqual(end.sx, 1, accuracy: 1e-3, mode)
            XCTAssertEqual(end.sy, 1, accuracy: 1e-3, mode)
            XCTAssertFalse(p.sprites.isEmpty, mode)
        }
    }

    // MARK: - Attention

    private func feed(_ c: LauncherAttentionController, mode: String = "heartbeat", chatOpen: Bool = false, card: Bool = false,
                      moment: Bool = false, busy: Bool = false, size: Bool = true, reduced: Bool = false) {
        c.update(mode: mode, enabled: true, reduced: reduced, chatOpen: chatOpen, cardShown: card, moment: moment, entranceBusy: busy, hasSize: size, wide: false)
    }

    func testAttentionWaitsForTheEntranceThenRunsItsLoopFromTheStart() {
        let clock = FakeClock()
        let c = LauncherAttentionController(clock: clock)
        feed(c, busy: true)
        XCTAssertTrue(c.onLauncher)
        XCTAssertFalse(c.running)
        clock.advance(3000)
        feed(c)
        XCTAssertTrue(c.running)
        XCTAssertEqual(c.elapsed, 0)
        clock.advance(1600)
        XCTAssertEqual(c.elapsed, 1600)
        // Laps after the 1.5s intro.
        clock.advance(3000)
        XCTAssertEqual(c.elapsed, 1600, accuracy: 1e-9)
    }

    func testAttentionPausesForALauncherMomentAndResumesWhereItWas() {
        let clock = FakeClock()
        let c = LauncherAttentionController(clock: clock)
        feed(c)
        clock.advance(500)
        feed(c, moment: true)
        clock.advance(2600)
        XCTAssertEqual(c.elapsed, 500)
        feed(c)
        clock.advance(100)
        XCTAssertEqual(c.elapsed, 600)
    }

    func testAttentionIsOverOnceTheChatOpensAndNotStartedWithin30MinutesOfAnOpening() {
        let clock = FakeClock()
        let c = LauncherAttentionController(clock: clock)
        feed(c)
        feed(c, chatOpen: true)
        XCTAssertFalse(c.running)
        feed(c)
        XCTAssertFalse(c.running)
        LauncherFxSession.openedAt = clock.now()
        clock.advance(LauncherMotion.openedRestMs - 1)
        let d = LauncherAttentionController(clock: clock)
        feed(d)
        XCTAssertFalse(d.active)
        clock.advance(2)
        let e = LauncherAttentionController(clock: clock)
        feed(e)
        XCTAssertTrue(e.running)
    }

    func testACardModeRunsOnlyWhileTheCardShowsAndNothingWithReduceMotion() {
        let clock = FakeClock()
        let c = LauncherAttentionController(clock: clock)
        feed(c, mode: "wave")
        XCTAssertEqual(c.target, "greeting")
        XCTAssertFalse(c.onLauncher)
        XCTAssertFalse(c.running)
        feed(c, mode: "wave", card: true)
        XCTAssertTrue(c.running)
        XCTAssertTrue(c.has("hand"))
        let r = LauncherAttentionController(clock: clock)
        feed(r, reduced: true)
        XCTAssertFalse(r.active)
    }

    // MARK: - Idle call

    private func started(_ mode: String = "knock", delay: Int = 12, bot: String = "b1", clock: FakeClock = FakeClock(), rest: MemoryRest = MemoryRest()) -> (LauncherIdleCallController, FakeClock, MemoryRest) {
        let c = LauncherIdleCallController(clock: clock, store: rest)
        c.width = 50
        c.height = 50
        c.start(mode, delay: delay, botId: bot, reduced: false)
        return (c, clock, rest)
    }

    func testIdleCallCallsAfterTheDelayAndIsOverAfterItsPerformance() throws {
        let (c, clock, _) = started()
        clock.advance(11999)
        XCTAssertNil(c.perf)
        clock.advance(1)
        let p = try XCTUnwrap(c.perf)
        XCTAssertTrue(p.front)
        clock.advance(p.total.rounded(.up) + 80)
        XCTAssertNil(c.perf)
    }

    func testIdleCallWaits4sAtATimeWhileBlocked() throws {
        let (c, clock, _) = started()
        c.keyboard = true
        clock.advance(12000)
        XCTAssertNil(c.perf)
        c.keyboard = false
        c.appActive = false
        clock.advance(LauncherIdleCall.retryMs)
        XCTAssertNil(c.perf)
        c.appActive = true
        c.entranceBusy = true
        clock.advance(LauncherIdleCall.retryMs)
        XCTAssertNil(c.perf)
        c.entranceBusy = false
        c.chatOpen = true
        clock.advance(LauncherIdleCall.retryMs)
        XCTAssertNil(c.perf)
        c.chatOpen = false
        c.cardShown = true
        clock.advance(LauncherIdleCall.retryMs)
        XCTAssertNil(c.perf)
        // The card has had 15s alone: the mascot calls, without a bubble.
        clock.advance(12000)
        XCTAssertFalse(try XCTUnwrap(c.perf).talks)
    }

    func testIdleCallTwicePerSession3MinutesApartThen3DaysOfRest() {
        let clock = FakeClock()
        let rest = MemoryRest()
        let a = started(clock: clock, rest: rest).0
        clock.advance(12000)
        XCTAssertNotNil(a.perf)
        XCTAssertNil(rest.until["b1"])
        // A second screen this session, too soon: nothing.
        let b = started(clock: clock, rest: rest).0
        clock.advance(60000)
        XCTAssertNil(b.perf)
        clock.advance(LauncherIdleCall.minGapMs)
        let c = started(clock: clock, rest: rest).0
        clock.advance(12000)
        XCTAssertNotNil(c.perf)
        XCTAssertGreaterThan(rest.until["b1"]!, clock.now() + LauncherIdleCall.restMs - 20000)
        // A third: the session's two are spent.
        clock.advance(LauncherIdleCall.minGapMs * 2)
        let d = started(clock: clock, rest: rest).0
        clock.advance(12000)
        XCTAssertNil(d.perf)
        // Next session (the rest stays in storage).
        LauncherFxSession.reset()
        let e = started(clock: clock, rest: rest).0
        clock.advance(12000)
        XCTAssertNil(e.perf)
        clock.advance(LauncherIdleCall.restMs)
        LauncherFxSession.reset()
        let f = started(clock: clock, rest: rest).0
        clock.advance(12000)
        XCTAssertNotNil(f.perf)
    }

    func testOpeningTheChatEndsTheCallAndRests3DaysAndClosingTheGreetingStopsCallsForTheSession() {
        let (c, clock, rest) = started()
        clock.advance(12000)
        c.chatOpened()
        XCTAssertNil(c.perf)
        XCTAssertEqual(rest.until["b1"], clock.now() + LauncherIdleCall.restMs)
        let (g, clock2, _) = started(bot: "b2")
        g.greetingClosed()
        clock2.advance(60000)
        XCTAssertNil(g.perf)
        XCTAssertEqual(LauncherFxSession.visits["b2"]?.quiet, true)
    }

    func testIdleCallNothingForOffOrWithReduceMotionNorWithin30MinutesOfAnOpening() {
        let (off, k1, _) = started("off")
        k1.advance(60000)
        XCTAssertNil(off.perf)
        let clock = FakeClock()
        let reduced = LauncherIdleCallController(clock: clock, store: MemoryRest())
        reduced.width = 50
        reduced.height = 50
        reduced.start("wave", delay: 5, botId: "b3", reduced: true)
        clock.advance(60000)
        XCTAssertNil(reduced.perf)
        LauncherFxSession.openedAt = clock.now()
        let opened = started(bot: "b4", clock: clock).0
        clock.advance(60000)
        XCTAssertNil(opened.perf)
    }

    func testTheRestIsKeptInUserDefaultsPerBot() {
        let defaults = UserDefaults(suiteName: "launcherfx-test")!
        defaults.removePersistentDomain(forName: "launcherfx-test")
        let store = DefaultsIdleCallRestStore(defaults: defaults)
        XCTAssertEqual(store.read("b1"), 0)
        store.write("b1", until: 1_700_000_000_123)
        XCTAssertEqual(store.read("b1"), 1_700_000_000_123)
        XCTAssertEqual(store.read("b2"), 0)
        XCTAssertEqual(defaults.string(forKey: "conferbot_idlecall_rest_b1"), "{\"until\":1700000000123}")
        defaults.removePersistentDomain(forName: "launcherfx-test")
    }
}
