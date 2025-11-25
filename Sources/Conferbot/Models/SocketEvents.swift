//
//  SocketEvents.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation

/// Socket events matching embed-server socket.js
public struct SocketEvents {
    // Client to server events
    public static let getChatbotData = "get-chatbot-data"
    public static let joinChatRoomVisitor = "join-chat-room-visitor"
    public static let leaveChatRoom = "leave-chat-room"
    public static let visitorTyping = "visitor-typing"
    public static let responseRecord = "response-record" // Send visitor messages
    public static let initiateHandover = "initiate-handover"
    public static let endChat = "end-chat"
    public static let emailNodeTrigger = "email-node-trigger"
    public static let zapierNodeTrigger = "zapier-node-trigger"
    public static let calendarSlotSelectionRecord = "calendar-slot-selection-record"

    // Deprecated - use joinChatRoomVisitor instead
    @available(*, deprecated, renamed: "joinChatRoomVisitor")
    public static let joinChatRoom = "join-chat-room-visitor"
    @available(*, deprecated, message: "Use responseRecord instead")
    public static let sendVisitorMessage = "response-record"
    @available(*, deprecated, message: "Use joinChatRoomVisitor instead - mobileInit doesn't exist in embed-server")
    public static let mobileInit = "join-chat-room-visitor"

    // Server to client events
    public static let fetchedChatbotData = "fetched-chatbot-data"
    public static let botResponse = "bot-response"
    public static let agentMessage = "agent-message"
    public static let agentAccepted = "agent-accepted"
    public static let agentLeft = "agent-left"
    public static let agentTypingStatus = "agent-typing-status"
    public static let visitorTypingStatus = "visitor-typing-status"
    public static let chatEnded = "chat-ended"
    public static let visitorDisconnected = "visitor-disconnected"
    public static let visitorInputToggled = "visitor-input-toggled"
    public static let destroyNotification = "destroy-notification"

    // Connection events
    public static let connect = "connect"
    public static let disconnect = "disconnect"
    public static let connectError = "connect_error"
    public static let reconnect = "reconnect"
    public static let reconnectAttempt = "reconnect_attempt"
    public static let reconnectError = "reconnect_error"
    public static let reconnectFailed = "reconnect_failed"
}
