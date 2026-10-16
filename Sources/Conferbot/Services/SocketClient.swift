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
    /// Listeners added with on(_:callback:), kept so they hold before connect()
    /// creates the socket (ConferBot registers them first) and across a new socket.
    private var handlers: [(event: String, callback: NormalCallback)] = []
    /// The visitor, sent with the handshake so the server can refuse one the
    /// workspace blocked (web core/socket.ts). Set before connect().
    public var visitorId: String?
    /// The handshake was refused: the workspace blocked this visitor
    /// (connect_error "visitor_blocked"). The socket stops retrying.
    public var onBlocked: (() -> Void)?

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

    /// One connect at a time: two threads building managers at once tore
    /// down each other's socket mid-connect.
    private let connectLock = NSLock()

    /// Connect to socket server
    public func connect() {
        connectLock.lock()
        defer { connectLock.unlock() }
        guard socket?.status != .connected else {
            debugPrint("[ConferBot Socket] Already connected")
            return
        }

        let config: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            // The embed-server reads socket.handshake.query.botId, so the
            // connect params must use plain keys (not X- header names)
            .connectParams(handshakeParams),
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
        for h in handlers { socket?.on(h.event, callback: h.callback) }
        // The visitor in the handshake's auth too (socket.io v4 reads both).
        socket?.connect(withPayload: visitorId.map { ["botId": botId, "visitorId": $0] } ?? ["botId": botId])
    }

    /// The handshake's query: the bot, and the visitor when known (#40).
    var handshakeParams: [String: Any] {
        var params: [String: Any] = [
            "botId": botId,
            "apiKey": apiKey,
            "platform": ConferBotConstants.platformIdentifier
        ]
        if let id = visitorId, !id.isEmpty { params["visitorId"] = String(id.prefix(128)) }
        return params
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
            // Refused at the handshake: the workspace blocked this visitor.
            // No retrying; the chat shows its closed state.
            if LiveEvents.isBlockedError(data) {
                self?.manager?.reconnects = false
                self?.socket?.disconnect()
                self?.onBlocked?()
            }
        }

        socket?.on(clientEvent: .reconnect) { [weak self] _, _ in
            self?.debugPrint("[ConferBot Socket] Reconnected")
        }

        socket?.on(clientEvent: .reconnectAttempt) { [weak self] data, _ in
            self?.debugPrint("[ConferBot Socket] Reconnect attempt: \(data)")
        }
    }

    /// Request the bot configuration. The embed-server answers with the
    /// 'fetched-chatbot-data' event (workspaceId, customizations, elements).
    public func requestChatbotData() {
        emit(SocketEvents.getChatbotData, ["botId": botId])
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
            "answerVariables": answerVariables,
            "channel": "mobile"
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

    /// end-chat. Only an agent ends a live chat: the server refuses it from a
    /// visitor (`forbidden`), so the SDK never sends it; ConferBot.endSession
    /// leaves the queue with queue-self-resolve instead (#59).
    public func endChat(chatSessionId: String) {
        emit(SocketEvents.endChat, ["chatSessionId": chatSessionId])
    }

    /// Emit event with variadic data
    public func emit(_ event: String, _ data: SocketData...) {
        guard isConnected else {
            debugPrint("[ConferBot Socket] Cannot emit - not connected")
            return
        }
        // Each item as its own argument: passing the variadic array on sent
        // the server one array ([{botId}]) instead of the payload itself.
        socket?.emit(event, with: data, completion: nil)
    }

    /// Emit event with dictionary data (for analytics)
    public func emit(event: String, data: [String: Any]) {
        guard isConnected else {
            debugPrint("[ConferBot Socket] Cannot emit - not connected")
            return
        }
        socket?.emit(event, data)
    }

    /// Emit and wait for the server's acknowledgement (ai-action-decision,
    /// ai-answer-feedback). `completion` gets the first ack item, or nil when
    /// offline or after `timeout` seconds.
    public func emitWithAck(event: String, data: [String: Any], timeout: Double = 30, completion: @escaping (Any?) -> Void = { _ in }) {
        guard isConnected, let socket = socket else {
            completion(nil)
            return
        }
        socket.emitWithAck(event, data).timingOut(after: timeout) { items in
            // socket.io reports a timeout as the single item "NO ACK".
            if let first = items.first as? String, first == "NO ACK" {
                completion(nil)
            } else {
                completion(items.first)
            }
        }
    }

    /// Listen to event
    public func on(_ event: String, callback: @escaping NormalCallback) {
        handlers.append((event, callback))
        socket?.on(event, callback: callback)
    }

    /// Remove event listener
    public func off(_ event: String) {
        handlers.removeAll { $0.event == event }
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
