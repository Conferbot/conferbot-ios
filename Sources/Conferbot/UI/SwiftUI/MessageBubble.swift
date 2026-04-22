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
                // Check for file content
                if let fileInfo = extractFileInfo() {
                    FileMessageBubble(
                        fileInfo: fileInfo,
                        isUserMessage: isUserMessage,
                        backgroundColor: backgroundColor,
                        cornerRadius: customization?.bubbleCornerRadius ?? 16
                    )
                } else {
                    Text(messageText)
                        .padding(12)
                        .background(backgroundColor)
                        .foregroundColor(textColor)
                        .cornerRadius(customization?.bubbleCornerRadius ?? 16)
                }

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
        return message.type == .userMessage || message.type == .userInputResponse
    }

    private var messageText: String {
        if let userMessage = message as? UserMessageRecord {
            return userMessage.text
        } else if let userInputResponse = message as? UserInputResponseRecord {
            return userInputResponse.text
        } else if let botMessage = message as? BotMessageRecord {
            return botMessage.text ?? "..."
        } else if let agentMessage = message as? AgentMessageRecord {
            return agentMessage.text
        } else if let fileMessage = message as? AgentMessageFileRecord {
            return "File: \(fileMessage.file)"
        } else if let audioMessage = message as? AgentMessageAudioRecord {
            return "Audio message"
        } else if let joinedMessage = message as? AgentJoinedMessageRecord {
            return "\(joinedMessage.agentDetails.name) joined the chat"
        } else if let systemMessage = message as? SystemMessageRecord {
            return systemMessage.text
        }
        return ""
    }

    /// Extract file information from the message if present
    private func extractFileInfo() -> FileMessageInfo? {
        // Check for agent file message
        if let fileMessage = message as? AgentMessageFileRecord {
            let filename = URL(string: fileMessage.file)?.lastPathComponent ?? fileMessage.file
            return FileMessageInfo(
                url: fileMessage.file,
                filename: filename,
                mimeType: mimeType(for: filename),
                fileSize: nil
            )
        }

        // Check for user message with file metadata
        if let userMessage = message as? UserMessageRecord,
           let metadata = userMessage.metadata {
            if let url = metadata["url"]?.value as? String {
                let filename = metadata["filename"]?.value as? String
                    ?? metadata["name"]?.value as? String
                    ?? URL(string: url)?.lastPathComponent
                    ?? "file"
                let mimeType = metadata["mimeType"]?.value as? String
                    ?? self.mimeType(for: filename)
                let fileSize = metadata["fileSize"]?.value as? Int64

                return FileMessageInfo(
                    url: url,
                    filename: filename,
                    mimeType: mimeType,
                    fileSize: fileSize
                )
            }
        }

        // Check for user input response with file metadata
        if let userInputResponse = message as? UserInputResponseRecord,
           let metadata = userInputResponse.metadata {
            if let url = metadata["url"]?.value as? String {
                let filename = metadata["filename"]?.value as? String
                    ?? metadata["name"]?.value as? String
                    ?? URL(string: url)?.lastPathComponent
                    ?? "file"
                let mimeType = metadata["mimeType"]?.value as? String
                    ?? self.mimeType(for: filename)
                let fileSize = metadata["fileSize"]?.value as? Int64

                return FileMessageInfo(
                    url: url,
                    filename: filename,
                    mimeType: mimeType,
                    fileSize: fileSize
                )
            }
        }

        // Check if text looks like a file URL or contains file marker
        let text = messageText
        if text.hasPrefix("[File:") || text.hasPrefix("File:") {
            // Extract URL from text if present
            if let range = text.range(of: "http", options: .caseInsensitive) {
                let urlString = String(text[range.lowerBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ]"))
                if let url = URL(string: urlString) {
                    return FileMessageInfo(
                        url: urlString,
                        filename: url.lastPathComponent,
                        mimeType: mimeType(for: url.lastPathComponent),
                        fileSize: nil
                    )
                }
            }
        }

        return nil
    }

    private func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "doc", "docx": return "application/msword"
        case "xls", "xlsx": return "application/vnd.ms-excel"
        case "mp4": return "video/mp4"
        case "mp3": return "audio/mpeg"
        default: return "application/octet-stream"
        }
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

