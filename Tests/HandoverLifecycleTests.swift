//
//  HandoverLifecycleTests.swift
//  HandoverLifecycle against a fake socket and record: the Connecting line
//  and its outcomes, the waiting signals, the AI escalation's nudge,
//  leaving the queue, and a restored chat picked back up from
//  live-chat-state. The same cases as the React Native SDK's
//  useHandoverLifecycle.test.ts.
//

import XCTest
@testable import Conferbot

final class HandoverLifecycleTests: XCTestCase {

    private var clock: FakeClock!
    private var messages: [any RecordItem] = []
    private var emitted: [(String, [String: Any])] = []
    private var acks: [String: Any] = [:]
    private var joined: [String] = []
    private var live: Bool?
    private var agent: Agent?
    private var engine: NodeFlowEngine?
    private var waitingForPerson = false
    private var stepData: [String: Any]?
    private var lifecycle: HandoverLifecycle!

    override func setUp() {
        super.setUp()
        ChatState.shared.reset()
        clock = FakeClock()
        messages = []
        emitted = []
        acks = [:]
        joined = []
        live = nil
        agent = nil
        engine = nil
        waitingForPerson = false
        stepData = nil
        lifecycle = HandoverLifecycle(hooks: .init(
            sessionId: { "s1" },
            emit: { [unowned self] e, d in self.emitted.append((e, d)) },
            emitWithAck: { [unowned self] e, d, _, done in
                self.emitted.append((e, d))
                done(self.acks[e])
            },
            joinRoom: { [unowned self] id in self.joined.append(id) },
            chatState: { ChatState.shared },
            messages: { [unowned self] in self.messages },
            setMessages: { [unowned self] in self.messages = $0 },
            engine: { [unowned self] in self.engine },
            chatVisible: { true },
            waitingForPerson: { [unowned self] in self.waitingForPerson },
            handoverStepData: { [unowned self] in self.stepData },
            setLive: { [unowned self] in self.live = $0 },
            setAgent: { [unowned self] a, _ in self.agent = a },
            save: {}
        ), schedule: clock.schedule)
    }

    override func tearDown() {
        ChatState.shared.reset()
        super.tearDown()
    }

