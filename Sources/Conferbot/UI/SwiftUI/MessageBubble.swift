//
//  MessageBubble.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI

/// Message bubble view for SwiftUI
@available(iOS 14.0, *)
public struct MessageBubble: View {
    let message: any RecordItem
    let customization: ConferBotCustomization?

    public init(message: any RecordItem, customization: ConferBotCustomization?) {
        self.message = message
        self.customization = customization
    }

    public var body: some View {
        HStack {
            if isUserMessage {
                Spacer()
            }

            if !isUserMessage && (customization?.showAvatar ?? true) {
                avatarView
            }

            VStack(alignment: isUserMessage ? .trailing : .leading, spacing: 4) {
                Text(messageText)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundColor(textColor)
                    .cornerRadius(customization?.bubbleCornerRadius ?? 16)

                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if isUserMessage {
                Spacer()
                    .frame(width: 48)
            }
        }
    }

    private var isUserMessage: Bool {
        return message.type == .userMessage
    }

    private var messageText: String {
        if let userMessage = message as? UserMessageRecord {
            return userMessage.text
        } else if let botMessage = message as? BotMessageRecord {
            return botMessage.text ?? "..."
        } else if let agentMessage = message as? AgentMessageRecord {
            return agentMessage.text
        } else if let fileMessage = message as? AgentMessageFileRecord {
            return "📎 File: \(fileMessage.file)"
        } else if let audioMessage = message as? AgentMessageAudioRecord {
            return "🎵 Audio message"
        } else if let joinedMessage = message as? AgentJoinedMessageRecord {
            return "\(joinedMessage.agentDetails.name) joined the chat"
        } else if let systemMessage = message as? SystemMessageRecord {
            return systemMessage.text
        }
        return ""
    }

    private var backgroundColor: Color {
        if isUserMessage {
            if let color = customization?.userBubbleColor {
                return Color(color)
            }
            return Color.blue
        } else {
            if let color = customization?.botBubbleColor {
                return Color(color)
            }
            return Color(UIColor.systemGray5)
        }
    }

    private var textColor: Color {
        return isUserMessage ? .white : .primary
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.time)
    }

    private var avatarView: some View {
        Group {
            if let avatarURL = customization?.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.gray)
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
}

/// Typing indicator view
@available(iOS 14.0, *)
public struct TypingIndicator: View {
    @State private var animating = false

    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .opacity(animating ? 0.3 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(12)
        .background(Color(UIColor.systemGray5))
        .cornerRadius(16)
        .onAppear {
            animating = true
        }
    }
}
