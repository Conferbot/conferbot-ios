//
//  Home.swift
//  Conferbot
//
//  The home screen: what the visitor sees when the chat opens, before they
//  have said anything, and the shortest path from there to an answer.
//  Ported from the React Native SDK (src/core/home.ts), itself from the web
//  widget (all under conferbot-widget/src/):
//
//    ts/home/firstImpression.ts  enhanceHome, buildHelpCard: what shows and in what order
//    ts/home/homeCopy.ts          honest words for early bots' placeholder copy
//    ts/home/homeUtils.ts         salutation, topCategories, isLight, homeBrand, homeCardAvatar
//    ts/home/askBox.ts            "Ask anything": askBoxOn, askPlaceholder, the list as rows
//    ts/home/trust.ts             the team's faces, the rating, the customer logos
//    ts/home/visitorMemory.ts     "Welcome back, Jamie", "Pick up where you left off"
//    ts/home/requests/card.ts     "Your requests" on the home screen
//    ts/chat/replyTimeView.ts     decorateHomeReply: the card's status line
//    core/helpCentre.ts           showsRecentArticles, publishedArticles
//    templates/shared.ts          generateInitialPage: the template the above decorate
//    ts/i18n/en.ts                home.*, trust.*, requests.* (English)
//
//  The home exists only when the owner turned it on (`enableInitialPage`);
//  with it off the chat opens straight on the conversation.
//
//  Not in an app, on purpose: the page-aware parts (ts/home/pageAware.ts -
//  "For this page" articles and a greeting page rule's own questions; an app
//  has no page address or title, so the agent's own questions are used), the
//  help card's own search's "For this page", and the floating panel's
//  three-article cap (wider than 500px only). The web's home draws no
//  mascot (it appears on the launcher, the greeting card, the typing bubble
//  and the idle call); `Model.mascot` is the owner's, for an app that draws
//  it on its own home (`HomeScreenView(mascot:)`, `MascotView`).
//
//  Pure: everything the view needs comes out of `Home.model`.
//

import Foundation

/// The open chat's views.
public enum HomeView: String, Equatable {
    case home, chat, help
}

public enum Home {

    // MARK: - Words (web ts/i18n/en.ts)

    public enum Text {
        public static let title = "Hi there 👋"
        public static let description = "Ask us anything - we're here to help."
        public static let onlineNow = "Online now"
        public static let support = "Support"
        public static let chatWithUs = "Chat with us"
        public static let ourAssistant = "Our assistant"
        public static let resume = "Pick up where you left off"
        public static let continueConversation = "Continue the conversation"
        public static let askAgain = "Ask it again - we'll answer right away"
        public static let helpCentre = "Help centre"
        public static let recentArticles = "Recent articles"
        public static let seeAll = "See all"
        public static let searchPlaceholder = "Search for help"
        public static let searchLabel = "Search help articles"
        public static func noMatch(_ q: String) -> String { "No articles match \u{201C}\(q)\u{201D}." }
        public static let askInstead = "Ask us instead"
        public static let chatInstead = "Chat with us instead"
        public static let askPlaceholder = "Ask a question\u{2026}"
        public static func askLabel(_ name: String) -> String { "Ask \(name) a question" }
        /// "Ask “<query>”": the query is drawn bold.
        public static let askQuery = "Ask"
        public static func answersRightAway(_ name: String) -> String { "\(name) answers right away" }
        public static let wellHelp = "We'll help you with it"
        public static let articles = "Articles"
        public static let goodMorning = "Good morning"
        public static let goodAfternoon = "Good afternoon"
        public static let goodEvening = "Good evening"
        public static let hello = "Hello"
        public static func welcomeBackName(_ name: String) -> String { "Welcome back, \(name)" }
        public static let welcomeBack = "Welcome back"
        public static let requestsTitle = "Your requests"
        public static func requestsSeeAll(_ n: Int) -> String { "See all (\(n))" }
        public static let review = "review"
        public static let reviews = "reviews"
        public static func rated(_ avg: String, _ count: Int, _ reviews: String) -> String { "Rated \(avg) out of 5 from \(count) \(reviews)" }
        public static let ourTeam = "Our team"
        public static let customerLogo = "Customer logo"
        public static let close = "Close"
        public static let back = "Back"
    }

    // MARK: - Small helpers

    /// JS truthiness for a setting.
    static func truthy(_ v: Any?) -> Bool {
        guard let v = v, !(v is NSNull) else { return false }
        if let s = v as? String { return !s.isEmpty }
        if let n = v as? NSNumber { return n.doubleValue != 0 && !n.doubleValue.isNaN }
        return true
    }

    static func str(_ v: Any?) -> String { (v as? String) ?? "" }
    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func idOf(_ v: Any?) -> String {
        guard let v = v, !(v is NSNull) else { return "" }
        if let s = v as? String { return s }
        return "\(v)"
    }

