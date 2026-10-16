//
//  LiveEventsTests.swift
//  Back in the queue, a transfer, the same end again, a blocked visitor and
//  the closed chat (#40, #41): LiveEvents as the React Native SDK's
//  liveEvents.test.ts, then HandoverLifecycle applying them to the record,
//  the messages and the flow.
//

import XCTest
@testable import Conferbot

final class LiveEventsTests: XCTestCase {

    // MARK: - Pure

    func testRequeuedSaysWhichTeamOrAnotherAgent() {
        XCTAssertEqual(LiveEvents.requeuedText(teamName: nil), "Connecting you to another agent...")
        XCTAssertEqual(LiveEvents.requeuedText(teamName: "  Sales <b> "), "Connecting you to Sales b...")
        XCTAssertEqual(LiveEvents.requeuedText(teamName: 42), "Connecting you to another agent...")
        XCTAssertEqual(LiveEvents.requeuedText(teamName: String(repeating: "x", count: 80)), "Connecting you to \(String(repeating: "x", count: 60))...")
    }

    func testRequeuedIsItsOwnRecordEntry() {
        let e = LiveEvents.requeuedEntry(["teamName": "Billing"])
        XCTAssertEqual(e["type"] as? String, "live-chat-requeued")
        XCTAssertEqual(e["text"] as? String, "Connecting you to Billing...")
        XCTAssertTrue((e["id"] as? String)?.hasPrefix("requeued-") == true)
        XCTAssertEqual(e["_id"] as? String, e["id"] as? String)
        XCTAssertNotEqual(LiveEvents.eventId("x"), LiveEvents.eventId("x"))
    }

    func testATransferIsKeptAsTheServerWroteIt() {
        let e = LiveEvents.transferEntry(["entry": ["id": "transfer-1", "text": "Transferred from Maya to Sales", "time": "t", "kind": "team"]])
        XCTAssertEqual(e?["id"] as? String, "transfer-1")
        XCTAssertEqual(e?["type"] as? String, "live-chat-transfer")
        XCTAssertEqual(e?["shape"] as? String, "live-chat-transfer")
        XCTAssertEqual(e?["time"] as? String, "t")
        XCTAssertEqual(e?["kind"] as? String, "team")
        XCTAssertEqual((LiveEvents.transferEntry(["entry": ["id": "x", "text": String(repeating: "y", count: 300)]])?["text"] as? String)?.count, 200)
        XCTAssertNil(LiveEvents.transferEntry(["entry": ["id": 1, "text": "x"]]))
        XCTAssertNil(LiveEvents.transferEntry([:]))
    }

    func testTheSameEndAgainOnlyWhileNothingLiveCameAfter() {
        XCTAssertFalse(LiveEvents.endedSinceLastLive([]))
        XCTAssertTrue(LiveEvents.endedSinceLastLive([["type": "agent-message"], ["type": "agent-chat-ended"]]))
        XCTAssertTrue(LiveEvents.endedSinceLastLive([["type": "agent-chat-ended"], ["type": "bot-message"]]))
        XCTAssertFalse(LiveEvents.endedSinceLastLive([["type": "agent-chat-ended"], ["type": "agent-joined-message"]]))
        XCTAssertFalse(LiveEvents.endedSinceLastLive([["type": "agent-chat-ended"], ["shape": "user-live-message"]]))
    }

    func testTheHandshakeRefusalAndTheEventAreRead() {
        XCTAssertTrue(LiveEvents.isBlockedError([["message": "visitor_blocked"]]))
        XCTAssertTrue(LiveEvents.isBlockedError(["visitor_blocked"]))
        XCTAssertFalse(LiveEvents.isBlockedError([["message": "timeout"]]))
        XCTAssertEqual(LiveEvents.blockedText(["message": "This conversation has been closed."]), LiveEvents.closedText)
        XCTAssertEqual(LiveEvents.blockedText(["message": "  Closed by the team "]), "Closed by the team")
        XCTAssertEqual(LiveEvents.blockedText(nil), LiveEvents.closedText)
    }

