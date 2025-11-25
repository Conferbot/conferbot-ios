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

    public init(id: String, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case email
    }
}