    static func matches(_ s: String, _ pattern: String, _ options: NSRegularExpression.Options = []) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    // MARK: - On or off

    /// Is there a home screen at all? The web's templates draw it when
    /// `enableInitialPage` is truthy, and the panel opens on it.
    public static func homeOn(_ c: [String: Any]?) -> Bool { truthy(c?["enableInitialPage"]) }

    /// A view that cannot be shown falls back (web core/helpCentre.ts safeView).
    public static func safeView(_ c: [String: Any]?, _ view: HomeView?) -> HomeView {
        let home = homeOn(c)
        switch view {
        case .help?: return WaitArticles.helpCentreOn(c) ? .help : home ? .home : .chat
        case .home?: return home ? .home : .chat
        case .chat?: return .chat
        case nil: return home ? .home : .chat
        }
    }

    // MARK: - The help centre's articles

    /// Drafts never show (web core/helpCentre.ts publishedArticles).
    public static func publishedArticles(_ list: [[String: Any]]?) -> [[String: Any]] {
        (list ?? []).filter { a in
            guard truthy(a["_id"]) else { return false }
            let status = a["reviewStatus"]
            return status == nil || status is NSNull || (status as? String) == "published"
        }
    }

    static func publishedCategories(_ categories: [[String: Any]]?) -> [[String: Any]] {
        (categories ?? []).map { c in
            guard let list = c["articles"] as? [[String: Any]] else { return c }
            var out = c
            out["articles"] = publishedArticles(list)
            return out
        }
    }

    /// The help centre counts as on: the owner's switch, and at least one
    /// published article (a help centre with no published articles is a
    /// blank screen and counts as off).
    public static func helpOn(_ c: [String: Any]?, _ categories: [[String: Any]]?, _ recent: [[String: Any]]?) -> Bool {
        guard WaitArticles.helpCentreOn(c) else { return false }
        let inCategories = publishedCategories(categories).contains { !(($0["articles"] as? [[String: Any]]) ?? []).isEmpty }
        return inCategories || !publishedArticles(recent).isEmpty
    }

    /// The home screen's Recent articles list (web core/helpCentre.ts showsRecentArticles).
    public static func showsRecentArticles(_ c: [String: Any]?, _ articles: [[String: Any]]?) -> Bool {
        guard let c = c else { return false }
        return c["enableInitialPage"] as? Bool == true && WaitArticles.helpCentreOn(c)
            && c["hideRecentArticles"] as? Bool != true && !publishedArticles(articles).isEmpty
    }

    /// The categories worth a shortcut: named, not empty, most articles first (ties keep order).
    public static func topCategories(_ categories: [[String: Any]], max: Int = 4) -> [[String: Any]] {
        struct Ranked { let c: [String: Any]; let i: Int; let n: Int }
        var ranked: [Ranked] = []
        for (i, c) in categories.enumerated() {
            let n = ((c["articles"] as? [Any]) ?? []).count
            if n > 0 && !trim(str(c["name"])).isEmpty { ranked.append(Ranked(c: c, i: i, n: n)) }
        }
        ranked.sort { a, b in a.n != b.n ? a.n > b.n : a.i < b.i }
        return ranked.prefix(max).map { $0.c }
    }

    // MARK: - The header

    /// "Good morning" / "Good afternoon" / "Good evening" by the visitor's clock.
    public static func salutation(_ hour: Double) -> String {
        let h = hour.isFinite ? ((Int(hour.rounded(.down)) % 24) + 24) % 24 : 12
        if h >= 5 && h < 12 { return Text.goodMorning }
        if h >= 12 && h < 18 { return Text.goodAfternoon }
        if h >= 18 && h < 23 { return Text.goodEvening }
        return Text.hello
    }

    public struct Brand: Equatable {
        public let logo: String
        public let name: String
    }

    /// Who the home screen is from: the logo and name the chat header shows.
    /// nil when the owner hid the logo or there is no usable image.
    public static func brand(_ c: [String: Any]?, fallbackName: String = "") -> Brand? {
        guard let c = c, !truthy(c["hideLogo"]) else { return nil }
        let logo = trim(str(c["logo"]))
        guard !logo.isEmpty, matches(logo, "^(https?:|data:image/|blob:|/)", .caseInsensitive) else { return nil }
        let own = trim(str(c["logoText"]))
        return Brand(logo: logo, name: collapse(own.isEmpty ? fallbackName : own))
    }

    static let conferbotFace = "https://prd.media.cdn.conferbot.com/62829a1c49f355163dfdbfb2/conferbot-logo-1710782074234.png"

    private static func ownImage(_ v: Any?) -> String {
        let s = trim(str(v))
        return !s.isEmpty && !matches(s, "conferbot-logo", .caseInsensitive) ? s : ""
    }

