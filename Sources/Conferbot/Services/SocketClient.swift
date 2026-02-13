//
//  SocketClient.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation
import SocketIO

/// Socket client for real-time communication
public class SocketClient {
    private let apiKey: String
    private let botId: String
    private let socketURL: String
    private var manager: SocketManager?
    private var socket: SocketIOClient?

    public var isConnected: Bool {
        return socket?.status == .connected
    }

    public init(
        apiKey: String,
        botId: String,
        socketURL: String = ConferBotEndpoints.socketURL
    ) {
        self.apiKey = apiKey
        self.botId = botId
        self.socketURL = socketURL
    }

    deinit {
        disconnect()
    }

    /// Connect to socket server
    public func connect() {
        guard socket?.status != .connected else {
            debugPrint("[ConferBot Socket] Already connected")
            return
        }

        let config: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .connectParams([
                ConferBotConstants.headerApiKey: apiKey,
                ConferBotConstants.headerBotId: botId,
                ConferBotConstants.headerPlatform: ConferBotConstants.platformIdentifier
            ]),
            .extraHeaders([
                ConferBotConstants.headerApiKey: apiKey,
                ConferBotConstants.headerBotId: botId,
                ConferBotConstants.headerPlatform: ConferBotConstants.platformIdentifier
            ]),
            .reconnects(true),
            .reconnectAttempts(ConferBotNetworkConfig.reconnectionAttempts),
            .reconnectWait(Int(ConferBotNetworkConfig.reconnectionDelay * 1000)),
            .reconnectWaitMax(Int(ConferBotNetworkConfig.reconnectionDelayMax * 1000))
        ]

        guard let url = URL(string: socketURL) else {
            debugPrint("[ConferBot Socket] Invalid URL: \(socketURL)")
            return
        }

        manager = SocketManager(socketURL: url, config: config)
        socket = manager?.defaultSocket

        setupConnectionHandlers()
        socket?.connect()
    }

    private func setupConnectionHandlers() {
        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            self?.debugPrint("[ConferBot Socket] Connected")
        }

        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.debugPrint("[ConferBot Socket] Disconnected")
        }

        socket?.on(clientEvent: .error) { [weak self] data, _ in
            self?.debugPrint("[ConferBot Socket] Error: \(data)")
        }

        socket?.on(clientEvent: .reconnect) { [weak self] _, _ in
            self?.debugPrint("[ConferBot Socket] Reconnected")
        }

        socket?.on(clientEvent: .reconnectAttempt) { [weak self] data, _ in
            self?.debugPrint("[ConferBot Socket] Reconnect attempt: \(data)")
        }
    }

    /// Join chat room as visitor (use this instead of deprecated mobileInit)
    /// This matches embed-server's 'join-chat-room-visitor' event
    public func joinChatRoomVisitor(
        chatSessionId: String,
        platform: String = ConferBotConstants.platformIdentifier,
        deviceInfo: [String: Any]? = nil
    ) {
        var data: [String: Any] = [
            "chatSessionId": chatSessionId,
            "platform": platform
        ]

        if let deviceInfo = deviceInfo {
            data["deviceInfo"] = deviceInfo
        }

        emit(SocketEvents.joinChatRoomVisitor, data)
    }

    /// Leave chat room
    /// Note: embed-server expects just the chatSessionId string, not a dictionary
    public func leaveChatRoom(chatSessionId: String) {
        guard isConnected else {
            debugPrint("[ConferBot Socket] Cannot emit - not connected")
            return
        }
        socket?.emit(SocketEvents.leaveChatRoom, chatSessionId)
    }

    /// Send response record (visitor message)
    /// This matches embed-server's 'response-record' event
    public func sendResponseRecord(
        chatSessionId: String,
        record: [[String: Any]],
        answerVariables: [[String: Any]] = [],
        visitorMeta: String? = nil,
        vIp: String? = nil
    ) {
        var data: [String: Any] = [
            "chatSessionId": chatSessionId,
            "botId": botId,
            "record": record,
            "answerVariables": answerVariables
        ]

        if let visitorMeta = visitorMeta {
            data["visitorMeta"] = visitorMeta
        }

        if let vIp = vIp {
            data["vIp"] = vIp
        }

        emit(SocketEvents.responseRecord, data)
    }

    // MARK: - Deprecated Methods

    /// Initialize mobile session
    /// - Note: Deprecated - use joinChatRoomVisitor instead
    @available(*, deprecated, message: "Use joinChatRoomVisitor instead - mobileInit event doesn't exist in embed-server")
    public func mobileInit(
        chatSessionId: String,
        visitorId: String? = nil,
        deviceInfo: [String: Any]? = nil
    ) {
        joinChatRoomVisitor(chatSessionId: chatSessionId, deviceInfo: deviceInfo)
    }

    /// Join chat room as visitor (deprecated)
    @available(*, deprecated, renamed: "joinChatRoomVisitor")
    public func joinChatRoom(chatSessionId: String) {
        joinChatRoomVisitor(chatSessionId: chatSessionId)
    }

    /// Send visitor message (deprecated)
    /// - Note: Use sendResponseRecord instead
    @available(*, deprecated, message: "Use sendResponseRecord instead")
    public func sendVisitorMessage(
        chatSessionId: String,
        record: [String: Any],
        answerVariables: [[String: Any]],
        visitorMeta: [String: Any]? = nil
    ) {
        sendResponseRecord(
            chatSessionId: chatSessionId,
            record: [record],
            answerVariables: answerVariables
        )
    }

    /// Send visitor typing status
    public func sendTypingStatus(chatSessionId: String, isTyping: Bool) {
        emit(SocketEvents.visitorTyping, [
            "chatSessionId": chatSessionId,
            "isTyping": isTyping
        ])
    }

    /// Initiate handover to live agent
    public func initiateHandover(chatSessionId: String, message: String? = nil) {
        var data: [String: Any] = ["chatSessionId": chatSessionId]
        if let message = message {
            data["message"] = message
        }
        emit(SocketEvents.initiateHandover, data)
    }

    /// End chat
    public func endChat(chatSessionId: String) {
        emit(SocketEvents.endChat, ["chatSessionId": chatSessionId])
    }

    /// Emit event with variadic data
    public func emit(_ event: String, _ data: SocketData...) {
        guard isConnected else {
            debugPrint("[ConferBot Socket] Cannot emit - not connected")
            return
        }
        socket?.emit(event, data)
    }

    /// Emit event with dictionary data (for analytics)
    public func emit(event: String, data: [String: Any]) {
        guard isConnected else {
            debugPrint("[ConferBot Socket] Cannot emit - not connected")
            return
        }
        socket?.emit(event, data)
    }

    /// Listen to event
    public func on(_ event: String, callback: @escaping NormalCallback) {
        socket?.on(event, callback: callback)
    }

    /// Remove event listener
    public func off(_ event: String) {
        socket?.off(event)
    }

    /// Disconnect from socket
    public func disconnect() {
        socket?.disconnect()
        socket?.removeAllHandlers()
        socket = nil
        manager = nil
    }

    private func debugPrint(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
