//
//  HomeTests.swift
//  The home screen's decisions (Core/Home/Home.swift): the same cases as the
//  React Native SDK's home.test.ts (the web widget's tests/homeCopy.test.js,
//  homeUtils.test.js, askBox.test.js, trust.test.js, visitorMemory.test.js)
//  and what firstImpression.ts enhanceHome shows, in what order.
//

import XCTest
@testable import Conferbot

final class HomeTests: XCTestCase {

    let NOW: Double = 1_800_000_000_000

    private func art(_ id: String, _ title: String, _ description: String = "", _ content: String = "", _ extra: [String: Any] = [:]) -> [String: Any] {
        ["_id": id, "title": title, "description": description, "content": content].merging(extra) { $1 }
    }

    private var CATS: [[String: Any]] {
        [
            ["_id": "c1", "name": "Billing", "articles": [art("3", "Changing your plan", "Upgrade, downgrade or cancel at any time."), art("4", "Downloading invoices", "Find every invoice in one place.")]],
            ["_id": "c2", "name": "Getting started", "articles": [art("1", "How to build your first bot", "A step by step guide.")]],
        ]
    }
    private var RECENT: [[String: Any]] {
        [art("2", "Embedding the widget on your website", "Copy one script tag into your site."), art("9", "A draft", "", "", ["reviewStatus": "draft"])]
    }
    private let HOME: [String: Any] = ["enableInitialPage": true, "initialPageTitle": "Hi there 👋", "logo": "https://cdn.x/logo.png", "logoText": "Acme"]

    private func with(_ extra: [String: Any]) -> [String: Any] { HOME.merging(extra) { $1 } }

    // MARK: - On or off

    func testOnlyWhenTheOwnerTurnedItOn() {
        XCTAssertTrue(Home.homeOn(["enableInitialPage": true]))
        XCTAssertFalse(Home.homeOn(["enableInitialPage": false]))
        XCTAssertFalse(Home.homeOn([:]))
        XCTAssertFalse(Home.homeOn(nil))
        XCTAssertNil(Home.model(.init(c: ["enableInitialPage": false])))
        XCTAssertNil(Home.model(.init(c: nil)))
    }

    func testAViewThatCannotShowFallsBack() {
        XCTAssertEqual(Home.safeView(["enableInitialPage": true], nil), .home)
        XCTAssertEqual(Home.safeView([:], nil), .chat)
        XCTAssertEqual(Home.safeView([:], .home), .chat)
        XCTAssertEqual(Home.safeView(["enableInitialPage": true], .help), .home)
        XCTAssertEqual(Home.safeView(["enableInitialPage": true, "enableKnowledgeBase": true], .help), .help)
        XCTAssertEqual(Home.safeView([:], .help), .chat)
    }

    // MARK: - Words

    func testEarlyBotsPlaceholderCopyIsShownAsWhatIsTrue() {
        let c: [String: Any] = [
            "initialPageCardSubTitle": "Our usual reply time",
            "initialPageCardTagline": "Later Today",
            "initialPageDescription": "Welcome to the Conferbot\nWe help your business to connect with your customer",
        ]
        XCTAssertEqual(Home.copy(c, name: "Acme Support"), .init(cardTitle: "Acme Support", cardTagline: "Online now", description: Home.Text.description, online: true))
        XCTAssertEqual(Home.copy([:], name: "").cardTitle, "Support")
    }

    func testTheOwnersOwnWordsAreKeptExactly() {
        let c: [String: Any] = ["initialPageCardSubTitle": "Sales team", "initialPageCardTagline": "Mon-Fri, 9-5", "initialPageDescription": "Hi! Questions about orders?"]
        XCTAssertEqual(Home.copy(c, name: "Acme"), .init(cardTitle: "Sales team", cardTagline: "Mon-Fri, 9-5", description: "Hi! Questions about orders?", online: false))
    }

    func testTheSalutationFollowsTheClock() {
        XCTAssertEqual(Home.salutation(9), "Good morning")
        XCTAssertEqual(Home.salutation(14), "Good afternoon")
        XCTAssertEqual(Home.salutation(20), "Good evening")
        XCTAssertEqual(Home.salutation(2), "Hello")
        XCTAssertEqual(Home.salutation(.nan), "Good afternoon")
    }

