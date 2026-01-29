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
    private let lock = NSLock()
    private let userDefaultsKey = "conferbot_offline_message_queue"

    /// Returns whether the queue is empty
    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return messages.isEmpty
    }

    /// Returns the number of messages in the queue
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return messages.count
    }

    /// Returns all queued messages (read-only)
    public var allMessages: [QueuedMessage] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    // MARK: - Initialization

    public init() {
        loadFromDisk()
    }

    // MARK: - Queue Operations

    /// Add a message to the queue
    /// - Parameter message: The message to enqueue
    public func enqueue(message: QueuedMessage) {
        lock.lock()
        messages.append(message)
        lock.unlock()
        persistToDisk()

        debugPrint("[ConferBot MessageQueue] Enqueued message: \(message.id), queue size: \(count)")
    }

    /// Remove and return the first message from the queue
    /// - Returns: The first message, or nil if queue is empty
    @discardableResult
    public func dequeue() -> QueuedMessage? {
        lock.lock()
        guard !messages.isEmpty else {
            lock.unlock()
            return nil
        }
        let message = messages.removeFirst()
        lock.unlock()
        persistToDisk()

        debugPrint("[ConferBot MessageQueue] Dequeued message: \(message.id), queue size: \(count)")
        return message
    }

    /// Return the first message without removing it
    /// - Returns: The first message, or nil if queue is empty
    public func peek() -> QueuedMessage? {
        lock.lock()
        defer { lock.unlock() }
        return messages.first
    }

    /// Remove a specific message from the queue by ID
    /// - Parameter id: The ID of the message to remove
    /// - Returns: The removed message, or nil if not found
    @discardableResult
    public func remove(byId id: String) -> QueuedMessage? {
        lock.lock()
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return nil
        }
        let message = messages.remove(at: index)
        lock.unlock()
        persistToDisk()

        debugPrint("[ConferBot MessageQueue] Removed message: \(id), queue size: \(count)")
        return message
    }

    /// Update the retry count for a message
    /// - Parameters:
    ///   - id: The ID of the message to update
    ///   - retryCount: The new retry count
    public func updateRetryCount(forId id: String, retryCount: Int) {
        lock.lock()
        if let index = messages.firstIndex(where: { $0.id == id }) {
            var message = messages[index]
            message.retryCount = retryCount
            messages[index] = message
        }
        lock.unlock()
        persistToDisk()
    }

    /// Clear all messages from the queue
    public func clear() {
        lock.lock()
        messages.removeAll()
        lock.unlock()
        persistToDisk()

        debugPrint("[ConferBot MessageQueue] Queue cleared")
    }

    /// Get all messages that have exceeded the retry limit
    /// - Parameter maxRetries: The maximum number of retries allowed
    /// - Returns: Messages that have exceeded the retry limit
    public func getFailedMessages(maxRetries: Int) -> [QueuedMessage] {
        lock.lock()
        defer { lock.unlock() }
        return messages.filter { $0.retryCount >= maxRetries }
    }

    /// Remove all messages that have exceeded the retry limit
    /// - Parameter maxRetries: The maximum number of retries allowed
    /// - Returns: The removed messages
    @discardableResult
    public func removeFailedMessages(maxRetries: Int) -> [QueuedMessage] {
        lock.lock()
        let failed = messages.filter { $0.retryCount >= maxRetries }
        messages.removeAll { $0.retryCount >= maxRetries }
        lock.unlock()
        persistToDisk()

        if !failed.isEmpty {
            debugPrint("[ConferBot MessageQueue] Removed \(failed.count) failed messages")
        }
        return failed
    }

    // MARK: - Persistence

    /// Save the queue to UserDefaults
    public func persistToDisk() {
        lock.lock()
        let messagesToSave = messages
        lock.unlock()

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(messagesToSave)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            UserDefaults.standard.synchronize()
            debugPrint("[ConferBot MessageQueue] Persisted \(messagesToSave.count) messages to disk")
        } catch {
            debugPrint("[ConferBot MessageQueue] Failed to persist messages: \(error)")
        }
    }

    /// Load the queue from UserDefaults
    public func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            debugPrint("[ConferBot MessageQueue] No persisted messages found")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedMessages = try decoder.decode([QueuedMessage].self, from: data)

            lock.lock()
            messages = loadedMessages
            lock.unlock()

            debugPrint("[ConferBot MessageQueue] Loaded \(loadedMessages.count) messages from disk")
        } catch {
            debugPrint("[ConferBot MessageQueue] Failed to load messages: \(error)")
        }
    }

    // MARK: - Debug

    private func debugPrint(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
