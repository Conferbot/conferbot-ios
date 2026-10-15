//
//  Redact.swift
//  Conferbot
//
//  Sensitive details visitors type, masked before anything is stored or
//  sent: payment cards (Luhn), bank accounts (IBAN, mod-97), government ids,
//  passwords and one-time codes said in a sentence, secret keys. Emails and
//  phone numbers are never masked.
//
//  A port of the web widget's conferbot-widget/src/ts/chat/privacy/redact.ts
//  and privacy/index.ts (maskRecordEntry, maskValue), through the React
//  Native SDK (src/core/privacy/redact.ts). The web applies it to the answer
//  variables and to the visitor's own record entries; the transcript keeps
//  what was typed. Owners switch it off with customizations.redactSensitive
//  === false. The embed server runs the same rules as a backstop - keep the
//  three in step.
//

import Foundation

public enum Redact {

    static func luhnOk(_ digits: String) -> Bool {
        var sum = 0
        var double = false
        for ch in digits.reversed() {
            guard var d = ch.wholeNumberValue else { return false }
            if double {
                d *= 2
                if d > 9 { d -= 9 }
            }
            sum += d
            double.toggle()
        }
        return sum % 10 == 0
    }

    static func ibanOk(_ raw: String) -> Bool {
        let s = raw.replacing("\\s+", with: "").uppercased()
        guard s.matches("^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$") else { return false }
        let moved = String(s.dropFirst(4)) + String(s.prefix(4))
        var rem = 0
        for ch in moved {
            let v = ch.isLetter ? String(Int(ch.asciiValue ?? 0) - 55) : String(ch)
            for c in v { rem = (rem * 10 + (c.wholeNumberValue ?? 0)) % 97 }
        }
        return rem == 1
    }

    private struct Rule {
        let kind: String
        let re: Re
        let test: ((String) -> Bool)?
        let label: ([String?]) -> String
    }

    private static let rules: [Rule] = [
        // Payment cards: 13-19 digits, optionally in groups, passing Luhn.
        Rule(kind: "card", re: Re("\\b(?:[0-9][ -]?){12,18}[0-9]\\b"), test: { m in
            let d = m.replacing("[^0-9]", with: "")
            return d.count >= 13 && d.count <= 19 && luhnOk(d) && !d.matches("^([0-9])\\1+$")
        }, label: { g in "[card •••• \(String((g[0] ?? "").replacing("[^0-9]", with: "").suffix(4)))]" }),
        // Bank accounts (IBAN), with or without spaces.
        Rule(kind: "iban", re: Re("\\b[A-Z]{2}[0-9]{2}(?:[ ]?[A-Z0-9]{4}){2,7}(?:[ ]?[A-Z0-9]{1,4})?\\b", [.caseInsensitive]),
             test: { ibanOk($0) }, label: { _ in "[bank account hidden]" }),
        // CVV / security code said with its name.
        Rule(kind: "cvv", re: Re("\\b(cvv2?|cvc2?|security code)\\s*(?:is|:|=|-)?\\s*[0-9]{3,4}\\b", [.caseInsensitive]),
             test: nil, label: { g in "\(g[1] ?? "") [hidden]" }),
        // Passwords and PINs said in a sentence: "my password is hunter2".
        Rule(kind: "password", re: Re("\\b(password|passcode|passwd|pwd|pin)\\b(\\s*(?:is|was|:|=|-)\\s*)(\"[^\"]{3,64}\"|'[^']{3,64}'|\\S{2,63}[^\\s.,;:!?)])", [.caseInsensitive]),
             test: nil, label: { g in "\(g[1] ?? "")\(g[2] ?? "")[hidden]" }),
        // One-time codes said in a sentence: "the code is 482913".
        Rule(kind: "code", re: Re("\\b((?:verification|one[- ]time|otp|2fa|login|security)\\s+code|otp)\\b(\\s*(?:is|:|=|-)?\\s*)([0-9]{4,8})\\b", [.caseInsensitive]),
             test: nil, label: { g in "\(g[1] ?? "")\(g[2] ?? "")[hidden]" }),
        // US social security number.
        Rule(kind: "id", re: Re("\\b(?!000|666|9[0-9][0-9])[0-9]{3}-(?!00)[0-9]{2}-(?!0000)[0-9]{4}\\b"), test: nil, label: { _ in "[id hidden]" }),
        // UAE Emirates ID: 784-YYYY-NNNNNNN-N.
        Rule(kind: "id", re: Re("\\b784[- ]?[0-9]{4}[- ]?[0-9]{7}[- ]?[0-9]\\b"), test: nil, label: { _ in "[id hidden]" }),
        // India Aadhaar: 12 digits in groups of 4 (first digit 2-9).
        Rule(kind: "id", re: Re("\\b[2-9][0-9]{3}[ -][0-9]{4}[ -][0-9]{4}\\b"), test: nil, label: { _ in "[id hidden]" }),
        // Secret keys and tokens people paste by mistake.
        Rule(kind: "secret", re: Re("\\b(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{16,}\\b|\\bsk-[A-Za-z0-9_-]{20,}\\b|\\bAKIA[0-9A-Z]{16}\\b|\\bgh[pousr]_[A-Za-z0-9]{30,}\\b|\\bxox[abprs]-[A-Za-z0-9-]{10,}\\b"),
             test: nil, label: { _ in "[secret key hidden]" }),
    ]

    /// Email addresses are left whole: digits in one are not a card number.
    private static let emailSplit = Re("([A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,})")

    private static func maskPart(_ part: String, _ found: inout [String]) -> String {
        var out = part
        for rule in rules {
            var hits: [String] = []
            out = rule.re.replace(out) { g in
                let m = g[0] ?? ""
                if let test = rule.test, !test(m) { return m }
                hits.append(rule.kind)
                return rule.label(g)
            }
            found += hits
        }
        return out
    }

    /// Mask what is sensitive in `text`: the masked text and the kinds masked.
    public static func redactText(_ text: String) -> (text: String, found: [String]) {
        if text.isEmpty { return (text, []) }
        var found: [String] = []
        var out = ""
        var last = text.startIndex
        for m in emailSplit.re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            out += maskPart(String(text[last..<r.lowerBound]), &found)
            out += text[r]
            last = r.upperBound
        }
        out += maskPart(String(text[last...]), &found)
        var unique: [String] = []
        for f in found where !unique.contains(f) { unique.append(f) }
        return (out, unique)
    }

    private static let textFields = ["text", "message", "userInput", "value", "display", "answer"]

    private static func isVisitorEntry(_ entry: [String: Any]) -> Bool {
        let s = JS.text(entry["shape"])
        return (s.isEmpty ? JS.text(entry["type"]) : s).hasPrefix("user-")
    }

    /// The visitor's own record entry with its text fields masked; other entries untouched.
    public static func maskRecordEntry(_ entry: [String: Any]) -> [String: Any] {
        guard isVisitorEntry(entry) else { return entry }
        var e = entry
        var found: [String] = []
        for f in textFields {
            guard let s = e[f] as? String else { continue }
            let r = redactText(s)
            if !r.found.isEmpty {
                e[f] = r.text
                found += r.found
            }
        }
        if !found.isEmpty {
            var all = (e["redacted"] as? [String]) ?? []
            for f in found where !all.contains(f) { all.append(f) }
            e["redacted"] = all
        }
        return e
    }

    /// A value saved from an answer, masked when it is a string.
    public static func maskValue(_ value: Any?) -> Any? {
        guard let s = value as? String else { return value }
        return redactText(s).text
    }
}
