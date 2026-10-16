//
//  ChatMarkdown.swift
//  Conferbot
//
//  Agent message text for a native bubble. AI replies arrive as markdown
//  wrapped in <p> (embed-server aiAgentHandlerService), a person's as the
//  inbox editor's HTML. Both become one markdown subset, parsed into blocks
//  of inline runs. What the web's renderer (conferbot-widget
//  utils/agentHtml.ts) draws, as the React Native SDK's utils/chatMarkdown.ts:
//
//    blocks   paragraphs, "- " / "1." lists, # headings (levels 3-6; # and
//             ## are drawn as 4, as the web folds h1/h2 into h4), | tables |
//             with a |---| rule, and from a person's HTML: <blockquote>
//             ("> " lines here) and <pre> (``` fences here)
//    inline   **bold**, _italic_, `code`, ~~strikethrough~~ (<s>, <del>),
//             [links](https://...) and bare links
//
//  Never HTML on screen: only http(s), mailto and tel links survive.
//  Foundation only.
//

import Foundation

public enum ChatMarkdown {

    public enum Inline: Equatable {
        case plain(String)
        case bold(String)
        case italic(String)
        case code(String)
        case strike(String)
        case link(text: String, url: String)

        public var text: String {
            switch self {
            case .plain(let t), .bold(let t), .italic(let t), .code(let t), .strike(let t): return t
            case .link(let t, _): return t
            }
        }
    }

    public enum Block: Equatable {
        case paragraph([Inline])
        case bullet([Inline])
        case numbered(Int, [Inline])
        /// Levels 3 to 6 (# and ## are drawn as 4).
        case heading(Int, [Inline])
        case quote([Inline])
        /// Preformatted lines, nothing formatted inside.
        case pre(String)
        /// The head row's cells, then each row's (as many cells as the head).
        case table(head: [[Inline]], rows: [[[Inline]]])

