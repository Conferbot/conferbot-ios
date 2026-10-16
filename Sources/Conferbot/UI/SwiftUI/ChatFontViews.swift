//
//  ChatFontViews.swift
//  Conferbot
//
//  The chat's font in SwiftUI (Core/Fonts; RN hooks/useChatFont.ts): the
//  owner's font, else the theme's, once loaded; until then (or with none)
//  the text keeps the font it had. Body text keeps Dynamic Type
//  (`relativeTo`).
//

import SwiftUI

extension Font.Weight {
    /// The CSS weight (400 regular, 700 bold).
    var cssWeight: Int {
        switch self {
        case .ultraLight: return 200
        case .thin: return 100
        case .light: return 300
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }
}

@available(iOS 14.0, *)
extension ChatFontLoader {
    /// The chat's font for `role` text of `size` and `weight`, or nil (the system font draws it).
    func font(_ role: Role, size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font? {
        guard let name = faceName(role, weight: weight.cssWeight) else { return nil }
        let font = Font.custom(name, size: size, relativeTo: style)
        // A system or unknown family drawn by name: its weight from SwiftUI.
        let role = role == .body ? fonts.body : fonts.display
        return role?.google == nil ? font.weight(weight) : font
    }
}

@available(iOS 15.0, *)
private struct ChatFontModifier: ViewModifier {
    @ObservedObject private var loader = ConferBot.shared.chatFont
    let role: ChatFontLoader.Role
    let size: CGFloat
    let weight: Font.Weight
    let style: Font.TextStyle
    let fallback: Font?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let font = loader.font(role, size: size, weight: weight, relativeTo: style) {
            content.font(font)
        } else if let fallback = fallback {
            content.font(fallback)
        } else {
            content
        }
    }
}

@available(iOS 15.0, *)
extension View {
    /// The chat's font (the owner's, else the theme's) for this text; else
    /// `fallback` (nil: the font it already has).
    func chatFont(_ role: ChatFontLoader.Role = .body, size: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize,
                  weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body, fallback: Font? = nil) -> some View {
        modifier(ChatFontModifier(role: role, size: size, weight: weight, style: style, fallback: fallback))
    }
}
