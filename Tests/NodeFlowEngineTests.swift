//
//  NodeFlowEngineTests.swift
//  Conferbot
//
//  NodeFlowEngine against the web widget's engine rules (the flow-node
//  spec's "engine" section; FlowFixtureTests runs all 156 fixtures): start
//  at the first welcome, the first edge whatever its handle, exact ports,
//  the end on a missing edge, unknown steps passed - and the iOS defects
//  that broke real bots (#52, #27).
//

import XCTest
@testable import Conferbot

@MainActor
final class NodeFlowEngineTests: XCTestCase {

    private var state: ChatState!
    private var clock: FlowVirtualClock!
    private var engine: NodeFlowEngine!
    private var trace: [FlowTraceEvent] = []

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
        trace = []
        config.onTrace = { [weak self] in self?.trace.append($0) }
        engine = NodeFlowEngine(state: state, registry: registry, config: config)
    }

    private func node(_ id: String, _ type: String, _ data: [String: Any] = [:]) -> [String: Any] {
        ["id": id, "type": type, "data": data]
    }

    private func edge(_ source: String, _ target: String, _ handle: String? = "source") -> [String: Any] {
        var e: [String: Any] = ["id": "e-\(source)-\(target)", "source": source, "target": target]
        if let h = handle { e["sourceHandle"] = h }
        return e
    }

    private func run(_ nodes: [[String: Any]], _ edges: [[String: Any]]) async {
        engine.loadFlow(["nodes": nodes, "edges": edges])
        Task { @MainActor in await self.engine.start() }
        await clock.settle()
    }

    private func answer(_ response: Any) async {
        Task { @MainActor in await self.engine.submitResponse(response) }
        await clock.settle()
    }

    private var entered: [String] {
        trace.compactMap { if case .enter(let n, _, _) = $0 { return n } else { return nil } }
    }

    // MARK: - Loading

    func testLoadsNodesAndEdgesFromEveryShape() {
        engine.loadFlow(["nodes": [node("a", "message-node")], "edges": []])
        XCTAssertEqual(engine.nodeCount, 1)
        engine.loadFlow(["flow": ["nodes": [node("a", "message-node"), node("b", "message-node")], "edges": [edge("a", "b")]]])
        XCTAssertEqual(engine.nodeCount, 2)
        XCTAssertEqual(engine.edgeCount, 1)
        engine.loadFlow(["nodes": [node("a", "message-node")], "connections": [edge("a", "a")]])
        XCTAssertEqual(engine.edgeCount, 1)
        XCTAssertEqual(engine.allNodeIds, ["a"])
        XCTAssertTrue(engine.isFlowLoaded)
    }

    // MARK: - Engine rules

    func testStartsAtTheFirstWelcomeAndMessagesMoveOnByThemselves() async {
        await run([node("m0", "message-node", ["text": "<p>not first</p>"]),
                   node("w", "welcome-node", ["text": "<p>Hi</p>"]),
                   node("m", "message-node", ["text": "<p>Bye</p>"])],
                  [edge("w", "m")])
        XCTAssertEqual(entered, ["w", "m"])
        XCTAssertTrue(engine.isEnded)
        XCTAssertTrue(engine.isFlowComplete)
    }

    func testTheFirstEdgeIsTakenWhateverItsHandle() async {
        await run([node("w", "welcome-node", ["text": "Hi"]), node("m", "message-node", ["text": "x"])], [edge("w", "m", "source-7")])
        XCTAssertEqual(entered, ["w", "m"])
    }

    func testACalendarStepWaitsInsteadOfEndingTheChat() async {
        // #52: any type containing "end" ended the chat
        await run([node("w", "welcome-node", ["text": "Hi"]), node("cal", "calendar-node", ["calendarPrompt": "<p>When?</p>"])], [edge("w", "cal")])
        XCTAssertFalse(engine.isEnded)
        XCTAssertTrue(engine.isWaitingForInput)
        XCTAssertEqual(engine.currentNodeId, "cal")
    }

    func testAChoiceLeavesByItsExactHandleAndAMissingOneEndsTheChat() async {
        let choices = node("c", "n-choices-node", ["choicePrompt": "Pick", "choices": [["id": "1", "choiceText": "One"], ["id": "2", "choiceText": "Two"]]])
        await run([node("w", "welcome-node", ["text": "Hi"]), choices, node("one", "message-node", ["text": "one"])],
                  [edge("w", "c"), edge("c", "one", "source-1")])
        XCTAssertEqual(engine.currentUIState.map { if case .buttons(let b, _) = $0 { return b.map { $0.label } } else { return [] } }, ["One", "Two"])
        await answer(["buttonId": "2"])
        XCTAssertEqual(entered, ["w", "c"])
        XCTAssertTrue(engine.isEnded, "no edge from source-2: the chat ends, never another edge")
        XCTAssertNil(engine.getNextNodeId(from: "c", port: "source-2"))
        XCTAssertEqual(engine.getNextNodeId(from: "c", port: "source-1"), "one")
        XCTAssertEqual(engine.getNextNodeId(from: "c"), "one")
    }

    func testAnUnknownStepIsPassedAlongItsFirstEdge() async {
        await run([node("w", "welcome-node", ["text": "Hi"]), node("x", "made-up-node"), node("m", "message-node", ["text": "m"])],
                  [edge("w", "x"), edge("x", "m")])
        XCTAssertEqual(entered, ["w", "x", "m"])
        XCTAssertTrue(trace.contains { if case .unsupported("x", _) = $0 { return true } else { return false } })
    }

    func testAJumpToAMissingStepEndsTheChat() async {
        await run([node("w", "welcome-node", ["text": "Hi"]), node("j", "jump-to-node", ["nodeId": "nowhere"])], [edge("w", "j")])
        XCTAssertTrue(engine.isEnded)
    }

    // MARK: - Answers

    func testAnAnswerIsSavedUnderItsAnswerVariableAndFillsLaterText() async {
        await run([node("w", "welcome-node", ["text": "Hi"]),
                   node("q", "ask-name-node", ["questionText": "Name?", "answerVariable": "name", "nameGreetResponse": ""]),
                   node("m", "message-node", ["text": "<p>Thanks {name}</p>"])],
                  [edge("w", "q"), edge("q", "m")])
        await answer("Jane Doe")
        XCTAssertEqual(state.answerValue("name") as? String, "Jane Doe")
        XCTAssertEqual(state.getAnswerVariablesList().first?["key"] as? String, "name")
        XCTAssertTrue(state.getTranscript().contains { ($0["message"] as? String) == "Thanks Jane Doe" })
        XCTAssertTrue(engine.isEnded)
    }

    func testARefusedEmailKeepsTheStepWaiting() async {
        await run([node("w", "welcome-node", ["text": "Hi"]), node("q", "ask-email-node", ["questionText": "Email?", "answerVariable": "email"])],
                  [edge("w", "q")])
        await answer("not-an-email")
        XCTAssertEqual(engine.validationError?.nodeId, "q")
        XCTAssertTrue(engine.isWaitingForInput)
        XCTAssertEqual(engine.currentNodeId, "q")
        XCTAssertTrue(trace.contains { if case .error("q", _) = $0 { return true } else { return false } })
    }

    func testButtonAndChoiceTapsGoThroughTheStep() async {
        let yesNo = node("y", "yes-or-no-choice-node", ["questionText": "Ok?", "answerVariable": "ok"])
        await run([node("w", "welcome-node", ["text": "Hi"]), yesNo, node("yes", "message-node", ["text": "yes"])],
                  [edge("w", "y"), edge("y", "yes", "source-1")])
        Task { await self.engine.handleButtonClick(buttonId: "1", forNodeId: "y") }
        await clock.settle()
        XCTAssertEqual(state.answerValue("ok") as? String, "Yes")
        XCTAssertEqual(entered.last, "yes")
    }

    func testAnswersForAnotherStepAreIgnored() async {
        await run([node("w", "welcome-node", ["text": "Hi"]), node("q", "ask-custom-question-node", ["questionText": "?", "answerVariable": "a"])],
                  [edge("w", "q")])
        Task { await self.engine.handleUserInput("x", forNodeId: "other") }
        await clock.settle()
        XCTAssertTrue(engine.isWaitingForInput)
        XCTAssertNil(state.answerValue("a") as? String)
    }

    func testAMissingStartNodeSaysSo() async {
        engine.loadFlow(["nodes": [], "edges": []])
        await engine.start()
        XCTAssertNotNil(engine.errorMessage)
    }

    func testRestartStartsOverWithFreshAnswers() async {
        await run([node("w", "welcome-node", ["text": "Hi"]), node("q", "ask-custom-question-node", ["questionText": "?", "answerVariable": "a"])],
                  [edge("w", "q")])
        await answer("one")
        engine.loadFlow(["nodes": [node("w", "welcome-node", ["text": "Hi"])], "edges": []])
        XCTAssertFalse(engine.isFlowComplete)
        XCTAssertNil(engine.currentNodeId)
        XCTAssertFalse(state.hasAnswerVariable("a"))
    }
}
