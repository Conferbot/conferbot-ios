//
//  WaitingGames.swift
//  Conferbot
//
//  Waiting games: the owner's settings, the catalogue, and when the offer is
//  made and when it steps aside. Ported from the React Native SDK
//  (src/core/waitingGames.ts), itself from the web widget:
//  conferbot-widget src/ts/chat/games/settings.ts (waitingGamesOf, GAMES,
//  PLAY_RE) and src/ts/chat/games/wire.ts (OFFER_DELAY_MS, the offer's
//  retries, "Not now", the typed "play"), with nodeKit.ts pickAccent for the
//  card's accent. Pure: the card itself is GamesCard.swift, and
//  WaitingExtras feeds the signals in.
//
//    waitingGames: { enabled: boolean, games: string[], offerText: string }
//
//  Unset means on with every game: the offer only ever appears while a
//  visitor is waiting for a person (cb:waiting-for-human), never starts a
//  game by itself, and goes away the moment a teammate joins.
//
//    cb:waiting-for-human  after offerDelayMs, one offer card per wait.
//    cb:human-joined       a game in progress is saved and folded away
//                          (wrapUp), an unused offer leaves.
//    cb:wait-over          no offer any more; an unused card leaves, a game
//                          being played stays to finish.
//
//  While waiting, a visitor who types "play" or "games" gets the menu instead
//  of sending it. "Not now" (or the x) means no more offers for this app
//  session (the web: this page view). Nothing is stored or sent.
//

import Foundation

public enum GameId: String, CaseIterable, Equatable {
    case rps, ttt, quiz, memory, reaction, emoji, scramble
}

public struct GameMeta: Equatable {
    public let id: GameId
    public let emoji: String
    /// The game's name in the active language (web ui.ts gameName, games.<id>.name).
    public var name: String { I18n.t("games.\(id.rawValue).name") }
    /// One line for the menu, in the active language (games.<id>.blurb).
    public var blurb: String { I18n.t("games.\(id.rawValue).blurb") }
}

public enum WaitingGames {

    public static let games: [GameMeta] = [
        GameMeta(id: .rps, emoji: "✊"),
        GameMeta(id: .ttt, emoji: "⭕"),
        GameMeta(id: .quiz, emoji: "🧠"),
        GameMeta(id: .memory, emoji: "🃏"),
        GameMeta(id: .reaction, emoji: "⚡"),
        GameMeta(id: .emoji, emoji: "🤔"),
        GameMeta(id: .scramble, emoji: "🔤"),
    ]

    public static let gameIds: [GameId] = games.map(\.id)

    public static func meta(_ id: GameId) -> GameMeta? { games.first { $0.id == id } }

    /// The stock offer as stored (English); drawn as `offerLine` (web ui.ts:
    /// the stock line is t("games.offer")).
    public static let defaultOfferText = "While you wait - fancy a quick game? 🎮"

    /// The offer as drawn: the stock line in the active language, the owner's own as written.
    public static func offerLine(_ offerText: String) -> String {
        offerText == defaultOfferText ? I18n.t("games.offer") : offerText
    }
    public static let offerTextMax = 140

    /// The games that work in a language: the emoji riddles are English
    /// wordplay ("Bookworm", "Hot dog"), so they are offered in English only.
    public static func forLanguage(_ list: [GameMeta], _ lang: String) -> [GameMeta] {
        list.filter { $0.id != .emoji || lang == "en" }
    }

    public struct Settings: Equatable {
        public var enabled: Bool
        public var games: [GameId]
        public var offerText: String
    }

    /// The settings as the widget uses them, from whatever was stored.
    public static func settings(_ c: [String: Any]?) -> Settings {
        let w = c?["waitingGames"] as? [String: Any] ?? [:]
        var list: [GameId] = gameIds
        if let raw = w["games"] as? [Any] {
            list = []
            for g in raw {
                if let s = g as? String, let id = GameId(rawValue: s), !list.contains(id) { list.append(id) }
            }
        }
        var text = ""
        if let t = w["offerText"] as? String {
            text = String(WaitArticles.replace(t, "\\s+", " ").trimmingCharacters(in: .whitespaces).prefix(offerTextMax))
        }
        return Settings(enabled: (w["enabled"] as? Bool) != false && !list.isEmpty, games: list,
                        offerText: text.isEmpty ? defaultOfferText : text)
    }

    /// Typed while waiting, these open the games menu: "play", "games", "let's play", "play a game".
    public static let playPattern = "(?i)^\\s*(?:let'?s\\s+)?(?:play(?:\\s+a)?(?:\\s+game)?|games?|i\\s+want\\s+to\\s+play)\\s*[!.?]*\\s*$"

    public static func isPlay(_ text: String) -> Bool { WaitArticles.matches(text, playPattern) }