    func testTheBrandIsTheHeaderLogoAndNameNothingWhenHidden() {
        XCTAssertEqual(Home.brand(["logo": "https://cdn.x/l.png", "logoText": " Acme  Co "]), .init(logo: "https://cdn.x/l.png", name: "Acme Co"))
        XCTAssertEqual(Home.brand(["logo": "https://cdn.x/l.png"], fallbackName: "Bot"), .init(logo: "https://cdn.x/l.png", name: "Bot"))
        XCTAssertNil(Home.brand(["logo": "https://cdn.x/l.png", "hideLogo": true]))
        XCTAssertNil(Home.brand(["logo": "javascript:x"]))
    }

    func testTheCardsFaceTheOwnersTheBotsAvatarItsLogoThenConferbots() {
        XCTAssertEqual(Home.cardAvatar(["initialPageAvatar": "https://a/me.png", "avatar": "https://a/b.png"]), "https://a/me.png")
        XCTAssertEqual(Home.cardAvatar(["avatar": "https://a/b.png"]), "https://a/b.png")
        XCTAssertEqual(Home.cardAvatar(["avatar": "https://a/b.png", "hideAvatar": true, "logo": "https://a/l.png"]), "https://a/l.png")
        XCTAssertTrue(Home.cardAvatar(["logo": "https://x/conferbot-logo.png"]).contains("conferbot-logo-1710782074234"))
    }

    func testLightColoursTakeDarkInk() {
        XCTAssertTrue(Home.isLight(Home.parseColor("#ffffff")))
        XCTAssertFalse(Home.isLight(Home.parseColor("#0808EE")))
        XCTAssertTrue(Home.isLight(Home.parseColor("rgb(250, 240, 200)")))
        XCTAssertNil(Home.parseColor("teal"))
    }

    // MARK: - Surfaces

    func testTheThemesCanvasAndCardsElseTheClassicWidgets() {
        XCTAssertEqual(Home.palette(nil), Home.classicPalette)
        let t = ThemeTokens(bg: "#000000", bg2: "#101014", card: "#18181d", card2: "#222228", field: "#000000", menu: "#000000",
                            ink: "#f4f4f5", text: "#f4f4f5", muted: "#a1a1aa", faint: "#000000", line: "#2a2a31", line2: "#000000")
        XCTAssertEqual(Home.palette(t), .init(page: "#101014", card: "#18181d", soft: "#222228", ink: "#f4f4f5", muted: "#a1a1aa", line: "#2a2a31"))
    }

    // MARK: - The help centre

    func testRecentArticlesShowOnlyWithTheHomeTheHelpCentreAPublishedArticleAndNotHidden() {
        let c: [String: Any] = ["enableInitialPage": true, "enableKnowledgeBase": true]
        XCTAssertTrue(Home.showsRecentArticles(c, RECENT))
        XCTAssertFalse(Home.showsRecentArticles(c.merging(["hideRecentArticles": true]) { $1 }, RECENT))
        XCTAssertFalse(Home.showsRecentArticles(c.merging(["enableKnowledgeBase": false]) { $1 }, RECENT))
        XCTAssertFalse(Home.showsRecentArticles(c, [RECENT[1]]))
    }

    func testTopicsNamedNotEmptyMostArticlesFirst() {
        let cats: [[String: Any]] = [["name": "A", "articles": [1]], ["name": "", "articles": [1, 2]], ["name": "B", "articles": [1, 2]], ["name": "C", "articles": [Int]()]]
        XCTAssertEqual(Home.topCategories(cats).map { $0["name"] as? String }, ["B", "A"])
    }

    // MARK: - Trust

