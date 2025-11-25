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
        baseURL: String = ConferBotConstants.defaultApiBaseURL,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.botId = botId
        self.baseURL = baseURL
        self.session = session
    }

    /// Initialize a new chat session
    public func initSession(userId: String? = nil) async throws -> ChatSession {
        let url = URL(string: "\(baseURL)/session/init")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ConferBotConstants.apiTimeout

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

        return session
    }

    /// Get session history
    public func getSessionHistory(chatSessionId: String) async throws -> [AnyRecordItem] {
        let url = URL(string: "\(baseURL)/session/\(chatSessionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = ConferBotConstants.apiTimeout

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

    /// Send a message
    public func sendMessage(
        chatSessionId: String,
        message: String,
        metadata: [String: AnyCodable]? = nil
    ) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/session/\(chatSessionId)/message")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ConferBotConstants.apiTimeout

        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        var body: [String: Any] = ["message": message]
        if let metadata = metadata {
            body["metadata"] = metadata.mapValues { $0.value }
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

    /// Register push notification token
    public func registerPushToken(
        token: String,
        chatSessionId: String
    ) async throws {
        let url = URL(string: "\(baseURL)/push/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ConferBotConstants.apiTimeout

        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let body: [String: Any] = [
            "token": token,
            "chatSessionId": chatSessionId,
            "platform": ConferBotConstants.platformIdentifier
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConferBotError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConferBotError.httpError(httpResponse.statusCode)
        }
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
