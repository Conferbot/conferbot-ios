//
//  DelightTests.swift
//  Conferbot
//
//  The conversation's human touches (RN __tests__/core/delight.test.ts; web
//  ts/chat/delight/rules.ts, index.ts, stallNudge.ts, celebrate.ts,
//  ratingFx.ts), auto-open (RN autoOpen.test.ts) and the typing preview
//  (RN typingPreview.test.ts).
//

import XCTest
@testable import Conferbot

/// A fake clock for the injected timers: ms, run in time order.
final class TouchClock {
    final class Timer { let at: Double; let fn: () -> Void; var cancelled = false; init(_ at: Double, _ fn: @escaping () -> Void) { self.at = at; self.fn = fn } }
    var now = 0.0
    private var timers: [Timer] = []

    func set(_ ms: Double, _ fn: @escaping () -> Void) -> AnyObject {
        let t = Timer(now + ms, fn)
        timers.append(t)
        return t
    }

    func clear(_ t: AnyObject) { (t as? Timer)?.cancelled = true }

    func advance(_ ms: Double) {
        let end = now + ms
        while true {
            timers.removeAll { $0.cancelled }
            timers.sort { $0.at < $1.at }
            guard let t = timers.first, t.at <= end else { break }
            timers.removeFirst()
            now = t.at
            t.fn()
        }
        now = end
    }
}

final class DelightTests: XCTestCase {

    override func tearDown() {
        I18n.setWidgetLanguage("en", languages: [])
        super.tearDown()
    }

    func testOnUnlessTheOwnerSetItToFalse() {
        XCTAssertTrue(Delight.touchOn([:], .celebrations))
        XCTAssertTrue(Delight.touchOn(nil, .botReactions))
        XCTAssertFalse(Delight.touchOn(["celebrations": false], .celebrations))
        XCTAssertTrue(Delight.touchOn(["stallNudges": 0], .stallNudges))
    }

    func testQuestionsCanBeChangedWhileOnlySafeStepsRanSince() {
        XCTAssertTrue(Delight.canChangeAnswer("ask-email-node", []))
        XCTAssertTrue(Delight.canChangeAnswer("ask-email-node", ["message-node", "condition-node", "delay-node", "ask-name-node"]))
        XCTAssertFalse(Delight.canChangeAnswer("ask-email-node", ["calendar-node"]))
        XCTAssertFalse(Delight.canChangeAnswer("ask-email-node", ["webhook-node"]))
        XCTAssertFalse(Delight.canChangeAnswer("ask-email-node", ["agent"]))
        XCTAssertFalse(Delight.canChangeAnswer("calendar-node", []))
        XCTAssertFalse(Delight.isSafeToUndo("welcome-node"))
        XCTAssertTrue(Delight.waitsForAnswer("payment-node"))
        XCTAssertFalse(Delight.waitsForAnswer("message-node"))
    }

    func testEditOnlyOnTheLatestAnswerWhenTheBotIsQuietAndNothingLocksTheChat() {
        func show(_ c: [String: Any] = [:], locked: Bool = false, busy: Bool = false, latest: Bool = true) -> Bool {
            Delight.showChangeFor(customizations: c, locked: locked, botBusy: busy, isLatestAnswer: latest, questionType: "ask-name-node", typesSince: [])
        }
        XCTAssertTrue(show())
        XCTAssertFalse(show(["allowChangeAnswer": false]))
        XCTAssertFalse(show(locked: true))
        XCTAssertFalse(show(busy: true))
        XCTAssertFalse(show(latest: false))
    }

    func testReadsAScoreFromTheAnswerText() {
        XCTAssertEqual(Delight.scoreShare("★★★★ Good")!, 0.8, accuracy: 1e-9)
        XCTAssertEqual(Delight.scoreShare("⭐⭐⭐⭐⭐"), 1)
        XCTAssertEqual(Delight.scoreShare("8/10")!, 0.8, accuracy: 1e-9)
        XCTAssertEqual(Delight.scoreShare("7 / 10")!, 0.7, accuracy: 1e-9)
        XCTAssertNil(Delight.scoreShare("hello"))
        XCTAssertEqual(Delight.scoreText("rating-choice-node", 4, 5), "4/5")
        XCTAssertEqual(Delight.scoreText("ask-name-node", 4, 5), "")
    }

