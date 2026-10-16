//
//  ComposerField.swift
//  Conferbot
//
//  The composer's text field: one line while empty, growing with the text
//  up to a few lines and then scrolling, as the web widget's composer does.
//  A bare TextEditor takes all the height it is offered, which left an empty
//  box about four lines tall (#76).
//

import SwiftUI

@available(iOS 15.0, *)
struct ComposerField: View {
    @Binding var text: String
    let placeholder: String
    var placeholderColor: Color = Color(hex: "4D4D4D")
    var textColor: Color = .primary
    var fontSize: CGFloat = 16
    /// Lines shown before the field scrolls.
    var maxLines: Int = 5
    /// Space around the text; the field's height is one line plus these.
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 12

    var body: some View {
        if #available(iOS 16.0, *) {
            // A text field that wraps and grows (iOS 16+); Return adds a line.
            TextField("", text: $text, axis: .vertical)
                .lineLimit(1...maxLines)
                .chatFont(.body, size: fontSize, fallback: .system(size: fontSize))
                .foregroundColor(textColor)
                .background(alignment: .leading) {
                    if text.isEmpty { placeholderText }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
        } else {
            // iOS 15: the TextEditor sized by an invisible copy of its text,
            // capped at maxLines (it scrolls past that).
            Text(text.isEmpty ? " " : text + (text.hasSuffix("\n") ? " " : ""))
                .chatFont(.body, size: fontSize, fallback: .system(size: fontSize))
                .lineLimit(maxLines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .opacity(0)
                .overlay(
                    // UITextView insets its text 8pt top / bottom and 5pt at the sides.
                    TextEditor(text: $text)
                        .chatFont(.body, size: fontSize, fallback: .system(size: fontSize))
                        .foregroundColor(textColor)
                        .padding(.horizontal, horizontalPadding - 5)
                        .padding(.vertical, verticalPadding - 8)
                )
                .overlay(alignment: .leading) {
                    if text.isEmpty {
                        placeholderText.padding(.horizontal, horizontalPadding)
                    }
                }
        }
    }

    private var placeholderText: some View {
        Text(placeholder)
            .chatFont(.body, size: fontSize, fallback: .system(size: fontSize))
            .foregroundColor(placeholderColor)
            .lineLimit(1)
            .allowsHitTesting(false)
    }
}
