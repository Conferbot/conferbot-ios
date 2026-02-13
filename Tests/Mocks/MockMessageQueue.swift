//
//  MockMessageQueue.swift
//  ConferbotTests
//
//  Mock MessageQueue for testing OfflineManager without persistence.
//

import Foundation
@testable import Conferbot

/// Mock MessageQueue that does not persist to UserDefaults
class MockMessageQueue {

    // MARK: - Properties

    private var messages: [QueuedMessage] = []
    private let lock = NSLock()

    // Tracking for test verification
    var enqueueCalls: [QueuedMessage] = []
    var dequeueCalls: Int = 0
    var clearCalls: Int = 0
    var persistCalls: Int = 0
    var loadCalls: Int = 0

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return messages.isEmpty
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return messages.count
    }

    var allMessages: [QueuedMessage] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    // MARK: - Queue Operations

    func enqueue(message: QueuedMessage) {
        lock.lock()
        messages.append(message)
        enqueueCalls.append(message)
        lock.unlock()
    }

    @discardableResult
    func dequeue() -> QueuedMessage? {
        lock.lock()
        guard !messages.isEmpty else {
            lock.unlock()
            return nil
        }
        let message = messages.removeFirst()
        dequeueCalls += 1
        lock.unlock()
        return message
    }

    func peek() -> QueuedMessage? {
        lock.lock()
        defer { lock.unlock() }
        return messages.first
    }

    @discardableResult
    func remove(byId id: String) -> QueuedMessage? {
        lock.lock()
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return nil
        }
        let message = messages.remove(at: index)
        lock.unlock()
        return message
    }

    func updateRetryCount(forId id: String, retryCount: Int) {
        lock.lock()
        if let index = messages.firstIndex(where: { $0.id == id }) {
            var message = messages[index]
            message.retryCount = retryCount
            messages[index] = message
        }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        messages.removeAll()
        clearCalls += 1
        lock.unlock()
    }

    func getFailedMessages(maxRetries: Int) -> [QueuedMessage] {
        lock.lock()
        defer { lock.unlock() }
        return messages.filter { $0.retryCount >= maxRetries }
    }

    @discardableResult
    func removeFailedMessages(maxRetries: Int) -> [QueuedMessage] {
        lock.lock()
        let failed = messages.filter { $0.retryCount >= maxRetries }
        messages.removeAll { $0.retryCount >= maxRetries }
        lock.unlock()
        return failed
    }

    func persistToDisk() {
        persistCalls += 1
        // No-op for mock
    }

    func loadFromDisk() {
        loadCalls += 1
        // No-op for mock
    }

    // MARK: - Test Helpers

    func reset() {
        lock.lock()
        messages.removeAll()
        enqueueCalls.removeAll()
        dequeueCalls = 0
        clearCalls = 0
        persistCalls = 0
        loadCalls = 0
        lock.unlock()
    }

    /// Add messages directly for testing
    func setMessages(_ messages: [QueuedMessage]) {
        lock.lock()
        self.messages = messages
        lock.unlock()
    }
}
