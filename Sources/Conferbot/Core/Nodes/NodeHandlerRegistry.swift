//
//  NodeHandlerRegistry.swift
//  Conferbot
//
//  Registry for managing node handlers
//

import Foundation

/// Registry for node handlers, managing handler lookup and registration
public final class NodeHandlerRegistry {

    // MARK: - Shared Instance

    /// Shared singleton instance with all handlers pre-registered
    public static let shared: NodeHandlerRegistry = {
        let registry = NodeHandlerRegistry()
        registry.registerAllHandlers()
        return registry
    }()

    // MARK: - Properties

    /// Dictionary mapping node types to their handlers
    private var handlers: [String: NodeHandler] = [:]

    /// Lock for thread-safe access
    private let lock = NSLock()

    // MARK: - Initialization

    public init() {}

    // MARK: - Registration

    /// Register a handler for its node type
    /// - Parameter handler: The handler to register
    public func register(_ handler: NodeHandler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[handler.nodeType] = handler
    }

    /// Register multiple handlers at once
    /// - Parameter handlers: Array of handlers to register
    public func register(_ handlers: [NodeHandler]) {
        lock.lock()
        defer { lock.unlock() }
        for handler in handlers {
            self.handlers[handler.nodeType] = handler
        }
    }

    /// Unregister a handler for a node type
    /// - Parameter nodeType: The node type to unregister
    public func unregister(_ nodeType: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: nodeType)
    }

    // MARK: - Lookup

    /// Get the handler for a specific node type
    /// - Parameter nodeType: The type of node to get handler for
    /// - Returns: The registered handler, or nil if not found
    public func getHandler(for nodeType: String) -> NodeHandler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[nodeType]
    }

    /// Check if a handler is registered for a node type
    /// - Parameter nodeType: The node type to check
    /// - Returns: True if a handler is registered
    public func hasHandler(for nodeType: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return handlers[nodeType] != nil
    }

    /// Get all registered node types
    /// - Returns: Array of registered node type strings
    public var registeredTypes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(handlers.keys)
    }

    /// Get the count of registered handlers
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return handlers.count
    }

    // MARK: - Handler Registration

    /// Register all built-in handlers
    private func registerAllHandlers() {
        // Message handlers
        register(MessageNodeHandler())
        register(ImageNodeHandler())
        register(VideoNodeHandler())
        register(AudioNodeHandler())
        register(FileNodeHandler())
        register(GifNodeHandler())

        // Input handlers
        register(TextInputNodeHandler())
        register(SingleChoiceNodeHandler())
        register(MultiChoiceNodeHandler())
        register(ButtonsNodeHandler())
        register(QuickRepliesNodeHandler())
        register(CardsNodeHandler())

        // Special input handlers
        register(RatingNodeHandler())
        register(OpinionScaleNodeHandler())
        register(CalendarNodeHandler())
        register(FileUploadNodeHandler())

        // Action handlers
        register(LiveChatNodeHandler())
        register(HumanHandoverNodeHandler())
        register(LinkNodeHandler())
        register(EmbedNodeHandler())

        // Flow control handlers (legacy types)
        register(ConditionNodeHandler())
        register(JumpNodeHandler())
        register(DelayNodeHandler())
        register(EndNodeHandler())

        // Integration handlers
        register(WebhookNodeHandler())
        register(ApiNodeHandler())
        register(EmailNodeHandler())
        register(GoogleMeetNodeHandler())
        register(AirtableNodeHandler())
        register(GoogleDocsNodeHandler())
        register(GoogleDriveNodeHandler())
        register(GoogleCalendarNodeHandler())
        register(NotionNodeHandler())
        register(StripeNodeHandler())

        // Variable handlers (legacy types)
        register(SetVariableNodeHandler())
        register(GetVariableNodeHandler())

        // Logic node handlers (new standardized types from NodeTypes.Logic)
        registerLogicHandlers()

        // Special flow node handlers (goal, end_conversation)
        registerSpecialFlowHandlers()

        // All 19 missing handlers (legacy, choice, logic, integration)
        registerMissingHandlers()
    }

    // MARK: - Convenience Methods

    /// Process a node using the appropriate handler
    /// - Parameters:
    ///   - node: The node data dictionary
    ///   - state: Current chat state
    /// - Returns: The result of processing the node
    public func process(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let nodeType = node["type"] as? String else {
            return .error("Node missing type field")
        }

        guard let handler = getHandler(for: nodeType) else {
            #if DEBUG
            print("[NodeHandlerRegistry] WARNING: No handler registered for node type: \(nodeType) - skipping node")
            #endif
            // Gracefully skip unhandled node types instead of returning an error.
            // Extract nextNodeId so the flow can continue.
            let data = node["data"] as? [String: Any]
            let nextNodeId = data?["nextNodeId"] as? String
                ?? data?["next"] as? String
                ?? node["nextNodeId"] as? String
                ?? node["next"] as? String
            return .proceed(nextNodeId, nil)
        }

        return await handler.handle(node: node, state: state)
    }

    /// Clear all registered handlers
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }

    /// Reset to default handlers
    public func reset() {
        clear()
        registerAllHandlers()
    }
}

// MARK: - Built-in Node Handlers

/// Handler for message nodes
public class MessageNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.sendMessage }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Message node missing data")
        }

        let text = getString(data, "text") ?? getString(data, "message") ?? ""
        let typing = getBool(data, "typing") ?? true

        return .displayUI(.message(text: text, typing: typing))
    }
}

/// Handler for image nodes
public class ImageNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.sendImage }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Image node missing data")
        }

        guard let url = getString(data, "url") ?? getString(data, "src") else {
            return .error("Image node missing URL")
        }

        let caption = getString(data, "caption")
        return .displayUI(.image(url: url, caption: caption))
    }
}

/// Handler for video nodes
public class VideoNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.sendVideo }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Video node missing data")
        }

        guard let url = getString(data, "url") ?? getString(data, "src") else {
            return .error("Video node missing URL")
        }

        let caption = getString(data, "caption")
        return .displayUI(.video(url: url, caption: caption))
    }
}

