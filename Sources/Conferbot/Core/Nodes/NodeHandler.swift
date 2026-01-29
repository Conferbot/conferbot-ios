//
//  NodeHandler.swift
//  Conferbot
//
//  Node handler infrastructure for processing chatbot nodes
//

import Foundation

// MARK: - Node Result

/// Result of processing a node, determining what happens next
public enum NodeResult {
    /// Display UI and wait for user interaction
    case displayUI(NodeUIState)

    /// Continue to next node with optional data
    /// - Parameters:
    ///   - nextNodeId: Optional specific node to proceed to
    ///   - data: Optional data to pass forward
    case proceed(String?, [String: Any]?)

    /// Wait for a duration then proceed
    /// - Parameters:
    ///   - delay: Time interval to wait
    ///   - nextNodeId: Optional specific node to proceed to
    case delayedProceed(TimeInterval, String?)

    /// Jump to a specific node by ID
    case jumpTo(String)

    /// An error occurred during node processing
    case error(String)
}

// MARK: - Node UI State

/// UI state to render for a node
public enum NodeUIState {
    /// Display a text message
    case message(text: String, typing: Bool)

    /// Display an image
    case image(url: String, caption: String?)

    /// Display a video
    case video(url: String, caption: String?)

    /// Display audio player
    case audio(url: String)

    /// Display a file download
    case file(url: String, name: String)

    /// Display a GIF
    case gif(url: String)

    /// Display text input field
    case textInput(placeholder: String?, validation: InputValidation?, nodeId: String)

    /// Display single choice selection
    case singleChoice(options: [ChoiceOption], nodeId: String)

    /// Display multiple choice selection
    case multiChoice(options: [ChoiceOption], nodeId: String)

    /// Display action buttons
    case buttons(buttons: [ButtonOption], nodeId: String)

    /// Display quick reply options
    case quickReplies(options: [ChoiceOption], nodeId: String)

    /// Display card carousel
    case cards(cards: [CardData], nodeId: String)

    /// Display rating input
    case rating(max: Int, style: RatingStyle, nodeId: String)

    /// Display opinion scale
    case opinionScale(min: Int, max: Int, minLabel: String?, maxLabel: String?, nodeId: String)

    /// Display calendar picker
    case calendar(mode: CalendarMode, nodeId: String)

    /// Display file upload
    case fileUpload(allowedTypes: [String], maxSize: Int?, nodeId: String)

    /// Initiate live chat
    case liveChat(message: String?)

    /// Initiate human handover
    case humanHandover(message: String?)

    /// Display a link
    case link(url: String, text: String?)

    /// Display embedded HTML content
    case embed(html: String)

    /// Display payment UI (Stripe, etc.)
    /// - Parameters:
    ///   - paymentUrl: The URL to open for payment (checkout session URL)
    ///   - amount: Optional payment amount for display
    ///   - currency: Currency code (e.g., "USD", "EUR")
    ///   - description: Optional description of the payment
    ///   - nodeId: The node ID for tracking
    case payment(paymentUrl: String, amount: Double?, currency: String, description: String?, nodeId: String)

    /// Display loading state
    case loading

    /// No UI to display
    case none
}

// MARK: - Input Validation

/// Validation types for text input
public enum InputValidation: Equatable {
    case email
    case phone
    case url
    case number
    case date
    case custom(String)

