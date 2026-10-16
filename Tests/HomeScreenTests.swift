//
//  HomeScreenTests.swift
//  The home screen's state (Core/Home/HomeScreen.swift): the React Native
//  SDK's useHomeScreen.test.ts cases - the view, a question asked from the
//  home, what the device remembers, the help centre's data and the server's
//  article search.
//

import XCTest
@testable import Conferbot

@MainActor
final class HomeScreenTests: XCTestCase {

    private final class Fake {
        var c: [String: Any]? = ["enableInitialPage": true]
        var connected = true
        var answers: [Any?] = []
        var asked: [(event: String, data: [String: Any], timeout: Double)] = []
        var sent: [String] = []
        var shown = 0
        var later: [(ms: Double, fn: () -> Void)] = []
        var clock: Double = 1_800_000_000_000
        var session: String? = "s1"
        var agent: Home.Agent?
    }

    private func make(_ f: Fake, _ defaults: UserDefaults) -> HomeScreen {
        let home = HomeScreen(hooks: .init(
            customizations: { f.c },
            botName: { "Acme bot" },
            agent: { f.agent },
            sessionId: { f.session },
            requests: { (nil, [:]) },
            isConnected: { f.connected },
            emitWithAck: { e, d, t, done in
                f.asked.append((e, d, t))
                done(f.answers.isEmpty ? nil : f.answers.removeFirst())
            },
            send: { f.sent.append($0) },
            onHomeShown: { f.shown += 1 },
            defaults: defaults,
            now: { f.clock },
            after: { ms, fn in f.later.append((ms, fn)) }
        ))
        home.load(botId: "bot1")
        return home
    }

    private func defaults() throws -> UserDefaults {
        let d = try XCTUnwrap(UserDefaults(suiteName: "HomeScreenTests"))
        d.removePersistentDomain(forName: "HomeScreenTests")
        return d
    }

    func testStartsOnTheHomeWhenTheOwnerHasOneElseTheChat() throws {
        let f = Fake()
        let home = make(f, try defaults())
        XCTAssertEqual(home.view, .home)
        XCTAssertTrue(home.isOn)
        f.c = [:]
        XCTAssertEqual(home.view, .chat)
        home.showHome()
        XCTAssertEqual(home.view, .chat)
        XCTAssertNil(home.model())
    }

    func testTheChatAsksAQuestion400msAfterGoingThereAndBackHomeReadsTheRequests() throws {
        let f = Fake()
        let home = make(f, try defaults())
        home.showChat("  Do you ship to Canada?  ")
        XCTAssertEqual(home.view, .chat)
        XCTAssertTrue(f.sent.isEmpty)
        XCTAssertEqual(f.later.map { $0.ms }, [400])
        f.later.removeFirst().fn()
        XCTAssertEqual(f.sent, ["Do you ship to Canada?"])
        home.showChat()
        XCTAssertTrue(f.later.isEmpty)
        XCTAssertEqual(f.shown, 0)
        home.showHome()
        XCTAssertEqual(home.view, .home)
        XCTAssertEqual(f.shown, 1)
        // Already home: not again.
        home.showHome()
        XCTAssertEqual(f.shown, 1)
    }

    func testTheHelpCentreOnlyWhileItIsOnOnATopicOrItsList() throws {
        let f = Fake()
        let home = make(f, try defaults())
        home.showHelp(categoryId: "c1")
        XCTAssertEqual(home.view, .home)
        f.c?["enableKnowledgeBase"] = true
        XCTAssertEqual(home.view, .help)
        XCTAssertEqual(home.helpCategoryId, "c1")
        home.showHelp()
        XCTAssertNil(home.helpCategoryId)
    }

    func testWhatTheDeviceRemembersPerBot() throws {
        let d = try defaults()
        let f = Fake()
        f.agent = Home.Agent(displayName: "Ava")
        let home = make(f, d)
        XCTAssertNil(home.memory)
        home.rememberText("hi")
        XCTAssertNil(home.memory?.topic)
        home.rememberText("Do you support Shopify stores?")
        home.rememberName("jamie lee")
        home.rememberName("jamie lee")
        XCTAssertEqual(home.memory?.topic, "Do you support Shopify stores?")
        XCTAssertEqual(home.memory?.name, "Jamie")
        // Read back from UserDefaults, half an hour on: welcome back, pick up.
        f.clock += Home.liveChatMs
        let again = make(f, d)
        XCTAssertEqual(again.memory?.name, "Jamie")
        let m = again.model()!
        XCTAssertEqual(m.hello, "Welcome back, Jamie")
        XCTAssertEqual(m.resume, .init(topic: "Do you support Shopify stores?", resumable: true, line: "Continue the conversation"))
        // Another bot remembers nothing of this one.
        again.load(botId: "bot2")
        XCTAssertNil(again.memory)
        d.removePersistentDomain(forName: "HomeScreenTests")
    }

    func testTheHelpCentresDataFillsTheCards() throws {
        let f = Fake()
        f.c = ["enableInitialPage": true, "enableKnowledgeBase": true]
        let home = make(f, try defaults())
        XCTAssertNil(home.model()?.help)
        home.setKnowledgeBase(["categories": [["_id": "c1", "name": "Billing", "articles": [["_id": "3", "title": "Changing your plan"]]]],
                               "recentArticles": [["_id": "2", "title": "Embedding the widget"]]])
        let m = home.model()!
        XCTAssertEqual(m.order, [.ask, .talk, .help])
        XCTAssertEqual(m.help?.recent.map { $0.id }, ["2"])
        XCTAssertEqual(home.rawArticles.count, 2)
    }

    func testTheServersSearchCachedPerQueryWhenItAnsweredFailuresNot() async throws {
        let f = Fake()
        let home = make(f, try defaults())
        f.answers = [nil]
        let failed = await home.searchArticleText("VAT Number")
        XCTAssertEqual(failed, [])
        XCTAssertEqual(f.asked.first?.event, "search-kb-articles")
        XCTAssertEqual(f.asked.first?.data["query"] as? String, "vat number")
        XCTAssertEqual(f.asked.first?.data["chatbotId"] as? String, "bot1")
        XCTAssertEqual(f.asked.first?.data["limit"] as? Int, 10)
        XCTAssertEqual(f.asked.first?.timeout, 5)
        f.answers = [["success": true, "articles": [["_id": "4", "snippet": "Your VAT number"], ["snippet": "no id"]]]]
        let hits = await home.searchArticleText("vat number")
        XCTAssertEqual(hits, [.init(id: "4", snippet: "Your VAT number")])
        let cached = await home.searchArticleText(" VAT number ")
        XCTAssertEqual(cached, hits)
        XCTAssertEqual(f.asked.count, 2)
        // Too short, or offline: nothing asked.
        let short = await home.searchArticleText("v")
        XCTAssertEqual(short, [])
        f.connected = false
        let offline = await home.searchArticleText("refunds")
        XCTAssertEqual(offline, [])
        XCTAssertEqual(f.asked.count, 2)
    }
}
