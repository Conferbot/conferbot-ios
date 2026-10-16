//
//  ReplyTime.swift
//  Conferbot
//
//  The chat header's status under the bot name: "Online", the team's reply
//  time, or when the team is back. Ported from the React Native SDK
//  (src/core/replyTime.ts), itself from the web widget: conferbot-widget
//  src/ts/chat/replyTime.ts (headerLine, backWhen, the English words from
//  ts/i18n/en.ts reply.*) and src/ts/chat/headerPresence.ts (a person in
//  the chat puts it back to a plain "Online").
//
//  The server works the reply time out (embed-server
//  liveChat/replyTimeService) and sends it with the bot data as
//  customizations.replyTime. The bot itself is always Online; the words say
//  when people answer. The header never changes to the agent. Also the
//  home screen's "Talk to us" line (homeLine, homePeople). Pure.
//

import Foundation

public enum ReplyTime {

    static let buckets = ["under_minute", "few_minutes", "under_15_minutes", "under_hour", "few_hours", "day", "few_days"]

    /// "The team typically replies <phrase>", per bucket, in the active
    /// language (web reply.phrase.*).
    public static var phrases: [String: String] {
        Dictionary(uniqueKeysWithValues: buckets.map { ($0, I18n.t("reply.phrase.\($0)")) })
    }

    private static func phraseFor(_ bucket: String?) -> String? {
        guard let b = bucket, buckets.contains(b) else { return nil }
        return I18n.t("reply.phrase.\(b)")
    }

    public static var statusOnline: String { I18n.t("status.online") }

    /// The widget's language and region for times (English writes en-US, as the web).
    static func defaultLocale(_ locale: Locale?) -> Locale {
        locale ?? (I18n.isEnglish ? Locale(identifier: "en_US") : I18n.locale)
    }
    static let sep = " \u{00B7} "

    private static func dateFormatter(_ template: String, _ locale: Locale, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale) ?? template
        return f
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// When the team is back, in the visitor's time: "at 9 AM" (today),
    /// "tomorrow 9 AM", "Monday 9:30 AM", "Mon, Oct 12 9 AM".
    public static func backWhen(_ backAt: String?, now: Date = Date(),
                                locale: Locale? = nil, timeZone: TimeZone = .current) -> String {
        guard let backAt = backAt, let d = parseISO(backAt) else { return "" }
        let locale = defaultLocale(locale)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let minutes = cal.component(.minute, from: d)
        // A plain space before AM / PM, as the browsers write it (newer ICU uses a narrow no-break space).
        let time = dateFormatter(minutes != 0 ? "jmm" : "j", locale, timeZone).string(from: d)
            .replacingOccurrences(of: "\u{202F}", with: " ")
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
        if days <= 0 { return I18n.t("reply.atTime", ["time": time]) }
        if days == 1 {
            // "morgen", "demain" (web: Intl.RelativeTimeFormat); English keeps the table's word.
            var tomorrow = I18n.t("reply.tomorrow")
            if !I18n.isEnglish {
                let rel = RelativeDateTimeFormatter()
                rel.locale = locale
                rel.dateTimeStyle = .named
                let word = rel.localizedString(from: DateComponents(day: 1))
                if !word.isEmpty { tomorrow = word }
            }
            return "\(tomorrow) \(time)"
        }
        if days < 7 { return "\(dateFormatter("EEEE", locale, timeZone).string(from: d)) \(time)" }
        return "\(dateFormatter("EEEMMMd", locale, timeZone).string(from: d)) \(time)"
    }

