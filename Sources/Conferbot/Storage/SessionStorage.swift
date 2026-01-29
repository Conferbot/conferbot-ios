//
//  SessionStorage.swift
//  Conferbot
//
//  Session persistence layer for storing chat sessions,
//  messages, and state across app restarts.
//

import Foundation

// MARK: - Codable Wrappers for State Persistence

/// Codable wrapper for answer variables
public struct AnswerVariable: Codable, Equatable {
    public let nodeId: String
    public let value: AnyCodable
    public let timestamp: Date

    public init(nodeId: String, value: Any, timestamp: Date = Date()) {
        self.nodeId = nodeId
        self.value = AnyCodable(value)
        self.timestamp = timestamp
    }

    public static func == (lhs: AnswerVariable, rhs: AnswerVariable) -> Bool {
        return lhs.nodeId == rhs.nodeId && lhs.timestamp == rhs.timestamp
    }
}

/// Codable wrapper for transcript entries
public struct TranscriptEntry: Codable {
    public let type: String
    public let message: String?
    public let nodeId: String?
    public let nodeType: String?
    public let timestamp: Date
    public let metadata: [String: AnyCodable]?

    public init(from dictionary: [String: Any]) {
        self.type = dictionary["type"] as? String ?? "unknown"
        self.message = dictionary["message"] as? String
        self.nodeId = dictionary["nodeId"] as? String
        self.nodeType = dictionary["nodeType"] as? String

        if let timestampString = dictionary["timestamp"] as? String,
           let date = ISO8601DateFormatter().date(from: timestampString) {
            self.timestamp = date
        } else {
            self.timestamp = Date()
        }

        // Extract any additional metadata
        var meta: [String: AnyCodable] = [:]
        for (key, value) in dictionary {
            if !["type", "message", "nodeId", "nodeType", "timestamp"].contains(key) {
                meta[key] = AnyCodable(value)
            }
        }
        self.metadata = meta.isEmpty ? nil : meta
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        if let message = message { dict["message"] = message }
        if let nodeId = nodeId { dict["nodeId"] = nodeId }
        if let nodeType = nodeType { dict["nodeType"] = nodeType }
        if let metadata = metadata {
            for (key, value) in metadata {
                dict[key] = value.value
            }
        }
        return dict
    }
}

/// Codable wrapper for user metadata
public struct UserMetadata: Codable {
    public let name: String?
    public let email: String?
    public let phone: String?
    public let additionalData: [String: AnyCodable]?

    public init(from dictionary: [String: Any]) {
        self.name = dictionary["name"] as? String
        self.email = dictionary["email"] as? String
        self.phone = dictionary["phone"] as? String

        var additional: [String: AnyCodable] = [:]
        for (key, value) in dictionary {
            if !["name", "email", "phone"].contains(key) {
                additional[key] = AnyCodable(value)
            }
        }
        self.additionalData = additional.isEmpty ? nil : additional
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let name = name { dict["name"] = name }
        if let email = email { dict["email"] = email }
        if let phone = phone { dict["phone"] = phone }
        if let additional = additionalData {
            for (key, value) in additional {
                dict[key] = value.value
            }
        }
        return dict
    }
}

/// Storable session data
public struct StoredSession: Codable {
    public let session: ChatSession
    public let createdAt: Date
    public let lastActivityAt: Date
    public let expiresAt: Date

    public init(session: ChatSession, expiryMinutes: Int = 30) {
        self.session = session
        self.createdAt = Date()
        self.lastActivityAt = Date()
        self.expiresAt = Date().addingTimeInterval(TimeInterval(expiryMinutes * 60))
    }

    public init(session: ChatSession, createdAt: Date, lastActivityAt: Date, expiresAt: Date) {
        self.session = session
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.expiresAt = expiresAt
    }

    /// Returns a new StoredSession with updated activity time and extended expiry
    public func withUpdatedActivity(expiryMinutes: Int = 30) -> StoredSession {
        return StoredSession(
            session: session,
            createdAt: createdAt,
            lastActivityAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(expiryMinutes * 60))
        )
    }

    public var isExpired: Bool {
        return Date() > expiresAt
    }
}

