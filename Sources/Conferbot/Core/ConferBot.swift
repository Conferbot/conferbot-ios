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
    func conferBot(_ conferBot: ConferBot, didUpdateQueuedMessageCount count: Int)
    func conferBot(_ conferBot: ConferBot, didChangeNetworkStatus isOnline: Bool)
}

/// Default implementations for new delegate methods
public extension ConferBotDelegate {
    func conferBot(_ conferBot: ConferBot, didUpdateUIState state: NodeUIState?) {}
    func conferBot(_ conferBot: ConferBot, didCompleteFlow success: Bool) {}
    func conferBot(_ conferBot: ConferBot, didReachGoal goalName: String, value: Any?) {}
    func conferBot(_ conferBot: ConferBot, didUpdateQueuedMessageCount count: Int) {}
    func conferBot(_ conferBot: ConferBot, didChangeNetworkStatus isOnline: Bool) {}
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
    @Published public private(set) var hasRestoredSession: Bool = false

    // Node Flow Engine - Published properties
    @Published public private(set) var currentUIState: NodeUIState?
    @Published public private(set) var isProcessingNode: Bool = false
    @Published public private(set) var nodeErrorMessage: String?
    @Published public private(set) var isFlowComplete: Bool = false

    // Offline support - Published properties
    @Published public private(set) var isOnline: Bool = true
    @Published public private(set) var queuedMessageCount: Int = 0

    // Knowledge Base - Published properties
    @Published public private(set) var knowledgeBaseCategories: [KnowledgeBaseCategory] = []
    @Published public private(set) var isLoadingKnowledgeBase: Bool = false

    // Configuration
    private var apiKey: String?
    private var botId: String?
    private var config: ConferBotConfig?
    public var customization: ConferBotCustomization?
    private var currentUser: ConferBotUser?

    // Clients
    private var apiClient: APIClient?
    private var socketClient: SocketClient?

    // Knowledge Base Service
    public private(set) var knowledgeBaseService: KnowledgeBaseService?

    // Node Flow Engine
    private var flowEngine: NodeFlowEngine?
    private var flowEngineCancellables = Set<AnyCancellable>()

    // Offline Manager
    private var offlineManagerCancellables = Set<AnyCancellable>()

    // Session Storage
    private var sessionStorage: SessionStorageProtocol {
        return SessionStorageManager.shared.storage
    }

    // Analytics
    public var analytics: ChatAnalytics {
        return ChatAnalytics.shared
    }