    /// The header's status from the server's reply time; nil keeps "Online".
    /// The bot stays Online when the team is away or offline ("Online · team
    /// back at 9 AM", "Online · team replies by email"). `agent`: an AI agent
    /// bot, which answers itself whatever the hour (no line).
    public static func headerLine(_ rt: [String: Any]?, agent: Bool = false, now: Date = Date(),
                                  locale: Locale? = nil, timeZone: TimeZone = .current) -> String? {
        guard let rt = rt, rt["mode"] as? String != "hide", rt["handover"] as? Bool == true, !agent else { return nil }
        let state = rt["state"] as? String
        if state == "away" || state == "offline" {
            let when = backWhen(rt["backAt"] as? String, now: now, locale: locale, timeZone: timeZone)
            let words = !when.isEmpty ? I18n.t("reply.teamBack", ["when": when])
                : rt["leaveMessage"] as? Bool == false ? I18n.t("reply.teamAwayNow") : I18n.t("reply.teamByEmail")
            return statusOnline + sep + words
        }
        if rt["mode"] as? String == "fixed",
           let fixed = (rt["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !fixed.isEmpty {
            return fixed
        }
        let phrase = phraseFor(rt["bucket"] as? String) ?? (rt["phrase"] as? String) ?? ""
        return phrase.isEmpty ? nil : I18n.t("reply.typicallyShort", ["phrase": phrase])
    }

    /// What the header shows under the bot name: the reply-time line, or
    /// plain "Online" once a person is in the chat (the snapshot about an
    /// away team is no longer true), or nothing when `hidden`.
    public static func headerStatus(_ rt: [String: Any]?, personInChat: Bool = false, agentBot: Bool = false, hidden: Bool = false,
                                    now: Date = Date(), locale: Locale? = nil, timeZone: TimeZone = .current) -> String? {
        if hidden { return nil }
        if personInChat { return statusOnline }
        return headerLine(rt, agent: agentBot, now: now, locale: locale, timeZone: timeZone) ?? statusOnline
    }
    // MARK: - The home card (web homeLine, homePeople)

    public enum Tone: String, Equatable { case online, away }

    /// A line and how it reads (online, or the team away).
    public struct Line: Equatable {
        public let text: String
        public let tone: Tone
        public init(_ text: String, _ tone: Tone) {
            self.text = text
            self.tone = tone
        }
    }

    /// The "Talk to us" card's line: a line, or `hide` (the owner chose Hide).
    public enum HomeLine: Equatable {
        case line(Line)
        case hide
    }

    private static func fixedOf(_ rt: [String: Any]) -> String {
        guard rt["mode"] as? String == "fixed", let t = rt["text"] as? String else { return "" }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func phraseOf(_ rt: [String: Any]) -> String {
        phraseFor(rt["bucket"] as? String) ?? (rt["phrase"] as? String) ?? ""
    }

    /// The "Talk to us" card's line (web replyTime.ts homeLine). `.hide`
    /// means take the line away (the owner chose Hide); nil keeps the old line.
    public static func homeLine(_ rt: [String: Any]?, agent: Bool = false, now: Date = Date(),
                                locale: Locale? = nil, timeZone: TimeZone = .current) -> HomeLine? {
        if let rt = rt, rt["mode"] as? String == "hide" { return agent ? nil : .hide }
        guard let rt = rt, rt["handover"] as? Bool == true else { return nil }
        let when = backWhen(rt["backAt"] as? String, now: now, locale: locale, timeZone: timeZone)
        let fixed = fixedOf(rt)
        let words = fixed.isEmpty ? phraseOf(rt) : fixed
        let state = rt["state"] as? String
        if agent {
            // The AI answers whatever the hour; say when people are around.
            let instantly = I18n.t("reply.answersInstantly")
            if state == "away" { return .line(Line(instantly + (when.isEmpty ? "" : sep + I18n.t("reply.teamBack", ["when": when])), .away)) }
            if state == "offline" || words.isEmpty { return nil }
            return .line(Line(instantly + sep + (fixed.isEmpty ? I18n.t("reply.teamReplies", ["phrase": words]) : fixed), .online))
        }
        if state == "away" { return .line(Line(I18n.t("reply.away") + (when.isEmpty ? "" : sep + I18n.t("reply.back", ["when": when])), .away)) }
        if state == "offline" {
            return .line(Line(rt["leaveMessage"] as? Bool != false ? I18n.t("reply.offline") + sep + I18n.t("reply.byEmail") : I18n.t("reply.offlineNow"), .away))
        }
        if !fixed.isEmpty { return .line(Line(fixed, .online)) }
        return words.isEmpty ? nil : .line(Line(I18n.t("reply.typically", ["phrase": words]), .online))
    }

    /// The home card's promise (web replyTime.ts homePeople), read after
    /// "Online" under the bot's name: an AI agent "Answers instantly, day or
    /// night" (or with when the team replies / is back); a bot that never
    /// hands over (or no data) the same; a team online "Usually replies in a
    /// few minutes" (or the owner's Fixed words); away or offline "Team back
    /// tomorrow 9 AM", else "Team replies by email" ("Team away right now"
    /// with leave-a-message off); Hide: no words ("").
    public static func homePeople(_ rt: [String: Any]?, agent: Bool = false, now: Date = Date(),
                                  locale: Locale? = nil, timeZone: TimeZone = .current) -> Line {
        let always = Line(I18n.t("reply.answersAlways"), .online)
        let line = homeLine(rt, agent: agent, now: now, locale: locale, timeZone: timeZone)
        if agent {
            if case .line(let l)? = line { return l }
            return always
        }
        if line == .hide { return Line("", .online) }
        guard let rt = rt, rt["handover"] as? Bool == true else { return always }
        let state = rt["state"] as? String
        if state == "away" || state == "offline" {
            let when = backWhen(rt["backAt"] as? String, now: now, locale: locale, timeZone: timeZone)
            let text = !when.isEmpty ? I18n.t("reply.teamBackAt", ["when": when])
                : rt["leaveMessage"] as? Bool == false ? I18n.t("reply.teamAwayRightNow") : I18n.t("reply.teamRepliesByEmail")
            return Line(text, .away)
        }
        let fixed = fixedOf(rt)
        if !fixed.isEmpty { return Line(fixed, .online) }
        let words = phraseOf(rt)
        return Line(words.isEmpty ? I18n.t("reply.usuallyInstantly") : I18n.t("reply.usually", ["phrase": words]), .online)
    }
    /// The usual wait, per bucket, in the active language (web reply.wait.*).
    public static var waits: [String: String] {
        Dictionary(uniqueKeysWithValues: buckets.map { ($0, I18n.t("reply.wait.\($0)")) })
    }

    private static func waitOf(_ bucket: String?, _ fallback: String?) -> String {
        if let b = bucket, buckets.contains(b) { return I18n.t("reply.wait.\(b)") }
        return fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// "Typical wait: a few minutes" for the wait card (web replyTime.ts
    /// typicalWait): the routed team's usual first reply (queue-status
    /// `typical`), else the workspace's (customizations.replyTime). nil when
    /// the owner chose Fixed or Hide, or there is no data.
    public static func typicalWait(_ rt: [String: Any]?, queueTypical: [String: Any]? = nil) -> String? {
        if let rt = rt, rt["mode"] as? String == "hide" || !fixedOf(rt).isEmpty { return nil }
        var w = waitOf(queueTypical?["bucket"] as? String, queueTypical?["wait"] as? String)
        if w.isEmpty, let rt = rt { w = waitOf(rt["bucket"] as? String, rt["wait"] as? String) }
        return w.isEmpty ? nil : I18n.t("reply.typicalWait", ["wait": w])
    }
}