    func testABlockedVisitorGetsTheClosedLineNoInputAndNoNewChat() {
        XCTAssertEqual(LiveEvents.closedState([], blocked: LiveEvents.closedText, stepWaiting: true, live: true),
                       .init(kind: .blocked, text: LiveEvents.closedText, newChat: false, inputOff: true))
    }

    func testAnEndedChatOffersANewOneOnceNothingIsGoingOn() {
        let ended: [[String: Any]] = [["type": "agent-message"], ["type": "agent-chat-ended"]]
        XCTAssertEqual(LiveEvents.closedState(ended, blocked: nil, stepWaiting: false, live: false),
                       .init(kind: .ended, text: "Chat ended", newChat: true, inputOff: true))
        XCTAssertNil(LiveEvents.closedState(ended, blocked: nil, stepWaiting: true, live: false))
        XCTAssertNil(LiveEvents.closedState(ended, blocked: nil, stepWaiting: false, live: true))
        XCTAssertNil(LiveEvents.closedState([["type": "agent-message"]], blocked: nil, stepWaiting: false, live: false))
    }

    func testTheHandshakeCarriesTheVisitorSoABlockedOneIsRefused() {
        let socket = SocketClient(apiKey: "k", botId: "b1", socketURL: "http://localhost:8001")
        XCTAssertNil(socket.handshakeParams["visitorId"])
        socket.visitorId = "v_123"
        XCTAssertEqual(socket.handshakeParams["visitorId"] as? String, "v_123")
        XCTAssertEqual(socket.handshakeParams["botId"] as? String, "b1")
    }

