//
//  ConferBot.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#endif

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
    @Published public private(set) var isLiveChatMode: Bool = false
    @Published public private(set) var currentAgent: Agent? = nil
    @Published public private(set) var hasRestoredSession: Bool = false
    @Published public private(set) var serverCustomizations: [String: Any]?
    /// The bot's settings as the web widget applies them (Core/Customization); defaults until it loads.
    @Published public private(set) var customizations = ResolvedCustomizations()

    /// The settings exactly as sent, before the widget theme's palette (applyLook).
    private var rawCustomizations: [String: Any]?
    /// The phone's dark mode: a theme set to "auto" follows it.
    private var prefersDark = false

    /// The phone switched between light and dark: a bot whose theme follows
    /// the phone ("auto") repaints. The chat screens call this; apps need not.
    public func setSystemDarkMode(_ dark: Bool) {
        guard dark != prefersDark else { return }
        prefersDark = dark
        applyLook()
    }

    /// The widget theme over the bot's settings, as the web widget does
    /// (WidgetTheme): the theme palette in place of the owner's colours when
    /// chosen, then the resolved look. Main thread.
    private func applyLook() {
        guard let raw = rawCustomizations else {
            serverCustomizations = nil
            customizations = Customizations.resolve(nil)
            return
        }
        let themed = WidgetTheme.withThemePalette(raw, prefersDark: prefersDark)
        let widgetTheme = WidgetTheme.resolve(themed, prefersDark: prefersDark)
        serverCustomizations = themed
        customizations = Customizations.resolve(themed, theme: widgetTheme)
    }

    // Node Flow Engine - Published properties
    @Published public private(set) var currentUIState: NodeUIState?
    @Published public private(set) var isProcessingNode: Bool = false
    @Published public private(set) var nodeErrorMessage: String?
    @Published public private(set) var isFlowComplete: Bool = false

    // Offline support - Published properties
    @Published public private(set) var isOnline: Bool = true
    @Published public private(set) var queuedMessageCount: Int = 0

    // AI agent bots (Agent Studio) - a bot with no flow, answered by an AI
    // agent from the first message (Core/Agent/AgentBot.swift). nil for
    // every flow bot.
    @Published public private(set) var agentBot: AgentBot?
    /// The AI reply as it is being written (one live bubble), or nil.
    @Published public private(set) var agentStream: AgentStream?
    /// One-tap questions: the greeting's starters, then each answer's follow-ups.
    @Published public private(set) var suggestions: [String] = []
    /// Waiting for the AI's reply (the typing dots), at most 45 seconds.
    @Published public private(set) var awaitingReply: Bool = false

    // Knowledge Base - Published properties
    @Published public private(set) var knowledgeBaseCategories: [KnowledgeBaseCategory] = []
    @Published public private(set) var isLoadingKnowledgeBase: Bool = false
    /// A help article the chat asked to open (a source under an AI answer
    /// or an article card); the chat screens show it in the help centre.
    @Published public private(set) var helpArticleToOpen: String?

    // Configuration
    private var apiKey: String?
    private var botId: String?
    /// The bot initialize(...) was called with, or nil before (the greeting card keeps its memory per bot).
    public var activeBotId: String? { botId }
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
    /// The step answered in its own view (answerStep): its reply lines are
    /// shown as the visitor's bubbles until the flow moves past it.
    private var echoNodeId: String?
    /// The socket events the flow's steps listen to (one app listener each, fanned out).
    private let flowEvents = FlowEventHub()
    private var flowEngineCancellables = Set<AnyCancellable>()

    // MARK: - Live chat extras
    // Queue position, leave a message, receipts, locks, file requests, the
    // lead card and the post-chat rating (Core/LiveChat).
    public private(set) lazy var liveChat: LiveChatExtras = LiveChatExtras(
        socket: { [weak self] in self?.socketClient },
        sessionId: { [weak self] in self?.currentSession?.chatSessionId },
        chatState: { [unowned self] in self.chatState },
        addMessage: { [weak self] item in
            guard let self = self, !self.messages.contains(where: { $0.id == item.id }) else { return }
            self.messages.append(item)
            self.saveSessionState()
        },
        sendRecord: { [weak self] in self?.sendCurrentRecord() }
    )
    private var liveChatCancellables = Set<AnyCancellable>()

    // MARK: - Handover lifecycle
    // The "Connecting you with the team…" line and its outcome, the waiting
    // signals, the AI escalation's max-wait nudge, leaving the queue, and a
    // live chat picked back up after a restart (Core/LiveChat/HandoverLifecycle).
    public private(set) lazy var handover: HandoverLifecycle = HandoverLifecycle(hooks: .init(
        sessionId: { [weak self] in self?.currentSession?.chatSessionId },
        emit: { [weak self] event, data in self?.socketClient?.emit(event: event, data: data) },
        emitWithAck: { [weak self] event, data, timeout, done in
            guard let socket = self?.socketClient else { return done(nil) }
            socket.emitWithAck(event: event, data: data, timeout: timeout, completion: done)
        },
        joinRoom: { [weak self] id in self?.socketClient?.joinChatRoomVisitor(chatSessionId: id, deviceInfo: self?.getDeviceInfo()) },
        chatState: { ChatState.shared },
        messages: { [weak self] in self?.messages ?? [] },
        setMessages: { [weak self] list in self?.messages = list },
        engine: { [weak self] in self?.flowEngine },
        chatVisible: { [weak self] in self?.isChatVisible ?? false },
        waitingForPerson: { [weak self] in
            guard let self = self, !self.isLiveChatMode, case .humanHandover = self.currentUIState else { return false }
            return true
        },
        handoverStepData: { [weak self] in self?.flowEngine?.handoverNodeData ?? self?.agentStepData },
        setLive: { [weak self] on in
            self?.isLiveChatMode = on
            self?.chatState.isLiveChatMode = on
        },
        setAgent: { [weak self] agent, details in
            self?.currentAgent = agent
            self?.chatState.currentAgent = details
        },
        save: { [weak self] in self?.saveSessionState() }
    ))
    /// The flow's handover step whose 20s waiting signal has started (once per wait).
    private var connectingWaitFor: String?
    /// An agent bot's handover step data (its max wait), for the AI escalation's nudge.
    private var agentStepData: [String: Any]?

    /// Listen to the web widget's waiting signals: `.waitingForHuman` (also
    /// 20s into a wait with nobody yet), `.humanJoined`, `.waitOver`.
    /// Returns the unsubscribe. Called on the main thread.
    @discardableResult
    public func onWidgetSignal(_ signal: WidgetSignal, _ listener: @escaping (WidgetSignalDetail) -> Void) -> () -> Void {
        handover.signals.on(signal, listener)
    }

    /// Leave the queue (the wait card's Cancel): queue-self-resolve, then the
    /// flow carries on. `done(false)` when a person already picked the chat up.
    public func leaveQueue(_ done: @escaping (Bool) -> Void = { _ in }) {
        DispatchQueue.main.async { self.handover.leaveQueue(done) }
    }
    /// The chat is on screen (ChatView appears): the agent's latest message counts as seen.
    @Published public private(set) var isChatVisible = false

    public func setChatVisible(_ visible: Bool) {
        DispatchQueue.main.async {
            self.isChatVisible = visible
            if visible { self.liveChat.reportReceipts(chatVisible: true) }
        }
    }

    /// Leave a message was sent or skipped: the flow carries on from the handover.
    public func continueAfterLeaveMessage() {
        Task { @MainActor in await self.flowEngine?.continueAfterHandover() }
    }

    /// The conversation's record to the server (response-record).
    func sendCurrentRecord() {
        guard let session = currentSession, let botId = botId else { return }
        socketClient?.emit(event: SocketEvents.responseRecord, data: chatState.buildResponseData(chatSessionId: session.chatSessionId, botId: botId))
    }

    /// The visitor's file in a live chat: uploaded, then sent as the web widget sends it.
    /// [completion] gets an error message, or nil when it went.
    public func sendLiveFile(fileURL: URL, completion: @escaping (String?) -> Void = { _ in }) {
        guard let session = currentSession, let apiKey = apiKey, let botId = botId else {
            return DispatchQueue.main.async { completion("Uploads are not available") }
        }
        let uploader = FileUploadService(apiKey: apiKey, botId: botId, baseURL: config?.apiBaseURL ?? ConferBotEndpoints.apiBaseURL)
        let name = fileURL.lastPathComponent
        Task {
            do {
                // The /media proxy, bound to this conversation (as the web widget uploads).
                let url = try await uploader.uploadFile(from: fileURL, sessionId: session.chatSessionId)
                guard !url.isEmpty else {
                    return await MainActor.run { completion("That file can't be sent. Please try another one.") }
                }
                self.liveChat.sendLiveFile(url: url, fileName: name, mimeType: nil)
                await MainActor.run { completion(nil) }
            } catch {
                await MainActor.run { completion("That file can't be sent. Please try another one.") }
            }
        }
    }

    private func updateQueuePoll(state: NodeUIState?, live: Bool) {
        if case .humanHandover = state, !live {
            // Waiting for a person: the 20s signal, once per wait (not when an AI agent takes it first).
            let node = flowEngine?.currentNodeId
            if connectingWaitFor != node {
                connectingWaitFor = node
                handover.flowWaitStarted(nodeData: flowEngine?.handoverNodeData)
            }
            liveChat.startQueuePoll()
            liveChat.startWaitTimer(nodeData: flowEngine?.handoverNodeData, workspaceId: chatState.getVariable(name: "_workspaceId") as? String)
        } else {
            connectingWaitFor = nil
            liveChat.stopQueuePoll()
            liveChat.stopWaitTimer()
        }
    }

    /// Ask for the queue while a handover waits for a person; report the
    /// visitor's delivered / seen receipts as agent messages arrive.
    private func watchLiveChat() {
        liveChatCancellables.removeAll()
        $currentUIState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updateQueuePoll(state: state, live: self?.isLiveChatMode ?? false) }
            .store(in: &liveChatCancellables)
        $isLiveChatMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] live in self?.updateQueuePoll(state: self?.currentUIState, live: live) }
            .store(in: &liveChatCancellables)
        $messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.liveChat.reportReceipts(chatVisible: self.isChatVisible)
            }
            .store(in: &liveChatCancellables)
    }

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

    // The bot's flow from fetched-chatbot-data, started once a session exists.
    private var cachedNodes: [[String: Any]]?
    private var cachedEdges: [[String: Any]] = []
    private var flowStarted = false

    // An agent bot's silent handover waits for the visitor to engage (every
    // record sent becomes a Response - a chat on the customer's plan); live
    // sends wait for its acceptance.
    private var agentPendingHandover: (id: String, data: [String: Any])?
    private var agentHandoverPending = false
    private var agentStartedFor: String?
    private var awaitReplyTask: Task<Void, Never>?

    // Chat State
    public var chatState: ChatState {
        return ChatState.shared
    }

    private init() {
        setupFlowEngine()
        setupAnalytics()
        setupOfflineManager()
    }

    /// Get or create a persistent visitor ID that survives across sessions and app restarts.
    /// Stored in UserDefaults and only cleared on app uninstall or explicit logout.
    private func getOrCreateVisitorId() -> String {
        let key = "conferbot_visitor_id"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newId = "v_\(UUID().uuidString.prefix(12).lowercased())"
        UserDefaults.standard.set(newId, forKey: key)
        return newId
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
        // Validate required parameters
        guard !apiKey.isEmpty else {
            fatalError("ConferBot: API key must not be empty")
        }
        guard !botId.isEmpty else {
            fatalError("ConferBot: Bot ID must not be empty")
        }
        if !apiKey.hasPrefix("conf_") && apiKey.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) == nil {
            print("[ConferBot] Warning: API key looks unusual. Any non-empty key is accepted - the bot ID is the operative credential.")
        }

        self.apiKey = apiKey
        self.botId = botId
        self.config = config
        self.customization = customization
        // The flow's steps call the bot server (/api/v1/bot/:id/gpt, otp, ai, pay...)
        flowEngine?.config.apiOrigin = NodeFlowEngine.origin(of: config.apiBaseURL)

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
        // The visitor goes with the handshake: the server refuses one the
        // workspace blocked, and the chat shows its closed state (#40).
        socketClient?.visitorId = sessionStorage.loadSession(botId: botId)?.visitorId ?? chatState.visitorId
        socketClient?.onBlocked = { [weak self] in
            DispatchQueue.main.async { self?.applyVisitorBlock(nil) }
        }
        // "Email me this chat" goes through the mobile API (#39).
        liveChat.postTranscriptEmail = { [weak self] id, email in
            guard let api = self?.apiClient else { return TranscriptEmailResult(ok: false) }
            return await api.sendTranscriptEmail(chatSessionId: id, email: email)
        }

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

            // Restore chat state, under this conversation's ids (#62)
            chatState.setSession(sessionId: storedSession.chatSessionId, botId: botId)
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
        // Suspend the bot-entry mirror while replaying the stored transcript;
        // restored messages are already loaded via loadMessages and mirroring
        // them again would duplicate bubbles.
        let savedBotEntryCallback = chatState.onBotEntryAppended
        chatState.onBotEntryAppended = nil
        defer { chatState.onBotEntryAppended = savedBotEntryCallback }

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

        // The server record and the flow's step: a restart reads its live
        // chat and handover from them (they used not to be saved).
        if let stored = sessionStorage.loadChatState(sessionId: sessionId) {
            chatState.restoreServerRecord(stored)
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

            // The server record and the flow's step (with the rest of the state).
            try sessionStorage.saveChatState(state: chatState.toStoredState(sessionId: sessionId))

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
        var flowConfig = NodeFlowEngine.Config()
        flowConfig.socket = ConferBotFlowSocket(client: { [weak self] in self?.socketClient }, hub: flowEvents)
        flowEngine = NodeFlowEngine(state: chatState, registry: .shared, config: flowConfig)

        // Mirror flow-engine bot transcript entries (welcome/message text and
        // standalone images) into the visible message list so ChatView renders
        // them as persisted bubbles - matching the web widget transcript.
        chatState.onBotEntryAppended = { [weak self] entry in
            guard let self = self else { return }

            // The owner's HTML when the line has some: the bubble draws it
            // formatted, as the web does (#64); else the plain text.
            let text = (entry["html"] as? String) ?? (entry["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let imageUrl = entry["imageUrl"] as? String
            guard text != nil || imageUrl != nil else { return }

            var nodeData: [String: AnyCodable] = [:]
            if let nodeId = entry["nodeId"] as? String {
                nodeData["nodeId"] = AnyCodable(nodeId)
            }
            if let nodeType = entry["nodeType"] as? String {
                nodeData["nodeType"] = AnyCodable(nodeType)
            }
            if let imageUrl = imageUrl {
                nodeData["imageUrl"] = AnyCodable(imageUrl)
            }

            let record = BotMessageRecord(
                id: "bot-\(UUID().uuidString)",
                time: Date(),
                text: text,
                nodeData: nodeData
            )

            Task { @MainActor in
                self.messages.append(record)
                self.delegate?.conferBot(self, didReceiveMessage: record)
            }
        }

        // A step answered in its own view says the visitor's reply itself
        // ("⭐⭐⭐⭐", "Oct 19, 2026", "Signed: ..."): shown as their bubble.
        chatState.onUserEntryAppended = { [weak self] entry in
            guard let self = self, let nodeId = entry["nodeId"] as? String,
                  let text = entry["message"] as? String, !text.isEmpty else { return }
            Task { @MainActor in
                guard nodeId == self.echoNodeId else { return }
                self.messages.append(UserMessageRecord(id: "user-step-\(UUID().uuidString)", time: Date(), text: text))
            }
        }

        // Subscribe to flow engine state changes
        flowEngine?.$currentUIState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.currentUIState = state
                self.delegate?.conferBot(self, didUpdateUIState: state)
            }
            .store(in: &flowEngineCancellables)

        // sink, not assign(to: &$...): that is iOS 14+, and the package supports iOS 13.
        flowEngine?.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.isProcessingNode = value }
            .store(in: &flowEngineCancellables)

        flowEngine?.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.nodeErrorMessage = value }
            .store(in: &flowEngineCancellables)

        flowEngine?.$isFlowComplete
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isComplete in
                guard let self = self else { return }
                self.isFlowComplete = isComplete
                if isComplete {
                    self.delegate?.conferBot(self, didCompleteFlow: true)
                    // Finalize analytics when flow completes
                    self.analytics.finalizeChatAnalytics()
                }
            }
            .store(in: &flowEngineCancellables)

        // Subscribe to node changes for analytics tracking
        flowEngine?.$currentNodeId
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] nodeId in
                if let echo = self?.echoNodeId, echo != nodeId { self?.echoNodeId = nil }
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
        registry.socketClient = self.socketClient
        // Every step of the flow-node spec, as the web widget runs it
        registry.reset()
        debugPrint("[ConferBot] Registered \(registry.count) node handlers")
    }

    /// Identify current user
    public func identify(user: ConferBotUser) {
        self.currentUser = user
        ChatState.shared.visitorContext = user.toVisitorContext()
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
            debugPrint("[ConferBot] Using restored session: \(currentSession?.chatSessionId ?? "unknown")")
            await MainActor.run { self.tryStartFlow() }
            return
        }

        // A new session: its flow starts afresh.
        await MainActor.run {
            self.flowStarted = false
            self.resetAgentBotChat()
            self.handover.reset()
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
            // The flow's steps name the conversation from the chat state (#62).
            self.chatState.setSession(sessionId: session.chatSessionId, botId: botId)

            // Store visitorId on ChatState for response-record payloads
            if let visitorId = session.visitorId {
                self.chatState.visitorId = visitorId
            }

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
            visitorIdentifier: session.visitorId ?? currentUser?.id ?? getOrCreateVisitorId()
        )

        // Save the new session to storage
        saveSessionState()

        debugPrint("[ConferBot] Session started: \(session.chatSessionId)")

        // Start the bot's flow (or an agent bot's chat) if its data is here.
        await MainActor.run { self.tryStartFlow() }
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

        // Add to local messages immediately (with deduplication)
        await MainActor.run {
            if !messages.contains(where: { $0.id == messageId }) {
                messages.append(userMessage)
            }
        }

        // An agent bot's conversation starts with the visitor's first word.
        await MainActor.run { self.engageAgent() }

        // Push user response to server record (matching web widget format)
        // ChatState.pushUserRecord uses "user-live-message" shape when isLiveChatMode is true
        chatState.pushUserRecord(nodeId: messageId, nodeType: nil, text: text)

        // Stop visitor typing indicator when message is sent
        if chatState.isLiveChatMode {
            socketClient?.sendTypingStatus(chatSessionId: session.chatSessionId, isTyping: false)
        }

        // Held while an agent bot's handover is being accepted; the
        // acceptance sends the record with this message in it.
        let holdForAgent = await MainActor.run { () -> Bool in
            self.noteVisitorMessage()
            return self.agentHandoverPending
        }
        if holdForAgent {
            saveSessionState()
            return
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
        guard let socketClient = socketClient, let botId = botId else { return }

        // Build the full response data including visitorId and workspaceId
        let responseData = chatState.buildResponseData(
            chatSessionId: session.chatSessionId,
            botId: botId
        )

        socketClient.emit(event: SocketEvents.responseRecord, data: responseData)
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
    /// During live chat mode, this also emits `visitor-typing` so the agent sees it
    public func sendTypingIndicator(isTyping: Bool) {
        // Typing in the composer: a person is here.
        if isTyping {
            Task { @MainActor in self.engageAgent() }
        }
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
        echoNodeId = nil

        // Add user message bubble (right-aligned) showing the input text
        let inputText = stringValue(from: input)
        if !inputText.isEmpty {
            let userMessage = UserMessageRecord(
                id: "user-input-\(UUID().uuidString)",
                time: Date(),
                text: inputText
            )
            Task { @MainActor in
                if !self.messages.contains(where: { $0.id == userMessage.id }) {
                    self.messages.append(userMessage)
                }
            }
        }

        // Store the answer in chat state (the step itself saves it under its
        // answer variable and puts the visitor's line on the transcript)
        chatState.setAnswer(nodeId: nodeId, value: input)

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

    /// Route a bottom-bar submission like the web widget: if a text-input
    /// node (ask-name, ask-email, ...) is awaiting input, answer it through
    /// the flow engine; otherwise send it as a free-form chat message.
    /// - Parameter text: The trimmed text the user typed
    /// - Returns: A validation error message when the awaiting node rejects
    ///   the input, or nil when the text was accepted/sent
    @discardableResult
    public func submitText(_ text: String) -> String? {
        if case .textInput(_, let validation, let nodeId)? = currentUIState {
            if let validation = validation, !validation.validate(text) {
                return validation.errorMessage
            }
            handleNodeInput(text, forNodeId: nodeId)
            return nil
        }

        Task {
            try? await sendMessage(text)
        }
        return nil
    }

    /// Handle button click from node UI
    public func handleButtonClick(buttonId: String, forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }
        echoNodeId = nil

        // A button that opens a page (a navigate link, the payment's
        // Checkout) opens it; the step keeps waiting, so nothing is frozen.
        if case .buttons(let buttons, let uiNodeId)? = currentUIState, uiNodeId == nodeId,
           let link = buttons.first(where: { $0.id == buttonId })?.url, let url = URL(string: link), url.scheme?.hasPrefix("http") == true {
            #if canImport(UIKit)
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            #endif
            Task { await flowEngine.handleButtonClick(buttonId: buttonId, forNodeId: nodeId) }
            return
        }

        // Freeze the button pills into the transcript so they persist across
        // view rebuilds: disabled, selected one highlighted - web widget parity
        var pillLabels: [String] = []
        var selectedLabel = buttonId
        if case .buttons(let buttons, let uiNodeId)? = currentUIState, uiNodeId == nodeId {
            pillLabels = buttons.map { $0.label }
            selectedLabel = buttons.first(where: { $0.id == buttonId })?.label ?? buttonId
        }

        let frozenPills: BotMessageRecord? = pillLabels.isEmpty ? nil : BotMessageRecord(
            id: "buttons-\(UUID().uuidString)",
            time: Date(),
            text: nil,
            nodeData: [
                "choices": AnyCodable(pillLabels),
                "selectedChoice": AnyCodable(selectedLabel)
            ]
        )

        // Add user message bubble (right-aligned) showing the button label
        let userMessage = UserMessageRecord(
            id: "user-button-\(UUID().uuidString)",
            time: Date(),
            text: selectedLabel
        )
        Task { @MainActor in
            if let frozenPills = frozenPills {
                self.messages.append(frozenPills)
            }
            if !self.messages.contains(where: { $0.id == userMessage.id }) {
                self.messages.append(userMessage)
            }
        }

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
        echoNodeId = nil

        // Freeze the choice pills into the transcript so they persist across
        // view rebuilds: disabled, selected one highlighted - web widget parity
        var pillLabels: [String] = []
        var selectedLabel = optionId
        if case .singleChoice(let options, let uiNodeId)? = currentUIState, uiNodeId == nodeId {
            pillLabels = options.map { $0.label }
            selectedLabel = options.first(where: { $0.id == optionId })?.label ?? optionId
        } else if case .quickReplies(let options, let uiNodeId)? = currentUIState, uiNodeId == nodeId {
            pillLabels = options.map { $0.label }
            selectedLabel = options.first(where: { $0.id == optionId })?.label ?? optionId
        }

        let frozenPills: BotMessageRecord? = pillLabels.isEmpty ? nil : BotMessageRecord(
            id: "choices-\(UUID().uuidString)",
            time: Date(),
            text: nil,
            nodeData: [
                "choices": AnyCodable(pillLabels),
                "selectedChoice": AnyCodable(selectedLabel)
            ]
        )

        // Add user message bubble (right-aligned) showing the selected option label
        let userMessage = UserMessageRecord(
            id: "user-choice-\(UUID().uuidString)",
            time: Date(),
            text: selectedLabel
        )
        Task { @MainActor in
            if let frozenPills = frozenPills {
                self.messages.append(frozenPills)
            }
            if !self.messages.contains(where: { $0.id == userMessage.id }) {
                self.messages.append(userMessage)
            }
        }

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

    /// The visitor's answer to a step drawn by its own view (rating, scale,
    /// slider, date, calendar, file, check options, ranking, cards, matrix,
    /// consent, OTP, address, signature, payment), in the flow-node spec's
    /// shape: build it with `FlowStepAnswer`. The visitor's bubble is the
    /// step's own reply, so a refused answer shows none.
    public func answerStep(_ response: Any, forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }
        echoNodeId = nodeId
        chatState.setAnswer(nodeId: nodeId, value: response)
        analytics.trackInteraction(type: .formSubmitted, data: ["nodeId": nodeId, "inputType": "step"])
        Task { await flowEngine.handleUserInput(response, forNodeId: nodeId) }
        saveSessionState()
        if let session = currentSession {
            sessionStorage.updateSessionActivity(sessionId: session.chatSessionId)
        }
    }

    /// The step waiting for the visitor: its node type and data (what its
    /// view draws from), nil when none is waiting.
    public func waitingStep(_ nodeId: String) -> (type: String, data: [String: Any])? {
        guard let info = flowEngine?.getNodeInfo(nodeId) else { return nil }
        return (info["type"] as? String ?? "", info["data"] as? [String: Any] ?? [:])
    }

    /// Handle multiple choice selections
    public func handleMultipleChoiceSelection(optionIds: [String], forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }
        echoNodeId = nil

        // Add user message bubble (right-aligned) showing the selected options
        let displayText = optionIds.joined(separator: ", ")
        if !displayText.isEmpty {
            let userMessage = UserMessageRecord(
                id: "user-multi-choice-\(UUID().uuidString)",
                time: Date(),
                text: displayText
            )
            Task { @MainActor in
                if !self.messages.contains(where: { $0.id == userMessage.id }) {
                    self.messages.append(userMessage)
                }
            }
        }

        // Store selections
        chatState.setAnswer(nodeId: nodeId, value: optionIds)

        // Every ticked option (n-check-options), or a ranking's order
        Task {
            await flowEngine.handleMultipleChoice(optionIds: optionIds, forNodeId: nodeId)
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

    /// Handle date/time selection: the picked moment goes to the step, which
    /// reads it on the right clock (the bot's for a calendar, the visitor's
    /// for a date / time step) and records a booked slot itself (#73).
    public func handleDateSelection(date: Date, forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }
        // Track date selection interaction
        analytics.trackInteraction(type: .dateSelected, data: [
            "nodeId": nodeId,
            "date": ISO8601DateFormatter().string(from: date)
        ])

        chatState.setAnswer(nodeId: nodeId, value: date)
        Task { await flowEngine.handleUserInput(date, forNodeId: nodeId) }
        saveSessionState()
    }

    /// A file the visitor picked for a file step (a local copy the app can
    /// read). The step checks its type and size and uploads it to the bot's
    /// media endpoint, as the web does; a local path is never saved (#72).
    public func handleFileUpload(fileURL: URL, forNodeId nodeId: String) {
        guard let flowEngine = flowEngine else { return }
        // Track file upload interaction
        analytics.trackInteraction(type: .filesUploaded, data: [
            "nodeId": nodeId,
            "fileExtension": fileURL.pathExtension
        ])

        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let file: [String: Any] = ["file": [
            "uri": fileURL.absoluteString,
            "name": fileURL.lastPathComponent,
            "type": Self.mimeType(forExtension: fileURL.pathExtension),
            "size": size
        ]]
        chatState.setAnswer(nodeId: nodeId, value: fileURL.lastPathComponent)
        Task { await flowEngine.handleUserInput(file, forNodeId: nodeId) }
        saveSessionState()
    }

    /// A file's media type from its extension ("" when unknown).
    static func mimeType(forExtension ext: String) -> String {
        #if canImport(UniformTypeIdentifiers)
        if #available(iOS 14.0, macOS 11.0, *), let type = UTType(filenameExtension: ext)?.preferredMIMEType { return type }
        #endif
        return ""
    }

    /// Get current node ID being processed
    public func getCurrentNodeId() -> String? {
        return flowEngine?.currentNodeId
    }

    /// Check if a specific node type requires user interaction
    public func nodeRequiresInteraction(_ nodeType: String) -> Bool {
        return requiresUserInteraction(nodeType)
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

    /// Reset flow state and start a new session (matching web widget restart behavior)
    public func resetFlow() {
        chatState.reset()
        handover.reset()

        // Reset live chat state on ConferBot level too
        isLiveChatMode = false
        isAgentTyping = false
        currentAgent = nil

        // Generate a new session so messages don't append to old conversation
        let newSessionId = String((0..<15).map { _ in
            "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()!
        })
        let newSession = ChatSession(
            id: newSessionId,
            chatSessionId: newSessionId,
            botId: currentSession?.botId ?? "",
            visitorId: currentSession?.visitorId,
            record: [],
            chatDate: Date(),
            visitorMeta: nil,
            isActive: true
        )
        currentSession = newSession
        messages = []
        chatState.setSession(sessionId: newSessionId, botId: botId ?? newSession.botId)

        // Join new chat room
        socketClient?.joinChatRoomVisitor(chatSessionId: newSessionId)

        flowEngine?.restartFlow()
        isFlowComplete = false
        currentUIState = nil
        nodeErrorMessage = nil
        debugPrint("[ConferBot] Flow reset with new session: \(newSessionId)")
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

        // The server has no visitor end-chat (only an agent ends a live chat;
        // it answers a visitor's end-chat with forbidden). Still waiting for
        // a person: leave the queue, as the web does (#59).
        if isWaitingInQueue {
            socketClient?.emit(event: SocketEvents.queueSelfResolve, data: HandoverState.queueSelfResolvePayload(session.chatSessionId))
        }
        socketClient?.leaveChatRoom(chatSessionId: session.chatSessionId)

        // Clear stored session data if requested
        if clearStorage {
            sessionStorage.clearSession(sessionId: session.chatSessionId)
        }

        delegate?.conferBot(self, didEndSession: session.chatSessionId)

        currentSession = nil
        messages = []
        unreadCount = 0
        hasRestoredSession = false
        flowStarted = false
        handover.reset()
        liveChat.reset()
        Task { @MainActor in self.resetAgentBotChat() }

        debugPrint("[ConferBot] Session ended: \(session.chatSessionId)")
    }

    /// Waiting for a person: the flow's handover step in the queue, or an AI
    /// escalation's Connecting line still pending.
    private var isWaitingInQueue: Bool {
        if case .humanHandover = currentUIState, !isLiveChatMode { return true }
        return HandoverState.phase(chatState.getServerRecord()) == .connecting
    }

    // MARK: - The closed chat (#40)

    /// The chat's closed state, or nil while it is open: blocked (the
    /// neutral line, no input, no new chat), or ended with nothing going on
    /// (composer off, "Start a new chat"). LiveEvents.closedState.
    public var closedState: LiveEvents.ClosedState? {
        LiveEvents.closedState(chatState.getServerRecord(), blocked: liveChat.blocked,
                               stepWaiting: currentUIState != nil || isProcessingNode,
                               live: isLiveChatMode && currentAgent != nil)
    }

    /// The workspace blocked this visitor (visitor-blocked, or refused at
    /// the handshake): "This conversation has been closed.", no input, no
    /// new chat; the wait, the flow and the cards stop. Main thread.
    func applyVisitorBlock(_ data: [String: Any]?) {
        guard isOwnSession(data) else { return }
        liveChat.block(LiveEvents.blockedText(data))
        handover.onBlocked()
        isAgentTyping = false
        chatState.isAgentTyping = false
        suggestions = []
        Task { @MainActor in self.setAwaitingReply(false) }
        debugPrint("[ConferBot] Visitor blocked")
    }

    /// "Start a new chat" under an ended chat: a fresh conversation (never
    /// for a blocked visitor, whom the server refuses).
    public func startNewChat() {
        guard liveChat.blocked == nil else { return }
        DispatchQueue.main.async {
            self.liveChat.reset()
            self.isLiveChatMode = false
            self.currentAgent = nil
            self.isAgentTyping = false
            self.chatState.isLiveChatMode = false
            self.chatState.currentAgent = nil
            self.chatState.isAgentTyping = false
            Task { try? await self.startSession(forceNew: true) }
        }
    }

    // MARK: - Email me this chat (#39)

    /// Show the "Email me this chat" card (the chat menu has it).
    public func openEmailTranscript() { liveChat.openEmailTranscript() }

    public func closeEmailTranscript() { liveChat.closeEmailTranscript() }

    /// Email the transcript to this address (POST /mobile/chat/transcript-email);
    /// on success the address is kept as the visitor's. `done` on the main thread.
    public func emailTranscript(_ email: String, done: @escaping (TranscriptEmailResult) -> Void = { _ in }) {
        liveChat.emailTranscript(email, done: done)
    }

    /// Reset unread message count (e.g. when chat overlay opens)
    public func resetUnreadCount() {
        DispatchQueue.main.async {
            self.unreadCount = 0
        }
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
    #if canImport(UIKit)
    public func present(from viewController: UIViewController, animated: Bool = true) {
        let chatVC = ChatViewController()
        let navController = UINavigationController(rootViewController: chatVC)
        navController.modalPresentationStyle = .fullScreen
        viewController.present(navController, animated: animated)
    }
    #endif

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

                // A restored session's room: the join sent at start-up went
                // out before the socket was connected (and was dropped).
                if let sessionId = self.currentSession?.chatSessionId {
                    self.socketClient?.joinChatRoomVisitor(chatSessionId: sessionId, deviceInfo: self.getDeviceInfo())
                }

                // Load bot config (workspaceId, server customizations) like the
                // web widget does on every connect.
                self.socketClient?.requestChatbotData()

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

        // Reconnect event - rejoin room and flush queue after reconnection
        socketClient?.on(SocketEvents.reconnect) { [weak self] _, _ in
            guard let self = self else { return }
            Task { @MainActor in
                // Re-join chat room (socket.io drops room membership on disconnect)
                if let sessionId = self.currentSession?.chatSessionId {
                    self.socketClient?.joinChatRoomVisitor(
                        chatSessionId: sessionId,
                        deviceInfo: self.getDeviceInfo()
                    )
                    self.debugPrint("[ConferBot] Rejoined chat room on reconnect: \(sessionId)")
                }
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

        // No agents available
        socketClient?.on(SocketEvents.noAgentsAvailable) { [weak self] data, _ in
            self?.handleNoAgentsAvailable(data: data)
        }

        // Chat ended
        socketClient?.on(SocketEvents.chatEnded) { [weak self] data, _ in
            self?.handleChatEnded(data: data.first as? [String: Any])
        }

        // Blocked by the workspace mid-chat (#40)
        socketClient?.on(SocketEvents.visitorBlocked) { [weak self] data, _ in
            let json = data.first as? [String: Any]
            DispatchQueue.main.async { self?.applyVisitorBlock(json) }
        }

        // Fetched chatbot data - extract workspaceId and botName for handover
        socketClient?.on(SocketEvents.fetchedChatbotData) { [weak self] data, _ in
            guard let self = self,
                  let json = data.first as? [String: Any],
                  let chatbotData = json["chatbotData"] as? [String: Any] else { return }

            // Store workspaceId for handover handler and response-record payloads
            if let workspaceId = chatbotData["workspaceId"] as? String, !workspaceId.isEmpty {
                self.chatState.setVariable(name: "_workspaceId", value: workspaceId)
                self.chatState.workspaceId = workspaceId
            }

            // Store full customizations for FAB widget
            let customizations = chatbotData["customizations"] as? [String: Any]
            DispatchQueue.main.async {
                self.rawCustomizations = customizations
                self.applyLook()
                // The steps read redactSensitive, chatLeaveMessage...
                self.flowEngine?.setCustomizations(customizations)
            }
            let botName = (customizations?["botName"] as? String)
                ?? (customizations?["logoText"] as? String)
                ?? ""
            if !botName.isEmpty {
                self.chatState.setVariable(name: "_botName", value: botName)
            }

            // The help centre: published articles without bodies, sent only
            // while the owner has it on (embed-server chatbotHandler).
            if let help = KnowledgeBaseData.from(json: json["knowledgeBaseData"]) {
                self.knowledgeBaseService?.apply(help)
                DispatchQueue.main.async { self.knowledgeBaseCategories = help.categories }
            }

            // Store integration webhooks so the Zapier handler can look up
            // the webhook registered for its node
            if let integrationWebhooks = chatbotData["integrationWebhooks"] as? [[String: Any]] {
                self.chatState.setVariable(name: "_integrationWebhooks", value: integrationWebhooks)
            }

            // The bot's flow, and whether it is a no-flow AI agent bot. The
            // flow was never loaded from here: a flow bot ran nothing unless
            // the app loaded the flow itself.
            let agentBot = AgentBotParser.parseAgentBot(chatbotData)
            self.liveChat.setChatbotData(chatbotData)
            let elements = (chatbotData["elements"] as? [[String: Any]])?.first
            let nodes = elements?["nodes"] as? [[String: Any]] ?? []
            let edges = elements?["edges"] as? [[String: Any]] ?? []
            DispatchQueue.main.async {
                self.agentBot = agentBot
                if !nodes.isEmpty || agentBot != nil {
                    self.cachedNodes = nodes
                    self.cachedEdges = edges
                }
                self.tryStartFlow()
            }
        }

        setupAgentBotListeners()
        liveChat.setupListeners()
        if let socket = socketClient { handover.setupListeners(on: socket) }
        watchLiveChat()

        // The server's answers the flow's steps wait for: an integration's
        // result (its values fill the answer variables there), a payment's
        // status; "no-agents-available" is handed on in handleNoAgentsAvailable.
        for event in [SocketEvents.integrationResult, "payment-status"] {
            socketClient?.on(event) { [weak self] data, _ in
                guard let self = self, let json = data.first as? [String: Any] else { return }
                DispatchQueue.main.async { self.flowEvents.fire(event, json) }
            }
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
                // Deduplicate by message ID
                let messageId = message.value.id
                guard !self.messages.contains(where: { $0.id == messageId }) else { return }
                self.messages.append(message.value)
                self.delegate?.conferBot(self, didReceiveMessage: message.value)

                // Save session state after receiving message
                self.saveSessionState()
            }
        } catch {
            ConferBotLogger.error("Failed to decode bot response: \(error.localizedDescription)")
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
        // Server sends: { message, agentDetails, isFileInput, isAudioInput, agentMessageId, ... }
        // NOT a full record. We construct the message from these fields.
        guard let json = data.first as? [String: Any] else { return }
        if let sid = json["chatSessionId"] as? String, let own = currentSession?.chatSessionId, sid != own { return }

        let agentData = json["agentDetails"] as? [String: Any]
        let rawMessageText = json["message"] as? String
        let isFileInput = json["isFileInput"] as? Bool ?? false
        let isAudioInput = json["isAudioInput"] as? Bool ?? false
        // A file or voice note's message is its URL; text is the inbox
        // editor's HTML or the AI's markdown, as one markdown subset.
        let messageText: String? = (isFileInput || isAudioInput)
            ? rawMessageText?.trimmingCharacters(in: .whitespacesAndNewlines)
            : rawMessageText.map { ChatMarkdown.htmlToMarkdown($0) }
        let agentMessageId = json["agentMessageId"] as? String ?? UUID().uuidString
        // An AI reply's sources, buttons and cards; its follow-ups shown.
        let extras = AgentBotParser.aiReplyExtras(json)
        let isAIReply = AgentBotParser.isAIAgent(agentData)
        let followUps = isAIReply && json["isFallback"] as? Bool != true ? AgentBotParser.followUps(json["followUps"]) : []

        // Parse agent details
        let agentDetails: AgentDetails? = agentData.flatMap { agentData in
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: agentData)
                return try JSONDecoder().decode(AgentDetails.self, from: jsonData)
            } catch {
                ConferBotLogger.error("Failed to decode agent details: \(error.localizedDescription)")
                return nil
            }
        }

        let now = Date()

        Task { @MainActor in
            // The wait and the live bubble end; the follow-ups show.
            self.setAwaitingReply(false)
            self.agentStream = nil
            self.suggestions = followUps

            // Deduplicate by message ID
            guard !self.messages.contains(where: { $0.id == agentMessageId }) else { return }

            // Hide agent typing indicator
            self.isAgentTyping = false
            self.chatState.isAgentTyping = false

            let recordItem: any RecordItem

            if isFileInput, let fileUrl = messageText {
                // Agent sent a file
                recordItem = AgentMessageFileRecord(
                    id: agentMessageId,
                    time: now,
                    file: fileUrl,
                    agentDetails: agentDetails
                )
                // Push to server record
                self.chatState.pushLiveChatRecord(
                    entryId: agentMessageId,
                    type: MessageType.agentMessageFile.rawValue,
                    text: fileUrl,
                    agentDetails: agentData
                )
            } else if isAudioInput, let audioUrl = messageText {
                // Agent sent audio
                recordItem = AgentMessageAudioRecord(
                    id: agentMessageId,
                    time: now,
                    url: audioUrl,
                    agentDetails: agentDetails ?? AgentDetails(id: "", name: "Agent", email: "")
                )
                self.chatState.pushLiveChatRecord(
                    entryId: agentMessageId,
                    type: MessageType.agentMessageAudio.rawValue,
                    text: audioUrl,
                    agentDetails: agentData
                )
            } else {
                // Agent sent a text message
                recordItem = AgentMessageRecord(
                    id: agentMessageId,
                    time: now,
                    text: messageText ?? "",
                    agentDetails: agentDetails ?? AgentDetails(id: "", name: "Agent", email: ""),
                    extras: (extras?.isEmpty == false || extras?.isFallback == true) ? extras : nil,
                    translation: LiveChat.agentTranslation(json)
                )
                self.chatState.pushLiveChatRecord(
                    entryId: agentMessageId,
                    type: MessageType.agentMessage.rawValue,
                    text: messageText,
                    agentDetails: agentData
                )
            }

            self.messages.append(recordItem)
            self.unreadCount += 1
            self.delegate?.conferBot(self, didReceiveMessage: recordItem)
            self.delegate?.conferBot(self, didUpdateUnreadCount: self.unreadCount)

            // Save session state after receiving agent message
            self.saveSessionState()
        }
    }

    // MARK: - AI Agent Bots (Agent Studio)

    /// Start the loaded bot's flow, or an agent bot's chat, once both the
    /// bot's data and a session are here. Once per session.
    @MainActor
    private func tryStartFlow() {
        guard !flowStarted, let nodes = cachedNodes, let session = currentSession else { return }
        flowStarted = true
        if let bot = agentBot {
            startAgentBotChat(sessionId: session.chatSessionId, bot: bot, nodes: nodes)
            return
        }
        // A restored conversation is not replayed from the first node: the
        // flow is loaded as it stood, and a live chat (or a handover still in
        // the queue) is picked back up from the server (live-chat-state).
        if hasRestoredSession && !messages.isEmpty {
            flowEngine?.loadFlow(["nodes": nodes, "edges": cachedEdges], keepingState: true)
            handover.resumeRestored(sessionId: session.chatSessionId, nodes: nodes, agentBot: false)
            return
        }
        loadFlow(["nodes": nodes, "edges": cachedEdges])
        startFlow()
    }

    @MainActor
    private func setAwaitingReply(_ on: Bool) {
        awaitReplyTask?.cancel()
        awaitingReply = on
        guard on else { return }
        awaitReplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AgentBotParser.awaitReplySeconds * 1_000_000_000))
            guard !Task.isCancelled, let self = self else { return }
            self.awaitingReply = false
            // Say so, instead of silently dropping the dots (web
            // agentListeners.ts): on screen only, not in the record (#49).
            self.messages.append(AgentBotParser.replyTimeoutNotice())
        }
    }

    /// Open the agent chat for this session on screen: the greeting and the
    /// starters. Nothing is sent yet - only a person starts a conversation
    /// (see engageAgent). A restored session already has its conversation:
    /// back in the room only, nothing greeted or handed over again.
    @MainActor
    private func startAgentBotChat(sessionId: String, bot: AgentBot, nodes: [[String: Any]]) {
        guard agentStartedFor != sessionId else { return }
        agentStartedFor = sessionId
        let details = AgentDetails(id: bot.agentDetailsId, name: bot.displayName, email: "", avatar: bot.avatar, isAIAgent: true)
        let resumed = messages.contains { item in
            (item as? AgentMessageRecord)?.id.hasPrefix("agent-greeting-") == true || item.type == .userLiveMessage
        }
        // A restored chat a person has (the AI handed it on): not the AI.
        if !(resumed && HandoverState.phase(chatState.getServerRecord()) == .joined) {
            currentAgent = Agent(id: details.id, name: details.name, email: "", avatar: bot.avatar)
        }
        // Visitor messages go the live way from the start.
        isLiveChatMode = true
        chatState.isLiveChatMode = true

        let shell = AgentBotParser.agentShellNodes(nodes, agentId: bot.agentId)
        let stepData = AgentBotParser.agentHandoverData(shell.handover?["data"] as? [String: Any], agentId: bot.agentId)
        agentStepData = stepData

        if resumed {
            agentPendingHandover = nil
            agentHandoverPending = false
            // A person (or the wait for one) is picked back up from the server.
            if hasRestoredSession { handover.resumeRestored(sessionId: sessionId, nodes: nodes, agentBot: true) }
            return
        }

        agentHandoverPending = true
        let greeting = bot.greeting.isEmpty ? AgentBotParser.defaultGreeting : bot.greeting
        let welcomeId = shell.welcome?["id"] as? String ?? "agent-welcome"
        var welcomeData = shell.welcome?["data"] as? [String: Any] ?? [:]
        welcomeData["text"] = greeting
        welcomeData["disableImage"] = true
        welcomeData["agentDetails"] = AgentBotParser.agentDetails(of: bot)
        chatState.pushBotRecord(nodeId: welcomeId, nodeType: "welcome-node", nodeData: welcomeData, text: greeting)

        let greetingRecord = AgentMessageRecord(id: "agent-greeting-\(sessionId)", time: Date(), text: greeting, agentDetails: details)
        messages.append(greetingRecord)
        delegate?.conferBot(self, didReceiveMessage: greetingRecord)
        suggestions = bot.starters

        let handoverId = shell.handover?["id"] as? String ?? "agent-handover"
        agentPendingHandover = (handoverId, stepData)
        saveSessionState()
    }

    /// The visitor is engaging (typing, a suggestion tapped, a message sent):
    /// create the Response from the record, then the silent handover. Once.
    @MainActor
    public func engageAgent() {
        guard let step = agentPendingHandover, let socketClient = socketClient, socketClient.isConnected,
              let session = currentSession, let botId = botId else { return }
        agentPendingHandover = nil
        socketClient.emit(event: SocketEvents.responseRecord, data: chatState.buildResponseData(chatSessionId: session.chatSessionId, botId: botId))
        chatState.pushBotRecord(nodeId: step.id, nodeType: "human-handover-node", nodeData: step.data, text: nil)
        let payload = AgentHandover.payload(state: chatState, chatSessionId: session.chatSessionId, botId: botId,
                                            nodeData: step.data, extra: ["silentStart": true])
        socketClient.emit(event: SocketEvents.initiateHandover, data: payload)
    }

    /// agent-accepted for this bot's own AI agent: nothing drawn, held messages sent.
    @MainActor
    private func onAgentBotAccepted(agent: Agent, details: AgentDetails) {
        let wasPending = agentHandoverPending
        agentHandoverPending = false
        currentAgent = agent
        isLiveChatMode = true
        chatState.isLiveChatMode = true
        chatState.currentAgent = details
        let hasVisitorWords = chatState.getServerRecord().contains { $0["shape"] as? String == "user-live-message" }
        if wasPending, hasVisitorWords, let session = currentSession, let botId = botId {
            socketClient?.emit(event: SocketEvents.responseRecord, data: chatState.buildResponseData(chatSessionId: session.chatSessionId, botId: botId))
            setAwaitingReply(true)
        }
    }

    /// The visitor said something: the chips go, the dots wait for the AI.
    @MainActor
    private func noteVisitorMessage() {
        suggestions = []
        let types = chatState.getServerRecord().map { $0["type"] as? String }
        if agentBot != nil && AgentBotParser.isAgentAIActive(types) { setAwaitingReply(true) }
    }

    @MainActor
    private func resetAgentBotChat() {
        agentStartedFor = nil
        agentStepData = nil
        agentPendingHandover = nil
        agentHandoverPending = false
        agentStream = nil
        suggestions = []
        setAwaitingReply(false)
    }

    private func isOwnSession(_ json: [String: Any]?) -> Bool {
        guard let sid = json?["chatSessionId"] as? String, let own = currentSession?.chatSessionId else { return true }
        return sid == own
    }

    private func agentDetails(from raw: Any?) -> AgentDetails? {
        guard let dict = raw as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(AgentDetails.self, from: data)
    }

    private func setupAgentBotListeners() {
        // The reply as it is written: one live bubble, replaced by the finished agent-message.
        socketClient?.on(SocketEvents.agentMessageStream) { [weak self] data, _ in
            guard let self = self, let json = data.first as? [String: Any], self.isOwnSession(json),
                  let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let streamId = json["streamId"] as? String else { return }
            let details = self.agentDetails(from: json["agentDetails"]) ?? AgentDetails(id: "", name: "Agent", email: "")
            let markdown = ChatMarkdown.htmlToMarkdown(text)
            Task { @MainActor in
                self.setAwaitingReply(false)
                self.isAgentTyping = false
                self.agentStream = AgentStream(id: streamId, text: markdown, agentDetails: details)
            }
        }

        // An article, quick replies or a card from the agent.
        socketClient?.on(SocketEvents.agentMessageRich) { [weak self] data, _ in
            guard let self = self, let json = data.first as? [String: Any], self.isOwnSession(json),
                  let entry = json["entry"] as? [String: Any], let id = entry["id"] as? String,
                  let rich = AgentBotParser.safeRich(entry["rich"]) else { return }
            let text = entry["text"] as? String ?? ""
            let details = self.agentDetails(from: entry["agentDetails"])
            let rawAgent = entry["agentDetails"] as? [String: Any]
            Task { @MainActor in
                self.setAwaitingReply(false)
                self.agentStream = nil
                guard !self.messages.contains(where: { $0.id == id }) else { return }
                let record = AgentRichMessageRecord(id: id, time: Date(), rich: rich, text: text, agentDetails: details)
                self.messages.append(record)
                self.chatState.pushLiveChatRecord(entryId: id, type: MessageType.agentMessageRich.rawValue, text: text, agentDetails: rawAgent)
                self.delegate?.conferBot(self, didReceiveMessage: record)
                self.saveSessionState()
            }
        }

        // An agent edited or unsent a message: the bubble changes in place.
        for (event, deleted) in [(SocketEvents.agentMessageEdited, false), (SocketEvents.agentMessageDeleted, true)] {
            socketClient?.on(event) { [weak self] data, _ in
                guard let self = self, let json = data.first as? [String: Any], self.isOwnSession(json),
                      let messageId = json["agentMessageId"] as? String else { return }
                let newText = (json["text"] as? String) ?? (json["message"] as? String)
                Task { @MainActor in
                    guard let index = self.messages.firstIndex(where: { $0.id == messageId }),
                          let message = self.messages[index] as? AgentMessageRecord else { return }
                    self.messages[index] = deleted
                        ? message.with(text: "", deleted: true)
                        : message.with(text: newText.map { ChatMarkdown.htmlToMarkdown($0) }, edited: true)
                    self.saveSessionState()
                }
            }
        }

        // Closed for inactivity; the visitor's next message reopens it.
        socketClient?.on(SocketEvents.aiAgentInactiveClose) { [weak self] data, _ in
            guard let self = self, self.isOwnSession(data.first as? [String: Any]) else { return }
            let json = data.first as? [String: Any]
            Task { @MainActor in
                // A wait for a person still going ends with the chat.
                self.handover.onChatEnded(json)
                self.setAwaitingReply(false)
                self.suggestions = []
                self.chatState.pushLiveChatRecord(entryId: "ai-close-\(UUID().uuidString)", type: "ai-agent-inactive-close")
            }
        }
        socketClient?.on(SocketEvents.aiAgentResumed) { [weak self] data, _ in
            guard let self = self, self.isOwnSession(data.first as? [String: Any]) else { return }
            Task { @MainActor in
                self.chatState.pushLiveChatRecord(entryId: "ai-resumed-\(UUID().uuidString)", type: "ai-agent-resumed")
                self.isLiveChatMode = true
                self.chatState.isLiveChatMode = true
            }
        }
    }

    /// "Helpful?" on an AI answer: kept on the message, sent to the server.
    @MainActor
    public func sendAnswerFeedback(agentMessageId: String, helpful: Bool, reason: String? = nil) {
        sendAnswerFeedback(agentMessageId: agentMessageId, feedback: AnswerFeedback(helpful: helpful, reason: helpful ? nil : reason))
    }

    /// A vote from the "Helpful?" row (HelpfulRow.step): kept on the message
    /// and on the answer's record entry (a restore draws it rated), sent as
    /// ai-answer-feedback {chatSessionId, agentMessageId, helpful, reason?,
    /// comment?} (#43). A changed vote is sent again.
    @MainActor
    public func sendAnswerFeedback(agentMessageId: String, feedback: AnswerFeedback) {
        if let index = messages.firstIndex(where: { $0.id == agentMessageId }),
           let message = messages[index] as? AgentMessageRecord {
            messages[index] = message.with(feedback: feedback)
        }
        let at = LiveEvents.iso(Date())
        chatState.updateServerRecord { HelpfulRow.withFeedback($0, agentMessageId: agentMessageId, feedback, at: at) ?? $0 }
        saveSessionState()
        var payload: [String: Any] = [
            "chatSessionId": currentSession?.chatSessionId ?? "",
            "agentMessageId": agentMessageId,
        ]
        for (k, v) in feedback.payload { payload[k] = v }
        socketClient?.emitWithAck(event: SocketEvents.aiAnswerFeedback, data: payload, timeout: 10)
    }

    /// The visitor's Confirm / Not now on an action the AI is about to take.
    /// `completion` gets (ok, code) on the main queue.
    public func decideAction(token: String, accept: Bool, completion: @escaping (Bool, String?) -> Void) {
        let payload: [String: Any] = ["chatSessionId": currentSession?.chatSessionId ?? "", "token": token, "accept": accept]
        guard let socketClient = socketClient else {
            completion(false, nil)
            return
        }
        socketClient.emitWithAck(event: SocketEvents.aiActionDecision, data: payload) { [weak self] response in
            let result = response as? [String: Any]
            let ok = result?["ok"] as? Bool ?? false
            DispatchQueue.main.async {
                if ok && accept { self?.setAwaitingReply(true) }
                completion(ok, result?["code"] as? String)
            }
        }
    }

    /// A tapped answer button or quick action, as a goal.
    public func trackConversion(goalId: String, conversionEvent: String) {
        socketClient?.emit(event: SocketEvents.trackGoalCompletion, data: [
            "chatSessionId": currentSession?.chatSessionId ?? "",
            "goalId": goalId,
            "conversionEvent": conversionEvent
        ])
    }

    /// A quick reply chosen on a rich message: the chips freeze, the label is sent.
    @MainActor
    public func answerRichMessage(messageId: String, label: String) {
        if let index = messages.firstIndex(where: { $0.id == messageId }),
           let message = messages[index] as? AgentRichMessageRecord {
            messages[index] = message.answering(label)
        }
        Task { try? await self.sendMessage(label) }
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
                email: agentDetails.email,
                avatar: agentDetails.avatar
            )

            Task { @MainActor in
                // The wait is over: the Connecting line settles (joined, or
                // unavailable when the AI takes the chat back) and the
                // waiting signal stops (HandoverState.acceptedPlan), before
                // the agent bot's silent-start check, as the web does.
                let plan = self.handover.onAccepted(json)

                // An agent bot's own AI agent taking the chat it already
                // greeted: nothing to announce, the held messages go out.
                if self.agentBot != nil && agentDetails.isAIAgent {
                    self.onAgentBotAccepted(agent: agent, details: agentDetails)
                    return
                }

                // Set live chat mode; the handover step's waiting card goes
                self.flowEngine?.handoverAccepted()
                self.isLiveChatMode = true
                self.currentAgent = agent
                self.chatState.isLiveChatMode = true
                self.chatState.currentAgent = agentDetails

                // "<name> joined the chat" - not again for the same person (a
                // repeat after a reconnect), with "They can see your
                // conversation so far" after an AI handover.
                if plan.announce {
                    self.handover.addJoin(agentDetails, raw: agentData, plan: plan)
                    if let joined = self.messages.last as? AgentJoinedMessageRecord {
                        self.delegate?.conferBot(self, didReceiveMessage: joined)
                    }
                }

                self.delegate?.conferBot(self, agentDidJoin: agent)
                self.saveSessionState()
                self.debugPrint("[ConferBot] Agent joined: \(agentDetails.name), live chat mode ON")
            }
        } catch {
            ConferBotLogger.error("Failed to decode agent joined: \(error.localizedDescription)")
        }
    }

    private func handleAgentLeft(data: [Any]) {
        let json = data.first as? [String: Any]
        guard isOwnSession(json) else { return }
        Task { @MainActor in
            // An AI handing the visitor to the team is not leaving them: the
            // Connecting line, not "<name> left" (HandoverState.agentLeftKind);
            // an AI pausing an idle visitor draws nothing.
            let kind = self.handover.onAgentLeft(json)
            guard kind != .ignore else { return }
            // No reply is coming from the one who left: no "took too long" either.
            self.setAwaitingReply(false)
            if let line = self.messages.last as? AgentLeftMessageRecord {
                self.delegate?.conferBot(self, didReceiveMessage: line)
            }
            self.isAgentTyping = false
            self.chatState.isAgentTyping = false
            guard kind == .left else { return }

            // A person left: clear the agent but keep live chat mode
            // (another agent might join, or chat-ended will clear it)
            let details = (json?["agentDetails"] as? [String: Any]) ?? [:]
            let agent = Agent(id: details["_id"] as? String ?? "", name: details["name"] as? String ?? "", email: details["email"] as? String)
            self.currentAgent = nil
            self.chatState.currentAgent = nil
            self.delegate?.conferBot(self, agentDidLeave: agent)
            self.saveSessionState()
            self.debugPrint("[ConferBot] Agent left: \(agent.name)")
        }
    }

    private func handleAgentTyping(data: [Any]) {
        guard let json = data.first as? [String: Any],
              let isTyping = json["isTyping"] as? Bool else {
            return
        }

        Task { @MainActor in
            self.isAgentTyping = isTyping
            self.chatState.isAgentTyping = isTyping
        }
    }

    private func handleNoAgentsAvailable(data: [Any]) {
        Task { @MainActor in
            // The Connecting line settles, the wait is over (cb:wait-over).
            self.handover.onNoAgentsAvailable()

            // A flow at its handover step, as the web widget does it: the
            // step itself says the owner's fallback and, with "leave a
            // message" off, carries the flow on (HumanHandoverNodeHandler);
            // otherwise "Leave a message" carries it on once sent or skipped.
            if let engine = self.flowEngine, engine.isAtHandover {
                engine.handoverAccepted()
                self.flowEvents.fire(SocketEvents.noAgentsAvailable, data.first as? [String: Any] ?? [:])
                self.saveSessionState()
                return
            }

            // Outside a flow (an AI escalation) the web draws no line of its
            // own: the AI already said so, and the Leave a message card shows.
            self.saveSessionState()
            self.debugPrint("[ConferBot] No agents available")
        }
    }

    private func handleChatEnded(data: [String: Any]? = nil) {
        guard isOwnSession(data) else { return }
        Task { @MainActor in
            // The same end again (an agent's double click, an AI close racing
            // a person's): one "Chat ended" line and one survey, not two (#40).
            guard !LiveEvents.endedSinceLastLive(self.chatState.getServerRecord()) else { return }

            // A wait still going ends with the chat: the line says so.
            self.handover.onChatEnded(data)
            self.setAwaitingReply(false)

            // Its own id per end: under one id a second live chat's end
            // merged into the first one's entry (web agentListeners.ts).
            let messageId = LiveEvents.eventId("agent-chat-ended")
            let systemMessage = SystemMessageRecord(
                id: messageId,
                time: Date(),
                text: "Chat has ended"
            )
            self.messages.append(systemMessage)
            self.delegate?.conferBot(self, didReceiveMessage: systemMessage)

            // Recorded as the web widget records it (agent-chat-ended): a
            // restart reads the live chat as over from it.
            self.chatState.pushLiveChatRecord(
                entryId: messageId,
                type: "agent-chat-ended",
                text: "Chat has ended"
            )

            // Clear live chat state
            self.isLiveChatMode = false
            self.currentAgent = nil
            self.isAgentTyping = false
            self.chatState.isLiveChatMode = false
            self.chatState.currentAgent = nil
            self.chatState.isAgentTyping = false

            // The post-chat rating, once per end.
            self.liveChat.chatEnded()

            self.saveSessionState()
            self.debugPrint("[ConferBot] Chat ended by server")

            // As on the web: the conversation stays on screen and the flow
            // moves to the handover step's next step - its post-chat survey
            // questions first when it has them (#66).
            await self.flowEngine?.handoverEnded()
        }
    }

    private func getDeviceInfo() -> [String: Any] {
        #if canImport(UIKit)
        let device = UIDevice.current
        return [
            "platform": "iOS",
            "osVersion": device.systemVersion,
            "model": device.model,
            "deviceId": device.identifierForVendor?.uuidString ?? ""
        ]
        #else
        return [
            "platform": "linux",
            "osVersion": "unknown",
            "model": "unknown",
            "deviceId": UUID().uuidString
        ]
        #endif
    }

    private func debugPrint(_ message: String) {
        ConferBotLogger.debug(message)
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

    /// Disconnect socket and clean up resources
    public func disconnect() {
        socketClient?.disconnect()
        apiClient = nil
        socketClient = nil
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

    /// Whether the owner turned the help centre on (`enableKnowledgeBase`).
    public var isHelpCentreOn: Bool { HelpCentre.isOn(serverCustomizations) }

    /// Open a help article by id, as the web widget's openArticle does: the
    /// chat screens switch to the help centre and show it. False while the
    /// help centre is off.
    @discardableResult
    public func openHelpArticle(id: String) -> Bool {
        guard HelpCentre.canOpenArticle(serverCustomizations, articleId: id) else { return false }
        let set = { self.helpArticleToOpen = id }
        if Thread.isMainThread { set() } else { DispatchQueue.main.async(execute: set) }
        return true
    }

    /// The help centre took the article ``helpArticleToOpen`` asked for.
    public func helpArticleOpened() {
        helpArticleToOpen = nil
    }

    /// Clear Knowledge Base cache
    public func clearKnowledgeBaseCache() {
        knowledgeBaseService?.clearCache()
    }
}

// MARK: - The flow's socket

/// The app's socket as the flow engine uses it: events out through the
/// SocketClient, events in from the hub ConferBot fills.
final class ConferBotFlowSocket: FlowSocket {
    private let client: () -> SocketClient?
    private let hub: FlowEventHub

    init(client: @escaping () -> SocketClient?, hub: FlowEventHub) {
        self.client = client
        self.hub = hub
    }

    var isConnected: Bool { client()?.isConnected ?? false }

    func emit(_ event: String, _ payload: [String: Any]) {
        client()?.emit(event: event, data: payload)
    }

    func on(_ event: String, _ listener: @escaping ([String: Any]) -> Void) -> () -> Void {
        hub.on(event, listener)
    }

    func sendResponseRecord(_ data: [String: Any]) {
        client()?.emit(event: SocketEvents.responseRecord, data: data)
    }
}
