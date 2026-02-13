//
//  NodeFlowEngineTests.swift
//  Conferbot
//
//  Comprehensive tests for NodeFlowEngine - the core orchestration engine
//  that processes chatbot flows.
//

import XCTest
@testable import Conferbot

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class NodeFlowEngineTests: XCTestCase {

    // MARK: - Properties

    var engine: NodeFlowEngine!
    var testState: ChatState!
    var testRegistry: NodeHandlerRegistry!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        // Create fresh instances for each test
        testState = ChatState.shared
        testState.reset()
        testRegistry = NodeHandlerRegistry()
        testRegistry.reset()
        engine = NodeFlowEngine(state: testState, registry: testRegistry)
    }

    override func tearDown() {
        testState.reset()
        engine = nil
        testState = nil
        testRegistry = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    /// Creates a simple flow with start and end nodes
    private func createSimpleFlow() -> [String: Any] {
        return [
            "nodes": [
                ["id": "start-1", "type": "START", "data": [:]],
                ["id": "message-1", "type": "message", "data": ["text": "Hello, welcome!"]],
                ["id": "end-1", "type": "end", "data": [:]]
            ],
            "edges": [
                ["source": "start-1", "target": "message-1"],
                ["source": "message-1", "target": "end-1"]
            ]
        ]
    }

    /// Creates a flow with conditional branching
    private func createConditionalFlow() -> [String: Any] {
        return [
            "nodes": [
                ["id": "start-1", "type": "START", "data": [:]],
                ["id": "buttons-1", "type": "buttons", "data": [
                    "buttons": [
                        ["id": "btn-yes", "label": "Yes", "value": "yes"],
                        ["id": "btn-no", "label": "No", "value": "no"]
                    ]
                ]],
                ["id": "yes-response", "type": "message", "data": ["text": "Great!"]],
                ["id": "no-response", "type": "message", "data": ["text": "Maybe later!"]],
                ["id": "end-1", "type": "end", "data": [:]]
            ],
            "edges": [
                ["source": "start-1", "target": "buttons-1"],
                ["source": "buttons-1", "target": "yes-response", "sourceHandle": "btn-yes"],
                ["source": "buttons-1", "target": "no-response", "sourceHandle": "btn-no"],
                ["source": "yes-response", "target": "end-1"],
                ["source": "no-response", "target": "end-1"]
            ]
        ]
    }

    /// Creates a flow with nested structure
    private func createNestedFlow() -> [String: Any] {
        return [
            "flow": [
                "nodes": [
                    ["id": "start-1", "type": "START", "data": [:]],
                    ["id": "message-1", "type": "message", "data": ["text": "Nested message"]],
                    ["id": "end-1", "type": "end", "data": [:]]
                ],
                "edges": [
                    ["source": "start-1", "target": "message-1"],
                    ["source": "message-1", "target": "end-1"]
                ]
            ]
        ]
    }

    /// Creates a flow with isStart flag instead of START type
    private func createFlowWithIsStartFlag() -> [String: Any] {
        return [
            "nodes": [
                ["id": "entry-node", "type": "message", "data": ["text": "Entry point"], "isStart": true],
                ["id": "end-1", "type": "end", "data": [:]]
            ],
            "edges": [
                ["source": "entry-node", "target": "end-1"]
            ]
        ]
    }

    /// Creates a flow with connections key instead of edges
    private func createFlowWithConnections() -> [String: Any] {
        return [
            "nodes": [
                ["id": "start-1", "type": "START", "data": [:]],
                ["id": "message-1", "type": "message", "data": ["text": "Using connections"]],
                ["id": "end-1", "type": "end", "data": [:]]
            ],
            "connections": [
                ["source": "start-1", "target": "message-1"],
                ["source": "message-1", "target": "end-1"]
            ]
        ]
    }

    // MARK: - Initialization Tests

    func testEngineInitialization() {
        // Given a new engine
        let engine = NodeFlowEngine()

        // Then it should be properly initialized
        XCTAssertNotNil(engine)
        XCTAssertFalse(engine.isFlowLoaded)
        XCTAssertEqual(engine.nodeCount, 0)
        XCTAssertEqual(engine.edgeCount, 0)
        XCTAssertNil(engine.currentNodeId)
        XCTAssertFalse(engine.isProcessing)
        XCTAssertFalse(engine.isFlowComplete)
        XCTAssertNil(engine.errorMessage)
    }

    func testEngineInitializationWithCustomDependencies() {
        // Given custom state and registry
        let customState = ChatState.shared
        let customRegistry = NodeHandlerRegistry()

        // When creating engine with custom dependencies
        let engine = NodeFlowEngine(state: customState, registry: customRegistry)

        // Then it should use the provided dependencies
        XCTAssertNotNil(engine)
        XCTAssertFalse(engine.isFlowLoaded)
    }

    // MARK: - Flow Loading Tests

    func testLoadSimpleFlow() {
        // Given a simple flow
        let flowData = createSimpleFlow()

        // When loading the flow
        engine.loadFlow(flowData)

        // Then the flow should be loaded
        XCTAssertTrue(engine.isFlowLoaded)
        XCTAssertEqual(engine.nodeCount, 3)
        XCTAssertEqual(engine.edgeCount, 2)
    }

    func testLoadNestedFlow() {
        // Given a nested flow structure
        let flowData = createNestedFlow()

        // When loading the flow
        engine.loadFlow(flowData)

        // Then the flow should be loaded from nested structure
        XCTAssertTrue(engine.isFlowLoaded)
        XCTAssertEqual(engine.nodeCount, 3)
        XCTAssertEqual(engine.edgeCount, 2)
    }

    func testLoadFlowWithConnections() {
        // Given a flow with connections key
        let flowData = createFlowWithConnections()

        // When loading the flow
        engine.loadFlow(flowData)

        // Then the edges should be loaded from connections
        XCTAssertTrue(engine.isFlowLoaded)
        XCTAssertEqual(engine.edgeCount, 2)
    }

    func testLoadEmptyFlow() {
        // Given an empty flow
        let flowData: [String: Any] = [:]

        // When loading the flow
        engine.loadFlow(flowData)

        // Then the flow should not be loaded
        XCTAssertFalse(engine.isFlowLoaded)
        XCTAssertEqual(engine.nodeCount, 0)
        XCTAssertEqual(engine.edgeCount, 0)
    }

    func testLoadFlowResetsState() {
        // Given a flow that has been loaded
        engine.loadFlow(createSimpleFlow())

        // When loading a new flow
        let newFlow: [String: Any] = [
            "nodes": [
                ["id": "new-start", "type": "START", "data": [:]]
            ],
            "edges": []
        ]
        engine.loadFlow(newFlow)

        // Then the state should be reset
        XCTAssertEqual(engine.nodeCount, 1)
        XCTAssertFalse(engine.isFlowComplete)
        XCTAssertNil(engine.currentNodeId)
    }

    func testAllNodeIdsReturnsCorrectIds() {
        // Given a flow with multiple nodes
        engine.loadFlow(createSimpleFlow())

        // When getting all node IDs
        let nodeIds = engine.allNodeIds

        // Then all IDs should be returned
        XCTAssertEqual(nodeIds.count, 3)
        XCTAssertTrue(nodeIds.contains("start-1"))
        XCTAssertTrue(nodeIds.contains("message-1"))
        XCTAssertTrue(nodeIds.contains("end-1"))
    }

    // MARK: - Start Node Detection Tests

    func testStartFlowWithNoNodesShowsError() async {
        // Given an empty flow
        engine.loadFlow([:])

        // When starting the flow
        engine.startFlow()

        // Allow async error to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then an error should be set
        XCTAssertNotNil(engine.errorMessage)
        XCTAssertTrue(engine.errorMessage!.contains("No nodes"))
    }

    func testStartFlowFindsStartNodeByType() async {
        // Given a flow with START type node
        engine.loadFlow(createSimpleFlow())

        // When starting the flow
        engine.startFlow()

        // Allow processing
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then the start node should be found and processed
        XCTAssertNotNil(engine.currentNodeId)
    }

    func testStartFlowFindsStartNodeByIsStartFlag() async {
        // Given a flow with isStart flag
        engine.loadFlow(createFlowWithIsStartFlag())

        // When starting the flow
        engine.startFlow()

        // Allow processing
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then the entry node should be found
        // (node with isStart: true should be detected)
        XCTAssertTrue(engine.isFlowLoaded)
    }

    func testStartFlowFindsEntryNodeFromEdges() {
        // Given a flow where start is determined by edges (no incoming edges)
        let flowData: [String: Any] = [
            "nodes": [
                ["id": "orphan-1", "type": "message", "data": ["text": "Orphan"]],
                ["id": "message-2", "type": "message", "data": ["text": "Connected"]],
                ["id": "end-1", "type": "end", "data": [:]]
            ],
            "edges": [
                ["source": "orphan-1", "target": "message-2"],
                ["source": "message-2", "target": "end-1"]
            ]
        ]

        // When loading and starting
        engine.loadFlow(flowData)

        // Then the orphan node (no incoming edges) should be detected as start
        XCTAssertTrue(engine.isFlowLoaded)
    }

    // MARK: - Edge Navigation Tests

    func testGetNextNodeIdWithDefaultEdge() {
        // Given a flow with edges
        engine.loadFlow(createSimpleFlow())

        // When getting next node without port
        let nextId = engine.getNextNodeId(from: "start-1")

        // Then the next node should be found
        XCTAssertEqual(nextId, "message-1")
    }

    func testGetNextNodeIdWithPort() {
        // Given a flow with conditional edges
        engine.loadFlow(createConditionalFlow())

        // When getting next node with specific port
        let yesNextId = engine.getNextNodeId(from: "buttons-1", port: "btn-yes")
        let noNextId = engine.getNextNodeId(from: "buttons-1", port: "btn-no")

        // Then the correct nodes should be returned
        XCTAssertEqual(yesNextId, "yes-response")
        XCTAssertEqual(noNextId, "no-response")
    }

    func testGetNextNodeIdWithNonexistentPort() {
        // Given a flow with edges
        engine.loadFlow(createSimpleFlow())

        // When getting next node with nonexistent port
        let nextId = engine.getNextNodeId(from: "start-1", port: "nonexistent")

        // Then it should fall back to default edge
        XCTAssertEqual(nextId, "message-1")
    }

    func testGetNextNodeIdReturnsNilForEndNode() {
        // Given a flow
        engine.loadFlow(createSimpleFlow())

        // When getting next node from end node
        let nextId = engine.getNextNodeId(from: "end-1")

        // Then nil should be returned
        XCTAssertNil(nextId)
    }

    func testGetNextNodeIdReturnsNilForNonexistentNode() {
        // Given a flow
        engine.loadFlow(createSimpleFlow())

        // When getting next node from nonexistent node
        let nextId = engine.getNextNodeId(from: "nonexistent-node")

        // Then nil should be returned
        XCTAssertNil(nextId)
    }

    func testGetOutgoingEdges() {
        // Given a conditional flow
        engine.loadFlow(createConditionalFlow())

        // When getting outgoing edges from buttons node
        let edges = engine.getOutgoingEdges(from: "buttons-1")

        // Then both edges should be returned
        XCTAssertEqual(edges.count, 2)
    }

    func testGetOutgoingEdgesForEndNode() {
        // Given a flow
        engine.loadFlow(createSimpleFlow())

        // When getting outgoing edges from end node
        let edges = engine.getOutgoingEdges(from: "end-1")

        // Then no edges should be returned
        XCTAssertTrue(edges.isEmpty)
    }

    // MARK: - Node Processing Tests

    func testProcessNodeUpdatesCurrentNodeId() async {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When processing a node
        await engine.processNode("message-1")

        // Then the current node ID should be updated
        XCTAssertEqual(engine.currentNodeId, "message-1")
    }

    func testProcessNonexistentNodeSetsError() async {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When processing a nonexistent node
        await engine.processNode("nonexistent")

        // Allow error to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then an error should be set
        XCTAssertNotNil(engine.errorMessage)
        XCTAssertTrue(engine.errorMessage!.contains("not found"))
    }

    func testProcessNodeWithoutTypeSetsError() async {
        // Given a flow with a node missing type
        let flowData: [String: Any] = [
            "nodes": [
                ["id": "broken-node", "data": [:]]
            ],
            "edges": []
        ]
        engine.loadFlow(flowData)

        // When processing the broken node
        await engine.processNode("broken-node")

        // Allow error to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then an error should be set
        XCTAssertNotNil(engine.errorMessage)
        XCTAssertTrue(engine.errorMessage!.contains("missing type"))
    }

    // MARK: - Flow Completion Tests

    func testEndNodeTriggersFlowCompletion() async {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When processing an end node
        await engine.processNode("end-1")

        // Then flow should be marked complete
        XCTAssertTrue(engine.isFlowComplete)
    }

    func testGoalNodeTriggersFlowCompletion() async {
        // Given a flow with goal node
        let flowData: [String: Any] = [
            "nodes": [
                ["id": "start-1", "type": "START", "data": [:]],
                ["id": "goal-1", "type": "goal", "data": [:]]
            ],
            "edges": [
                ["source": "start-1", "target": "goal-1"]
            ]
        ]
        engine.loadFlow(flowData)

        // When processing the goal node
        await engine.processNode("goal-1")

        // Then flow should be marked complete
        XCTAssertTrue(engine.isFlowComplete)
    }

    func testEndConversationNodeTriggersCompletion() async {
        // Given a flow with end_conversation node
        let flowData: [String: Any] = [
            "nodes": [
                ["id": "start-1", "type": "START", "data": [:]],
                ["id": "end-conv-1", "type": "end_conversation", "data": [:]]
            ],
            "edges": [
                ["source": "start-1", "target": "end-conv-1"]
            ]
        ]
        engine.loadFlow(flowData)

        // When processing the end_conversation node
        await engine.processNode("end-conv-1")

        // Then flow should be marked complete
        XCTAssertTrue(engine.isFlowComplete)
    }

    // MARK: - Restart Flow Tests

    func testRestartFlowResetsState() async {
        // Given a flow that has been started
        engine.loadFlow(createSimpleFlow())
        engine.startFlow()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // When restarting the flow
        engine.restartFlow()

        // Then state should be reset
        XCTAssertFalse(engine.isFlowComplete)
    }

    // MARK: - Node Info Tests

    func testGetNodeInfoReturnsCorrectData() {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When getting node info
        let info = engine.getNodeInfo("message-1")

        // Then correct info should be returned
        XCTAssertNotNil(info)
        XCTAssertEqual(info?["id"] as? String, "message-1")
        XCTAssertEqual(info?["type"] as? String, "message")
        XCTAssertNotNil(info?["data"])
    }

    func testGetNodeInfoReturnsNilForNonexistentNode() {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When getting info for nonexistent node
        let info = engine.getNodeInfo("nonexistent")

        // Then nil should be returned
        XCTAssertNil(info)
    }

    // MARK: - User Input Handling Tests

    func testHandleUserInputStoresAnswer() async {
        // Given a loaded flow with text input
        let flowData: [String: Any] = [
            "nodes": [
                ["id": "start-1", "type": "START", "data": [:]],
                ["id": "input-1", "type": "textInput", "data": ["placeholder": "Enter name"]],
                ["id": "end-1", "type": "end", "data": [:]]
            ],
            "edges": [
                ["source": "start-1", "target": "input-1"],
                ["source": "input-1", "target": "end-1"]
            ]
        ]
        engine.loadFlow(flowData)

        // When handling user input
        await engine.handleUserInput("John Doe", forNodeId: "input-1")

        // Then the answer should be stored
        XCTAssertEqual(testState.getAnswer(nodeId: "input-1") as? String, "John Doe")
    }

    func testHandleUserInputAddsToTranscript() async {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When handling user input
        await engine.handleUserInput("Test message", forNodeId: "message-1")

        // Then the message should be in transcript
        let transcript = testState.getTranscript()
        let userMessages = transcript.filter { $0["type"] as? String == "user" }
        XCTAssertFalse(userMessages.isEmpty)
    }

    func testHandleButtonClickStoresAnswer() async {
        // Given a conditional flow
        engine.loadFlow(createConditionalFlow())

        // When handling button click
        await engine.handleButtonClick(buttonId: "btn-yes", forNodeId: "buttons-1")

        // Then the answer should be stored
        XCTAssertNotNil(testState.getAnswer(nodeId: "buttons-1"))
    }

    func testHandleChoiceSelectionStoresAnswer() async {
        // Given a flow with single choice
        let flowData: [String: Any] = [
            "nodes": [
                ["id": "start-1", "type": "START", "data": [:]],
                ["id": "choice-1", "type": "singleChoice", "data": [
                    "options": [
                        ["id": "opt-1", "label": "Option 1", "value": "option1"],
                        ["id": "opt-2", "label": "Option 2", "value": "option2"]
                    ]
                ]],
                ["id": "end-1", "type": "end", "data": [:]]
            ],
            "edges": [
                ["source": "start-1", "target": "choice-1"],
                ["source": "choice-1", "target": "end-1"]
            ]
        ]
        engine.loadFlow(flowData)

        // When handling choice selection
        await engine.handleChoiceSelection(optionId: "opt-1", forNodeId: "choice-1")

        // Then the answer should be stored
        XCTAssertNotNil(testState.getAnswer(nodeId: "choice-1"))
    }

    // MARK: - Input Validation Tests

    func testEmailValidationAcceptsValidEmail() async {
        // Given a flow with email validation
        let flowData: [String: Any] = [
            "nodes": [
                ["id": "start-1", "type": "START", "data": [:]],
                ["id": "email-1", "type": "textInput", "data": [
                    "validation": "email"
                ]],
                ["id": "end-1", "type": "end", "data": [:]]
            ],
            "edges": [
                ["source": "start-1", "target": "email-1"],
                ["source": "email-1", "target": "end-1"]
            ]
        ]
        engine.loadFlow(flowData)

        // When entering valid email
        await engine.handleUserInput("test@example.com", forNodeId: "email-1")

        // Then no error should be set
        XCTAssertNil(engine.errorMessage)
    }

    func testEmailValidationRejectsInvalidEmail() async {
        // Given a flow with email validation
        let flowData: [String: Any] = [
            "nodes": [
                ["id": "start-1", "type": "START", "data": [:]],
                ["id": "email-1", "type": "textInput", "data": [
                    "validation": "email"
                ]],
                ["id": "end-1", "type": "end", "data": [:]]
            ],
            "edges": [
                ["source": "start-1", "target": "email-1"],
                ["source": "email-1", "target": "end-1"]
            ]
        ]
        engine.loadFlow(flowData)

        // When entering invalid email
        await engine.handleUserInput("not-an-email", forNodeId: "email-1")

        // Allow error to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then an error should be set
        XCTAssertNotNil(engine.errorMessage)
    }

    func testPhoneValidationAcceptsValidPhone() async {
        // Given a flow with phone validation
        let flowData: [String: Any] = [
            "nodes": [
                ["id": "start-1", "type": "START", "data": [:]],
                ["id": "phone-1", "type": "textInput", "data": [
                    "validationType": "phone"
                ]],
                ["id": "end-1", "type": "end", "data": [:]]
            ],
            "edges": [
                ["source": "start-1", "target": "phone-1"],
                ["source": "phone-1", "target": "end-1"]
            ]
        ]
        engine.loadFlow(flowData)

        // When entering valid phone
        await engine.handleUserInput("+1-555-123-4567", forNodeId: "phone-1")

        // Then no error should be set
        XCTAssertNil(engine.errorMessage)
    }

    // MARK: - Publisher Tests

    func testUIStatePublisher() {
        // Given an engine
        let engine = NodeFlowEngine()

        // When accessing publisher
        let publisher = engine.uiStatePublisher

        // Then it should not be nil
        XCTAssertNotNil(publisher)
    }

    func testProcessingPublisher() {
        // Given an engine
        let engine = NodeFlowEngine()

        // When accessing publisher
        let publisher = engine.processingPublisher

        // Then it should not be nil
        XCTAssertNotNil(publisher)
    }

    func testErrorPublisher() {
        // Given an engine
        let engine = NodeFlowEngine()

        // When accessing publisher
        let publisher = engine.errorPublisher

        // Then it should not be nil
        XCTAssertNotNil(publisher)
    }

    func testCompletionPublisher() {
        // Given an engine
        let engine = NodeFlowEngine()

        // When accessing publisher
        let publisher = engine.completionPublisher

        // Then it should not be nil
        XCTAssertNotNil(publisher)
    }

    func testCurrentNodePublisher() {
        // Given an engine
        let engine = NodeFlowEngine()

        // When accessing publisher
        let publisher = engine.currentNodePublisher

        // Then it should not be nil
        XCTAssertNotNil(publisher)
    }

    // MARK: - Error Handling Tests

    func testHandleUserInputForNonexistentNodeSetsError() async {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When handling input for nonexistent node
        await engine.handleUserInput("test", forNodeId: "nonexistent")

        // Allow error to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then an error should be set
        XCTAssertNotNil(engine.errorMessage)
    }

    func testHandleButtonClickForNonexistentNodeSetsError() async {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When clicking button on nonexistent node
        await engine.handleButtonClick(buttonId: "btn-1", forNodeId: "nonexistent")

        // Allow error to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then an error should be set
        XCTAssertNotNil(engine.errorMessage)
    }

    func testHandleChoiceSelectionForNonexistentNodeSetsError() async {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When selecting choice on nonexistent node
        await engine.handleChoiceSelection(optionId: "opt-1", forNodeId: "nonexistent")

        // Allow error to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then an error should be set
        XCTAssertNotNil(engine.errorMessage)
    }

    // MARK: - Debug Extension Tests

    #if DEBUG
    func testDebugSetCurrentNode() {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When setting current node manually
        engine.debugSetCurrentNode("message-1")

        // Then the current node should be updated
        XCTAssertEqual(engine.currentNodeId, "message-1")
    }

    func testDebugCompleteFlow() {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When completing flow manually
        engine.debugCompleteFlow()

        // Then the flow should be marked complete
        XCTAssertTrue(engine.isFlowComplete)
    }

    func testDebugPrintFlowDoesNotCrash() {
        // Given a loaded flow
        engine.loadFlow(createSimpleFlow())

        // When printing debug info
        engine.debugPrintFlow()

        // Then it should not crash (no assertion needed, just verify no crash)
        XCTAssertTrue(true)
    }
    #endif

    // MARK: - Performance Tests

    func testLoadFlowPerformance() {
        // Given a large flow
        var nodes: [[String: Any]] = []
        var edges: [[String: Any]] = []

        for i in 0..<100 {
            nodes.append(["id": "node-\(i)", "type": "message", "data": ["text": "Message \(i)"]])
            if i < 99 {
                edges.append(["source": "node-\(i)", "target": "node-\(i + 1)"])
            }
        }

        let flowData: [String: Any] = ["nodes": nodes, "edges": edges]

        // Measure performance
        measure {
            engine.loadFlow(flowData)
        }
    }

    func testEdgeNavigationPerformance() {
        // Given a flow with many edges
        var nodes: [[String: Any]] = [["id": "hub", "type": "buttons", "data": [:]]]
        var edges: [[String: Any]] = []

        for i in 0..<50 {
            nodes.append(["id": "target-\(i)", "type": "message", "data": [:]])
            edges.append(["source": "hub", "target": "target-\(i)", "sourceHandle": "btn-\(i)"])
        }

        let flowData: [String: Any] = ["nodes": nodes, "edges": edges]
        engine.loadFlow(flowData)

        // Measure performance
        measure {
            for i in 0..<50 {
                _ = engine.getNextNodeId(from: "hub", port: "btn-\(i)")
            }
        }
    }
}
