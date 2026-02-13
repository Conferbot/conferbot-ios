//
//  ChatState.swift
//  Conferbot
//
//  Singleton class managing all chat state using Combine framework
//  for reactive updates throughout the SDK.
//

import Foundation
import Combine

/// ChatState is a singleton that manages all conversational state
/// including user answers, variables, metadata, and conversation history.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class ChatState: ObservableObject {

    // MARK: - Singleton Instance

    /// Shared singleton instance
    public static let shared = ChatState()

    // MARK: - Published Properties

    /// Stores user answers keyed by node ID
    @Published public private(set) var answerVariables: [String: Any] = [:]

    /// Flow variables for dynamic content
    @Published public private(set) var variables: [String: Any] = [:]

    /// User metadata (name, email, phone, etc.)
    @Published public private(set) var userMetadata: [String: Any] = [:]

    /// Complete conversation history
    @Published public private(set) var transcript: [[String: Any]] = []

    /// Current session record
    @Published public private(set) var record: [String: Any] = [:]

    /// Indicates if the bot is currently typing
    @Published public var isTyping: Bool = false

    /// Current node being processed
    @Published public var currentNodeId: String?

    // MARK: - Private Properties

    /// Lock for thread-safe access
    private let lock = NSLock()

    /// Maximum number of transcript entries to retain (prevents unbounded memory growth)
    private let maxTranscriptEntries = 500

    /// Variable pattern regex for {{varName}} syntax
    private let doubleBracePattern: NSRegularExpression? = {
        do {
            return try NSRegularExpression(
                pattern: "\\{\\{\\s*([a-zA-Z_][a-zA-Z0-9_.]*)\\s*\\}\\}",
                options: []
            )
        } catch {
            #if DEBUG
            print("[ChatState] Failed to compile doubleBracePattern regex: \(error)")
            #endif
            return nil
        }
    }()

    /// Variable pattern regex for ${varName} syntax
    private let dollarBracePattern: NSRegularExpression? = {
        do {
            return try NSRegularExpression(
                pattern: "\\$\\{\\s*([a-zA-Z_][a-zA-Z0-9_.]*)\\s*\\}",
                options: []
            )
        } catch {
            #if DEBUG
            print("[ChatState] Failed to compile dollarBracePattern regex: \(error)")
            #endif
            return nil
        }
    }()

    // MARK: - Initialization

    private init() {
        // Private initializer for singleton
    }

    // MARK: - Answer Management

    /// Sets an answer value for a specific node
    /// - Parameters:
    ///   - nodeId: The unique identifier of the node
    ///   - value: The answer value to store
    public func setAnswer(nodeId: String, value: Any) {
        lock.lock()
        defer { lock.unlock() }

        answerVariables[nodeId] = value

        // Also update the record with the answer
        var currentRecord = record
        var answers = currentRecord["answers"] as? [String: Any] ?? [:]
        answers[nodeId] = value
        currentRecord["answers"] = answers
        currentRecord["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        record = currentRecord
    }

    /// Retrieves an answer for a specific node
    /// - Parameter nodeId: The unique identifier of the node
    /// - Returns: The stored answer value, or nil if not found
    public func getAnswer(nodeId: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }

        return answerVariables[nodeId]
    }

    /// Retrieves all answers as a dictionary
    /// - Returns: A copy of all stored answers
    public func getAllAnswers() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        return answerVariables
    }

    // MARK: - Variable Management

    /// Sets a flow variable
    /// - Parameters:
    ///   - name: The variable name
    ///   - value: The variable value
    public func setVariable(name: String, value: Any) {
        lock.lock()
        defer { lock.unlock() }

        variables[name] = value
    }

    /// Retrieves a flow variable
    /// - Parameter name: The variable name
    /// - Returns: The variable value, or nil if not found
    public func getVariable(name: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }

        return variables[name]
    }

    /// Sets multiple variables at once
    /// - Parameter vars: Dictionary of variable names and values
    public func setVariables(_ vars: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }

        for (key, value) in vars {
            variables[key] = value
        }
    }

    // MARK: - Variable Resolution

    /// Resolves variable placeholders in text
    /// Supports both {{varName}} and ${varName} patterns
    /// - Parameter text: The text containing variable placeholders
    /// - Returns: The text with variables replaced by their values
    public func resolveVariables(text: String) -> String {
        lock.lock()
        let currentVariables = variables
        let currentAnswers = answerVariables
        let currentMetadata = userMetadata
        lock.unlock()

        var result = text

        // Process {{varName}} pattern
        if let doubleBracePattern = doubleBracePattern {
            result = resolvePattern(
                in: result,
                using: doubleBracePattern,
                variables: currentVariables,
                answers: currentAnswers,
                metadata: currentMetadata
            )
        }

        // Process ${varName} pattern
        if let dollarBracePattern = dollarBracePattern {
            result = resolvePattern(
                in: result,
                using: dollarBracePattern,
                variables: currentVariables,
                answers: currentAnswers,
                metadata: currentMetadata
            )
        }

        return result
    }

    /// Helper method to resolve a specific regex pattern
    private func resolvePattern(
        in text: String,
        using regex: NSRegularExpression,
        variables: [String: Any],
        answers: [String: Any],
        metadata: [String: Any]
    ) -> String {
        var result = text
        let range = NSRange(text.startIndex..., in: text)

        // Find all matches in reverse order to preserve indices
        let matches = regex.matches(in: text, options: [], range: range).reversed()

        for match in matches {
            guard let varNameRange = Range(match.range(at: 1), in: text),
                  let fullMatchRange = Range(match.range, in: text) else {
                continue
            }

            let varName = String(text[varNameRange])

            // Try to resolve the variable from different sources
            if let value = resolveValue(for: varName, variables: variables, answers: answers, metadata: metadata) {
                result = result.replacingCharacters(in: fullMatchRange, with: stringValue(from: value))
            }
        }

        return result
    }

    /// Resolves a variable name to its value
    private func resolveValue(
        for varName: String,
        variables: [String: Any],
        answers: [String: Any],
        metadata: [String: Any]
    ) -> Any? {
        // Check for dot notation (e.g., user.name)
        let parts = varName.split(separator: ".").map(String.init)

        if parts.count > 1 {
            let prefix = parts[0]
            let key = parts.dropFirst().joined(separator: ".")

            switch prefix {
            case "user", "metadata":
                return getNestedValue(from: metadata, path: key)
            case "answer", "answers":
                return getNestedValue(from: answers, path: key)
            case "var", "variable", "variables":
                return getNestedValue(from: variables, path: key)
            default:
                // Try as a nested path in variables
                return getNestedValue(from: variables, path: varName)
            }
        }

        // Simple variable name - check all sources
        // Priority: variables > answers > metadata
        if let value = variables[varName] {
            return value
        }
        if let value = answers[varName] {
            return value
        }
        if let value = metadata[varName] {
            return value
        }

        return nil
    }

    /// Gets a nested value from a dictionary using dot notation path
    private func getNestedValue(from dict: [String: Any], path: String) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any = dict

        for part in parts {
            if let dict = current as? [String: Any], let value = dict[part] {
                current = value
            } else if let array = current as? [Any], let index = Int(part), index < array.count {
                current = array[index]
            } else {
                return nil
            }
        }

        return current
    }

    /// Converts any value to a string representation
    private func stringValue(from value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        case let array as [Any]:
            return array.map { stringValue(from: $0) }.joined(separator: ", ")
        case let dict as [String: Any]:
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return String(describing: dict)
        default:
            return String(describing: value)
        }
    }

    // MARK: - Metadata Management

    /// Updates a single metadata value
    /// - Parameters:
    ///   - key: The metadata key
    ///   - value: The metadata value
    public func updateMetadata(key: String, value: Any) {
        lock.lock()
        defer { lock.unlock() }

        userMetadata[key] = value
    }

    /// Updates multiple metadata values at once
    /// - Parameter metadata: Dictionary of metadata to merge
    public func updateMetadata(_ metadata: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }

        for (key, value) in metadata {
            userMetadata[key] = value
        }
    }

    /// Retrieves a metadata value
    /// - Parameter key: The metadata key
    /// - Returns: The metadata value, or nil if not found
    public func getMetadata(key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }

        return userMetadata[key]
    }

    // MARK: - Transcript Management

    /// Adds an entry to the conversation transcript
    /// - Parameter entry: The transcript entry to add
    public func addToTranscript(entry: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }

        var entryWithTimestamp = entry
        if entryWithTimestamp["timestamp"] == nil {
            entryWithTimestamp["timestamp"] = ISO8601DateFormatter().string(from: Date())
        }

        transcript.append(entryWithTimestamp)

        // Enforce size limit to prevent unbounded memory growth
        if transcript.count > maxTranscriptEntries {
            transcript = Array(transcript.suffix(maxTranscriptEntries))
        }
    }

    /// Adds a bot message to the transcript
    /// - Parameters:
    ///   - message: The message content
    ///   - nodeId: Optional node ID
    ///   - nodeType: Optional node type
    public func addBotMessage(_ message: String, nodeId: String? = nil, nodeType: String? = nil) {
        var entry: [String: Any] = [
            "type": "bot",
            "message": message
        ]
        if let nodeId = nodeId {
            entry["nodeId"] = nodeId
        }
        if let nodeType = nodeType {
            entry["nodeType"] = nodeType
        }
        addToTranscript(entry: entry)
    }

    /// Adds a user message to the transcript
    /// - Parameters:
    ///   - message: The message content
    ///   - nodeId: Optional node ID that this is a response to
    public func addUserMessage(_ message: String, nodeId: String? = nil) {
        var entry: [String: Any] = [
            "type": "user",
            "message": message
        ]
        if let nodeId = nodeId {
            entry["nodeId"] = nodeId
        }
        addToTranscript(entry: entry)
    }

    /// Returns the full transcript
    /// - Returns: A copy of the transcript array
    public func getTranscript() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }

        return transcript
    }

    // MARK: - Record Management

    /// Updates the session record
    /// - Parameter updates: Dictionary of updates to merge
    public func updateRecord(_ updates: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }

        for (key, value) in updates {
            record[key] = value
        }
        record["updatedAt"] = ISO8601DateFormatter().string(from: Date())
    }

    /// Gets the current session record
    /// - Returns: A copy of the record dictionary
    public func getRecord() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        return record
    }

    /// Initializes a new session record
    /// - Parameters:
    ///   - sessionId: Unique session identifier
    ///   - botId: The bot identifier
    public func initializeRecord(sessionId: String, botId: String) {
        lock.lock()
        defer { lock.unlock() }

        let now = ISO8601DateFormatter().string(from: Date())
        record = [
            "sessionId": sessionId,
            "botId": botId,
            "createdAt": now,
            "updatedAt": now,
            "answers": [String: Any](),
            "metadata": [String: Any]()
        ]
    }

    // MARK: - Reset

    /// Resets all state to initial values
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        answerVariables = [:]
        variables = [:]
        userMetadata = [:]
        transcript = []
        record = [:]
        isTyping = false
        currentNodeId = nil
    }

    /// Resets only the conversation state while preserving user metadata
    public func resetConversation() {
        lock.lock()
        defer { lock.unlock() }

        answerVariables = [:]
        transcript = []
        isTyping = false
        currentNodeId = nil

        // Preserve session info but reset answers
        if let sessionId = record["sessionId"] as? String,
           let botId = record["botId"] as? String {
            let now = ISO8601DateFormatter().string(from: Date())
            record = [
                "sessionId": sessionId,
                "botId": botId,
                "createdAt": record["createdAt"] ?? now,
                "updatedAt": now,
                "answers": [String: Any](),
                "metadata": userMetadata
            ]
        }
    }
}

