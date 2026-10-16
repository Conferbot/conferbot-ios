//
//  FlowText.swift
//  Conferbot
//
//  Text helpers the flow steps share, ported from the web widget
//  (conferbot-widget/src/ts/chat/nodeLogic.ts, richNodes.ts plainText,
//  utils/helpers.ts _stripHtmlAndDecodeEntities) through the React Native
//  SDK (src/core/flow/text.ts). Pure: no state.
//
//  The flow-node spec (conferbot-react-native scripts/parity/flows,
//  nodes.spec.json engine.interpolation) is the reference: {x}, ${x}, {{x}},
//  ${ANSWERS.x} and $${x} fill from the answers; an unknown, null or ""
//  value shows nothing and the gap it leaves is tidied; values are
//  HTML-escaped.
//

import Foundation

public typealias VariableLookup = (String) -> Any?

public enum FlowText {

    private static func plainScalar(_ v: Any?) -> Bool { JS.isNullish(v) || !(v is [Any] || v is [String: Any]) }
    private static func plainList(_ v: Any?) -> Bool { (v as? [Any]).map { $0.allSatisfy { plainScalar($0) } } ?? false }

    /// A saved value as text: a list reads "a, b"; a matrix answer
    /// ({row: column} or a list of columns per row) "Row: Col · Row2: Col2";
    /// any other object is JSON.
    public static func variableText(_ value: Any?) -> String {
        if plainList(value), let list = value as? [Any] { return list.map { JS.isNullish($0) ? "" : JS.str($0) }.joined(separator: ", ") }
        if let o = value as? [String: Any], !o.isEmpty, o.values.allSatisfy({ plainScalar($0) || plainList($0) }) {
            return o.keys.sorted().map { k -> String in
                let v = o[k]
                if let list = v as? [Any] { return "\(k): \(list.map { JS.str($0) }.joined(separator: ", "))" }
                return "\(k): \(JS.str(v))"
            }.joined(separator: " · ")
        }
        if value is [Any] || value is [String: Any] { return JS.json(value) }
        return JS.str(value)
    }

    /// Text made safe inside HTML.
    public static func escapeHtml(_ value: Any?) -> String {
        JS.text(value)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// {x}, ${x}, $${x}, {{x}} and ${ANSWERS.x}: groups 1/3 the "$" prefix, 2/4 the key.
    private static let placeholder = Re("(\\$\\$|\\$)?\\{\\{\\s*((?:ANSWERS\\.)?[A-Za-z0-9_]+)\\s*\\}\\}|(\\$\\$|\\$)?\\{\\s*((?:ANSWERS\\.)?[A-Za-z0-9_]+)\\s*\\}")
    /// The gap marker is a NUL: no owner text contains one.
    private static let gap = "\u{0000}"

    /// A gap left by an empty placeholder, tidied ("Hey ${name}, welcome" -> "Hey, welcome").
    static func closeGaps(_ text: String) -> String {
        guard text.contains(gap) else { return text }
        return text
            .replacing("(^|>)[ \\t ]*\\x{0000}+[ \\t ]*[,;:]?[ \\t ]*", with: "$1")
            .replacing("[ \\t ]*\\x{0000}+(?=[ \\t ]*([,.!?;:)]|<|$))", with: "")
            .replacing("([ \\t])\\x{0000}+[ \\t ]+", with: "$1")
            .replacingOccurrences(of: gap, with: "")
    }

    public enum FillMode { case html, raw }

    private static func lookupKey(_ lookup: VariableLookup, _ key: String) -> Any? {
        var value = lookup(key)
        if JS.isNullish(value), key.hasPrefix("ANSWERS.") { value = lookup(String(key.dropFirst(8))) }
        return value
    }

    /// Fill the placeholders in owner text from the answers (web nodeLogic.fillVariables).
    public static func fillVariables(_ text: Any?, _ lookup: VariableLookup, mode: FillMode = .html) -> String {
        let filled = placeholder.replace(JS.text(text)) { g in
            let prefix = g[1] ?? g[3]
            let key = g[2] ?? g[4] ?? ""
            let value = lookupKey(lookup, key)
            if JS.isNullish(value) { return gap }
            if let s = value as? String, s.isEmpty { return gap }
            let shown = mode == .raw ? variableText(value) : escapeHtml(variableText(value))
            return prefix == "$$" ? "$\(shown)" : shown
        }
        return closeGaps(filled)
    }

    /// Fill the variables in a link: a value in the query or hash is
    /// URL-encoded, one before it goes in as is; an unknown one stays as written.
    public static func fillLinkVariables(_ link: Any?, _ lookup: VariableLookup) -> String {
        let text = JS.text(link).trimmed
        var out = ""
        var last = text.startIndex
        for m in placeholder.re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(m.range, in: text) else { continue }
            out += text[last..<whole.lowerBound]
            last = whole.upperBound
            let g = Re.groups(m, text)
            let key = g[2] ?? g[4] ?? ""
            let value = lookupKey(lookup, key)
            if JS.isNullish(value) {
                out += text[whole]
                continue
            }
            let shown = variableText(value).trimmed
            let inQuery = out.contains("?") || out.contains("#")
            out += ((g[1] ?? g[3]) == "$$" ? "$" : "") + (inQuery ? encodeURIComponent(shown) : shown)
        }
        return out + text[last...]
    }

