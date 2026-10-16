//
//  MessageBubble.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI

/// Message bubble view for SwiftUI
@available(iOS 15.0, *)
public struct MessageBubble: View {
    let message: any RecordItem
    let customization: ConferBotCustomization?
    /// A translated agent message shows the agent's own words when on.
    @State private var showOriginal = false
    /// The bot's settings as the web applies them, once they arrived. Taken
    /// when the row is made, so a bubble drawn before they came (a restored
    /// conversation) is drawn again with the bot's avatar and bubble style
    /// once they do (#65).
    private let look: ResolvedCustomizations?

    public init(message: any RecordItem, customization: ConferBotCustomization?) {
        self.message = message
        self.customization = customization
        self.look = ConferBot.shared.hasServerLook ? ConferBot.shared.customizations : nil
    }

    public var body: some View {
        if let line = systemLine {
            // A centred line, as on the web: joined, left, the Connecting
            // line (dots while it waits) and how it ended, chat ended.
            SystemLineView(text: line.text, pending: line.pending, note: line.note,
                           color: look?.theme.tokens.map { Color(hex: $0.muted) } ?? .secondary)
        } else {
            bubbleRow
        }
    }

    /// The line's words for a joined / left / system record, nil for a bubble.
    private var systemLine: (text: String, pending: Bool, note: String?)? {
        if let left = message as? AgentLeftMessageRecord {
            return (left.text, left.isPendingHandover, nil)
        }
        if let joined = message as? AgentJoinedMessageRecord {
            return (HandoverState.joinedText(joined.agentDetails.name), false, joined.afterAI == true ? HandoverState.handedOverNote : nil)
        }
        if let system = message as? SystemMessageRecord {
            return (system.text, false, nil)
        }
        return nil
    }

