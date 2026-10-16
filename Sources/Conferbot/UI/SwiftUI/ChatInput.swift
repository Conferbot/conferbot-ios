//
//  ChatInput.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI

/// Chat input view for SwiftUI
@available(iOS 15.0, *)
public struct ChatInput: View {
    @Binding var text: String
    let onSend: (String) -> Void
    let onEditingChanged: (Bool) -> Void
    /// Off for a locked or closed chat (#80): no typing, no sending.
    let enabled: Bool
    /// The empty field's line; nil is "Type a message...".
    let placeholder: String?

    @State private var isEditing = false

    public init(
        text: Binding<String>,
        enabled: Bool = true,
        placeholder: String? = nil,
        onSend: @escaping (String) -> Void,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._text = text
        self.enabled = enabled
        self.placeholder = placeholder
        self.onSend = onSend
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Text input: one line, growing with the text up to five (#76)
            ComposerField(text: $text, placeholder: placeholder ?? ChatText.placeholder, placeholderColor: .gray,
                          horizontalPadding: 14, verticalPadding: 10)
                .disabled(!enabled)
                .frame(minHeight: 40)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(20)
                .onChange(of: text) { newValue in
                    if newValue.count > ConferBotConstants.maxMessageLength {
                        text = String(newValue.prefix(ConferBotConstants.maxMessageLength))
                    }
                    if !isEditing && !newValue.isEmpty {
                        isEditing = true
                        onEditingChanged(true)
                    }
                }

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
            .accessibilityLabel(ChatText.send)
            .disabled(!enabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .opacity(enabled ? 1 : 0.6)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
    }

    private func sendMessage() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard enabled, !trimmedText.isEmpty else { return }

        onSend(trimmedText)
        text = ""
        isEditing = false
        onEditingChanged(false)
    }
}

@available(iOS 15.0, *)
struct ChatInput_Previews: PreviewProvider {
    static var previews: some View {
        ChatInput(text: .constant("")) { _ in }
    }
}