    // Offline Manager
    public var offlineManager: OfflineManager {
        return OfflineManager.shared
    }

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
        setupAnalytics()
        setupOfflineManager()
    }

    // MARK: - Offline Manager Setup

    private func setupOfflineManager() {
        // Subscribe to offline manager state changes
        offlineManager.$isOnline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] online in
                guard let self = self else { return }
                self.isOnline = online
                self.delegate?.conferBot(self, didChangeNetworkStatus: online)
            }
            .store(in: &offlineManagerCancellables)

        offlineManager.$queuedMessageCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self = self else { return }
                self.queuedMessageCount = count
                self.delegate?.conferBot(self, didUpdateQueuedMessageCount: count)
            }
            .store(in: &offlineManagerCancellables)

        // Set up the send message handler for the offline manager
        offlineManager.sendMessageHandler = { [weak self] queuedMessage in
            guard let self = self else {
                throw OfflineManagerError.socketNotConnected
            }
            try await self.sendQueuedMessage(queuedMessage)
        }

        debugPrint("[ConferBot] Offline manager setup complete")
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

        // Initialize Knowledge Base Service
        self.knowledgeBaseService = KnowledgeBaseService(
            apiKey: apiKey,
            botId: botId,
            baseURL: config.apiBaseURL,
            socketClient: self.socketClient
        )

        // Register all node handlers
        registerAllNodeHandlers()

        setupSocketListeners()
        connectSocket()

        // Attempt to restore existing session
        restoreSessionIfValid()

        debugPrint("[ConferBot] Initialized with botId: \(botId)")
    }

    // MARK: - Session Persistence

    /// Attempt to restore a valid session from storage
    private func restoreSessionIfValid() {
        guard let botId = botId else { return }

        // Check if there's a valid stored session
        if let storedSession = sessionStorage.loadSession(botId: botId) {
            debugPrint("[ConferBot] Found stored session: \(storedSession.chatSessionId)")

            // Restore the session
            self.currentSession = storedSession

            // Restore messages
            let storedMessages = sessionStorage.loadMessages(sessionId: storedSession.chatSessionId)
            if !storedMessages.isEmpty {
                self.messages = storedMessages
                debugPrint("[ConferBot] Restored \(storedMessages.count) messages")
            }

            // Restore chat state
            restoreChatState(sessionId: storedSession.chatSessionId)

            // Update session activity to extend expiry
            sessionStorage.updateSessionActivity(sessionId: storedSession.chatSessionId)

            // Rejoin chat room
            socketClient?.joinChatRoomVisitor(
                chatSessionId: storedSession.chatSessionId,
                deviceInfo: getDeviceInfo()
            )

            hasRestoredSession = true
            delegate?.conferBot(self, didStartSession: storedSession.chatSessionId)

            debugPrint("[ConferBot] Session restored successfully")
        }
    }

    /// Restore chat state from storage
    private func restoreChatState(sessionId: String) {
        // Restore answer variables
        let answerVariables = sessionStorage.loadAnswerVariables(sessionId: sessionId)
        for variable in answerVariables {
            chatState.setAnswer(nodeId: variable.nodeId, value: variable.value.value)
        }

        // Restore user metadata
        if let metadata = sessionStorage.loadUserMetadata(sessionId: sessionId) {
            chatState.updateMetadata(metadata.toDictionary())
        }

        // Restore transcript
        let transcript = sessionStorage.loadTranscript(sessionId: sessionId)
        for entry in transcript {
            chatState.addToTranscript(entry: entry.toDictionary())
        }

        debugPrint("[ConferBot] Chat state restored")
    }

    /// Save current session state to storage
    private func saveSessionState() {
        guard let session = currentSession else { return }

        do {
            // Save session
            try sessionStorage.saveSession(session: session)

            // Save messages
            try sessionStorage.saveMessages(messages: messages, sessionId: session.chatSessionId)

            // Save chat state
            saveChatState(sessionId: session.chatSessionId)

            debugPrint("[ConferBot] Session state saved")
        } catch {
            debugPrint("[ConferBot] Failed to save session state: \(error)")
        }
    }

    /// Save chat state to storage
    private func saveChatState(sessionId: String) {
        do {
            // Convert answer variables to storable format
            let answerVars = chatState.getAllAnswers().map { key, value in
                AnswerVariable(nodeId: key, value: value)
            }
            try sessionStorage.saveAnswerVariables(variables: answerVars, sessionId: sessionId)

            // Save user metadata
            let metadata = UserMetadata(from: chatState.userMetadata)
            try sessionStorage.saveUserMetadata(metadata: metadata, sessionId: sessionId)

            // Save transcript
            let transcript = chatState.getTranscript().map { TranscriptEntry(from: $0) }
            try sessionStorage.saveTranscript(transcript: transcript, sessionId: sessionId)

        } catch {
            debugPrint("[ConferBot] Failed to save chat state: \(error)")
        }
    }

    /// Check if there's a valid stored session
    public func hasValidStoredSession() -> Bool {
        guard let botId = botId else { return false }
        return sessionStorage.loadSession(botId: botId) != nil
    }

    /// Get session expiry date
    public func getSessionExpiry() -> Date? {
        guard let session = currentSession else { return nil }
        return sessionStorage.getSessionExpiry(sessionId: session.chatSessionId)
    }

    /// Clear stored session data (logout/end chat)
    public func clearStoredSession() {
        guard let session = currentSession else { return }
        sessionStorage.clearSession(sessionId: session.chatSessionId)
        hasRestoredSession = false
        debugPrint("[ConferBot] Stored session cleared")
    }

    /// Configure session storage with custom expiry time
    public func configureSessionStorage(expiryMinutes: Int) {
        SessionStorageManager.shared.configure(expiryMinutes: expiryMinutes)
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
                    // Finalize analytics when flow completes
                    self?.analytics.finalizeChatAnalytics()
                }
            }
            .store(in: &flowEngineCancellables)

        // Subscribe to node changes for analytics tracking
        flowEngine?.$currentNodeId
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] nodeId in
                guard let self = self,
                      let nodeInfo = self.flowEngine?.getNodeInfo(nodeId),
                      let nodeType = nodeInfo["type"] as? String else { return }

                // Track node entry in analytics
                self.analytics.trackNodeEntry(
                    nodeId: nodeId,
                    nodeType: nodeType,
                    nodeName: nodeInfo["name"] as? String
                )
            }
            .store(in: &flowEngineCancellables)
    }

    // MARK: - Analytics Setup

    private func setupAnalytics() {
        // Configure analytics emit handler to send events via socket
        analytics.setEmitHandler { [weak self] event, data in
            guard let self = self,
                  let socketClient = self.socketClient,
                  socketClient.isConnected else {
                return
            }

            socketClient.emit(event, data)
            self.debugPrint("[ConferBot] Analytics event emitted: \(event)")
        }
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
    /// - Parameter forceNew: If true, creates a new session even if a valid one exists
    public func startSession(forceNew: Bool = false) async throws {
        guard let apiClient = apiClient,
              let botId = botId else {
            throw ConferBotError.notInitialized
        }

        // If not forcing new and we have a restored session, just return
        if !forceNew && hasRestoredSession && currentSession != nil {
            debugPrint("[ConferBot] Using restored session: \(currentSession!.chatSessionId)")
            return
        }

        // Clear any existing stored session if forcing new
        if forceNew, let existingSession = currentSession {
            sessionStorage.clearSession(sessionId: existingSession.chatSessionId)
        }

        let session = try await apiClient.initSession(userId: currentUser?.id)

        await MainActor.run {
            self.currentSession = session
            self.messages = session.record.map { $0.value }
            self.hasRestoredSession = false
            delegate?.conferBot(self, didStartSession: session.chatSessionId)
        }

        // Join chat room as visitor (matches embed-server 'join-chat-room-visitor' event)
        socketClient?.joinChatRoomVisitor(
            chatSessionId: session.chatSessionId,
            deviceInfo: getDeviceInfo()
        )

        // Initialize analytics tracking for this session
        analytics.initializeChatAnalytics(
            sessionId: session.chatSessionId,
            botIdentifier: botId,
            visitorIdentifier: session.visitorId ?? currentUser?.id ?? UUID().uuidString
        )

        // Save the new session to storage
        saveSessionState()

        debugPrint("[ConferBot] Session started: \(session.chatSessionId)")
    }

    /// Send a message (with offline support)
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

        // Check if we can send immediately or need to queue
        if offlineManager.canSendMessages {
            // Send via socket
            sendMessageViaSocket(text: text, messageId: messageId, session: session)

            // Track user message in analytics
            analytics.trackUserMessage(text: text, messageIndex: messages.count)

            debugPrint("[ConferBot] Message sent: \(text)")
        } else {
            // Queue message for later sending
            offlineManager.queueMessage(
                content: text,
                metadata: metadata,
                chatSessionId: session.chatSessionId
            )

            debugPrint("[ConferBot] Message queued (offline): \(text)")
        }

        // Save session state after sending/queueing message
        saveSessionState()

        // Update session activity to extend expiry
        sessionStorage.updateSessionActivity(sessionId: session.chatSessionId)
    }

    /// Internal method to send a message via socket
    private func sendMessageViaSocket(text: String, messageId: String, session: ChatSession) {
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
    }

    /// Send a queued message (called by OfflineManager)
    private func sendQueuedMessage(_ queuedMessage: QueuedMessage) async throws {
        guard let session = currentSession else {
            throw ConferBotError.notInitialized
        }

        guard socketClient?.isConnected == true else {
            throw OfflineManagerError.socketNotConnected
        }

        // Use the original message ID
        let messageId = queuedMessage.id

        // Send via socket
        sendMessageViaSocket(text: queuedMessage.content, messageId: messageId, session: session)

        // Track user message in analytics
        analytics.trackUserMessage(text: queuedMessage.content, messageIndex: messages.count)

        debugPrint("[ConferBot] Queued message sent: \(queuedMessage.content)")
    }

    /// Get queued messages
    public var queuedMessages: [QueuedMessage] {
        return offlineManager.queuedMessages
    }

    /// Manually flush the message queue
    public func flushMessageQueue() {
        offlineManager.flushQueue()
    }

    /// Retry failed messages
    public func retryFailedMessages() {
        offlineManager.retryFailedMessages()
    }

    /// Clear the message queue
    public func clearMessageQueue() {
        offlineManager.clearQueue()
    }

    /// Send typing indicator
    public func sendTypingIndicator(isTyping: Bool) {
        guard let session = currentSession else { return }
        socketClient?.sendTypingStatus(chatSessionId: session.chatSessionId, isTyping: isTyping)

        // Track typing behavior for analytics
        if isTyping {
            analytics.trackTypingStart()
        } else {
            analytics.trackTypingEnd()
        }
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

        // Track node exit with user input for analytics
        let inputString = stringValue(from: input)
        analytics.trackNodeExit(
            nodeId: nodeId,
            exitType: .proceeded,
            userInput: inputString,
            selectedOption: nil
        )

        // Track user message
        analytics.trackUserMessage(text: inputString)

        // Track form submission interaction
        analytics.trackInteraction(type: .formSubmitted, data: [
            "nodeId": nodeId,
            "inputType": "text"
        ])

        // Process the input
        Task {
            await flowEngine.handleUserInput(input, forNodeId: nodeId)
        }

        // Save session state after handling input
        saveSessionState()

        // Update session activity
        if let session = currentSession {
            sessionStorage.updateSessionActivity(sessionId: session.chatSessionId)
        }

        debugPrint("[ConferBot] Node input handled for node: \(nodeId)")
    }

    /// Handle button click from node UI
    public func handleButtonClick(buttonId: String, forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }

        // Store button selection
        chatState.setAnswer(nodeId: nodeId, value: buttonId)

        // Track node exit with selected option for analytics
        analytics.trackNodeExit(
            nodeId: nodeId,
            exitType: .proceeded,
            userInput: nil,
            selectedOption: buttonId
        )

        // Track button click interaction
        analytics.trackInteraction(type: .buttonsClicked, data: [
            "nodeId": nodeId,
            "buttonId": buttonId
        ])

        Task {
            await flowEngine.handleButtonClick(buttonId: buttonId, forNodeId: nodeId)
        }

        // Save session state after button click
        saveSessionState()

        // Update session activity
        if let session = currentSession {
            sessionStorage.updateSessionActivity(sessionId: session.chatSessionId)
        }

        debugPrint("[ConferBot] Button clicked: \(buttonId) for node: \(nodeId)")
    }

    /// Handle choice selection from node UI
    public func handleChoiceSelection(optionId: String, forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }

        // Store choice selection
        chatState.setAnswer(nodeId: nodeId, value: optionId)

        // Track node exit with selected option for analytics
        analytics.trackNodeExit(
            nodeId: nodeId,
            exitType: .proceeded,
            userInput: nil,
            selectedOption: optionId
        )

        // Track quick reply selection interaction
        analytics.trackInteraction(type: .quickReplySelected, data: [
            "nodeId": nodeId,
            "optionId": optionId
        ])

        Task {
            await flowEngine.handleChoiceSelection(optionId: optionId, forNodeId: nodeId)
        }

        // Save session state after choice selection
        saveSessionState()

        // Update session activity
        if let session = currentSession {
            sessionStorage.updateSessionActivity(sessionId: session.chatSessionId)
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

        // Save session state after multiple choice selection
        saveSessionState()

        // Update session activity
        if let session = currentSession {
            sessionStorage.updateSessionActivity(sessionId: session.chatSessionId)
        }

        debugPrint("[ConferBot] Multiple choices selected: \(optionIds) for node: \(nodeId)")
    }

    /// Handle rating selection
    public func handleRatingSelection(rating: Int, forNodeId nodeId: String) {
        // Track rating interaction
        analytics.trackInteraction(type: .ratingSubmitted, data: [
            "nodeId": nodeId,
            "rating": rating
        ])

        handleNodeInput(rating, forNodeId: nodeId)
    }

    /// Handle date/time selection
    public func handleDateSelection(date: Date, forNodeId nodeId: String) {
        let formatter = ISO8601DateFormatter()

        // Track date selection interaction
        analytics.trackInteraction(type: .dateSelected, data: [
            "nodeId": nodeId,
            "date": formatter.string(from: date)
        ])

        handleNodeInput(formatter.string(from: date), forNodeId: nodeId)
    }

    /// Handle file upload completion
    public func handleFileUpload(fileURL: URL, forNodeId nodeId: String) {
        // Track file upload interaction
        analytics.trackInteraction(type: .filesUploaded, data: [
            "nodeId": nodeId,
            "fileURL": fileURL.absoluteString,
            "fileExtension": fileURL.pathExtension
        ])

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

    /// Track goal completion
    /// - Parameters:
    ///   - goalId: The goal identifier
    ///   - goalName: Optional display name for the goal
    ///   - value: Optional conversion value
    public func trackGoal(goalId: String, goalName: String? = nil, value: Any? = nil) {
        var goalData: [String: Any] = [:]

        if let goalName = goalName {
            goalData["goalName"] = goalName
        }
        if let value = value {
            goalData["conversionValue"] = value
        }

        analytics.trackGoalCompletion(goalId: goalId, data: goalData)

        // Notify delegate
        delegate?.conferBot(self, didReachGoal: goalName ?? goalId, value: value)

        debugPrint("[ConferBot] Goal tracked: \(goalId)")
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
    /// - Parameter clearStorage: If true, clears stored session data (default: true)
    public func endSession(clearStorage: Bool = true) {
        guard let session = currentSession else { return }

        // Finalize analytics before ending session
        analytics.finalizeChatAnalytics()

        socketClient?.leaveChatRoom(chatSessionId: session.chatSessionId)
        socketClient?.endChat(chatSessionId: session.chatSessionId)

        // Clear stored session data if requested
        if clearStorage {
            sessionStorage.clearSession(sessionId: session.chatSessionId)
        }

        delegate?.conferBot(self, didEndSession: session.chatSessionId)

        currentSession = nil
        messages = []
        unreadCount = 0
        hasRestoredSession = false

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

                // Notify offline manager that socket connected
                self.offlineManager.handleSocketConnected()
            }
        }

        socketClient?.on(SocketEvents.disconnect) { [weak self] _, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.isConnected = false
                self.delegate?.conferBot(self, didChangeConnectionStatus: false)

                // Notify offline manager that socket disconnected
                self.offlineManager.handleSocketDisconnected()
            }
        }

        // Reconnect event - flush queue after reconnection
        socketClient?.on(SocketEvents.reconnect) { [weak self] _, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.debugPrint("[ConferBot] Socket reconnected, flushing message queue")
                self.offlineManager.handleSocketConnected()
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

                // Save session state after receiving message
                self.saveSessionState()
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

                // Save session state after receiving agent message
                self.saveSessionState()
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

    /// Convert any value to string representation for analytics
    private func stringValue(from value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "Yes" : "No"
        case let array as [Any]:
            return array.compactMap { stringValue(from: $0) }.joined(separator: ", ")
        default:
            return String(describing: value)
        }
    }

    /// Disconnect socket
    public func disconnect() {
        socketClient?.disconnect()
        isConnected = false
        offlineManager.handleSocketDisconnected()
    }

    // MARK: - Knowledge Base Methods

    /// Fetch Knowledge Base categories
    @MainActor
    public func fetchKnowledgeBaseCategories() async throws -> [KnowledgeBaseCategory] {
        guard let service = knowledgeBaseService else {
            throw ConferBotError.notInitialized
        }

        isLoadingKnowledgeBase = true
        defer { isLoadingKnowledgeBase = false }

        let categories = try await service.fetchCategories()
        knowledgeBaseCategories = categories
        return categories
    }

    /// Fetch Knowledge Base articles
    @MainActor
    public func fetchKnowledgeBaseArticles() async throws -> [KnowledgeBaseArticle] {
        guard let service = knowledgeBaseService else {
            throw ConferBotError.notInitialized
        }

        return try await service.fetchArticles()
    }

    /// Search Knowledge Base articles
    @MainActor
    public func searchKnowledgeBaseArticles(query: String) async throws -> [KnowledgeBaseArticle] {
        guard let service = knowledgeBaseService else {
            throw ConferBotError.notInitialized
        }

        return try await service.searchArticles(query: query)
    }

    /// Get a specific Knowledge Base article
    @MainActor
    public func getKnowledgeBaseArticle(id: String) async throws -> KnowledgeBaseArticle {
        guard let service = knowledgeBaseService else {
            throw ConferBotError.notInitialized
        }

        return try await service.getArticle(id: id)
    }

    /// Track Knowledge Base article view
    public func trackKnowledgeBaseArticleView(articleId: String) {
        knowledgeBaseService?.trackArticleView(
            articleId: articleId,
            visitorId: currentSession?.visitorId,
            sessionId: currentSession?.chatSessionId
        )
    }

    /// Rate a Knowledge Base article
    public func rateKnowledgeBaseArticle(
        articleId: String,
        helpful: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        knowledgeBaseService?.rateArticle(
            articleId: articleId,
            helpful: helpful,
            visitorId: currentSession?.visitorId,
            sessionId: currentSession?.chatSessionId,
            completion: completion
        )
    }

    /// Start tracking engagement for a Knowledge Base article
    public func startKnowledgeBaseArticleEngagement(articleId: String) {
        knowledgeBaseService?.startArticleEngagement(
            articleId: articleId,
            visitorId: currentSession?.visitorId,
            sessionId: currentSession?.chatSessionId
        )
    }

    /// Update scroll depth for Knowledge Base article engagement
    public func updateKnowledgeBaseScrollDepth(_ scrollDepth: Double) {
        knowledgeBaseService?.updateScrollDepth(scrollDepth)
    }

    /// Send Knowledge Base article engagement data
    public func sendKnowledgeBaseEngagement() {
        knowledgeBaseService?.sendCurrentEngagement()
    }

    /// Get related Knowledge Base articles
    public func getRelatedKnowledgeBaseArticles(
        for article: KnowledgeBaseArticle,
        limit: Int = 3
    ) -> [KnowledgeBaseArticle] {
        return knowledgeBaseService?.getRelatedArticles(for: article, limit: limit) ?? []
    }

    /// Clear Knowledge Base cache
    public func clearKnowledgeBaseCache() {
        knowledgeBaseService?.clearCache()
    }
}
