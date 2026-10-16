//
//  PostChatRedirectTests.swift
//  Conferbot
//
//  Post-chat redirect (Core/LiveChat/PostChatRedirect.swift), the cases of
//  the web widget's tests/postChatRedirect.test.js and React Native's
//  __tests__/core/postChatRedirect.test.ts and
//  __tests__/context/usePostChatRedirect.test.ts: which URLs are followed,
//  the 10-second line with Cancel, once per conversation (also after a
//  restart), the app's hook first, waiting for the rating, what stops it,
//  and a "Continue to" button when the system cannot open the URL.
//

import XCTest
@testable import Conferbot

private final class MemoryStore: RedirectStore {
    var m: [String: String] = [:]
    func read(_ key: String) -> String? { m[key] }
    func write(_ key: String, _ value: String) { m[key] = value }
}

/// A chat on screen on a hand-moved clock.
private final class Chat {
    let clock = FakeClock()
    let store: MemoryStore?
    var session: String? = "s1"
    var visible = true
    var blocked = false
    var live = false
    var rating = false
    var disabled = false
    var foreground = true
    var url: Any? = "https://www.example.com/thanks"
    var hook: ((String) -> Bool)?
    var refuse = false
    var went: [String] = []
    lazy var r = PostChatRedirectController(hooks: .init(
        redirectUrl: { [unowned self] in self.url },
        sessionId: { [unowned self] in self.session },
        chatVisible: { [unowned self] in self.visible },
        blocked: { [unowned self] in self.blocked },
        live: { [unowned self] in self.live },
        ratingPending: { [unowned self] in self.rating },
        open: { [unowned self] href, done in
            if self.refuse { return done(false) }
            self.went.append(href)
            done(true)
        },
        disabled: { [unowned self] in self.disabled },
        onPostChatRedirect: { [unowned self] in self.hook },
        store: { [unowned self] in self.store },
        appInForeground: { [unowned self] in self.foreground }
    ), schedule: clock.schedule)

    init(store: MemoryStore? = MemoryStore()) { self.store = store }

    var line: RedirectLine? { r.line }

    /// The conversation ended, and the rating's 1.5 s passed.
    func end() {
        r.conversationEnded()
        clock.tick(PostChatRedirect.settleSeconds)
    }
}

final class PostChatRedirectTests: XCTestCase {

    override func setUp() {
        super.setUp()
        _ = I18n.setWidgetLanguage("en")
    }

    func testOnlyPlainHttpAddressesAreFollowed() {
        XCTAssertEqual(PostChatRedirect.safeURL("https://example.com/thanks"), "https://example.com/thanks")
        XCTAssertEqual(PostChatRedirect.safeURL("  http://example.com  "), "http://example.com/")
        XCTAssertEqual(PostChatRedirect.safeURL("HTTPS://Example.com/a?b=1#c"), "https://example.com/a?b=1#c")
        let bad: [Any?] = [
            "javascript:alert(1)",
            " JavaScript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "mailto:a@b.co",
            "//example.com",
            "example.com",
            "ftp://example.com",
            "https://user:pass@example.com",
            "https://",
            "",
            nil,
            42,
            "https://example.com/" + String(repeating: "a", count: 3000),
        ]
        for b in bad { XCTAssertNil(PostChatRedirect.safeURL(b), "\(String(describing: b))") }
    }

    func testWritesTheAddressAsABrowserDoes() {
        XCTAssertEqual(PostChatRedirect.safeURL("https://example.com?x=1"), "https://example.com/?x=1")
        XCTAssertEqual(PostChatRedirect.safeURL("https://example.com:443/a"), "https://example.com/a")
        XCTAssertEqual(PostChatRedirect.safeURL("http://example.com:8080/a"), "http://example.com:8080/a")
        XCTAssertEqual(PostChatRedirect.safeURL("https://[::1]/a"), "https://[::1]/a")
        XCTAssertNil(PostChatRedirect.safeURL("https://user@example.com"))
        XCTAssertNil(PostChatRedirect.safeURL("https://exa mple.com"))
        XCTAssertNil(PostChatRedirect.safeURL("https://example.com:99999"))
        XCTAssertNil(PostChatRedirect.safeURL("https://example.com:abc"))
    }

