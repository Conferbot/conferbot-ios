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

        // Variable handlers (legacy types)
        register(SetVariableNodeHandler())
        register(GetVariableNodeHandler())

        // Logic node handlers (new standardized types from NodeTypes.Logic)
        registerLogicHandlers()

        // Special flow node handlers (goal, end_conversation)
        registerSpecialFlowHandlers()
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
            return .error("No handler registered for node type: \(nodeType)")
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

// MARK: - Placeholder Node Handlers

// These are placeholder implementations that should be replaced with actual implementations

/// Handler for message nodes
public class MessageNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "message" }

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
    public override var nodeType: String { "image" }

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
    public override var nodeType: String { "video" }

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
    public override var nodeType: String { "audio" }

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
    public override var nodeType: String { "file" }

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
    public override var nodeType: String { "gif" }

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
    public override var nodeType: String { "textInput" }

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
    public override var nodeType: String { "singleChoice" }

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
    public override var nodeType: String { "multiChoice" }

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
    public override var nodeType: String { "buttons" }

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
    public override var nodeType: String { "quickReplies" }

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
    public override var nodeType: String { "cards" }

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
    public override var nodeType: String { "rating" }

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
    public override var nodeType: String { "opinionScale" }

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
    public override var nodeType: String { "calendar" }

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
    public override var nodeType: String { "fileUpload" }

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
    public override var nodeType: String { "liveChat" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let message = data != nil ? getString(data!, "message") : nil

        return .displayUI(.liveChat(message: message))
    }
}

/// Handler for human handover nodes
public class HumanHandoverNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "humanHandover" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let message = data != nil ? getString(data!, "message") : nil

        return .displayUI(.humanHandover(message: message))
    }
}

/// Handler for link nodes
public class LinkNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "link" }

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
    public override var nodeType: String { "embed" }

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
    public override var nodeType: String { "condition" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Delegate to ConditionalHandler for actual implementation
        let conditionalHandler = ConditionalHandler()
        return await conditionalHandler.handle(node: node, state: state)
    }
}

/// Handler for jump nodes
public class JumpNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "jump" }

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
    public override var nodeType: String { "delay" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Delegate to LogicDelayHandler for actual implementation
        let logicDelayHandler = LogicDelayHandler()
        return await logicDelayHandler.handle(node: node, state: state)
    }
}

/// Handler for end nodes
public class EndNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "end" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        return .displayUI(.none)
    }
}

/// Handler for webhook nodes
public class WebhookNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "webhook" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Webhook execution would be implemented here
        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}

/// Handler for API nodes
public class ApiNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "api" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // API call would be implemented here
        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}

/// Handler for email nodes
public class EmailNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "email" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Email sending would be implemented here
        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}

/// Handler for set variable nodes (legacy type)
public class SetVariableNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "setVariable" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Delegate to SetVariableHandler for actual implementation
        let setVariableHandler = SetVariableHandler()
        return await setVariableHandler.handle(node: node, state: state)
    }
}

/// Handler for get variable nodes
public class GetVariableNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "getVariable" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        // Variable getting would be implemented here
        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}