        public var inlines: [Inline] {
            switch self {
            case .paragraph(let i), .bullet(let i), .quote(let i): return i
            case .numbered(_, let i), .heading(_, let i): return i
            case .pre, .table: return []
            }
        }
    }

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
        // Patterns are constants: a bad one is a programming error.
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String, _ options: NSRegularExpression.Options = [.caseInsensitive]) -> String {
        let r = regex(pattern, options)
        return r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Every match replaced by what `transform` makes of its groups (group 0 is the whole match).
    private static func replace(_ s: String, _ pattern: String, _ options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators], _ transform: ([String]) -> String) -> String {
        let r = regex(pattern, options)
        var out = ""
        var last = s.startIndex
        for m in r.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s) else { continue }
            out += s[last..<whole.lowerBound]
            let groups = (0..<m.numberOfRanges).map { i -> String in
                guard let g = Range(m.range(at: i), in: s) else { return "" }
                return String(s[g])
            }
            out += transform(groups)
            last = whole.upperBound
        }
        return out + s[last...]
    }

    // A cell's text: no tags, no line breaks, and its own "|" kept as text.
    private static func cellText(_ html: String) -> String {
        var t = replace(html, "<br\\s*/?>", " ")
        t = replace(t, "<[^>]+>", "")
        t = replace(t, "\\s+", " ", [])
        return t.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "|", with: "\\|")
    }

    /// An HTML table as a markdown one: the first row is the head.
    private static func tableToMarkdown(_ inner: String) -> String {
        let rowRe = regex("<tr[^>]*>(.*?)</tr>", [.caseInsensitive, .dotMatchesLineSeparators])
        let cellRe = regex("<t[hd][^>]*>(.*?)</t[hd]>", [.caseInsensitive, .dotMatchesLineSeparators])
        let rows: [[String]] = rowRe.matches(in: inner, range: NSRange(inner.startIndex..., in: inner)).compactMap { m in
            guard let r = Range(m.range(at: 1), in: inner) else { return nil }
            let row = String(inner[r])
            let cells = cellRe.matches(in: row, range: NSRange(row.startIndex..., in: row)).compactMap { c -> String? in
                guard let cr = Range(c.range(at: 1), in: row) else { return nil }
                return cellText(String(row[cr]))
            }
            return cells.isEmpty ? nil : cells
        }
        guard let head = rows.first else { return "" }
        let line = { (cells: [String]) in "| \(cells.joined(separator: " | ")) |" }
        let lines = [line(head), line(head.map { _ in "---" })] + rows.dropFirst().map(line)
        return "\n\n\(lines.joined(separator: "\n"))\n\n"
    }

    public static func safeLinkURL(_ url: String) -> String? {
        let u = url.trimmingCharacters(in: .whitespaces)
        return u.range(of: "^(https?://|mailto:|tel:)", options: [.regularExpression, .caseInsensitive]) != nil ? u : nil
    }

    private static let entities: [String: String] = [
        "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#x27;": "'"
    ]

    private static func decode(_ s: String) -> String {
        let r = regex("&(nbsp|amp|lt|gt|quot|#39|#x27);")
        var out = ""
        var last = s.startIndex
        for m in r.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let range = Range(m.range, in: s) else { continue }
            out += s[last..<range.lowerBound]
            out += entities[String(s[range])] ?? String(s[range])
            last = range.upperBound
        }
        return out + s[last...]
    }

    /// The message as markdown: the inbox's HTML tags turned into their markdown.
    public static func htmlToMarkdown(_ html: String?) -> String {
        guard var s = html, !s.isEmpty else { return "" }
        s = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // Preformatted text keeps its lines and nothing inside is formatted.
        s = replace(s, "<pre[^>]*>(.*?)</pre>") { g in
            var text = replace(g[1], "<br\\s*/?>", "\n")
            text = replace(text, "<[^>]+>", "")
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            return "\n\n```\n\(text)\n```\n\n"
        }
        // Links: [label](url) for a safe url, the label alone otherwise.
        s = replace(s, "<a\\s[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>") { g in
            let label = replace(g[2], "<[^>]+>", "").trimmingCharacters(in: .whitespaces)
            return safeLinkURL(g[1]) != nil ? "[\(label.isEmpty ? g[1] : label)](\(g[1]))" : label
        }
        let dotAll: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]
        s = replace(s, "<(strong|b)>(.*?)</\\1>", "**$2**", dotAll)
        s = replace(s, "<(em|i)>(.*?)</\\1>", "_$2_", dotAll)
        s = replace(s, "<code>(.*?)</code>", "`$1`", dotAll)
        s = replace(s, "<(s|del|strike)>(.*?)</\\1>", "~~$2~~", dotAll)
        // h1 / h2 are drawn as h4, as the web's sanitizer folds them.
        s = replace(s, "<h([1-6])[^>]*>(.*?)</h\\1>") { g in
            let n = Int(g[1]) ?? 4
            var text = replace(g[2], "<[^>]+>", "")
            text = replace(text, "\\s+", " ", []).trimmingCharacters(in: .whitespaces)
            return "\n\n\(String(repeating: "#", count: n <= 2 ? 4 : n)) \(text)\n\n"
        }
        s = replace(s, "<table[^>]*>(.*?)</table>") { g in tableToMarkdown(g[1]) }
        s = replace(s, "<blockquote[^>]*>(.*?)</blockquote>") { g in
            var inner = replace(g[1], "<br\\s*/?>", "\n")
            inner = replace(inner, "</p>\\s*<p[^>]*>", "\n")
            inner = replace(inner, "<[^>]+>", "")
            let lines = inner.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return "\n\n\(lines.map { "> \($0)" }.joined(separator: "\n"))\n\n"
        }
        s = replace(s, "<li[^>]*>", "\n- ")
        s = replace(s, "</(li|ul|ol)>", "\n")
        s = replace(s, "<br\\s*/?>", "\n")
        s = replace(s, "</p>\\s*<p[^>]*>", "\n\n")
        s = replace(s, "</?(p|div|ul|ol)[^>]*>", "\n")
        s = replace(s, "<[^>]+>", "")
        s = decode(s)
        s = replace(s, "[ \\t]+\\n", "\n", [])
        s = replace(s, "\\n{3,}", "\n\n", [])
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let inlinePattern = regex(
        "\\*\\*([^*]+)\\*\\*|__([^_]+)__|`([^`]+)`|\\[([^\\]]+)\\]\\(([^)\\s]+)\\)|(^|[^\\w*])[*_]([^*_\\n]+)[*_](?![\\w*])|(https?://[^\\s<>()]+[^\\s<>().,;:!?'\"])|~~([^~\\n]+)~~",
        []
    )

    /// One line's inline runs.
    public static func parseInline(_ line: String) -> [Inline] {
        var out: [Inline] = []
        func push(_ text: String) {
            guard !text.isEmpty else { return }
            if case .plain(let prev)? = out.last { out[out.count - 1] = .plain(prev + text) } else { out.append(.plain(text)) }
        }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: line) else { return "" }
            return String(line[r])
        }
        var last = line.startIndex
        for m in inlinePattern.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            guard let whole = Range(m.range, in: line) else { continue }
            push(String(line[last..<whole.lowerBound]))
            last = whole.upperBound
            let g1 = group(m, 1), g2 = group(m, 2), g3 = group(m, 3), g4 = group(m, 4)
            let g7 = group(m, 7), g8 = group(m, 8), g9 = group(m, 9)
            if !g1.isEmpty || !g2.isEmpty {
                out.append(.bold(g1.isEmpty ? g2 : g1))
            } else if !g3.isEmpty {
                out.append(.code(g3))
            } else if !g4.isEmpty {
                if let url = safeLinkURL(group(m, 5)) { out.append(.link(text: g4, url: url)) } else { push(g4) }
            } else if !g7.isEmpty {
                push(group(m, 6))
                out.append(.italic(g7))
            } else if !g8.isEmpty {
                out.append(.link(text: g8, url: g8))
            } else if !g9.isEmpty {
                out.append(.strike(g9))
            }
        }
        push(String(line[last...]))
        return out
    }

    /// A row's cells; a "\\|" inside a cell is its own text.
    public static func tableCells(_ line: String) -> [String] {
        let chars = Array(line.trimmingCharacters(in: .whitespaces))
        var cells: [String] = []
        var cell = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "|" {
                cell.append("|")
                i += 2
                continue
            }
            if chars[i] == "|" {
                cells.append(cell)
                cell = ""
            } else {
                cell.append(chars[i])
            }
            i += 1
        }
        cells.append(cell)
        // The outer pipes open and close the row.
        let s = String(chars)
        if s.hasPrefix("|") { cells.removeFirst() }
        if s.hasSuffix("|") && !s.hasSuffix("\\|") && !cells.isEmpty { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func matches(_ s: String, _ r: NSRegularExpression) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// The text as blocks: list items, headings, tables, quotes, code and
    /// paragraphs (a single newline is a line break).
    public static func parse(_ markdown: String?) -> [Block] {
        var blocks: [Block] = []
        var para: [String] = []
        var quote: [String] = []
        func flushPara() {
            if !para.isEmpty { blocks.append(.paragraph(parseInline(para.joined(separator: "\n")))) }
            para.removeAll()
        }
        func flush() {
            flushPara()
            if !quote.isEmpty { blocks.append(.quote(parseInline(quote.joined(separator: "\n")))) }
            quote.removeAll()
        }
        let bullet = regex("^[-*+•]\\s+(.*)$", [])
        let numbered = regex("^(\\d{1,3})[.)]\\s+(.*)$", [])
        let heading = regex("^(#{1,6})\\s+(.*?)\\s*#*\\s*$", [])
        let quoted = regex("^>\\s?(.*)$", [])
        let fence = regex("^```", [])
        let fenceEnd = regex("^```\\s*$", [])
        // A markdown table: a header row, a |---| rule, then rows (web agentHtml.ts).
        let tableRow = regex("^\\s*\\|.*\\|\\s*$", [])
        let tableRule = regex("^\\s*\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{2,}:?\\s*)*\\|?\\s*$", [])
        func group(_ r: NSRegularExpression, _ s: String, _ i: Int) -> String? {
            guard let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let g = Range(m.range(at: i), in: s) else { return nil }
            return String(s[g])
        }

        let lines = (markdown ?? "").components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)
            // ``` fences: the lines as they are, nothing formatted.
            if matches(line, fence) {
                flush()
                var body: [String] = []
                i += 1
                while i < lines.count && !matches(lines[i].trimmingCharacters(in: .whitespaces), fenceEnd) {
                    body.append(lines[i])
                    i += 1
                }
                blocks.append(.pre(body.joined(separator: "\n")))
                i += 1
                continue
            }
            // A table: this row, a rule under it, and every row after.
            let nextLine = i + 1 < lines.count ? lines[i + 1] : ""
            if matches(raw, tableRow) && matches(nextLine, tableRule) && nextLine.contains("-") {
                flush()
                let head = tableCells(raw)
                i += 2
                var rows: [[[Inline]]] = []
                while i < lines.count && matches(lines[i], tableRow) {
                    let cells = tableCells(lines[i])
                    rows.append(head.indices.map { k in parseInline(k < cells.count ? cells[k] : "") })
                    i += 1
                }
                blocks.append(.table(head: head.map { parseInline($0) }, rows: rows))
                continue
            }
            if let q = group(quoted, line, 1) {
                flushPara()
                quote.append(q)
                i += 1
                continue
            }
            if !quote.isEmpty { flush() }
            if let b = group(bullet, line, 1) {
                flush()
                blocks.append(.bullet(parseInline(b)))
            } else if let n = group(numbered, line, 1), let t = group(numbered, line, 2) {
                flush()
                blocks.append(.numbered(Int(n) ?? 1, parseInline(t)))
            } else if let hashes = group(heading, line, 1), let t = group(heading, line, 2) {
                flush()
                blocks.append(.heading(hashes.count <= 2 ? 4 : hashes.count, parseInline(t)))
            } else if line.isEmpty {
                flush()
            } else {
                para.append(line)
            }
            i += 1
        }
        flush()
        return blocks
    }

    /// Plain text of the blocks (accessibility, transcript, notifications).
    public static func plainText(_ blocks: [Block]) -> String {
        func line(_ inlines: [Inline]) -> String { inlines.map { $0.text }.joined() }
        return blocks.map { block -> String in
            switch block {
            case .bullet(let i): return "• \(line(i))"
            case .numbered(let n, let i): return "\(n). \(line(i))"
            case .paragraph(let i), .heading(_, let i), .quote(let i): return line(i)
            case .pre(let text): return text
            case .table(let head, let rows):
                return ([head] + rows).map { $0.map(line).joined(separator: " | ") }.joined(separator: "\n")
            }
        }.joined(separator: "\n")
    }
}