    /// Let the main-queue hops run.
    private func drain() {
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private var events: [String] { emitted.map { $0.0 } }
    private let escalation: [String: Any] = ["reason": "escalated", "agentDetails": ["_id": "ai-agent-1", "name": "Ava", "isAIAgent": true]]

    func testAnAIEscalatingDrawsOneConnectingLineAnIdlePauseNothing() {
        XCTAssertEqual(lifecycle.onAgentLeft(["reason": "visitor_inactive", "agentDetails": ["name": "Ava", "isAIAgent": true]]), .ignore)
        XCTAssertTrue(messages.isEmpty)
        lifecycle.onAgentLeft(escalation)
        lifecycle.onAgentLeft(escalation)
        XCTAssertEqual(messages.count, 1)
        let line = messages[0] as? AgentLeftMessageRecord
        XCTAssertEqual(line?.isPendingHandover, true)
        XCTAssertEqual(line?.text, "Connecting you with the team\u{2026}")
        XCTAssertEqual(HandoverState.phase(ChatState.shared.getServerRecord()), .connecting)
        lifecycle.onAgentLeft(["agentDetails": ["_id": "u1", "name": "Sam"]])
        XCTAssertEqual((messages[1] as? AgentLeftMessageRecord)?.text, "Sam left the chat")
    }

    func testAPersonJoiningSettlesTheLineSaysHumanJoinedAndNo20sSignal() {
        var got: [String] = []
        lifecycle.signals.on(.waitingForHuman) { _ in got.append("waiting") }
        lifecycle.signals.on(.humanJoined) { got.append("joined:\($0.name ?? "")") }
        lifecycle.onAgentLeft(escalation)
        let data: [String: Any] = ["agentDetails": ["_id": "u1", "name": "Sam"]]
        let plan = lifecycle.onAccepted(data)
        lifecycle.addJoin(AgentDetails(id: "u1", name: "Sam", email: ""), raw: data["agentDetails"] as? [String: Any], plan: plan)
        XCTAssertEqual((messages[0] as? AgentLeftMessageRecord)?.text, "Connected with the team")
        let join = messages[1] as? AgentJoinedMessageRecord
        XCTAssertEqual(join?.afterAI, true)
        XCTAssertEqual(HandoverState.phase(ChatState.shared.getServerRecord()), .joined)
        XCTAssertEqual(ChatState.shared.getServerRecord().last?["agentId"] as? String, "u1")
        clock.tick(300)
        XCTAssertEqual(got, ["joined:Sam"])
        XCTAssertFalse(events.contains(SocketEvents.handoverTimeout))
    }

    func testNobodyIn20sSignalsOnceTheServersHandoverWaitingSettlesUnavailable() {
        var got: [WidgetSignalDetail] = []
        lifecycle.signals.on(.waitingForHuman) { got.append($0) }
        lifecycle.onAgentLeft(escalation)
        clock.tick(20)
        XCTAssertEqual(got, [WidgetSignalDetail(offline: false, reason: "busy", backAt: nil, emailCaptured: false)])
        lifecycle.onHandoverWaiting(["chatSessionId": "s1", "reason": "offline"])
        XCTAssertEqual(got.last?.reason, "offline")
        XCTAssertEqual((messages[0] as? AgentLeftMessageRecord)?.text, "The team couldn't join just now")
        // Another chat's event is not ours.
        lifecycle.onHandoverWaiting(["chatSessionId": "other"])
        XCTAssertEqual(got.count, 2)
    }

    func testChatEndedFirstTheLineSaysSoAndWaitOverEnded() {
        var over: [WidgetSignalDetail] = []
        lifecycle.signals.on(.waitOver) { over.append($0) }
        lifecycle.onAgentLeft(escalation)
        lifecycle.onChatEnded(["chatSessionId": "s1"])
        XCTAssertEqual((messages[0] as? AgentLeftMessageRecord)?.text, "Chat ended before the team joined")
        XCTAssertEqual(over, [WidgetSignalDetail(reason: "ended")])
    }

    func testNobodyAvailableSettlesUnavailableAndTheWaitIsOver() {
        var over: [WidgetSignalDetail] = []
        lifecycle.signals.on(.waitOver) { over.append($0) }
        lifecycle.onAgentLeft(escalation)
        lifecycle.onNoAgentsAvailable()
        XCTAssertEqual((messages[0] as? AgentLeftMessageRecord)?.settled, "unavailable")
        XCTAssertEqual(over, [WidgetSignalDetail(reason: "unavailable")])
    }

    func testAnAIEscalationNudgesTheServerAfterTheMaxWaitAndGrace() {
        stepData = ["maxWaitTime": 1, "assignmentType": "auto", "assignedAgents": ["u1"]]
        lifecycle.onAgentLeft(escalation)
        clock.tick(89)
        XCTAssertFalse(events.contains(SocketEvents.handoverTimeout))
        clock.tick(1)
        let nudge = emitted.first { $0.0 == SocketEvents.handoverTimeout }?.1
        XCTAssertEqual(nudge?["chatSessionId"] as? String, "s1")
        XCTAssertEqual((nudge?["assignmentData"] as? [String: Any])?["assignedAgents"] as? [String], ["u1"])
        // Nothing drawn by the SDK itself.
        XCTAssertEqual(messages.count, 1)
    }

    func testTheServersAnswerStopsTheNudge() {
        lifecycle.onAgentLeft(escalation)
        XCTAssertTrue(lifecycle.nudgePending)
        lifecycle.onHandoverWaiting(["chatSessionId": "s1"])
        XCTAssertFalse(lifecycle.nudgePending)
        clock.tick(600)
        XCTAssertFalse(events.contains(SocketEvents.handoverTimeout))
    }

    func testLeavingTheQueueSendsQueueSelfResolveThenTheLine() {
        acks[SocketEvents.queueSelfResolve] = ["ok": true]
        var over: [WidgetSignalDetail] = []
        lifecycle.signals.on(.waitOver) { over.append($0) }
        var left: Bool?
        lifecycle.leaveQueue { left = $0 }
        drain()
        XCTAssertEqual(left, true)
        XCTAssertEqual(emitted.first?.0, SocketEvents.queueSelfResolve)
        XCTAssertEqual(emitted.first?.1 as NSDictionary?, ["chatSessionId": "s1"])
        XCTAssertEqual((messages.last as? SystemMessageRecord)?.text, "You left the queue")
        XCTAssertEqual(ChatState.shared.getServerRecord().last?["type"] as? String, "queue-self-resolved")
        XCTAssertEqual(over, [WidgetSignalDetail(reason: "cancelled")])
    }

    func testAPersonAcceptedJustBeforeNotWaitingThenLiveTheVisitorStays() {
        acks[SocketEvents.queueSelfResolve] = ["ok": false, "reason": "not_waiting"]
        acks[SocketEvents.liveChatState] = ["status": "live", "agentDetails": ["_id": "u1"]]
        var left: Bool?
        lifecycle.leaveQueue { left = $0 }
        drain()
        XCTAssertEqual(left, false)
        XCTAssertEqual(events, [SocketEvents.queueSelfResolve, SocketEvents.liveChatState])
        XCTAssertTrue(messages.isEmpty)
    }

    func testAPersonAlreadyHasItTheVisitorStays() {
        acks[SocketEvents.queueSelfResolve] = ["ok": false, "reason": "agent_joined"]
        var left: Bool?
        lifecycle.leaveQueue { left = $0 }
        drain()
        XCTAssertEqual(left, false)
        XCTAssertTrue(messages.isEmpty)
    }

    func testRestartALiveChatComesBackLiveWithItsAgent() {
        let lineId = "agent-left-1"
        ChatState.shared.pushServerEntry(["id": "b1", "type": "bot-message"])
        ChatState.shared.pushServerEntry(["id": lineId, "type": "agent-left-chat", "handover": true])
        messages = [AgentLeftMessageRecord(id: lineId, time: Date(), agentDetails: AgentDetails(id: "ai-agent-1", name: "Ava", email: ""), handover: true)]
        acks[SocketEvents.liveChatState] = ["status": "live", "agentDetails": ["_id": "u1", "name": "Sam"]]
        var step: HandoverState.RestoreStep?
        lifecycle.resumeRestored(sessionId: "s1", nodes: [], agentBot: true) { step = $0 }
        drain()
        XCTAssertEqual(step, .live)
        XCTAssertEqual(joined, ["s1"])
        XCTAssertEqual(emitted.first?.0, SocketEvents.liveChatState)
        XCTAssertEqual(live, true)
        XCTAssertEqual(agent?.id, "u1")
        XCTAssertEqual((messages[0] as? AgentLeftMessageRecord)?.settled, "joined")
        let join = messages[1] as? AgentJoinedMessageRecord
        XCTAssertEqual(join?.agentDetails.name, "Sam")
        XCTAssertEqual(join?.afterAI, true)
    }

    func testRestartWhileStillInTheQueueBackOnTheHandoverStepNotAskedAgain() {
        let flow = NodeFlowEngine(state: .shared)
        flow.loadFlow(["nodes": [["id": "h1", "type": "human-handover-node", "data": ["handoverMessage": "<p>One moment</p>"]]], "edges": []], keepingState: true)
        engine = flow
        ChatState.shared.pushServerEntry(["id": "b1", "type": "bot-message"])
        ChatState.shared.currentNodeId = "h1"
        acks[SocketEvents.liveChatState] = ["status": "waiting", "waitEndsAt": Date().timeIntervalSince1970 * 1000 + 60_000]
        var step: HandoverState.RestoreStep?
        lifecycle.resumeRestored(sessionId: "s1", nodes: [["id": "h1", "type": "human-handover-node"]], agentBot: false) { step = $0 }
        drain()
        XCTAssertEqual(step, .wait)
        XCTAssertEqual(flow.currentNodeId, "h1")
        XCTAssertTrue(flow.isAtHandover)
        if case .humanHandover = flow.currentUIState {} else { XCTFail("not waiting on the handover step") }
        XCTAssertFalse(events.contains(SocketEvents.initiateHandover))
        XCTAssertTrue(lifecycle.connecting.pending)
    }

    func testARestoredChatWithNothingLiveIsNotAskedAbout() {
        ChatState.shared.pushServerEntry(["id": "b1", "type": "bot-message"])
        var step: HandoverState.RestoreStep?
        lifecycle.resumeRestored(sessionId: "s1", nodes: [], agentBot: false) { step = $0 }
        drain()
        XCTAssertEqual(step, .start)
        XCTAssertTrue(emitted.isEmpty)
    }

    func testAFlowWaitForAPersonSignalsButNotWhenAnAIAgentTakesItFirst() {
        lifecycle.flowWaitStarted(nodeData: ["assignedAIAgents": ["a1"]])
        XCTAssertFalse(lifecycle.connecting.pending)
        lifecycle.flowWaitStarted(nodeData: [:])
        XCTAssertTrue(lifecycle.connecting.pending)
    }
}
