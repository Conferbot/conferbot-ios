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

    @State private var isEditing = false

    public init(
        text: Binding<String>,
        onSend: @escaping (String) -> Void,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._text = text
        self.onSend = onSend
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Text input: one line, growing with the text up to five (#76)
            ComposerField(text: $text, placeholder: ChatText.placeholder, placeholderColor: .gray,
                          horizontalPadding: 14, verticalPadding: 10)
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
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
    }

    private func sendMessage() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else { return }

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