    func testReactsAsAPersonWould() {
        XCTAssertEqual(Delight.reactionFor("ask-name-node", "Jamie"), "👋")
        XCTAssertEqual(Delight.reactionFor("calendar-node", "Tue 10:00"), "🎉")
        XCTAssertEqual(Delight.reactionFor("payment-node", "Paid"), "🎉")
        XCTAssertEqual(Delight.reactionFor("rating-choice-node", "5/5"), "❤️")
        XCTAssertEqual(Delight.reactionFor("opinion-scale-choice-node", "6/10"), "👍")
        XCTAssertEqual(Delight.reactionFor("user-rating-node", "2/5"), "🙏")
        XCTAssertNil(Delight.reactionFor("rating-choice-node", "great"))
        XCTAssertNil(Delight.reactionFor("ask-email-node", "a@b.co"))
        XCTAssertEqual(Delight.reactionLabel("👋"), "The bot waved")
        XCTAssertEqual(Delight.reactionLabel("🦄"), "The bot reacted")
    }

    func testCelebratesABookingAPaymentAPerfectScoreNotTheRatingCard() {
        XCTAssertTrue(Delight.celebrates("calendar-node", ""))
        XCTAssertTrue(Delight.celebrates("payment-node", ""))
        XCTAssertTrue(Delight.celebrates("opinion-scale-choice-node", "10/10"))
        XCTAssertFalse(Delight.celebrates("opinion-scale-choice-node", "9/10"))
        XCTAssertFalse(Delight.celebrates("rating-choice-node", "5/5"))
        XCTAssertFalse(Delight.celebrates("ask-email-node", ""))
    }

    func testFollowsTheOwnersSwitchesAndReduceMotion() {
        var t = Delight.touchesFor([:], "calendar-node", "", reducedMotion: false)
        XCTAssertEqual(t.reaction, "🎉"); XCTAssertTrue(t.celebrate)
        t = Delight.touchesFor([:], "calendar-node", "", reducedMotion: true)
        XCTAssertEqual(t.reaction, "🎉"); XCTAssertFalse(t.celebrate)
        t = Delight.touchesFor(["celebrations": false], "calendar-node", "", reducedMotion: false)
        XCTAssertEqual(t.reaction, "🎉"); XCTAssertFalse(t.celebrate)
        t = Delight.touchesFor(["botReactions": false], "ask-name-node", "Jo", reducedMotion: false)
        XCTAssertNil(t.reaction); XCTAssertFalse(t.celebrate)
    }

    func testDrawsTheWebsConfettiFanAndRatingSparks() {
        let pieces = Delight.confettiPieces { 0.5 }
        XCTAssertEqual(pieces.count, Delight.confettiPieceCount)
        // The first piece at -160 degrees (no jitter at 0.5), 86 out.
        let a = -160 * Double.pi / 180
        XCTAssertEqual(pieces[0], Delight.ConfettiPiece(dx: (cos(a) * 86).rounded(), dy: (sin(a) * 86 + 0.5).rounded(.down),
                                                        fall: 41, rot: 0, delay: 45, tone: 0, round: true))
        // The fan opens up: every piece flies upward.
        pieces.forEach { XCTAssertLessThan($0.dy, 0) }
        XCTAssertEqual(pieces.prefix(5).map { $0.tone }, [0, 1, 2, 3, 0])
        XCTAssertEqual(Delight.ratingSparks(top: false), [20, 65, 110, 155, 200, 245, 290, 335])
        XCTAssertEqual(Delight.ratingSparks(top: true).count, 12)
    }

    func testWordsTheNudgeForTypingOrPickingInTheVisitorsLanguage() {
        XCTAssertEqual(Delight.stallHintFor("ask-email-node"), "No rush - type your answer below whenever you're ready.")
        XCTAssertEqual(Delight.stallHintFor("n-choices-node"), "No rush - pick whichever fits when you're ready.")
        I18n.setWidgetLanguage("de", languages: [])
        XCTAssertFalse(Delight.stallHintFor("n-choices-node").contains("No rush"))
        XCTAssertTrue(Delight.nudgesWhileWaiting("calendar-node"))
        XCTAssertFalse(Delight.nudgesWhileWaiting("ask-file-node"))
    }

