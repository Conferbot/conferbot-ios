//
//  ChatAnalytics.swift
//  Conferbot
//
//  Comprehensive analytics tracking for chat sessions.
//  Tracks session lifecycle, node visits, user interactions,
//  typing behavior, and goal completions.
//
//  Reference: conferbot-widget/src/ts/analytics/chatAnalytics.ts
//

import Foundation
import Combine
import UIKit

// MARK: - Analytics Event Types

/// Enum defining all analytics event types that can be tracked
public enum AnalyticsEvent: String, CaseIterable {
    // Session Events
    case chatStart = "track-chat-start"
    case chatEngagement = "track-chat-engagement"
    case finalizeAnalytics = "finalize-analytics"

    // Node Events
    case nodeVisit = "track-node-visit"
    case nodeExit = "track-node-exit"

    // Interaction Events
    case sentiment = "track-sentiment"
    case interaction = "track-interaction"
    case dropOff = "track-drop-off"

    // Goal Events
    case goalCompletion = "track-goal-completion"

    // Rating Events
    case chatRating = "submit-chat-rating"

    // Generic analytics event
    case analytics = "track-analytics"
}

// MARK: - Node Exit Types

/// Types of node exits for analytics tracking
public enum NodeExitType: String {
    case proceeded = "proceeded"
    case abandoned = "abandoned"
    case backPressed = "back_pressed"
    case skipped = "skipped"
    case timeout = "timeout"
    case error = "error"
}

// MARK: - Interaction Types

/// Types of interactions that can be tracked
public enum InteractionType: String {
    case linksClicked = "linksClicked"
    case buttonsClicked = "buttonsClicked"
    case filesUploaded = "filesUploaded"
    case imagesViewed = "imagesViewed"
    case videosWatched = "videosWatched"
    case carouselInteractions = "carouselInteractions"
    case quickReplySelected = "quickReplySelected"
    case ratingSubmitted = "ratingSubmitted"
    case dateSelected = "dateSelected"
    case formSubmitted = "formSubmitted"
}

// MARK: - Supporting Models

/// Data structure for tracking node visits
public struct NodeVisitData {
    let nodeId: String
    let nodeType: String
    let nodeName: String
    let enteredAt: Date

    var enteredAtTimestamp: TimeInterval {
        return enteredAt.timeIntervalSince1970 * 1000
    }
}

/// Session metrics tracked during chat
public struct SessionMetrics {
    var startedAt: Date
    var firstMessageAt: Date?
    var lastMessageAt: Date?
    var totalDuration: TimeInterval = 0
    var activeDuration: TimeInterval = 0
    var idleTime: TimeInterval = 0

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "startedAt": startedAt.timeIntervalSince1970 * 1000,
            "totalDuration": Int(totalDuration),
            "activeDuration": Int(activeDuration),
            "idleTime": Int(idleTime)
        ]

        if let firstMessage = firstMessageAt {
            dict["firstMessageAt"] = firstMessage.timeIntervalSince1970 * 1000
        }
        if let lastMessage = lastMessageAt {
            dict["lastMessageAt"] = lastMessage.timeIntervalSince1970 * 1000
        }

        return dict
    }
}

/// Typing behavior metrics
public struct TypingBehavior {
    var totalTypingTime: TimeInterval = 0
    var deletions: Int = 0
    var abandonedMessages: Int = 0
    var avgMessageLength: Double = 0

    func toDictionary() -> [String: Any] {
        return [
            "totalTypingTime": Int(totalTypingTime),
            "deletions": deletions,
            "abandonedMessages": abandonedMessages,
            "avgMessageLength": Int(avgMessageLength)
        ]
    }
}

/// Device and environment information
public struct EnvironmentInfo {
    let deviceType: String
    let platform: String
    let osVersion: String
    let deviceModel: String
    let appVersion: String?
    let screenResolution: String
    let language: String
    let timezone: String

    static func current() -> EnvironmentInfo {
        let device = UIDevice.current
        let screen = UIScreen.main

        return EnvironmentInfo(
            deviceType: getDeviceType(),
            platform: "iOS",
            osVersion: device.systemVersion,
            deviceModel: getDeviceModel(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            screenResolution: "\(Int(screen.bounds.width * screen.scale))x\(Int(screen.bounds.height * screen.scale))",
            language: Locale.preferredLanguages.first ?? "unknown",
            timezone: TimeZone.current.identifier
        )
    }

    private static func getDeviceType() -> String {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return "mobile"
        case .pad:
            return "tablet"
        case .tv:
            return "tv"
        case .carPlay:
            return "carplay"
        case .mac:
            return "desktop"
        default:
            return "unknown"
        }
    }

    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "deviceType": deviceType,
            "platform": platform,
            "osVersion": osVersion,
            "deviceModel": deviceModel,
            "screenResolution": screenResolution,
            "language": language,
            "timezone": timezone
        ]

        if let appVersion = appVersion {
            dict["appVersion"] = appVersion
        }

        return dict
    }
}

