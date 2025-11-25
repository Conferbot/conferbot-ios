//
//  ChatView.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI

/// Main chat view for SwiftUI
@available(iOS 14.0, *)
public struct ChatView: View {
    @ObservedObject private var conferBot = ConferBot.shared
    @State private var inputText = ""
    @State private var isSessionStarted = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Messages
            messagesView

            Divider()

            // Input
            inputView
        }
        .background(Color(UIColor.systemBackground))
        .task {
            if !isSessionStarted {
                isSessionStarted = true
                try? await conferBot.startSession()
            }
        }
    }

    private var headerView: some View {
        HStack {
            if conferBot.customization?.showAvatar ?? true {
                if let avatarURL = conferBot.customization?.avatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image.resizable()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(conferBot.customization?.headerTitle ?? "Support Chat")
                    .font(.headline)

                if conferBot.isConnected {
                    Text("Online")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(conferBot.messages.enumerated()), id: \.offset) { index, message in
                        MessageBubble(message: message, customization: conferBot.customization)
                            .id(index)
                    }

                    if conferBot.isAgentTyping {
                        TypingIndicator()
                            .id("typing")
                    }
                }
                .padding()
            }
            .onChange(of: conferBot.messages.count) { _ in
                withAnimation {
                    if let lastIndex = conferBot.messages.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
            .onChange(of: conferBot.isAgentTyping) { _ in
                withAnimation {
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            }
        }
    }

    private var inputView: some View {
        ChatInput(text: $inputText) { message in
            Task {
                try? await conferBot.sendMessage(message)
            }
        } onEditingChanged: { isEditing in
            conferBot.sendTypingIndicator(isTyping: isEditing)
        }
    }
}

@available(iOS 14.0, *)
struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView()
    }
}
