//
//  OfflineManager.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation
#if canImport(Network)
import Network
#endif
import Combine

/// Delegate protocol for offline manager events
public protocol OfflineManagerDelegate: AnyObject {
    func offlineManager(_ manager: OfflineManager, didChangeNetworkStatus isOnline: Bool)
    func offlineManager(_ manager: OfflineManager, didQueueMessage message: QueuedMessage)
    func offlineManager(_ manager: OfflineManager, didSendQueuedMessage message: QueuedMessage)
    func offlineManager(_ manager: OfflineManager, didFailToSendMessage message: QueuedMessage, error: Error?)
    func offlineManager(_ manager: OfflineManager, didUpdateQueueCount count: Int)
}

/// Default implementations for delegate methods
public extension OfflineManagerDelegate {
    func offlineManager(_ manager: OfflineManager, didChangeNetworkStatus isOnline: Bool) {}
    func offlineManager(_ manager: OfflineManager, didQueueMessage message: QueuedMessage) {}
    func offlineManager(_ manager: OfflineManager, didSendQueuedMessage message: QueuedMessage) {}
    func offlineManager(_ manager: OfflineManager, didFailToSendMessage message: QueuedMessage, error: Error?) {}
    func offlineManager(_ manager: OfflineManager, didUpdateQueueCount count: Int) {}
}

/// Error types for offline operations
public enum OfflineManagerError: Error, LocalizedError {
    case networkUnavailable
    case maxRetriesExceeded
    case socketNotConnected
    case messageEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network is unavailable"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded"
        case .socketNotConnected:
            return "Socket is not connected"
        case .messageEncodingFailed:
            return "Failed to encode message"
        }
    }
}

/// Manages offline message queueing and automatic sending when back online
public class OfflineManager: ObservableObject {

    // MARK: - Singleton

    public static let shared = OfflineManager()

    // MARK: - Published Properties

    /// Current online status
    @Published public private(set) var isOnline: Bool = true

    /// Number of messages currently queued
    @Published public private(set) var queuedMessageCount: Int = 0

    /// Whether we're currently flushing the queue
    @Published public private(set) var isFlushing: Bool = false

    // MARK: - Configuration

    /// Maximum number of retry attempts for failed messages
    public var maxRetries: Int = 3

    /// Delay between retry attempts (in seconds)
    public var retryDelay: TimeInterval = 2.0

    /// Whether to automatically flush queue when coming online
    public var autoFlushOnReconnect: Bool = true

    // MARK: - Properties

    public weak var delegate: OfflineManagerDelegate?

    private let messageQueue: MessageQueue
    private let networkMonitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    private var socketConnected: Bool = false
    private var flushTask: Task<Void, Never>?

    /// Callback for sending messages (set by ConferBot)
    internal var sendMessageHandler: ((QueuedMessage) async throws -> Void)?

    // MARK: - Initialization

    private init() {
        messageQueue = MessageQueue()
        networkMonitor = NWPathMonitor()
        monitorQueue = DispatchQueue(label: "com.conferbot.networkMonitor")

        queuedMessageCount = messageQueue.count

        startNetworkMonitoring()
        debugPrint("[ConferBot OfflineManager] Initialized with \(queuedMessageCount) queued messages")
    }

    deinit {
        stopNetworkMonitoring()
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let wasOnline = self.isOnline
            let nowOnline = path.status == .satisfied

            DispatchQueue.main.async {
                self.isOnline = nowOnline
            }

            if nowOnline != wasOnline {
                self.debugPrint("[ConferBot OfflineManager] Network status changed: \(nowOnline ? "online" : "offline")")
                self.delegate?.offlineManager(self, didChangeNetworkStatus: nowOnline)

                // Auto-flush when coming back online
                if nowOnline && self.autoFlushOnReconnect {
                    self.flushQueueWhenReady()
                }
            }
        }

