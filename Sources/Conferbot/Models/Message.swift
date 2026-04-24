//
//  Message.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation

/// Message types matching embed-server schema
public enum MessageType: String, Codable {
    case userMessage = "user-message"
    case userInputResponse = "user-input-response" // User input from chatbot flow
    case userLiveMessage = "user-live-message"      // User message during live chat
    case botMessage = "bot-message"
    case agentMessage = "agent-message"
    case agentMessageFile = "agent-message-file"
    case agentMessageAudio = "agent-message-audio"
    case agentJoinedMessage = "agent-joined-message"
    case agentLeftChat = "agent-left-chat"
    case visitorDisconnectedMessage = "visitor-disconnected-message"
    case visitorReconnectedMessage = "visitor-reconnected-message"
    case systemMessage = "system-message"
}

/// Base protocol for record items matching embed-server Response.record structure
public protocol RecordItem: Codable {
    var id: String { get }
    var type: MessageType { get }
    var time: Date { get }
}

/// User message record
public struct UserMessageRecord: RecordItem, Identifiable, Equatable {
    public let id: String
    public let type: MessageType
    public let time: Date
    public let text: String
    public let metadata: [String: AnyCodable]?

    public init(
        id: String,
        time: Date,
        text: String,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.type = .userMessage
        self.time = time
        self.text = text
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case time
        case text
        case metadata
    }

    public static func == (lhs: UserMessageRecord, rhs: UserMessageRecord) -> Bool {
        return lhs.id == rhs.id && lhs.text == rhs.text && lhs.time == rhs.time
    }
}

/// User input response record (from chatbot flow)
public struct UserInputResponseRecord: RecordItem, Identifiable, Equatable {
    public let id: String
    public let type: MessageType
    public let time: Date
    public let text: String
    public let metadata: [String: AnyCodable]?

    public init(
        id: String,
        time: Date,
        text: String,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.type = .userInputResponse
        self.time = time
        self.text = text
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case time
        case text
        case metadata
    }

    public static func == (lhs: UserInputResponseRecord, rhs: UserInputResponseRecord) -> Bool {
        return lhs.id == rhs.id && lhs.text == rhs.text && lhs.time == rhs.time
    }
}

/// Bot message record
public struct BotMessageRecord: RecordItem, Identifiable, Equatable {
    public let id: String
    public let type: MessageType
    public let time: Date
    public let text: String?
    public let nodeData: [String: AnyCodable]?

    public init(
        id: String,
        time: Date,
        text: String? = nil,
        nodeData: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.type = .botMessage
        self.time = time
        self.text = text
        self.nodeData = nodeData
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case time
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = .botMessage
        time = try container.decode(Date.self, forKey: .time)
        text = try container.decodeIfPresent(String.self, forKey: .text)

        // Store all data as nodeData
        let allData = try decoder.singleValueContainer().decode([String: AnyCodable].self)
        nodeData = allData
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(time, forKey: .time)
        try container.encodeIfPresent(text, forKey: .text)

        if let nodeData = nodeData {
            var dataContainer = encoder.singleValueContainer()
            try dataContainer.encode(nodeData)
        }
    }

    public static func == (lhs: BotMessageRecord, rhs: BotMessageRecord) -> Bool {
        return lhs.id == rhs.id && lhs.text == rhs.text && lhs.time == rhs.time
    }
}

/// Agent message record
public struct AgentMessageRecord: RecordItem, Identifiable, Equatable {
    public let id: String
    public let type: MessageType
    public let time: Date
    public let text: String
    public let agentDetails: AgentDetails

    public init(
        id: String,
        time: Date,
        text: String,
        agentDetails: AgentDetails
    ) {
        self.id = id
        self.type = .agentMessage
        self.time = time
        self.text = text
        self.agentDetails = agentDetails
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case time
        case text
        case agentDetails
    }

    public static func == (lhs: AgentMessageRecord, rhs: AgentMessageRecord) -> Bool {
        return lhs.id == rhs.id && lhs.text == rhs.text && lhs.time == rhs.time
    }
}

/// Agent file message record
public struct AgentMessageFileRecord: RecordItem, Identifiable, Equatable {
    public let id: String
    public let type: MessageType
    public let time: Date
    public let file: String
    public let agentDetails: AgentDetails?

    public init(
        id: String,
        time: Date,
        file: String,
        agentDetails: AgentDetails? = nil
    ) {
        self.id = id
        self.type = .agentMessageFile
        self.time = time
        self.file = file
        self.agentDetails = agentDetails
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case time
        case file
        case agentDetails
    }

    public static func == (lhs: AgentMessageFileRecord, rhs: AgentMessageFileRecord) -> Bool {
        return lhs.id == rhs.id && lhs.file == rhs.file && lhs.time == rhs.time
    }
}

