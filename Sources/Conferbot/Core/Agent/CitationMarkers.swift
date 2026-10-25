//
//  CitationMarkers.swift
//  Conferbot
//
//  Placeholder citation markers in AI answers, as embed-server
//  utils/citationMarkers.js stripPlaceholderMarkers.
//
//  The server strips markers from new answers, but answers saved before that
//  can come back in restored history with an echoed placeholder ("[n]",
//  "[N]", "[1, n]") or a label ("[source]", "[web:2]"). Conservative on
//  purpose: a bracket goes only when every part is a number or one of the
//  placeholder words, and at least one part is not a plain number ("[2]"
//  could be the author's own). "[Klik hier]", a markdown link "[n](url)" and
//  a task-list "- [x]" stay as written.
//

import Foundation

public enum CitationMarkers {
    // Words a model writes in place of (or in front of) a passage number.
    private static let words = [
        "n", "x", "k", "#", "nr", "no", "num", "number",
        "source", "sources", "citation", "citations", "cite", "ref", "refs", "reference", "references",
        "passage", "passages", "knowledge", "kb", "faq", "context", "doc", "docs", "website", "web",
        "instruction", "instructions",
    ].map { $0.replacingOccurrences(of: "#", with: "\\#") }.joined(separator: "|")

    // One part of a marker: "2", "n", "source", "source 2", "web:2", "passage n".
    private static let part = "(?:\\d+|(?:\(words))(?:[ \\t]*[#:\\-]?[ \\t]*(?:\\d+|n))?)"

    // A whole marker, with the one space before it. Not a markdown link ("[n](url)").
    private static let marker = try! NSRegularExpression(
        pattern: "[ \\t]?\\[[ \\t]*\(part)(?:[ \\t]*[,;][ \\t]*\(part))*[ \\t]*\\](?!\\()",
        options: [.caseInsensitive]
    )
    private static let numeric = try! NSRegularExpression(pattern: "^\\[\\s*\\d+(?:\\s*[,;]\\s*\\d+)*\\s*\\]$")
    private static let checkbox = try! NSRegularExpression(pattern: "^\\s*\\[\\s*x\\s*\\]$", options: [.caseInsensitive])
    private static let listStart = try! NSRegularExpression(pattern: "(^|\\n)[ \\t]*[-*+][ \\t]*$")
    // What a removed marker leaves: "zit ." and "zit ,".
    private static let spaceBeforePunct = try! NSRegularExpression(pattern: "[ \\t]+([.,;:!?])")

    private static func test(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// `text` without its placeholder markers; unchanged when it has none.
    public static func stripPlaceholderMarkers(_ text: String) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        var changed = false
        for m in marker.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let found = ns.substring(with: m.range)
            let from = max(0, m.range.location - 40)
            let before = ns.substring(with: NSRange(location: from, length: m.range.location - from))
            let isCheckbox = test(checkbox, found) && test(listStart, before)
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            if isCheckbox || test(numeric, found.trimmingCharacters(in: .whitespaces)) {
                out += found
            } else {
                changed = true
            }
            last = m.range.location + m.range.length
        }
        guard changed else { return text }
        out += ns.substring(from: last)
        let tidy = spaceBeforePunct.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "$1")
        return tidy.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
