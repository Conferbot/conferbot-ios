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


/// Configurable endpoint URLs with HTTPS enforcement.
/// Use `ConferBotEndpoints.configure(...)` to override default URLs.
public struct ConferBotEndpoints {
    /// The current API base URL. Defaults to `ConferBotConstants.defaultApiBaseURL`.
    public static var apiBaseURL: String = ConferBotConstants.defaultApiBaseURL

    /// The current Socket URL. Defaults to `ConferBotConstants.defaultSocketURL`.
    public static var socketURL: String = ConferBotConstants.defaultSocketURL

    /// Configure custom endpoint URLs. Both must use HTTPS.
    /// - Parameters:
    ///   - apiBaseURL: Custom API base URL (must start with "https://")
    ///   - socketURL: Custom socket URL (must start with "https://")
    public static func configure(apiBaseURL: String? = nil, socketURL: String? = nil) {
        if let api = apiBaseURL {
            precondition(api.hasPrefix("https://"), "ConferBot: API URL must use HTTPS")
            self.apiBaseURL = api
        }
        if let socket = socketURL {
            precondition(socket.hasPrefix("https://"), "ConferBot: Socket URL must use HTTPS")
            self.socketURL = socket
        }
    }

    /// Reset endpoints to their default values.
    public static func resetToDefaults() {
        apiBaseURL = ConferBotConstants.defaultApiBaseURL
        socketURL = ConferBotConstants.defaultSocketURL
    }
}

// MARK: - Configurable Network Config

/// Configurable network timeouts and retry policies.
/// Use ConferBotNetworkConfig.configure(...) to override defaults.
public struct ConferBotNetworkConfig {
    public static var apiTimeout: TimeInterval = ConferBotConstants.apiTimeout
    public static var socketTimeout: TimeInterval = ConferBotConstants.socketTimeout
    public static var reconnectionAttempts: Int = ConferBotConstants.socketReconnectionAttempts
    public static var reconnectionDelay: TimeInterval = ConferBotConstants.socketReconnectionDelay
    public static var reconnectionDelayMax: TimeInterval = ConferBotConstants.socketReconnectionDelayMax

    public static func configure(
        apiTimeout: TimeInterval? = nil,
        socketTimeout: TimeInterval? = nil,
        reconnectionAttempts: Int? = nil,
        reconnectionDelay: TimeInterval? = nil,
        reconnectionDelayMax: TimeInterval? = nil
    ) {
        if let t = apiTimeout { precondition(t > 0, "apiTimeout must be > 0"); self.apiTimeout = t }
        if let t = socketTimeout { precondition(t > 0, "socketTimeout must be > 0"); self.socketTimeout = t }
        if let a = reconnectionAttempts { precondition(a >= 0, "reconnectionAttempts must be >= 0"); self.reconnectionAttempts = a }
        if let d = reconnectionDelay { precondition(d > 0, "reconnectionDelay must be > 0"); self.reconnectionDelay = d }
        if let d = reconnectionDelayMax { precondition(d > 0, "reconnectionDelayMax must be > 0"); self.reconnectionDelayMax = d }
    }

    public static func reset() {
        apiTimeout = ConferBotConstants.apiTimeout
        socketTimeout = ConferBotConstants.socketTimeout
        reconnectionAttempts = ConferBotConstants.socketReconnectionAttempts
        reconnectionDelay = ConferBotConstants.socketReconnectionDelay
        reconnectionDelayMax = ConferBotConstants.socketReconnectionDelayMax
    }
}

// MARK: - Logger

/// Lightweight logger that always invokes the logHandler callback (if set),
/// and prints to console only in DEBUG builds.
public enum ConferBotLogger {
    public static var isEnabled: Bool = true
    public static var logHandler: ((String, LogLevel) -> Void)?

    public enum LogLevel: String { case debug, info, warning, error }

    public static func error(_ message: String) {
        log(message, level: .error)
    }

    public static func warning(_ message: String) {
        log(message, level: .warning)
    }

    public static func info(_ message: String) {
        log(message, level: .info)
    }

    public static func debug(_ message: String) {
        log(message, level: .debug)
    }

    private static func log(_ message: String, level: LogLevel) {
        guard isEnabled else { return }
        logHandler?(message, level)
        #if DEBUG
        let prefix: String
        switch level {
        case .debug:   prefix = "[ConferBot DEBUG]"
        case .info:    prefix = "[ConferBot INFO]"
        case .warning: prefix = "[ConferBot WARN]"
        case .error:   prefix = "[ConferBot ERROR]"
        }
        print("\(prefix) \(message)")
        #endif
    }
}