    /// The card's face when the owner set none: the bot's avatar, then its logo, then Conferbot's.
    public static func cardAvatar(_ c: [String: Any]?) -> String {
        let own = trim(str(c?["initialPageAvatar"]))
        if !own.isEmpty { return own }
        if !truthy(c?["hideAvatar"]), !ownImage(c?["avatar"]).isEmpty { return ownImage(c?["avatar"]) }
        if !truthy(c?["hideLogo"]), !ownImage(c?["logo"]).isEmpty { return ownImage(c?["logo"]) }
        return conferbotFace
    }

    // MARK: - Honest words (web homeCopy.ts)

    private static func norm(_ v: Any?) -> String { collapse(str(v)).lowercased() }
    private static let legacyTitles = ["our usual reply time", "our usual reply time is"]
    private static let legacyTaglines = ["later today", "a few hours", "within a day"]
    private static func isLegacyDescription(_ v: Any?) -> Bool {
        let n = norm(v)
        return n.isEmpty || n.hasPrefix("welcome to the conferbot") || n == "we help your business to connect with your customer"
    }

    public struct Copy: Equatable {
        /// Who answers: the owner's card title, else the bot's (or agent's) name.
        public let cardTitle: String
        public let cardTagline: String
        public let description: String
        /// Whether the tagline is ours (so the status line replaces it).
        public let online: Bool
    }

    public static func copy(_ c: [String: Any]?, name: String) -> Copy {
        let title = norm(c?["initialPageCardSubTitle"])
        let tagline = norm(c?["initialPageCardTagline"])
        let ownTagline = !tagline.isEmpty && !legacyTaglines.contains(tagline)
        return Copy(
            cardTitle: title.isEmpty || legacyTitles.contains(title) ? (name.isEmpty ? Text.support : name) : trim(str(c?["initialPageCardSubTitle"])),
            cardTagline: ownTagline ? trim(str(c?["initialPageCardTagline"])) : Text.onlineNow,
            description: isLegacyDescription(c?["initialPageDescription"]) ? Text.description : str(c?["initialPageDescription"]),
            online: !ownTagline
        )
    }

