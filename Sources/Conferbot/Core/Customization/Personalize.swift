//
//  Personalize.swift
//  Conferbot
//
//  Personalised texts: "Hi {{first_name|there}} 👋" -> "Hi Sam 👋" (or
//  "Hi there 👋"). Ported from the React Native SDK (src/core/personalize.ts),
//  itself from the web widget: conferbot-widget src/ts/layout/ownerLayout.ts
//  (visitorVars, personalize, PERSONALIZED_KEYS, personalizeCustomizations),
//  applied in index.ts right after the bot's data arrives. This is the
//  dashboard's "Greet by name" (Customize > Welcome).
//
//  One difference, on purpose: the web HTML-escapes the values because it
//  draws these texts as markup; the SDK draws them as text, so they stay as
//  typed. Pure.
//

import Foundation

public enum Personalize {

    private static func firstString(_ values: [Any?]) -> String {
        for v in values {
            if let s = v as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return ""
    }

    /// What a visitor is known by: the app's user (`identify(user:)`: its
    /// name and metadata, as the web's identify data) and a name the chat
    /// already asked for.
    public static func visitorVars(_ context: [String: Any]?, name: Any? = nil) -> [String: String] {
        let c = context ?? [:]
        let parts = [c["firstName"] ?? c["first_name"], c["lastName"] ?? c["last_name"]]
            .compactMap { $0 as? String }.filter { !$0.isEmpty }
        let full = firstString([c["name"], c["fullName"], c["full_name"], name, parts.joined(separator: " ")])
        let firstWord = full.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return [
            "name": full,
            "first_name": firstString([c["firstName"], c["first_name"], firstWord]),
            "company": firstString([c["company"], c["companyName"], c["company_name"], c["organization"]]),
        ]
    }

    private static let token = try! NSRegularExpression(pattern: "\\{\\{\\s*([a-z_]+)\\s*(?:\\|([^}]*))?\\}\\}", options: [.caseInsensitive])
    private static let dropped = try! NSRegularExpression(pattern: "[ \\t]*\\u0000")
    private static let spaces = try! NSRegularExpression(pattern: "[ \\t]{2,}")

    /// Fill the tokens. A token with no value and no fallback is dropped
    /// along with the space before it ("Hi {{name}}!" -> "Hi!"); the fallback
    /// is the owner's own text.
    public static func personalize(_ text: String, _ vars: [String: String]) -> String {
        guard text.contains("{{") else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in token.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            var key = ns.substring(with: m.range(at: 1)).lowercased()
            if key == "firstname" { key = "first_name" }
            if let v = vars[key], !v.isEmpty {
                out += v
            } else if m.range(at: 2).location != NSNotFound {
                out += ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                out += "\u{0}"
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        out = dropped.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "")
        return spaces.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: " ")
    }

    /// The visitor-facing texts that take {{name}} / {{first_name}} / {{company}}.
    public static let keys = ["chatIconCtaText", "initialPageTitle", "initialPageDescription", "initialPageCardButtonText"]

    /// The bot's settings with those texts (and each greeting rule's text) filled in.
    public static func customizations(_ c: [String: Any]?, _ vars: [String: String]) -> [String: Any]? {
        guard var out = c else { return nil }
        for k in keys {
            if let s = out[k] as? String { out[k] = personalize(s, vars) }
        }
        if let rules = out["greetingRules"] as? [Any] {
            out["greetingRules"] = rules.map { r -> Any in
                guard var d = r as? [String: Any], let text = d["text"] as? String, text.contains("{{") else { return r }
                d["text"] = personalize(text, vars)
                return d
            }
        }
        return out
    }
}