// MARK: - Convenience Extensions

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension ChatState {

    /// Checks if an answer exists for a node
    func hasAnswer(for nodeId: String) -> Bool {
        return getAnswer(nodeId: nodeId) != nil
    }

    /// Checks if a variable exists
    func hasVariable(_ name: String) -> Bool {
        return getVariable(name: name) != nil
    }

    /// Gets the answer as a specific type
    func getAnswer<T>(nodeId: String, as type: T.Type) -> T? {
        return getAnswer(nodeId: nodeId) as? T
    }

    /// Gets a variable as a specific type
    func getVariable<T>(name: String, as type: T.Type) -> T? {
        return getVariable(name: name) as? T
    }

    /// User convenience accessors
    var userName: String? {
        return userMetadata["name"] as? String
    }

    var userEmail: String? {
        return userMetadata["email"] as? String
    }

    var userPhone: String? {
        return userMetadata["phone"] as? String
    }
}

// MARK: - Persistence Extensions

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension ChatState {

    /// Restore state from stored answer variables
    /// - Parameter variables: Array of stored answer variables
    func restoreAnswerVariables(_ variables: [AnswerVariable]) {
        lock.lock()
        defer { lock.unlock() }

        for variable in variables {
            answerVariables[variable.nodeId] = variable.value.value
        }
    }

    /// Restore state from stored user metadata
    /// - Parameter metadata: Stored user metadata
    func restoreUserMetadata(_ metadata: UserMetadata) {
        lock.lock()
        defer { lock.unlock() }

        userMetadata = metadata.toDictionary()
    }

    /// Restore state from stored transcript entries
    /// - Parameter entries: Array of stored transcript entries
    func restoreTranscript(_ entries: [TranscriptEntry]) {
        lock.lock()
        defer { lock.unlock() }

        transcript = entries.map { $0.toDictionary() }
    }

    /// Restore state from stored flow variables
    /// - Parameter vars: Dictionary of stored variables
    func restoreVariables(_ vars: [String: AnyCodable]) {
        lock.lock()
        defer { lock.unlock() }

        for (key, value) in vars {
            variables[key] = value.value
        }
    }

    /// Restore complete state from stored chat state
    /// - Parameter storedState: The stored chat state to restore from
    func restoreFromStoredState(_ storedState: StoredChatState) {
        restoreAnswerVariables(storedState.answerVariables)
        restoreUserMetadata(storedState.userMetadata)
        restoreTranscript(storedState.transcript)
        restoreVariables(storedState.variables)
    }

    /// Convert current state to storable format
    /// - Parameter sessionId: The session ID to associate with this state
    /// - Returns: A StoredChatState containing all current state data
    func toStoredState(sessionId: String) -> StoredChatState {
        lock.lock()
        defer { lock.unlock() }

        // Convert answer variables
        let storedAnswers = answerVariables.map { key, value in
            AnswerVariable(nodeId: key, value: value)
        }

        // Convert user metadata
        let storedMetadata = UserMetadata(from: userMetadata)

        // Convert transcript
        let storedTranscript = transcript.map { TranscriptEntry(from: $0) }

        // Convert variables
        let storedVariables = variables.mapValues { AnyCodable($0) }

        return StoredChatState(
            sessionId: sessionId,
            answerVariables: storedAnswers,
            userMetadata: storedMetadata,
            transcript: storedTranscript,
            variables: storedVariables
        )
    }

    /// Save current state to storage
    /// - Parameter sessionId: The session ID to save state for
    func saveToStorage(sessionId: String) {
        let storage = SessionStorageManager.shared.storage
        let storedState = toStoredState(sessionId: sessionId)

        do {
            try storage.saveChatState(state: storedState)
        } catch {
            #if DEBUG
            print("[ChatState] Failed to save state: \(error)")
            #endif
        }
    }

    /// Load state from storage
    /// - Parameter sessionId: The session ID to load state for
    /// - Returns: True if state was loaded successfully
    @discardableResult
    func loadFromStorage(sessionId: String) -> Bool {
        let storage = SessionStorageManager.shared.storage

        guard let storedState = storage.loadChatState(sessionId: sessionId) else {
            return false
        }

        restoreFromStoredState(storedState)
        return true
    }
}
