//
//  Agent.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation

/// Agent model representing a live agent
public struct Agent: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let email: String?
    public let avatar: String?
    public let title: String?
    public let status: String?

    public init(
        id: String,
        name: String,
        email: String? = nil,
        avatar: String? = nil,
        title: String? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.avatar = avatar
        self.title = title
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case avatar
        case title
        case status
    }
}

/// Agent details matching embed-server agentDetails structure
public struct AgentDetails: Codable, Equatable {
    public let id: String
    public let name: String
    public let email: String
    public let avatar: String?
    /// An AI agent (Agent Studio) rather than a person.
    public let isAIAgent: Bool

    public init(id: String, name: String, email: String, avatar: String? = nil, isAIAgent: Bool = false) {
        self.id = id
        self.name = name
        self.email = email
        self.avatar = avatar
        self.isAIAgent = isAIAgent
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case email
        case avatar
        case isAIAgent
    }

    // An AI agent's details carry no email (and a person's may not): decoding
    // failed on them, and the agent never joined.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? I18n.t("agent.agent")
        email = (try? c.decode(String.self, forKey: .email)) ?? ""
        let rawAvatar = try? c.decode(String.self, forKey: .avatar)
        avatar = (rawAvatar?.isEmpty ?? true) ? nil : rawAvatar
        isAIAgent = ((try? c.decode(Bool.self, forKey: .isAIAgent)) ?? false) || id.hasPrefix("ai-agent-")
    }
}
