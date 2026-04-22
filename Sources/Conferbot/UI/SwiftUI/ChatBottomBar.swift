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
private let conferbotLogoURL = "https://prd.media.cdn.conferbot.com/62829a1c49f355163dfdbfb2/conferbot-logo-1710782074234.png"

@available(iOS 14.0, *)
public struct ChatBottomBar: View {
    @Binding var text: String
    let onSend: (String) -> Void
    let onEditingChanged: (Bool) -> Void
    var hideBrand: Bool = false
    var customBrand: String? = nil
    var primaryColor: Color = .blue

    @State private var isEditing = false
    @Environment(\.openURL) private var openURL

    public init(
        text: Binding<String>,
        onSend: @escaping (String) -> Void,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        hideBrand: Bool = false,
        customBrand: String? = nil,
        primaryColor: Color = .blue
    ) {
        self._text = text
        self.onSend = onSend
        self.onEditingChanged = onEditingChanged
        self.hideBrand = hideBrand
        self.customBrand = customBrand
        self.primaryColor = primaryColor
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Input row ──
            HStack(alignment: .center, spacing: 8) {
                // Pill-shaped input with subtle border
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text("Type a message...")
                            .foregroundColor(Color(hex: "4D4D4D"))
                            .font(.system(size: 16))
                            .padding(.horizontal, 18)
                    }

                    TextEditor(text: $text)
                        .font(.system(size: 16))
                        .foregroundColor(.black)
                        .frame(minHeight: 44, maxHeight: 130)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .scrollContentBackground(.hidden)
                        .background(Color.white)
                        .onChange(of: text) { newValue in
                            if newValue.count > ConferBotConstants.maxMessageLength {
                                text = String(newValue.prefix(ConferBotConstants.maxMessageLength))
                            }
                            if !isEditing {
                                isEditing = true
                                onEditingChanged(true)
                            }
                        }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color(hex: "E0E0E0"), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 25))

                // Themed circular send button
                Button(action: sendMessage) {
                    ZStack {
                        Circle()
                            .fill(canSend ? primaryColor : primaryColor.opacity(0.35))
                            .frame(width: 44, height: 44)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
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
        .background(Color.white)
        .shadow(color: Color(hex: "636363").opacity(0.12), radius: 4, x: 0, y: -4)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                .foregroundColor(Color(hex: "687882"))
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
                    Text("Powered by ")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "56595B"))

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

// MARK: - Color hex extension (if not already available)
@available(iOS 14.0, *)
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
