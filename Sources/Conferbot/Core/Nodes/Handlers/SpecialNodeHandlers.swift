//
//  SpecialNodeHandlers.swift
//  Conferbot
//
//  Node handlers for the 2 special flow node types:
//  - goal (marks conversion goals)
//  - end_conversation (ends the conversation flow)
//

import Foundation

// MARK: - Flow Completion Signal

/// Enum representing the completion state of a conversation flow
public enum FlowCompletionState {
    /// Flow is still in progress
    case inProgress

    /// Flow completed successfully
    case completed(reason: String?)

    /// Flow ended with a goal reached
    case goalReached(goalName: String, goalValue: Any?)

    /// Flow was interrupted or cancelled
    case cancelled(reason: String?)
}

/// Protocol for signaling flow completion to the NodeFlowEngine
public protocol FlowCompletionDelegate: AnyObject {
    /// Called when the flow reaches a completion point
    /// - Parameter state: The completion state of the flow
    func flowDidComplete(with state: FlowCompletionState)

    /// Called when a goal is reached during the flow
    /// - Parameters:
    ///   - goalName: Name of the goal
    ///   - goalValue: Value associated with the goal
    ///   - conversionData: Additional conversion tracking data
    func goalReached(goalName: String, goalValue: Any?, conversionData: [String: Any]?)
}

// MARK: - Flow Completion Helper

