//
//  ChatHeader.swift
//  Conferbot
//
//  The chat header's title and connection line (web headerPresence.ts),
//  also for a chat that never got the bot's settings: a visitor refused at
//  the handshake (#79) gets a closed chat and no fetched-chatbot-data, so
//  the header showed "Connecting..." for good. A closed chat is not
//  connecting to anything: no connection line. The title is the bot's name
//  from the last settings this device saw for the bot, else the host's.
//

import Foundation

enum ChatHeader {

    /// The line under the title while there is no connection.
    enum Connection: Equatable {
        /// "Connecting..."
        case connecting
        /// Connected: the tagline, the reply time or "Online", as before.
        case connected
        /// A closed chat (blocked, or ended with nothing going on): no line.
        case none
    }

    static func connection(connected: Bool, closed: Bool) -> Connection {
        if connected { return .connected }
        return closed ? .none : .connecting
    }

    /// The bot's name: the settings' title, else the one remembered from the
    /// last settings for this bot, else the host's title, else "Support Chat".
    static func title(server: String?, remembered: String?, host: String?) -> String {
        for t in [server, remembered, host] {
            if let t = t?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        }
        return I18n.t("sdk.header.supportChat")
    }

    static let titleKeyPrefix = "conferbot_bot_title_"

    /// Kept each time the bot's settings are applied.
    static func remember(_ title: String, botId: String?, defaults: UserDefaults = .standard) {
        guard let botId = botId, !botId.isEmpty else { return }
        let key = titleKeyPrefix + botId
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, defaults.string(forKey: key) != t else { return }
        defaults.set(t, forKey: key)
    }

    static func remembered(botId: String?, defaults: UserDefaults = .standard) -> String? {
        guard let botId = botId, !botId.isEmpty else { return nil }
        return defaults.string(forKey: titleKeyPrefix + botId)
    }
}
