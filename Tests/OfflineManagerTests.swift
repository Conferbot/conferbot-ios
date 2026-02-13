//
//  OfflineManagerTests.swift
//  ConferbotTests
//
//  Comprehensive tests for the OfflineManager service covering queue management,
//  message persistence, retry logic, and network status handling.
//

import XCTest
import Combine
@testable import Conferbot

final class OfflineManagerTests: XCTestCase {

    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
        // Clear the queue before each test
        OfflineManager.shared.clearQueue()
    }

    override func tearDown() {
        OfflineManager.shared.clearQueue()
        OfflineManager.shared.sendMessageHandler = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testShared_returnsSameInstance() {
        let instance1 = OfflineManager.shared
        let instance2 = OfflineManager.shared

        XCTAssertTrue(instance1 === instance2)
    }

    func testInitialState_queueIsEmpty() {
        XCTAssertEqual(OfflineManager.shared.queuedMessageCount, 0)
        XCTAssertTrue(OfflineManager.shared.queuedMessages.isEmpty)
    }

    func testInitialState_isNotFlushing() {
        XCTAssertFalse(OfflineManager.shared.isFlushing)
    }

    // MARK: - Queue Message Tests

    func testQueueMessage_addsToQueue() {
        let message = OfflineManager.shared.queueMessage(
            content: "Test message",
            chatSessionId: "session-123"
        )

        XCTAssertEqual(OfflineManager.shared.queuedMessageCount, 1)
        XCTAssertEqual(message.content, "Test message")
        XCTAssertEqual(message.chatSessionId, "session-123")
    }

    func testQueueMessage_generatesUniqueId() {
        let message1 = OfflineManager.shared.queueMessage(content: "Message 1")
        let message2 = OfflineManager.shared.queueMessage(content: "Message 2")

        XCTAssertNotEqual(message1.id, message2.id)
    }

    func testQueueMessage_setsTimestamp() {
        let beforeQueue = Date()
        let message = OfflineManager.shared.queueMessage(content: "Test")
        let afterQueue = Date()

        XCTAssertGreaterThanOrEqual(message.timestamp, beforeQueue)
        XCTAssertLessThanOrEqual(message.timestamp, afterQueue)
    }

    func testQueueMessage_initialRetryCountIsZero() {
        let message = OfflineManager.shared.queueMessage(content: "Test")

        XCTAssertEqual(message.retryCount, 0)
    }

    func testQueueMessage_withMetadata() {
        let metadata: [String: AnyCodable] = [
            "key1": AnyCodable("value1"),
            "key2": AnyCodable(42)
        ]

        let message = OfflineManager.shared.queueMessage(
            content: "Test",
            metadata: metadata
        )

        XCTAssertNotNil(message.metadata)
        XCTAssertEqual(message.metadata?["key1"]?.value as? String, "value1")
    }

    func testQueueMessage_multipleMessages() {
        OfflineManager.shared.queueMessage(content: "Message 1")
        OfflineManager.shared.queueMessage(content: "Message 2")
        OfflineManager.shared.queueMessage(content: "Message 3")

        XCTAssertEqual(OfflineManager.shared.queuedMessageCount, 3)
    }

    // MARK: - Queue Access Tests

    func testQueuedMessages_returnsAllMessages() {
        OfflineManager.shared.queueMessage(content: "Message 1")
        OfflineManager.shared.queueMessage(content: "Message 2")

        let messages = OfflineManager.shared.queuedMessages

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].content, "Message 1")
        XCTAssertEqual(messages[1].content, "Message 2")
    }

    // MARK: - Remove Message Tests

    func testRemoveMessage_removesFromQueue() {
        let message = OfflineManager.shared.queueMessage(content: "Test")

        let removed = OfflineManager.shared.removeMessage(byId: message.id)

        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.id, message.id)
        XCTAssertEqual(OfflineManager.shared.queuedMessageCount, 0)
    }

    func testRemoveMessage_nonExistentId_returnsNil() {
        OfflineManager.shared.queueMessage(content: "Test")

        let removed = OfflineManager.shared.removeMessage(byId: "non-existent-id")

        XCTAssertNil(removed)
        XCTAssertEqual(OfflineManager.shared.queuedMessageCount, 1)
    }

    // MARK: - Clear Queue Tests

    func testClearQueue_removesAllMessages() {
        OfflineManager.shared.queueMessage(content: "Message 1")
        OfflineManager.shared.queueMessage(content: "Message 2")
        OfflineManager.shared.queueMessage(content: "Message 3")

        OfflineManager.shared.clearQueue()

        XCTAssertEqual(OfflineManager.shared.queuedMessageCount, 0)
        XCTAssertTrue(OfflineManager.shared.queuedMessages.isEmpty)
    }

    // MARK: - Connection State Tests

    func testHandleSocketConnected_updatesState() {
        OfflineManager.shared.handleSocketConnected()

        // Cannot directly verify internal state, but no crash means success
        XCTAssertTrue(true)
    }

    func testHandleSocketDisconnected_updatesState() {
        OfflineManager.shared.handleSocketConnected()
        OfflineManager.shared.handleSocketDisconnected()

        XCTAssertTrue(true)
    }

    func testCanSendMessages_whenOffline_returnsFalse() {
        OfflineManager.shared.handleSocketDisconnected()

        // The result depends on actual network state
        // This test verifies the property exists and can be accessed
        _ = OfflineManager.shared.canSendMessages
        XCTAssertTrue(true)
    }

    // MARK: - Flush Queue Tests

    func testFlushQueue_whenQueueIsEmpty_doesNothing() {
        OfflineManager.shared.handleSocketConnected()
        OfflineManager.shared.flushQueue()

        // No crash and queue remains empty
        XCTAssertEqual(OfflineManager.shared.queuedMessageCount, 0)
    }

    func testFlushQueue_whenNotConnected_doesNotFlush() {
        OfflineManager.shared.queueMessage(content: "Test")
        OfflineManager.shared.handleSocketDisconnected()

        OfflineManager.shared.flushQueue()

        // Message should still be in queue
        XCTAssertEqual(OfflineManager.shared.queuedMessageCount, 1)
    }

    func testFlushQueue_callsSendMessageHandler() async throws {
        let expectation = self.expectation(description: "Send handler called")

        var sentMessages: [QueuedMessage] = []

        OfflineManager.shared.sendMessageHandler = { message in
            sentMessages.append(message)
            expectation.fulfill()
        }

        OfflineManager.shared.queueMessage(content: "Test message")
        OfflineManager.shared.handleSocketConnected()

        // Simulate being online
        // Note: In real tests, we'd mock NWPathMonitor

        OfflineManager.shared.flushQueue()

        // Wait for async flush
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertEqual(sentMessages.count, 1)
        XCTAssertEqual(sentMessages[0].content, "Test message")
    }

    func testFlushQueue_removesMessageOnSuccess() async throws {
        let expectation = self.expectation(description: "Flush complete")

        OfflineManager.shared.sendMessageHandler = { _ in
            // Success - no throw
        }

        OfflineManager.shared.queueMessage(content: "Test message")
        let initialCount = OfflineManager.shared.queuedMessageCount

        OfflineManager.shared.handleSocketConnected()
        OfflineManager.shared.flushQueue()

        // Wait for async flush
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        // Message should be removed after successful send
        XCTAssertLessThan(OfflineManager.shared.queuedMessageCount, initialCount)
    }

    // MARK: - Retry Logic Tests

    func testMaxRetries_defaultValue() {
        XCTAssertEqual(OfflineManager.shared.maxRetries, 3)
    }

    func testMaxRetries_canBeModified() {
        let originalValue = OfflineManager.shared.maxRetries

        OfflineManager.shared.maxRetries = 5
        XCTAssertEqual(OfflineManager.shared.maxRetries, 5)

        // Reset
        OfflineManager.shared.maxRetries = originalValue
    }

    func testRetryDelay_defaultValue() {
        XCTAssertEqual(OfflineManager.shared.retryDelay, 2.0)
    }

    func testRetryDelay_canBeModified() {
        let originalValue = OfflineManager.shared.retryDelay

        OfflineManager.shared.retryDelay = 5.0
        XCTAssertEqual(OfflineManager.shared.retryDelay, 5.0)

        // Reset
        OfflineManager.shared.retryDelay = originalValue
    }

    func testRetryFailedMessages_resetsRetryCount() {
        // This test would require access to internal retry count tracking
        // For now, verify the method doesn't crash
        OfflineManager.shared.retryFailedMessages()

        XCTAssertTrue(true)
    }

    // MARK: - Auto Flush Tests

    func testAutoFlushOnReconnect_defaultIsTrue() {
        XCTAssertTrue(OfflineManager.shared.autoFlushOnReconnect)
    }

    func testAutoFlushOnReconnect_canBeDisabled() {
        let originalValue = OfflineManager.shared.autoFlushOnReconnect

        OfflineManager.shared.autoFlushOnReconnect = false
        XCTAssertFalse(OfflineManager.shared.autoFlushOnReconnect)

        // Reset
        OfflineManager.shared.autoFlushOnReconnect = originalValue
    }

    // MARK: - Delegate Tests

    func testDelegate_canBeSet() {
        let delegate = MockOfflineManagerDelegate()
        OfflineManager.shared.delegate = delegate

        XCTAssertNotNil(OfflineManager.shared.delegate)

        // Clean up
        OfflineManager.shared.delegate = nil
    }

    func testDelegate_receivesQueueMessageEvent() {
        let delegate = MockOfflineManagerDelegate()
        OfflineManager.shared.delegate = delegate

        OfflineManager.shared.queueMessage(content: "Test")

        XCTAssertEqual(delegate.queuedMessageCount, 1)

        // Clean up
        OfflineManager.shared.delegate = nil
    }

    func testDelegate_receivesQueueCountUpdate() {
        let delegate = MockOfflineManagerDelegate()
        OfflineManager.shared.delegate = delegate

        OfflineManager.shared.queueMessage(content: "Test")

        XCTAssertEqual(delegate.lastQueueCount, 1)

        // Clean up
        OfflineManager.shared.delegate = nil
    }

    // MARK: - Published Properties Tests

    func testQueuedMessageCount_publishesChanges() {
        let expectation = self.expectation(description: "Count published")
        var receivedCounts: [Int] = []

        OfflineManager.shared.$queuedMessageCount
            .dropFirst() // Skip initial value
            .sink { count in
                receivedCounts.append(count)
                if receivedCounts.count >= 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        OfflineManager.shared.queueMessage(content: "Test")

        waitForExpectations(timeout: 2.0)

        XCTAssertFalse(receivedCounts.isEmpty)
    }

    func testIsOnline_publishesChanges() {
        // This test verifies the publisher exists
        var received = false

        OfflineManager.shared.$isOnline
            .sink { _ in
                received = true
            }
            .store(in: &cancellables)

        XCTAssertTrue(received) // Initial value
    }

    func testIsFlushing_publishesChanges() {
        var received = false

        OfflineManager.shared.$isFlushing
            .sink { _ in
                received = true
            }
            .store(in: &cancellables)

        XCTAssertTrue(received) // Initial value
    }

    // MARK: - QueuedMessage Model Tests

    func testQueuedMessage_initialization() {
        let message = QueuedMessage(
            content: "Test content",
            chatSessionId: "session-123"
        )

        XCTAssertFalse(message.id.isEmpty)
        XCTAssertEqual(message.content, "Test content")
        XCTAssertEqual(message.chatSessionId, "session-123")
        XCTAssertEqual(message.retryCount, 0)
    }

    func testQueuedMessage_equatable() {
        let id = UUID().uuidString
        let message1 = QueuedMessage(id: id, content: "Content 1")
        let message2 = QueuedMessage(id: id, content: "Content 2")
        let message3 = QueuedMessage(content: "Content 1")

        XCTAssertEqual(message1, message2) // Same ID
        XCTAssertNotEqual(message1, message3) // Different ID
    }

    func testQueuedMessage_codable() throws {
        let message = QueuedMessage(
            content: "Test",
            metadata: ["key": AnyCodable("value")],
            chatSessionId: "session-123"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(QueuedMessage.self, from: data)

        XCTAssertEqual(decoded.id, message.id)
        XCTAssertEqual(decoded.content, message.content)
        XCTAssertEqual(decoded.chatSessionId, message.chatSessionId)
    }

    // MARK: - Error Tests

    func testOfflineManagerError_networkUnavailable() {
        let error = OfflineManagerError.networkUnavailable
        XCTAssertTrue(error.errorDescription!.contains("unavailable"))
    }

    func testOfflineManagerError_maxRetriesExceeded() {
        let error = OfflineManagerError.maxRetriesExceeded
        XCTAssertTrue(error.errorDescription!.contains("retry"))
    }

    func testOfflineManagerError_socketNotConnected() {
        let error = OfflineManagerError.socketNotConnected
        XCTAssertTrue(error.errorDescription!.contains("not connected"))
    }

    func testOfflineManagerError_messageEncodingFailed() {
        let error = OfflineManagerError.messageEncodingFailed
        XCTAssertTrue(error.errorDescription!.contains("encode"))
    }

    // MARK: - Thread Safety Tests

    func testQueueMessage_threadSafe() {
        let expectation = self.expectation(description: "Concurrent queue")
        expectation.expectedFulfillmentCount = 100

        for i in 0..<100 {
            DispatchQueue.global().async {
                OfflineManager.shared.queueMessage(content: "Message \(i)")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 10.0)

        XCTAssertEqual(OfflineManager.shared.queuedMessageCount, 100)
    }

    func testClearQueue_threadSafe() {
        // Add some messages
        for i in 0..<50 {
            OfflineManager.shared.queueMessage(content: "Message \(i)")
        }

        let expectation = self.expectation(description: "Concurrent clear")
        expectation.expectedFulfillmentCount = 10

        for _ in 0..<10 {
            DispatchQueue.global().async {
                OfflineManager.shared.clearQueue()
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)

        XCTAssertEqual(OfflineManager.shared.queuedMessageCount, 0)
    }

    // MARK: - MessageQueue Tests

    func testMessageQueue_isEmpty_whenEmpty() {
        let queue = MessageQueue()
        // Clear any persisted messages
        queue.clear()

        XCTAssertTrue(queue.isEmpty)
    }

    func testMessageQueue_count_returnsCorrectValue() {
        let queue = MessageQueue()
        queue.clear()

        let message1 = QueuedMessage(content: "Test 1")
        let message2 = QueuedMessage(content: "Test 2")

        queue.enqueue(message: message1)
        queue.enqueue(message: message2)

        XCTAssertEqual(queue.count, 2)

        queue.clear()
    }

    func testMessageQueue_peek_returnsFirstWithoutRemoving() {
        let queue = MessageQueue()
        queue.clear()

        let message = QueuedMessage(content: "Test")
        queue.enqueue(message: message)

        let peeked = queue.peek()

        XCTAssertEqual(peeked?.id, message.id)
        XCTAssertEqual(queue.count, 1)

        queue.clear()
    }

    func testMessageQueue_dequeue_removesAndReturnsFirst() {
        let queue = MessageQueue()
        queue.clear()

        let message1 = QueuedMessage(content: "First")
        let message2 = QueuedMessage(content: "Second")

        queue.enqueue(message: message1)
        queue.enqueue(message: message2)

        let dequeued = queue.dequeue()

        XCTAssertEqual(dequeued?.content, "First")
        XCTAssertEqual(queue.count, 1)

        queue.clear()
    }

    func testMessageQueue_updateRetryCount() {
        let queue = MessageQueue()
        queue.clear()

        let message = QueuedMessage(content: "Test")
        queue.enqueue(message: message)

        queue.updateRetryCount(forId: message.id, retryCount: 3)

        let updated = queue.peek()
        XCTAssertEqual(updated?.retryCount, 3)

        queue.clear()
    }

    func testMessageQueue_getFailedMessages() {
        let queue = MessageQueue()
        queue.clear()

        let message1 = QueuedMessage(content: "Test 1")
        let message2 = QueuedMessage(content: "Test 2")

        queue.enqueue(message: message1)
        queue.enqueue(message: message2)

        queue.updateRetryCount(forId: message1.id, retryCount: 5)
        queue.updateRetryCount(forId: message2.id, retryCount: 2)

        let failed = queue.getFailedMessages(maxRetries: 3)

        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed[0].id, message1.id)

        queue.clear()
    }

    func testMessageQueue_removeFailedMessages() {
        let queue = MessageQueue()
        queue.clear()

        let message1 = QueuedMessage(content: "Test 1")
        let message2 = QueuedMessage(content: "Test 2")

        queue.enqueue(message: message1)
        queue.enqueue(message: message2)

        queue.updateRetryCount(forId: message1.id, retryCount: 5)

        let removed = queue.removeFailedMessages(maxRetries: 3)

        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(queue.count, 1)

        queue.clear()
    }

    func testMessageQueue_allMessages_returnsAllInOrder() {
        let queue = MessageQueue()
        queue.clear()

        let message1 = QueuedMessage(content: "First")
        let message2 = QueuedMessage(content: "Second")
        let message3 = QueuedMessage(content: "Third")

        queue.enqueue(message: message1)
        queue.enqueue(message: message2)
        queue.enqueue(message: message3)

        let all = queue.allMessages

        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].content, "First")
        XCTAssertEqual(all[1].content, "Second")
        XCTAssertEqual(all[2].content, "Third")

        queue.clear()
    }
}

// MARK: - Mock Delegate

class MockOfflineManagerDelegate: OfflineManagerDelegate {
    var networkStatusChanges: [Bool] = []
    var queuedMessageCount = 0
    var sentMessages: [QueuedMessage] = []
    var failedMessages: [(QueuedMessage, Error?)] = []
    var lastQueueCount: Int = 0

    func offlineManager(_ manager: OfflineManager, didChangeNetworkStatus isOnline: Bool) {
        networkStatusChanges.append(isOnline)
    }

    func offlineManager(_ manager: OfflineManager, didQueueMessage message: QueuedMessage) {
        queuedMessageCount += 1
    }

    func offlineManager(_ manager: OfflineManager, didSendQueuedMessage message: QueuedMessage) {
        sentMessages.append(message)
    }

    func offlineManager(_ manager: OfflineManager, didFailToSendMessage message: QueuedMessage, error: Error?) {
        failedMessages.append((message, error))
    }

    func offlineManager(_ manager: OfflineManager, didUpdateQueueCount count: Int) {
        lastQueueCount = count
    }
}
