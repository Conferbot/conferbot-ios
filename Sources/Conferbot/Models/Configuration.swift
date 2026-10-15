//
//  Configuration.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation
#if canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
#else
/// Stub color type for non-Apple platforms (Linux CI)
public class PlatformColor {
    public init() {}
}
#endif

/// User identification model
public struct ConferBotUser: Codable {
    public let id: String
    public let name: String?
    public let email: String?
    public let phone: String?
    public let metadata: [String: AnyCodable]?
    /// Identity verification: HMAC-SHA256 of the user's id (or email when there
    /// is no id) with your workspace's identity secret, hex, made on your
    /// server. With it the chat is filed under the verified user.
    public let hash: String?

    public init(
        id: String,
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        metadata: [String: AnyCodable]? = nil,
        hash: String? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.metadata = metadata
        self.hash = hash
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case phone
        case metadata
        case hash
    }

    /// The user as the web widget's visitorContext: the app's own data, then id, name, email, phone, hash.
    public func toVisitorContext() -> [String: Any] {
        var ctx: [String: Any] = [:]
        metadata?.forEach { ctx[$0.key] = $0.value.value }
        ctx["id"] = id
        for (key, value) in [("name", name), ("email", email), ("phone", phone), ("hash", hash)] {
            if let v = value, !v.trimmingCharacters(in: .whitespaces).isEmpty { ctx[key] = v }
        }
        return ctx
    }
}

/// SDK configuration options
public struct ConferBotConfig {
    public let enableNotifications: Bool
    public let enableOfflineMode: Bool
    public let apiBaseURL: String
    public let socketURL: String

    public init(
        enableNotifications: Bool = true,
        enableOfflineMode: Bool = true,
        apiBaseURL: String = ConferBotEndpoints.apiBaseURL,
        socketURL: String = ConferBotEndpoints.socketURL
    ) {
        self.enableNotifications = enableNotifications
        self.enableOfflineMode = enableOfflineMode
        self.apiBaseURL = apiBaseURL
        self.socketURL = socketURL
    }
}

/// UI customization options
public struct ConferBotCustomization {
    public let primaryColor: PlatformColor?
    public let fontFamily: String?
    public let bubbleCornerRadius: CGFloat?
    public let headerTitle: String?
    public let showAvatar: Bool
    public let avatarURL: URL?
    public let botBubbleColor: PlatformColor?
    public let userBubbleColor: PlatformColor?
    /// When true, hides the "Powered by Conferbot" footer
    public let hideBrand: Bool

    public init(
        primaryColor: PlatformColor? = nil,
        fontFamily: String? = nil,
        bubbleCornerRadius: CGFloat? = nil,
        headerTitle: String? = nil,
        showAvatar: Bool = true,
        avatarURL: URL? = nil,
        botBubbleColor: PlatformColor? = nil,
        userBubbleColor: PlatformColor? = nil,
        hideBrand: Bool = false
    ) {
        self.primaryColor = primaryColor
        self.fontFamily = fontFamily
        self.bubbleCornerRadius = bubbleCornerRadius
        self.headerTitle = headerTitle
        self.showAvatar = showAvatar
        self.avatarURL = avatarURL
        self.botBubbleColor = botBubbleColor
        self.userBubbleColor = userBubbleColor
        self.hideBrand = hideBrand
    }
}
