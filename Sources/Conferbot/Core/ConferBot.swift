//
//  ConferBot.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation
import Combine
import UIKit

/// ConferBot delegate protocol for event callbacks
public protocol ConferBotDelegate: AnyObject {
    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem)
    func conferBot(_ conferBot: ConferBot, agentDidJoin agent: Agent)
    func conferBot(_ conferBot: ConferBot, agentDidLeave agent: Agent)
    func conferBot(_ conferBot: ConferBot, didStartSession sessionId: String)
    func conferBot(_ conferBot: ConferBot, didEndSession sessionId: String)
    func conferBot(_ conferBot: ConferBot, didUpdateUnreadCount count: Int)
    func conferBot(_ conferBot: ConferBot, didChangeConnectionStatus isConnected: Bool)
}

/// Main ConferBot SDK class (Singleton)
public class ConferBot: ObservableObject {
    public static let shared = ConferBot()

    // Published properties for SwiftUI
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var currentSession: ChatSession?
    @Published public private(set) var messages: [any RecordItem] = []
    @Published public private(set) var unreadCount: Int = 0
    @Published public private(set) var isAgentTyping: Bool = false

    // Configuration
    private var apiKey: String?
    private var botId: String?
    private var config: ConferBotConfig?
    public var customization: ConferBotCustomization?
    private var currentUser: ConferBotUser?

    // Clients
    private var apiClient: APIClient?
    private var socketClient: SocketClient?

    // Delegate
    public weak var delegate: ConferBotDelegate?

    // Push token
    private var pushToken: String?

    private init() {}

    /// Initialize the SDK
    public func initialize(
        apiKey: String,
        botId: String,
        config: ConferBotConfig = ConferBotConfig(),
        customization: ConferBotCustomization? = nil
    ) {
        self.apiKey = apiKey
        self.botId = botId
        self.config = config
        self.customization = customization

        // Initialize API client
        self.apiClient = APIClient(
            apiKey: apiKey,
            botId: botId,
            baseURL: config.apiBaseURL
        )

        // Initialize Socket client
        self.socketClient = SocketClient(
            apiKey: apiKey,
            botId: botId,
            socketURL: config.socketURL
        )

        setupSocketListeners()
        connectSocket()

        debugPrint("[ConferBot] Initialized with botId: \(botId)")
    }

    /// Identify current user
    public func identify(user: ConferBotUser) {
        self.currentUser = user
        debugPrint("[ConferBot] User identified: \(user.id)")
    }

    /// Start a new chat session
    public func startSession() async throws {
        guard let apiClient = apiClient else {
            throw ConferBotError.notInitialized
        }

        let session = try await apiClient.initSession(userId: currentUser?.id)

        await MainActor.run {
            self.currentSession = session
            self.messages = session.record.map { $0.value }
            delegate?.conferBot(self, didStartSession: session.chatSessionId)
        }

        // Join chat room as visitor (matches embed-server 'join-chat-room-visitor' event)
        socketClient?.joinChatRoomVisitor(
            chatSessionId: session.chatSessionId,
            deviceInfo: getDeviceInfo()
        )

        debugPrint("[ConferBot] Session started: \(session.chatSessionId)")
    }

    /// Send a message
    public func sendMessage(_ text: String, metadata: [String: AnyCodable]? = nil) async throws {
        guard let session = currentSession else {
            throw ConferBotError.notInitialized
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        // Create user message record
        let messageId = UUID().uuidString
        let userMessage = UserMessageRecord(
            id: messageId,
            time: Date(),
            text: text,
            metadata: metadata
        )

        // Add to local messages immediately
        await MainActor.run {
            messages.append(userMessage)
        }

        // Send via socket using response-record event (matches embed-server)
        let record: [String: Any] = [
            "_id": messageId,
            "type": "user-input-response",
            "text": text,
            "time": ISO8601DateFormatter().string(from: Date())
        ]

        // Get all messages as records for the full conversation history
        var allRecords: [[String: Any]] = messages.compactMap { msg -> [String: Any]? in
            if let userMsg = msg as? UserMessageRecord {
                return [
                    "_id": userMsg.id,
                    "type": "user-message",
                    "text": userMsg.text,
                    "time": ISO8601DateFormatter().string(from: userMsg.time)
                ]
            } else if let userInputMsg = msg as? UserInputResponseRecord {
                return [
                    "_id": userInputMsg.id,
                    "type": "user-input-response",
                    "text": userInputMsg.text,
                    "time": ISO8601DateFormatter().string(from: userInputMsg.time)
                ]
            }
            return nil
        }
        allRecords.append(record)

        socketClient?.sendResponseRecord(
            chatSessionId: session.chatSessionId,
            record: allRecords,
            answerVariables: []
        )

        debugPrint("[ConferBot] Message sent: \(text)")
    }

    /// Send typing indicator
    public func sendTypingIndicator(isTyping: Bool) {
        guard let session = currentSession else { return }
        socketClient?.sendTypingStatus(chatSessionId: session.chatSessionId, isTyping: isTyping)
    }

    /// Initiate handover to live agent
    public func initiateHandover(message: String? = nil) {
        guard let session = currentSession else { return }
        socketClient?.initiateHandover(chatSessionId: session.chatSessionId, message: message)
    }

    /// End current session
    public func endSession() {
        guard let session = currentSession else { return }

        socketClient?.leaveChatRoom(chatSessionId: session.chatSessionId)
        socketClient?.endChat(chatSessionId: session.chatSessionId)

        delegate?.conferBot(self, didEndSession: session.chatSessionId)

        currentSession = nil
        messages = []
        unreadCount = 0

        debugPrint("[ConferBot] Session ended: \(session.chatSessionId)")
    }

    /// Register push notification token
    public func registerPushToken(_ token: String) {
        self.pushToken = token

        guard let session = currentSession,
              let apiClient = apiClient else {
            // Store token for later registration
            return
        }

        Task {
            try? await apiClient.registerPushToken(token: token, chatSessionId: session.chatSessionId)
            debugPrint("[ConferBot] Push token registered")
        }
    }

    /// Handle push notification
    public func handlePushNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard userInfo["type"] as? String == "conferbot_message" else {
            return false
        }

        // Increment unread count
        unreadCount += 1
        delegate?.conferBot(self, didUpdateUnreadCount: unreadCount)

        return true
    }