    // MARK: - The accent

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        let s = hex.trimmingCharacters(in: .whitespaces)
        guard WaitArticles.matches(s, "(?i)^#?([0-9a-f]{3}|[0-9a-f]{6})$") else { return nil }
        var h = s.hasPrefix("#") ? String(s.dropFirst()) : s
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard let n = Int(h, radix: 16) else { return nil }
        return (Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255))
    }

    /// Relative luminance (0 black .. 1 white), or nil for non-hex input (web nodeKit.ts).
    public static func luminance(_ hex: Any?) -> Double? {
        guard let s = hex as? String, let (r, g, b) = rgb(s) else { return nil }
        func lin(_ v: Double) -> Double {
            let c = v / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// The card's accent (web nodeKit.ts pickAccent): the header colour
    /// unless it is too pale to carry white text, then the bot bubble's, the
    /// visitor bubble's, the choice text's, then Conferbot blue.
    public static func pickAccent(_ c: [String: Any]?) -> String {
        for key in ["headerBgColor", "botMsgColor", "userMsgColor", "optionBubbleTextColor"] {
            if let v = c?[key] as? String, let l = luminance(v), l < 0.5 { return v }
        }
        return "#0808EE"
    }

    // MARK: - The offer

    /// The offer card comes this long after the waiting signal.
    public static let offerDelayMs: Double = 2500
    /// A card that could not be drawn is tried again this often, offerRetries times.
    public static let offerRetryMs: Double = 1500
    public static let offerRetries = 3
}

/// What the offer needs of the card on screen (GamesCard).
public protocol OfferCard: AnyObject {
    /// Still on screen.
    var up: Bool { get }
    /// A game is under way.
    var playing: Bool { get }
    /// Back to the menu.
    func menu()
    func remove()
    /// A teammate joined: save a game in progress, or step aside.
    func wrapUp(_ name: String)
}

/// The offer's rules (web wire.ts wireWaitingGames). Feed it the signals:
/// waiting() on cb:waiting-for-human, joined(name) on cb:human-joined,
/// waitOver() on cb:wait-over; play(text) before sending the visitor's
/// words; dismissed() when the card's "Not now" or x closes it. Main thread.
public final class GamesOffer {
    public enum Mode: String { case offer, menu }

    private let enabled: () -> Bool
    private let mount: (Mode) -> OfferCard?
    private let schedule: ConnectingSignal.Schedule
    private var waitingNow = false
    private var offered = false
    private var dismissedForSession = false
    private var card: OfferCard?
    private var timer: SignalTimer?

    /// `mount` draws a new card ("offer": the owner's line; "menu": the visitor asked), nil when it cannot.
    init(enabled: @escaping () -> Bool, mount: @escaping (Mode) -> OfferCard?,
         schedule: @escaping ConnectingSignal.Schedule = ConnectingSignal.mainQueueTimer) {
        self.enabled = enabled
        self.mount = mount
        self.schedule = schedule
    }

    private func cancel() {
        timer?.cancel()
        timer = nil
    }

    private func show(_ mode: Mode) -> Bool {
        guard enabled() else { return false }
        if let c = card, c.up, mode == .menu {
            // Mid-game, "play" brings the game back into view instead.
            if !c.playing { c.menu() }
            return true
        }
        card = mount(mode)
        return card != nil
    }

    public var isWaiting: Bool { waitingNow }

    /// cb:waiting-for-human: after offerDelayMs, one offer per wait.
    public func waiting() {
        guard !waitingNow else { return }
        waitingNow = true
        offered = false
        cancel()
        attempt(WaitingGames.offerRetries)
    }

    // The chat may still be drawing: a few more tries before giving up.
    private func attempt(_ left: Int) {
        let ms = left == WaitingGames.offerRetries ? WaitingGames.offerDelayMs : WaitingGames.offerRetryMs
        timer = schedule(ms / 1000) { [weak self] in
            guard let self = self else { return }
            self.timer = nil
            guard self.waitingNow, !self.offered, !self.dismissedForSession else { return }
            if let c = self.card, c.up { return }
            self.offered = self.show(.offer)
            if !self.offered && left > 0 { self.attempt(left - 1) }
        }
    }

    /// cb:wait-over: no more offers; an unused card leaves, a game being played stays.
    public func waitOver() {
        waitingNow = false
        cancel()
        if let c = card, c.up, !c.playing {
            c.remove()
            card = nil
        }
    }

    /// cb:human-joined: a game in progress is saved and folded away, an unused card leaves.
    public func joined(_ name: String?) {
        waitingNow = false
        cancel()
        if let c = card, c.up { c.wrapUp(name ?? "") }
    }

    /// The visitor's words while waiting: "play" opens the menu instead of
    /// being sent. True when it did (do not send them).
    public func play(_ text: String) -> Bool {
        guard waitingNow, WaitingGames.isPlay(text) else { return false }
        guard show(.menu) else { return false }
        dismissedForSession = false
        return true
    }

    /// The card's "Not now" or x: no more offers for this session.
    public func dismissed() {
        dismissedForSession = true
        card = nil
    }

    /// A new conversation: the wait is gone ("Not now" still holds, as on the web's page view).
    public func reset() {
        cancel()
        waitingNow = false
        offered = false
        card = nil
    }
}
