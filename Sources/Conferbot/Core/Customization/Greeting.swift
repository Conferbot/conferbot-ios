//
//  Greeting.swift
//  Conferbot
//
//  The greeting card by the closed launcher, as the web widget decides it
//  (conferbot-widget ts/visibility/nudges.ts greetingSettings / decideGreeting,
//  ts/visibility/greeting.ts, ts/home/firstImpression.ts upgradeGreeting,
//  ts/home/greetingStyle.ts): which message, after how long, what a tap
//  does, how often, and how it is dressed. Pure; the same as the React
//  Native SDK's core/greeting.ts.
//
//  An app has no page address, so it counts as the site's home page ("/"):
//  a rule for every page applies, a rule for a given page does not. Rules
//  that need what only a browser knows (where the visitor came from, pages
//  viewed, the visitor's country, page attributes) never apply here.
//

import Foundation

public struct ResolvedGreeting: Equatable {
    public var text: String
    /// Seconds after the launcher shows.
    public var delay: Int
    /// "open", "send" or "link".
    public var click: String
    public var linkUrl: String
    /// The rule's own suggested questions (the agent's are added by the caller).
    public var starters: [String]
    /// Results key: the rule's id or its words.
    public var key: String
}

public struct GreetingFacts {
    /// This visitor has been here before (a previous app session).
    public var returning: Bool
    /// The app identified the visitor (identify(user:)).
    public var signedIn: Bool
    /// App sessions so far, this one included (rules' "after N visits").
    public var visits: Int
    /// The visitor has chatted before.
    public var chatted: Bool
    /// Each rule's shows (ms) and last close, for its limits (nudges.ts limitsAllow).
    public var shows: [String: [Double]]
    public var dismissed: [String: Double]
    /// Now, in ms since 1970; nil for the clock.
    public var now: Double?

    public init(returning: Bool, signedIn: Bool, visits: Int = 1, chatted: Bool = false,
                shows: [String: [Double]] = [:], dismissed: [String: Double] = [:], now: Double? = nil) {
        self.returning = returning
        self.signedIn = signedIn
        self.visits = visits
        self.chatted = chatted
        self.shows = shows
        self.dismissed = dismissed
        self.now = now
    }
}

public struct GreetingSeen {
    /// When the card last showed (ms).
    public var shownAt: Double?
    /// When it was last closed or the chat opened from it (ms).
    public var closedAt: Double?
    /// Shown in this app session already.
    public var shownThisSession: Bool

    public init(shownAt: Double? = nil, closedAt: Double? = nil, shownThisSession: Bool = false) {
        self.shownAt = shownAt
        self.closedAt = closedAt
        self.shownThisSession = shownThisSession
    }
}

public struct GreetingHead: Equatable {
    public var avatar: String?
    public var name: String
    public var online: Bool
}

/// The launcher's colours for the phone text and the voice note: a solid or two gradient stops, the tail, the ink.
public struct GreetingBubble: Equatable {
    public var bg: [String]
    public var tail: String
    public var fg: String
}

public enum Greeting {
    public static let styles = ["card", "note", "imessage", "postcard", "sticky", "typewriter", "glass", "notification", "neon", "voice", "aurora"]
    public static let defaultStyle = "imessage"
    public static let defaultDelay = 3
    public static let defaultFrequencyDays = 7
    /// Closing the card (or opening the chat) rests it this long on "every page".
    public static let pageCooldownSeconds = 300.0
    static let textMax = 140
    static let legacyPromptDelay = 8
    static let dayMs = 86_400_000.0

    // The smart greetings' own ids (embed-server services/chatbot/greeting/smartGreetings.js).
    static let smartRuleIds: Set<String> = ["sgpric", "sgads0", "sgretn", "sgengd", "sgcust", "sgchko"]

    static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