    func testOnlyHttpsImagesOnceEachAtMostMax() {
        let list: [Any] = ["https://cdn.x/a.png", "http://cdn.x/b.png", "javascript:alert(1)", "https://cdn.x/a.png", " https://cdn.x/c.png ", "https://x/\"onerror=1", 42, "https://cdn.x/d.png"]
        XCTAssertEqual(Home.trustImages(list, max: 6), ["https://cdn.x/a.png", "https://cdn.x/c.png", "https://cdn.x/d.png"])
        XCTAssertEqual(Home.trustImages(list, max: 1), ["https://cdn.x/a.png"])
        XCTAssertEqual(Home.trustImages(nil, max: 3), [])
    }

    func testCountsReadAsPeopleSayThem() {
        XCTAssertEqual(Home.compactCount(7), "7")
        XCTAssertEqual(Home.compactCount(999), "999")
        XCTAssertEqual(Home.compactCount(1320), "1.3k")
        XCTAssertEqual(Home.compactCount(12900), "12k")
    }

    func testARatingLineForARealAverageOnly() {
        XCTAssertEqual(Home.ratingLine(["average": 4.83, "count": 120]), .init(average: "4.8", count: "120 reviews", fill: 96, label: "Rated 4.8 out of 5 from 120 reviews"))
        XCTAssertEqual(Home.ratingLine(["average": 4.36, "count": 1520]), .init(average: "4.4", count: "1.5k reviews", fill: 88, label: "Rated 4.4 out of 5 from 1520 reviews"))
        XCTAssertEqual(Home.ratingLine(["average": 5, "count": 1])?.count, "1 review")
        XCTAssertNil(Home.ratingLine(nil))
        XCTAssertNil(Home.ratingLine(["average": 6, "count": 50]))
        XCTAssertNil(Home.ratingLine(["average": 4.5, "count": 0]))
        XCTAssertNil(Home.ratingLine(["average": "x", "count": 30]))
    }

    // MARK: - Visitor memory

    func testAConversationsFirstRealQuestionIsWhatTheyCameFor() {
        var m = Home.withMessage(nil, session: "s1", text: "hi", now: NOW)
        XCTAssertNil(m.topic)
        m = Home.withMessage(m, session: "s1", text: "Do you support Shopify stores?", now: NOW)
        m = Home.withMessage(m, session: "s1", text: "And what about WooCommerce?", now: NOW + 1000)
        XCTAssertEqual(m.topic, "Do you support Shopify stores?")
        m = Home.withMessage(m, session: "s2", text: "Can I cancel my plan anytime?", now: NOW + 5000)
        XCTAssertEqual(m.topic, "Can I cancel my plan anytime?")
        XCTAssertEqual(m.session, "s2")
        XCTAssertEqual(m.at, NOW + 5000)
    }

    func testAFirstNameOnlyAndNeverSomethingThatIsNotAName() {
        let m = Home.withName(nil, name: "jamie lee", now: NOW)!
        XCTAssertEqual(m.name, "Jamie")
        XCTAssertNil(Home.withName(m, name: "x@y.com", now: NOW))
        XCTAssertNil(Home.withName(m, name: "R2D2", now: NOW))
    }

    func testWelcomeBackOnceTheLastChatIsOverNotWhileItWouldBeRestored() {
        let m = Home.Memory(name: "Jamie", topic: "Do you support Shopify stores?", at: NOW)
        XCTAssertNil(Home.welcomeBack(m, now: NOW + Home.liveChatMs - 1))
        let back = Home.welcomeBack(m, now: NOW + Home.liveChatMs)
        XCTAssertEqual(back?.hello, "Welcome back, Jamie")
        XCTAssertEqual(back?.topic, "Do you support Shopify stores?")
        let noName = Home.welcomeBack(Home.Memory(topic: "Do you support Shopify stores?", at: NOW), now: NOW + Home.liveChatMs)
        XCTAssertEqual(noName?.hello, "Welcome back")
        XCTAssertEqual(noName?.topic, "Do you support Shopify stores?")
        XCTAssertNil(Home.welcomeBack(Home.Memory(at: NOW), now: NOW + Home.liveChatMs))
        XCTAssertNil(Home.welcomeBack(nil, now: NOW))
    }