/// Storable chat state data
public struct StoredChatState: Codable {
    public let sessionId: String
    public let answerVariables: [AnswerVariable]
    public let userMetadata: UserMetadata
    public let transcript: [TranscriptEntry]
    public let variables: [String: AnyCodable]
    public let lastUpdated: Date

    public init(
        sessionId: String,
        answerVariables: [AnswerVariable],
        userMetadata: UserMetadata,
        transcript: [TranscriptEntry],
        variables: [String: AnyCodable],
        lastUpdated: Date = Date()
    ) {
        self.sessionId = sessionId
        self.answerVariables = answerVariables
        self.userMetadata = userMetadata
        self.transcript = transcript
        self.variables = variables
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Session Storage Protocol

/// Protocol defining session storage operations
public protocol SessionStorageProtocol {
    /// Save a chat session
    func saveSession(session: ChatSession) throws

    /// Load a session for a specific bot
    func loadSession(botId: String) -> ChatSession?

    /// Save messages/records for a session
    func saveMessages(messages: [any RecordItem], sessionId: String) throws

    /// Load messages for a session
    func loadMessages(sessionId: String) -> [any RecordItem]

    /// Save answer variables for a session
    func saveAnswerVariables(variables: [AnswerVariable], sessionId: String) throws

    /// Load answer variables for a session
    func loadAnswerVariables(sessionId: String) -> [AnswerVariable]

    /// Save user metadata for a session
    func saveUserMetadata(metadata: UserMetadata, sessionId: String) throws

    /// Load user metadata for a session
    func loadUserMetadata(sessionId: String) -> UserMetadata?

    /// Save transcript for a session
    func saveTranscript(transcript: [TranscriptEntry], sessionId: String) throws

    /// Load transcript for a session
    func loadTranscript(sessionId: String) -> [TranscriptEntry]

    /// Save complete chat state
    func saveChatState(state: StoredChatState) throws

    /// Load complete chat state
    func loadChatState(sessionId: String) -> StoredChatState?

    /// Clear all data for a session
    func clearSession(sessionId: String)

    /// Clear all stored sessions for a bot
    func clearAllSessions(botId: String)

    /// Get session expiry date
    func getSessionExpiry(sessionId: String) -> Date?

    /// Check if a session is still valid (not expired)
    func isSessionValid(sessionId: String) -> Bool

    /// Update session activity (extends expiry)
    func updateSessionActivity(sessionId: String)
}

// MARK: - UserDefaults Implementation

/// UserDefaults-based implementation of SessionStorageProtocol
public final class UserDefaultsSessionStorage: SessionStorageProtocol {

    // MARK: - Constants

    private enum Keys {
        static let prefix = "conferbot_"
        static let session = "session_"
        static let messages = "messages_"
        static let answerVariables = "answer_vars_"
        static let userMetadata = "user_meta_"
        static let transcript = "transcript_"
        static let chatState = "chat_state_"
        static let botSessionMapping = "bot_session_"
    }

    /// Default session expiry in minutes (30 minutes like web widget)
    public static let defaultExpiryMinutes = 30

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let expiryMinutes: Int

    // MARK: - Initialization

    public init(
        userDefaults: UserDefaults = .standard,
        expiryMinutes: Int = defaultExpiryMinutes
    ) {
        self.userDefaults = userDefaults
        self.expiryMinutes = expiryMinutes

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Key Generation

    private func key(_ suffix: String) -> String {
        return Keys.prefix + suffix
    }

    private func sessionKey(_ sessionId: String) -> String {
        return key(Keys.session + sessionId)
    }

    private func messagesKey(_ sessionId: String) -> String {
        return key(Keys.messages + sessionId)
    }

    private func answerVariablesKey(_ sessionId: String) -> String {
        return key(Keys.answerVariables + sessionId)
    }

    private func userMetadataKey(_ sessionId: String) -> String {
        return key(Keys.userMetadata + sessionId)
    }

    private func transcriptKey(_ sessionId: String) -> String {
        return key(Keys.transcript + sessionId)
    }

    private func chatStateKey(_ sessionId: String) -> String {
        return key(Keys.chatState + sessionId)
    }

    private func botSessionMappingKey(_ botId: String) -> String {
        return key(Keys.botSessionMapping + botId)
    }

    // MARK: - Session Operations

    public func saveSession(session: ChatSession) throws {
        let storedSession = StoredSession(session: session, expiryMinutes: expiryMinutes)
        let data = try encoder.encode(storedSession)
        userDefaults.set(data, forKey: sessionKey(session.chatSessionId))

        // Map bot ID to session ID for lookup
        userDefaults.set(session.chatSessionId, forKey: botSessionMappingKey(session.botId))

        debugLog("Session saved: \(session.chatSessionId)")
    }

    public func loadSession(botId: String) -> ChatSession? {
        guard let sessionId = userDefaults.string(forKey: botSessionMappingKey(botId)),
              let storedSession = loadStoredSession(sessionId: sessionId),
              !storedSession.isExpired else {
            debugLog("No valid session found for bot: \(botId)")
            return nil
        }

        debugLog("Session loaded: \(storedSession.session.chatSessionId)")
        return storedSession.session
    }

    private func loadStoredSession(sessionId: String) -> StoredSession? {
        guard let data = userDefaults.data(forKey: sessionKey(sessionId)) else {
            return nil
        }

        do {
            return try decoder.decode(StoredSession.self, from: data)
        } catch {
            debugLog("Failed to decode session: \(error)")
            return nil
        }
    }

    // MARK: - Messages Operations

    public func saveMessages(messages: [any RecordItem], sessionId: String) throws {
        let wrappedMessages = messages.map { AnyRecordItem($0) }
        let data = try encoder.encode(wrappedMessages)
        userDefaults.set(data, forKey: messagesKey(sessionId))

        debugLog("Messages saved: \(messages.count) items")
    }

    public func loadMessages(sessionId: String) -> [any RecordItem] {
        guard let data = userDefaults.data(forKey: messagesKey(sessionId)) else {
            return []
        }

        do {
            let wrappedMessages = try decoder.decode([AnyRecordItem].self, from: data)
            debugLog("Messages loaded: \(wrappedMessages.count) items")
            return wrappedMessages.map { $0.value }
        } catch {
            debugLog("Failed to decode messages: \(error)")
            return []
        }
    }

    // MARK: - Answer Variables Operations

    public func saveAnswerVariables(variables: [AnswerVariable], sessionId: String) throws {
        let data = try encoder.encode(variables)
        userDefaults.set(data, forKey: answerVariablesKey(sessionId))

        debugLog("Answer variables saved: \(variables.count) items")
    }

    public func loadAnswerVariables(sessionId: String) -> [AnswerVariable] {
        guard let data = userDefaults.data(forKey: answerVariablesKey(sessionId)) else {
            return []
        }

        do {
            let variables = try decoder.decode([AnswerVariable].self, from: data)
            debugLog("Answer variables loaded: \(variables.count) items")
            return variables
        } catch {
            debugLog("Failed to decode answer variables: \(error)")
            return []
        }
    }

    // MARK: - User Metadata Operations

    public func saveUserMetadata(metadata: UserMetadata, sessionId: String) throws {
        let data = try encoder.encode(metadata)
        userDefaults.set(data, forKey: userMetadataKey(sessionId))

        debugLog("User metadata saved")
    }

    public func loadUserMetadata(sessionId: String) -> UserMetadata? {
        guard let data = userDefaults.data(forKey: userMetadataKey(sessionId)) else {
            return nil
        }

        do {
            return try decoder.decode(UserMetadata.self, from: data)
        } catch {
            debugLog("Failed to decode user metadata: \(error)")
            return nil
        }
    }

    // MARK: - Transcript Operations

    public func saveTranscript(transcript: [TranscriptEntry], sessionId: String) throws {
        let data = try encoder.encode(transcript)
        userDefaults.set(data, forKey: transcriptKey(sessionId))

        debugLog("Transcript saved: \(transcript.count) entries")
    }

    public func loadTranscript(sessionId: String) -> [TranscriptEntry] {
        guard let data = userDefaults.data(forKey: transcriptKey(sessionId)) else {
            return []
        }

        do {
            let transcript = try decoder.decode([TranscriptEntry].self, from: data)
            debugLog("Transcript loaded: \(transcript.count) entries")
            return transcript
        } catch {
            debugLog("Failed to decode transcript: \(error)")
            return []
        }
    }

    // MARK: - Chat State Operations

    public func saveChatState(state: StoredChatState) throws {
        let data = try encoder.encode(state)
        userDefaults.set(data, forKey: chatStateKey(state.sessionId))

        debugLog("Chat state saved for session: \(state.sessionId)")
    }

    public func loadChatState(sessionId: String) -> StoredChatState? {
        guard let data = userDefaults.data(forKey: chatStateKey(sessionId)) else {
            return nil
        }

        do {
            let state = try decoder.decode(StoredChatState.self, from: data)
            debugLog("Chat state loaded for session: \(sessionId)")
            return state
        } catch {
            debugLog("Failed to decode chat state: \(error)")
            return nil
        }
    }

    // MARK: - Session Management

    public func clearSession(sessionId: String) {
        userDefaults.removeObject(forKey: sessionKey(sessionId))
        userDefaults.removeObject(forKey: messagesKey(sessionId))
        userDefaults.removeObject(forKey: answerVariablesKey(sessionId))
        userDefaults.removeObject(forKey: userMetadataKey(sessionId))
        userDefaults.removeObject(forKey: transcriptKey(sessionId))
        userDefaults.removeObject(forKey: chatStateKey(sessionId))

        debugLog("Session cleared: \(sessionId)")
    }

    public func clearAllSessions(botId: String) {
        if let sessionId = userDefaults.string(forKey: botSessionMappingKey(botId)) {
            clearSession(sessionId: sessionId)
        }
        userDefaults.removeObject(forKey: botSessionMappingKey(botId))

        debugLog("All sessions cleared for bot: \(botId)")
    }

    public func getSessionExpiry(sessionId: String) -> Date? {
        guard let storedSession = loadStoredSession(sessionId: sessionId) else {
            return nil
        }
        return storedSession.expiresAt
    }

    public func isSessionValid(sessionId: String) -> Bool {
        guard let storedSession = loadStoredSession(sessionId: sessionId) else {
            return false
        }
        return !storedSession.isExpired
    }

    public func updateSessionActivity(sessionId: String) {
        guard let storedSession = loadStoredSession(sessionId: sessionId) else {
            return
        }

        let updatedSession = storedSession.withUpdatedActivity(expiryMinutes: expiryMinutes)

        do {
            let data = try encoder.encode(updatedSession)
            userDefaults.set(data, forKey: sessionKey(sessionId))
            debugLog("Session activity updated: \(sessionId)")
        } catch {
            debugLog("Failed to update session activity: \(error)")
        }
    }

    // MARK: - Debug Logging

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[SessionStorage] \(message)")
        #endif
    }
}

// MARK: - Session Storage Manager

/// Singleton manager for session storage operations
public final class SessionStorageManager {

    /// Shared singleton instance
    public static let shared = SessionStorageManager()

    /// The underlying storage implementation
    public var storage: SessionStorageProtocol

    private init() {
        self.storage = UserDefaultsSessionStorage()
    }

    /// Configure with a custom storage implementation
    public func configure(storage: SessionStorageProtocol) {
        self.storage = storage
    }

    /// Configure with custom expiry time
    public func configure(expiryMinutes: Int) {
        self.storage = UserDefaultsSessionStorage(expiryMinutes: expiryMinutes)
    }
}
