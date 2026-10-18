//
//  MessageQueue.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation

/// Represents a message that has been queued for sending while offline
public struct QueuedMessage: Codable, Identifiable, Equatable {
    public let id: String
    public let content: String
    public let timestamp: Date
    public var retryCount: Int
    public let metadata: [String: AnyCodable]?
    public let chatSessionId: String?

    public init(
        id: String = UUID().uuidString,
        content: String,
        timestamp: Date = Date(),
        retryCount: Int = 0,
        metadata: [String: AnyCodable]? = nil,
        chatSessionId: String? = nil
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.metadata = metadata
        self.chatSessionId = chatSessionId
    }

    public static func == (lhs: QueuedMessage, rhs: QueuedMessage) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Thread-safe message queue for offline message handling
/// Persists messages to UserDefaults so they survive app restart
public class MessageQueue {

    // MARK: - Properties

    private var messages: [QueuedMessage] = []
    /// Guards `messages` and its write to UserDefaults together: a change and
    /// its save happen as one step, so saves land in the order of the changes
    /// and the saved queue is the queue in memory. Recursive, so code that a
    /// save calls back into (a UserDefaults observer) can use the queue too.
    private let lock = NSRecursiveLock()
    private let userDefaultsKey = "conferbot_offline_message_queue"

    /// Returns whether the queue is empty
    public var isEmpty: Bool {
        withLock { messages.isEmpty }
    }

    /// Returns the number of messages in the queue
    public var count: Int {
        withLock { messages.count }
    }

    /// Returns all queued messages (read-only)
    public var allMessages: [QueuedMessage] {
        withLock { messages }
    }

    // MARK: - Initialization

    public init() {
        loadFromDisk()
    }

    // MARK: - Locking

    /// Runs `body` under the lock. Synchronous, so it is safe to call from
    /// async code (the lock is never held across a suspension point).
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Changes the queue and, when `body` says it changed, saves it, all
    /// under the lock.
    private func mutate<T>(_ body: (inout [QueuedMessage]) -> (result: T, changed: Bool)) -> T {
        withLock {
            let outcome = body(&messages)
            if outcome.changed { writeLocked() }
            return outcome.result
        }
    }

    // MARK: - Queue Operations

    /// Add a message to the queue
    /// - Parameter message: The message to enqueue
    public func enqueue(message: QueuedMessage) {
        let size: Int = mutate { messages in
            messages.append(message)
            return (messages.count, true)
        }

        debugPrint("[ConferBot MessageQueue] Enqueued message: \(message.id), queue size: \(size)")
    }

    /// Remove and return the first message from the queue
    /// - Returns: The first message, or nil if queue is empty
    @discardableResult
    public func dequeue() -> QueuedMessage? {
        let (message, size): (QueuedMessage?, Int) = mutate { messages in
            guard !messages.isEmpty else { return ((nil, 0), false) }
            let first = messages.removeFirst()
            return ((first, messages.count), true)
        }

        if let message = message {
            debugPrint("[ConferBot MessageQueue] Dequeued message: \(message.id), queue size: \(size)")
        }
        return message
    }

    /// Return the first message without removing it
    /// - Returns: The first message, or nil if queue is empty
    public func peek() -> QueuedMessage? {
        withLock { messages.first }
    }

    /// Remove a specific message from the queue by ID
    /// - Parameter id: The ID of the message to remove
    /// - Returns: The removed message, or nil if not found
    @discardableResult
    public func remove(byId id: String) -> QueuedMessage? {
        let (message, size): (QueuedMessage?, Int) = mutate { messages in
            guard let index = messages.firstIndex(where: { $0.id == id }) else {
                return ((nil, messages.count), false)
            }
            let removed = messages.remove(at: index)
            return ((removed, messages.count), true)
        }

        if message != nil {
            debugPrint("[ConferBot MessageQueue] Removed message: \(id), queue size: \(size)")
        }
        return message
    }

    /// Update the retry count for a message
    /// - Parameters:
    ///   - id: The ID of the message to update
    ///   - retryCount: The new retry count
    public func updateRetryCount(forId id: String, retryCount: Int) {
        mutate { messages in
            if let index = messages.firstIndex(where: { $0.id == id }) {
                messages[index].retryCount = retryCount
            }
            return ((), true)
        }
    }

    /// Clear all messages from the queue
    public func clear() {
        mutate { messages in
            messages.removeAll()
            return ((), true)
        }

        debugPrint("[ConferBot MessageQueue] Queue cleared")
    }

    /// Get all messages that have exceeded the retry limit
    /// - Parameter maxRetries: The maximum number of retries allowed
    /// - Returns: Messages that have exceeded the retry limit
    public func getFailedMessages(maxRetries: Int) -> [QueuedMessage] {
        withLock { messages.filter { $0.retryCount >= maxRetries } }
    }

    /// Remove all messages that have exceeded the retry limit
    /// - Parameter maxRetries: The maximum number of retries allowed
    /// - Returns: The removed messages
    @discardableResult
    public func removeFailedMessages(maxRetries: Int) -> [QueuedMessage] {
        let failed: [QueuedMessage] = mutate { messages in
            let failed = messages.filter { $0.retryCount >= maxRetries }
            messages.removeAll { $0.retryCount >= maxRetries }
            return (failed, true)
        }

        if !failed.isEmpty {
            debugPrint("[ConferBot MessageQueue] Removed \(failed.count) failed messages")
        }
        return failed
    }

    // MARK: - Persistence

    /// Save the queue to UserDefaults
    public func persistToDisk() {
        withLock { writeLocked() }
    }

    /// Writes `messages` to UserDefaults. The caller holds the lock, so no
    /// change can land between the snapshot and the write.
    private func writeLocked() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(messages)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            UserDefaults.standard.synchronize()
            debugPrint("[ConferBot MessageQueue] Persisted \(messages.count) messages to disk")
        } catch {
            debugPrint("[ConferBot MessageQueue] Failed to persist messages: \(error)")
        }
    }

    /// Load the queue from UserDefaults
    public func loadFromDisk() {
        withLock {
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
                debugPrint("[ConferBot MessageQueue] No persisted messages found")
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                messages = try decoder.decode([QueuedMessage].self, from: data)
                debugPrint("[ConferBot MessageQueue] Loaded \(messages.count) messages from disk")
            } catch {
                debugPrint("[ConferBot MessageQueue] Failed to load messages: \(error)")
            }
        }
    }

    // MARK: - Debug

    private func debugPrint(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