    /// Validate input against this validation type
    /// - Parameter input: The input string to validate
    /// - Returns: True if valid, false otherwise
    public func validate(_ input: String) -> Bool {
        switch self {
        case .email:
            let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
            return input.range(of: emailRegex, options: .regularExpression) != nil

        case .phone:
            let phoneRegex = #"^[\+]?[(]?[0-9]{1,4}[)]?[-\s\./0-9]*$"#
            return input.range(of: phoneRegex, options: .regularExpression) != nil

        case .url:
            if let url = URL(string: input) {
                return url.scheme != nil && url.host != nil
            }
            return false

        case .number:
            return Double(input) != nil

        case .date:
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            return dateFormatter.date(from: input) != nil

        case .custom(let pattern):
            return input.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// Get error message for this validation type
    public var errorMessage: String {
        switch self {
        case .email:
            return "Please enter a valid email address"
        case .phone:
            return "Please enter a valid phone number"
        case .url:
            return "Please enter a valid URL"
        case .number:
            return "Please enter a valid number"
        case .date:
            return "Please enter a valid date"
        case .custom:
            return "Please enter a valid value"
        }
    }
}

// MARK: - Choice Option

/// Option for single/multi choice and quick replies
public struct ChoiceOption: Identifiable, Equatable, Codable {
    public let id: String
    public let label: String
    public let value: String
    public let imageUrl: String?

    public init(id: String, label: String, value: String, imageUrl: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.imageUrl = imageUrl
    }

    public init(from dict: [String: Any]) {
        self.id = dict["id"] as? String ?? UUID().uuidString
        self.label = dict["label"] as? String ?? dict["text"] as? String ?? ""
        self.value = dict["value"] as? String ?? self.label
        self.imageUrl = dict["imageUrl"] as? String ?? dict["image"] as? String
    }
}

// MARK: - Button Option

/// Option for action buttons
public struct ButtonOption: Identifiable, Equatable, Codable {
    public let id: String
    public let label: String
    public let url: String?
    public let action: String?

    public init(id: String, label: String, url: String? = nil, action: String? = nil) {
        self.id = id
        self.label = label
        self.url = url
        self.action = action
    }

    public init(from dict: [String: Any]) {
        self.id = dict["id"] as? String ?? UUID().uuidString
        self.label = dict["label"] as? String ?? dict["text"] as? String ?? ""
        self.url = dict["url"] as? String
        self.action = dict["action"] as? String ?? dict["type"] as? String
    }

    /// Whether this button opens a URL
    public var isLink: Bool {
        return url != nil && !url!.isEmpty
    }
}

// MARK: - Card Data

/// Data for card carousel items
public struct CardData: Identifiable, Equatable, Codable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let imageUrl: String?
    public let buttons: [ButtonOption]

    public init(id: String, title: String, subtitle: String? = nil, imageUrl: String? = nil, buttons: [ButtonOption] = []) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.imageUrl = imageUrl
        self.buttons = buttons
    }

    public init(from dict: [String: Any]) {
        self.id = dict["id"] as? String ?? UUID().uuidString
        self.title = dict["title"] as? String ?? ""
        self.subtitle = dict["subtitle"] as? String ?? dict["description"] as? String
        self.imageUrl = dict["imageUrl"] as? String ?? dict["image"] as? String

        if let buttonDicts = dict["buttons"] as? [[String: Any]] {
            self.buttons = buttonDicts.map { ButtonOption(from: $0) }
        } else {
            self.buttons = []
        }
    }
}

// MARK: - Rating Style

/// Style for rating input
public enum RatingStyle: String, Codable, CaseIterable {
    case stars
    case hearts
    case thumbs
    case emojis

    /// Get the SF Symbol name for this rating style
    public var symbolName: String {
        switch self {
        case .stars:
            return "star.fill"
        case .hearts:
            return "heart.fill"
        case .thumbs:
            return "hand.thumbsup.fill"
        case .emojis:
            return "face.smiling.fill"
        }
    }

    /// Get emoji array for emoji style
    public var emojis: [String] {
        return ["1", "2", "3", "4", "5"]
    }
}

// MARK: - Calendar Mode

/// Mode for calendar picker
public enum CalendarMode: String, Codable, CaseIterable {
    case date
    case time
    case dateTime
    case dateRange

    /// Display format for this mode
    public var dateFormat: String {
        switch self {
        case .date:
            return "yyyy-MM-dd"
        case .time:
            return "HH:mm"
        case .dateTime:
            return "yyyy-MM-dd HH:mm"
        case .dateRange:
            return "yyyy-MM-dd"
        }
    }
}

// MARK: - Node Handler Protocol

/// Protocol for handling specific node types
public protocol NodeHandler {
    /// The type of node this handler processes
    var nodeType: String { get }

    /// Handle the node and return a result
    /// - Parameters:
    ///   - node: The node data dictionary
    ///   - state: Current chat state
    /// - Returns: The result of processing this node
    func handle(node: [String: Any], state: ChatState) async -> NodeResult
}

// MARK: - Base Node Handler

/// Base class with helper methods for node handlers
open class BaseNodeHandler: NodeHandler {

    public var nodeType: String {
        fatalError("Subclasses must override nodeType")
    }

    public init() {}