    static func plainText(_ v: String) -> String {
        collapse(v.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression))
    }

    /// The owner's words, or the stock ones (web i18n.ts ownerTextOr).
    static func ownerTextOr(_ value: Any?, _ stock: String) -> String {
        let v = (value as? String).map(plainText) ?? ""
        return v.isEmpty || v == plainText(stock) ? stock : str(value)
    }

    // MARK: - Colours

    /// "#abc", "#aabbcc" or "rgb(a, b, c)" as [r, g, b]; nil for anything else.
    public static func parseColor(_ value: String) -> [Int]? {
        let s = trim(value)
        if let re = try? NSRegularExpression(pattern: "^#?([0-9a-f]{3}|[0-9a-f]{6})$", options: .caseInsensitive),
           let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: 1), in: s) {
            var hex = String(s[r])
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            let n = Int(hex, radix: 16) ?? 0
            return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
        }
        if let re = try? NSRegularExpression(pattern: "^rgba?\\(\\s*(\\d+)[,\\s]+(\\d+)[,\\s]+(\\d+)", options: .caseInsensitive),
           let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
            return (1...3).map { i in Range(m.range(at: i), in: s).flatMap { Int(s[$0]) } ?? 0 }
        }
        return nil
    }

    /// True when white text would not read on this colour (relative luminance above ~0.55).
    public static func isLight(_ rgb: [Int]?) -> Bool {
        guard let rgb = rgb, rgb.count == 3 else { return false }
        func lin(_ ch: Int) -> Double {
            let s = Double(ch) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2]) > 0.55
    }

    /// The band's two colours: the launcher's gradient, else its solid colour (firstImpression.ts brandColors).
    public static func brandColors(_ c: [String: Any]?) -> (String, String) {
        if str(c?["widgetIconThemeType"]) == "Gradient", truthy(c?["widgetGradientBgOne"]), truthy(c?["widgetGradientBgTwo"]) {
            return (str(c?["widgetGradientBgOne"]), str(c?["widgetGradientBgTwo"]))
        }
        let solid = [c?["widgetIconBgColor"], c?["headerBgColor"]].map(str).first { !$0.isEmpty } ?? "#4f46e5"
        return (solid, solid)
    }

    /// The home screen's surfaces: the widget theme's canvas, cards, quiet
    /// fills and text (bg2 is "home screen, help centre"), else the classic
    /// widget's (web polish.css / polish-home.css).
    public struct Palette: Equatable {
        public let page: String
        public let card: String
        public let soft: String
        public let ink: String
        public let muted: String
        public let line: String
    }

    public static let classicPalette = Palette(page: "#f6f7fb", card: "#ffffff", soft: "#f1f5f9", ink: "#0f172a", muted: "#64748b", line: "#f1f5f9")

    public static func palette(_ tokens: ThemeTokens?) -> Palette {
        guard let t = tokens, !t.bg2.isEmpty, !t.card.isEmpty, !t.ink.isEmpty else { return classicPalette }
        let soft = t.card2.isEmpty ? t.bg2 : t.card2
        return Palette(page: t.bg2, card: t.card, soft: soft, ink: t.ink, muted: t.muted.isEmpty ? t.ink : t.muted,
                       line: t.line.isEmpty ? soft : t.line)
    }

    // MARK: - Trust (web trust.ts)

    /// The owner's images, https only, once each, at most `max`.
    public static func trustImages(_ list: Any?, max: Int) -> [String] {
        var out: [String] = []
        for v in (list as? [Any]) ?? [] {
            let url = trim((v as? String) ?? "")
            guard matches(url, "^https://[^\\s\"'<>]+$", .caseInsensitive), !out.contains(url) else { continue }
            out.append(url)
        }
        return Array(out.prefix(max))
    }

    /// A count as people say it: 120, 1.2k, 12k.
    public static func compactCount(_ n: Double) -> String {
        let v = Swift.max(0, n.isFinite ? n.rounded(.down) : 0)
        if v < 1000 { return String(Int(v)) }
        let k = v / 1000
        if k < 10 {
            let t = (k * 10).rounded(.down) / 10
            return t == t.rounded() ? "\(Int(t))k" : "\(t)k"
        }
        return "\(Int(k.rounded(.down)))k"
    }

    public struct Rating: Equatable {
        public let average: String
        public let count: String
        /// How far the stars fill, 0-100.
        public let fill: Double
        public let label: String
    }

    private static func number(_ v: Any?) -> Double {
        if let s = v as? String { return Double(s) ?? .nan }
        if let n = v as? NSNumber { return n.doubleValue }
        return .nan
    }

    /// The rating to show (the server's average of real post-chat scores), or nil.
    public static func ratingLine(_ r: Any?) -> Rating? {
        let d = r as? [String: Any]
        let average = number(d?["average"])
        let rawCount = number(d?["count"])
        guard average.isFinite, average >= 1, average <= 5, rawCount.isFinite, rawCount.rounded(.down) >= 1 else { return nil }
        let count = Int(rawCount.rounded(.down))
        let avg = String(format: "%.1f", average)
        let many = count == 1 ? Text.review : Text.reviews
        return Rating(
            average: avg,
            count: "\(compactCount(Double(count))) \(many)",
            // The stars fill to the average shown, so they agree with the number.
            fill: ((Double(avg) ?? 0) / 5 * 1000).rounded() / 10,
            label: Text.rated(avg, count, many)
        )
    }

    // MARK: - Visitor memory (web visitorMemory.ts)

    /// Per bot, on the device only (web localStorage `cb_mem_<botId>`), in UserDefaults.
    public static func memoryKey(_ botId: String) -> String { "conferbot_home_\(botId.isEmpty ? "default" : botId)" }
    static let forgetAfterMs: Double = 60 * 24 * 60 * 60 * 1000
    /// The web restores a live chat this long after its last message (BOT_STATE_EXPIRY).
    public static let liveChatMs: Double = 30 * 60 * 1000

    public struct Memory: Equatable {
        public var name: String?
        /// The first real question of their latest conversation.
        public var topic: String?
        /// The conversation that question came from.
        public var session: String?
        /// Last time they wrote (ms).
        public var at: Double

        public init(name: String? = nil, topic: String? = nil, session: String? = nil, at: Double) {
            self.name = name
            self.topic = topic
            self.session = session
            self.at = at
        }
    }

    /// What the device remembers, or nil (none, broken, or older than 60 days).
    public static func parseMemory(_ raw: String?, now: Double = Date().timeIntervalSince1970 * 1000) -> Memory? {
        guard let data = (raw ?? "null").data(using: .utf8),
              let m = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any],
              let atNumber = m["at"] as? NSNumber, CFGetTypeID(atNumber) != CFBooleanGetTypeID() else { return nil }
        let at = atNumber.doubleValue
        guard now - at <= forgetAfterMs else { return nil }
        return Memory(
            name: (m["name"] as? String).map { String($0.prefix(40)) },
            topic: (m["topic"] as? String).map { String($0.prefix(160)) },
            session: m["session"] as? String,
            at: at
        )
    }

    public static func serializeMemory(_ m: Memory) -> String {
        var d: [String: Any] = ["at": m.at]
        d["name"] = m.name
        d["topic"] = m.topic
        d["session"] = m.session
        guard let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) else { return "null" }
        return String(data: data, encoding: .utf8) ?? "null"
    }

    private static func fresh(_ m: Memory?, _ now: Double) -> Memory? {
        guard let m = m, now - m.at <= forgetAfterMs else { return nil }
        return m
    }

    /// They wrote `text` in conversation `session` (web rememberMessage).
    public static func withMessage(_ m: Memory?, session: String?, text: String, now: Double = Date().timeIntervalSince1970 * 1000) -> Memory {
        var next = fresh(m, now) ?? Memory(at: now)
        next.at = now
        // A new conversation's first real question becomes what they came for.
        if let session = session, !session.isEmpty, next.session != session, WaitArticles.isRealQuestion(text) {
            next.topic = String(collapse(text).prefix(160))
            next.session = session
        }
        return next
    }

    /// They told us their name (web rememberName): a first name, or nil when it is not one.
    public static func withName(_ m: Memory?, name: String, now: Double = Date().timeIntervalSince1970 * 1000) -> Memory? {
        let first = trim(name).split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        guard !first.isEmpty, first.count <= 40, !matches(first, "[@\\d<>]") else { return nil }
        var next = fresh(m, now) ?? Memory(at: now)
        next.name = first.prefix(1).uppercased() + first.dropFirst()
        return next
    }

    /// "Welcome back[, Name]" once their last chat is over (not while the
    /// web would still restore it), and the question to pick up. nil for a first visit.
    public static func welcomeBack(_ m: Memory?, now: Double = Date().timeIntervalSince1970 * 1000) -> (hello: String, topic: String?)? {
        guard let m = m, now - m.at >= liveChatMs else { return nil }
        let topic = (m.topic ?? "").isEmpty ? nil : m.topic
        let name = (m.name ?? "").isEmpty ? nil : m.name
        guard topic != nil || name != nil else { return nil }
        return (name.map(Text.welcomeBackName) ?? Text.welcomeBack, topic)
    }

    /// The remembered conversation is the one on the device, so the card can open it (web canResume).
    public static func canResume(_ m: Memory?, chatSessionId: String?) -> Bool {
        guard let s = m?.session, !s.isEmpty, let id = chatSessionId, !id.isEmpty else { return false }
        return s == id
    }

    // MARK: - "Ask anything" (web askBox.ts)

    /// Whether the box shows at all: the owner's switch (on unless off), and an agent or an article to find.
    public static func askBoxOn(_ c: [String: Any]?, hasAgent: Bool, hasArticles: Bool) -> Bool {
        c?["homeAskBox"] as? Bool != false && (hasAgent || hasArticles)
    }

    /// The box's words: a question for an agent, a search for articles alone.
    public static func askPlaceholder(hasAgent: Bool, hasArticles: Bool) -> String {
        hasAgent ? Text.askPlaceholder : hasArticles ? Text.searchPlaceholder : ""
    }

    /// A run of text, marked where it matches the question (web kbUtils.ts highlight).
    public struct TextRun: Equatable {
        public let text: String
        public let mark: Bool
        public init(_ text: String, mark: Bool = false) {
            self.text = text
            self.mark = mark
        }
    }

    public static func highlightRuns(_ text: String, _ tokens: [String]) -> [TextRun] {
        let words = tokens.filter { !$0.isEmpty }.enumerated()
            .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .map { NSRegularExpression.escapedPattern(for: $0.element) }
        guard !words.isEmpty, !text.isEmpty,
              let re = try? NSRegularExpression(pattern: "(\(words.joined(separator: "|")))", options: .caseInsensitive) else { return [TextRun(text)] }
        let ns = text as NSString
        var out: [TextRun] = []
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.range.length > 0 {
            if m.range.location > last { out.append(TextRun(ns.substring(with: NSRange(location: last, length: m.range.location - last)))) }
            out.append(TextRun(ns.substring(with: m.range), mark: true))
            last = m.range.location + m.range.length
        }
        if last < ns.length { out.append(TextRun(ns.substring(from: last))) }
        return out
    }

    public enum AskRow: Equatable {
        /// Ask the agent this question: the chat opens and asks.
        case ask(query: String, sub: String)
        case label(String)
        case article(id: String, title: [TextRun], sub: String)
        case none(String)
        /// A flow bot with nothing found: open the chat.
        case chat(title: String, sub: String)

        public var key: String {
            switch self {
            case .ask: return "ask"
            case .label: return "label"
            case .article(let id, _, _): return "a-\(id)"
            case .none: return "none"
            case .chat: return "chat"
            }
        }

        /// The row does something when tapped (Enter picks the first one).
        public var acts: Bool {
            switch self {
            case .ask, .article, .chat: return true
            case .label, .none: return false
            }
        }
    }

    /// A match inside article text from the server.
    public struct RemoteHit: Equatable {
        public let id: String
        public let snippet: String
        public init(id: String, snippet: String) {
            self.id = id
            self.snippet = snippet
        }
    }

    /// The server's matches for the query they were asked for (lowercased).
    public struct RemoteHits: Equatable {
        public let query: String
        public let hits: [RemoteHit]
        public init(query: String, hits: [RemoteHit]) {
            self.query = query
            self.hits = hits
        }
    }

    /// The list under the box as the visitor types (web askBox.ts render):
    /// for an agent first "Ask “...”"; the articles that answer it (best
    /// first, at most 4, the server's body matches after the local ones); for
    /// a flow bot with nothing found, "No articles match" and "Chat with us".
    /// Empty while the box is empty.
    public static func askRows(_ query: String, agentName: String?, articles: [WaitArticles.HelpArticle], remote: RemoteHits? = nil) -> [AskRow] {
        let q = trim(query)
        guard !q.isEmpty else { return [] }
        let words = WaitArticles.keywordsOf(q)
        let tokens = words.isEmpty ? WaitArticles.tokenize(q) : words
        var found = WaitArticles.answersFor(articles, q, max: 4)
        if let remote = remote, remote.query == q.lowercased() {
            var byId: [String: WaitArticles.HelpArticle] = [:]
            for a in articles where byId[a.id] == nil { byId[a.id] = a }
            let extra = remote.hits.filter { h in byId[h.id] != nil && !found.contains { $0.id == h.id } }
            for h in extra.prefix(Swift.max(0, 4 - found.count)) {
                var a = byId[h.id]!
                a.description = h.snippet
                found.append(a)
            }
        }
        var rows: [AskRow] = []
        if let name = agentName { rows.append(.ask(query: q, sub: Text.answersRightAway(name))) }
        if !found.isEmpty {
            rows.append(.label(Text.articles))
            for a in found {
                rows.append(.article(id: a.id, title: highlightRuns(a.title, tokens), sub: a.description.isEmpty ? a.categoryName : a.description))
            }
        } else if agentName == nil {
            rows.append(.none(Text.noMatch(q)))
            rows.append(.chat(title: Text.chatWithUs, sub: Text.wellHelp))
        }
        return rows
    }

    /// What Enter does: the first row that does something.
    public static func askDefault(_ rows: [AskRow]) -> AskRow? { rows.first { $0.acts } }

    /// What to ask the server for matches inside article bodies (web
    /// askBox.ts askRemote): the question's two longest key words, or nil
    /// when there is nothing to ask or no article lacks its body.
    public static func remoteQueryFor(_ query: String, articles: [[String: Any]]) -> String? {
        guard articles.contains(where: { !($0["content"] is String) }) else { return nil }
        let words = WaitArticles.keywordsOf(trim(query))
        guard !words.isEmpty else { return nil }
        let key = words.enumerated()
            .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .prefix(2).map { $0.element }.joined(separator: " ")
        return key.count < 2 ? nil : key
    }

    public struct HelpResultRow: Equatable {
        public let id: String
        public let title: [TextRun]
        public let sub: String
    }

    /// The help card's own search, when the ask box is off (web buildHelpCard render).
    public enum HelpSearch: Equatable {
        case results([HelpResultRow])
        case empty(text: String, action: String, asks: Bool)
    }

    public static func helpSearch(_ query: String, articles: [WaitArticles.HelpArticle], hasAgent: Bool) -> HelpSearch? {
        let q = trim(query)
        guard !q.isEmpty else { return nil }
        let tokens = WaitArticles.tokenize(q)
        let found = WaitArticles.searchArticles(articles, q).prefix(5)
        if !found.isEmpty {
            return .results(found.map { HelpResultRow(id: $0.id, title: highlightRuns($0.title, tokens), sub: $0.categoryName.isEmpty ? $0.description : $0.categoryName) })
        }
        return .empty(text: Text.noMatch(q), action: hasAgent ? Text.askInstead : Text.chatInstead, asks: hasAgent)
    }

    // MARK: - The model

    /// The bot's AI agent (a no-flow agent bot).
    public struct Agent: Equatable {
        public var displayName: String
        public var starters: [String]
        public var avatar: String?

        public init(displayName: String, starters: [String] = [], avatar: String? = nil) {
            self.displayName = displayName
            self.starters = starters
            self.avatar = avatar
        }
    }

    public struct Input {
        /// The bot's settings (themed and personalised, as the chat uses them).
        public var c: [String: Any]?
        public var botName: String?
        public var agent: Agent?
        public var categories: [[String: Any]]
        public var recentArticles: [[String: Any]]
        public var memory: Memory?
        /// The conversation on the device.
        public var chatSessionId: String?
        /// The visitor's requests (nil until read) and when each was last read here.
        public var requests: [RequestSummary]?
        public var seen: [String: Double]
        public var now: Double
        /// The visitor's hour (0-23), for the salutation; nil reads the clock.
        public var hour: Double?

        public init(c: [String: Any]?, botName: String? = nil, agent: Agent? = nil, categories: [[String: Any]] = [],
                    recentArticles: [[String: Any]] = [], memory: Memory? = nil, chatSessionId: String? = nil,
                    requests: [RequestSummary]? = nil, seen: [String: Double] = [:],
                    now: Double = Date().timeIntervalSince1970 * 1000, hour: Double? = nil) {
            self.c = c
            self.botName = botName
            self.agent = agent
            self.categories = categories
            self.recentArticles = recentArticles
            self.memory = memory
            self.chatSessionId = chatSessionId
            self.requests = requests
            self.seen = seen
            self.now = now
            self.hour = hour
        }
    }

    public struct ArticleRow: Equatable {
        public let id: String
        public let title: String
        public let description: String
        /// The cover image, when it has one (else the document icon).
        public let image: String?
    }

    public struct RequestRow: Equatable {
        public let id: String
        public let title: String
        public let line: String
        public let state: RequestState
        public let fresh: Bool
    }

    public enum Section: String, Equatable {
        case ask, resume, requests, talk, help, trust
    }

    public struct Talk: Equatable {
        public let avatar: String
        public let title: String
        /// The owner's own tagline (kept), else nil (the status line takes its place).
        public let tagline: String?
        /// "Online · Usually replies in a few minutes"; nil when there is nothing to say.
        public let status: String?
        public let tone: ReplyTime.Tone
        /// The green dot on the avatar (off with hideOnlineStatus).
        public let dot: Bool
        public let button: String
        /// An AI agent's suggested questions: one tap opens the chat and asks.
        public let starters: [String]
        /// The team's photos, a small stack at the end of the name row.
        public let faces: [String]
        public let rating: Rating?
    }

    public struct Ask: Equatable {
        public let placeholder: String
        public let label: String
        public let agentName: String?
    }

    public struct Resume: Equatable {
        public let topic: String
        public let resumable: Bool
        public let line: String
    }

    public struct RequestsCard: Equatable {
        public let rows: [RequestRow]
        public let total: Int
        public let seeAll: String?
        public let fresh: Bool
    }

    public struct Topic: Equatable {
        public let id: String
        public let name: String
        public let count: Int
    }

    public struct Help: Equatable {
        public let title: String
        public let recent: [ArticleRow]
        public let seeAll: Bool
        public let topics: [Topic]
        /// The card's own search (only when the ask box is not there).
        public let search: Bool
    }

    public struct Trust: Equatable {
        public let label: String
        public let logos: [String]
    }

    /// What the home screen shows.
    public struct Model: Equatable {
        /// "Good afternoon", or "Welcome back, Jamie".
        public let hello: String
        public let brand: Brand?
        /// The owner's title (may be empty, as the web prints it).
        public let title: String
        public let description: String
        /// The owner's line above the card (initialPageMessage), or "".
        public let message: String
        /// The band behind the top: the launcher's colours; light means dark ink on it.
        public let band: [String]
        public let light: Bool
        /// Chips, links and the ask box's ring (web --cb-accent).
        public let accent: String
        public let talk: Talk
        public let ask: Ask?
        public let resume: Resume?
        public let requests: RequestsCard?
        public let help: Help?
        public let trust: Trust?
        /// The cards from the top down.
        public let order: [Section]
        /// Every article the ask box and the help card search.
        public let articles: [WaitArticles.HelpArticle]
        /// The owner's mascot (art3d mascotLookOf) and its colour, for an app that draws it on its home; the web's home has none.
        public let mascot: Mascot
    }

    /// The owner's mascot and the colour it is drawn in when the owner chose none (the launcher's).
    public struct Mascot: Equatable {
        public let look: MascotArt.Look
        public let accent: String

        public init(look: MascotArt.Look, accent: String) {
            self.look = look
            self.accent = accent
        }
    }

    private static func truncate(_ v: Any?, _ max: Int) -> String {
        let s = v.map { $0 is NSNull ? "" : (($0 as? String) ?? "\($0)") } ?? ""
        return s.count > max ? String(s.prefix(max)) + "..." : s
    }

    /// What the home screen shows, from the owner's settings and what the
    /// device knows; nil while the owner has no home screen.
    public static func model(_ input: Input) -> Model? {
        let c = input.c ?? [:]
        guard homeOn(c) else { return nil }
        let now = input.now
        let agent = input.agent
        let categories = publishedCategories(input.categories)
        let recent = publishedArticles(input.recentArticles)
        let kbOn = helpOn(c, categories, recent)
        let logoText = str(c["logoText"])
        let name = [agent?.displayName ?? "", logoText, input.botName ?? ""].first { !$0.isEmpty } ?? ""

        // The header: salutation (or welcome back), the brand, the owner's words.
        let back = welcomeBack(input.memory, now: now)
        let words = copy(c, name: name)
        let (a, b) = brandColors(c)

        // "Talk to us": the status line replaces our own tagline (replyTimeView.ts decorateHomeReply).
        let hideStatus = c["hideOnlineStatus"] as? Bool == true
        let people = ReplyTime.homePeople(c["replyTime"] as? [String: Any], agent: agent != nil, now: Date(timeIntervalSince1970: now / 1000))
        let statusText = [hideStatus ? "" : ReplyTime.statusOnline, people.text].filter { !$0.isEmpty }.joined(separator: ReplyTime.sep)
        let talk = Talk(
            avatar: cardAvatar(c),
            title: words.cardTitle,
            tagline: words.online ? nil : words.cardTagline,
            status: statusText.isEmpty ? nil : statusText,
            tone: people.tone,
            dot: !hideStatus,
            button: ownerTextOr(c["initialPageCardButtonText"], Text.chatWithUs),
            starters: agent.map { Array($0.starters.filter { !trim($0).isEmpty }.prefix(3)) } ?? [],
            faces: trustImages(c["homeTeamPhotos"], max: 3),
            rating: ratingLine(c["homeRating"])
        )

        // Search first.
        let articles = kbOn ? WaitArticles.flattenArticles(categories, recent) : []
        let agentName: String? = agent.map { ag in [ag.displayName, logoText, input.botName ?? ""].first { !$0.isEmpty } ?? Text.ourAssistant }
        let ask: Ask? = askBoxOn(c, hasAgent: agent != nil, hasArticles: !articles.isEmpty)
            ? Ask(placeholder: askPlaceholder(hasAgent: agent != nil, hasArticles: !articles.isEmpty),
                  label: agentName.map(Text.askLabel) ?? Text.searchLabel, agentName: agentName)
            : nil

        // Pick up where they left off: an agent bot only.
        let resumable = canResume(input.memory, chatSessionId: input.chatSessionId)
        let resume: Resume? = back?.topic.flatMap { topic in
            agent == nil ? nil : Resume(topic: topic, resumable: resumable, line: resumable ? Text.continueConversation : Text.askAgain)
        }

        // Their requests: up to two, "See all (n)" when there are more; a new reply puts it above "Talk to us".
        let seen = input.seen
        let list = Requests.ordered(input.requests ?? [], seen: seen)
        let requests: RequestsCard? = list.isEmpty ? nil : RequestsCard(
            rows: list.prefix(Requests.onHome).map {
                RequestRow(id: $0.id, title: $0.title, line: Requests.rowLine($0, seen: seen, now: now),
                           state: Requests.stateOf($0), fresh: Requests.isNewReply($0, seen: seen))
            },
            total: list.count,
            seeAll: list.count > Requests.onHome ? Text.requestsSeeAll(list.count) : nil,
            fresh: list.contains { Requests.isNewReply($0, seen: seen) }
        )

        // The help card: the recent list (unless hidden), the topics, See all.
        var help: Help?
        if kbOn {
            let topics = topCategories(categories, max: 6)
            let withList = showsRecentArticles(c, recent)
            if !articles.isEmpty || !topics.isEmpty {
                help = Help(
                    title: withList ? Text.recentArticles : Text.helpCentre,
                    recent: withList ? recent.map { r in
                        let cover = trim(str(r["coverImage"]))
                        return ArticleRow(id: idOf(r["_id"]), title: truncate(r["title"], 100), description: truncate(r["description"], 120),
                                          image: cover.isEmpty ? nil : cover)
                    } : [],
                    seeAll: !topics.isEmpty,
                    topics: topics.map { t in
                        let id = [idOf(t["_id"]), idOf(t["id"]), str(t["name"])].first { !$0.isEmpty } ?? ""
                        return Topic(id: id, name: str(t["name"]), count: ((t["articles"] as? [Any]) ?? []).count)
                    },
                    search: ask == nil
                )
            }
        }

        // The owner's customer logos with their line, last.
        let logos = trustImages(c["homeTrustLogos"], max: 6)
        let trust: Trust? = logos.isEmpty ? nil : Trust(label: trim(str(c["homeTrustLabel"])), logos: logos)

        var order: [Section] = []
        if ask != nil { order.append(.ask) }
        if resume != nil { order.append(.resume) }
        if requests?.fresh == true { order.append(.requests) }
        order.append(.talk)
        if let r = requests, !r.fresh { order.append(.requests) }
        if help != nil { order.append(.help) }
        if trust != nil { order.append(.trust) }

        let hour = input.hour ?? Double(Calendar.current.component(.hour, from: Date(timeIntervalSince1970: now / 1000)))
        return Model(
            hello: back?.hello ?? salutation(hour),
            brand: brand(c, fallbackName: [agent?.displayName ?? "", input.botName ?? ""].first { !$0.isEmpty } ?? ""),
            title: trim(str(c["initialPageTitle"])),
            description: words.description,
            message: (c["initialPageMessage"] as? String).map(plainText) ?? "",
            band: [a, b],
            light: isLight(parseColor(a)) && isLight(parseColor(b)),
            accent: Requests.accent(c),
            talk: talk,
            ask: ask,
            resume: resume,
            requests: requests,
            help: help,
            trust: trust,
            order: order,
            articles: articles,
            mascot: Mascot(look: MascotArt.lookOf(c), accent: [str(c["widgetIconBgColor"]), str(c["headerBgColor"])].map(trim).first { !$0.isEmpty } ?? "#4f46e5")
        )
    }

    /// While the visitor types in the ask box, the list is the page: these go (web cb-home--asking).
    public static let hiddenWhileAsking: [Section] = [.resume, .requests, .talk, .help]
}
