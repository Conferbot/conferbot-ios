//
//  ChatView.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI

/// Tab selection for chat view with knowledge base
@available(iOS 14.0, *)
public enum ChatViewTab: Int, CaseIterable {
    case chat = 0
    case knowledgeBase = 1

    var title: String {
        switch self {
        case .chat:
            return "Chat"
        case .knowledgeBase:
            return "Help"
        }
    }

    var icon: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .knowledgeBase:
            return "book"
        }
    }
}

/// Main chat view for SwiftUI with Knowledge Base support
@available(iOS 14.0, *)
public struct ChatView: View {
    @ObservedObject private var conferBot = ConferBot.shared
    @State private var inputText = ""
    @State private var isSessionStarted = false
    @State private var selectedTab: ChatViewTab = .chat
    @State private var showKnowledgeBaseSheet = false

    /// Enable or disable the knowledge base tab
    public var enableKnowledgeBase: Bool

    public init(enableKnowledgeBase: Bool = true) {
        self.enableKnowledgeBase = enableKnowledgeBase
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Tab bar (if KB is enabled)
            if enableKnowledgeBase {
                tabBarView
            }

            Divider()

            // Content based on selected tab
            if enableKnowledgeBase && selectedTab == .knowledgeBase {
                KnowledgeBaseView()
            } else {
                // Chat content
                VStack(spacing: 0) {
                    messagesView
                    Divider()
                    inputView
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .task {
            if !isSessionStarted {
                isSessionStarted = true
                try? await conferBot.startSession()
            }
        }
        .sheet(isPresented: $showKnowledgeBaseSheet) {
            KnowledgeBaseView()
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

            // Knowledge Base button (alternative to tab)
            if !enableKnowledgeBase {
                Button(action: {
                    showKnowledgeBaseSheet = true
                }) {
                    Image(systemName: "book")
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                }
                .padding(.trailing, 4)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }

    private var tabBarView: some View {
        HStack(spacing: 0) {
            ForEach(ChatViewTab.allCases, id: \.rawValue) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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

// MARK: - Tab Button

@available(iOS 14.0, *)
struct TabButton: View {
    let tab: ChatViewTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 14))

                    Text(tab.title)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
                .foregroundColor(isSelected ? .accentColor : .gray)

                // Selection indicator
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Chat View with KB Sheet

/// Chat view that shows Knowledge Base as a sheet instead of a tab
@available(iOS 14.0, *)
public struct ChatViewWithKBSheet: View {
    @ObservedObject private var conferBot = ConferBot.shared
    @State private var inputText = ""
    @State private var isSessionStarted = false
    @State private var showKnowledgeBase = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header with KB button
            headerView

            Divider()

            // Messages
            messagesView

            Divider()

            // Input with KB quick access
            inputViewWithKB
        }
        .background(Color(UIColor.systemBackground))
        .task {
            if !isSessionStarted {
                isSessionStarted = true
                try? await conferBot.startSession()
            }
        }
        .sheet(isPresented: $showKnowledgeBase) {
            NavigationView {
                KnowledgeBaseView()
                    .navigationBarItems(trailing: Button("Done") {
                        showKnowledgeBase = false
                    })
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

            // Knowledge Base button
            Button(action: {
                showKnowledgeBase = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "book")
                    Text("Help")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .foregroundColor(.accentColor)
                .cornerRadius(16)
            }
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

    private var inputViewWithKB: some View {
        VStack(spacing: 0) {
            // Quick help suggestion
            if conferBot.messages.isEmpty {
                quickHelpSuggestion
            }

            ChatInput(text: $inputText) { message in
                Task {
                    try? await conferBot.sendMessage(message)
                }
            } onEditingChanged: { isEditing in
                conferBot.sendTypingIndicator(isTyping: isEditing)
            }
        }
    }

    private var quickHelpSuggestion: some View {
        Button(action: {
            showKnowledgeBase = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.caption)

                Text("Browse help articles before chatting")
                    .font(.caption)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.caption)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.05))
            .foregroundColor(.accentColor)
        }
    }
}

@available(iOS 14.0, *)
struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView()
    }
}