// MARK: - Chat Analytics Manager

/// ChatAnalytics is responsible for tracking all analytics events during a chat session.
/// It manages session lifecycle, node visits, user interactions, and engagement metrics.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class ChatAnalytics: ObservableObject {

    // MARK: - Singleton Instance

    /// Shared singleton instance
    public static let shared = ChatAnalytics()

    // MARK: - Published Properties

    /// Indicates whether analytics is currently active
    @Published public private(set) var isActive: Bool = false

    /// Current session ID being tracked
    @Published public private(set) var chatSessionId: String?

    /// Total message count for current session
    @Published public private(set) var messageCount: Int = 0

    /// Total interaction count for current session
    @Published public private(set) var interactionCount: Int = 0

    // MARK: - Private Properties

    /// Bot identifier
    private var botId: String?

    /// Visitor identifier
    private var visitorId: String?

    /// Session start time
    private var sessionStartTime: Date?

    /// Last activity timestamp
    private var lastActivityTime: Date?

    /// Current node visit data
    private var currentNodeData: NodeVisitData?

    /// Total idle time accumulated
    private var totalIdleTime: TimeInterval = 0

    /// Periodic engagement tracking timer
    private var engagementTimer: Timer?

    /// Typing start time
    private var typingStartTime: Date?

    /// Total typing time accumulated
    private var totalTypingTime: TimeInterval = 0

    /// Deletion count during typing
    private var deletionCount: Int = 0

    /// Total message length for average calculation
    private var totalMessageLength: Int = 0

    /// Node visit history for path analysis
    private var nodeVisitHistory: [NodeVisitData] = []

    /// Goal completions during session
    private var goalCompletions: [(goalId: String, timestamp: Date)] = []

    /// Socket emit closure for sending analytics
    private var emitHandler: ((String, [String: Any]) -> Void)?

    /// Lock for thread-safe access
    private let lock = NSLock()

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Idle threshold in seconds (60 seconds)
    private let idleThreshold: TimeInterval = 60

    /// Engagement tracking interval in seconds (30 seconds)
    private let engagementInterval: TimeInterval = 30

    // MARK: - Initialization

    private init() {
        setupAppLifecycleObservers()
    }

    // MARK: - Configuration

    /// Sets the emit handler for sending analytics events via socket
    /// - Parameter handler: Closure that takes event name and data dictionary
    public func setEmitHandler(_ handler: @escaping (String, [String: Any]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        emitHandler = handler
    }

    // MARK: - Session Lifecycle

    /// Initialize analytics tracking for a new chat session
    /// - Parameters:
    ///   - sessionId: Unique session identifier
    ///   - botIdentifier: Bot ID
    ///   - visitorIdentifier: Visitor ID
    public func initializeChatAnalytics(
        sessionId: String,
        botIdentifier: String,
        visitorIdentifier: String
    ) {
        lock.lock()
        defer { lock.unlock() }

        // Reset any existing session
        resetStateInternal()

        // Initialize new session
        chatSessionId = sessionId
        botId = botIdentifier
        visitorId = visitorIdentifier
        sessionStartTime = Date()
        lastActivityTime = sessionStartTime
        isActive = true

        // Get attribution data (for iOS, we track deep link and referrer if available)
        let attribution = getAttributionData()

        // Emit chat start event
        emit(event: .chatStart, data: [
            "chatSessionId": sessionId,
            "botId": botIdentifier,
            "visitorId": visitorIdentifier,
            "attribution": attribution,
            "environment": EnvironmentInfo.current().toDictionary()
        ])

        // Start periodic engagement tracking
        startEngagementTracking()

        debugPrint("[ChatAnalytics] Initialized for session: \(sessionId)")
    }

    /// Finalize analytics when chat session ends
    public func finalizeChatAnalytics() {
        lock.lock()

        guard let sessionId = chatSessionId, let startTime = sessionStartTime else {
            lock.unlock()
            return
        }

        // Stop engagement tracking
        stopEngagementTracking()

        // Calculate final metrics
        let endTime = Date()
        let totalDuration = endTime.timeIntervalSince(startTime)
        let activeDuration = totalDuration - totalIdleTime

        let sessionMetrics = SessionMetrics(
            startedAt: startTime,
            firstMessageAt: nil,
            lastMessageAt: lastActivityTime,
            totalDuration: totalDuration,
            activeDuration: activeDuration,
            idleTime: totalIdleTime
        )

        let typingBehavior = TypingBehavior(
            totalTypingTime: totalTypingTime,
            deletions: deletionCount,
            abandonedMessages: 0,
            avgMessageLength: messageCount > 0 ? Double(totalMessageLength) / Double(messageCount) : 0
        )

        let finalData: [String: Any] = [
            "chatSessionId": sessionId,
            "finalMetrics": [
                "totalDuration": Int(totalDuration),
                "activeDuration": Int(activeDuration),
                "idleTime": Int(totalIdleTime),
                "messageCount": messageCount,
                "interactionCount": interactionCount,
                "nodesVisited": nodeVisitHistory.count,
                "goalsCompleted": goalCompletions.count,
                "typingBehavior": typingBehavior.toDictionary(),
                "environment": EnvironmentInfo.current().toDictionary(),
                "sessionMetrics": sessionMetrics.toDictionary()
            ]
        ]

        lock.unlock()

        // Emit finalize event
        emit(event: .finalizeAnalytics, data: finalData)

        // Reset state
        lock.lock()
        resetStateInternal()
        lock.unlock()

        debugPrint("[ChatAnalytics] Finalized analytics for session: \(sessionId)")
    }

    // MARK: - Node Tracking

    /// Track entry into a node
    /// - Parameters:
    ///   - nodeId: The node identifier
    ///   - nodeType: The type of node
    ///   - nodeName: Optional display name for the node
    public func trackNodeEntry(nodeId: String, nodeType: String, nodeName: String? = nil) {
        lock.lock()

        guard let sessionId = chatSessionId else {
            lock.unlock()
            return
        }

        // Exit previous node if exists
        if currentNodeData != nil {
            lock.unlock()
            trackNodeExitInternal(exitType: .proceeded, userInput: nil, selectedOption: nil)
            lock.lock()
        }

        let visitData = NodeVisitData(
            nodeId: nodeId,
            nodeType: nodeType,
            nodeName: nodeName ?? nodeType,
            enteredAt: Date()
        )

        currentNodeData = visitData
        nodeVisitHistory.append(visitData)

        let eventData: [String: Any] = [
            "chatSessionId": sessionId,
            "nodeId": nodeId,
            "nodeType": nodeType,
            "nodeName": nodeName ?? nodeType,
            "enteredAt": visitData.enteredAtTimestamp,
            "visitIndex": nodeVisitHistory.count
        ]

        lock.unlock()

        emit(event: .nodeVisit, data: eventData)
        updateActivity()

        debugPrint("[ChatAnalytics] Node entry: \(nodeId) (type: \(nodeType))")
    }

    /// Track exit from current node
    /// - Parameters:
    ///   - nodeId: The node identifier (for validation)
    ///   - exitType: How the user exited the node
    ///   - userInput: Optional user input value
    ///   - selectedOption: Optional selected option value
    public func trackNodeExit(
        nodeId: String,
        exitType: NodeExitType = .proceeded,
        userInput: String? = nil,
        selectedOption: String? = nil
    ) {
        lock.lock()

        // Validate node ID matches current node
        guard currentNodeData?.nodeId == nodeId else {
            lock.unlock()
            return
        }

        lock.unlock()
        trackNodeExitInternal(exitType: exitType, userInput: userInput, selectedOption: selectedOption)
    }

    /// Internal node exit tracking
    private func trackNodeExitInternal(
        exitType: NodeExitType,
        userInput: String?,
        selectedOption: String?
    ) {
        lock.lock()

        guard let sessionId = chatSessionId,
              let nodeData = currentNodeData else {
            lock.unlock()
            return
        }

        let exitedAt = Date()
        let dwellTime = exitedAt.timeIntervalSince(nodeData.enteredAt)

        var eventData: [String: Any] = [
            "chatSessionId": sessionId,
            "nodeId": nodeData.nodeId,
            "nodeType": nodeData.nodeType,
            "exitedAt": exitedAt.timeIntervalSince1970 * 1000,
            "exitType": exitType.rawValue,
            "dwellTime": Int(dwellTime)
        ]

        if let userInput = userInput {
            eventData["userInput"] = userInput
        }
        if let selectedOption = selectedOption {
            eventData["selectedOption"] = selectedOption
        }

        currentNodeData = nil

        lock.unlock()

        emit(event: .nodeExit, data: eventData)
        updateActivity()

        debugPrint("[ChatAnalytics] Node exit: \(nodeData.nodeId) (dwell: \(Int(dwellTime))s)")
    }

    // MARK: - User Message Tracking

    /// Track a user message being sent
    /// - Parameters:
    ///   - text: The message text
    ///   - messageIndex: Optional message index in conversation
    public func trackUserMessage(text: String? = nil, messageIndex: Int? = nil) {
        lock.lock()

        guard let sessionId = chatSessionId else {
            lock.unlock()
            return
        }

        messageCount += 1
        let currentMessageCount = messageCount

        if let text = text {
            totalMessageLength += text.length
        }

        var eventData: [String: Any] = [
            "chatSessionId": sessionId,
            "messageIndex": messageIndex ?? currentMessageCount,
            "messageType": "user"
        ]

        if let text = text {
            eventData["text"] = text
            eventData["messageLength"] = text.count
        }

        if let nodeData = currentNodeData {
            eventData["nodeId"] = nodeData.nodeId
        }

        lock.unlock()

        emit(event: .sentiment, data: eventData)
        updateActivity()

        debugPrint("[ChatAnalytics] User message tracked (count: \(currentMessageCount))")
    }

    // MARK: - Typing Behavior Tracking

    /// Track when user starts typing
    public func trackTypingStart() {
        lock.lock()
        defer { lock.unlock() }

        if typingStartTime == nil {
            typingStartTime = Date()
        }
    }

    /// Track when user stops typing
    public func trackTypingEnd() {
        lock.lock()
        defer { lock.unlock() }

        if let startTime = typingStartTime {
            totalTypingTime += Date().timeIntervalSince(startTime)
            typingStartTime = nil
        }
    }

    /// Track a deletion during typing
    public func trackDeletion() {
        lock.lock()
        defer { lock.unlock() }

        deletionCount += 1
    }

    // MARK: - Interaction Tracking

    /// Track a user interaction
    /// - Parameters:
    ///   - type: The type of interaction
    ///   - data: Additional data about the interaction
    public func trackInteraction(type: InteractionType, data: [String: Any]? = nil) {
        lock.lock()

        guard let sessionId = chatSessionId else {
            lock.unlock()
            return
        }

        interactionCount += 1
        let currentInteractionCount = interactionCount

        var eventData: [String: Any] = [
            "chatSessionId": sessionId,
            "type": type.rawValue,
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "interactionIndex": currentInteractionCount
        ]

        if let nodeData = currentNodeData {
            eventData["nodeId"] = nodeData.nodeId
        }

        if let additionalData = data {
            for (key, value) in additionalData {
                eventData[key] = value
            }
        }

        lock.unlock()

        emit(event: .interaction, data: eventData)
        updateActivity()

        debugPrint("[ChatAnalytics] Interaction tracked: \(type.rawValue)")
    }

    // MARK: - Goal Tracking

    /// Track goal completion
    /// - Parameters:
    ///   - goalId: The goal identifier
    ///   - data: Additional data about the goal completion
    public func trackGoalCompletion(goalId: String, data: [String: Any]? = nil) {
        lock.lock()

        guard let sessionId = chatSessionId else {
            lock.unlock()
            return
        }

        let timestamp = Date()
        goalCompletions.append((goalId: goalId, timestamp: timestamp))

        var eventData: [String: Any] = [
            "chatSessionId": sessionId,
            "goalId": goalId,
            "timestamp": timestamp.timeIntervalSince1970 * 1000,
            "goalIndex": goalCompletions.count
        ]

        if let nodeData = currentNodeData {
            eventData["nodeId"] = nodeData.nodeId
        }

        if let additionalData = data {
            if let conversionEvent = additionalData["conversionEvent"] {
                eventData["conversionEvent"] = conversionEvent
            }
            if let conversionValue = additionalData["conversionValue"] {
                eventData["conversionValue"] = conversionValue
            }
        }

        lock.unlock()

        emit(event: .goalCompletion, data: eventData)
        updateActivity()

        debugPrint("[ChatAnalytics] Goal completed: \(goalId)")
    }

    // MARK: - Rating Tracking

    /// Submit chat rating
    /// - Parameters:
    ///   - csatScore: Customer satisfaction score (1-5)
    ///   - feedback: Optional text feedback
    ///   - thumbsUp: Optional thumbs up/down rating
    ///   - npsScore: Optional NPS score (0-10)
    ///   - source: Rating source identifier
    public func submitChatRating(
        csatScore: Int? = nil,
        feedback: String? = nil,
        thumbsUp: Bool? = nil,
        npsScore: Int? = nil,
        source: String = "post_chat_survey"
    ) {
        lock.lock()

        guard let sessionId = chatSessionId else {
            lock.unlock()
            return
        }

        var eventData: [String: Any] = [
            "chatSessionId": sessionId,
            "source": source
        ]

        if let csatScore = csatScore {
            eventData["csatScore"] = csatScore
        }
        if let feedback = feedback {
            eventData["feedback"] = feedback
        }
        if let thumbsUp = thumbsUp {
            eventData["thumbsUp"] = thumbsUp
        }
        if let npsScore = npsScore {
            eventData["npsScore"] = npsScore
        }

        lock.unlock()

        emit(event: .chatRating, data: eventData)

        debugPrint("[ChatAnalytics] Chat rating submitted")
    }

    // MARK: - Drop-off Tracking

    /// Track potential drop-off when user leaves
    public func trackDropOff(reason: String = "navigated_away") {
        lock.lock()

        guard let sessionId = chatSessionId,
              let nodeData = currentNodeData,
              let lastActivity = lastActivityTime else {
            lock.unlock()
            return
        }

        let timeBeforeDropOff = Date().timeIntervalSince(lastActivity)

        let eventData: [String: Any] = [
            "chatSessionId": sessionId,
            "nodeId": nodeData.nodeId,
            "nodeType": nodeData.nodeType,
            "nodeName": nodeData.nodeName,
            "reason": reason,
            "timeBeforeDropOff": Int(timeBeforeDropOff),
            "lastUserAction": "none"
        ]

        lock.unlock()

        emit(event: .dropOff, data: eventData)

        debugPrint("[ChatAnalytics] Drop-off tracked: \(reason)")
    }

    // MARK: - Generic Analytics

    /// Send a generic analytics event
    /// - Parameters:
    ///   - eventName: Custom event name
    ///   - data: Event data
    public func trackAnalytics(eventName: String, data: [String: Any]) {
        lock.lock()

        guard let sessionId = chatSessionId else {
            lock.unlock()
            return
        }

        var eventData = data
        eventData["chatSessionId"] = sessionId
        eventData["eventName"] = eventName
        eventData["timestamp"] = Date().timeIntervalSince1970 * 1000

        if let nodeData = currentNodeData {
            eventData["nodeId"] = nodeData.nodeId
        }

        lock.unlock()

        emit(event: .analytics, data: eventData)
        updateActivity()
    }

    // MARK: - Session Info

    /// Get current session metrics
    /// - Returns: Current session metrics or nil if no active session
    public func getCurrentMetrics() -> SessionMetrics? {
        lock.lock()
        defer { lock.unlock() }

        guard let startTime = sessionStartTime else {
            return nil
        }

        let now = Date()
        let totalDuration = now.timeIntervalSince(startTime)
        let activeDuration = totalDuration - totalIdleTime

        return SessionMetrics(
            startedAt: startTime,
            firstMessageAt: nil,
            lastMessageAt: lastActivityTime,
            totalDuration: totalDuration,
            activeDuration: activeDuration,
            idleTime: totalIdleTime
        )
    }

    /// Get current typing behavior metrics
    /// - Returns: Current typing behavior metrics
    public func getTypingBehavior() -> TypingBehavior {
        lock.lock()
        defer { lock.unlock() }

        return TypingBehavior(
            totalTypingTime: totalTypingTime,
            deletions: deletionCount,
            abandonedMessages: 0,
            avgMessageLength: messageCount > 0 ? Double(totalMessageLength) / Double(messageCount) : 0
        )
    }

    /// Get node visit history
    /// - Returns: Array of node visit data
    public func getNodeVisitHistory() -> [NodeVisitData] {
        lock.lock()
        defer { lock.unlock() }

        return nodeVisitHistory
    }

    // MARK: - Private Methods

    /// Emit an analytics event
    private func emit(event: AnalyticsEvent, data: [String: Any]) {
        lock.lock()
        let handler = emitHandler
        lock.unlock()

        handler?(event.rawValue, data)
    }

    /// Update activity timestamp and track idle time
    private func updateActivity() {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()

        if let lastActivity = lastActivityTime {
            let timeSinceLastActivity = now.timeIntervalSince(lastActivity)

            // If idle for more than threshold, count as idle time
            if timeSinceLastActivity > idleThreshold {
                totalIdleTime += timeSinceLastActivity - idleThreshold
            }
        }

        lastActivityTime = now
    }

    /// Start periodic engagement tracking
    private func startEngagementTracking() {
        stopEngagementTracking()

        engagementTimer = Timer.scheduledTimer(
            withTimeInterval: engagementInterval,
            repeats: true
        ) { [weak self] _ in
            self?.sendPeriodicEngagement()
        }
    }

    /// Stop periodic engagement tracking
    private func stopEngagementTracking() {
        engagementTimer?.invalidate()
        engagementTimer = nil
    }

    /// Send periodic engagement update
    private func sendPeriodicEngagement() {
        lock.lock()

        guard let sessionId = chatSessionId,
              let startTime = sessionStartTime else {
            lock.unlock()
            return
        }

        let now = Date()
        let totalDuration = now.timeIntervalSince(startTime)
        let activeDuration = totalDuration - totalIdleTime

        let sessionMetrics = SessionMetrics(
            startedAt: startTime,
            firstMessageAt: nil,
            lastMessageAt: lastActivityTime,
            totalDuration: totalDuration,
            activeDuration: activeDuration,
            idleTime: totalIdleTime
        )

        let typingBehavior = TypingBehavior(
            totalTypingTime: totalTypingTime,
            deletions: deletionCount,
            abandonedMessages: 0,
            avgMessageLength: messageCount > 0 ? Double(totalMessageLength) / Double(messageCount) : 0
        )

        let eventData: [String: Any] = [
            "chatSessionId": sessionId,
            "sessionMetrics": sessionMetrics.toDictionary(),
            "typingBehavior": typingBehavior.toDictionary(),
            "messageCount": messageCount,
            "interactionCount": interactionCount,
            "nodesVisited": nodeVisitHistory.count
        ]

        lock.unlock()

        emit(event: .chatEngagement, data: eventData)
    }

    /// Get attribution data (deep link, referrer, etc.)
    private func getAttributionData() -> [String: Any] {
        var attribution: [String: Any] = [
            "platform": "iOS",
            "sdkVersion": "1.0.0" // TODO: Get from bundle
        ]

        // Add any stored attribution from UserDefaults
        if let referrer = UserDefaults.standard.string(forKey: "conferbot_referrer") {
            attribution["referrer"] = referrer
        }

        if let deepLink = UserDefaults.standard.string(forKey: "conferbot_deep_link") {
            attribution["deepLink"] = deepLink
        }

        if let campaign = UserDefaults.standard.string(forKey: "conferbot_campaign") {
            attribution["campaign"] = campaign
        }

        return attribution
    }

    /// Setup app lifecycle observers
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func handleAppWillResignActive() {
        // Track potential drop-off when app goes to background
        if isActive {
            trackDropOff(reason: "app_backgrounded")
        }
    }

    @objc private func handleAppDidBecomeActive() {
        // Update activity when app becomes active
        if isActive {
            updateActivity()
        }
    }

    @objc private func handleAppWillTerminate() {
        // Finalize analytics if active when app terminates
        if isActive {
            finalizeChatAnalytics()
        }
    }

    /// Reset internal state (must be called with lock held)
    private func resetStateInternal() {
        chatSessionId = nil
        botId = nil
        visitorId = nil
        sessionStartTime = nil
        lastActivityTime = nil
        currentNodeData = nil
        totalIdleTime = 0
        typingStartTime = nil
        totalTypingTime = 0
        deletionCount = 0
        messageCount = 0
        totalMessageLength = 0
        interactionCount = 0
        nodeVisitHistory = []
        goalCompletions = []
        isActive = false

        stopEngagementTracking()
    }

    /// Debug print helper
    private func debugPrint(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopEngagementTracking()
    }
}

// MARK: - String Extension

private extension String {
    var length: Int {
        return self.count
    }
}

// MARK: - Publisher Extensions

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension ChatAnalytics {

    /// Publisher for active state changes
    var activePublisher: AnyPublisher<Bool, Never> {
        $isActive.eraseToAnyPublisher()
    }

    /// Publisher for message count changes
    var messageCountPublisher: AnyPublisher<Int, Never> {
        $messageCount.eraseToAnyPublisher()
    }

    /// Publisher for interaction count changes
    var interactionCountPublisher: AnyPublisher<Int, Never> {
        $interactionCount.eraseToAnyPublisher()
    }
}
