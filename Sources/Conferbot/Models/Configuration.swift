//
//  Configuration.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation
#if canImport(UIKit)
import UIKit
public typealias PlatformColor = PlatformColor
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

    public init(
        id: String,
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case phone
        case metadata
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