    func testForgottenAfter60DaysBrokenStorageIsNoMemory() {
        let raw = Home.serializeMemory(Home.withMessage(nil, session: "s1", text: "Do you support Shopify stores?", now: NOW))
        XCTAssertEqual(Home.parseMemory(raw, now: NOW)?.topic, "Do you support Shopify stores?")
        XCTAssertNil(Home.parseMemory(raw, now: NOW + 61 * 86_400_000))
        XCTAssertNil(Home.parseMemory("{nope", now: NOW))
        XCTAssertNil(Home.parseMemory(nil, now: NOW))
        // An old memory is started again, not added to.
        XCTAssertNil(Home.withMessage(Home.parseMemory(raw, now: NOW), session: "s9", text: "hello", now: NOW + 61 * 86_400_000).topic)
    }

    func testTheCardOpensTheConversationOnlyWhenItIsTheOneOnTheDevice() {
        let m = Home.withMessage(nil, session: "s1", text: "Do you support Shopify stores?", now: NOW)
        XCTAssertTrue(Home.canResume(m, chatSessionId: "s1"))
        XCTAssertFalse(Home.canResume(m, chatSessionId: "s9"))
        XCTAssertFalse(Home.canResume(m, chatSessionId: nil))
        XCTAssertFalse(Home.canResume(nil, chatSessionId: "s1"))
    }

    // MARK: - "Ask anything"

    private let articles: [WaitArticles.HelpArticle] = [
        .init(id: "1", title: "How to build your first bot", description: "A step by step guide to your first chatbot.", categoryName: "", text: "Open the builder."),
        .init(id: "3", title: "Changing your plan", description: "Upgrade, downgrade or cancel at any time.", categoryName: "Billing", text: ""),
        .init(id: "4", title: "Downloading invoices", description: "Find every invoice in one place.", categoryName: "Billing", text: ""),
    ]

    private func kinds(_ rows: [Home.AskRow]) -> [String] { rows.map { $0.key.hasPrefix("a-") ? "article" : $0.key } }

    func testTheBoxAsksForAQuestionWithAnAgentASearchWithout() {
        XCTAssertEqual(Home.askPlaceholder(hasAgent: true, hasArticles: false), "Ask a question\u{2026}")
        XCTAssertEqual(Home.askPlaceholder(hasAgent: false, hasArticles: true), "Search for help")
    }

    func testItShowsWithAnAgentOrArticlesUnlessTheOwnerTurnedItOff() {
        XCTAssertTrue(Home.askBoxOn([:], hasAgent: true, hasArticles: false))
        XCTAssertTrue(Home.askBoxOn([:], hasAgent: false, hasArticles: true))
        XCTAssertFalse(Home.askBoxOn(["homeAskBox": false], hasAgent: true, hasArticles: true))
        XCTAssertFalse(Home.askBoxOn([:], hasAgent: false, hasArticles: false))
    }

    func testAnAgentAskFirstThenTheArticles() {
        let rows = Home.askRows("how do I change my plan", agentName: "Ava", articles: articles)
        XCTAssertEqual(kinds(rows), ["ask", "label", "article"])
        XCTAssertEqual(rows[0], .ask(query: "how do I change my plan", sub: "Ava answers right away"))
        guard case .article(let id, _, let sub) = rows[2] else { return XCTFail() }
        XCTAssertEqual(id, "3")
        XCTAssertEqual(sub, "Upgrade, downgrade or cancel at any time.")
        XCTAssertEqual(Home.askDefault(rows)?.key, "ask")
    }

    func testAFlowBotTheArticlesElseNoArticlesMatchAndChatWithUs() {
        let rows = Home.askRows("invoice", agentName: nil, articles: articles)
        XCTAssertEqual(kinds(rows), ["label", "article"])
        XCTAssertEqual(Home.askDefault(rows)?.key, "a-4")
        let none = Home.askRows("do you ship to mars", agentName: nil, articles: articles)
        XCTAssertEqual(none, [.none("No articles match \u{201C}do you ship to mars\u{201D}."), .chat(title: "Chat with us", sub: "We'll help you with it")])
        XCTAssertEqual(Home.askDefault(none)?.key, "chat")
        // An agent with nothing found: only the ask.
        XCTAssertEqual(kinds(Home.askRows("do you ship to mars", agentName: "Ava", articles: articles)), ["ask"])
        XCTAssertEqual(Home.askRows("   ", agentName: "Ava", articles: articles), [])
    }