    /// The web's row (css/polish.css): a bot message starts at the left edge
    /// with its avatar in a fixed 32pt column, on the bubble's bottom line
    /// (the column stays when the avatar is hidden, so the bubbles and the
    /// step cards under them line up); the visitor's ends at the right edge,
    /// 48pt clear of the left. Neither runs the full width.
    private var bubbleRow: some View {
        HStack(alignment: .bubbleBottom, spacing: 8) {
            if isUserMessage {
                Spacer(minLength: 48)
            } else if showsAvatar {
                avatarView
                    .frame(width: MessageBubble.avatarColumn)
                    .alignmentGuide(.bubbleBottom) { $0[.bottom] }
            } else {
                Color.clear.frame(width: MessageBubble.avatarColumn, height: 1)
                    .alignmentGuide(.bubbleBottom) { $0[.bottom] }
            }

            VStack(alignment: isUserMessage ? .trailing : .leading, spacing: 4) {
                VStack(alignment: isUserMessage ? .trailing : .leading, spacing: 4) {
                    if let imageUrl = standaloneImageUrl {
                        // Standalone bot image (welcome-node / image-node):
                        // rounded, no bubble background - web widget parity
                        StandaloneImageView(url: imageUrl)
                    } else if let frozen = frozenChoices {
                        // Persisted choice pills: disabled, selected one highlighted
                        ChoicePillsView(
                            pills: frozen.labels.map { ChoicePillsView.Pill(id: $0, label: $0) },
                            selectedLabel: frozen.selected,
                            isFrozen: true,
                            primaryColor: pillPrimaryColor,
                            ink: look.map { Color(hex: $0.optionTextColor) },
                            onTap: nil
                        )
                    } else if let rich = message as? AgentRichMessageRecord {
                        // An agent's article, quick replies or card (AgentReplyViews.swift)
                        RichAgentMessageView(record: rich, accent: pillPrimaryColor, bubbleColor: backgroundColor)
                    } else if let agentMessage = message as? AgentMessageRecord {
                        // Lists, bold and tappable links; an unsent message says so.
                        Group {
                            if agentMessage.deleted {
                                Text(ChatText.deleted).italic().opacity(0.7)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    // The server answering because the AI failed: the same
                                    // bubble, italic and muted (web _markAgentFallbackBubble, #49).
                                    ChatMarkdownText(text: showOriginal ? (agentMessage.translation?.original ?? agentMessage.text) : agentMessage.text, color: textColor,
                                                     muted: agentMessage.extras?.isFallback == true)
                                        .chatFont(.body)
                                    // Sent in the visitor's language: the agent's own words one tap away.
                                    if let translation = agentMessage.translation {
                                        let labels = LiveChat.translationLabels(translation.to)
                                        Button { showOriginal.toggle() } label: {
                                            Text(showOriginal ? labels.1 : labels.0)
                                                .font(.caption)
                                                .underline()
                                                .foregroundColor(textColor.opacity(0.8))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(backgroundColor)
                        .foregroundColor(textColor)
                        .clipShape(bubbleShape)
                        .overlay(bubbleOutline)

                        // An AI reply's sources, buttons, cards and "Helpful?"
                        AgentReplyExtrasView(message: agentMessage, accent: pillPrimaryColor)
                    } else if let fileInfo = extractFileInfo() {
                        FileMessageBubble(
                            fileInfo: fileInfo,
                            isUserMessage: isUserMessage,
                            backgroundColor: backgroundColor,
                            cornerRadius: customization?.bubbleCornerRadius ?? 16
                        )
                    } else if let html = botHtml {
                        // Text from the builder's rich-text editor, drawn
                        // formatted as the web draws it (#64)
                        ChatMarkdownText(text: ChatMarkdown.htmlToMarkdown(html), color: textColor)
                            .chatFont(.body)
                            .padding(12)
                            .background(backgroundColor)
                            .clipShape(bubbleShape)
                            .overlay(bubbleOutline)
                    } else {
                        Text(messageText)
                            .chatFont(.body)
                            .padding(12)
                            .background(backgroundColor)
                            .foregroundColor(textColor)
                            .clipShape(bubbleShape)
                            .overlay(bubbleOutline)
                    }
                }
                // The bot's tapback and the burst on the visitor's answer (Core/Delight)
                .overlay(Group {
                    if isUserMessage {
                        AnswerTouches(rowId: message.id, accent: Color(hex: look?.accent ?? "0808EE"),
                                      card: look?.theme.tokens.map { Color(hex: $0.card) } ?? Color(UIColor.systemBackground),
                                      ring: look?.surface.map { Color(hex: $0) } ?? Color(UIColor.systemBackground))
                    }
                })
                .alignmentGuide(.bubbleBottom) { $0[.bottom] }

                Text((message as? AgentMessageRecord)?.edited == true ? ChatText.editedAt(timeString) : timeString)
                    .font(.caption2)
                    .foregroundColor(look?.theme.tokens.map { Color(hex: $0.muted) } ?? .secondary)
                // "Edit" under the visitor's latest answer
                if isUserMessage {
                    ChangeAnswerSlot(rowId: message.id, muted: look?.theme.tokens.map { Color(hex: $0.muted) } ?? .secondary)
                }
            }

            if !isUserMessage {
                Spacer(minLength: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUserMessage ? .trailing : .leading)
    }

    /// The bot's avatar column (the web's 32px avatar and its 8px gap make
    /// the 40pt indent the step cards use).
    static let avatarColumn: CGFloat = 32

    private var showsAvatar: Bool {
        (customization?.showAvatar ?? true) && !(look.map { $0.hideAvatar } ?? false)
    }

    private var isUserMessage: Bool {
        return message.type == .userMessage || message.type == .userInputResponse || message.type == .userLiveMessageFile
    }

    /// A relative /media proxy link opens on the server.
    private func resolvedFileURL(_ raw: String) -> String {
        LiveChat.resolveMediaURL(raw, origin: ConferBotEndpoints.socketURL)?.absoluteString ?? raw
    }

    private var botNodeData: [String: AnyCodable]? {
        return (message as? BotMessageRecord)?.nodeData
    }

    /// URL of a standalone bot image entry (welcome-node / image-node)
    private var standaloneImageUrl: String? {
        return botNodeData?["imageUrl"]?.value as? String
    }

    /// Frozen (already answered) choice pills persisted in the transcript
    private var frozenChoices: (labels: [String], selected: String?)? {
        guard let labels = botNodeData?["choices"]?.value as? [String], !labels.isEmpty else {
            return nil
        }
        return (labels, botNodeData?["selectedChoice"]?.value as? String)
    }

    private var pillPrimaryColor: Color {
        if let look = look { return Color(hex: look.optionBubbleColor) }
        if let color = customization?.primaryColor {
            return Color(color)
        }
        return .blue
    }

    /// A bot message whose text is the owner's HTML (<p>, <strong>, <a>...).
    private var botHtml: String? {
        guard let text = (message as? BotMessageRecord)?.text, text.range(of: "<[a-zA-Z/][^>]*>", options: .regularExpression) != nil else { return nil }
        return text
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
            return ChatText.file(fileMessage.file)
        } else if let audioMessage = message as? AgentMessageAudioRecord {
            return ChatText.audio
        } else if let joinedMessage = message as? AgentJoinedMessageRecord {
            return HandoverState.joinedText(joinedMessage.agentDetails.name)
        } else if let systemMessage = message as? SystemMessageRecord {
            return systemMessage.text
        }
        return ""
    }

    /// Extract file information from the message if present
    private func extractFileInfo() -> FileMessageInfo? {
        // Check for agent file message
        // The visitor's file in a live chat
        if let visitorFile = message as? UserLiveMessageFileRecord {
            let url = resolvedFileURL(visitorFile.url)
            let filename = LiveChat.fileName(visitorFile.fileName, url: url)
            return FileMessageInfo(url: url, filename: filename, mimeType: visitorFile.mimeType ?? mimeType(for: filename), fileSize: nil)
        }

        if let fileMessage = message as? AgentMessageFileRecord {
            let filename = LiveChat.fileName(nil, url: fileMessage.file)
            return FileMessageInfo(
                url: resolvedFileURL(fileMessage.file),
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

    /// The web's bubble corners, else the host app's radius.
    /// The widget theme's outline round the bubble (cartoon, neo-brutal, sketch...).
    @ViewBuilder
    private var bubbleOutline: some View {
        if let b = look?.bubbleBorder {
            bubbleShape.stroke(Color(hex: b.color), lineWidth: CGFloat(b.width))
        }
    }

    private var bubbleShape: BubbleShape {
        if let look = look { return BubbleShape(corners: isUserMessage ? look.userBubble : look.botBubble) }
        return BubbleShape(corners: .all(Double(customization?.bubbleCornerRadius ?? 16)))
    }

    private var backgroundColor: Color {
        if let look = look { return Color(hex: isUserMessage ? look.userBubbleColor : look.botBubbleColor) }
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
        if let look = look { return Color(hex: isUserMessage ? look.userTextColor : look.botTextColor) }
        return isUserMessage ? .white : .primary
    }

    private var timeString: String {
        ChatText.time(message.time)
    }

    private var avatarView: some View {
        // Never wider than the column (the web pins it at 32px).
        let size = min(CGFloat(look?.avatarSize ?? 32), MessageBubble.avatarColumn)
        let radius = min(CGFloat(look?.avatarRadius ?? 16), size / 2)
        return Group {
            if let avatarURL = agentPhoto ?? (look.flatMap { URL(string: $0.avatar) }) ?? customization?.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable()
                } placeholder: {
                    initialsAvatar
                }
            } else {
                initialsAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A person's own photo in a live chat (an AI agent uses the bot's avatar).
    private var agentPhoto: URL? {
        guard let details = (message as? AgentMessageRecord)?.agentDetails, details.isAIAgent != true else { return nil }
        return details.avatar.flatMap { URL(string: $0) }
    }

    /// Colored-circle initials fallback (never transparent) - shows the
    /// agent's initial during live chat, otherwise the bot/header initial
    private var initialsAvatar: some View {
        ZStack {
            Circle().fill(pillPrimaryColor)
            Text(avatarInitial)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private var avatarInitial: String {
        let name: String
        if let agentMessage = message as? AgentMessageRecord {
            name = agentMessage.agentDetails.name
        } else if let joinedMessage = message as? AgentJoinedMessageRecord {
            name = joinedMessage.agentDetails.name
        } else {
            name = customization?.headerTitle ?? ChatText.bot
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "B" : String(trimmed.prefix(1)).uppercased()
    }
}

// MARK: - System Line

/// A centred system line (web .cb-sys): with three dots fading in turn while
/// the Connecting line waits, and a note under it ("They can see your
/// conversation so far").
@available(iOS 15.0, *)
struct SystemLineView: View {
    let text: String
    let pending: Bool
    let note: String?
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            if pending {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().fill(color).frame(width: 5, height: 5).opacity(Self.dotOpacity(t, i))
                        }
                    }
                }
                .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption)
                .foregroundColor(color)
                .multilineTextAlignment(.center)
            if let note = note {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(color.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Each dot brightens in turn over the 1.2s loop.
    static func dotOpacity(_ t: Double, _ i: Int) -> Double {
        let peak = (Double(i) + 0.5) / 4
        let d = abs(t - peak)
        return d < 0.25 ? 1 - d / 0.25 * 0.7 : 0.3
    }
}

// MARK: - Standalone Bot Image

/// Rounded standalone image (welcome-node / image-node) rendered without a
/// bubble background, left-aligned past the avatar column - web widget parity
@available(iOS 15.0, *)
struct StandaloneImageView: View {
    let url: String

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                    .frame(width: 100, height: 100)
            case .empty:
                ProgressView()
                    .frame(width: 100, height: 100)
            @unknown default:
                EmptyView()
            }
        }
        .frame(maxWidth: 220, alignment: .leading)
        .cornerRadius(10)
    }
}

// MARK: - Choice Pills

/// Choice pills used both interactively (while a choice node awaits input)
/// and frozen from the transcript after answering (disabled, selected pill
/// highlighted in the primary color, others dimmed)
@available(iOS 15.0, *)
struct ChoicePillsView: View {
    struct Pill: Identifiable {
        let id: String
        let label: String
    }

    let pills: [Pill]
    /// Label of the selected pill (only meaningful when frozen)
    let selectedLabel: String?
    let isFrozen: Bool
    /// The option bubble colour (filled, as the web's choice bubbles).
    let primaryColor: Color
    /// The option text colour; nil: the old outlined pill in `primaryColor`.
    var ink: Color? = nil
    let onTap: ((Pill) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pills) { pill in
                pillButton(for: pill)
            }
        }
    }

    private func pillButton(for pill: Pill) -> some View {
        let isSelected = isFrozen && pill.label == selectedLabel

        return Button(action: { onTap?(pill) }) {
            if let ink = ink {
                // The bot's option bubble: its colour, its text colour (web __chat__choice__bubble)
                Text(pill.label)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(primaryColor)
                    .foregroundColor(ink)
                    .clipShape(Capsule())
                    .opacity(isFrozen && !isSelected ? 0.45 : 1)
            } else {
                Text(pill.label)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isSelected ? primaryColor : Color.clear)
                    .foregroundColor(isSelected ? .white : primaryColor)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(primaryColor, lineWidth: 1)
                    )
                    .opacity(isFrozen && !isSelected ? 0.45 : 1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isFrozen)
    }
}

// MARK: - File Message Info

/// Information about a file in a message
@available(iOS 15.0, *)
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
@available(iOS 15.0, *)
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
                    .accessibilityLabel(I18n.t("common.close"))
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

/// Typing indicator view with bot avatar, in the owner's typing style
/// (chatChrome.ts typingStyle): dots, an equaliser wave, a shimmering
/// "Typing...", a pencil writing a line, or the bot's mascot swaying beside
/// three thought dots. Still under Reduce Motion.
@available(iOS 15.0, *)
public struct TypingIndicator: View {
    @State private var animating = false
    var avatarURL: URL? = nil

    private var look: ResolvedCustomizations? {
        ConferBot.shared.hasServerLook ? ConferBot.shared.customizations : nil
    }

    private var dotColor: Color { look.map { Color(hex: $0.botTextColor) } ?? .gray }

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

            // The owner's typing style in a bubble (chatChrome.ts typingStyle): the bot's
            // colours and the web's 18/6 bubble once the bot's settings arrived.
            let style = look?.typingStyle ?? "dots"
            Group {
                switch style {
                case "mascot":
                    TypingMascotView(look: look!.mascot, accent: look!.mascotAccent, ink: dotColor)
                        .padding(.leading, 6)
                        .padding(.trailing, 12)
                        .frame(height: 42)
                case "pencil":
                    TypingPencilView(accent: look!.mascotAccent, ink: dotColor, inkHex: look!.botTextColor)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 70, minHeight: 36)
                case "shimmer":
                    TypingShimmerView(ink: dotColor)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 92, minHeight: 36)
                default:
                    HStack(spacing: look == nil ? 6 : (style == "wave" ? 3 : 4)) {
                        ForEach(0..<(style == "wave" ? 5 : 3), id: \.self) { index in
                            Group {
                                if style == "wave" {
                                    RoundedRectangle(cornerRadius: 1.5).fill(dotColor).frame(width: 3, height: animating ? 16 : 5)
                                } else {
                                    Circle().fill(dotColor).frame(width: look == nil ? 8 : 6, height: look == nil ? 8 : 6)
                                }
                            }
                                .opacity(animating ? 0.3 : 1.0)
                                .animation(
                                    Animation.easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(index) * 0.2),
                                    value: animating
                                )
                        }
                    }
                    .padding(.horizontal, look == nil ? 16 : 12)
                    .frame(minWidth: look == nil ? nil : 54, minHeight: look == nil ? nil : 36)
                    .padding(.vertical, look == nil ? 10 : 0)
                }
            }
            .background(look.map { Color(hex: $0.botBubbleColor) } ?? Color(UIColor.systemGray5))
            .clipShape(BubbleShape(corners: look?.botBubble ?? .all(16)))
            // "Pip is typing" when the owner named their mascot, else "Typing".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MascotMoods.typingLabel(style, look?.mascot.name ?? ""))
        }
        // In the bot's column, as a bot message (it was centred).
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            animating = true
        }
    }
}

private extension VerticalAlignment {
    /// The bottom of a message's bubble (not its time line), where the avatar sits.
    enum BubbleBottom: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.bottom] }
    }
    static let bubbleBottom = VerticalAlignment(BubbleBottom.self)
}
