//
//  NodeHandlerRegistryTests.swift
//  Conferbot
//
//  The registry and the built-in steps: every node type the builder saves
//  (the flow-node fixtures' types) has a handler or is run by the engine,
//  and the handlers read the fields the builder saves (#28, #45).
//

import XCTest
@testable import Conferbot

@MainActor
final class NodeHandlerRegistryTests: XCTestCase {

    private var registry: NodeHandlerRegistry!
    private var state: ChatState!

    override func setUp() {
        super.setUp()
        registry = NodeHandlerRegistry()
        state = ChatState()
        state.setSession(sessionId: "s1", botId: "b1")
    }

    final class MockNodeHandler: BaseNodeHandler {
        let type: String
        var handled = false
        init(_ type: String) {
            self.type = type
            super.init()
        }
        override var nodeType: String { type }
        override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
            handled = true
            return .next
        }
    }

    // MARK: - Registry

    func testRegisterLookUpAndUnregister() {
        let h = MockNodeHandler("mock-node")
        registry.register(h)
        XCTAssertTrue(registry.hasHandler(for: "mock-node"))
        XCTAssertEqual(registry.count, 1)
        XCTAssertTrue(registry.getHandler(for: "mock-node") as AnyObject === h)
        registry.register([MockNodeHandler("a-node"), MockNodeHandler("b-node")])
        XCTAssertEqual(Set(registry.registeredTypes), ["mock-node", "a-node", "b-node"])
        registry.unregister("mock-node")
        XCTAssertFalse(registry.hasHandler(for: "mock-node"))
        registry.clear()
        XCTAssertEqual(registry.count, 0)
    }

    func testTheLastRegistrationWins() {
        let first = MockNodeHandler("x-node")
        let second = MockNodeHandler("x-node")
        registry.register(first)
        registry.register(second)
        XCTAssertTrue(registry.getHandler(for: "x-node") as AnyObject === second)
    }

    func testProcessRunsTheHandlerAndSkipsAnUnknownType() async {
        let h = MockNodeHandler("mock-node")
        registry.register(h)
        _ = await registry.process(node: ["id": "1", "type": "mock-node"], state: state)
        XCTAssertTrue(h.handled)
        if case .proceed = await registry.process(node: ["id": "2", "type": "nope"], state: state) {} else { XCTFail("an unknown type is skipped") }
        if case .error = await registry.process(node: ["id": "3"], state: state) {} else { XCTFail("a node without a type is an error") }
    }

    func testResetAndTheSharedRegistryHaveEveryBuiltInStep() {
        registry.reset()
        XCTAssertEqual(registry.count, 80)
        XCTAssertEqual(NodeHandlerRegistry.shared.count >= 80, true)
    }

    /// Every node type the fixtures cover runs: a handler, or the engine's loops and sub-flows.
    func testEveryNodeTypeTheBuilderSavesRuns() {
        registry.registerAllHandlers()
        var types = Set<String>()
        for c in FlowFixtureTests.cases {
            let fx = FlowFixtureTests.load(JS.text(c["file"]))
            for t in JS.array(fx["covers"]) { types.insert(JS.str(t)) }
        }
        // "unknown": the cases with a type no SDK runs (passed along its first edge)
        types.remove("unknown")
        XCTAssertGreaterThan(types.count, 70)
        for t in types.sorted() {
            XCTAssertTrue(registry.hasHandler(for: t) || FlowControl.types.contains(t), "no handler for \(t)")
        }
    }

    // MARK: - The fields the builder saves (#28)

    private func run(_ handler: NodeHandler, _ data: [String: Any], id: String = "n1") async -> NodeResult {
        await handler.handle(node: ["id": id, "type": handler.nodeType, "data": data], state: state)
    }

    func testNChoicesReadsChoicesAndLeavesByTheChoiceId() async {
        let h = NChoicesNodeHandler()
        let data: [String: Any] = ["choicePrompt": "<p>Pick</p>", "choices": [["id": "a1", "choiceText": "<p>One</p>"], ["id": "b2", "choiceText": ""]], "answerVariable": "pick"]
        guard case .displayUI(.buttons(let buttons, _)) = await run(h, data) else { return XCTFail("buttons") }
        XCTAssertEqual(buttons.map { $0.label }, ["One"])
        state.registerAnswerVariable(nodeId: "n1", key: "pick")
        let r = await h.handleResponse(["buttonId": "a1"], node: ["id": "n1", "type": h.nodeType, "data": data], state: state)
        guard case .port("source-a1", nil)? = r else { return XCTFail("port source-a1") }
        XCTAssertEqual(state.answerValue("pick") as? String, "One")
    }

    func testTwoChoicesReadChoiceTextAndPortsByNumber() async {
        let h = TwoChoicesNodeHandler()
        let data: [String: Any] = ["choicePrompt": "?", "choiceText1": "<p>Left</p>", "choiceText2": "<p>Right</p>"]
        guard case .displayUI(.buttons(let buttons, _)) = await run(h, data) else { return XCTFail("buttons") }
        XCTAssertEqual(buttons.map { $0.id }, ["1", "2"])
        XCTAssertEqual(buttons.map { $0.label }, ["Left", "Right"])
        let r = await h.handleResponse(["buttonId": "2"], node: ["id": "n1", "type": h.nodeType, "data": data], state: state)
        guard case .port("source-2", nil)? = r else { return XCTFail("port source-2") }
    }

    func testHtmlReadsTheHtmlFieldSanitised() async {
        let r = await run(HTMLNodeHandler(), ["html": "<b>Hi</b><script>x()</script>"])
        guard case .displayUI(.embed(let html)) = r else { return XCTFail("embed") }
        XCTAssertEqual(html, "<b>Hi</b>")
    }

    func testConditionReadsTheFlatFieldsAndPortsSource0Or1() async {
        state.saveVariableByName("plan", value: "pro")
        let r = await run(ConditionNodeHandler(), ["leftValue": "plan", "operator": "equals", "rightValue": "pro", "customRightValue": true])
        guard case .port("source-0", nil) = r else { return XCTFail("true branch") }
        let r2 = await run(ConditionNodeHandler(), ["leftValue": "plan", "operator": "!=", "rightValue": "pro", "customRightValue": true])
        guard case .port("source-1", nil) = r2 else { return XCTFail("false branch") }
    }

    func testBooleanLogicIsNotAlwaysFalse() async {
        state.saveVariableByName("a", value: "yes")
        let r = await run(BooleanLogicNodeHandler(), ["leftValue": "a", "operator": "AND", "rightValue": "true"])
        guard case .port("source-0", nil) = r else { return XCTFail("true") }
    }

    func testRandomFlowPicksByBranchIdNotPosition() async {
        let h = RandomFlowNodeHandler()
        let r = await h.handle(node: ["id": "r", "type": h.nodeType, "data": ["branches": [["id": "x", "weight": 1]]]], state: state)
        // no ctx edges stand-alone: no wired branch, the flow ends there
        guard case .port(FlowLogic.noPath, nil) = r else { return XCTFail("no path") }
        XCTAssertEqual(FlowLogic.pickRandomHandle([["id": "x", "weight": 0], ["id": "y", "weight": 5]], ["source-x", "source-y"], 0.1), "source-y")
    }

    func testDelayIsNotCappedAtAMinute() async {
        guard case .delayedProceed(let s, nil) = await run(DelayNodeHandler(), ["delay": 120]) else { return XCTFail("delay") }
        XCTAssertEqual(s, 120)
    }
}
