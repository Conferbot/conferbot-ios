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
    func conferBot(_ conferBot: ConferBot, didUpdateUIState state: NodeUIState?)
    func conferBot(_ conferBot: ConferBot, didCompleteFlow success: Bool)
    func conferBot(_ conferBot: ConferBot, didReachGoal goalName: String, value: Any?)
}

/// Default implementations for new delegate methods
public extension ConferBotDelegate {
    func conferBot(_ conferBot: ConferBot, didUpdateUIState state: NodeUIState?) {}
    func conferBot(_ conferBot: ConferBot, didCompleteFlow success: Bool) {}
    func conferBot(_ conferBot: ConferBot, didReachGoal goalName: String, value: Any?) {}
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

    // Node Flow Engine - Published properties
    @Published public private(set) var currentUIState: NodeUIState?
    @Published public private(set) var isProcessingNode: Bool = false
    @Published public private(set) var nodeErrorMessage: String?
    @Published public private(set) var isFlowComplete: Bool = false

    // Configuration
    private var apiKey: String?
    private var botId: String?
    private var config: ConferBotConfig?
    public var customization: ConferBotCustomization?
    private var currentUser: ConferBotUser?

    // Clients
    private var apiClient: APIClient?
    private var socketClient: SocketClient?

    // Node Flow Engine
    private var flowEngine: NodeFlowEngine?
    private var flowEngineCancellables = Set<AnyCancellable>()

    // Delegate
    public weak var delegate: ConferBotDelegate?

    // Push token
    private var pushToken: String?

    // Chat State
    public var chatState: ChatState {
        return ChatState.shared
    }

    private init() {
        setupFlowEngine()
    }

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

        // Register all node handlers
        registerAllNodeHandlers()

        setupSocketListeners()
        connectSocket()

