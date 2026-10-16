//
//  ChatBottomBar.swift
//  Conferbot
//
//  Unified bottom bar: chat input + powered-by footer as one seamless block.
//  Matches the web widget where input area and footer share the same
//  white background with a single upward shadow.
//

import SwiftUI

private let conferbotURL = "https://www.conferbot.com"
private let conferbotLogoURL = "https://www.conferbot.com/img/logo/conferbot-logo.png"

@available(iOS 15.0, *)
public struct ChatBottomBar: View {
    @Binding var text: String
    let onSend: (String) -> Void
    let onEditingChanged: (Bool) -> Void
    var hideBrand: Bool = false
    var customBrand: String? = nil
    var primaryColor: Color = .blue
    /// Off while the agent turned replies off or locked the conversation.
    var enabled: Bool = true
    var placeholder: String = I18n.t("chat.composer.placeholder")
    /// The paperclip: shown when given (a live chat that takes visitor files).
    var onAttach: (() -> Void)? = nil
    /// The widget theme's surfaces and text (nil: white, as before).
    var tokens: ThemeTokens? = nil
    /// The field's corner radius: 25 (a pill) unless the theme has its own.
    var fieldRadius: Double = 25
    /// Ink on the send button: the theme palette's, else white.
    var sendInk: Color = .white

    @State private var isEditing = false
    @Environment(\.openURL) private var openURL

    public init(
        text: Binding<String>,
        onSend: @escaping (String) -> Void,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        hideBrand: Bool = false,
        customBrand: String? = nil,
        primaryColor: Color = .blue,
        enabled: Bool = true,
        placeholder: String = I18n.t("chat.composer.placeholder"),
        onAttach: (() -> Void)? = nil,
        tokens: ThemeTokens? = nil,
        fieldRadius: Double = 25,
        sendInk: Color = .white
    ) {
        self._text = text
        self.onSend = onSend
        self.onEditingChanged = onEditingChanged
        self.hideBrand = hideBrand
        self.customBrand = customBrand
        self.primaryColor = primaryColor
        self.enabled = enabled
        self.placeholder = placeholder
        self.onAttach = onAttach
        self.tokens = tokens
        self.fieldRadius = fieldRadius
        self.sendInk = sendInk
    }

    private var surface: Color { tokens.map { Color(hex: $0.bg) } ?? .white }
    private var muted: Color { tokens.map { Color(hex: $0.muted) } ?? Color(hex: "56595B") }
    private var radius: CGFloat { CGFloat(min(fieldRadius, 25)) }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Input row ──
            HStack(alignment: .bottom, spacing: 8) {
                if let onAttach = onAttach {
                    Button(action: onAttach) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                            .frame(width: 36, height: 44)
                    }
                    .disabled(!enabled)
                    .accessibilityLabel(ChatText.attach)
                }
                // Pill-shaped input with subtle border: one line, growing
                // with the text up to five, as the web's composer (#76)
                ComposerField(
                    text: $text,
                    placeholder: placeholder,
                    placeholderColor: tokens.map { Color(hex: $0.muted) } ?? Color(hex: "4D4D4D"),
                    textColor: tokens.map { Color(hex: $0.ink) } ?? .black
                )
                .frame(minHeight: 44)
                .hideEditorBackground()
                .background(tokens.map { Color(hex: $0.field) } ?? .white)
                .disabled(!enabled)
                .onChange(of: text) { newValue in
                    if newValue.count > ConferBotConstants.maxMessageLength {
                        text = String(newValue.prefix(ConferBotConstants.maxMessageLength))
                    }
                    if !isEditing && !newValue.isEmpty {
                        isEditing = true
                        onEditingChanged(true)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(tokens.map { Color(hex: $0.line2) } ?? Color(hex: "E0E0E0"), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: radius))

                // Themed circular send button
                Button(action: sendMessage) {
                    ZStack {
                        Circle()
                            .fill(canSend ? primaryColor : primaryColor.opacity(0.35))
                            .frame(width: 44, height: 44)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(sendInk)
                    }
                }
                .accessibilityLabel(ChatText.send)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // ── Powered-by footer — same white background, no separator ──
            if !hideBrand {
                footerView
            }
        }
        .background(surface)
        .shadow(color: Color(hex: "636363").opacity(0.12), radius: 4, x: 0, y: -4)
    }

    private var canSend: Bool {
        enabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        onSend(trimmedText)
        text = ""
        isEditing = false
        onEditingChanged(false)
    }

    @ViewBuilder
    private var footerView: some View {
        if let brand = customBrand, !brand.isEmpty {
            Text(brand)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tokens.map { Color(hex: $0.muted) } ?? Color(hex: "687882"))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 8)
        } else {
            Button(action: {
                if let url = URL(string: conferbotURL) {
                    openURL(url)
                }
            }) {
                HStack(spacing: 4) {
                    Text(ChatText.poweredBy + " ")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(muted)

                    AsyncImage(url: URL(string: conferbotLogoURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 18)
                    } placeholder: {
                        // Fallback: bold "conferbot" text
                        Text("conferbot")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "4A4A4A"))
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }
}


@available(iOS 15.0, *)
private extension View {
    /// TextEditor's own background off (iOS 16+; iOS 15 draws it clear already
    /// once UITextView's background is cleared by the app's appearance).
    @ViewBuilder
    func hideEditorBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