    func testTheServersMatchesInsideArticleTextComeAfterTheLocalOnesForTheQueryAsked() {
        let remote = Home.RemoteHits(query: "pdf vat", hits: [.init(id: "4", snippet: "Each invoice is a PDF with your VAT number."), .init(id: "zz", snippet: "not here")])
        let rows = Home.askRows("PDF VAT", agentName: nil, articles: articles, remote: remote)
        guard rows.count > 1, case .article(let id, _, let sub) = rows[1] else { return XCTFail("\(rows)") }
        XCTAssertEqual(id, "4")
        XCTAssertEqual(sub, "Each invoice is a PDF with your VAT number.")
        XCTAssertFalse(kinds(Home.askRows("other", agentName: nil, articles: articles, remote: remote)).contains("article"))
    }

    func testAsksTheServerWithTheTwoLongestKeyWordsOnlyWhenABodyIsMissing() {
        XCTAssertEqual(Home.remoteQueryFor("where is my vat number", articles: [["_id": "1"]]), "number vat")
        XCTAssertNil(Home.remoteQueryFor("where is my vat number", articles: [["_id": "1", "content": "<p>x</p>"]]))
        XCTAssertNil(Home.remoteQueryFor("how do I", articles: [["_id": "1"]]))
    }

    func testMarksTheWordsThatMatched() {
        XCTAssertEqual(Home.highlightRuns("Changing your plan", ["plan"]), [.init("Changing your "), .init("plan", mark: true)])
        XCTAssertEqual(Home.highlightRuns("Plain", []), [.init("Plain")])
    }

    func testTheHelpCardsOwnSearchUpToFiveElseAskOrChatInstead() {
        guard case .results(let rows)? = Home.helpSearch("billing", articles: articles, hasAgent: false) else { return XCTFail() }
        XCTAssertEqual(rows.map { $0.id }, ["3", "4"])
        XCTAssertEqual(Home.helpSearch("mars", articles: articles, hasAgent: true), .empty(text: "No articles match \u{201C}mars\u{201D}.", action: "Ask us instead", asks: true))
        XCTAssertEqual(Home.helpSearch("mars", articles: articles, hasAgent: false), .empty(text: "No articles match \u{201C}mars\u{201D}.", action: "Chat with us instead", asks: false))
        XCTAssertNil(Home.helpSearch("", articles: articles, hasAgent: false))
    }

    // MARK: - The home screen

    private let agent = Home.Agent(displayName: "Ava", starters: ["Pricing?", "Do you integrate with Shopify?", "Refunds", "Fourth"])

    func testAPlainFlowBotTheHeaderAndTalkToUs() {
        let m = Home.model(.init(c: HOME, botName: "Acme bot", now: NOW, hour: 9))!
        XCTAssertEqual(m.hello, "Good morning")
        XCTAssertEqual(m.brand, .init(logo: "https://cdn.x/logo.png", name: "Acme"))
        XCTAssertEqual(m.title, "Hi there 👋")
        XCTAssertEqual(m.description, Home.Text.description)
        XCTAssertEqual(m.order, [.talk])
        XCTAssertNil(m.ask)
        XCTAssertNil(m.help)
        XCTAssertEqual(m.talk.title, "Acme")
        XCTAssertNil(m.talk.tagline)
        XCTAssertEqual(m.talk.status, "Online \u{00B7} Answers instantly, day or night")
        XCTAssertTrue(m.talk.dot)
        XCTAssertEqual(m.talk.button, "Chat with us")
        XCTAssertEqual(m.talk.starters, [])
        XCTAssertFalse(m.light)
    }

