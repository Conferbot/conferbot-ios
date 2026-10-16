//
//  WaitingExtrasTests.swift
//  While you wait, wired to the handover (Core/LiveChat/WaitingExtras with
//  HandoverLifecycle) on a fake clock and socket: the help card 6s into a
//  wait for a person, the games 2.5s after the waiting signal, the server's
//  queue-help with "That solved it", "play" typed while waiting, and the
//  cards folding away when a person joins. The same cases as the React
//  Native SDK's provider tests for useWaitingExtras.
//

import XCTest
@testable import Conferbot

final class WaitingExtrasTests: XCTestCase {

    private var clock: FakeClock!
    private var messages: [any RecordItem] = []
    private var emitted: [(String, [String: Any])] = []
    private var acks: [String: Any] = [:]
    private var opened: [String] = []
    private var c: [String: Any] = ["enableKnowledgeBase": true]
    private var lifecycle: HandoverLifecycle!
    private var waiting: WaitingExtras!

    private let kb: [String: Any] = ["categories": [[
        "name": "Billing",
        "articles": [["_id": "1", "title": "Downloading invoices", "description": "Find every invoice in one place."]],
    ]]]

    override func setUp() {
        super.setUp()
        ChatState.shared.reset()
        clock = FakeClock()
        messages = [BotMessageRecord(id: "m1", time: Date(), text: "Hi")]
        emitted = []
        acks = [:]
        opened = []
        c = ["enableKnowledgeBase": true]
        lifecycle = HandoverLifecycle(hooks: .init(
            sessionId: { "s1" },
            emit: { [unowned self] e, d in self.emitted.append((e, d)) },
            emitWithAck: { [unowned self] e, d, _, done in
                self.emitted.append((e, d))
                done(self.acks[e])
            },
            joinRoom: { _ in },
            chatState: { ChatState.shared },
            messages: { [unowned self] in self.messages },
            setMessages: { [unowned self] in self.messages = $0 },
            engine: { nil },
            chatVisible: { true },
            waitingForPerson: { false },
            handoverStepData: { nil },
            setLive: { _ in },
            setAgent: { _, _ in },
            save: {}
        ), schedule: clock.schedule)
        waiting = WaitingExtras(hooks: .init(
            sessionId: { "s1" },
            emitWithAck: { [unowned self] e, d, _, done in
                self.emitted.append((e, d))
                done(self.acks[e])
            },
            customizations: { [unowned self] in self.c },
            record: { ChatState.shared.getServerRecord() },
            lastMessageId: { [unowned self] in self.messages.last?.id },
            leftQueueHelped: { [unowned self] in self.lifecycle.leftQueueHelped() },
            openArticle: { [unowned self] id in
                self.opened.append(id)
                return true
            },
            reducedMotion: { false },
            schedule: clock.schedule
        ))
        waiting.listen(to: lifecycle.signals)
        lifecycle.waitHooks = (start: { [unowned self] in self.waiting.waitStarted() }, end: { [unowned self] in self.waiting.waitEnded() })
        waiting.setKnowledgeBase(kb)
        waiting.setDrawing(true)
        ChatState.shared.pushServerEntry(["id": "u1", "type": "user-message", "text": "Where can I download my invoices?"])
    }

    override func tearDown() {
        ChatState.shared.reset()
        super.tearDown()
    }