// MARK: - File Message Info

/// Information about a file in a message
@available(iOS 14.0, *)
public struct FileMessageInfo {
    public let url: String
    public let filename: String
    public let mimeType: String
    public let fileSize: Int64?

    public var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    public var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }

    public var isAudio: Bool {
        mimeType.hasPrefix("audio/")
    }

    public var formattedSize: String? {
        guard let size = fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public var fileExtension: String {
        (filename as NSString).pathExtension.lowercased()
    }

    public var iconName: String {
        switch fileExtension {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "doc.richtext.fill"
        case "zip", "rar", "7z": return "doc.zipper"
        case "mp3", "wav", "m4a", "aac": return "music.note"
        case "mp4", "mov", "avi": return "film.fill"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - File Message Bubble

/// A bubble view that displays file content with preview
@available(iOS 14.0, *)
public struct FileMessageBubble: View {
    let fileInfo: FileMessageInfo
    let isUserMessage: Bool
    let backgroundColor: Color
    let cornerRadius: CGFloat

    @State private var showFullImage = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show image preview for images
            if fileInfo.isImage {
                imagePreview
            } else {
                // Show file info for other types
                fileInfoView
            }
        }
        .padding(12)
        .background(backgroundColor)
        .cornerRadius(cornerRadius)
        .fullScreenCover(isPresented: $showFullImage) {
            imageFullScreen
        }
    }

    private var imagePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: fileInfo.url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 220, maxHeight: 200)
                        .cornerRadius(8)
                        .onTapGesture {
                            showFullImage = true
                        }
                case .failure:
                    fileInfoView
                case .empty:
                    ProgressView()
                        .frame(width: 100, height: 100)
                @unknown default:
                    EmptyView()
                }
            }

            // Show filename below image
            HStack(spacing: 4) {
                Image(systemName: "photo.fill")
                    .font(.caption2)
                Text(fileInfo.filename)
                    .font(.caption)
                    .lineLimit(1)
                if let size = fileInfo.formattedSize {
                    Text("(\(size))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(isUserMessage ? .white.opacity(0.9) : .secondary)
        }
    }

    private var fileInfoView: some View {
        Button(action: openFile) {
            HStack(spacing: 12) {
                // File icon
                Image(systemName: fileInfo.iconName)
                    .font(.title2)
                    .foregroundColor(isUserMessage ? .white : .accentColor)
                    .frame(width: 40)

                // File details
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileInfo.filename)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isUserMessage ? .white : .primary)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        if let size = fileInfo.formattedSize {
                            Text(size)
                        }
                        Text(fileInfo.fileExtension.uppercased())
                    }
                    .font(.caption)
                    .foregroundColor(isUserMessage ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                // Download/open indicator
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundColor(isUserMessage ? .white.opacity(0.8) : .accentColor)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: 250)
    }

    private var imageFullScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: URL(string: fileInfo.url)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { showFullImage = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .padding()
                }
                Spacer()

                // Bottom bar with filename and share
                HStack {
                    Text(fileInfo.filename)
                        .foregroundColor(.white)
                        .font(.caption)
                    Spacer()
                    Button(action: shareFile) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.5))
            }
        }
    }

    private func openFile() {
        guard let url = URL(string: fileInfo.url) else { return }
        UIApplication.shared.open(url)
    }

    private func shareFile() {
        guard let url = URL(string: fileInfo.url) else { return }

        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

/// Typing indicator view with bot avatar — matches web widget
@available(iOS 14.0, *)
public struct TypingIndicator: View {
    @State private var animating = false
    var avatarURL: URL? = nil

    public init(avatarURL: URL? = nil) {
        self.avatarURL = avatarURL
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Bot avatar
            if let url = avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.gray)
            }

            // Typing dots in a bubble
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(UIColor.systemGray5))
            .cornerRadius(16)
        }
        .padding(.horizontal, 12)
        .onAppear {
            animating = true
        }
    }
}