/// Handler for audio nodes
public class AudioNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.sendAudio }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Audio node missing data")
        }

        guard let url = getString(data, "url") ?? getString(data, "src") else {
            return .error("Audio node missing URL")
        }

        return .displayUI(.audio(url: url))
    }
}

/// Handler for file nodes
public class FileNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.sendFile }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("File node missing data")
        }

        guard let url = getString(data, "url") ?? getString(data, "src") else {
            return .error("File node missing URL")
        }

        let name = getString(data, "name") ?? getString(data, "filename") ?? "file"
        return .displayUI(.file(url: url, name: name))
    }
}

/// Handler for GIF nodes
public class GifNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "send-gif-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("GIF node missing data")
        }

        guard let url = getString(data, "url") ?? getString(data, "src") else {
            return .error("GIF node missing URL")
        }

        return .displayUI(.gif(url: url))
    }
}

/// Handler for text input nodes
public class TextInputNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.askCustomQuestion }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Text input node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let placeholder = getString(data, "placeholder")

        var validation: InputValidation? = nil
        if let validationType = getString(data, "validation") ?? getString(data, "validationType") {
            switch validationType.lowercased() {
            case "email":
                validation = .email
            case "phone":
                validation = .phone
            case "url":
                validation = .url
            case "number":
                validation = .number
            case "date":
                validation = .date
            default:
                validation = .custom(validationType)
            }
        }

        return .displayUI(.textInput(placeholder: placeholder, validation: validation, nodeId: nodeId))
    }
}

/// Handler for single choice nodes
public class SingleChoiceNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.nChoices }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Single choice node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let options = parseChoiceOptions(getArray(data, "options") ?? getArray(data, "choices"))

        return .displayUI(.singleChoice(options: options, nodeId: nodeId))
    }
}

/// Handler for multi choice nodes
public class MultiChoiceNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.nCheckOptions }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Multi choice node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let options = parseChoiceOptions(getArray(data, "options") ?? getArray(data, "choices"))

        return .displayUI(.multiChoice(options: options, nodeId: nodeId))
    }
}

/// Handler for buttons nodes
public class ButtonsNodeHandler: BaseNodeHandler {
    // Legacy alias for n-choices-node; SingleChoiceNodeHandler handles the canonical type
    public override var nodeType: String { "buttons-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Buttons node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let buttons = parseButtonOptions(getArray(data, "buttons") ?? getArray(data, "options"))

        return .displayUI(.buttons(buttons: buttons, nodeId: nodeId))
    }
}

/// Handler for quick replies nodes
public class QuickRepliesNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "send-quick-replies-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Quick replies node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let options = parseChoiceOptions(getArray(data, "options") ?? getArray(data, "replies"))

        return .displayUI(.quickReplies(options: options, nodeId: nodeId))
    }
}

/// Handler for cards nodes
public class CardsNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "send-cards-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Cards node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let cards = parseCardData(getArray(data, "cards") ?? getArray(data, "items"))

        return .displayUI(.cards(cards: cards, nodeId: nodeId))
    }
}

/// Handler for rating nodes
public class RatingNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.ratingChoice }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Rating node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let max = getInt(data, "max") ?? getInt(data, "maxRating") ?? 5

        var style: RatingStyle = .stars
        if let styleString = getString(data, "style") ?? getString(data, "ratingStyle") {
            style = RatingStyle(rawValue: styleString.lowercased()) ?? .stars
        }

        return .displayUI(.rating(max: max, style: style, nodeId: nodeId))
    }
}

/// Handler for opinion scale nodes
public class OpinionScaleNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.opinionScaleChoice }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Opinion scale node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let min = getInt(data, "min") ?? 1
        let max = getInt(data, "max") ?? 10
        let minLabel = getString(data, "minLabel") ?? getString(data, "leftLabel")
        let maxLabel = getString(data, "maxLabel") ?? getString(data, "rightLabel")

        return .displayUI(.opinionScale(min: min, max: max, minLabel: minLabel, maxLabel: maxLabel, nodeId: nodeId))
    }
}

/// Handler for calendar nodes
public class CalendarNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.calendar }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Calendar node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        var mode: CalendarMode = .date
        if let modeString = getString(data, "mode") ?? getString(data, "pickerMode") {
            mode = CalendarMode(rawValue: modeString.lowercased()) ?? .date
        }

        return .displayUI(.calendar(mode: mode, nodeId: nodeId))
    }
}

