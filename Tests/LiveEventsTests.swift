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
}