    /// JavaScript's encodeURIComponent.
    public static func encodeURIComponent(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
        allowed.insert(charactersIn: "-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// The visitor's first name, capitalised: "deepak gopal" -> "Deepak".
    public static func firstName(_ value: Any?) -> String {
        let first = JS.text(value).trimmed.components(separatedBy: .whitespacesAndNewlines).first(where: { !$0.isEmpty }) ?? ""
        guard let c = first.first else { return "" }
        return String(c).uppercased() + first.dropFirst()
    }

    /// True when owner HTML shows nothing ("<p><br></p>").
    public static func isBlankHtml(_ html: Any?) -> Bool {
        let s = JS.text(html)
        if s.matches("<(img|iframe|video|audio|svg)\\b", .caseInsensitive) { return false }
        return s.replacing("</?[^>]+(>|$)", with: "")
            .replacing("&nbsp;|&#160;| |\\x{FEFF}|&#xFEFF;", with: "", .caseInsensitive)
            .trimmed.isEmpty
    }

    /// The ask-name greeting by first name: none set at all is the default
    /// "Nice to meet you, X" in the visitor's language (web nodeLogic.ts); one cleared in the builder is "" (no bubble).
    public static func nameGreetingHtml(_ template: Any?, _ name: Any?) -> String {
        let first = escapeHtml(firstName(name))
        if JS.isNullish(template) { return first.isEmpty ? "" : I18n.t("node.niceToMeet", ["name": first]) }
        if isBlankHtml(template) { return "" }
        let filled = Re("\\$?\\{\\{?\\s*name\\s*\\}?\\}").replace(JS.text(template)) { _ in first.isEmpty ? gap : first }
        return closeGaps(filled)
    }

    /// Owner HTML as one line of plain text (web richNodes.plainText).
    public static func plainText(_ value: Any?) -> String {
        JS.text(value)
            .replacing("<br\\s*/?>", with: " ", .caseInsensitive)
            .replacing("</?[^>]+(>|$)", with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacing("\\s+", with: " ")
            .trimmed
    }

    /// Tags stripped and entities decoded, trimmed (web helpers _stripHtmlAndDecodeEntities).
    public static func stripHtmlAndDecode(_ html: Any?) -> String {
        guard JS.truthy(html) else { return "" }
        var s = JS.text(html)
            .replacing("</?[^>]+(>|$)", with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        s = Re("&#(\\d+);").replace(s) { g in
            guard let n = UInt32(g[1] ?? ""), let u = Unicode.Scalar(n) else { return g[0] ?? "" }
            return String(Character(u))
        }
        s = Re("&#x([0-9A-Fa-f]+);").replace(s) { g in
            guard let n = UInt32(g[1] ?? "", radix: 16), let u = Unicode.Scalar(n) else { return g[0] ?? "" }
            return String(Character(u))
        }
        return s.trimmed
    }

    /// Owner HTML as the text a native bubble shows: paragraphs and <br>
    /// keep their line breaks, tags go, entities are decoded.
    public static func bubbleText(_ html: Any?) -> String {
        JS.text(html)
            .replacing("<br\\s*/?>", with: "\n", .caseInsensitive)
            .replacing("</p>", with: "\n", .caseInsensitive)
            .replacing("<[^>]+>", with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacing("\\n{3,}", with: "\n\n")
            .trimmed
    }

    /// Owner HTML for the HTML step, made safe: no <script>, no on* handlers,
    /// no javascript:/vbscript: URLs (web nodeLogic.sanitizeOwnerHtml).
    public static func sanitizeOwnerHtml(_ html: Any?) -> String {
        JS.text(html)
            .replacing("<script\\b[\\s\\S]*?</script\\s*>", with: "", .caseInsensitive)
            .replacing("<script\\b[^>]*/?>", with: "", .caseInsensitive)
            .replacing("<(object|embed|base|meta|link)\\b[^>]*>", with: "", .caseInsensitive)
            .replacing("\\s+on[a-z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)", with: "", .caseInsensitive)
            .replacing("\\s(href|src|action|formaction|xlink:href)\\s*=\\s*(\"|')?\\s*(javascript|vbscript|data:text/html)[^\"'\\s>]*(\"|')?", with: " $1=\"#\"", .caseInsensitive)
    }

    /// The field holding the text a step shows, by type (web nodeLogic PROMPT_FIELD).
    public static let promptField: [String: String] = [
        "welcome-node": "text",
        "message-node": "text",
        "ask-name-node": "questionText",
        "ask-email-node": "questionText",
        "ask-phone-number-node": "questionText",
        "ask-number-node": "questionText",
        "ask-url-node": "questionText",
        "ask-location-node": "questionText",
        "ask-custom-question-node": "questionText",
        "ask-file-node": "questionText",
        "ask-multiple-questions-node": "message",
        "calendar-node": "calendarPrompt",
        "n-choices-node": "choicePrompt",
        "n-select-option-node": "selectPrompt",
        "n-check-options-node": "checkOptionsPrompt",
        "image-choice-node": "questionText",
        "carousel-node": "questionText",
        "rating-choice-node": "questionText",
        "yes-or-no-choice-node": "questionText",
        "opinion-scale-choice-node": "questionText",
        "user-redirect-node": "redirectPrompt",
        "navigate-node": "navigatePrompt",
        "quiz-node": "quizPrompt",
        "human-handover-node": "handoverMessage",
        "dynamic-choices-node": "questionText",
        "consent-node": "questionText",
        "product-card-node": "questionText",
        "slider-node": "questionText",
        "datetime-node": "questionText",
        "ranking-node": "questionText",
        "otp-node": "questionText",
        "address-node": "questionText",
        "matrix-node": "questionText",
        "ai-extract-node": "questionText",
        "ai-route-node": "questionText",
        "kb-answer-node": "questionText",
        "signature-node": "questionText",
    ]

    /// A step's own text with the variables filled in; nil when it shows none.
    public static func renderedText(_ node: [String: Any], _ lookup: VariableLookup) -> String? {
        guard let field = promptField[JS.text(node["type"])] else { return nil }
        guard let raw = JS.dict(node["data"])[field] as? String, !raw.trimmed.isEmpty else { return nil }
        return fillVariables(raw, lookup)
    }

    /// A message with no text or an image with no picture is skipped (no typing).
    public static func isEmptyContentStep(_ step: [String: Any]) -> Bool {
        let type = JS.text(step["type"])
        let data = JS.dict(step["data"])
        if type == "message-node" { return isBlankHtml(data["text"]) }
        if type == "image-node" { return JS.text(data["image"]).trimmed.isEmpty }
        return false
    }

    /// Ticked options in list order, not click order.
    public static func inListOrder(_ picked: [String], _ list: [String]) -> [String] {
        func rank(_ v: String) -> Int { list.firstIndex(of: v) ?? Int.max }
        return picked.enumerated()
            .sorted { a, b in rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset }
            .map { $0.element }
    }

    private static func clamp(_ n: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, n)) }

    /// A step's length for pacing: its message or question, tags stripped.
    private static func wordsOf(_ step: [String: Any]?) -> Int {
        let d = JS.dict(step?["data"])
        let raw: Any? = [d["text"], d["questionText"], d["calendarPrompt"], d["message"]].first(where: { !JS.isNullish($0) }) ?? ""
        return JS.text(raw)
            .replacing("<[^>]*>", with: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacing("\\s+", with: " ")
            .trimmed.jsLength
    }

    /// How long the typing dots show before a bot step (web nodeLogic.paceFor):
    /// after the visitor spoke, clamp(500 + len*12, 700, 1800); right after a
    /// step that moved on by itself, time to read it, then a shorter beat.
    public static func paceFor(previous: [String: Any]?, next: [String: Any], followsBotStep: Bool) -> Double {
        let nextLen = Double(wordsOf(next))
        if !followsBotStep { return clamp(500 + nextLen * 12, 700, 1800).rounded() }
        let read = clamp(Double(wordsOf(previous)) * 22, 350, 2200)
        return (read + clamp(250 + nextLen * 6, 300, 900)).rounded()
    }

    private static let autoAdvanceTypes: Set<String> = [
        "welcome-node", "message-node", "image-node", "video-node", "audio-node", "file-node", "html-node", "user-redirect-node",
    ]

    /// True when the step before was a bot step that moved on by itself.
    public static func followsAutoAdvanceStep(_ previousType: String?) -> Bool {
        autoAdvanceTypes.contains(previousType ?? "")
    }
}
