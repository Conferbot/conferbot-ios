//
//  NodeHandlerRegistryTests.swift
//  Conferbot
//
//  Comprehensive tests for NodeHandlerRegistry - the registry for managing
//  node handlers that process different chatbot node types.
//

import XCTest
@testable import Conferbot

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class NodeHandlerRegistryTests: XCTestCase {

    // MARK: - Properties

    var registry: NodeHandlerRegistry!
    var testState: ChatState!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        registry = NodeHandlerRegistry()
        testState = ChatState.shared
        testState.reset()
    }

    override func tearDown() {
        registry.clear()
        testState.reset()
        registry = nil
        testState = nil
        super.tearDown()
    }

    // MARK: - Mock Handler for Testing

    /// A mock handler for testing registration and lookup
    class MockNodeHandler: BaseNodeHandler {
        let testNodeType: String
        var handleCalled = false
        var lastNode: [String: Any]?

        init(nodeType: String) {
            self.testNodeType = nodeType
            super.init()
        }

        override var nodeType: String {
            return testNodeType
        }

        override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
            handleCalled = true
            lastNode = node
            return .proceed(nil, nil)
        }
    }

    /// A handler that returns an error
    class ErrorNodeHandler: BaseNodeHandler {
        override var nodeType: String { "error_node" }

        override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
            return .error("Test error message")
        }
    }

    /// A handler that returns UI state
    class UINodeHandler: BaseNodeHandler {
        override var nodeType: String { "ui_node" }

        override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
            return .displayUI(.message(text: "Test message", typing: false))
        }
    }

    // MARK: - Initialization Tests

    func testRegistryInitialization() {
        // Given a new registry
        let registry = NodeHandlerRegistry()

        // Then it should be empty
        XCTAssertEqual(registry.count, 0)
        XCTAssertTrue(registry.registeredTypes.isEmpty)
    }

    func testSharedRegistryHasHandlersRegistered() {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        // Then it should have handlers registered
        XCTAssertGreaterThan(sharedRegistry.count, 0)
    }

    func testSharedRegistryContainsMessageHandler() {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        // Then it should contain message handler
        XCTAssertTrue(sharedRegistry.hasHandler(for: "message"))
    }

    func testSharedRegistryContainsCommonHandlers() {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        // Then it should contain common handlers
        let commonTypes = [
            "message", "image", "video", "audio", "file", "gif",
            "textInput", "singleChoice", "multiChoice", "buttons",
            "quickReplies", "cards", "rating", "opinionScale",
            "calendar", "fileUpload", "liveChat", "humanHandover",
            "link", "embed", "condition", "jump", "delay", "end"
        ]

        for type in commonTypes {
            XCTAssertTrue(sharedRegistry.hasHandler(for: type), "Missing handler for: \(type)")
        }
    }

    // MARK: - Handler Registration Tests

    func testRegisterSingleHandler() {
        // Given a mock handler
        let handler = MockNodeHandler(nodeType: "test_node")

        // When registering
        registry.register(handler)

        // Then it should be registered
        XCTAssertTrue(registry.hasHandler(for: "test_node"))
        XCTAssertEqual(registry.count, 1)
    }

    func testRegisterMultipleHandlers() {
        // Given multiple handlers
        let handlers = [
            MockNodeHandler(nodeType: "node1"),
            MockNodeHandler(nodeType: "node2"),
            MockNodeHandler(nodeType: "node3")
        ]

        // When registering
        registry.register(handlers)

        // Then all should be registered
        XCTAssertEqual(registry.count, 3)
        XCTAssertTrue(registry.hasHandler(for: "node1"))
        XCTAssertTrue(registry.hasHandler(for: "node2"))
        XCTAssertTrue(registry.hasHandler(for: "node3"))
    }

    func testRegisterOverwritesExistingHandler() {
        // Given an existing handler
        let handler1 = MockNodeHandler(nodeType: "test_node")
        registry.register(handler1)

        // When registering another handler for same type
        let handler2 = MockNodeHandler(nodeType: "test_node")
        registry.register(handler2)

        // Then the count should remain 1 (overwritten)
        XCTAssertEqual(registry.count, 1)
    }

    func testUnregisterHandler() {
        // Given a registered handler
        let handler = MockNodeHandler(nodeType: "test_node")
        registry.register(handler)

        // When unregistering
        registry.unregister("test_node")

        // Then it should be removed
        XCTAssertFalse(registry.hasHandler(for: "test_node"))
        XCTAssertEqual(registry.count, 0)
    }

    func testUnregisterNonexistentHandlerDoesNotCrash() {
        // When unregistering nonexistent handler
        registry.unregister("nonexistent")

        // Then no crash should occur
        XCTAssertEqual(registry.count, 0)
    }

    // MARK: - Handler Lookup Tests

    func testGetHandlerReturnsRegisteredHandler() {
        // Given a registered handler
        let handler = MockNodeHandler(nodeType: "test_node")
        registry.register(handler)

        // When getting the handler
        let retrieved = registry.getHandler(for: "test_node")

        // Then the correct handler should be returned
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.nodeType, "test_node")
    }

    func testGetHandlerReturnsNilForUnregistered() {
        // When getting an unregistered handler
        let handler = registry.getHandler(for: "nonexistent")

        // Then nil should be returned
        XCTAssertNil(handler)
    }

    func testHasHandlerReturnsTrueForRegistered() {
        // Given a registered handler
        registry.register(MockNodeHandler(nodeType: "test_node"))

        // When checking
        let hasHandler = registry.hasHandler(for: "test_node")

        // Then true should be returned
        XCTAssertTrue(hasHandler)
    }

    func testHasHandlerReturnsFalseForUnregistered() {
        // When checking for unregistered handler
        let hasHandler = registry.hasHandler(for: "nonexistent")

        // Then false should be returned
        XCTAssertFalse(hasHandler)
    }

    func testRegisteredTypesReturnsAllTypes() {
        // Given multiple registered handlers
        registry.register(MockNodeHandler(nodeType: "type1"))
        registry.register(MockNodeHandler(nodeType: "type2"))
        registry.register(MockNodeHandler(nodeType: "type3"))

        // When getting registered types
        let types = registry.registeredTypes

        // Then all types should be returned
        XCTAssertEqual(types.count, 3)
        XCTAssertTrue(types.contains("type1"))
        XCTAssertTrue(types.contains("type2"))
        XCTAssertTrue(types.contains("type3"))
    }

    func testCountReturnsCorrectNumber() {
        // Given registered handlers
        registry.register(MockNodeHandler(nodeType: "type1"))
        registry.register(MockNodeHandler(nodeType: "type2"))

        // Then count should be correct
        XCTAssertEqual(registry.count, 2)
    }

    // MARK: - Missing Handler Error Tests

    func testProcessReturnsErrorForMissingHandler() async {
        // Given a node with unregistered type
        let node: [String: Any] = [
            "id": "node-1",
            "type": "unknown_type",
            "data": [:]
        ]

        // When processing
        let result = await registry.process(node: node, state: testState)

        // Then an error should be returned
        if case .error(let message) = result {
            XCTAssertTrue(message.contains("No handler registered"))
            XCTAssertTrue(message.contains("unknown_type"))
        } else {
            XCTFail("Expected error result")
        }
    }

    func testProcessReturnsErrorForMissingType() async {
        // Given a node without type
        let node: [String: Any] = [
            "id": "node-1",
            "data": [:]
        ]

        // When processing
        let result = await registry.process(node: node, state: testState)

        // Then an error should be returned
        if case .error(let message) = result {
            XCTAssertTrue(message.contains("missing type"))
        } else {
            XCTFail("Expected error result")
        }
    }

    // MARK: - Handler Execution Tests

    func testProcessCallsHandler() async {
        // Given a registered mock handler
        let handler = MockNodeHandler(nodeType: "test_node")
        registry.register(handler)

        let node: [String: Any] = [
            "id": "node-1",
            "type": "test_node",
            "data": ["key": "value"]
        ]

        // When processing
        _ = await registry.process(node: node, state: testState)

        // Then handler should be called
        XCTAssertTrue(handler.handleCalled)
        XCTAssertNotNil(handler.lastNode)
        XCTAssertEqual(handler.lastNode?["id"] as? String, "node-1")
    }

    func testProcessReturnsHandlerResult() async {
        // Given a handler that returns proceed
        let handler = MockNodeHandler(nodeType: "test_node")
        registry.register(handler)

        let node: [String: Any] = [
            "id": "node-1",
            "type": "test_node",
            "data": [:]
        ]

        // When processing
        let result = await registry.process(node: node, state: testState)

        // Then proceed result should be returned
        if case .proceed = result {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected proceed result")
        }
    }

    func testProcessReturnsErrorResult() async {
        // Given a handler that returns error
        let handler = ErrorNodeHandler()
        registry.register(handler)

        let node: [String: Any] = [
            "id": "node-1",
            "type": "error_node",
            "data": [:]
        ]

        // When processing
        let result = await registry.process(node: node, state: testState)

        // Then error result should be returned
        if case .error(let message) = result {
            XCTAssertEqual(message, "Test error message")
        } else {
            XCTFail("Expected error result")
        }
    }

    func testProcessReturnsUIResult() async {
        // Given a handler that returns UI state
        let handler = UINodeHandler()
        registry.register(handler)

        let node: [String: Any] = [
            "id": "node-1",
            "type": "ui_node",
            "data": [:]
        ]

        // When processing
        let result = await registry.process(node: node, state: testState)

        // Then UI result should be returned
        if case .displayUI(let uiState) = result {
            if case .message(let text, _) = uiState {
                XCTAssertEqual(text, "Test message")
            } else {
                XCTFail("Expected message UI state")
            }
        } else {
            XCTFail("Expected displayUI result")
        }
    }

    // MARK: - Clear and Reset Tests

    func testClearRemovesAllHandlers() {
        // Given registered handlers
        registry.register(MockNodeHandler(nodeType: "type1"))
        registry.register(MockNodeHandler(nodeType: "type2"))
        registry.register(MockNodeHandler(nodeType: "type3"))

        // When clearing
        registry.clear()

        // Then all handlers should be removed
        XCTAssertEqual(registry.count, 0)
        XCTAssertTrue(registry.registeredTypes.isEmpty)
    }

    func testResetRestoresDefaultHandlers() {
        // Given cleared registry
        let sharedRegistry = NodeHandlerRegistry.shared
        let originalCount = sharedRegistry.count

        // Create a fresh registry for testing
        let testRegistry = NodeHandlerRegistry()
        testRegistry.register(MockNodeHandler(nodeType: "custom"))
        testRegistry.clear()

        // When resetting
        testRegistry.reset()

        // Then default handlers should be restored
        XCTAssertGreaterThan(testRegistry.count, 0)
        XCTAssertTrue(testRegistry.hasHandler(for: "message"))
    }

    // MARK: - Thread Safety Tests

    func testConcurrentRegistration() {
        // Given concurrent registrations
        let expectation = XCTestExpectation(description: "Concurrent registration complete")
        expectation.expectedFulfillmentCount = 100

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<100 {
            queue.async {
                self.registry.register(MockNodeHandler(nodeType: "type-\(i)"))
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Then all handlers should be registered
        XCTAssertEqual(registry.count, 100)
    }

    func testConcurrentLookup() {
        // Given registered handlers
        for i in 0..<100 {
            registry.register(MockNodeHandler(nodeType: "type-\(i)"))
        }

        // Given concurrent lookups
        let expectation = XCTestExpectation(description: "Concurrent lookup complete")
        expectation.expectedFulfillmentCount = 1000

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for _ in 0..<1000 {
            queue.async {
                let randomType = "type-\(Int.random(in: 0..<100))"
                _ = self.registry.getHandler(for: randomType)
                _ = self.registry.hasHandler(for: randomType)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Then no crashes should occur
        XCTAssertTrue(true)
    }

    func testConcurrentRegistrationAndLookup() {
        // Given concurrent registration and lookup
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 200

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<100 {
            queue.async {
                self.registry.register(MockNodeHandler(nodeType: "type-\(i)"))
                expectation.fulfill()
            }
            queue.async {
                _ = self.registry.getHandler(for: "type-\(i)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Then no crashes should occur
        XCTAssertTrue(true)
    }

    // MARK: - Built-in Handler Tests

    func testMessageNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "msg-1",
            "type": "message",
            "data": ["text": "Hello, world!"]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then message UI should be returned
        if case .displayUI(let uiState) = result {
            if case .message(let text, _) = uiState {
                XCTAssertEqual(text, "Hello, world!")
            } else {
                XCTFail("Expected message UI state")
            }
        } else {
            XCTFail("Expected displayUI result")
        }
    }

    func testImageNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "img-1",
            "type": "image",
            "data": ["url": "https://example.com/image.jpg", "caption": "Test image"]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then image UI should be returned
        if case .displayUI(let uiState) = result {
            if case .image(let url, let caption) = uiState {
                XCTAssertEqual(url, "https://example.com/image.jpg")
                XCTAssertEqual(caption, "Test image")
            } else {
                XCTFail("Expected image UI state")
            }
        } else {
            XCTFail("Expected displayUI result")
        }
    }

    func testTextInputNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "input-1",
            "type": "textInput",
            "data": ["placeholder": "Enter your name"]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then text input UI should be returned
        if case .displayUI(let uiState) = result {
            if case .textInput(let placeholder, _, let nodeId) = uiState {
                XCTAssertEqual(placeholder, "Enter your name")
                XCTAssertEqual(nodeId, "input-1")
            } else {
                XCTFail("Expected textInput UI state")
            }
        } else {
            XCTFail("Expected displayUI result")
        }
    }

    func testButtonsNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "btn-1",
            "type": "buttons",
            "data": [
                "buttons": [
                    ["id": "btn-yes", "label": "Yes"],
                    ["id": "btn-no", "label": "No"]
                ]
            ]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then buttons UI should be returned
        if case .displayUI(let uiState) = result {
            if case .buttons(let buttons, let nodeId) = uiState {
                XCTAssertEqual(buttons.count, 2)
                XCTAssertEqual(nodeId, "btn-1")
            } else {
                XCTFail("Expected buttons UI state")
            }
        } else {
            XCTFail("Expected displayUI result")
        }
    }

    func testRatingNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "rating-1",
            "type": "rating",
            "data": ["max": 5, "style": "stars"]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then rating UI should be returned
        if case .displayUI(let uiState) = result {
            if case .rating(let max, let style, let nodeId) = uiState {
                XCTAssertEqual(max, 5)
                XCTAssertEqual(style, .stars)
                XCTAssertEqual(nodeId, "rating-1")
            } else {
                XCTFail("Expected rating UI state")
            }
        } else {
            XCTFail("Expected displayUI result")
        }
    }

    func testCalendarNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "cal-1",
            "type": "calendar",
            "data": ["mode": "dateTime"]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then calendar UI should be returned
        if case .displayUI(let uiState) = result {
            if case .calendar(let mode, let nodeId) = uiState {
                XCTAssertEqual(mode, .dateTime)
                XCTAssertEqual(nodeId, "cal-1")
            } else {
                XCTFail("Expected calendar UI state")
            }
        } else {
            XCTFail("Expected displayUI result")
        }
    }

    func testJumpNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "jump-1",
            "type": "jump",
            "data": ["targetNodeId": "target-node-123"]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then jumpTo result should be returned
        if case .jumpTo(let targetId) = result {
            XCTAssertEqual(targetId, "target-node-123")
        } else {
            XCTFail("Expected jumpTo result")
        }
    }

    func testEndNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "end-1",
            "type": "end",
            "data": [:]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then none UI should be returned
        if case .displayUI(let uiState) = result {
            if case .none = uiState {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected none UI state")
            }
        } else {
            XCTFail("Expected displayUI result")
        }
    }

    // MARK: - Node Handler Missing Data Error Tests

    func testMessageNodeHandlerMissingData() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "msg-1",
            "type": "message"
            // Missing data
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then error should be returned
        if case .error(let message) = result {
            XCTAssertTrue(message.contains("missing data"))
        } else {
            XCTFail("Expected error result")
        }
    }

    func testImageNodeHandlerMissingURL() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "img-1",
            "type": "image",
            "data": [:] // Missing URL
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then error should be returned
        if case .error(let message) = result {
            XCTAssertTrue(message.contains("missing URL") || message.contains("URL"))
        } else {
            XCTFail("Expected error result")
        }
    }

    // MARK: - Integration Handler Tests

    func testWebhookNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "webhook-1",
            "type": "webhook",
            "data": ["url": "https://example.com/webhook"]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then proceed result should be returned (webhook is async, proceeds immediately)
        if case .proceed = result {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected proceed result")
        }
    }

    func testApiNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "api-1",
            "type": "api",
            "data": ["endpoint": "https://api.example.com/data"]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then proceed result should be returned
        if case .proceed = result {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected proceed result")
        }
    }

    func testEmailNodeHandler() async {
        // Given the shared registry
        let sharedRegistry = NodeHandlerRegistry.shared

        let node: [String: Any] = [
            "id": "email-1",
            "type": "email",
            "data": ["to": "test@example.com", "subject": "Test"]
        ]

        // When processing
        let result = await sharedRegistry.process(node: node, state: testState)

        // Then proceed result should be returned
        if case .proceed = result {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected proceed result")
        }
    }

    // MARK: - Performance Tests

    func testRegistrationPerformance() {
        measure {
            for i in 0..<1000 {
                registry.register(MockNodeHandler(nodeType: "type-\(i)"))
            }
        }
    }

    func testLookupPerformance() {
        // Setup: register many handlers
        for i in 0..<1000 {
            registry.register(MockNodeHandler(nodeType: "type-\(i)"))
        }

        measure {
            for i in 0..<1000 {
                _ = registry.getHandler(for: "type-\(i)")
            }
        }
    }

    func testProcessPerformance() {
        // Given a registered handler
        registry.register(MockNodeHandler(nodeType: "test_node"))

        let node: [String: Any] = [
            "id": "node-1",
            "type": "test_node",
            "data": [:]
        ]

        measure {
            let expectation = XCTestExpectation(description: "Process complete")

            Task {
                for _ in 0..<100 {
                    _ = await registry.process(node: node, state: testState)
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }
}

// MARK: - BaseNodeHandler Helper Method Tests

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class BaseNodeHandlerHelperTests: XCTestCase {

    // MARK: - Properties

    var handler: TestableBaseNodeHandler!

    // MARK: - Test Handler

    class TestableBaseNodeHandler: BaseNodeHandler {
        override var nodeType: String { "test" }

        override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
            return .proceed(nil, nil)
        }

        // Expose helper methods for testing
        func testGetNodeData(_ node: [String: Any]) -> [String: Any]? {
            return getNodeData(node)
        }

        func testGetString(_ dict: [String: Any], _ key: String) -> String? {
            return getString(dict, key)
        }

        func testGetInt(_ dict: [String: Any], _ key: String) -> Int? {
            return getInt(dict, key)
        }

        func testGetBool(_ dict: [String: Any], _ key: String) -> Bool? {
            return getBool(dict, key)
        }

        func testGetDouble(_ dict: [String: Any], _ key: String) -> Double? {
            return getDouble(dict, key)
        }

        func testGetArray(_ dict: [String: Any], _ key: String) -> [[String: Any]]? {
            return getArray(dict, key)
        }

        func testGetStringArray(_ dict: [String: Any], _ key: String) -> [String]? {
            return getStringArray(dict, key)
        }

        func testGetNodeId(_ node: [String: Any]) -> String? {
            return getNodeId(node)
        }

        func testGetNextNodeId(_ node: [String: Any]) -> String? {
            return getNextNodeId(node)
        }

        func testParseChoiceOptions(_ dicts: [[String: Any]]?) -> [ChoiceOption] {
            return parseChoiceOptions(dicts)
        }

        func testParseButtonOptions(_ dicts: [[String: Any]]?) -> [ButtonOption] {
            return parseButtonOptions(dicts)
        }

        func testParseCardData(_ dicts: [[String: Any]]?) -> [CardData] {
            return parseCardData(dicts)
        }
    }

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        handler = TestableBaseNodeHandler()
    }

    override func tearDown() {
        handler = nil
        super.tearDown()
    }

    // MARK: - Helper Method Tests

    func testGetNodeDataReturnsData() {
        let node: [String: Any] = [
            "id": "node-1",
            "data": ["key": "value"]
        ]

        let data = handler.testGetNodeData(node)

        XCTAssertNotNil(data)
        XCTAssertEqual(data?["key"] as? String, "value")
    }

    func testGetNodeDataReturnsNilWhenMissing() {
        let node: [String: Any] = ["id": "node-1"]

        let data = handler.testGetNodeData(node)

        XCTAssertNil(data)
    }

    func testGetStringReturnsValue() {
        let dict: [String: Any] = ["name": "John"]

        let value = handler.testGetString(dict, "name")

        XCTAssertEqual(value, "John")
    }

    func testGetStringReturnsNilForNonString() {
        let dict: [String: Any] = ["count": 42]

        let value = handler.testGetString(dict, "count")

        XCTAssertNil(value)
    }

    func testGetIntReturnsIntValue() {
        let dict: [String: Any] = ["count": 42]

        let value = handler.testGetInt(dict, "count")

        XCTAssertEqual(value, 42)
    }

    func testGetIntConvertsStringToInt() {
        let dict: [String: Any] = ["count": "42"]

        let value = handler.testGetInt(dict, "count")

        XCTAssertEqual(value, 42)
    }

    func testGetIntConvertsDoubleToInt() {
        let dict: [String: Any] = ["count": 42.5]

        let value = handler.testGetInt(dict, "count")

        XCTAssertEqual(value, 42)
    }

    func testGetBoolReturnsBoolValue() {
        let dict: [String: Any] = ["enabled": true]

        let value = handler.testGetBool(dict, "enabled")

        XCTAssertEqual(value, true)
    }

    func testGetBoolConvertsIntToBool() {
        let dict: [String: Any] = ["enabled": 1]

        let value = handler.testGetBool(dict, "enabled")

        XCTAssertEqual(value, true)
    }

    func testGetBoolConvertsStringToBool() {
        let dict: [String: Any] = ["enabled": "true"]

        let value = handler.testGetBool(dict, "enabled")

        XCTAssertEqual(value, true)
    }

    func testGetDoubleReturnsDoubleValue() {
        let dict: [String: Any] = ["price": 19.99]

        let value = handler.testGetDouble(dict, "price")

        XCTAssertEqual(value, 19.99, accuracy: 0.01)
    }

    func testGetDoubleConvertsIntToDouble() {
        let dict: [String: Any] = ["price": 20]

        let value = handler.testGetDouble(dict, "price")

        XCTAssertEqual(value, 20.0)
    }

    func testGetArrayReturnsArray() {
        let dict: [String: Any] = [
            "items": [
                ["id": "1", "name": "Item 1"],
                ["id": "2", "name": "Item 2"]
            ]
        ]

        let value = handler.testGetArray(dict, "items")

        XCTAssertEqual(value?.count, 2)
    }

    func testGetStringArrayReturnsArray() {
        let dict: [String: Any] = ["tags": ["tag1", "tag2", "tag3"]]

        let value = handler.testGetStringArray(dict, "tags")

        XCTAssertEqual(value, ["tag1", "tag2", "tag3"])
    }

    func testGetNodeIdFromIdField() {
        let node: [String: Any] = ["id": "node-123"]

        let value = handler.testGetNodeId(node)

        XCTAssertEqual(value, "node-123")
    }

    func testGetNodeIdFromNodeIdField() {
        let node: [String: Any] = ["nodeId": "node-456"]

        let value = handler.testGetNodeId(node)

        XCTAssertEqual(value, "node-456")
    }

    func testGetNextNodeIdFromData() {
        let node: [String: Any] = [
            "id": "node-1",
            "data": ["nextNodeId": "node-2"]
        ]

        let value = handler.testGetNextNodeId(node)

        XCTAssertEqual(value, "node-2")
    }

    func testGetNextNodeIdFromNextField() {
        let node: [String: Any] = [
            "id": "node-1",
            "data": ["next": "node-3"]
        ]

        let value = handler.testGetNextNodeId(node)

        XCTAssertEqual(value, "node-3")
    }

    func testParseChoiceOptions() {
        let options: [[String: Any]] = [
            ["id": "opt-1", "label": "Option 1", "value": "val1"],
            ["id": "opt-2", "label": "Option 2", "value": "val2"]
        ]

        let parsed = handler.testParseChoiceOptions(options)

        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].id, "opt-1")
        XCTAssertEqual(parsed[0].label, "Option 1")
        XCTAssertEqual(parsed[1].value, "val2")
    }

    func testParseButtonOptions() {
        let buttons: [[String: Any]] = [
            ["id": "btn-1", "label": "Button 1", "url": "https://example.com"],
            ["id": "btn-2", "label": "Button 2", "action": "submit"]
        ]

        let parsed = handler.testParseButtonOptions(buttons)

        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].id, "btn-1")
        XCTAssertEqual(parsed[0].url, "https://example.com")
        XCTAssertEqual(parsed[1].action, "submit")
    }

    func testParseCardData() {
        let cards: [[String: Any]] = [
            [
                "id": "card-1",
                "title": "Card 1",
                "subtitle": "Description 1",
                "imageUrl": "https://example.com/img1.jpg",
                "buttons": [
                    ["id": "btn-1", "label": "Action"]
                ]
            ]
        ]

        let parsed = handler.testParseCardData(cards)

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].title, "Card 1")
        XCTAssertEqual(parsed[0].subtitle, "Description 1")
        XCTAssertEqual(parsed[0].buttons.count, 1)
    }

    func testParseChoiceOptionsHandlesNil() {
        let parsed = handler.testParseChoiceOptions(nil)

        XCTAssertTrue(parsed.isEmpty)
    }

    func testParseButtonOptionsHandlesNil() {
        let parsed = handler.testParseButtonOptions(nil)

        XCTAssertTrue(parsed.isEmpty)
    }

    func testParseCardDataHandlesNil() {
        let parsed = handler.testParseCardData(nil)

        XCTAssertTrue(parsed.isEmpty)
    }
}