    // MARK: - The stall watch

    private func watch(_ clock: TouchClock, visible: @escaping () -> Bool = { true }, composer: @escaping () -> String = { "" },
                       shown: @escaping (String) -> Void, hidden: @escaping () -> Void) -> Delight.StallWatch {
        Delight.StallWatch(isVisible: visible, composerValue: composer, show: shown, hide: hidden,
                           now: { clock.now }, setTimer: { clock.set($0, $1) }, clearTimer: { clock.clear($0) })
    }

    func testNudgesOnce40sIntoAQuestionNobodyTouched() {
        let clock = TouchClock()
        var shown: [String] = []
        var hidden = 0
        let w = watch(clock, shown: { shown.append($0) }, hidden: { hidden += 1 })
        clock.advance(Delight.stallQuietMs)
        w.arm("n-choices-node")
        clock.advance(Delight.stallAfterMs - 1)
        XCTAssertEqual(shown, [])
        clock.advance(1)
        XCTAssertEqual(shown, ["No rush - pick whichever fits when you're ready."])
        w.arm("n-choices-node")
        clock.advance(Delight.stallAfterMs * 2)
        XCTAssertEqual(shown.count, 1)
        w.disarm()
        XCTAssertEqual(hidden, 1)
    }

    func testWaitsWhileTheVisitorIsBusyAwayOrTyping() {
        let clock = TouchClock()
        var visible = false
        var typed = "hel"
        var shown: [String] = []
        let w = watch(clock, visible: { visible }, composer: { typed }, shown: { shown.append($0) }, hidden: {})
        clock.advance(Delight.stallQuietMs)
        w.arm("ask-name-node")
        clock.advance(Delight.stallAfterMs)
        XCTAssertEqual(shown, [])
        visible = true
        clock.advance(Delight.stallQuietMs)
        XCTAssertEqual(shown, []) // still typing
        typed = ""
        w.touch()
        clock.advance(Delight.stallQuietMs - 1)
        XCTAssertEqual(shown, [])
        clock.advance(Delight.stallQuietMs)
        XCTAssertEqual(shown.count, 1)
    }

    func testGoesQuietlyWhenAnsweredBeforeTheNudge() {
        let clock = TouchClock()
        var shown: [String] = []
        var hidden = 0
        let w = watch(clock, shown: { shown.append($0) }, hidden: { hidden += 1 })
        clock.advance(Delight.stallQuietMs)
        w.arm("ask-name-node")
        clock.advance(1000)
        w.disarm()
        clock.advance(Delight.stallAfterMs)
        XCTAssertEqual(shown, [])
        XCTAssertEqual(hidden, 0)
    }

    // MARK: - The answer's stamp

    func testAVisitorRowSaysWhatItAnswered() {
        let row = UserMessageRecord(id: "u1", time: Date(), text: "⭐⭐⭐⭐⭐",
                                    metadata: HumanTouches.stamp(nodeId: "r", type: "rating-choice-node", text: "5/5"))
        let a = HumanTouches.answerOf(row)
        XCTAssertEqual(a?.nodeId, "r")
        XCTAssertEqual(a?.type, "rating-choice-node")
        XCTAssertEqual(a?.text, "5/5")
        // Saved and read back (a restored chat keeps it).
        let data = try! JSONEncoder().encode(row)
        let back = try! JSONDecoder().decode(UserMessageRecord.self, from: data)
        XCTAssertEqual(HumanTouches.answerOf(back)?.nodeId, "r")
        XCTAssertNil(HumanTouches.answerOf(UserMessageRecord(id: "u2", time: Date(), text: "hi")))
    }

    // MARK: - Auto-open (web index.ts live_chat auto-open)

