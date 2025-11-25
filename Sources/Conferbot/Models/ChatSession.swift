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
    }

    public static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        return lhs.id == rhs.id && lhs.chatSessionId == rhs.chatSessionId
    }
}