    func testTheOwnersTaglineIsKeptStatusOffTakesOnlineAndTheDot() {
        let c = with(["initialPageCardTagline": "Mon-Fri 9-5", "hideOnlineStatus": true,
                      "replyTime": ["mode": "auto", "handover": true, "state": "online", "bucket": "few_minutes"]])
        let m = Home.model(.init(c: c, now: NOW))!
        XCTAssertEqual(m.talk.tagline, "Mon-Fri 9-5")
        XCTAssertEqual(m.talk.status, "Usually replies in a few minutes")
        XCTAssertFalse(m.talk.dot)
        // Hide: no line at all.
        XCTAssertNil(Home.model(.init(c: c.merging(["replyTime": ["mode": "hide", "handover": true]]) { $1 }, now: NOW))!.talk.status)
    }

    func testTheOwnersButtonTextOrTheStockOne() {
        XCTAssertEqual(Home.model(.init(c: with(["initialPageCardButtonText": "Message us"])))!.talk.button, "Message us")
        XCTAssertEqual(Home.model(.init(c: with(["initialPageCardButtonText": "Chat with us"])))!.talk.button, "Chat with us")
    }

    func testAnAgentTheAskBoxFirstThreeOfItsQuestionsOnTheCard() {
        let m = Home.model(.init(c: HOME, agent: agent, now: NOW))!
        XCTAssertEqual(m.order, [.ask, .talk])
        XCTAssertEqual(m.ask, .init(placeholder: "Ask a question\u{2026}", label: "Ask Ava a question", agentName: "Ava"))
        XCTAssertEqual(m.talk.starters, ["Pricing?", "Do you integrate with Shopify?", "Refunds"])
        XCTAssertEqual(m.talk.title, "Ava")
        XCTAssertNil(Home.model(.init(c: with(["homeAskBox": false]), agent: agent))!.ask)
    }

    func testTheHelpCentreAskBoxOverArticlesRecentListTopicsAndSeeAllDraftsNever() {
        let m = Home.model(.init(c: with(["enableKnowledgeBase": true]), categories: CATS, recentArticles: RECENT))!
        XCTAssertEqual(m.order, [.ask, .talk, .help])
        XCTAssertEqual(m.ask?.placeholder, "Search for help")
        XCTAssertEqual(m.help?.title, "Recent articles")
        XCTAssertEqual(m.help?.seeAll, true)
        XCTAssertEqual(m.help?.search, false)
        XCTAssertEqual(m.help?.recent.map { $0.id }, ["2"])
        XCTAssertEqual(m.help?.topics, [.init(id: "c1", name: "Billing", count: 2), .init(id: "c2", name: "Getting started", count: 1)])
        XCTAssertEqual(m.articles.map { $0.id }, ["3", "4", "1", "2"])
    }

    func testRecentArticlesHiddenTheCardIsTheHelpCentreTheAskBoxOffTheCardSearches() {
        let m = Home.model(.init(c: with(["enableKnowledgeBase": true, "hideRecentArticles": true, "homeAskBox": false]), categories: CATS, recentArticles: RECENT))!
        XCTAssertEqual(m.order, [.talk, .help])
        XCTAssertEqual(m.help?.title, "Help centre")
        XCTAssertEqual(m.help?.recent, [])
        XCTAssertEqual(m.help?.search, true)
    }

    func testAHelpCentreWithNoPublishedArticleCountsAsOff() {
        let m = Home.model(.init(c: with(["enableKnowledgeBase": true]), categories: [], recentArticles: [RECENT[1]]))!
        XCTAssertNil(m.help)
        XCTAssertNil(m.ask)
        XCTAssertEqual(m.articles, [])
    }

    func testWelcomeBackAndPickUpWhereTheyLeftOffForAnAgentBot() {
        let memory = Home.Memory(name: "Jamie", topic: "Do you support Shopify stores?", session: "s1", at: NOW - Home.liveChatMs)
        let m = Home.model(.init(c: HOME, agent: agent, memory: memory, chatSessionId: "s1", now: NOW))!
        XCTAssertEqual(m.hello, "Welcome back, Jamie")
        XCTAssertEqual(m.order, [.ask, .resume, .talk])
        XCTAssertEqual(m.resume, .init(topic: "Do you support Shopify stores?", resumable: true, line: "Continue the conversation"))
        XCTAssertEqual(Home.model(.init(c: HOME, agent: agent, memory: memory, chatSessionId: "s2", now: NOW))!.resume?.line, "Ask it again - we'll answer right away")
        // A flow bot: welcomed back, nothing to pick up.
        let flow = Home.model(.init(c: HOME, memory: memory, now: NOW))!
        XCTAssertEqual(flow.hello, "Welcome back, Jamie")
        XCTAssertNil(flow.resume)
    }