    func testAutoOpenAfterTheOwnersDelayInSeconds() {
        func plan(_ c: [String: Any]?, started: Bool = false, open: Bool = false, done: Bool = false, closedAt: Double? = nil, now: Double = 0) -> Double? {
            AutoOpen.plan(c, chatStarted: started, isOpen: open, alreadyAutoOpened: done, closedAt: closedAt, now: now)
        }
        XCTAssertEqual(plan(["botAutoOpen": true, "botAutoOpenDelay": 5]), 5000)
        XCTAssertEqual(plan(["botAutoOpen": true]), 0)
        XCTAssertEqual(AutoOpen.delayMs(["botAutoOpenDelay": "2.5"]), 2500)
        XCTAssertEqual(AutoOpen.delayMs(["botAutoOpenDelay": -3]), 0)
        XCTAssertEqual(AutoOpen.delayMs(["botAutoOpenDelay": "soon"]), 0)
        // Off, a chat already started, already open, or already done once.
        XCTAssertNil(plan([:]))
        XCTAssertNil(plan(["botAutoOpen": false]))
        XCTAssertNil(plan(["botAutoOpen": true], started: true))
        XCTAssertNil(plan(["botAutoOpen": true], open: true))
        XCTAssertNil(plan(["botAutoOpen": true], done: true))
        // 2 minutes after the visitor closed it.
        XCTAssertNil(plan(["botAutoOpen": true], closedAt: 1000, now: 1000 + AutoOpen.closedBlocksMs - 1))
        XCTAssertEqual(plan(["botAutoOpen": true], closedAt: 1000, now: 1000 + AutoOpen.closedBlocksMs), 0)
    }

    func testAutoOpenRemembersThisLaunchPerBot() {
        AutoOpen.Memory.reset()
        XCTAssertFalse(AutoOpen.Memory.autoOpened("b1"))
        AutoOpen.Memory.noteAutoOpened("b1")
        XCTAssertTrue(AutoOpen.Memory.autoOpened("b1"))
        XCTAssertFalse(AutoOpen.Memory.autoOpened("b2"))
        AutoOpen.Memory.noteClosed("b2", at: 42)
        XCTAssertEqual(AutoOpen.Memory.closedAt("b2"), 42)
        AutoOpen.Memory.reset()
    }

    // MARK: - Typing preview (web ts/chat/typingPreview.ts)

    func testTrimsAndCapsADraft() {
        XCTAssertEqual(TypingPreview.cleanDraft("  hi  "), "hi")
        XCTAssertEqual(TypingPreview.cleanDraft(String(repeating: "x", count: TypingPreview.draftMax + 10)).count, TypingPreview.draftMax)
        XCTAssertEqual(TypingPreview.cleanDraft(5), "")
    }

    func testSendsAtMostEvery300msTheLatestTextTrailingAndOneEmptyDraftToClear() {
        let clock = TouchClock()
        var sent: [String] = []
        let s = TypingPreview.DraftSender(send: { sent.append($0) }, now: { clock.now },
                                          setTimer: { clock.set($0, $1) }, clearTimer: { clock.clear($0) })
        s.update("h")
        s.update("he")
        s.update("hel")
        XCTAssertEqual(sent, ["h"])
        clock.advance(299)
        XCTAssertEqual(sent, ["h"])
        clock.advance(1)
        XCTAssertEqual(sent, ["h", "hel"])
        s.update("hel ")
        clock.advance(300)
        XCTAssertEqual(sent, ["h", "hel"]) // the same text after trimming: nothing new
        s.clear()
        s.clear()
        XCTAssertEqual(sent, ["h", "hel", ""])
        s.update("   ")
        XCTAssertEqual(sent, ["h", "hel", ""])
    }

    func testNeverPreviewsASecretField() {
        XCTAssertTrue(TypingPreview.isSensitiveField(secure: true))
        XCTAssertTrue(TypingPreview.isSensitiveField(contentType: "oneTimeCode"))
        XCTAssertTrue(TypingPreview.isSensitiveField(contentType: "creditCardNumber"))
        XCTAssertTrue(TypingPreview.isSensitiveField(contentType: "password"))
        XCTAssertFalse(TypingPreview.isSensitiveField(contentType: "emailAddress"))
        XCTAssertFalse(TypingPreview.isSensitiveField())
    }

    func testPreviewOnlyWithAPersonInTheChatUnlessTheOwnerTurnedItOff() {
        XCTAssertTrue(TypingPreview.draftPreviewOn([:], chattingWithPerson: true))
        XCTAssertFalse(TypingPreview.draftPreviewOn(["visitorDraftPreview": false], chattingWithPerson: true))
        XCTAssertFalse(TypingPreview.draftPreviewOn([:], chattingWithPerson: false))
    }
}
