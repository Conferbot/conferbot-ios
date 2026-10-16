//
//  WaitArticlesTests.swift
//  While you wait for a person (Core/LiveChat/WaitArticles): the articles
//  for the visitor's question, the server's queue-help card and "That
//  solved it", the same cases as the React Native SDK's
//  waitArticles.test.ts (web tests/waitArticles.test.js), on a fake clock.
//

import XCTest
@testable import Conferbot

final class WaitArticlesTests: XCTestCase {

    let cats: [[String: Any]] = [[
        "name": "Billing",
        "articles": [
            ["_id": "1", "title": "Downloading invoices", "description": "Find every invoice in one place."],
            ["_id": "2", "title": "Changing your plan", "description": "Upgrade, downgrade or cancel at any time."],
        ],
    ]]
    let on: [String: Any] = ["enableKnowledgeBase": true]
    let wait = WaitArticles.waitBeforeMs / 1000

    // MARK: - waitArticlesFor (web waitArticles.ts)

    func testTheArticlesThatMayAnswerTheirQuestionAtMostTwo() {
        XCTAssertEqual(WaitArticles.waitArticlesFor(on, "Where can I download my invoices?", cats, []).map(\.id), ["1"])
        XCTAssertEqual(WaitArticles.waitArticlesFor(on, "Where can I download my invoices?", cats, []).first,
                       HelpItem(kind: .article, id: "1", title: "Downloading invoices", description: "Find every invoice in one place."))
        XCTAssertLessThanOrEqual(WaitArticles.waitArticlesFor(on, "billing", cats, []).count, 2)
        XCTAssertEqual(WaitArticles.waitArticlesFor(on, "how do I change my plan", cats, []).map(\.id), ["2"])
    }

    func testNothingWithTheHelpCentreOffNoQuestionOrNothingThatFits() {
        XCTAssertEqual(WaitArticles.waitArticlesFor(["enableKnowledgeBase": false], "download my invoices", cats, []), [])
        XCTAssertEqual(WaitArticles.waitArticlesFor([:], "download my invoices", cats, []), [])
        XCTAssertEqual(WaitArticles.waitArticlesFor(on, "", cats, []), [])
        XCTAssertEqual(WaitArticles.waitArticlesFor(on, "do you ship to mars", cats, []), [])
    }

    func testTheHelpCentreOnceEachCategoriesFirstRecentAfter() {
        let all = WaitArticles.flattenArticles(cats, [
            ["_id": "1", "title": "dup"],
            ["_id": "9", "title": " Recent ", "content": "<p>Hi&amp;there</p>", "category": ["name": "X"]],
            ["title": "no id"],
        ])
        XCTAssertEqual(all.map { [$0.id, $0.title, $0.categoryName] }, [
            ["1", "Downloading invoices", "Billing"],
            ["2", "Changing your plan", "Billing"],
            ["9", "Recent", "X"],
        ])
        XCTAssertEqual(all[2].text, "Hi there")
        XCTAssertEqual(WaitArticles.findArticle("2", cats, [])?["title"] as? String, "Changing your plan")
        XCTAssertEqual(WaitArticles.findArticle("9", cats, [["_id": "9", "title": "R"]])?["title"] as? String, "R")
        XCTAssertNil(WaitArticles.findArticle("nope", cats, []))
        XCTAssertEqual(WaitArticles.keywordsOf("How do I change my plan?"), ["change", "plan"])
        XCTAssertEqual(WaitArticles.answersFor(all, "invoices", max: 4).map(\.id), ["1"])
    }

    // MARK: - The question (web special.ts lastVisitorText)

