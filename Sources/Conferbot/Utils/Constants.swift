//
//  Constants.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation

/// Conferbot SDK constants
public struct ConferBotConstants {
    // API Configuration
    public static let defaultApiBaseURL = "https://embed.conferbot.com/api/v1/mobile"
    public static let defaultSocketURL = "https://embed.conferbot.com"
    public static let apiTimeout: TimeInterval = 30.0 // 30 seconds
    public static let socketTimeout: TimeInterval = 20.0 // 20 seconds

    // Headers
    public static let headerApiKey = "X-API-Key"
    public static let headerBotId = "X-Bot-ID"
    public static let headerPlatform = "X-Platform"

    // Platform identifier
    public static let platformIdentifier = "ios"

    // Socket configuration
    public static let socketReconnectionAttempts = 5
    public static let socketReconnectionDelay: TimeInterval = 1.0
    public static let socketReconnectionDelayMax: TimeInterval = 5.0

    // Message limits
    public static let maxMessageLength = 5000
    public static let maxFileSize = 10485760 // 10MB

    // UI Constants
    public static let typingIndicatorDuration: TimeInterval = 3.0
    public static let messageAnimationDuration: TimeInterval = 0.3
}