    /// Handle the node - must be overridden by subclasses
    open func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        fatalError("Subclasses must override handle(node:state:)")
    }

    // MARK: - Helper Methods

    /// Extract the data dictionary from a node
    /// - Parameter node: The node dictionary
    /// - Returns: The data dictionary if present
    public func getNodeData(_ node: [String: Any]) -> [String: Any]? {
        return node["data"] as? [String: Any]
    }

    /// Get a string value from a dictionary
    /// - Parameters:
    ///   - dict: The dictionary to read from
    ///   - key: The key to look up
    /// - Returns: The string value if present
    public func getString(_ dict: [String: Any], _ key: String) -> String? {
        return dict[key] as? String
    }

    /// Get an integer value from a dictionary
    /// - Parameters:
    ///   - dict: The dictionary to read from
    ///   - key: The key to look up
    /// - Returns: The integer value if present
    public func getInt(_ dict: [String: Any], _ key: String) -> Int? {
        if let intValue = dict[key] as? Int {
            return intValue
        }
        if let stringValue = dict[key] as? String {
            return Int(stringValue)
        }
        if let doubleValue = dict[key] as? Double {
            return Int(doubleValue)
        }
        return nil
    }

    /// Get a boolean value from a dictionary
    /// - Parameters:
    ///   - dict: The dictionary to read from
    ///   - key: The key to look up
    /// - Returns: The boolean value if present
    public func getBool(_ dict: [String: Any], _ key: String) -> Bool? {
        if let boolValue = dict[key] as? Bool {
            return boolValue
        }
        if let intValue = dict[key] as? Int {
            return intValue != 0
        }
        if let stringValue = dict[key] as? String {
            return stringValue.lowercased() == "true" || stringValue == "1"
        }
        return nil
    }

    /// Get an array of dictionaries from a dictionary
    /// - Parameters:
    ///   - dict: The dictionary to read from
    ///   - key: The key to look up
    /// - Returns: The array of dictionaries if present
    public func getArray(_ dict: [String: Any], _ key: String) -> [[String: Any]]? {
        return dict[key] as? [[String: Any]]
    }

    /// Get the node ID from a node
    /// - Parameter node: The node dictionary
    /// - Returns: The node ID if present
    public func getNodeId(_ node: [String: Any]) -> String? {
        return getString(node, "id") ?? getString(node, "nodeId")
    }

    /// Get the next node ID from a node
    /// - Parameter node: The node dictionary
    /// - Returns: The next node ID if present
    public func getNextNodeId(_ node: [String: Any]) -> String? {
        if let data = getNodeData(node) {
            return getString(data, "nextNodeId") ?? getString(data, "next")
        }
        return getString(node, "nextNodeId") ?? getString(node, "next")
    }

    /// Parse choice options from an array of dictionaries
    /// - Parameter optionDicts: Array of option dictionaries
    /// - Returns: Array of ChoiceOption
    public func parseChoiceOptions(_ optionDicts: [[String: Any]]?) -> [ChoiceOption] {
        guard let dicts = optionDicts else { return [] }
        return dicts.map { ChoiceOption(from: $0) }
    }

    /// Parse button options from an array of dictionaries
    /// - Parameter buttonDicts: Array of button dictionaries
    /// - Returns: Array of ButtonOption
    public func parseButtonOptions(_ buttonDicts: [[String: Any]]?) -> [ButtonOption] {
        guard let dicts = buttonDicts else { return [] }
        return dicts.map { ButtonOption(from: $0) }
    }

    /// Parse card data from an array of dictionaries
    /// - Parameter cardDicts: Array of card dictionaries
    /// - Returns: Array of CardData
    public func parseCardData(_ cardDicts: [[String: Any]]?) -> [CardData] {
        guard let dicts = cardDicts else { return [] }
        return dicts.map { CardData(from: $0) }
    }

    /// Get a double value from a dictionary
    /// - Parameters:
    ///   - dict: The dictionary to read from
    ///   - key: The key to look up
    /// - Returns: The double value if present
    public func getDouble(_ dict: [String: Any], _ key: String) -> Double? {
        if let doubleValue = dict[key] as? Double {
            return doubleValue
        }
        if let intValue = dict[key] as? Int {
            return Double(intValue)
        }
        if let stringValue = dict[key] as? String {
            return Double(stringValue)
        }
        return nil
    }

    /// Get a string array from a dictionary
    /// - Parameters:
    ///   - dict: The dictionary to read from
    ///   - key: The key to look up
    /// - Returns: The string array if present
    public func getStringArray(_ dict: [String: Any], _ key: String) -> [String]? {
        return dict[key] as? [String]
    }
}