/// Helper extension for ChatState to manage flow completion
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension ChatState {

    /// Marks the conversation as complete
    /// - Parameter reason: Optional reason for completion
    func markConversationComplete(reason: String? = nil) {
        setVariable(name: "_flowComplete", value: true)
        setVariable(name: "_flowCompletedAt", value: ISO8601DateFormatter().string(from: Date()))
        if let reason = reason {
            setVariable(name: "_flowCompletionReason", value: reason)
        }
    }

    /// Checks if the conversation flow is complete
    var isFlowComplete: Bool {
        return getVariable(name: "_flowComplete") as? Bool ?? false
    }

    /// Gets the session ID from the record
    var sessionId: String? {
        return record["sessionId"] as? String
    }

    /// Adds a goal record to the transcript
    /// - Parameters:
    ///   - goalName: Name of the goal
    ///   - goalValue: Value associated with the goal
    func addGoalToTranscript(goalName: String, goalValue: Any?) {
        var entry: [String: Any] = [
            "type": "goal",
            "goalName": goalName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let value = goalValue {
            entry["goalValue"] = value
        }
        addToTranscript(entry: entry)
    }

    /// Generates a summary of the transcript for conversation end events
    /// - Returns: A summary dictionary containing key conversation data
    func generateTranscriptSummary() -> [String: Any] {
        let allTranscript = getTranscript()

        // Count messages by type
        var botMessageCount = 0
        var userMessageCount = 0
        var goalsReached: [[String: Any]] = []

        for entry in allTranscript {
            let type = entry["type"] as? String ?? ""
            switch type {
            case "bot":
                botMessageCount += 1
            case "user":
                userMessageCount += 1
            case "goal":
                goalsReached.append(entry)
            default:
                break
            }
        }

        return [
            "totalMessages": allTranscript.count,
            "botMessages": botMessageCount,
            "userMessages": userMessageCount,
            "goalsReached": goalsReached,
            "answersCollected": getAllAnswers().count,
            "variablesSet": variables.count
        ]
    }
}

// MARK: - Socket Event Names for Special Nodes

/// Socket event names used by special node handlers
public enum SpecialNodeSocketEvents {
    /// Event emitted when a goal is reached
    public static let goalReached = "goal_reached"

    /// Event emitted when conversation ends
    public static let conversationEnded = "conversation_ended"
}

// MARK: - Goal Handler

/// Handler for goal nodes
/// Marks conversion goals and emits goal_reached socket events for analytics
public final class GoalHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Flow.goal }

    /// Weak reference to flow completion delegate
    public weak var flowCompletionDelegate: FlowCompletionDelegate?

    /// Socket client for emitting events
    private weak var socketClient: SocketClient?

    /// Initialize with optional dependencies
    /// - Parameters:
    ///   - socketClient: Socket client for emitting events
    ///   - delegate: Optional flow completion delegate
    public init(socketClient: SocketClient? = nil, delegate: FlowCompletionDelegate? = nil) {
        self.socketClient = socketClient
        self.flowCompletionDelegate = delegate
        super.init()
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)

        // Extract goal name (required)
        let goalName = data.flatMap { getString($0, "goalName") }
            ?? data.flatMap { getString($0, "name") }
            ?? data.flatMap { getString($0, "goal") }
            ?? "unnamed_goal"

        // Extract goal value (optional, can be any type)
        let goalValue = data?["goalValue"] ?? data?["value"]

        // Extract conversion data if present
        var conversionData: [String: Any] = [:]
        if let convData = data?["conversionData"] as? [String: Any] {
            conversionData = convData
        }

        // Add common conversion tracking fields
        if let revenue = data?["revenue"] {
            conversionData["revenue"] = revenue
        }
        if let currency = data?["currency"] as? String {
            conversionData["currency"] = currency
        }
        if let orderId = data?["orderId"] as? String {
            conversionData["orderId"] = orderId
        }

        // Get session ID from state
        let sessionId = state.sessionId ?? state.getVariable(name: "_sessionId") as? String ?? ""

        // Create timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())

        // Build goal event payload
        var goalEventPayload: [String: Any] = [
            "goalName": goalName,
            "timestamp": timestamp,
            "sessionId": sessionId
        ]

        // Add goal value if present
        if let value = goalValue {
            goalEventPayload["goalValue"] = value
        }

        // Add conversion data if present
        if !conversionData.isEmpty {
            goalEventPayload["conversionData"] = conversionData
        }

        // Add user metadata for attribution
        if let userName = state.userName {
            goalEventPayload["userName"] = userName
        }
        if let userEmail = state.userEmail {
            goalEventPayload["userEmail"] = userEmail
        }

        // Emit socket event for goal reached
        emitGoalReachedEvent(payload: goalEventPayload)

        // Log goal completion for analytics
        logGoalCompletion(goalName: goalName, goalValue: goalValue, sessionId: sessionId)

        // Add goal to state transcript
        state.addGoalToTranscript(goalName: goalName, goalValue: goalValue)

        // Store goal in state variables for later reference
        state.setVariable(name: "goal_\(goalName)", value: goalValue ?? true)
        state.setVariable(name: "goal_\(goalName)_timestamp", value: timestamp)

        // Update goals reached count
        let goalsReachedCount = (state.getVariable(name: "_goalsReachedCount") as? Int ?? 0) + 1
        state.setVariable(name: "_goalsReachedCount", value: goalsReachedCount)

        // Notify delegate
        flowCompletionDelegate?.goalReached(
            goalName: goalName,
            goalValue: goalValue,
            conversionData: conversionData.isEmpty ? nil : conversionData
        )

        // Proceed to next node - goals don't stop the flow
        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, ["goalReached": goalName, "goalValue": goalValue as Any])
    }

    /// Emits the goal_reached socket event
    /// - Parameter payload: The event payload
    private func emitGoalReachedEvent(payload: [String: Any]) {
        guard let socketClient = socketClient, socketClient.isConnected else {
            #if DEBUG
            print("[Conferbot] Goal reached but socket not connected. Payload: \(payload)")
            #endif
            return
        }

        socketClient.emit(SpecialNodeSocketEvents.goalReached, payload)

        #if DEBUG
        print("[Conferbot] Goal reached event emitted: \(payload["goalName"] ?? "unknown")")
        #endif
    }

    /// Logs goal completion for analytics
    /// - Parameters:
    ///   - goalName: Name of the goal
    ///   - goalValue: Value of the goal
    ///   - sessionId: Current session ID
    private func logGoalCompletion(goalName: String, goalValue: Any?, sessionId: String) {
        #if DEBUG
        var logMessage = "[Conferbot] Goal completed: '\(goalName)'"
        if let value = goalValue {
            logMessage += " with value: \(value)"
        }
        logMessage += " (session: \(sessionId))"
        print(logMessage)
        #endif

        // Future: Add analytics logging here (Firebase, Mixpanel, etc.)
    }
}