        networkMonitor.start(queue: monitorQueue)
    }

    private func stopNetworkMonitoring() {
        networkMonitor.cancel()
    }

    // MARK: - Socket Connection State

    /// Called when socket connects
    public func handleSocketConnected() {
        socketConnected = true
        debugPrint("[ConferBot OfflineManager] Socket connected")

        if autoFlushOnReconnect && isOnline {
            flushQueue()
        }
    }

    /// Called when socket disconnects
    public func handleSocketDisconnected() {
        socketConnected = false
        debugPrint("[ConferBot OfflineManager] Socket disconnected")
    }

    // MARK: - Queue Operations

    /// Queue a message for later sending
    /// - Parameters:
    ///   - content: The message content
    ///   - metadata: Optional metadata
    ///   - chatSessionId: The chat session ID
    /// - Returns: The queued message
    @discardableResult
    public func queueMessage(
        content: String,
        metadata: [String: AnyCodable]? = nil,
        chatSessionId: String? = nil
    ) -> QueuedMessage {
        let message = QueuedMessage(
            content: content,
            metadata: metadata,
            chatSessionId: chatSessionId
        )

        messageQueue.enqueue(message: message)

        DispatchQueue.main.async {
            self.queuedMessageCount = self.messageQueue.count
        }

        delegate?.offlineManager(self, didQueueMessage: message)
        delegate?.offlineManager(self, didUpdateQueueCount: messageQueue.count)

        debugPrint("[ConferBot OfflineManager] Message queued: \(message.id)")

        return message
    }

    /// Check if we can send messages (online and socket connected)
    public var canSendMessages: Bool {
        return isOnline && socketConnected
    }

    /// Flush the message queue (send all queued messages)
    public func flushQueue() {
        guard !isFlushing else {
            debugPrint("[ConferBot OfflineManager] Already flushing queue")
            return
        }

        guard canSendMessages else {
            debugPrint("[ConferBot OfflineManager] Cannot flush - not connected")
            return
        }

        guard !messageQueue.isEmpty else {
            debugPrint("[ConferBot OfflineManager] Queue is empty")
            return
        }

        flushTask?.cancel()
        flushTask = Task { @MainActor in
            await performFlush()
        }
    }

    /// Flush queue when both network and socket are ready
    private func flushQueueWhenReady() {
        // Wait a short delay to allow socket to reconnect
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.canSendMessages else { return }
            self.flushQueue()
        }
    }

    @MainActor
    private func performFlush() async {
        guard !messageQueue.isEmpty else { return }

        isFlushing = true
        debugPrint("[ConferBot OfflineManager] Starting queue flush (\(messageQueue.count) messages)")

        while let message = messageQueue.peek(), canSendMessages {
            do {
                // Attempt to send the message
                if let handler = sendMessageHandler {
                    try await handler(message)
                }

                // Remove from queue on success
                messageQueue.dequeue()
                queuedMessageCount = messageQueue.count

                delegate?.offlineManager(self, didSendQueuedMessage: message)
                delegate?.offlineManager(self, didUpdateQueueCount: messageQueue.count)

                debugPrint("[ConferBot OfflineManager] Successfully sent queued message: \(message.id)")

            } catch {
                // Increment retry count
                let newRetryCount = message.retryCount + 1
                messageQueue.updateRetryCount(forId: message.id, retryCount: newRetryCount)

                debugPrint("[ConferBot OfflineManager] Failed to send message: \(message.id), retry: \(newRetryCount)/\(maxRetries)")

                if newRetryCount >= maxRetries {
                    // Remove message after max retries
                    messageQueue.remove(byId: message.id)
                    queuedMessageCount = messageQueue.count

                    delegate?.offlineManager(self, didFailToSendMessage: message, error: error)
                    delegate?.offlineManager(self, didUpdateQueueCount: messageQueue.count)

                    debugPrint("[ConferBot OfflineManager] Message exceeded max retries, removed: \(message.id)")
                } else {
                    // Wait before retrying
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))

                    // If we're no longer online, stop flushing
                    if !canSendMessages {
                        break
                    }
                }
            }
        }

        isFlushing = false
        debugPrint("[ConferBot OfflineManager] Queue flush completed, remaining: \(messageQueue.count)")
    }

    /// Retry all failed messages (resets their retry count)
    public func retryFailedMessages() {
        let failedMessages = messageQueue.getFailedMessages(maxRetries: maxRetries)

        for message in failedMessages {
            messageQueue.updateRetryCount(forId: message.id, retryCount: 0)
        }

        if !failedMessages.isEmpty {
            debugPrint("[ConferBot OfflineManager] Reset retry count for \(failedMessages.count) messages")
            flushQueue()
        }
    }

    /// Clear all queued messages
    public func clearQueue() {
        messageQueue.clear()

        DispatchQueue.main.async {
            self.queuedMessageCount = 0
        }

        delegate?.offlineManager(self, didUpdateQueueCount: 0)
    }

    /// Get all currently queued messages
    public var queuedMessages: [QueuedMessage] {
        return messageQueue.allMessages
    }

    /// Remove a specific message from the queue
    /// - Parameter id: The ID of the message to remove
    @discardableResult
    public func removeMessage(byId id: String) -> QueuedMessage? {
        let message = messageQueue.remove(byId: id)

        if message != nil {
            DispatchQueue.main.async {
                self.queuedMessageCount = self.messageQueue.count
            }
            delegate?.offlineManager(self, didUpdateQueueCount: messageQueue.count)
        }

        return message
    }

    // MARK: - Debug

    private func debugPrint(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
