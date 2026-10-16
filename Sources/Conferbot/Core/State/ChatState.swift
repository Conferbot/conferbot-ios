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

    /// Server-compatible conversation record (array of node entries matching web widget format)
    @Published public private(set) var serverRecord: [[String: Any]] = []

    /// Indicates if the bot is currently typing
    @Published public var isTyping: Bool = false

    /// Indicates if live chat (agent handover) mode is active
    @Published public var isLiveChatMode: Bool = false

    /// Current live chat agent details
    @Published public var currentAgent: AgentDetails? = nil

    /// Indicates if the agent is currently typing
    @Published public var isAgentTyping: Bool = false

    /// Visitor ID for the current session
    @Published public var visitorId: String?

    /// Workspace ID for the current session
    @Published public var workspaceId: String?

    /// Current node being processed
    @Published public var currentNodeId: String?

    /// Called whenever a bot entry (message or image) is appended to the
    /// transcript. ConferBot uses this to mirror flow-engine bot output into
    /// the visible message list. Invoked outside the internal lock.
    public var onBotEntryAppended: (([String: Any]) -> Void)?

    /// Called whenever a visitor entry is appended to the transcript (a
    /// step's own reply line: "⭐⭐⭐⭐", "Oct 19, 2026", "Signed: ..."). The
    /// chat shows these for the steps answered in their own views.
    /// Invoked outside the internal lock.
    public var onUserEntryAppended: (([String: Any]) -> Void)?

    // MARK: - Private Properties

    /// Lock for thread-safe access
    private let lock = NSLock()

    private var visitorContextStorage: [String: Any]?

    /// The app's signed-in user (ConferBotUser.toVisitorContext), sent with every
    /// response record. Set by ConferBot.identify; kept across resets.
    public var visitorContext: [String: Any]? {
        get { lock.lock(); defer { lock.unlock() }; return visitorContextStorage }
        set { lock.lock(); visitorContextStorage = newValue; lock.unlock() }
    }

    /// Maximum number of transcript entries to retain (prevents unbounded memory growth)
    private let maxTranscriptEntries = 500

    /// The answer variables in the web widget's shape: one entry per step
    /// that asked (registered when shown, filled by the answer) or per name
    /// saved, in the order they were made. The flow reads them by name
    /// (the first entry with that key) and sends them as answerVariables.
    private var answerEntries: [FlowAnswerVariable] = []

    /// Card numbers, ids and passwords masked in answers and records
    /// (customizations.redactSensitive: on unless false).
    private var redactSensitiveStorage = true

    // MARK: - Initialization

    /// ChatState.shared is the app's; tests and headless flows make their own.
    init() {}

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

    /// Removes a flow variable.
    public func deleteVariable(name: String) {
        lock.lock()
        defer { lock.unlock() }
        variables.removeValue(forKey: name)
    }

    // MARK: - Flow answers (the web widget's answer variables)

    /// The conversation's chatSessionId ("" before a session).
    public var sessionId: String {
        lock.lock()
        defer { lock.unlock() }
        return record["sessionId"] as? String ?? ""
    }

    /// The bot this conversation belongs to ("" before a session).
    public var botId: String {
        lock.lock()
        defer { lock.unlock() }
        return record["botId"] as? String ?? ""
    }

    /// Masking of card numbers, ids and passwords in the answers and the
    /// visitor's record entries (web customizations.redactSensitive: on
    /// unless false). The transcript keeps what was typed (#30).
    public var redactSensitive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return redactSensitiveStorage }
        set { lock.lock(); redactSensitiveStorage = newValue; lock.unlock() }
    }

    private func maskedLocked(_ value: Any?) -> Any {
        let v = redactSensitiveStorage ? Redact.maskValue(value) : value
        return v ?? NSNull()
    }

    /// A question step with data.answerVariable registers {nodeId, key,
    /// value: null} when it is shown; its answer then fills it by nodeId
    /// (web index.ts _nodeCategorizeHelper / _setAnswerVariable).
    public func registerAnswerVariable(nodeId: String, key: String) {
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        answerEntries.append(FlowAnswerVariable(nodeId: nodeId, key: key, value: NSNull()))
    }

    /// Fills the entry registered for a step (the first with that nodeId).
    /// A step that registered none stores nothing. True when one was filled.
    @discardableResult
    public func setAnswerVariable(nodeId: String, value: Any?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let i = answerEntries.firstIndex(where: { $0.nodeId == nodeId }) else { return false }
        answerEntries[i].value = maskedLocked(value)
        return true
    }

    /// Saves a value under a variable's name: every entry with that name
    /// gets it; with none, one entry is added (nodeId "column_mapped_<key>"
    /// unless one is given) - web index.ts _setAnswerVariableByKey.
    public func saveVariableByName(_ key: String, value: Any?, nodeId: String? = nil) {
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let v = maskedLocked(value)
        var matched = false
        for i in answerEntries.indices where answerEntries[i].key == key {
            answerEntries[i].value = v
            matched = true
        }
        if !matched {
            let id = (nodeId?.isEmpty == false) ? nodeId! : "column_mapped_\(key)"
            answerEntries.append(FlowAnswerVariable(nodeId: id, key: key, value: v))
        }
    }

    /// Whether an entry with this key exists (answered or not).
    public func hasAnswerVariable(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return answerEntries.contains { $0.key == key }
    }

    /// An answer by name: the FIRST entry with that key (web
    /// _getValueFromAnswerVariableKey); nil when there is none.
    public func answerValue(_ key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return answerEntries.first { $0.key == key }?.value
    }

    /// The answer variables in the order they were made.
    public func flowAnswerVariables() -> [FlowAnswerVariable] {
        lock.lock()
        defer { lock.unlock() }
        return answerEntries
    }

    /// A placeholder's value: the answers first (the first entry with that
    /// key), then the flow variables, then the visitor's details. Internal
    /// "_" variables never fill text.
    public func lookupVariable(_ key: String) -> Any? {
        let name = key.trimmed
        guard !name.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let entry = answerEntries.first(where: { $0.key == name }) { return entry.value }
        if !name.hasPrefix("_"), let v = variables[name] { return v }
        return userMetadata[name]
    }

    /// Adds a record entry, merging into an earlier one for the same step
    /// and kind (type|shape) as the web widget's _pushDataToRecord. The
    /// visitor's own entries are masked first.
    public func addRecord(_ entry: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        let e = redactSensitiveStorage ? Redact.maskRecordEntry(entry) : entry
        let id = JS.text(e["id"]).isEmpty ? JS.text(e["_id"]) : JS.text(e["id"])
        func kind(_ r: [String: Any]) -> String { "\(JS.text(r["type"]))|\(JS.text(r["shape"]))" }
        if !id.isEmpty, let i = serverRecord.firstIndex(where: {
            (JS.text($0["id"]).isEmpty ? JS.text($0["_id"]) : JS.text($0["id"])) == id && kind($0) == kind(e)
        }) {
            var merged = serverRecord[i]
            for (k, v) in e { merged[k] = v }
            var data = JS.dict(serverRecord[i]["data"])
            for (k, v) in JS.dict(e["data"]) { data[k] = v }
            merged["data"] = data
            serverRecord[i] = merged
            return
        }
        serverRecord.append(e)
    }

    /// Appends an entry as it is - every visit of a step and every edge
    /// taken is its own entry (web index.ts S.record.push).
    public func appendRecord(_ entry: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        serverRecord.append(entry)
    }

    /// The chat reached the end of its flow.
    public func markConversationComplete(reason: String?) {
        lock.lock()
        defer { lock.unlock() }
        variables["_flowComplete"] = true
        variables["_flowCompletedAt"] = Flow.iso(Date())
        if let reason = reason { variables["_flowCompletionReason"] = reason }
    }

    /// A bot line on the transcript (the chat draws it): its plain text, the
    /// owner's HTML when it has some, and media / link details.
    public func addBotEntry(text: String, html: String? = nil, nodeId: String, nodeType: String, data: [String: Any]? = nil) {
        guard !text.isEmpty || data != nil else { return }
        var entry: [String: Any] = ["type": "bot", "message": text, "nodeId": nodeId, "nodeType": nodeType]
        if let html = html, html != text { entry["html"] = html }
        if let data = data {
            entry["data"] = data
            for (k, v) in data where entry[k] == nil { entry[k] = v }
        }
        addToTranscript(entry: entry)
    }

    // MARK: - Variable Resolution

    /// Fills the placeholders in text the way the web widget does
    /// (nodeLogic.fillVariables): {x}, ${x}, {{x}}, ${ANSWERS.x} and $${x}
    /// from the answers, then the flow variables, then the visitor's
    /// details; an unknown, null or "" value shows nothing and the gap it
    /// leaves is tidied. Values go in as they are (raw).
    public func resolveVariables(text: String) -> String {
        guard !text.isEmpty else { return text }
        return FlowText.fillVariables(text, { [weak self] in self?.lookupVariable($0) }, mode: .raw)
    }

    /// The same, for owner HTML: the values are HTML-escaped.
    public func resolveVariables(html: String) -> String {
        guard !html.isEmpty else { return html }
        return FlowText.fillVariables(html, { [weak self] in self?.lookupVariable($0) }, mode: .html)
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
        var entryWithTimestamp = entry
        if entryWithTimestamp["timestamp"] == nil {
            entryWithTimestamp["timestamp"] = ISO8601DateFormatter().string(from: Date())
        }

        lock.lock()
        transcript.append(entryWithTimestamp)

        // Enforce size limit to prevent unbounded memory growth
        if transcript.count > maxTranscriptEntries {
            transcript = Array(transcript.suffix(maxTranscriptEntries))
        }
        let callback = onBotEntryAppended
        let userCallback = onUserEntryAppended
        lock.unlock()

        // Mirror bot entries to the visible message list (outside the lock)
        if (entryWithTimestamp["type"] as? String) == "bot" {
            callback?(entryWithTimestamp)
        } else if (entryWithTimestamp["type"] as? String) == "user" {
            userCallback?(entryWithTimestamp)
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

    /// Adds a standalone bot image to the transcript (welcome-node / image-node).
    /// The web widget persists these as separate rounded images below the text
    /// bubble, so they get their own transcript entry rather than bubble text.
    /// - Parameters:
    ///   - imageUrl: The image/GIF URL
    ///   - nodeId: Optional node ID
    ///   - nodeType: Optional node type
    public func addBotImage(_ imageUrl: String, nodeId: String? = nil, nodeType: String? = nil) {
        var entry: [String: Any] = [
            "type": "bot",
            "imageUrl": imageUrl
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

    /// Push a bot message entry to the server record (web widget format)
    public func pushBotRecord(nodeId: String, nodeType: String, nodeData: [String: Any]?, text: String?) {
        lock.lock()
        defer { lock.unlock() }

        var dataMap = nodeData ?? [:]
        if let text = text { dataMap["text"] = text }

        let entry: [String: Any] = [
            "_id": nodeId,
            "id": nodeId,
            "type": nodeType,
            "data": dataMap,
            "time": ISO8601DateFormatter().string(from: Date())
        ]

        // Merge if same ID exists
        if let idx = serverRecord.firstIndex(where: { ($0["id"] as? String) == nodeId }) {
            serverRecord[idx] = entry
        } else {
            serverRecord.append(entry)
        }
    }

    /// Push a user response entry to the server record (web widget format)
    /// Uses "user-live-message" shape when in live chat mode, otherwise "user-input-response"
    public func pushUserRecord(nodeId: String, nodeType: String?, text: String) {
        lock.lock()
        defer { lock.unlock() }

        let shape = isLiveChatMode ? "user-live-message" : "user-input-response"
        let entry: [String: Any] = [
            "_id": nodeId,
            "id": nodeId,
            "shape": shape,
            "type": nodeType ?? shape,
            "text": text,
            "time": ISO8601DateFormatter().string(from: Date())
        ]

        // Merge if same ID exists (deduplication)
        if let idx = serverRecord.firstIndex(where: { ($0["id"] as? String) == nodeId }) {
            serverRecord[idx] = entry
        } else {
            serverRecord.append(entry)
        }
    }

    /// Get server record array for socket emit
    public func getServerRecord() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return serverRecord
    }

    // MARK: - Integration Payload Helpers

    /// The answer variables as the server reads them: [{nodeId, key,
    /// value}] in the order they were made (web answerVariables). Callers
    /// must hold `lock`.
    private func answerVariablesListLocked() -> [[String: Any]] {
        answerEntries.map { ["nodeId": $0.nodeId, "key": $0.key, "value": $0.value] }
    }

    /// The answer variables in the server's format: [{nodeId, key, value}].
    /// The server resolves ${var} placeholders in integration steps from it.
    public func getAnswerVariablesList() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }

        return answerVariablesListLocked()
    }

    /// Visitor data (name, email, phone) for integration payloads
    public func getVisitorData() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        var data: [String: Any] = [:]
        if let name = userMetadata["name"] ?? variables["name"] {
            data["name"] = name
        }
        if let email = userMetadata["email"] ?? variables["email"] {
            data["email"] = email
        }
        if let phone = userMetadata["phone"] ?? variables["phone"] {
            data["phone"] = phone
        }
        return data
    }

    /// Transcript in the email-node contract format: [{by, message}]
    /// where "by" is one of "bot", "user", or "agent"
    public func getEmailTranscript() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }

        return transcript.compactMap { entry -> [String: Any]? in
            let type = entry["type"] as? String ?? ""
            var message = entry["message"] as? String ?? entry["text"] as? String ?? ""
            if message.isEmpty, let value = entry["value"] {
                message = String(describing: value)
            }
            guard !message.isEmpty else { return nil }

            let by: String
            if type.hasPrefix("agent") {
                by = "agent"
            } else if type == "bot" {
                by = "bot"
            } else {
                by = "user"
            }
            return ["by": by, "message": message]
        }
    }

    /// Build the full response data dictionary for socket emit,
    /// including visitorId and workspaceId when available
    public func buildResponseData(chatSessionId: String, botId: String) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        var data: [String: Any] = [
            "chatSessionId": chatSessionId,
            "botId": botId,
            "record": serverRecord,
            "answerVariables": answerVariablesListLocked(),
            "channel": "mobile"
        ]

        if let visitorId = visitorId {
            data["visitorId"] = visitorId
        }
        if let workspaceId = workspaceId {
            data["workspaceId"] = workspaceId
        }
        // The app's signed-in user travels with every record, as the web widget's
        // visitorContext; the server checks its hash and drops it.
        if let ctx = visitorContextStorage {
            data["visitorContext"] = ctx
            if let name = ctx["name"] as? String { data["visitorName"] = name }
            if let email = ctx["email"] as? String { data["visitorEmail"] = email }
        }
        // The phone's language, as the web's visitorInsights.language.browser:
        // the AI answers a short message ("ok", "hi") in it (#44).
        if let insights = DeviceLanguage.visitorInsights(deviceLanguage()) {
            data["visitorInsights"] = insights
        }

        return data
    }

    /// The visitor's language for the response record (the phone's; tests set their own).
    public var deviceLanguage: () -> String = { DeviceLanguage.current }

    /// Push a system/agent record entry to the server record (for live chat events)
    public func pushLiveChatRecord(entryId: String, type: String, text: String? = nil, agentDetails: [String: Any]? = nil) {
        lock.lock()
        defer { lock.unlock() }

        var entry: [String: Any] = [
            "_id": entryId,
            "id": entryId,
            "type": type,
            "time": ISO8601DateFormatter().string(from: Date())
        ]
        if let text = text {
            entry["text"] = text
        }
        if let agentDetails = agentDetails {
            entry["agentDetails"] = agentDetails
        }

        serverRecord.append(entry)
    }

    /// Replaces the server record (a handover line settled, a restored record annotated).
    public func setServerRecord(_ record: [[String: Any]]) {
        lock.lock()
        defer { lock.unlock() }
        serverRecord = record
    }

    /// Changes the server record in one step: `transform` gets the record and returns the new one.
    public func updateServerRecord(_ transform: ([[String: Any]]) -> [[String: Any]]) {
        lock.lock()
        defer { lock.unlock() }
        serverRecord = transform(serverRecord)
    }

    /// Appends a live chat entry as the web widget records it (a visitor's
    /// file {url}, a message left by email {via, data}), replacing one with
    /// the same id.
    public func pushServerEntry(_ entry: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        var e = entry
        if e["time"] == nil { e["time"] = ISO8601DateFormatter().string(from: Date()) }
        let id = e["id"] as? String
        if let id = id, let idx = serverRecord.firstIndex(where: { ($0["id"] as? String) == id }) {
            serverRecord[idx] = e
        } else {
            serverRecord.append(e)
        }
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

    /// Names the conversation this state belongs to, keeping its answers:
    /// the flow's steps read the chatSessionId and botId from the record
    /// for the events they send (initiate-handover, response-record) (#62).
    public func setSession(sessionId: String, botId: String) {
        lock.lock()
        defer { lock.unlock() }

        let now = ISO8601DateFormatter().string(from: Date())
        var r = record
        r["sessionId"] = sessionId
        r["botId"] = botId
        if r["createdAt"] == nil { r["createdAt"] = now }
        r["updatedAt"] = now
        if r["answers"] == nil { r["answers"] = [String: Any]() }
        if r["metadata"] == nil { r["metadata"] = [String: Any]() }
        record = r
    }

    // MARK: - Reset

    /// Resets all state to initial values
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        answerVariables = [:]
        answerEntries = []
        variables = [:]
        userMetadata = [:]
        transcript = []
        record = [:]
        serverRecord = []
        isTyping = false
        isLiveChatMode = false
        currentAgent = nil
        isAgentTyping = false
        currentNodeId = nil
    }

    /// The conversation's state at one moment (the answers, variables,
    /// metadata, transcript, record and current step), in memory: what
    /// "Edit" on an answer returns to (Core/Delight). The values are plain
    /// dictionaries and arrays, copied on write.
    public struct Snapshot {
        let answerVariables: [String: Any]
        let answerEntries: [FlowAnswerVariable]
        let variables: [String: Any]
        let userMetadata: [String: Any]
        let transcript: [[String: Any]]
        let record: [String: Any]
        let serverRecord: [[String: Any]]
        let currentNodeId: String?
    }

    /// The state as it is now.
    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(answerVariables: answerVariables, answerEntries: answerEntries, variables: variables,
                        userMetadata: userMetadata, transcript: transcript, record: record,
                        serverRecord: serverRecord, currentNodeId: currentNodeId)
    }

    /// Puts a snapshot back in place, keeping this instance and its
    /// subscribers (RN ChatState.restore).
    public func restore(_ snap: Snapshot) {
        lock.lock()
        answerVariables = snap.answerVariables
        answerEntries = snap.answerEntries
        variables = snap.variables
        userMetadata = snap.userMetadata
        transcript = snap.transcript
        record = snap.record
        serverRecord = snap.serverRecord
        currentNodeId = snap.currentNodeId
        lock.unlock()
    }

    /// Resets only the conversation state while preserving user metadata
    public func resetConversation() {
        lock.lock()
        defer { lock.unlock() }

        answerVariables = [:]
        answerEntries = []
        transcript = []
        isTyping = false
        isLiveChatMode = false
        currentAgent = nil
        isAgentTyping = false
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
        restoreServerRecord(storedState)
    }

    /// The server record and the flow's step from storage: a restart reads
    /// its live chat from them (they used not to be saved, so a restored
    /// chat had no record of its handover).
    func restoreServerRecord(_ storedState: StoredChatState) {
        let record = storedState.serverRecordJSON
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
        lock.lock()
        defer { lock.unlock() }
        if let record = record { serverRecord = record }
        if let node = storedState.currentNodeId { currentNodeId = node }
        if let saved = storedState.answerVariablesJSON.flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }) {
            answerEntries = saved.compactMap { e in
                guard let key = e["key"] as? String, !key.isEmpty else { return nil }
                return FlowAnswerVariable(nodeId: JS.text(e["nodeId"]), key: key, value: e["value"] ?? NSNull())
            }
        }
    }

    /// The server record as JSON for storage; entries that can't be written are left out.
    static func serverRecordJSON(_ record: [[String: Any]]) -> Data? {
        func safe(_ v: Any) -> Any? {
            switch v {
            case let d as Date: return ISO8601DateFormatter().string(from: d)
            case let a as [Any]: return a.compactMap(safe)
            case let m as [String: Any]: return m.compactMapValues(safe)
            case is String, is NSNumber, is NSNull: return v
            case let c as AnyCodable: return safe(c.value)
            default: return nil
            }
        }
        let clean = record.map { $0.compactMapValues(safe) }
        return JSONSerialization.isValidJSONObject(clean) ? try? JSONSerialization.data(withJSONObject: clean) : nil
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
            variables: storedVariables,
            serverRecordJSON: Self.serverRecordJSON(serverRecord),
            currentNodeId: currentNodeId,
            answerVariablesJSON: Self.serverRecordJSON(answerVariablesListLocked())
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

// MARK: - Flow answer variable

/// One answer variable as the web widget keeps it: the step that asked (or
/// "column_mapped_<key>" for a value saved by name), its key and value.
public struct FlowAnswerVariable {
    public let nodeId: String
    public let key: String
    public var value: Any
}