    func testYourRequestsTwoRowsAndSeeAllBelowTalkToUsAboveItWhenAReplyIsNew() {
        func req(_ id: String, _ lastAt: Double, _ from: RequestSummary.From) -> RequestSummary {
            RequestSummary(id: id, title: "Request \(id)", status: .open, lastAt: Requests.iso(lastAt), lastFrom: from, teamName: "Ada")
        }
        let requests = [req("a", NOW - 3000, .you), req("b", NOW - 2000, .you), req("c", NOW - 1000, .you)]
        let m = Home.model(.init(c: HOME, requests: requests, seen: [:], now: NOW))!
        XCTAssertEqual(m.order, [.talk, .requests])
        XCTAssertEqual(m.requests?.rows.map { $0.id }, ["c", "b"])
        XCTAssertEqual(m.requests?.seeAll, "See all (3)")
        XCTAssertEqual(m.requests?.fresh, false)
        let replied = [req("a", NOW - 3000, .team), req("b", NOW - 2000, .you)]
        let n = Home.model(.init(c: HOME, requests: replied, seen: [:], now: NOW))!
        XCTAssertEqual(n.order, [.requests, .talk])
        XCTAssertEqual(n.requests?.rows.first?.id, "a")
        XCTAssertEqual(n.requests?.rows.first?.fresh, true)
        XCTAssertEqual(n.requests?.rows.first?.state, .replied)
        XCTAssertNil(n.requests?.seeAll)
        // Read here since: no longer new.
        XCTAssertEqual(Home.model(.init(c: HOME, requests: replied, seen: ["a": NOW], now: NOW))!.order, [.talk, .requests])
        // Nothing at all for a first-time visitor.
        XCTAssertNil(Home.model(.init(c: HOME, requests: nil))!.requests)
        XCTAssertNil(Home.model(.init(c: HOME, requests: []))!.requests)
    }

    func testTrustFacesAndTheRatingOnTheCardTheLogosWithTheirLineLast() {
        let c = with(["homeTeamPhotos": ["https://cdn.x/1.png", "https://cdn.x/2.png"], "homeRating": ["average": 4.83, "count": 120],
                      "homeTrustLogos": ["https://cdn.x/l.png"], "homeTrustLabel": " Trusted by 2,000+ teams "])
        let m = Home.model(.init(c: c))!
        XCTAssertEqual(m.talk.faces, ["https://cdn.x/1.png", "https://cdn.x/2.png"])
        XCTAssertEqual(m.talk.rating?.average, "4.8")
        XCTAssertEqual(m.trust, .init(label: "Trusted by 2,000+ teams", logos: ["https://cdn.x/l.png"]))
        XCTAssertEqual(m.order, [.talk, .trust])
        // A label with no logo is a claim with no proof: nothing.
        XCTAssertNil(Home.model(.init(c: with(["homeTrustLabel": "Trusted"])))!.trust)
    }

    func testTheBandIsTheLauncherColoursLightOnesTakeDarkInk() {
        XCTAssertEqual(Home.model(.init(c: with(["widgetIconThemeType": "Gradient", "widgetGradientBgOne": "#0808EE", "widgetGradientBgTwo": "#6366F1"])))!.band, ["#0808EE", "#6366F1"])
        let light = Home.model(.init(c: with(["widgetIconBgColor": "#ffffff"])))!
        XCTAssertTrue(light.light)
        XCTAssertEqual(light.accent, "#4F46E5")
    }

    func testWhileTheVisitorTypesTheListIsThePage() {
        XCTAssertEqual(Home.hiddenWhileAsking, [.resume, .requests, .talk, .help])
    }

    func testTheMascotHasItsPlaceEmptyForNow() {
        XCTAssertNil(Home.model(.init(c: HOME))!.mascot)
    }
}