    func testTheLineNamesTheSiteWithoutWww() {
        XCTAssertEqual(PostChatRedirect.host("https://www.example.com/x"), "example.com")
        XCTAssertEqual(PostChatRedirect.host("https://shop.example.co.uk/"), "shop.example.co.uk")
    }

    func testCountsDownTenSecondsThenOpensTheURL() {
        let c = Chat()
        XCTAssertEqual(c.r.start("s1"), .none, "not ended yet")
        c.end()
        XCTAssertEqual(c.line?.text, I18n.tFor(.en, "redirect.countdown", ["host": "example.com", "n": 10]))
        XCTAssertEqual(c.line?.text, "Taking you to example.com in 10s")
        XCTAssertEqual(c.line?.cancelText, "Cancel")
        XCTAssertEqual(c.line?.cancelLabel, "Cancel going to example.com")
        c.clock.tick(3)
        XCTAssertEqual(c.line?.text, "Taking you to example.com in 7s")
        // Said once, not every second.
        XCTAssertEqual(c.line?.said, "Taking you to example.com in 10s")
        c.clock.tick(6)
        XCTAssertEqual(c.went, [])
        c.clock.tick(1)
        XCTAssertEqual(c.went, ["https://www.example.com/thanks"])
        XCTAssertEqual(c.line?.phase, .going)
        XCTAssertEqual(c.line?.text, "Taking you to example.com…")
        c.clock.tick(5)
        XCTAssertEqual(c.went.count, 1)
    }

    func testCancelStopsItAndTakesTheLineAway() {
        let c = Chat()
        c.end()
        c.r.cancel()
        XCTAssertNil(c.line)
        c.clock.tick(20)
        XCTAssertEqual(c.went, [])
    }

    func testOncePerConversationAlsoAfterARestart() {
        let store = MemoryStore()
        var c = Chat(store: store)
        c.end()
        c.r.cancel()
        // The agent ends it again.
        c.end()
        XCTAssertNil(c.line)
        // The ended chat restored after a restart.
        c = Chat(store: store)
        XCTAssertTrue(PostChatRedirect.alreadyOffered("s1", store: store))
        XCTAssertEqual(store.m[PostChatRedirect.doneKeyPrefix + "s1"], "1")
        c.end()
        XCTAssertNil(c.line)
        // A new conversation gets its own.
        c.session = "s2"
        c.end()
        XCTAssertEqual(c.line?.phase, .counting)
    }

    func testWithoutStorageOncePerConversationWhileTheAppRuns() {
        let c = Chat(store: nil)
        c.end()
        c.r.cancel()
        XCTAssertEqual(c.r.start("s1"), .none)
    }

    func testNothingForABadURLNoURLOrTheAppTurningItOff() {
        let setups: [(Chat) -> Void] = [
            { $0.url = "javascript:alert(1)" },
            { $0.url = "" },
            { $0.url = nil },
            { $0.disabled = true },
        ]
        for setup in setups {
            let c = Chat()
            setup(c)
            c.end()
            XCTAssertNil(c.line)
            XCTAssertTrue(c.store!.m.isEmpty)
        }
    }

    func testTheAppsHookGetsTheURLFirst() {
        var got: [String] = []
        let c = Chat()
        c.hook = { got.append($0); return true }
        c.end()
        XCTAssertEqual(got, ["https://www.example.com/thanks"])
        XCTAssertNil(c.line)
        c.clock.tick(20)
        XCTAssertEqual(c.went, [])
        // Remembered: not offered again.
        c.end()
        XCTAssertEqual(got.count, 1)
        // false: the SDK counts down.
        let d = Chat()
        d.hook = { _ in false }
        d.end()
        XCTAssertEqual(d.line?.phase, .counting)
    }