/// Agent audio message record
public struct AgentMessageAudioRecord: RecordItem, Identifiable, Equatable {
    public let id: String
    public let type: MessageType
    public let time: Date
    public let url: String
    public let agentDetails: AgentDetails

    public init(
        id: String,
        time: Date,
        url: String,
        agentDetails: AgentDetails
    ) {
        self.id = id
        self.type = .agentMessageAudio
        self.time = time
        self.url = url
        self.agentDetails = agentDetails
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case time
        case url
        case agentDetails
    }

    public static func == (lhs: AgentMessageAudioRecord, rhs: AgentMessageAudioRecord) -> Bool {
        return lhs.id == rhs.id && lhs.url == rhs.url && lhs.time == rhs.time
    }
}

/// Agent joined message record
public struct AgentJoinedMessageRecord: RecordItem, Identifiable, Equatable {
    public let id: String
    public let type: MessageType
    public let time: Date
    public let agentDetails: AgentDetails

    public init(
        id: String,
        time: Date,
        agentDetails: AgentDetails
    ) {
        self.id = id
        self.type = .agentJoinedMessage
        self.time = time
        self.agentDetails = agentDetails
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case time
        case agentDetails
    }

    public static func == (lhs: AgentJoinedMessageRecord, rhs: AgentJoinedMessageRecord) -> Bool {
        return lhs.id == rhs.id && lhs.time == rhs.time
    }
}

/// Agent left chat message record
public struct AgentLeftMessageRecord: RecordItem, Identifiable, Equatable {
    public let id: String
    public let type: MessageType
    public let time: Date
    public let agentDetails: AgentDetails

    public init(
        id: String,
        time: Date,
        agentDetails: AgentDetails
    ) {
        self.id = id
        self.type = .agentLeftChat
        self.time = time
        self.agentDetails = agentDetails
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case time
        case agentDetails
    }

    public static func == (lhs: AgentLeftMessageRecord, rhs: AgentLeftMessageRecord) -> Bool {
        return lhs.id == rhs.id && lhs.time == rhs.time
    }
}

/// System message record
public struct SystemMessageRecord: RecordItem, Identifiable, Equatable {
    public let id: String
    public let type: MessageType
    public let time: Date
    public let text: String

    public init(
        id: String,
        time: Date,
        text: String
    ) {
        self.id = id
        self.type = .systemMessage
        self.time = time
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case time
        case text
    }

    public static func == (lhs: SystemMessageRecord, rhs: SystemMessageRecord) -> Bool {
        return lhs.id == rhs.id && lhs.text == rhs.text && lhs.time == rhs.time
    }
}

/// Helper for decoding any RecordItem from JSON
public struct AnyRecordItem: Codable {
    public let value: any RecordItem

    public init(_ value: any RecordItem) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        let messageType = MessageType(rawValue: typeString) ?? .systemMessage

        switch messageType {
        case .userMessage:
            value = try UserMessageRecord(from: decoder)
        case .userInputResponse, .userLiveMessage:
            value = try UserInputResponseRecord(from: decoder)
        case .botMessage:
            value = try BotMessageRecord(from: decoder)
        case .agentMessage:
            value = try AgentMessageRecord(from: decoder)
        case .agentMessageFile:
            value = try AgentMessageFileRecord(from: decoder)
        case .agentMessageAudio:
            value = try AgentMessageAudioRecord(from: decoder)
        case .agentJoinedMessage:
            value = try AgentJoinedMessageRecord(from: decoder)
        case .agentLeftChat:
            value = try AgentLeftMessageRecord(from: decoder)
        default:
            value = try SystemMessageRecord(from: decoder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if let userMessage = value as? UserMessageRecord {
            try userMessage.encode(to: encoder)
        } else if let userInputResponse = value as? UserInputResponseRecord {
            try userInputResponse.encode(to: encoder)
        } else if let botMessage = value as? BotMessageRecord {
            try botMessage.encode(to: encoder)
        } else if let agentMessage = value as? AgentMessageRecord {
            try agentMessage.encode(to: encoder)
        } else if let fileMessage = value as? AgentMessageFileRecord {
            try fileMessage.encode(to: encoder)
        } else if let audioMessage = value as? AgentMessageAudioRecord {
            try audioMessage.encode(to: encoder)
        } else if let joinedMessage = value as? AgentJoinedMessageRecord {
            try joinedMessage.encode(to: encoder)
        } else if let leftMessage = value as? AgentLeftMessageRecord {
            try leftMessage.encode(to: encoder)
        } else if let systemMessage = value as? SystemMessageRecord {
            try systemMessage.encode(to: encoder)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
    }
}

/// AnyCodable wrapper for heterogeneous JSON
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dictionary = value as? [String: Any] {
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
}