    func testTheNewestRealQuestionNotHiAndNotAnAskForAPerson() {
        XCTAssertFalse(WaitArticles.isRealQuestion("hi"))
        XCTAssertTrue(WaitArticles.isRealQuestion("Where can I download my invoices?"))
        XCTAssertFalse(WaitArticles.isRealQuestion("me@example.com"))
        let record: [[String: Any]] = [
            ["type": "user-message", "text": "Where can I download my invoices?"],
            ["type": "bot-message", "text": "Let me check that for you right now."],
            ["type": "user-message", "text": "Can I talk to a real person please"],
            ["type": "user-message", "text": "thanks"],
        ]
        XCTAssertEqual(WaitArticles.waitQuestion(record), "Where can I download my invoices?")
        XCTAssertEqual(WaitArticles.waitQuestion([]), "")
        XCTAssertEqual(WaitArticles.waitQuestion(nil), "")
        // The shape when there is no type, and an answer's value.
        XCTAssertEqual(WaitArticles.waitQuestion([["shape": "user-input-response", "value": "How do I reset my password today?"]]),
                       "How do I reset my password today?")
    }

    // MARK: - helpItemsOf (embed-server queueHelp.js payload)

    func testArticlesAndPagesAnIdAndATitleEachAPageOnlyWithAnHttpAddress() {
        let items = WaitArticles.helpItemsOf([
            "chatSessionId": "s", "offer": 1,
            "items": [
                ["kind": "article", "id": "a1", "title": "Invoices", "description": "Find them", "score": 0.8],
                ["kind": "page", "id": "p1", "title": "Pricing", "url": "https://example.com/pricing", "description": ""],
                ["kind": "page", "id": "p2", "title": "Bad", "url": "javascript:alert(1)"],
                ["id": "x", "title": "  "],
                NSNull(),
            ] as [Any],
        ])
        XCTAssertEqual(items, [
            HelpItem(kind: .article, id: "a1", title: "Invoices", description: "Find them"),
            HelpItem(kind: .page, id: "p1", title: "Pricing", url: "https://example.com/pricing"),
            HelpItem(kind: .page, id: "p2", title: "Bad"),
        ])
        XCTAssertEqual(WaitArticles.helpItemsOf(nil), [])
    }

    // MARK: - WaitHelp

    private func setup(question: String = "Where can I download my invoices?", c: [String: Any]? = nil, joined: Bool = false)
        -> (k: FakeClock, help: WaitHelp, cards: () -> [HelpCardState?]) {
        let k = FakeClock()
        var cards: [HelpCardState?] = []
        let cats = self.cats
        let on = self.on
        let help = WaitHelp(.init(
            customizations: { c ?? on },
            question: { question },
            articles: { (cats, []) },
            joined: { joined },
            onChange: { cards.append($0) },
            schedule: k.schedule
        ))
        return (k, help, { cards })
    }

    func testSixSecondsIntoAWaitTheArticlesForTheirQuestionNoThatSolvedIt() {
        let s = setup()
        s.help.startWait()
        s.k.tick(wait - 0.5)
        XCTAssertNil(s.help.card)
        s.k.tick(0.5)
        let card = s.help.card
        XCTAssertEqual(card?.key, 1)
        XCTAssertEqual(card?.solvable, false)
        XCTAssertEqual(card?.settled, false)
        XCTAssertEqual(card?.items.map(\.id), ["1"])
        XCTAssertEqual(card?.items.first?.title, "Downloading invoices")
        XCTAssertNil(s.help.solving())
    }

    func testNothingWhenTheWaitEndsFirstAPersonIsHereNothingFitsOrThereIsNoQuestion() {
        let a = setup()
        a.help.startWait()
        a.k.tick(3)
        a.help.endWait()
        a.k.tick(10)
        XCTAssertNil(a.help.card)
        for s in [setup(joined: true), setup(question: "do you ship to mars"), setup(question: ""), setup(c: [:])] {
            s.help.startWait()
            s.k.tick(wait)
            XCTAssertNil(s.help.card)
        }
    }