    func testTheReplyTimeoutNoticeIsAnOnScreenLine() {
        let n = AgentBotParser.replyTimeoutNotice(now: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(n.text, "That took too long. Try again, or ask for a human.")
        XCTAssertEqual(n.id, "reply-timeout-5000")
        XCTAssertEqual(AgentBotParser.awaitReplySeconds, 45)
    }

    // MARK: - Applied (HandoverLifecycle)

    private var messages: [any RecordItem] = []
    private var emitted: [(String, [String: Any])] = []
    private var acks: [String: Any] = [:]
    private var live: Bool?
    private var agent: Agent?
    private var agentCleared = false
    private var engine: NodeFlowEngine?

    private func lifecycle() -> HandoverLifecycle {
        HandoverLifecycle(hooks: .init(
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
            engine: { [unowned self] in self.engine },
            chatVisible: { true },
            waitingForPerson: { false },
            handoverStepData: { nil },
            setLive: { [unowned self] in self.live = $0 },
            setAgent: { [unowned self] a, _ in
                self.agent = a
                if a == nil { self.agentCleared = true }
            },
            save: {}
        ), schedule: FakeClock().schedule)
    }

    override func setUp() {
        super.setUp()
        ChatState.shared.reset()
        messages = []
        emitted = []
        acks = [:]
        live = nil
        agent = nil
        agentCleared = false
        engine = nil
    }

    override func tearDown() {
        ChatState.shared.reset()
        super.tearDown()
    }

    private func drain() {
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private var clock = FlowVirtualClock()

    private func handoverFlow(_ data: [String: Any] = [:]) -> NodeFlowEngine {
        let registry = NodeHandlerRegistry()
        registry.registerAllHandlers()
        var config = NodeFlowEngine.Config()
        clock = FlowVirtualClock()
        config.clock = clock
        config.transport = FlowFakeTransport(server: [:])
        config.socket = FlowFakeSocket(server: [:], clock: clock)
        let flow = NodeFlowEngine(state: .shared, registry: registry, config: config)
        flow.loadFlow(["nodes": [["id": "h1", "type": "human-handover-node", "data": data], ["id": "m1", "type": "message-node", "data": ["text": "Bye"]]],
                       "edges": [["id": "e1", "source": "h1", "target": "m1", "sourceHandle": "source"]]], keepingState: true)
        return flow
    }

    func testRequeuedDrawsItsLineClearsTheAgentAndTheFlowWaitsAgain() {
        let flow = handoverFlow()
        engine = flow
        let handover = lifecycle()
        let waited = expectation(description: "back on the step")
        Task { @MainActor in
            flow.standAt("h1")
            handover.onRequeued(["chatSessionId": "s1", "teamName": "Sales"])
            // Another chat's event is not ours.
            handover.onRequeued(["chatSessionId": "other"])
            waited.fulfill()
        }
        wait(for: [waited], timeout: 2)
        drain()
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual((messages[0] as? SystemMessageRecord)?.text, "Connecting you to Sales...")
        XCTAssertEqual(ChatState.shared.getServerRecord().last?["type"] as? String, "live-chat-requeued")
        XCTAssertTrue(agentCleared)
        XCTAssertEqual(live, false)
        if case .humanHandover = flow.currentUIState {} else { XCTFail("the flow is not waiting on its handover step") }
        XCTAssertTrue(handover.connecting.pending)
    }

    func testATransferIsKeptInTheRecordNotDrawn() {
        let handover = lifecycle()
        handover.onTransferred(["chatSessionId": "s1", "entry": ["id": "transfer-1", "text": "Transferred to Sales"]])
        handover.onTransferred(["chatSessionId": "s1", "entry": ["text": "no id"]])
        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(ChatState.shared.getServerRecord().count, 1)
        XCTAssertEqual(ChatState.shared.getServerRecord().first?["type"] as? String, "live-chat-transfer")
    }

    func testABlockSettlesTheConnectingLineAndStopsTheFlowAndTheWait() {
        let flow = handoverFlow()
        engine = flow
        let handover = lifecycle()
        handover.onAgentLeft(["reason": "escalated", "agentDetails": ["_id": "ai-agent-1", "name": "Ava", "isAIAgent": true]])
        XCTAssertTrue(handover.connecting.pending)
        let stood = expectation(description: "on the step")
        Task { @MainActor in
            flow.waitAt("h1", uiState: .humanHandover(message: nil))
            handover.onBlocked()
            stood.fulfill()
        }
        wait(for: [stood], timeout: 2)
        drain()
        XCTAssertFalse(handover.connecting.pending)
        XCTAssertEqual((messages[0] as? AgentLeftMessageRecord)?.settled, "ended")
        XCTAssertNil(flow.currentUIState)
        XCTAssertEqual(live, false)
    }

    @MainActor
    func testARestoredLiveChatStandsOnItsHandoverStepSoTheEndCarriesTheFlowOn() async {
        let flow = handoverFlow()
        engine = flow
        ChatState.shared.pushServerEntry(["id": "b1", "type": "bot-message"])
        ChatState.shared.pushServerEntry(["id": "j1", "type": "agent-joined-message", "agentId": "u1", "name": "Sam"])
        ChatState.shared.currentNodeId = "h1"
        acks[SocketEvents.liveChatState] = ["status": "live", "agentDetails": ["_id": "u1", "name": "Sam"]]
        var step: HandoverState.RestoreStep?
        let handover = lifecycle()
        handover.resumeRestored(sessionId: "s1", nodes: [["id": "h1", "type": "human-handover-node"]], agentBot: false) { step = $0 }
        // The main queue's hops, from the main actor.
        for _ in 0..<10 where step == nil || flow.currentNodeId == nil { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(step, .live)
        XCTAssertEqual(flow.currentNodeId, "h1")
        XCTAssertTrue(flow.isAtHandover)
        XCTAssertNil(flow.currentUIState)

        Task { @MainActor in await flow.handoverEnded() }
        await clock.settle()
        XCTAssertEqual(flow.currentNodeId, "m1")
        XCTAssertTrue(ChatState.shared.getTranscript().contains { $0["message"] as? String == "Bye" })
    }

    // MARK: - The handover step when the chat ends (#66, #59)

    private let survey: [String: Any] = [
        "enablePostChatSurveyQuestions": true,
        "postChatSurveyQuestions": [
            ["id": "q1", "questionText": "<p>How did we do?</p>", "answerVariable": "feedback"],
            ["id": "q2", "questionText": "Your email?", "answerVariable": "email", "incorrectEmailResponse": "That is not an email"],
        ],
    ]

    @MainActor
    func testTheEndAsksTheStepsPostChatSurveyThenTheFlowCarriesOn() async {
        let flow = handoverFlow(survey)
        flow.standAt("h1")
        Task { @MainActor in await flow.handoverEnded() }
        await clock.settle()
        XCTAssertEqual(flow.currentNodeId, "h1")
        guard case .textInput(_, _, let nodeId)? = flow.currentUIState else { return XCTFail("no survey question") }
        XCTAssertEqual(nodeId, "h1")
        XCTAssertTrue(ChatState.shared.getServerRecord().contains { $0["type"] as? String == "post-chat-survey-question" && $0["id"] as? String == "q1" })

        Task { @MainActor in await flow.submitResponse("Great, thanks") }
        await clock.settle()
        XCTAssertTrue(ChatState.shared.getServerRecord().contains {
            $0["type"] as? String == "post-chat-survey-question-response" && $0["text"] as? String == "Great, thanks" && $0["questionId"] as? String == "q1"
        })
        // A refused email keeps the question.
        Task { @MainActor in await flow.submitResponse("nope") }
        await clock.settle()
        XCTAssertEqual(flow.currentNodeId, "h1")
        Task { @MainActor in await flow.submitResponse("sam@example.com") }
        await clock.settle()
        XCTAssertEqual(flow.currentNodeId, "m1")
        XCTAssertEqual(ChatState.shared.userMetadata["email"] as? String, "sam@example.com")
    }

    @MainActor
    func testAStepWithoutASurveyMovesOnAtTheEnd() async {
        let flow = handoverFlow()
        flow.standAt("h1")
        Task { @MainActor in await flow.handoverEnded() }
        await clock.settle()
        XCTAssertEqual(flow.currentNodeId, "m1")
    }

    @MainActor
    func testTheHandoverSurveyRatingGoesAsSubmitChatRating() async {
        let socket = FlowFakeSocket(server: [:], clock: clock)
        let registry = NodeHandlerRegistry()
        registry.registerAllHandlers()
        var config = NodeFlowEngine.Config()
        config.clock = clock
        config.transport = FlowFakeTransport(server: [:])
        config.socket = socket
        ChatState.shared.setSession(sessionId: "s1", botId: "b1")
        let flow = NodeFlowEngine(state: .shared, registry: registry, config: config)
        flow.loadFlow(["nodes": [["id": "h1", "type": "human-handover-node", "data": ["surveyConfig": ["ratingStyle": "numbers"]]]], "edges": []], keepingState: true)
        flow.standAt("h1")
        Task { @MainActor in await flow.submitResponse(["action": "surveySubmit", "surveyResponse": ["rating": 9, "feedback": "quick"]]) }
        await clock.settle()
        XCTAssertTrue(socket.emits.contains(SocketEvents.submitChatRating))
        // End chat leaves the queue (no visitor end-chat on the server).
        flow.standAt("h1")
        Task { @MainActor in await flow.submitResponse(["action": "endChat"]) }
        await clock.settle()
        XCTAssertTrue(socket.emits.contains(SocketEvents.queueSelfResolve))
        XCTAssertFalse(socket.emits.contains(SocketEvents.endChat))
    }

    func testTheSurveyRatingIsTheWebsShape() {
        let nps = LiveChat.surveyRatingPayload(chatSessionId: "s1", style: "numbers", response: ["rating": 9, "feedback": " quick "])
        XCTAssertEqual(nps?["npsScore"] as? Int, 9)
        XCTAssertEqual(nps?["feedback"] as? String, "quick")
        XCTAssertEqual(nps?["source"] as? String, "post_chat_survey")
        XCTAssertEqual(LiveChat.surveyRatingPayload(chatSessionId: "s1", style: "thumbs", response: ["rating": 1])?["thumbsUp"] as? Bool, true)
        XCTAssertEqual(LiveChat.surveyRatingPayload(chatSessionId: "s1", style: nil, response: ["rating": 4])?["csatScore"] as? Int, 4)
        XCTAssertNil(LiveChat.surveyRatingPayload(chatSessionId: "s1", style: "stars", response: ["comment": "x"]))
        XCTAssertNil(LiveChat.surveyRatingPayload(chatSessionId: "", style: "stars", response: ["rating": 4]))
    }

    // MARK: - The AI's inactivity close (#32)

    private let escalated: [String: Any] = ["reason": "escalated", "agentDetails": ["_id": "ai-agent-1", "name": "Ava", "isAIAgent": true]]

    func testAnInactivityPauseSaysChatPausedOnceAndTheChatStaysLive() {
        let handover = lifecycle()
        live = true
        let plan = handover.onInactiveClose(["chatSessionId": "s1", "action": "pause"], agentBot: false)
        XCTAssertEqual(plan, .init(paused: true, continueFlow: false))
        // Another chat's close is not ours.
        XCTAssertNil(handover.onInactiveClose(["chatSessionId": "other"], agentBot: false))
        XCTAssertEqual(messages.count, 1)
        let line = messages[0] as? SystemMessageRecord
        XCTAssertEqual(line?.line.text, "Chat paused")
        XCTAssertEqual(line?.line.note, "Send a message to pick up where you left off")
        // Recorded once, with `paused`, without the screen's own fields.
        let closes = ChatState.shared.getServerRecord().filter { $0["type"] as? String == "ai-agent-inactive-close" }
        XCTAssertEqual(closes.count, 1)
        XCTAssertEqual(closes[0]["paused"] as? Bool, true)
        XCTAssertEqual(closes[0]["action"] as? String, "pause")
        XCTAssertNil(closes[0]["shape"])
        XCTAssertNil(closes[0]["_id"])
        XCTAssertEqual(closes[0]["id"] as? String, line?.id)
        // Live mode stays on (the next message goes the live way) and the composer stays on.
        XCTAssertEqual(live, true)
        XCTAssertFalse(agentCleared)
        XCTAssertNil(LiveEvents.closedState(ChatState.shared.getServerRecord(), blocked: nil, stepWaiting: false, live: false))
    }

    func testAnAgentBotIsOnlyPausedEvenWithContinueFlow() {
        let handover = lifecycle()
        live = true
        XCTAssertEqual(handover.onInactiveClose(["action": "continue_flow"], agentBot: true), .init(paused: true, continueFlow: false))
        XCTAssertEqual((messages[0] as? SystemMessageRecord)?.line.text, "Chat paused")
        XCTAssertEqual(live, true)
    }

    func testAPendingConnectingLineSettlesAsEndedAndTheNudgeStops() {
        let handover = lifecycle()
        handover.onAgentLeft(escalated)
        XCTAssertTrue(handover.nudgePending)
        handover.onInactiveClose(["chatSessionId": "s1"], agentBot: false)
        XCTAssertFalse(handover.nudgePending)
        XCTAssertFalse(handover.connecting.pending)
        XCTAssertEqual((messages[0] as? AgentLeftMessageRecord)?.settled, "ended")
        XCTAssertEqual((messages[1] as? SystemMessageRecord)?.line.text, "Chat paused")
    }

    @MainActor
    func testContinueFlowEndsTheChatAndTheFlowGoesOnFromItsNextEdgeWithNoSurvey() async {
        let flow = handoverFlow(survey)
        engine = flow
        flow.standAt("h1")
        live = true
        let handover = lifecycle()
        XCTAssertEqual(handover.onInactiveClose(["chatSessionId": "s1", "action": "continue_flow"], agentBot: false), .init(paused: false, continueFlow: true))
        XCTAssertEqual((messages[0] as? SystemMessageRecord)?.line.text, "Chat ended")
        XCTAssertNil((messages[0] as? SystemMessageRecord)?.line.note)
        XCTAssertEqual(live, false)
        XCTAssertTrue(agentCleared)
        await clock.settle()
        for _ in 0..<10 where flow.currentNodeId != "m1" { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(flow.currentNodeId, "m1")
        XCTAssertTrue(ChatState.shared.getTranscript().contains { $0["message"] as? String == "Bye" })
        XCTAssertFalse(ChatState.shared.getServerRecord().contains { $0["type"] as? String == "post-chat-survey-question" })
    }
}

// MARK: - Paused or ended for inactivity (#32)

final class InactiveCloseTests: XCTestCase {

    override func tearDown() {
        _ = I18n.setWidgetLanguage("en", languages: [])
        super.tearDown()
    }

    func testPausedUnlessContinueFlowOnAFlowBot() {
        XCTAssertEqual(LiveEvents.inactiveClosePlan(["action": "continue_flow"], agentBotChat: false), .init(paused: false, continueFlow: true))
        XCTAssertEqual(LiveEvents.inactiveClosePlan(["action": "pause"], agentBotChat: false), .init(paused: true, continueFlow: false))
        XCTAssertEqual(LiveEvents.inactiveClosePlan(nil, agentBotChat: false), .init(paused: true, continueFlow: false))
        // An agent bot has no flow to go on with: always only paused.
        XCTAssertEqual(LiveEvents.inactiveClosePlan(["action": "continue_flow"], agentBotChat: true), .init(paused: true, continueFlow: false))
    }

    func testItsEntryHasItsOwnIdTheActionAndPaused() {
        let a = LiveEvents.inactiveCloseEntry(["action": "continue_flow"], agentBotChat: false)
        let b = LiveEvents.inactiveCloseEntry(nil, agentBotChat: false)
        XCTAssertEqual(a["type"] as? String, "ai-agent-inactive-close")
        XCTAssertEqual(a["action"] as? String, "continue_flow")
        XCTAssertEqual(a["paused"] as? Bool, false)
        XCTAssertEqual(b["paused"] as? Bool, true)
        XCTAssertNil(b["action"])
        XCTAssertTrue((a["id"] as? String)?.hasPrefix("ai-agent-inactive-close-") == true)
        XCTAssertNotEqual(a["id"] as? String, b["id"] as? String)
    }

    func testTheLinePausedWithItsNoteOrEndedInTheVisitorsLanguage() {
        let paused = LiveEvents.inactiveCloseLine(paused: true)
        XCTAssertEqual(paused.text, "Chat paused")
        XCTAssertEqual(paused.note, "Send a message to pick up where you left off")
        XCTAssertEqual(LiveEvents.inactiveCloseLine(paused: false).text, "Chat ended")
        XCTAssertNil(LiveEvents.inactiveCloseLine(paused: false).note)
        // An older entry without `paused` is a pause.
        XCTAssertTrue(LiveEvents.inactiveCloseLine(paused: nil).paused)
        _ = I18n.setWidgetLanguage("de", languages: ["de"])
        XCTAssertEqual(LiveEvents.inactiveCloseLine(paused: true).text, I18n.tFor(.de, "system.chatPaused"))
        XCTAssertNotEqual(I18n.tFor(.de, "system.chatPaused"), "Chat paused")
    }

    func testTheSavedLineDrawsTheSameAfterARestart() throws {
        let defaults = UserDefaults(suiteName: "InactiveCloseTests")!
        defaults.removePersistentDomain(forName: "InactiveCloseTests")
        let storage = UserDefaultsSessionStorage(userDefaults: defaults)
        let paused = SystemMessageRecord(id: "p1", time: Date(), text: "Chat paused", kind: LiveEvents.inactiveCloseType, paused: true)
        let ended = SystemMessageRecord(id: "e1", time: Date(), text: "Chat ended", kind: LiveEvents.inactiveCloseType, paused: false)
        let plain = SystemMessageRecord(id: "s1", time: Date(), text: "Chat has ended")
        try storage.saveMessages(messages: [paused, ended, plain], sessionId: "s")
        let back = storage.loadMessages(sessionId: "s").compactMap { $0 as? SystemMessageRecord }
        XCTAssertEqual(back.count, 3)
        XCTAssertEqual(back[0].line.text, "Chat paused")
        XCTAssertEqual(back[0].line.note, "Send a message to pick up where you left off")
        XCTAssertEqual(back[1].line.text, "Chat ended")
        XCTAssertNil(back[1].line.note)
        XCTAssertEqual(back[2].line.text, "Chat has ended")
        XCTAssertNil(back[2].kind)
        defaults.removePersistentDomain(forName: "InactiveCloseTests")
    }
}
