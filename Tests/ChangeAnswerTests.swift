//
//  ChangeAnswerTests.swift
//  Conferbot
//
//  "Edit" on an answer (RN __tests__/core/changeAnswer.test.ts; web
//  index.ts _noteQuestionPoint / _rewindToQuestion, ts/chat/delight/index.ts):
//  the engine keeps a point for each question, says what ran since, and goes
//  back to it - the conversation's state as it was, the question asked again.
//

import XCTest
import Combine
@testable import Conferbot

@MainActor
final class ChangeAnswerTests: XCTestCase {

    private var state: ChatState!
    private var clock: FlowVirtualClock!
    private var engine: NodeFlowEngine!

    override func setUp() {
        super.setUp()
        state = ChatState()
        state.setSession(sessionId: "s1", botId: "b1")
        clock = FlowVirtualClock()
        let registry = NodeHandlerRegistry()
        registry.registerAllHandlers()
        var config = NodeFlowEngine.Config()
        config.clock = clock
        config.transport = FlowFakeTransport(server: [:])
        config.visitorTimeZone = "UTC"
        config.typingDelay = 0
        engine = NodeFlowEngine(state: state, registry: registry, config: config)
    }

    private func node(_ id: String, _ type: String, _ data: [String: Any] = [:]) -> [String: Any] {
        ["id": id, "type": type, "data": data]
    }

    private func edge(_ source: String, _ target: String) -> [String: Any] {
        ["id": "e-\(source)-\(target)", "source": source, "target": target, "sourceHandle": "source"]
    }

    private func start() async {
        engine.loadFlow(["nodes": [
            node("w", "welcome-node", ["text": "<p>Hi</p>", "disableImage": true]),
            node("q1", "ask-name-node", ["questionText": "<p>Your name?</p>", "answerVariable": "name"]),
            node("m", "message-node", ["text": "<p>Thanks {name}</p>"]),
            node("q2", "ask-email-node", ["questionText": "<p>Your email?</p>", "answerVariable": "email"]),
            node("q3", "ask-file-node", ["questionText": "<p>A file?</p>"]),
        ], "edges": [edge("w", "q1"), edge("q1", "m"), edge("m", "q2"), edge("q2", "q3")]])
        Task { @MainActor in await self.engine.start() }
        await clock.settle()
    }

    private func answer(_ response: Any) async {
        Task { @MainActor in await self.engine.submitResponse(response) }
        await clock.settle()
    }

    private func rewind(_ id: Int) async -> Bool {
        var ok = false
        Task { @MainActor in ok = await self.engine.rewindTo(id) }
        await clock.settle()
        return ok
    }

    func testKeepsAPointForEachQuestionBeforeItIsDrawn() async {
        await start()
        let points = engine.questionPoints
        XCTAssertEqual(points.map { $0.nodeId }, ["q1"])
        // Taken before the question's own record entry.
        XCTAssertEqual(JS.text(state.getServerRecord()[points[0].recordLen]["id"]), "q1")
        XCTAssertTrue(state.getTranscript().contains { ($0["nodeId"] as? String) == "q1" })
    }

    func testSaysWhatRanSinceAMessageIsSafeToUndoAFileStepIsNot() async {
        await start()
        await answer("Jamie")
        let p = engine.questionPoints
        XCTAssertEqual(p.map { $0.nodeId }, ["q1", "q2"])
        XCTAssertEqual(engine.typesSince(p[0]), ["message-node", "ask-email-node"])
        XCTAssertTrue(Delight.canChangeAnswer(p[0].type, Array(engine.typesSince(p[0]).dropLast())))
        await answer("jamie@example.com")
        // The file step acts on the world: the email can no longer be changed.
        XCTAssertEqual(engine.typesSince(engine.questionPoints[1]), ["ask-file-node"])
        XCTAssertFalse(Delight.canChangeAnswer("ask-email-node", ["ask-file-node"]))
    }

    func testGoesBackTheStateAsItWasTheQuestionAskedAgainANewAnswerTaken() async {
        await start()
        await answer("Jamie")
        XCTAssertEqual(state.answerValue("name") as? String, "Jamie")
        XCTAssertEqual(engine.currentNodeId, "q2")
        let transcriptBefore = state.getTranscript().count

        let p1 = engine.questionPoints[0]
        let ok = await rewind(p1.id)
        XCTAssertTrue(ok)
        XCTAssertEqual(engine.currentNodeId, "q1")
        XCTAssertTrue(engine.isWaitingForInput)
        XCTAssertTrue(state.answerValue("name") == nil || state.answerValue("name") is NSNull)
        // The answer and everything after it are gone; the question is asked again.
        XCTAssertLessThan(state.getTranscript().count, transcriptBefore)
        XCTAssertFalse(state.getTranscript().contains { ($0["type"] as? String) == "user" })
        // Points after it are gone; the question has a new one.
        XCTAssertEqual(engine.questionPoints.map { $0.nodeId }, ["q1"])
        XCTAssertNotEqual(engine.questionPoints[0].id, p1.id)

        await answer("Sam")
        XCTAssertEqual(state.answerValue("name") as? String, "Sam")
        XCTAssertEqual(engine.currentNodeId, "q2")
    }

    func testRefusesAPointThatIsGoneAndOnceTheChatIsOver() async {
        await start()
        let gone = await rewind(999)
        XCTAssertFalse(gone)
        state.markConversationComplete(reason: "done")
        let over = await rewind(engine.questionPoints[0].id)
        XCTAssertFalse(over)
    }

    func testCountsAPersonInTheConversationSinceAsNotSafe() async {
        await start()
        let p1 = engine.questionPoints[0]
        state.appendRecord(["_id": "a1", "type": "agent-message", "time": Flow.iso(Date()), "text": "Hi"])
        XCTAssertTrue(engine.typesSince(p1).contains("agent"))
        XCTAssertFalse(Delight.canChangeAnswer("ask-name-node", engine.typesSince(p1)))
    }

    func testPutsASavedStateBackInPlace() {
        let s = ChatState()
        s.setSession(sessionId: "s1", botId: "b1")
        s.saveVariableByName("name", value: "Jamie", nodeId: "q1")
        let snap = s.snapshot()
        s.saveVariableByName("name", value: "Sam", nodeId: "q1")
        s.addUserMessage("Sam", nodeId: "q1")
        var heard = 0
        let sub = s.$transcript.dropFirst().sink { _ in heard += 1 }
        s.restore(snap)
        XCTAssertEqual(s.answerValue("name") as? String, "Jamie")
        XCTAssertEqual(s.getTranscript().count, 0)
        XCTAssertEqual(s.sessionId, "s1")
        XCTAssertGreaterThan(heard, 0)
        sub.cancel()
    }

    // MARK: - Where "Edit" cuts the conversation

    func testCutsTheQuestionsOwnRowsAboveTheAnswer() {
        XCTAssertEqual(Delight.cutIndex(["w", "q1", "q1", nil], answerIndex: 3, nodeId: "q1"), 1)
        XCTAssertEqual(Delight.cutIndex(["w", "m", nil], answerIndex: 2, nodeId: "q1"), 2)
    }
}