// MARK: - End Conversation Handler

/// Handler for end_conversation nodes
/// Ends the conversation flow and optionally displays a final message
public final class EndConversationHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Flow.endConversation }

    /// Weak reference to flow completion delegate
    public weak var flowCompletionDelegate: FlowCompletionDelegate?

    /// Socket client for emitting events
    private weak var socketClient: SocketClient?

    /// Initialize with optional dependencies
    /// - Parameters:
    ///   - socketClient: Socket client for emitting events
    ///   - delegate: Optional flow completion delegate
    public init(socketClient: SocketClient? = nil, delegate: FlowCompletionDelegate? = nil) {
        self.socketClient = socketClient
        self.flowCompletionDelegate = delegate
        super.init()
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)

        // Extract end message if present
        let endMessage = data.flatMap { getString($0, "message") }
            ?? data.flatMap { getString($0, "endMessage") }
            ?? data.flatMap { getString($0, "text") }

        // Extract completion status
        let completionStatus = data.flatMap { getString($0, "status") }
            ?? data.flatMap { getString($0, "completionStatus") }
            ?? "completed"

        // Get session ID
        let sessionId = state.sessionId ?? state.getVariable(name: "_sessionId") as? String ?? ""

        // Create timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())

        // Generate transcript summary
        let transcriptSummary = state.generateTranscriptSummary()

        // Build conversation ended event payload
        var endEventPayload: [String: Any] = [
            "sessionId": sessionId,
            "timestamp": timestamp,
            "completionStatus": completionStatus,
            "transcriptSummary": transcriptSummary
        ]

        // Add collected data summary
        endEventPayload["collectedData"] = [
            "answers": state.getAllAnswers(),
            "metadata": [
                "name": state.userName as Any,
                "email": state.userEmail as Any,
                "phone": state.userPhone as Any
            ]
        ]

        // Add any goals reached during the conversation
        let goalsReachedCount = state.getVariable(name: "_goalsReachedCount") as? Int ?? 0
        endEventPayload["goalsReachedCount"] = goalsReachedCount

        // Mark conversation as complete in state
        state.markConversationComplete(reason: completionStatus)

        // Add end message to transcript if present
        if let message = endMessage {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: getNodeId(node), nodeType: nodeType)
        }

        // Add conversation end entry to transcript
        state.addToTranscript(entry: [
            "type": "system",
            "event": "conversation_ended",
            "status": completionStatus,
            "timestamp": timestamp
        ])

        // Emit socket event for conversation ended
        emitConversationEndedEvent(payload: endEventPayload)

        // Log conversation end
        logConversationEnd(sessionId: sessionId, status: completionStatus)

        // Notify delegate
        flowCompletionDelegate?.flowDidComplete(with: .completed(reason: completionStatus))

        // Return appropriate result based on whether there's an end message
        if let message = endMessage {
            // Resolve variables in the message
            let resolvedMessage = state.resolveVariables(text: message)

            // Display the end message, then signal flow complete
            // The displayUI result includes flowComplete flag in data for the engine to process
            return .displayUI(.message(text: resolvedMessage, typing: true))
        } else {
            // No message, signal flow complete immediately
            return .proceed(nil, ["flowComplete": true, "completionStatus": completionStatus])
        }
    }

    /// Emits the conversation_ended socket event
    /// - Parameter payload: The event payload
    private func emitConversationEndedEvent(payload: [String: Any]) {
        guard let socketClient = socketClient, socketClient.isConnected else {
            #if DEBUG
            print("[Conferbot] Conversation ended but socket not connected. Payload: \(payload)")
            #endif
            return
        }

        socketClient.emit(SpecialNodeSocketEvents.conversationEnded, payload)

        #if DEBUG
        print("[Conferbot] Conversation ended event emitted for session: \(payload["sessionId"] ?? "unknown")")
        #endif
    }

    /// Logs conversation end for analytics
    /// - Parameters:
    ///   - sessionId: Current session ID
    ///   - status: Completion status
    private func logConversationEnd(sessionId: String, status: String) {
        #if DEBUG
        print("[Conferbot] Conversation ended - session: \(sessionId), status: \(status)")
        #endif

        // Future: Add analytics logging here (Firebase, Mixpanel, etc.)
    }
}

