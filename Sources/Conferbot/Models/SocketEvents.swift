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
    public static let discordNodeTrigger = "discord-node-trigger"
    public static let calendarSlotSelectionRecord = "calendar-slot-selection-record"
    public static let notionNodeTrigger = "notion-node-trigger"
    public static let googleDriveNodeTrigger = "google-drive-node-trigger"
    public static let zohoCrmNodeTrigger = "zohocrm-node-trigger"
    public static let airtableNodeTrigger = "airtable-node-trigger"
    public static let googleMeetNodeTrigger = "google-meet-node-trigger"
    public static let googleDocsNodeTrigger = "google-docs-node-trigger"
    public static let googleCalendarNodeTrigger = "google-calendar-node-trigger"
    public static let stripeNodeTrigger = "stripe-node-trigger"
    public static let gptNodeTrigger = "gpt-node-trigger"
    public static let gmailNodeTrigger = "gmail-node-trigger"
    public static let webhookNodeTrigger = "webhook-node-trigger"
    public static let googleSheetsNodeTrigger = "google-sheets-node-trigger"
    public static let hubspotNodeTrigger = "hubspot-node-trigger"
    public static let slackNodeTrigger = "slack-node-trigger"

    // Analytics events
    public static let trackChatStart = "track-chat-start"
    public static let trackChatEngagement = "track-chat-engagement"
    public static let trackNodeVisit = "track-node-visit"
    public static let trackNodeExit = "track-node-exit"
    public static let trackSentiment = "track-sentiment"
    public static let trackInteraction = "track-interaction"
    public static let trackGoalCompletion = "track-goal-completion"
    public static let trackDropOff = "track-drop-off"
    public static let submitChatRating = "submit-chat-rating"
    public static let finalizeAnalytics = "finalize-analytics"
    public static let trackAnalytics = "track-analytics"

    // Knowledge Base events - Client to server
    public static let trackArticleView = "track-article-view"
    public static let trackArticleEngagement = "track-article-engagement"
    public static let rateArticle = "rate-article"
    public static let getKnowledgeBaseCategories = "get-knowledge-base-categories"
    public static let getKnowledgeBaseArticle = "get-knowledge-base-article"
    public static let searchKnowledgeBase = "search-knowledge-base"

    // Knowledge Base events - Server to client
    public static let knowledgeBaseCategoriesResponse = "knowledge-base-categories-response"
    public static let knowledgeBaseArticleResponse = "knowledge-base-article-response"
    public static let knowledgeBaseSearchResponse = "knowledge-base-search-response"
    public static let articleRated = "article-rated"

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

    // Stripe payment events - Server to client
    public static let stripePaymentUrlResponse = "stripe-payment-url-response"
    public static let stripePaymentComplete = "stripe-payment-complete"
    public static let stripePaymentFailed = "stripe-payment-failed"

    // Connection events
    public static let connect = "connect"
    public static let disconnect = "disconnect"
    public static let connectError = "connect_error"
    public static let reconnect = "reconnect"
    public static let reconnectAttempt = "reconnect_attempt"
    public static let reconnectError = "reconnect_error"
    public static let reconnectFailed = "reconnect_failed"
}