/// Handler for file upload nodes
public class FileUploadNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.askFile }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("File upload node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let allowedTypes = getStringArray(data, "allowedTypes") ?? getStringArray(data, "accept") ?? ["*/*"]
        let maxSize = getInt(data, "maxSize") ?? getInt(data, "maxFileSize")

        return .displayUI(.fileUpload(allowedTypes: allowedTypes, maxSize: maxSize, nodeId: nodeId))
    }
}

/// Handler for live chat nodes
public class LiveChatNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "live-chat-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let message = data.flatMap { getString($0, "message") }

        return .displayUI(.liveChat(message: message))
    }
}

/// Handler for human handover nodes
public class HumanHandoverNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Special.humanHandover }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let message = data.flatMap { getString($0, "message") }

        return .displayUI(.humanHandover(message: message))
    }
}

/// Handler for link nodes
public class LinkNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.userRedirect }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Link node missing data")
        }

        guard let url = getString(data, "url") ?? getString(data, "href") else {
            return .error("Link node missing URL")
        }

        let text = getString(data, "text") ?? getString(data, "label")
        return .displayUI(.link(url: url, text: text))
    }
}

/// Handler for embed nodes
public class EmbedNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.html }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Embed node missing data")
        }

        guard let html = getString(data, "html") ?? getString(data, "content") else {
            return .error("Embed node missing HTML content")
        }

        return .displayUI(.embed(html: html))
    }
}

/// Handler for condition nodes (legacy type)
public class ConditionNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Logic.condition }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Delegate to ConditionalHandler for actual implementation
        let conditionalHandler = ConditionalHandler()
        return await conditionalHandler.handle(node: node, state: state)
    }
}

/// Handler for jump nodes
public class JumpNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Logic.jumpTo }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Jump node missing data")
        }

        guard let targetNodeId = getString(data, "targetNodeId") ?? getString(data, "target") else {
            return .error("Jump node missing target node ID")
        }

        return .jumpTo(targetNodeId)
    }
}

/// Handler for delay nodes (legacy type)
public class DelayNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Special.delay }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Delegate to LogicDelayHandler for actual implementation
        let logicDelayHandler = LogicDelayHandler()
        return await logicDelayHandler.handle(node: node, state: state)
    }
}

/// Handler for end nodes
public class EndNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "end-conversation-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        return .displayUI(.none)
    }
}

/// Handler for webhook nodes
public class WebhookNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Integration.webhook }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Webhook execution would be implemented here
        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}

/// Handler for API nodes
public class ApiNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "api-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // API call would be implemented here
        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}

/// Handler for email nodes
public class EmailNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Integration.email }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Email sending would be implemented here
        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}

/// Handler for Google Meet integration nodes
/// Creates Google Meet meetings via server-side integration
public class GoogleMeetNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Integration.googleMeet }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Google Meet node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract operation type (book, create, etc.)
        let operation = getString(data, "operation") ?? "book"

        // Handle booking operation - display calendar UI for meeting selection
        if operation == "book" {
            // Extract timezone
            let timezone = getString(data, "timeZone") ?? TimeZone.current.identifier

            // Extract answer variable name for storing the result
            let answerVariable = getString(data, "answerVariable") ?? "meet_booking"

            // Extract meeting configuration
            let meetingTitle = getString(data, "title") ?? "Schedule a Google Meet"
            let duration = getInt(data, "duration") ?? 30 // Default 30 minutes

            // Extract calendar settings
            let excludeWeekends = getBool(data, "excludeWeekends") ?? false

            // Display calendar for meeting time selection
            return .displayUI(.calendar(mode: .dateTime, nodeId: nodeId))
        }

        // For other operations (create, etc.), just proceed
        // The actual meeting creation is handled server-side via socket event
        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}

/// Handler for set variable nodes (legacy type)
public class SetVariableNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Logic.variable }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Delegate to SetVariableHandler for actual implementation
        let setVariableHandler = SetVariableHandler()
        return await setVariableHandler.handle(node: node, state: state)
    }
}

/// Handler for get variable nodes
public class GetVariableNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "get-variable-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Variable getting would be implemented here
        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}

/// Handler for Airtable integration nodes
/// Emits socket event for server-side CRUD operations on Airtable
public class AirtableNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Integration.airtable }

    /// Reference to socket client for emitting events
    private weak var socketClient: SocketClient?

    public init(socketClient: SocketClient? = nil) {
        self.socketClient = socketClient
        super.init()
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Airtable node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract operation type (create, read, update, delete)
        let operation = getString(data, "operation") ?? "create"

        // Extract base and table configuration
        let baseId = getString(data, "baseId").map { state.resolveVariables(text: $0) }
        let tableName = getString(data, "tableName").map { state.resolveVariables(text: $0) }

        // Extract record ID for update/delete operations
        let recordId = getString(data, "recordId").map { state.resolveVariables(text: $0) }

        // Extract record data for create/update operations
        var recordData: [String: Any] = [:]
        if let rawData = data["recordData"] as? [String: Any] {
            recordData = resolveVariablesInDictionary(rawData, state: state)
        }

        // Extract field mappings if provided
        var fieldMappings: [[String: Any]] = []
        if let mappings = getArray(data, "fieldMappings") {
            for mapping in mappings {
                var resolvedMapping: [String: Any] = [:]
                if let field = mapping["field"] as? String {
                    resolvedMapping["field"] = field
                }
                if let column = mapping["column"] as? String {
                    resolvedMapping["column"] = column
                }
                if let value = mapping["value"] as? String {
                    resolvedMapping["value"] = state.resolveVariables(text: value)
                }
                if let variableName = mapping["variableName"] as? String {
                    if let variableValue = state.getVariable(name: variableName) {
                        resolvedMapping["value"] = variableValue
                    } else if let answerValue = state.getAnswer(nodeId: variableName) {
                        resolvedMapping["value"] = answerValue
                    }
                }
                fieldMappings.append(resolvedMapping)
            }
        }

        // Extract filter formula for read operations
        let filterFormula = getString(data, "filterFormula").map { state.resolveVariables(text: $0) }

        // Extract view name for read operations
        let viewName = getString(data, "viewName")

        // Extract max records for read operations
        let maxRecords = getInt(data, "maxRecords")

        // Extract sort configuration for read operations
        var sortConfig: [[String: Any]]?
        if let sort = getArray(data, "sort") {
            sortConfig = sort.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract response variable name
        let responseVariable = getString(data, "responseVariable") ?? "airtable_response"

        // Get session ID from state
        let sessionId = state.sessionId ?? state.getVariable(name: "_sessionId") as? String ?? ""
        let botId = state.record["botId"] as? String ?? ""

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": sessionId,
            "botId": botId,
            "nodeId": nodeId,
            "nodeType": "airtable",
            "operation": operation,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        // Add base/table configuration
        if let base = baseId { payload["baseId"] = base }
        if let table = tableName { payload["tableName"] = table }

        // Add operation-specific data
        if let recId = recordId { payload["recordId"] = recId }
        if !recordData.isEmpty { payload["recordData"] = recordData }
        if !fieldMappings.isEmpty { payload["fieldMappings"] = fieldMappings }

        // Add read operation specific fields
        if let filter = filterFormula { payload["filterFormula"] = filter }
        if let view = viewName { payload["viewName"] = view }
        if let maxRecs = maxRecords { payload["maxRecords"] = maxRecs }
        if let sort = sortConfig { payload["sort"] = sort }

        // Emit socket event for server processing
        socketClient?.emit(SocketEvents.airtableNodeTrigger, payload)

        #if DEBUG
        print("[Conferbot] Airtable \(operation) event emitted for server processing")
        #endif

        // Record the response
        state.addToTranscript(entry: [
            "type": "system",
            "nodeType": "airtable",
            "operation": operation,
            "nodeId": nodeId,
            "baseId": baseId as Any,
            "tableName": tableName as Any
        ])

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, ["airtableOperation": operation])
    }

    /// Resolve variables in a dictionary's string values
    private func resolveVariablesInDictionary(_ dict: [String: Any], state: ChatState) -> [String: Any] {
        var resolved: [String: Any] = [:]
        for (key, value) in dict {
            if let stringValue = value as? String {
                resolved[key] = state.resolveVariables(text: stringValue)
            } else if let nestedDict = value as? [String: Any] {
                resolved[key] = resolveVariablesInDictionary(nestedDict, state: state)
            } else if let array = value as? [[String: Any]] {
                resolved[key] = array.map { resolveVariablesInDictionary($0, state: state) }
            } else {
                resolved[key] = value
            }
        }
        return resolved
    }
}

/// Handler for Google Docs integration nodes
/// Emits socket event for server-side operations on Google Docs (create, update, append, read)
public class GoogleDocsNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Integration.googleDocs }

    /// Reference to socket client for emitting events
    private weak var socketClient: SocketClient?

    public init(socketClient: SocketClient? = nil) {
        self.socketClient = socketClient
        super.init()
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Google Docs node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract operation type (create, update, append, read)
        let operation = getString(data, "operation") ?? "create"

        // Extract document configuration
        let documentId = getString(data, "documentId").map { state.resolveVariables(text: $0) }
        let title = getString(data, "title").map { state.resolveVariables(text: $0) }

        // Extract content for create/update/append operations
        let content = getString(data, "content").map { state.resolveVariables(text: $0) }

        // Extract folder ID for create operations (where to store the new document)
        let folderId = getString(data, "folderId").map { state.resolveVariables(text: $0) }

        // Extract template configuration for create operations
        let templateId = getString(data, "templateId").map { state.resolveVariables(text: $0) }

        // Extract field mappings for template-based creation
        var fieldMappings: [[String: Any]] = []
        if let mappings = getArray(data, "fieldMappings") {
            for mapping in mappings {
                var resolvedMapping: [String: Any] = [:]
                if let placeholder = mapping["placeholder"] as? String {
                    resolvedMapping["placeholder"] = placeholder
                }
                if let value = mapping["value"] as? String {
                    resolvedMapping["value"] = state.resolveVariables(text: value)
                }
                if let variableName = mapping["variableName"] as? String {
                    if let variableValue = state.getVariable(name: variableName) {
                        if let stringValue = variableValue as? String {
                            resolvedMapping["value"] = stringValue
                        } else {
                            resolvedMapping["value"] = String(describing: variableValue)
                        }
                    } else if let answerValue = state.getAnswer(nodeId: variableName) {
                        resolvedMapping["value"] = answerValue
                    }
                }
                fieldMappings.append(resolvedMapping)
            }
        }

        // Extract text replacement pairs for update operations
        var replacements: [[String: String]] = []
        if let replaceList = getArray(data, "replacements") {
            for replacement in replaceList {
                var resolvedReplacement: [String: String] = [:]
                if let find = replacement["find"] as? String {
                    resolvedReplacement["find"] = state.resolveVariables(text: find)
                }
                if let replaceWith = replacement["replace"] as? String {
                    resolvedReplacement["replace"] = state.resolveVariables(text: replaceWith)
                }
                replacements.append(resolvedReplacement)
            }
        }

        // Extract position for append/insert operations
        let insertPosition = getString(data, "insertPosition") ?? "end" // start, end, or index
        let insertIndex = getInt(data, "insertIndex")

        // Extract sharing configuration
        var sharing: [String: Any]?
        if let shareConfig = data["sharing"] as? [String: Any] {
            sharing = resolveVariablesInDictionary(shareConfig, state: state)
        }

        // Extract response variable name
        let responseVariable = getString(data, "responseVariable") ?? "google_docs_response"

        // Get session ID from state
        let sessionId = state.sessionId ?? state.getVariable(name: "_sessionId") as? String ?? ""
        let botId = state.record["botId"] as? String ?? ""

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": sessionId,
            "botId": botId,
            "nodeId": nodeId,
            "nodeType": "google_docs",
            "operation": operation,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        // Add document configuration
        if let docId = documentId { payload["documentId"] = docId }
        if let docTitle = title { payload["title"] = docTitle }
        if let docContent = content { payload["content"] = docContent }
        if let folder = folderId { payload["folderId"] = folder }
        if let template = templateId { payload["templateId"] = template }

        // Add field mappings for template operations
        if !fieldMappings.isEmpty { payload["fieldMappings"] = fieldMappings }

        // Add text replacements for update operations
        if !replacements.isEmpty { payload["replacements"] = replacements }

        // Add position information for append/insert operations
        payload["insertPosition"] = insertPosition
        if let index = insertIndex { payload["insertIndex"] = index }

        // Add sharing configuration
        if let share = sharing { payload["sharing"] = share }

        // Emit socket event for server processing
        socketClient?.emit(SocketEvents.googleDocsNodeTrigger, payload)

        #if DEBUG
        print("[Conferbot] Google Docs \(operation) event emitted for server processing")
        #endif

        // Record the response
        state.addToTranscript(entry: [
            "type": "system",
            "nodeType": "google_docs",
            "operation": operation,
            "nodeId": nodeId,
            "documentId": documentId as Any,
            "title": title as Any
        ])

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, ["googleDocsOperation": operation])
    }

    /// Resolve variables in a dictionary's string values
    private func resolveVariablesInDictionary(_ dict: [String: Any], state: ChatState) -> [String: Any] {
        var resolved: [String: Any] = [:]
        for (key, value) in dict {
            if let stringValue = value as? String {
                resolved[key] = state.resolveVariables(text: stringValue)
            } else if let nestedDict = value as? [String: Any] {
                resolved[key] = resolveVariablesInDictionary(nestedDict, state: state)
            } else if let array = value as? [[String: Any]] {
                resolved[key] = array.map { resolveVariablesInDictionary($0, state: state) }
            } else {
                resolved[key] = value
            }
        }
        return resolved
    }
}

/// Handler for Google Drive integration nodes
/// Emits socket event for server-side file/folder operations on Google Drive
public class GoogleDriveNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Integration.googleDrive }

    /// Reference to socket client for emitting events
    private weak var socketClient: SocketClient?

    public init(socketClient: SocketClient? = nil) {
        self.socketClient = socketClient
        super.init()
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Google Drive node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract operation type (upload, download, create_folder, list, share, delete, move, copy)
        let operation = getString(data, "operation") ?? "upload"

        // Extract file/folder configuration with variable resolution
        let fileId = getString(data, "fileId").map { state.resolveVariables(text: $0) }
        let folderId = getString(data, "folderId").map { state.resolveVariables(text: $0) }
        let fileName = getString(data, "fileName").map { state.resolveVariables(text: $0) }
        let folderName = getString(data, "folderName").map { state.resolveVariables(text: $0) }
        let mimeType = getString(data, "mimeType").map { state.resolveVariables(text: $0) }
        let fileContent = getString(data, "fileContent").map { state.resolveVariables(text: $0) }
        let fileUrl = getString(data, "fileUrl").map { state.resolveVariables(text: $0) }

        // Extract sharing configuration
        let shareEmail = getString(data, "shareEmail").map { state.resolveVariables(text: $0) }
        let shareRole = getString(data, "shareRole") ?? "reader" // reader, writer, commenter, owner
        let shareType = getString(data, "shareType") ?? "user" // user, group, domain, anyone
        let sendNotification = getBool(data, "sendNotification") ?? true

        // Extract search/list configuration
        let query = getString(data, "query").map { state.resolveVariables(text: $0) }
        let pageSize = getInt(data, "pageSize") ?? 100
        let orderBy = getString(data, "orderBy") ?? "modifiedTime desc"
        let includeTrash = getBool(data, "includeTrash") ?? false

        // Extract destination for move/copy operations
        let destinationFolderId = getString(data, "destinationFolderId").map { state.resolveVariables(text: $0) }

        // Extract response variable name for storing results
        let responseVariable = getString(data, "responseVariable") ?? "drive_response"

        // Extract field mappings if provided (for storing specific response fields in variables)
        var fieldMappings: [String: String] = [:]
        if let mappings = data["fieldMappings"] as? [String: String] {
            for (responseField, variableName) in mappings {
                fieldMappings[responseField] = state.resolveVariables(text: variableName)
            }
        }

        // Get session ID from state
        let sessionId = state.sessionId ?? state.getVariable(name: "_sessionId") as? String ?? ""
        let botId = state.record["botId"] as? String ?? ""

        // Build the payload for server processing
        var payload: [String: Any] = [
            "chatSessionId": sessionId,
            "botId": botId,
            "nodeId": nodeId,
            "nodeType": "google_drive",
            "operation": operation,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        // Add operation-specific parameters
        switch operation {
        case "upload":
            if let name = fileName { payload["fileName"] = name }
            if let folder = folderId { payload["folderId"] = folder }
            if let mime = mimeType { payload["mimeType"] = mime }
            if let content = fileContent { payload["fileContent"] = content }
            if let url = fileUrl { payload["fileUrl"] = url }

            // Check for file data from a previous file upload node
            if let uploadedFile = state.getVariable(name: "_uploadedFile") {
                payload["uploadedFile"] = uploadedFile
            }
            if let uploadedFileKey = getString(data, "uploadedFileVariable"),
               let uploadedFile = state.getVariable(name: uploadedFileKey) {
                payload["uploadedFile"] = uploadedFile
            }

        case "download":
            if let file = fileId { payload["fileId"] = file }
            if let name = fileName { payload["fileName"] = name }

        case "create_folder":
            if let name = folderName ?? fileName { payload["folderName"] = name }
            if let parent = folderId { payload["parentFolderId"] = parent }

        case "list":
            if let folder = folderId { payload["folderId"] = folder }
            if let q = query { payload["query"] = q }
            payload["pageSize"] = pageSize
            payload["orderBy"] = orderBy
            payload["includeTrash"] = includeTrash

        case "share":
            if let file = fileId { payload["fileId"] = file }
            if let email = shareEmail { payload["shareEmail"] = email }
            payload["shareRole"] = shareRole
            payload["shareType"] = shareType
            payload["sendNotification"] = sendNotification

            // Optionally include email message for notification
            if let message = getString(data, "shareMessage").map({ state.resolveVariables(text: $0) }) {
                payload["shareMessage"] = message
            }

        case "delete":
            if let file = fileId { payload["fileId"] = file }
            // Optionally support permanent deletion vs trash
            payload["permanent"] = getBool(data, "permanent") ?? false

        case "move":
            if let file = fileId { payload["fileId"] = file }
            if let dest = destinationFolderId { payload["destinationFolderId"] = dest }

        case "copy":
            if let file = fileId { payload["fileId"] = file }
            if let dest = destinationFolderId { payload["destinationFolderId"] = dest }
            if let name = fileName { payload["newFileName"] = name }

        case "get_info":
            if let file = fileId { payload["fileId"] = file }

        case "search":
            if let q = query { payload["query"] = q }
            payload["pageSize"] = pageSize
            payload["orderBy"] = orderBy
            payload["includeTrash"] = includeTrash

        default:
            // For any custom operations, include all node data with resolved variables
            for (key, value) in data {
                if !["operation", "type", "id", "nodeType"].contains(key) {
                    if let stringValue = value as? String {
                        payload[key] = state.resolveVariables(text: stringValue)
                    } else if let dictValue = value as? [String: Any] {
                        payload[key] = resolveVariablesInDictionary(dictValue, state: state)
                    } else {
                        payload[key] = value
                    }
                }
            }
        }

        // Add field mappings if provided
        if !fieldMappings.isEmpty {
            payload["fieldMappings"] = fieldMappings
        }

        // Emit socket event for server processing
        socketClient?.emit(SocketEvents.googleDriveNodeTrigger, payload)

        #if DEBUG
        print("[Conferbot] Google Drive \(operation) event emitted for server processing")
        #endif

        // Record the response
        state.addToTranscript(entry: [
            "type": "system",
            "nodeType": "google_drive",
            "operation": operation,
            "nodeId": nodeId,
            "fileId": fileId as Any,
            "folderId": folderId as Any
        ])

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, ["googleDriveOperation": operation])
    }

    /// Resolve variables in a dictionary's string values
    private func resolveVariablesInDictionary(_ dict: [String: Any], state: ChatState) -> [String: Any] {
        var resolved: [String: Any] = [:]
        for (key, value) in dict {
            if let stringValue = value as? String {
                resolved[key] = state.resolveVariables(text: stringValue)
            } else if let nestedDict = value as? [String: Any] {
                resolved[key] = resolveVariablesInDictionary(nestedDict, state: state)
            } else if let array = value as? [[String: Any]] {
                resolved[key] = array.map { resolveVariablesInDictionary($0, state: state) }
            } else {
                resolved[key] = value
            }
        }
        return resolved
    }
}

// MARK: - Google Calendar Node Handler

/// Handler for Google Calendar integration nodes
/// Supports booking appointments, creating events, and listing available slots
public class GoogleCalendarNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Integration.googleCalendar }

    /// Reference to socket client for emitting events
    private weak var socketClient: SocketClient?

    public init(socketClient: SocketClient? = nil) {
        self.socketClient = socketClient
        super.init()
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Google Calendar node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract operation type (book, create, list, update, delete)
        let operation = getString(data, "operation") ?? "book"

        // Handle booking operation - display calendar UI for slot selection
        if operation == "book" {
            // Extract timezone (default to device timezone)
            let timezone = getString(data, "timeZone") ?? TimeZone.current.identifier

            // Extract answer variable name for storing the result
            let answerVariable = getString(data, "answerVariable") ?? "calendar_booking"

            // Extract event configuration
            let eventTitle = getString(data, "title") ?? "Select a date and time"
            let duration = getInt(data, "duration") ?? 30 // Default 30 minutes

            // Extract attendee collection settings
            let collectAttendeeEmail = getBool(data, "collectAttendeeEmail") ?? false

            // Extract calendar settings
            let excludeWeekends = getBool(data, "excludeWeekends") ?? false

            // Display calendar for date/time selection
            // The CalendarMode.dateTime allows user to pick both date and time
            return .displayUI(.calendar(mode: .dateTime, nodeId: nodeId))
        }

        // For other operations (create, list, update, delete), emit socket event and proceed
        let sessionId = state.sessionId ?? state.getVariable(name: "_sessionId") as? String ?? ""
        let botId = state.record["botId"] as? String ?? ""

        // Build payload for server processing
        var payload: [String: Any] = [
            "chatSessionId": sessionId,
            "botId": botId,
            "nodeId": nodeId,
            "nodeType": "google_calendar",
            "operation": operation,
            "variables": state.variables
        ]

        // Extract common configuration
        if let timezone = getString(data, "timeZone") {
            payload["timezone"] = state.resolveVariables(text: timezone)
        }
        if let calendarId = getString(data, "calendarId") {
            payload["calendarId"] = state.resolveVariables(text: calendarId)
        }
        if let title = getString(data, "title") {
            payload["title"] = state.resolveVariables(text: title)
        }
        if let description = getString(data, "description") {
            payload["description"] = state.resolveVariables(text: description)
        }
        if let location = getString(data, "location") {
            payload["location"] = state.resolveVariables(text: location)
        }
        if let duration = getInt(data, "duration") {
            payload["duration"] = duration
        }
        if let startTime = getString(data, "startTime") {
            payload["startTime"] = state.resolveVariables(text: startTime)
        }
        if let endTime = getString(data, "endTime") {
            payload["endTime"] = state.resolveVariables(text: endTime)
        }
        if let eventId = getString(data, "eventId") {
            payload["eventId"] = state.resolveVariables(text: eventId)
        }
        if let minDate = getString(data, "minDate") {
            payload["minDate"] = state.resolveVariables(text: minDate)
        }
        if let maxDate = getString(data, "maxDate") {
            payload["maxDate"] = state.resolveVariables(text: maxDate)
        }
        if let responseVariable = getString(data, "responseVariable") {
            payload["responseVariable"] = responseVariable
        }

        // Extract attendees
        if let attendees = data["attendees"] as? [String] {
            payload["attendees"] = attendees.map { state.resolveVariables(text: $0) }
        }
        if let attendeeEmail = getString(data, "attendeeEmail") {
            payload["attendeeEmail"] = state.resolveVariables(text: attendeeEmail)
        }

        // Extract reminders configuration
        if let reminders = data["reminders"] as? [String: Any] {
            payload["reminders"] = resolveVariablesInDictionary(reminders, state: state)
        }

        // Emit socket event for server processing
        socketClient?.emit(SocketEvents.googleCalendarNodeTrigger, payload)

        #if DEBUG
        print("[Conferbot] Google Calendar \(operation) event emitted for server processing")
        #endif

        // Record the response
        state.addToTranscript(entry: [
            "type": "system",
            "nodeType": "google_calendar",
            "operation": operation,
            "nodeId": nodeId
        ])

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, ["googleCalendarOperation": operation])
    }

    /// Resolve variables in a dictionary's string values
    private func resolveVariablesInDictionary(_ dict: [String: Any], state: ChatState) -> [String: Any] {
        var resolved: [String: Any] = [:]
        for (key, value) in dict {
            if let stringValue = value as? String {
                resolved[key] = state.resolveVariables(text: stringValue)
            } else if let nestedDict = value as? [String: Any] {
                resolved[key] = resolveVariablesInDictionary(nestedDict, state: state)
            } else if let array = value as? [[String: Any]] {
                resolved[key] = array.map { resolveVariablesInDictionary($0, state: state) }
            } else {
                resolved[key] = value
            }
        }
        return resolved
    }
}

// MARK: - Notion Node Handler

/// Handler for Notion integration nodes (databases and pages)
public class NotionNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Integration.notion }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let nodeId = getString(node, "id") ?? "unknown"
        let data = node["data"] as? [String: Any] ?? [:]

        #if DEBUG
        print("[Conferbot] Processing Notion node: \(nodeId)")
        #endif

        // Extract operation type (createPage, updatePage, queryDatabase, createDatabase, etc.)
        let operation = getString(data, "operation") ?? "createPage"

        // Extract database/page configuration
        let databaseId = getString(data, "databaseId").map { state.resolveVariables(text: $0) }
        let pageId = getString(data, "pageId").map { state.resolveVariables(text: $0) }

        // Extract page properties with variable resolution
        var properties: [String: Any] = [:]
        if let props = data["properties"] as? [String: Any] {
            properties = resolveVariablesInDictionary(props, state: state)
        }

        // Extract property mappings (maps conversation variables to Notion properties)
        if let mappings = data["propertyMappings"] as? [[String: Any]] {
            for mapping in mappings {
                if let notionProperty = mapping["notionProperty"] as? String,
                   let variableName = mapping["variableName"] as? String {
                    // Get value from state variables
                    if let value = state.getVariable(variableName) {
                        // Determine property type and format appropriately
                        let propertyType = mapping["propertyType"] as? String ?? "text"
                        properties[notionProperty] = formatPropertyValue(value, type: propertyType)
                    } else if let defaultValue = mapping["defaultValue"] {
                        let propertyType = mapping["propertyType"] as? String ?? "text"
                        properties[notionProperty] = formatPropertyValue(defaultValue, type: propertyType)
                    }
                }
            }
        }

        // Extract content blocks for page content
        var contentBlocks: [[String: Any]] = []
        if let blocks = data["content"] as? [[String: Any]] {
            contentBlocks = blocks.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract page title with variable resolution
        let pageTitle = getString(data, "title").map { state.resolveVariables(text: $0) }

        // Extract parent configuration for creating new pages/databases
        var parentConfig: [String: Any]?
        if let parent = data["parent"] as? [String: Any] {
            parentConfig = resolveVariablesInDictionary(parent, state: state)
        }

        // Extract filter for database queries
        var queryFilter: [String: Any]?
        if let filter = data["filter"] as? [String: Any] {
            queryFilter = resolveVariablesInDictionary(filter, state: state)
        }

        // Extract sort configuration for database queries
        var sorts: [[String: Any]]?
        if let sortConfig = data["sorts"] as? [[String: Any]] {
            sorts = sortConfig.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract response variable name for storing results
        let responseVariable = getString(data, "responseVariable") ?? "notion_response"

        // Extract icon and cover for page creation
        let icon = getString(data, "icon").map { state.resolveVariables(text: $0) }
        let cover = getString(data, "cover").map { state.resolveVariables(text: $0) }

        // Get session ID and bot ID from state
        let sessionId = state.sessionId ?? state.getVariable(name: "_sessionId") as? String ?? ""
        let botId = state.record["botId"] as? String ?? ""

        // Build payload for server processing
        var payload: [String: Any] = [
            "chatSessionId": sessionId,
            "botId": botId,
            "nodeType": "notion",
            "operation": operation,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        // Add optional fields based on operation
        if let dbId = databaseId { payload["databaseId"] = dbId }
        if let pgId = pageId { payload["pageId"] = pgId }
        if !properties.isEmpty { payload["properties"] = properties }
        if !contentBlocks.isEmpty { payload["content"] = contentBlocks }
        if let title = pageTitle { payload["title"] = title }
        if let parent = parentConfig { payload["parent"] = parent }
        if let filter = queryFilter { payload["filter"] = filter }
        if let sortConfig = sorts { payload["sorts"] = sortConfig }
        if let iconValue = icon { payload["icon"] = iconValue }
        if let coverValue = cover { payload["cover"] = coverValue }

        // Add include/exclude archived option for queries
        if let includeArchived = data["includeArchived"] as? Bool {
            payload["includeArchived"] = includeArchived
        }

        // Add page size for paginated queries
        if let pageSize = data["pageSize"] as? Int {
            payload["pageSize"] = pageSize
        }

        // Add start cursor for pagination
        if let startCursor = getString(data, "startCursor") {
            payload["startCursor"] = state.resolveVariables(text: startCursor)
        }

        // Emit socket event for server processing
        socketClient?.emit(SocketEvents.notionNodeTrigger, payload)

        #if DEBUG
        print("[Conferbot] Notion \(operation) event emitted for server processing")
        #endif

        // Record the response
        state.addToTranscript(entry: [
            "type": "system",
            "nodeType": "notion",
            "operation": operation,
            "nodeId": nodeId,
            "databaseId": databaseId as Any,
            "pageId": pageId as Any
        ])

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, ["notionOperation": operation])
    }

    /// Format a value according to the Notion property type
    private func formatPropertyValue(_ value: Any, type: String) -> Any {
        switch type.lowercased() {
        case "title", "rich_text", "text":
            if let stringValue = value as? String {
                return ["type": "text", "value": stringValue]
            }
            return ["type": "text", "value": String(describing: value)]

        case "number":
            if let numValue = value as? Double { return numValue }
            if let numValue = value as? Int { return Double(numValue) }
            if let strValue = value as? String, let num = Double(strValue) { return num }
            return value

        case "select":
            if let stringValue = value as? String {
                return ["name": stringValue]
            }
            return value

        case "multi_select":
            if let arrayValue = value as? [String] {
                return arrayValue.map { ["name": $0] }
            }
            if let stringValue = value as? String {
                let options = stringValue.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return options.map { ["name": $0] }
            }
            return value

        case "date":
            if let stringValue = value as? String {
                return ["start": stringValue]
            }
            return value

        case "checkbox":
            if let boolValue = value as? Bool { return boolValue }
            if let stringValue = value as? String {
                return stringValue.lowercased() == "true" || stringValue == "1"
            }
            if let intValue = value as? Int { return intValue != 0 }
            return value

        case "url", "email", "phone_number":
            if let stringValue = value as? String { return stringValue }
            return String(describing: value)

        case "relation":
            if let arrayValue = value as? [String] {
                return arrayValue.map { ["id": $0] }
            }
            if let stringValue = value as? String {
                return [["id": stringValue]]
            }
            return value

        default:
            return value
        }
    }

    /// Resolve variables in a dictionary's string values
    private func resolveVariablesInDictionary(_ dict: [String: Any], state: ChatState) -> [String: Any] {
        var resolved: [String: Any] = [:]
        for (key, value) in dict {
            if let stringValue = value as? String {
                resolved[key] = state.resolveVariables(text: stringValue)
            } else if let nestedDict = value as? [String: Any] {
                resolved[key] = resolveVariablesInDictionary(nestedDict, state: state)
            } else if let array = value as? [[String: Any]] {
                resolved[key] = array.map { resolveVariablesInDictionary($0, state: state) }
            } else {
                resolved[key] = value
            }
        }
        return resolved
    }
}

// MARK: - Stripe Node Handler

/// Handler for Stripe payment integration nodes
/// Creates payment links/checkout sessions via server-side integration
/// Properly waits for server response with payment URL before displaying UI
public class StripeNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Integration.stripe }

    /// Reference to socket client for emitting events
    private weak var socketClient: SocketClient?

    /// Timeout for waiting for payment URL response (in seconds)
    private let paymentUrlTimeout: TimeInterval = 30.0

    public init(socketClient: SocketClient? = nil) {
        self.socketClient = socketClient
        super.init()
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Stripe node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract operation type
        let operation = getString(data, "operation") ?? "createPaymentLink"

        // Extract payment details
        let amount = extractAmount(from: data)
        let currency = (getString(data, "currency") ?? "USD").uppercased()
        let description = getString(data, "description").map { state.resolveVariables(text: $0) }

        // Extract product information
        let productName = getString(data, "productName").map { state.resolveVariables(text: $0) }
        let productDescription = getString(data, "productDescription").map { state.resolveVariables(text: $0) }
        let productImage = getString(data, "productImage")

        // Extract customer information from state
        let customerEmail = getString(data, "customerEmail").map { state.resolveVariables(text: $0) }
            ?? state.getVariable(name: "email") as? String
        let customerName = getString(data, "customerName").map { state.resolveVariables(text: $0) }
            ?? state.getVariable(name: "name") as? String

        // Extract success/cancel URLs for checkout session
        let successUrl = getString(data, "successUrl").map { state.resolveVariables(text: $0) }
        let cancelUrl = getString(data, "cancelUrl").map { state.resolveVariables(text: $0) }

        // Extract metadata to attach to payment
        var metadata: [String: String] = [:]
        if let customMetadata = data["metadata"] as? [String: Any] {
            for (key, value) in customMetadata {
                if let stringValue = value as? String {
                    metadata[key] = state.resolveVariables(text: stringValue)
                } else {
                    metadata[key] = String(describing: value)
                }
            }
        }
        // Add session info to metadata
        let sessionId = state.sessionId ?? ""
        let botId = state.record["botId"] as? String ?? ""
        metadata["chatSessionId"] = sessionId
        metadata["botId"] = botId

        // Extract answer variable for storing payment result
        let answerVariable = getString(data, "answerVariable") ?? "stripe_payment"

        // Build socket payload
        var payload: [String: Any] = [
            "chatSessionId": sessionId,
            "botId": botId,
            "nodeId": nodeId,
            "nodeType": "stripe",
            "operation": operation,
            "currency": currency,
            "metadata": metadata,
            "answerVariable": answerVariable,
            "variables": state.variables
        ]

        // Add amount (convert to cents for Stripe)
        if let amountValue = amount {
            payload["amount"] = amountValue
            // Also include display amount
            payload["displayAmount"] = Double(amountValue) / 100.0
        }

        // Add optional fields
        if let desc = description { payload["description"] = desc }
        if let prodName = productName { payload["productName"] = prodName }
        if let prodDesc = productDescription { payload["productDescription"] = prodDesc }
        if let prodImage = productImage { payload["productImage"] = prodImage }
        if let email = customerEmail { payload["customerEmail"] = email }
        if let name = customerName { payload["customerName"] = name }
        if let success = successUrl { payload["successUrl"] = success }
        if let cancel = cancelUrl { payload["cancelUrl"] = cancel }

        // For payment operations, we need to emit event and let the server respond
        // The UI layer should listen for the stripe-payment-url-response event
        if operation == "createPaymentLink" || operation == "createCheckoutSession" {
            // Emit socket event for server to create payment session
            socketClient?.emit(SocketEvents.stripeNodeTrigger, payload)

            #if DEBUG
            print("[Conferbot] Stripe \(operation) event emitted, waiting for payment URL response")
            #endif

            // Return a payment UI state that indicates we're waiting for URL
            // The actual URL will come via socket event: stripe-payment-url-response
            let displayAmount = amount.flatMap { Double($0) / 100.0 }

            return .displayUI(.payment(
                paymentUrl: "", // Will be populated by socket response
                amount: displayAmount,
                currency: currency,
                description: description,
                nodeId: nodeId
            ))
        }

        // For non-payment operations (createCustomer, listProducts, etc.)
        // Just emit the event and proceed
        socketClient?.emit(SocketEvents.stripeNodeTrigger, payload)

        #if DEBUG
        print("[Conferbot] Stripe \(operation) event emitted for server processing")
        #endif

        // Record the operation in transcript
        state.addToTranscript(entry: [
            "type": "system",
            "nodeType": "stripe",
            "operation": operation,
            "nodeId": nodeId,
            "amount": amount as Any,
            "currency": currency
        ])

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, ["stripeOperation": operation])
    }

    /// Extract amount from node data, converting to cents if necessary
    private func extractAmount(from data: [String: Any]) -> Int? {
        // Try customAmount first (from node data)
        if let customAmount = data["customAmount"] {
            return convertToCents(customAmount)
        }

        // Try amount field
        if let amount = data["amount"] {
            return convertToCents(amount)
        }

        // Try price field
        if let price = data["price"] {
            return convertToCents(price)
        }

        return nil
    }

    /// Convert various amount formats to cents (integer)
    private func convertToCents(_ value: Any) -> Int? {
        switch value {
        case let intValue as Int:
            // Assume already in cents if > 1000, otherwise convert
            return intValue > 1000 ? intValue : intValue * 100
        case let doubleValue as Double:
            // Assume in dollars, convert to cents
            return Int(doubleValue * 100)
        case let stringValue as String:
            // Try to parse as double first (dollars)
            if let doubleValue = Double(stringValue) {
                return Int(doubleValue * 100)
            }
            // Try to parse as int (cents)
            if let intValue = Int(stringValue) {
                return intValue > 1000 ? intValue : intValue * 100
            }
            return nil
        default:
            return nil
        }
    }
}