    /// Get unread message count
    public func getUnreadCount() -> Int {
        return unreadCount
    }

    /// Clear chat history
    public func clearHistory() {
        messages = []
        unreadCount = 0
    }

    /// Present chat view controller modally (UIKit)
    public func present(from viewController: UIViewController, animated: Bool = true) {
        let chatVC = ChatViewController()
        let navController = UINavigationController(rootViewController: chatVC)
        navController.modalPresentationStyle = .fullScreen
        viewController.present(navController, animated: animated)
    }

    // MARK: - Private Methods

    private func connectSocket() {
        socketClient?.connect()
    }

    private func setupSocketListeners() {
        // Connection status
        socketClient?.on(SocketEvents.connect) { [weak self] _, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.isConnected = true
                self.delegate?.conferBot(self, didChangeConnectionStatus: true)
            }
        }

        socketClient?.on(SocketEvents.disconnect) { [weak self] _, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.isConnected = false
                self.delegate?.conferBot(self, didChangeConnectionStatus: false)
            }
        }

        // Bot response
        socketClient?.on(SocketEvents.botResponse) { [weak self] data, _ in
            self?.handleBotResponse(data: data)
        }

        // Agent message
        socketClient?.on(SocketEvents.agentMessage) { [weak self] data, _ in
            self?.handleAgentMessage(data: data)
        }

        // Agent joined
        socketClient?.on(SocketEvents.agentAccepted) { [weak self] data, _ in
            self?.handleAgentJoined(data: data)
        }

        // Agent left
        socketClient?.on(SocketEvents.agentLeft) { [weak self] data, _ in
            self?.handleAgentLeft(data: data)
        }

        // Agent typing
        socketClient?.on(SocketEvents.agentTypingStatus) { [weak self] data, _ in
            self?.handleAgentTyping(data: data)
        }

        // Chat ended
        socketClient?.on(SocketEvents.chatEnded) { [weak self] _, _ in
            self?.endSession()
        }
    }

    private func handleBotResponse(data: [Any]) {
        guard let json = data.first as? [String: Any],
              let recordData = json["record"] as? [String: Any] else {
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: recordData)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let message = try decoder.decode(AnyRecordItem.self, from: jsonData)

            Task { @MainActor in
                self.messages.append(message.value)
                self.delegate?.conferBot(self, didReceiveMessage: message.value)
            }
        } catch {
            debugPrint("[ConferBot] Failed to decode bot response: \(error)")
        }
    }

    private func handleAgentMessage(data: [Any]) {
        guard let json = data.first as? [String: Any],
              let recordData = json["record"] as? [String: Any] else {
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: recordData)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let message = try decoder.decode(AnyRecordItem.self, from: jsonData)

            Task { @MainActor in
                self.messages.append(message.value)
                self.unreadCount += 1
                self.delegate?.conferBot(self, didReceiveMessage: message.value)
                self.delegate?.conferBot(self, didUpdateUnreadCount: self.unreadCount)
            }
        } catch {
            debugPrint("[ConferBot] Failed to decode agent message: \(error)")
        }
    }

    private func handleAgentJoined(data: [Any]) {
        // embed-server sends 'agentDetails' not 'agent'
        guard let json = data.first as? [String: Any],
              let agentData = json["agentDetails"] as? [String: Any] else {
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: agentData)
            let agentDetails = try JSONDecoder().decode(AgentDetails.self, from: jsonData)

            // Map AgentDetails to Agent
            let agent = Agent(
                id: agentDetails.id,
                name: agentDetails.name,
                email: agentDetails.email
            )

            Task { @MainActor in
                self.delegate?.conferBot(self, agentDidJoin: agent)
            }
        } catch {
            debugPrint("[ConferBot] Failed to decode agent: \(error)")
        }
    }

    private func handleAgentLeft(data: [Any]) {
        // embed-server sends 'agentDetails' not 'agent'
        guard let json = data.first as? [String: Any],
              let agentData = json["agentDetails"] as? [String: Any] else {
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: agentData)
            let agentDetails = try JSONDecoder().decode(AgentDetails.self, from: jsonData)

            // Map AgentDetails to Agent
            let agent = Agent(
                id: agentDetails.id,
                name: agentDetails.name,
                email: agentDetails.email
            )

            Task { @MainActor in
                self.delegate?.conferBot(self, agentDidLeave: agent)
            }
        } catch {
            debugPrint("[ConferBot] Failed to decode agent: \(error)")
        }
    }

    private func handleAgentTyping(data: [Any]) {
        guard let json = data.first as? [String: Any],
              let isTyping = json["isTyping"] as? Bool else {
            return
        }

        Task { @MainActor in
            self.isAgentTyping = isTyping
        }
    }

    private func getDeviceInfo() -> [String: Any] {
        let device = UIDevice.current
        return [
            "platform": "iOS",
            "osVersion": device.systemVersion,
            "model": device.model,
            "deviceId": device.identifierForVendor?.uuidString ?? ""
        ]
    }

    private func debugPrint(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    /// Disconnect socket
    public func disconnect() {
        socketClient?.disconnect()
        isConnected = false
    }
}