    private func drain() {
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private let escalation: [String: Any] = ["reason": "escalated", "agentDetails": ["_id": "ai-agent-1", "name": "Ava", "isAIAgent": true]]

    func testAFlowHandoverWithoutAIAgentsTheArticlesFor6sInAfterTheLastMessage() {
        lifecycle.flowWaitStarted(nodeData: [:])
        clock.tick(5.5)
        XCTAssertNil(waiting.helpCard)
        clock.tick(0.5)
        XCTAssertEqual(waiting.helpCard?.items.map(\.id), ["1"])
        XCTAssertEqual(waiting.helpCard?.solvable, false)
        XCTAssertEqual(waiting.helpAnchor, "m1")
        // Never in the conversation itself.
        XCTAssertEqual(messages.map(\.id), ["m1"])
    }

    func testAnAIAgentTakingTheHandoverFirstNoArticles() {
        lifecycle.flowWaitStarted(nodeData: ["assignedAIAgents": ["a1"]])
        clock.tick(30)
        XCTAssertNil(waiting.helpCard)
        XCTAssertNil(waiting.gamesCard)
    }

    func testTheHelpCentreOffNoArticles() {
        c = [:]
        lifecycle.flowWaitStarted(nodeData: [:])
        clock.tick(10)
        XCTAssertNil(waiting.helpCard)
    }

    func testAnAIEscalationTheArticlesAt6sTheGames2500msAfterTheWaitingSignal() {
        lifecycle.onAgentLeft(escalation)
        clock.tick(6)
        XCTAssertNotNil(waiting.helpCard)
        // The connecting wait's own cb:waiting-for-human comes at 20s.
        clock.tick(14)
        XCTAssertNil(waiting.gamesCard)
        clock.tick(2.5)
        XCTAssertEqual(waiting.gamesCard?.state.view, .menu)
        XCTAssertEqual(waiting.gamesCard?.state.title, WaitingGames.defaultOfferText)
        XCTAssertNotNil(waiting.gamesAnchor)
    }

    func testNoChatScreenDrawingTheGamesNoOfferAndPlayIsSentAsWords() {
        waiting.setDrawing(false)
        lifecycle.onHandoverWaiting(["chatSessionId": "s1"])
        clock.tick(10)
        XCTAssertNil(waiting.gamesCard)
        XCTAssertFalse(waiting.interceptPlay("play"))
    }

    func testTheOwnerTurnedTheGamesOffNoOffer() {
        c["waitingGames"] = ["enabled": false]
        lifecycle.onHandoverWaiting(["chatSessionId": "s1"])
        clock.tick(10)
        XCTAssertNil(waiting.gamesCard)
    }

    func testPlayTypedWhileWaitingOpensTheMenuNotOtherwise() {
        XCTAssertFalse(waiting.interceptPlay("play"))
        lifecycle.onHandoverWaiting(["chatSessionId": "s1"])
        XCTAssertFalse(waiting.interceptPlay("How do I play the video?"))
        XCTAssertTrue(waiting.interceptPlay("games"))
        XCTAssertEqual(waiting.gamesCard?.state.title, GamesText.pick)
    }

    func testAPersonJoiningTheUnusedOfferGoesAGameInProgressIsSavedTheHelpCardSettles() {
        lifecycle.onAgentLeft(escalation)
        clock.tick(22.5)
        XCTAssertNotNil(waiting.gamesCard)
        waiting.gamesCard?.open(.ttt)
        waiting.gamesCard?.input(.ttt(0))
        lifecycle.onAccepted(["agentDetails": ["_id": "u7", "name": "Sam"]])
        XCTAssertEqual(waiting.helpCard?.settled, true)
        XCTAssertEqual(waiting.gamesCard?.state.view, .paused)
        XCTAssertEqual(waiting.gamesCard?.state.title, "Sam's here!")
        waiting.gamesCard?.press(.resume)
        XCTAssertEqual(waiting.gamesCard?.state.board?.ttt?.cells.filter { $0 == .o }.count, 1)

        // An unused offer leaves.
        setUp()
        lifecycle.onAgentLeft(escalation)
        clock.tick(22.5)
        XCTAssertNotNil(waiting.gamesCard)
        lifecycle.onAccepted(["agentDetails": ["_id": "u7", "name": "Sam"]])
        XCTAssertNil(waiting.gamesCard)
    }

    func testNotNowGoesAndNoMoreOffersThisSession() {
        lifecycle.onHandoverWaiting(["chatSessionId": "s1"])
        clock.tick(2.5)
        waiting.gamesCard?.press(.notNow)
        XCTAssertNil(waiting.gamesCard)
        lifecycle.onNoAgentsAvailable()
        lifecycle.onHandoverWaiting(["chatSessionId": "s1"])
        clock.tick(10)
        XCTAssertNil(waiting.gamesCard)
    }

    func testQueueHelpThatSolvedItLeavesTheQueueWithTheArticle() {
        lifecycle.onAgentLeft(escalation)
        waiting.onQueueHelp(["chatSessionId": "other", "items": [["id": "zz", "title": "Not mine"]]])
        XCTAssertNil(waiting.helpCard)
        waiting.onQueueHelp(["chatSessionId": "s1", "offer": 1, "items": [
            ["kind": "article", "id": "a1", "title": "Invoices"], ["kind": "page", "id": "p1", "title": "Pricing", "url": "https://example.com/p"],
        ]])
        XCTAssertEqual(waiting.helpCard?.solvable, true)
        // Ours does not come on top of the server's.
        clock.tick(6)
        XCTAssertEqual(waiting.helpCard?.items.map(\.id), ["a1", "p1"])
        waiting.openHelpItem(HelpItem(kind: .page, id: "p1", title: "Pricing"))
        XCTAssertEqual(opened, [])
        waiting.openHelpItem(HelpItem(kind: .article, id: "a1", title: "Invoices"))
        XCTAssertEqual(opened, ["a1"])
        acks[SocketEvents.queueSelfResolve] = ["ok": true]
        var result: Bool?
        waiting.solveWait { result = $0 }
        drain()
        XCTAssertEqual(result, true)
        let sent = emitted.last { $0.0 == SocketEvents.queueSelfResolve }?.1
        XCTAssertEqual(sent?["chatSessionId"] as? String, "s1")
        XCTAssertEqual(sent?["articleId"] as? String, "a1")
        XCTAssertEqual(waiting.helpCard?.done, true)
        XCTAssertEqual(waiting.helpCard?.settled, true)
        XCTAssertEqual((messages.last as? SystemMessageRecord)?.text, "You left the queue. Glad that helped.")
        let entry = ChatState.shared.getServerRecord().last
        XCTAssertEqual(entry?["type"] as? String, "queue-self-resolved")
        XCTAssertEqual(entry?["text"] as? String, "Resolved while waiting")
        // The room's queue-left for the same leave draws nothing more.
        let count = messages.count
        lifecycle.onQueueLeft(["chatSessionId": "s1", "reason": "self_service"])
        waiting.onQueueLeft(["chatSessionId": "s1", "reason": "self_service"])
        XCTAssertEqual(messages.count, count)
    }

    func testThatSolvedItRefusedTheButtonComesBack() {
        lifecycle.onAgentLeft(escalation)
        waiting.onQueueHelp(["items": [["id": "a1", "title": "Invoices"]]])
        acks[SocketEvents.queueSelfResolve] = ["ok": false, "reason": "not_waiting"]
        var result: Bool?
        waiting.solveWait { result = $0 }
        drain()
        XCTAssertEqual(result, false)
        XCTAssertEqual(waiting.helpCard?.busy, false)
        XCTAssertEqual(waiting.helpCard?.done, false)
        XCTAssertFalse(messages.contains { ($0 as? SystemMessageRecord)?.text == WaitArticles.Text.leftHelped })
    }

    func testAWaitingQueueStatusMeansTheServerPicksItsHelpIncluded() {
        lifecycle.flowWaitStarted(nodeData: [:])
        waiting.onQueueStatus(["chatSessionId": "s1", "status": "waiting", "position": 2])
        clock.tick(6)
        XCTAssertNil(waiting.helpCard)
        waiting.onQueueStatus(["status": "waiting", "help": ["items": [["id": "a9", "title": "Nine"]]]])
        XCTAssertEqual(waiting.helpCard?.items.map(\.id), ["a9"])
    }

    func testTheChatEndingSettlesTheCardAndANewChatClearsIt() {
        lifecycle.flowWaitStarted(nodeData: [:])
        clock.tick(6)
        lifecycle.onChatEnded(["chatSessionId": "s1"])
        XCTAssertEqual(waiting.helpCard?.settled, true)
        waiting.reset()
        XCTAssertNil(waiting.helpCard)
        XCTAssertNil(waiting.helpAnchor)
        XCTAssertNil(waiting.gamesCard)
    }
}