    func testWaitsForTheRatingToBeSentOrPutAway() {
        let c = Chat()
        c.rating = true
        c.end()
        XCTAssertNil(c.line)
        c.rating = false
        c.r.update()
        c.clock.tick(PostChatRedirect.settleSeconds)
        XCTAssertEqual(c.line?.phase, .counting)
    }

    func testTheRatingComingUpWithinTheSettleWaitsForIt() {
        let c = Chat()
        c.r.conversationEnded()
        c.clock.tick(0.5)
        c.rating = true
        c.r.update()
        c.clock.tick(5)
        XCTAssertNil(c.line)
        c.rating = false
        c.r.update()
        c.clock.tick(PostChatRedirect.settleSeconds)
        XCTAssertEqual(c.line?.phase, .counting)
    }

    func testAClosedChatANewConversationABlockAPersonOrTheBackgroundStopsIt() {
        let changes: [(Chat) -> Void] = [
            { $0.visible = false },
            { $0.session = "s2" },
            { $0.blocked = true },
            { $0.live = true },
            { $0.foreground = false },
        ]
        for change in changes {
            let c = Chat()
            c.end()
            c.clock.tick(2)
            XCTAssertEqual(c.line?.phase, .counting)
            change(c)
            c.clock.tick(20)
            XCTAssertNil(c.line)
            XCTAssertEqual(c.went, [])
        }
        // update() stops it at once (ConferBot calls it on every change).
        let c = Chat()
        c.end()
        c.visible = false
        c.r.update()
        XCTAssertNil(c.line)
    }

    func testAChatThatEndedOffScreenDoesNotCountDownWhenOpenedLater() {
        let c = Chat()
        c.visible = false
        c.end()
        c.visible = true
        c.r.update()
        c.clock.tick(20)
        XCTAssertNil(c.line)
        XCTAssertTrue(c.store!.m.isEmpty)
        // An agent ending it again, on screen: tried again.
        c.end()
        XCTAssertEqual(c.line?.phase, .counting)
    }

    func testARestartTheNextConversationGetsItsOwn() {
        let c = Chat()
        c.end()
        c.r.reset()
        XCTAssertNil(c.line)
        c.session = "s2"
        c.end()
        XCTAssertEqual(c.line?.phase, .counting)
        XCTAssertEqual(c.store!.m.count, 2)
    }

    func testWhenTheSystemCannotOpenItAContinueButton() {
        let c = Chat()
        c.url = "https://example.com/next"
        c.refuse = true
        c.end()
        c.clock.tick(10)
        XCTAssertEqual(c.line?.phase, .continueLink)
        XCTAssertEqual(c.line?.text, "Continue to example.com")
        XCTAssertEqual(c.line?.href, "https://example.com/next")
        c.refuse = false
        var opened = false
        c.r.continueNow { opened = $0 }
        XCTAssertTrue(opened)
        XCTAssertEqual(c.went, ["https://example.com/next"])
        XCTAssertNil(c.line)
    }

    func testTranslatedInEveryWidgetLanguage() {
        let keys = ["redirect.countdown", "redirect.cancel", "redirect.going", "redirect.continue"]
        for lang in [WidgetLanguage.nl, .fr, .de, .es] {
            for key in keys {
                let s = I18n.tFor(lang, key, ["host": "example.com", "n": 10])
                XCTAssertNotEqual(s, I18n.tFor(.en, key, ["host": "example.com", "n": 10]), "\(lang) \(key)")
                XCTAssertTrue(s.contains("example.com"))
            }
            XCTAssertTrue(I18n.tFor(lang, "redirect.countdown", ["host": "x.io", "n": 7]).contains("7"))
        }
    }

    func testConfigDefaults() {
        let config = ConferBotConfig()
        XCTAssertNil(config.onPostChatRedirect)
        XCTAssertFalse(config.disablePostChatRedirect)
        XCTAssertTrue(ConferBotConfig(disablePostChatRedirect: true).disablePostChatRedirect)
    }
}
