//
//  ChatSession.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation

/// Chat session model matching embed-server Response schema
public struct ChatSession: Codable, Identifiable, Equatable {
    public let id: String
    public let chatSessionId: String
    public let botId: String
    public let visitorId: String?
    public let record: [AnyRecordItem]
    public let chatDate: Date?
    public let visitorMeta: [String: AnyCodable]?
    public let isActive: Bool

    public init(
        id: String,
        chatSessionId: String,
        botId: String,
        visitorId: String? = nil,
        record: [AnyRecordItem] = [],
        chatDate: Date? = nil,
        visitorMeta: [String: AnyCodable]? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.chatSessionId = chatSessionId
        self.botId = botId
        self.visitorId = visitorId
        self.record = record
        self.chatDate = chatDate
        self.visitorMeta = visitorMeta
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case chatSessionId
        case botId
        case visitorId
        case record
        case chatDate
        case visitorMeta
        case isActive
        case responseId
    }

    /// Reads the server's session/init payload ({ responseId, chatSessionId,
    /// visitorId, record, ... }) as well as a full session record: the id is
    /// `_id`, else `responseId`, else the chatSessionId; `botId` may be absent
    /// (the client fills it in) and a session is active unless told otherwise.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chatSessionId = try c.decode(String.self, forKey: .chatSessionId)
        id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .responseId)
            ?? chatSessionId
        botId = try c.decodeIfPresent(String.self, forKey: .botId) ?? ""
        visitorId = try c.decodeIfPresent(String.self, forKey: .visitorId)
        record = try c.decodeIfPresent([AnyRecordItem].self, forKey: .record) ?? []
        chatDate = try? c.decodeIfPresent(Date.self, forKey: .chatDate)
        visitorMeta = try? c.decodeIfPresent([String: AnyCodable].self, forKey: .visitorMeta)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(chatSessionId, forKey: .chatSessionId)
        try c.encode(botId, forKey: .botId)
        try c.encodeIfPresent(visitorId, forKey: .visitorId)
        try c.encode(record, forKey: .record)
        try c.encodeIfPresent(chatDate, forKey: .chatDate)
        try c.encodeIfPresent(visitorMeta, forKey: .visitorMeta)
        try c.encode(isActive, forKey: .isActive)
    }

    public static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        return lhs.id == rhs.id && lhs.chatSessionId == rhs.chatSessionId
    }
}