// MARK: - Flow Completion Result Extension

/// Extension to NodeResult for checking flow completion
public extension NodeResult {

    /// Checks if this result indicates flow completion
    var isFlowComplete: Bool {
        switch self {
        case .proceed(_, let data):
            return data?["flowComplete"] as? Bool ?? false
        default:
            return false
        }
    }

    /// Creates a flow complete result
    /// - Parameters:
    ///   - nextNodeId: Optional next node ID (usually nil for flow complete)
    ///   - status: Completion status string
    /// - Returns: A NodeResult indicating flow completion
    static func flowComplete(nextNodeId: String? = nil, status: String = "completed") -> NodeResult {
        return .proceed(nextNodeId, ["flowComplete": true, "completionStatus": status])
    }
}

// MARK: - Handler Factory

/// Factory for creating special node handlers with proper dependencies
public final class SpecialNodeHandlerFactory {

    /// Creates a GoalHandler with the specified dependencies
    /// - Parameters:
    ///   - socketClient: Socket client for emitting events
    ///   - delegate: Optional flow completion delegate
    /// - Returns: Configured GoalHandler instance
    public static func createGoalHandler(
        socketClient: SocketClient? = nil,
        delegate: FlowCompletionDelegate? = nil
    ) -> GoalHandler {
        return GoalHandler(socketClient: socketClient, delegate: delegate)
    }

    /// Creates an EndConversationHandler with the specified dependencies
    /// - Parameters:
    ///   - socketClient: Socket client for emitting events
    ///   - delegate: Optional flow completion delegate
    /// - Returns: Configured EndConversationHandler instance
    public static func createEndConversationHandler(
        socketClient: SocketClient? = nil,
        delegate: FlowCompletionDelegate? = nil
    ) -> EndConversationHandler {
        return EndConversationHandler(socketClient: socketClient, delegate: delegate)
    }

    /// Creates both special flow handlers with shared dependencies
    /// - Parameters:
    ///   - socketClient: Socket client for emitting events
    ///   - delegate: Optional flow completion delegate
    /// - Returns: Tuple containing both handlers
    public static func createAllHandlers(
        socketClient: SocketClient? = nil,
        delegate: FlowCompletionDelegate? = nil
    ) -> (goal: GoalHandler, endConversation: EndConversationHandler) {
        return (
            goal: createGoalHandler(socketClient: socketClient, delegate: delegate),
            endConversation: createEndConversationHandler(socketClient: socketClient, delegate: delegate)
        )
    }
}

// MARK: - Handler Registration Extension

public extension NodeHandlerRegistry {

    /// Registers all special flow node handlers
    func registerSpecialFlowHandlers() {
        register([
            GoalHandler(),
            EndConversationHandler()
        ])
    }

    /// Registers special flow handlers with dependencies
    /// - Parameters:
    ///   - socketClient: Socket client for emitting events
    ///   - delegate: Optional flow completion delegate
    func registerSpecialFlowHandlers(
        socketClient: SocketClient?,
        delegate: FlowCompletionDelegate?
    ) {
        let handlers = SpecialNodeHandlerFactory.createAllHandlers(
            socketClient: socketClient,
            delegate: delegate
        )
        register([
            handlers.goal,
            handlers.endConversation
        ])
    }
}