    private static func str(_ v: Any?) -> String { v as? String ?? "" }
    private static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A JSON number (JSONSerialization hands booleans over as numbers too).
    private static func number(_ v: Any?) -> Double? {
        #if canImport(ObjectiveC)
        if let n = v as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() ? nil : n.doubleValue }
        #endif
        if v is Bool { return nil }
        return v as? Double ?? (v as? Int).map(Double.init)
    }

    private static func num(_ v: Any?, _ fallback: Int, _ lo: Int, _ hi: Int) -> Int {
        var n: Double?
        if let s = v as? String { n = s.isEmpty ? nil : Double(trim(s)) } else { n = number(v) }
        guard let d = n, d.isFinite else { return fallback }
        // JS Math.round: halves up.
        return min(max(Int((d + 0.5).rounded(.down)), lo), hi)
    }

    private static func obj(_ v: Any?) -> [String: Any]? { v as? [String: Any] }
    private static func list(_ v: Any?) -> [Any] { v as? [Any] ?? [] }

    public static func normalizeStyle(_ v: Any?) -> String {
        (v as? String).flatMap { styles.contains($0) ? $0 : nil } ?? defaultStyle
    }

    /// A rule's results key: its id, else its words.
    public static func ruleKey(_ rule: [String: Any]) -> String {
        let id = str(rule["id"])
        return id.isEmpty ? String(trim(str(rule["text"])).prefix(40)) : id
    }

    /// A rule's address pattern, asked of the app's "/" (nudges.ts ruleMatches).
    private static func matchesHome(_ rule: [String: Any]) -> Bool {
        if !list(rule["patterns"]).isEmpty { return false } // a smart greeting's detected pages
        let p = trim(str(rule["pattern"])).lowercased()
        if p.isEmpty { return false }
        switch str(rule["matchType"]) {
        case "glob": return ["*", "**", "/*", "/**"].contains(p)
        case "startsWith", "exact": return p == "/"
        default: return "/".contains(p)
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()
    private static let isoDay: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    /// Date.parse of an ISO date, in ms.
    private static func instant(_ v: Any?) -> Double? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        let d = isoFractional.date(from: s) ?? iso.date(from: s) ?? isoDay.date(from: s)
        return d.map { $0.timeIntervalSince1970 * 1000 }
    }

    private static func isUnset(_ v: Any?) -> Bool {
        if v == nil || v is NSNull { return true }
        if let n = number(v) { return n == 0 }
        if let a = v as? [Any] { return a.isEmpty }
        return false
    }

    /// Who and when (nudges.ts audienceMatches, scheduleMatches); what an app cannot know never matches.
    private static func applies(_ rule: [String: Any], _ facts: GreetingFacts) -> Bool {
        if !matchesHome(rule) { return false }
        let visitors = str(rule["visitors"]).isEmpty ? "all" : str(rule["visitors"])
        if visitors == "new" && facts.returning { return false }
        if visitors == "returning" && !facts.returning { return false }
        let signedIn = str(rule["signedIn"]).isEmpty ? "any" : str(rule["signedIn"])
        if signedIn == "yes" && !facts.signedIn { return false }
        if signedIn == "no" && facts.signedIn { return false }
        if !list(rule["countries"]).isEmpty { return false }
        let now = facts.now ?? nowMs()
        if let start = instant(rule["startsAt"]), now < start { return false }
        if let end = instant(rule["endsAt"]), now > end { return false }
        if let source = obj(rule["source"]), !source.isEmpty { return false }
        if let b = obj(rule["behavior"]) {
            // Pages, time and paths are a browser's; visits and "chatted" an app has.
            if b.contains(where: { $0.key != "minVisits" && $0.key != "chatted" && !isUnset($0.value) }) { return false }
            if let minVisits = number(b["minVisits"]), minVisits > 0, Double(max(1, facts.visits)) < minVisits { return false }
            if str(b["chatted"]) == "yes" && !facts.chatted { return false }
            if str(b["chatted"]) == "no" && facts.chatted { return false }
        }
        if !list(rule["attributes"]).isEmpty { return false }
        // Its own limits: at most N shows in a window, quiet for days after a close.
        if let l = obj(rule["limits"]) {
            let key = ruleKey(rule)
            if let maxShows = number(l["maxShows"]), maxShows > 0 {
                let windowDays = number(l["windowDays"]).flatMap { $0 > 0 ? $0 : nil } ?? Double(defaultFrequencyDays)
                let since = now - windowDays * dayMs
                if Double((facts.shows[key] ?? []).filter { $0 > since }.count) >= maxShows { return false }
            }
            if let quiet = number(l["quietDaysAfterDismiss"]), quiet > 0, let d = facts.dismissed[key], d > 0, now - d < quiet * dayMs { return false }
        }
        return true
    }

    private static func isSmart(_ rule: [String: Any]) -> Bool { smartRuleIds.contains(str(rule["id"])) }
    private static func isNone(_ rule: [String: Any]) -> Bool { str(obj(rule["action"])?["type"]) == "none" }
    private static func isTrue(_ v: Any?) -> Bool { (v as? Bool) == true }

    /// The greeting to show, or nil: the highest-priority rule that applies
    /// (a "show nothing" rule that applies silences it), else the default
    /// message when the greeting is on.
    public static func decide(_ c: [String: Any]?, facts: GreetingFacts) -> ResolvedGreeting? {
        let raw = c ?? [:]
        var on = isTrue(raw["chatIconCta"])
        // The stock "Hi👋, how can I help?" in the visitor's language; the owner's own words as written (web core/customizations.ts stockText).
        var text = I18n.stockText(trim(str(raw["chatIconCtaText"])), "greeting.stock", stockEnglish: ["Hi 👋, how can I help?"])
        var delay = num(raw["greetingDelay"], defaultDelay, 0, 3600)
        var click = ["send", "link"].contains(str(raw["greetingClickAction"])) ? str(raw["greetingClickAction"]) : "open"
        // Smart greetings with the owner's own greeting off: no default message.
        if isTrue(raw["smartOnly"]) && !on {
            on = true
            text = ""
        }
        var rules = list(raw["greetingRules"]).compactMap { obj($0) }
        // The old proactive teaser, carried over as the web does: its page rules
        // (never the app's "/"), and its every-page message as the default
        // message, or as a rule when the greeting already has one.
        let legacyText = isTrue(raw["proactivePromptEnabled"]) ? trim(str(raw["proactivePromptText"])) : ""
        let legacyRules = list(raw["proactivePromptRules"]).compactMap { obj($0) }
            .filter { !trim(str($0["text"])).isEmpty && !trim(str($0["urlPattern"])).isEmpty }
        if !legacyRules.isEmpty || !legacyText.isEmpty {
            if !on { text = "" }
            if !legacyText.isEmpty {
                let legacyDelay = num(raw["proactivePromptDelay"], legacyPromptDelay, 0, 3600)
                if !text.isEmpty {
                    rules.append(["matchType": "contains", "pattern": "/", "text": legacyText, "delay": legacyDelay, "clickAction": "send"])
                } else {
                    text = legacyText
                    delay = legacyDelay
                    click = "send"
                }
            }
            on = true
        }
        if !on { return nil }
        // "Show nothing" wins for the visitors it fits - a smart one yields to
        // the owner's own talking rule for the same visitor.
        let ownTalks = rules.contains { !isSmart($0) && !isNone($0) && !trim(str($0["text"])).isEmpty && applies($0, facts) }
        if rules.contains(where: { isNone($0) && applies($0, facts) && !(isSmart($0) && ownTalks) }) { return nil }
        let ranked = rules.enumerated()
            .map { (rule: $0.element, index: $0.offset, p: number($0.element["priority"]) ?? 50) }
            .sorted { $0.p != $1.p ? $0.p > $1.p : $0.index < $1.index }
        for item in ranked {
            let rule = item.rule
            let ruleText = trim(str(rule["text"]))
            if ruleText.isEmpty || isNone(rule) || !applies(rule, facts) { continue }
            let ruleClick = ["send", "open", "link"].contains(str(rule["clickAction"])) ? str(rule["clickAction"]) : click
            return ResolvedGreeting(
                text: String(ruleText.prefix(textMax)),
                delay: number(rule["delay"]) != nil ? num(rule["delay"], delay, 0, 3600) : delay,
                click: ruleClick,
                linkUrl: ruleClick == "link" ? str(rule["linkUrl"]) : "",
                starters: Array(list(rule["starters"]).compactMap { ($0 as? String).flatMap { trim($0).isEmpty ? nil : $0 } }.prefix(3)),
                key: ruleKey(rule)
            )
        }
        if text.isEmpty { return nil }
        return ResolvedGreeting(text: String(text.prefix(textMax)), delay: delay, click: click == "link" ? "open" : click,
                                linkUrl: "", starters: [], key: String(text.prefix(40)))
    }

    /// Whether the frequency lets the card show now (nudges.ts frequencyAllows).
    public static func frequencyAllows(_ c: [String: Any]?, seen: GreetingSeen, now: Double? = nil) -> Bool {
        let now = now ?? nowMs()
        let f = str(c?["greetingFrequency"])
        let days = Double(num(c?["greetingFrequencyDays"], defaultFrequencyDays, 1, 365))
        switch f {
        case "session": return !seen.shownThisSession
        case "visitor": return seen.shownAt.map { now - $0 >= days * dayMs } ?? true
        // Every page (each launch in an app): a close rests it a few minutes.
        default: return seen.closedAt.map { now - $0 >= pageCooldownSeconds * 1000 } ?? true
        }
    }

    /// The card's header: the agent or bot's avatar and name, and "Online" unless the owner hid it.
    public static func head(_ c: [String: Any]?, botName: String = "") -> GreetingHead {
        let x = c ?? [:]
        let avatar = [!isTrue(x["hideAvatar"]) ? str(x["avatar"]) : "", str(x["initialPageAvatar"]), !isTrue(x["hideLogo"]) ? str(x["logo"]) : ""]
            .first { !$0.isEmpty }
        let name = [str(x["logoText"]), botName].first { !$0.isEmpty } ?? I18n.t("home.support")
        return GreetingHead(avatar: avatar, name: name, online: !isTrue(x["hideOnlineStatus"]))
    }

    // MARK: Colours

    private static func channel(_ v: Double) -> Double {
        let s = v / 255
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }

    private static func luminance(_ c: WidgetTheme.RGBA) -> Double {
        0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    private static func hex(_ c: WidgetTheme.RGBA) -> String {
        "#" + [c.r, c.g, c.b].map { String(format: "%02x", Int(min(255, max(0, $0.rounded())))) }.joined()
    }

    private static func gradientStops(_ c: [String: Any]) -> (String, String)? {
        let one = str(c["widgetGradientBgOne"]), two = str(c["widgetGradientBgTwo"])
        return str(c["widgetIconThemeType"]) == "Gradient" && !one.isEmpty && !two.isEmpty ? (one, two) : nil
    }

    /// The card's accent (firstImpression.ts accentFor): the first bot colour that is not too light.
    public static func accent(_ c: [String: Any]?) -> String {
        let x = c ?? [:]
        // A widget theme's palette stands in for the owner's brand colour (brand.ts
        // brandColorOf; WidgetTheme.withThemePalette marks it with themeAccent).
        let themed = x["_themePalette"] != nil || x["themeAccent"] != nil
        let brand = [!themed ? str(x["brandColor"]) : "", str(x["headerBgColor"])].first { !$0.isEmpty } ?? "#1b55f3"
        let launcher = gradientStops(x).map { [$0.0, $0.1] } ?? [[str(x["widgetIconBgColor"]), str(x["headerBgColor"])].first { !$0.isEmpty } ?? "#4f46e5"]
        for v in [brand, str(x["headerBgColor"])] + launcher {
            if let rgb = WidgetTheme.parseColor(v), luminance(rgb) <= 0.55 { return hex(rgb) }
        }
        return "#4f46e5"
    }

    /// The launcher's colours for the phone text and the voice note (greetingStyle.ts).
    public static func bubble(_ c: [String: Any]?) -> GreetingBubble {
        let x = c ?? [:]
        let gradient = gradientStops(x)
        let solid = WidgetTheme.parseColor(gradient?.0 ?? x["widgetIconBgColor"]).map(hex) ?? "#1b55f3"
        let fg = WidgetTheme.parseColor(solid).map { luminance($0) > 0.6 } == true ? "#111827" : "#ffffff"
        if let g = gradient { return GreetingBubble(bg: [g.0, g.1], tail: g.1, fg: fg) }
        return GreetingBubble(bg: [solid], tail: solid, fg: fg)
    }

    /// The bot's own font for the card, or nil for the system font (Arial and Gill Sans read as the default).
    public static func font(_ c: [String: Any]?) -> String? {
        let f = trim(str(c?["font"]))
        let lower = f.lowercased()
        return f.isEmpty || lower.hasPrefix("arial") || lower.hasPrefix("gill sans") ? nil : f
    }

    // MARK: Style details (polish-home.css, greetingStyle.ts)

    /// The card's width per style.
    public static func width(_ style: String) -> Double {
        switch style {
        case "imessage": return 270
        case "sticky": return 250
        case "notification": return 300
        case "voice": return 280
        default: return 296
        }
    }

    /// The voice note's 22 bar heights, % of 26: 30 + round(70 * |sin(1.7i) * cos(0.45i)|).
    public static let voiceBars: [Double] = (0..<22).map { (i: Int) -> Double in
        let x = Double(i)
        let wave: Double = abs(sin(1.7 * x) * cos(0.45 * x))
        return 30 + (70 * wave + 0.5).rounded(.down)
    }

    /// The voice note's length, "0:SS": words / 2.4 seconds, 2 to 59.
    public static func voiceDuration(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let secs = min(59, max(2, Int((Double(words) / 2.4 + 0.5).rounded(.down))))
        return String(format: "0:%02d", secs)
    }

    /// The typewriter's pause after a character, ms: 34 + up to 30, or 204 after . , ! ?
    public static func typeDelay(after ch: Character, random: () -> Double = { Double.random(in: 0..<1) }) -> Double {
        ".,!?".contains(ch) ? 204 : 34 + random() * 30
    }
}