        debugPrint("[ConferBot] Initialized with botId: \(botId)")
    }

    // MARK: - Flow Engine Setup

    private func setupFlowEngine() {
        flowEngine = NodeFlowEngine()

        // Subscribe to flow engine state changes
        flowEngine?.$currentUIState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.currentUIState = state
                self?.delegate?.conferBot(self!, didUpdateUIState: state)
            }
            .store(in: &flowEngineCancellables)

        flowEngine?.$isProcessing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isProcessingNode)

        flowEngine?.$errorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$nodeErrorMessage)

        flowEngine?.$isFlowComplete
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isComplete in
                self?.isFlowComplete = isComplete
                if isComplete {
                    self?.delegate?.conferBot(self!, didCompleteFlow: true)
                }
            }
            .store(in: &flowEngineCancellables)
    }

    private func registerAllNodeHandlers() {
        let registry = NodeHandlerRegistry.shared

        // Register Display Node Handlers
        registry.register(SendMessageHandler())
        registry.register(SendImageHandler())
        registry.register(SendVideoHandler())
        registry.register(SendAudioHandler())
        registry.register(SendFileHandler())
        registry.register(SendGifHandler())

        // Ask Input Handlers
        registry.register(AskNameHandler())
        registry.register(AskEmailHandler())
        registry.register(AskPhoneHandler())
        registry.register(AskNumberHandler())
        registry.register(AskUrlHandler())
        registry.register(AskAddressHandler())
        registry.register(AskDateHandler())
        registry.register(AskTimeHandler())
        registry.register(AskDateTimeHandler())
        registry.register(AskDateRangeHandler())
        registry.register(AskFileUploadHandler())
        registry.register(AskQuestionHandler())

        // Choice Handlers
        registry.register(SendButtonsHandler())
        registry.register(SendQuickRepliesHandler())
        registry.register(SendCardsHandler())

        // Rating Handlers
        registry.register(AskRatingHandler())
        registry.register(OpinionScaleHandler())

        // Special Display Handlers
        registry.register(LiveChatHandler())
        registry.register(SendLinkHandler())
        registry.register(EmbedLinkHandler())
        registry.register(EmbedCustomCodeHandler())

        // Logic Node Handlers
        registry.register(RedirectUrlHandler())
        registry.register(SetVariableHandler())
        registry.register(JavaScriptFunctionHandler())
        registry.register(ConditionalHandler())
        registry.register(ABTestHandler())
        registry.register(SplitConversationHandler())
        registry.register(LogicDelayHandler())

        // Integration Node Handlers
        registry.register(WebhookHandler())
        registry.register(GoogleSheetsHandler())
        registry.register(SendEmailHandler())
        registry.register(CalendlyHandler())
        registry.register(HubspotHandler())
        registry.register(SalesforceHandler())
        registry.register(ZendeskHandler())
        registry.register(SlackHandler())
        registry.register(ZapierHandler())
        registry.register(DialogflowHandler())
        registry.register(OpenAIHandler())
        registry.register(GeminiHandler())
        registry.register(PerplexityHandler())
        registry.register(ClaudeHandler())
        registry.register(GroqHandler())
        registry.register(CustomLLMHandler())
        registry.register(HumanHandoverHandler())

        // Special Flow Handlers
        registry.register(GoalHandler())
        registry.register(EndConversationHandler())

        debugPrint("[ConferBot] Registered \(registry.count) node handlers")
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

    // MARK: - Node Flow Engine Methods

    /// Load and start a chatbot flow
    public func loadFlow(_ flowData: [String: Any]) {
        flowEngine?.loadFlow(flowData)

        // Initialize chat state with flow data
        if let variables = flowData["variables"] as? [String: Any] {
            for (key, value) in variables {
                chatState.setVariable(name: key, value: value)
            }
        }

        debugPrint("[ConferBot] Flow loaded")
    }

    /// Start processing the loaded flow
    public func startFlow() {
        guard flowEngine != nil else {
            debugPrint("[ConferBot] No flow loaded")
            return
        }

        isFlowComplete = false
        Task {
            await flowEngine?.startFlow()
        }

        debugPrint("[ConferBot] Flow started")
    }

    /// Handle user input for the current node
    public func handleNodeInput(_ input: Any, forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }

        // Store the answer in chat state
        chatState.setAnswer(nodeId: nodeId, value: input)

        // Add user response to transcript
        let transcript: [String: Any] = [
            "type": "user-input",
            "nodeId": nodeId,
            "value": input,
            "time": ISO8601DateFormatter().string(from: Date())
        ]
        chatState.addToTranscript(entry: transcript)

        // Process the input
        Task {
            await flowEngine.handleUserInput(input, forNodeId: nodeId)
        }

        debugPrint("[ConferBot] Node input handled for node: \(nodeId)")
    }

    /// Handle button click from node UI
    public func handleButtonClick(buttonId: String, forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }

        // Store button selection
        chatState.setAnswer(nodeId: nodeId, value: buttonId)

        Task {
            await flowEngine.handleButtonClick(buttonId: buttonId, forNodeId: nodeId)
        }

        debugPrint("[ConferBot] Button clicked: \(buttonId) for node: \(nodeId)")
    }

    /// Handle choice selection from node UI
    public func handleChoiceSelection(optionId: String, forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }

        // Store choice selection
        chatState.setAnswer(nodeId: nodeId, value: optionId)

        Task {
            await flowEngine.handleChoiceSelection(optionId: optionId, forNodeId: nodeId)
        }

        debugPrint("[ConferBot] Choice selected: \(optionId) for node: \(nodeId)")
    }

    /// Handle multiple choice selections
    public func handleMultipleChoiceSelection(optionIds: [String], forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }

        // Store selections
        chatState.setAnswer(nodeId: nodeId, value: optionIds)

        // Use first selection for edge routing
        if let firstOption = optionIds.first {
            Task {
                await flowEngine.handleChoiceSelection(optionId: firstOption, forNodeId: nodeId)
            }
        }

        debugPrint("[ConferBot] Multiple choices selected: \(optionIds) for node: \(nodeId)")
    }

    /// Handle rating selection
    public func handleRatingSelection(rating: Int, forNodeId nodeId: String) {
        handleNodeInput(rating, forNodeId: nodeId)
    }

    /// Handle date/time selection
    public func handleDateSelection(date: Date, forNodeId nodeId: String) {
        let formatter = ISO8601DateFormatter()
        handleNodeInput(formatter.string(from: date), forNodeId: nodeId)
    }

    /// Handle file upload completion
    public func handleFileUpload(fileURL: URL, forNodeId nodeId: String) {
        handleNodeInput(fileURL.absoluteString, forNodeId: nodeId)
    }

    /// Get current node ID being processed
    public func getCurrentNodeId() -> String? {
        return flowEngine?.currentNodeId
    }

    /// Check if a specific node type requires user interaction
    public func nodeRequiresInteraction(_ nodeType: String) -> Bool {
        return NodeTypes.requiresUserInteraction(nodeType)
    }

    /// Emit socket event (for integration nodes)
    public func emitSocketEvent(_ event: String, data: [String: Any]) {
        guard let session = currentSession else { return }

        var eventData = data
        eventData["chatSessionId"] = session.chatSessionId

        socketClient?.emit(event: event, data: eventData)
        debugPrint("[ConferBot] Socket event emitted: \(event)")
    }

    /// Reset flow state
    public func resetFlow() {
        chatState.reset()
        isFlowComplete = false
        currentUIState = nil
        nodeErrorMessage = nil
        debugPrint("[ConferBot] Flow state reset")
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
        guard let json = data.first as? [String: Any] else {
            return
        }

        // Check if this is a flow-based response with node data
        if let flowData = json["flow"] as? [String: Any] {
            // Load and start the flow
            loadFlow(flowData)
            startFlow()
            return
        }

        // Check for node data to process through flow engine
        if let nodeData = json["node"] as? [String: Any],
           let nodeType = nodeData["type"] as? String {
            // Process individual node through flow engine
            Task {
                await processNodeResponse(nodeData)
            }
            return
        }

        // Standard record-based response (fallback for legacy)
        guard let recordData = json["record"] as? [String: Any] else {
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

    private func processNodeResponse(_ nodeData: [String: Any]) async {
        guard let nodeId = nodeData["id"] as? String,
              let nodeType = nodeData["type"] as? String else {
            return
        }

        // Get handler and process
        if let handler = NodeHandlerRegistry.shared.getHandler(for: nodeType) {
            let result = await handler.handle(node: nodeData, state: chatState)

            await MainActor.run {
                switch result {
                case .displayUI(let uiState):
                    self.currentUIState = uiState
                    self.delegate?.conferBot(self, didUpdateUIState: uiState)

                case .proceed(let nextNodeId, let data):
                    if let flowComplete = data?["flowComplete"] as? Bool, flowComplete {
                        self.isFlowComplete = true
                        self.delegate?.conferBot(self, didCompleteFlow: true)
                    }

                case .error(let message):
                    self.nodeErrorMessage = message

                default:
                    break
                }
            }
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
