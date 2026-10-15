//
//  GreetingState.swift
//  Conferbot
//
//  The greeting card's memory, as the web widget keeps it
//  (conferbot-widget ts/visibility/greeting.ts; the React Native SDK's
//  components/FloatingWidget/useGreeting.ts): visits, whether the visitor
//  chatted, each rule's shows and dismissals, and when the card last
//  showed and was closed. Stored per bot in UserDefaults under
//  "conferbot.greeting.<botId>"; a visit counts once per app session. The
//  floating widget drives the clock and the delay.
//

import Foundation

/// What the greeting card shows (Greeting dressed for this bot).
public struct GreetingCardData: Equatable {
    public var style: String
    public var text: String
    public var head: GreetingHead
    public var starters: [String]
    public var bubble: GreetingBubble
    public var accent: String
    public var font: String?
    /// The phone text's typing moment plays once per app session.
    public var firstShow: Bool
    public var click: String
    public var linkUrl: String
    /// The card's motion (mascotMotion): "lively" (unset), "subtle" or "off".
    public var motion: String
}

public final class GreetingStore {
    /// What is kept per bot, as RN keeps it: {visits, chatted, shows, dismissed, closedAt, shownAt, last}.
    public struct Stored: Codable, Equatable {
        public var visits = 0
        public var chatted = false
        public var shows: [String: [Double]] = [:]
        public var dismissed: [String: Double] = [:]
        public var shownAt: Double?
        public var closedAt: Double?
        public var last: String?

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            visits = (try? c.decode(Int.self, forKey: .visits)) ?? 0
            chatted = (try? c.decode(Bool.self, forKey: .chatted)) ?? false
            shows = (try? c.decode([String: [Double]].self, forKey: .shows)) ?? [:]
            dismissed = (try? c.decode([String: Double].self, forKey: .dismissed)) ?? [:]
            shownAt = try? c.decode(Double.self, forKey: .shownAt)
            closedAt = try? c.decode(Double.self, forKey: .closedAt)
            last = try? c.decode(String.self, forKey: .last)
        }
    }

    /// Seen in this app session (the "session" frequency, the phone text's typing moment).
    struct SessionSeen {
        var shownThisSession = false
        var typed = false
        var counted = false
    }

    private static var session: [String: SessionSeen] = [:]
    private static let sessionLock = NSLock()
    /// A show is remembered this long against its rule's limits.
    static let showsKeptMs = 90 * Greeting.dayMs

    public let botId: String
    private let defaults: UserDefaults
    public private(set) var stored: Stored

    public static func key(_ botId: String) -> String { "conferbot.greeting.\(botId.isEmpty ? "default" : botId)" }

    public init(botId: String, defaults: UserDefaults = .standard) {
        self.botId = botId
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.key(botId)), let data = raw.data(using: .utf8),
           let st = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = st
        } else {
            stored = Stored()
        }
    }

    private var seen: SessionSeen {
        get { Self.sessionLock.lock(); defer { Self.sessionLock.unlock() }; return Self.session[botId] ?? SessionSeen() }
        set { Self.sessionLock.lock(); Self.session[botId] = newValue; Self.sessionLock.unlock() }
    }

    /// Forgets this app session (tests).
    static func resetSession() {
        sessionLock.lock(); session = [:]; sessionLock.unlock()
    }

    private func write(_ st: Stored) {
        stored = st
        if let data = try? JSONEncoder().encode(st), let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: Self.key(botId))
        }
    }

    /// Signed in: the visitor context (identify(user:)) has an id or an email.
    public static func signedIn(_ ctx: [String: Any]?) -> Bool {
        guard let ctx = ctx else { return false }
        func has(_ k: String) -> Bool {
            if let s = ctx[k] as? String { return !s.isEmpty }
            return ctx[k] != nil && !(ctx[k] is NSNull)
        }
        return has("id") || has("email")
    }

    /// A new visit, once per app session.
    public func countVisit() {
        var s = seen
        guard !s.counted else { return }
        s.counted = true
        seen = s
        var st = stored
        st.visits += 1
        write(st)
    }

    /// The greeting to show now, if any: the rules for this visitor, then the frequency.
    public func decide(_ c: [String: Any], signedIn: Bool, now: Double? = nil) -> ResolvedGreeting? {
        let st = stored
        let facts = GreetingFacts(returning: st.visits > 1, signedIn: signedIn, visits: max(1, st.visits), chatted: st.chatted,
                                  shows: st.shows, dismissed: st.dismissed, now: now)
        guard let g = Greeting.decide(c, facts: facts) else { return nil }
        let allowed = Greeting.frequencyAllows(c, seen: GreetingSeen(shownAt: st.shownAt, closedAt: st.closedAt, shownThisSession: seen.shownThisSession), now: now)
        return allowed ? g : nil
    }

    /// One show: counted against its rule's limits, and the card dressed.
    public func show(_ c: [String: Any], _ g: ResolvedGreeting, agentBot: AgentBot?, now: Double? = nil) -> GreetingCardData {
        let now = now ?? Greeting.nowMs()
        var s = seen
        s.shownThisSession = true
        var st = stored
        st.shows[g.key] = Array(((st.shows[g.key] ?? []).filter { now - $0 < Self.showsKeptMs } + [now]).suffix(20))
        st.shownAt = now
        st.last = g.key
        write(st)
        var head = Greeting.head(c)
        if let name = agentBot?.displayName, !name.isEmpty { head.name = name }
        let card = GreetingCardData(
            style: Greeting.normalizeStyle(c["greetingStyle"]),
            text: g.text,
            head: head,
            starters: Array((g.starters.isEmpty ? agentBot?.starters ?? [] : g.starters).prefix(3)),
            bubble: Greeting.bubble(c),
            accent: Greeting.accent(c),
            font: Greeting.font(c),
            firstShow: !s.typed,
            click: g.click,
            linkUrl: g.linkUrl,
            motion: ["subtle", "off"].contains(c["mascotMotion"] as? String ?? "") ? (c["mascotMotion"] as? String ?? "") : "lively"
        )
        s.typed = true
        seen = s
        return card
    }

    /// Closed with its X: rests for a while, and its rule counts as dismissed.
    public func dismiss(now: Double? = nil) {
        let now = now ?? Greeting.nowMs()
        var st = stored
        st.closedAt = now
        if let last = st.last { st.dismissed[last] = now }
        write(st)
    }

    /// Used (tapped): rests for a while like a close, but is not a dismissal of its rule.
    public func closeForNow(now: Double? = nil) {
        var st = stored
        st.closedAt = now ?? Greeting.nowMs()
        write(st)
    }

    /// The chat opened: the visitor chatted (for rules that ask), and a card on show rests as if closed.
    public func chatOpened(showing: Bool, now: Double? = nil) {
        var st = stored
        st.chatted = true
        if showing { st.closedAt = now ?? Greeting.nowMs() }
        write(st)
    }
}
