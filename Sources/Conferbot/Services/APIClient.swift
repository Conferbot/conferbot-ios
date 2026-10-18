//
//  APIClient.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation

/// API response wrapper
public struct APIResponse<T: Codable>: Codable {
    public let success: Bool
    public let data: T?
    public let error: String?
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case data
        case error
        case message
    }
}

/// API client for REST endpoints
public class APIClient {
    private let apiKey: String
    private let botId: String
    private let baseURL: String
    private let session: URLSession

    private var headers: [String: String] {
        return [
            ConferBotConstants.headerApiKey: apiKey,
            ConferBotConstants.headerBotId: botId,
            ConferBotConstants.headerPlatform: ConferBotConstants.platformIdentifier,
            "Content-Type": "application/json"
        ]
    }

    public init(
        apiKey: String,
        botId: String,
        baseURL: String = ConferBotEndpoints.apiBaseURL,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.botId = botId
        self.baseURL = baseURL
        self.session = session
    }

    deinit {
        // Cancel all outstanding tasks when this client is deallocated.
        // Only invalidate if we own a non-shared session; shared session must not be invalidated.
        if session !== URLSession.shared {
            session.invalidateAndCancel()
        }
    }

    /// Initialize a new chat session
    public func initSession(userId: String? = nil) async throws -> ChatSession {
        guard let url = URL(string: "\(baseURL)/session/init") else {
            throw ConferBotError.apiError("Invalid URL: \(baseURL)/session/init")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ConferBotNetworkConfig.apiTimeout

        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        var body: [String: Any] = [
            "botId": botId,
            "platform": ConferBotConstants.platformIdentifier
        ]
        if let userId = userId {
            body["userId"] = userId
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConferBotError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(APIResponse<ChatSession>.self, from: data) {
                throw ConferBotError.apiError(errorResponse.error ?? "Failed to initialize session")
            }
            throw ConferBotError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let apiResponse = try decoder.decode(APIResponse<ChatSession>.self, from: data)

        guard let session = apiResponse.data else {
            throw ConferBotError.noData
        }

        // session/init does not send the bot back: the session belongs to ours.
        guard session.botId.isEmpty else { return session }
        return ChatSession(id: session.id, chatSessionId: session.chatSessionId, botId: botId,
                           visitorId: session.visitorId, record: session.record, chatDate: session.chatDate,
                           visitorMeta: session.visitorMeta, isActive: session.isActive)
    }

    /// Get session history
    public func getSessionHistory(chatSessionId: String) async throws -> [AnyRecordItem] {
        guard let url = URL(string: "\(baseURL)/session/\(chatSessionId)") else {
            throw ConferBotError.apiError("Invalid URL: \(baseURL)/session/\(chatSessionId)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = ConferBotNetworkConfig.apiTimeout

        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConferBotError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConferBotError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct HistoryResponse: Codable {
            let data: HistoryData
        }

        struct HistoryData: Codable {
            let record: [AnyRecordItem]
        }

        let historyResponse = try decoder.decode(HistoryResponse.self, from: data)
        return historyResponse.data.record
    }

    /// Store the conversation record over REST - STORE ONLY.
    ///
    /// POST {mobile base}/session/{chatSessionId}/message with
    /// `{ record, answerVariables, visitorId? }`: the whole record, as the
    /// socket's response-record sends it. The server creates or updates the
    /// conversation and merges the answer variables, but never runs the bot:
    /// no AI agent or bot reply, no live-chat relay (embed-server #194).
    /// Returns the answer's data, which carries `storeOnly: true`. Throws
    /// `httpError(423)` when an agent locked the conversation (nothing stored).
    ///
    /// The SDK does not call this: messages go over the socket
    /// (`ConferBot.sendMessage`), which is where replies arrive.
    public func sendMessage(
        chatSessionId: String,
        record: [[String: Any]],
        answerVariables: [[String: Any]] = [],
        visitorId: String? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/session/\(chatSessionId)/message") else {
            throw ConferBotError.apiError("Invalid URL: \(baseURL)/session/\(chatSessionId)/message")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ConferBotNetworkConfig.apiTimeout

        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        var body: [String: Any] = ["record": record, "answerVariables": answerVariables]
        if let visitorId = visitorId {
            body["visitorId"] = visitorId
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConferBotError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConferBotError.httpError(httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["data"] as? [String: Any] ?? [:]
    }

    /// The old single-message form. The route never took `{ message, metadata }`
    /// (it stores a whole record and never answers), so this sends nothing and
    /// throws `apiError`; send messages with `ConferBot.sendMessage` (the
    /// socket), or store a record with `sendMessage(chatSessionId:record:)`.
    @available(*, deprecated, message: "The REST route is store-only and takes the whole record; send messages with ConferBot.sendMessage (the socket)")
    public func sendMessage(
        chatSessionId: String,
        message: String,
        metadata: [String: AnyCodable]? = nil
    ) async throws -> [String: Any] {
        throw ConferBotError.apiError("STORE_ONLY_ROUTE: POST session/{id}/message stores { record, answerVariables } and never sends a message; use ConferBot.sendMessage")
    }

    /// "Email me this chat": the server sends the conversation to this
    /// address only (embed-server POST /api/v1/mobile/chat/transcript-email;
    /// the bot is the X-Bot-ID header's). Never throws: a failure reads as
    /// not sent (EmailTranscript.result).
    public func sendTranscriptEmail(chatSessionId: String, email: String) async -> TranscriptEmailResult {
        guard let url = URL(string: "\(baseURL)\(EmailTranscript.path)"),
              let body = try? JSONSerialization.data(withJSONObject: EmailTranscript.body(chatSessionId: chatSessionId, email: email)) else {
            return TranscriptEmailResult(ok: false)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ConferBotNetworkConfig.apiTimeout
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = body
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return EmailTranscript.result(status: status, data: json)
        } catch {
            return TranscriptEmailResult(ok: false)
        }
    }

    /// Register the push token with the conversation (embed-server POST
    /// /api/v1/mobile/push/register, docs/mobile-push.md; the bot is the
    /// X-Bot-ID header's). `body` is `Push.registerBody`. Never throws: the
    /// server's error code, NETWORK or SERVER.
    public func registerPushToken(_ body: [String: Any]) async -> PushRegisterResult {
        guard let url = URL(string: "\(baseURL)\(Push.registerPath)"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return PushRegisterResult(ok: false, error: .server)
        }
        do {
            let (status, json) = try await post(url, data)
            return Push.registerResult(status: status, data: json)
        } catch {
            return PushRegisterResult(ok: false, error: .network)
        }
    }

    /// Unregister the token (logout, the visitor cleared, notifications
    /// off): POST /api/v1/mobile/push/unregister. Never throws.
    @discardableResult
    public func unregisterPushToken(_ token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)\(Push.unregisterPath)"),
              let data = try? JSONSerialization.data(withJSONObject: Push.unregisterBody(token: token)) else {
            return false
        }
        guard let (status, json) = try? await post(url, data) else { return false }
        return (200...299).contains(status) && json?["success"] as? Bool == true
    }

    /// Register push notification token (the old call; throws on any refusal).
    @available(*, deprecated, message: "Use registerPushToken(_ body:) with Push.registerBody, or ConferBot.setPushToken")
    public func registerPushToken(token: String, chatSessionId: String) async throws {
        guard let url = URL(string: "\(baseURL)\(Push.registerPath)") else {
            throw ConferBotError.apiError("Invalid URL: \(baseURL)\(Push.registerPath)")
        }
        let body = Push.registerBody(token: token, chatSessionId: chatSessionId, tokenType: Push.tokenType(of: token))
        let (status, json) = try await post(url, try JSONSerialization.data(withJSONObject: body))
        guard (200...299).contains(status) else { throw ConferBotError.httpError(status) }
        if json?["success"] as? Bool == false { throw ConferBotError.apiError(json?["error"] as? String ?? "Push registration refused") }
    }

    /// A JSON POST with the SDK's headers: the status and the JSON answer.
    private func post(_ url: URL, _ body: Data) async throws -> (Int, [String: Any]?) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ConferBotNetworkConfig.apiTimeout
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConferBotError.invalidResponse }
        return (http.statusCode, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    }
}

/// ConferBot errors
public enum ConferBotError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noData
    case notInitialized
    case socketNotConnected

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return message
        case .noData:
            return "No data received"
        case .notInitialized:
            return "SDK not initialized. Call Conferbot.shared.initialize() first"
        case .socketNotConnected:
            return "Socket not connected"
        }
    }
}
