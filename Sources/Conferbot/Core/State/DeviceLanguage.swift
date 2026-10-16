//
//  DeviceLanguage.swift
//  Conferbot
//
//  The visitor's language, sent with every response record as the web
//  widget's `visitorInsights.language.browser` (navigator.language,
//  conferbot-widget ts/visitors/insights.ts). The server reads it
//  (embed-server socket/handlers/messageHandler.js, `browserLanguage`) so the
//  AI answers a message too short to tell ("ok", "hi") in the visitor's own
//  language. An app has no page, so `language.page` and the browsing history
//  the web also sends are never set. Ported from the React Native SDK's
//  src/core/deviceLanguage.ts.
//

import Foundation

public enum DeviceLanguage {

    // The web's own cut: whitespace collapsed, trimmed, at most n characters.
    private static func cut(_ v: String?, _ n: Int) -> String {
        let collapsed = (v ?? "").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return String(collapsed.prefix(n))
    }

    /// A locale as the browser writes it: BCP 47 ("en-US"), not the
    /// platform's "en_US" or "en_US@calendar=..." / "en-US-u-ca-...".
    public static func normalize(_ raw: String?) -> String {
        var s = cut(raw, 64)
        if let at = s.firstIndex(of: "@") { s = String(s[..<at]) }
        s = s.replacingOccurrences(of: "_", with: "-")
        guard s.range(of: "^[A-Za-z]{2,3}(-|$)", options: .regularExpression) != nil else { return "" }
        if let ext = s.range(of: "-u-", options: .caseInsensitive), ext.lowerBound > s.startIndex {
            s = String(s[..<ext.lowerBound])
        }
        return cut(s, 16)
    }

    /// The first of the candidates that is a language ("" when none is).
    public static func localeOf(preferred: [String], current: String?) -> String {
        for candidate in [preferred.first, current] {
            let locale = normalize(candidate)
            if !locale.isEmpty { return locale }
        }
        return ""
    }

    /// The response record's `visitorInsights`: the web's snapshot shape with
    /// only the language. nil when the language is unknown.
    public static func visitorInsights(_ locale: String) -> [String: Any]? {
        let browser = cut(locale, 16)
        return browser.isEmpty ? nil : ["v": 1, "language": ["browser": browser]]
    }

    private static let lock = NSLock()
    private static var cached: String?

    /// The phone's preferred language ("de-DE"), read once per app run.
    public static var current: String {
        lock.lock()
        defer { lock.unlock() }
        if let c = cached { return c }
        let read = localeOf(preferred: Locale.preferredLanguages, current: Locale.current.identifier)
        cached = read
        return read
    }

    /// Tests: read the phone again.
    static func reset() {
        lock.lock()
        cached = nil
        lock.unlock()
    }
}