    func testTheServerKeepsAQueueItsPickOnlyOursStaysOut() {
        let s = setup()
        s.help.startWait()
        s.help.queueStatus(["status": "waiting", "position": 1])
        s.k.tick(wait)
        XCTAssertNil(s.help.card)
        // A reload: queue-status carries the help it was offered.
        s.help.queueStatus(["status": "waiting", "help": ["items": [["kind": "article", "id": "a1", "title": "Invoices"]], "offer": 1]])
        XCTAssertEqual(s.help.card?.solvable, true)
        XCTAssertEqual(s.help.card?.items.map(\.id), ["a1"])
        s.help.queueStatus(["status": "none", "help": ["items": [["id": "zz", "title": "Other"]]]])
        XCTAssertEqual(s.help.card?.items.first?.id, "a1")
    }

    func testQueueHelpTheCardReplacedOnlyByNewItems() {
        let s = setup()
        s.help.startWait()
        s.help.queueHelp(["items": [["kind": "article", "id": "a1", "title": "Invoices"]], "offer": 1])
        XCTAssertEqual(s.help.card?.key, 1)
        XCTAssertEqual(s.help.card?.solvable, true)
        s.help.queueHelp(["items": [["kind": "article", "id": "a1", "title": "Invoices"]], "offer": 1])
        XCTAssertEqual(s.cards().count, 1)
        s.help.queueHelp(["items": [["kind": "article", "id": "a2", "title": "Plans"]], "offer": 2])
        XCTAssertEqual(s.help.card?.key, 2)
        XCTAssertEqual(s.help.card?.items.map(\.id), ["a2"])
        s.help.queueHelp(["items": [] as [Any]])
        XCTAssertEqual(s.help.card?.key, 2)
    }

    func testThatSolvedItTheOpenedRowElseTheFirstGoesOkLeavesElseTheButtonComesBack() {
        let s = setup()
        s.help.startWait()
        s.help.queueHelp(["items": [["id": "a1", "title": "One"], ["id": "a2", "title": "Two"]]])
        s.help.open("a2")
        XCTAssertEqual(s.help.solving()?.id, "a2")
        XCTAssertEqual(s.help.card?.busy, true)
        // Busy: a second press sends nothing.
        XCTAssertNil(s.help.solving())
        s.help.solved(false)
        XCTAssertEqual(s.help.card?.busy, false)
        XCTAssertEqual(s.help.card?.done, false)
        XCTAssertEqual(s.help.solving()?.id, "a2")
        s.help.solved(true)
        XCTAssertEqual(s.help.card?.busy, false)
        XCTAssertEqual(s.help.card?.done, true)
        // Done: no more server cards for this wait.
        s.help.queueHelp(["items": [["id": "a3", "title": "Three"]]])
        XCTAssertEqual(s.help.card?.items.first?.id, "a1")
        // The wait settling keeps the done line.
        s.help.endWait()
        XCTAssertEqual(s.help.card?.settled, true)
        XCTAssertEqual(s.help.card?.done, true)
    }

    func testTheWaitOverTheCardStaysAsHistoryWithoutTheButtonANewWaitGetsNewCards() {
        let s = setup()
        s.help.startWait()
        s.help.queueHelp(["items": [["id": "a1", "title": "One"]]])
        s.help.endWait()
        XCTAssertEqual(s.help.card?.settled, true)
        XCTAssertEqual(s.help.card?.solvable, false)
        XCTAssertNil(s.help.solving())
        s.help.startWait()
        s.help.queueHelp(["items": [["id": "a1", "title": "One"]]])
        XCTAssertEqual(s.help.card?.key, 2)
        XCTAssertEqual(s.help.card?.settled, false)
        XCTAssertEqual(s.help.card?.solvable, true)
    }

    func testResetNoCardAndOurOwnArticlesAgain() {
        let s = setup()
        s.help.queueHelp(["items": [["id": "a1", "title": "One"]]])
        s.help.reset()
        XCTAssertNil(s.help.card)
        s.help.startWait()
        s.k.tick(wait)
        XCTAssertEqual(s.help.card?.solvable, false)
    }
}
