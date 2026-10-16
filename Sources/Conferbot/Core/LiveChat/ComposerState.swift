//
//  ComposerState.swift
//  Conferbot
//
//  Whether the message box takes text and what its empty line says, for
//  every stock chat (ChatView, ChatViewWithKBSheet, #80): off while the
//  agent locked the conversation or turned replies off ("Replies are
//  off"), off for a closed chat with the closed line ("This conversation
//  has been closed.", "Chat ended", #40).
//

import Foundation

struct ComposerState: Equatable {
    let enabled: Bool
    let placeholder: String

    static func of(lockedBy: String?, visitorInputEnabled: Bool, closed: LiveEvents.ClosedState?) -> ComposerState {
        let repliesOff = lockedBy != nil || !visitorInputEnabled
        if let closed = closed, closed.inputOff {
            return ComposerState(enabled: false, placeholder: closed.text)
        }
        return ComposerState(enabled: !repliesOff,
                             placeholder: repliesOff ? I18n.t("sdk.chat.repliesOff") : I18n.t("chat.composer.placeholder"))
    }
}
