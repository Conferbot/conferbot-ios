//
//  ChatInput.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI

/// Chat input view for SwiftUI
@available(iOS 14.0, *)
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
            // Text input
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Type a message...")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                TextEditor(text: $text)
                    .frame(minHeight: 40, maxHeight: 100)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(20)
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

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
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

@available(iOS 14.0, *)
struct ChatInput_Previews: PreviewProvider {
    static var previews: some View {
        ChatInput(text: .constant("")) { _ in }
    }
}
