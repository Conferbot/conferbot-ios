//
//  ChatMarkdown.swift
//  Conferbot
//
//  Agent message text for a native bubble. AI replies arrive as markdown
//  wrapped in <p> (embed-server aiAgentHandlerService), a person's as the
//  inbox editor's HTML. Both become one small markdown subset - paragraphs,
//  "- " / "1." lists, **bold**, _italic_, `code`, [links](https://...) and
//  bare links - parsed into blocks of inline runs. Never HTML on screen:
//  only http(s), mailto and tel links survive. Foundation only.
//

import Foundation

public enum ChatMarkdown {

    public enum Inline: Equatable {
        case plain(String)
        case bold(String)
        case italic(String)
        case code(String)
        case link(text: String, url: String)

        public var text: String {
            switch self {
            case .plain(let t), .bold(let t), .italic(let t), .code(let t): return t
            case .link(let t, _): return t
            }
        }
    }

    public enum Block: Equatable {
        case paragraph([Inline])
        case bullet([Inline])
        case numbered(Int, [Inline])

        public var inlines: [Inline] {
            switch self {
            case .paragraph(let i), .bullet(let i): return i
            case .numbered(_, let i): return i
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
        // Links first: [label](url) for a safe url, the label alone otherwise.
        let link = regex("<a\\s[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", [.caseInsensitive, .dotMatchesLineSeparators])
        var linked = ""
        var last = s.startIndex
        for m in link.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s), let urlR = Range(m.range(at: 1), in: s), let textR = Range(m.range(at: 2), in: s) else { continue }
            linked += s[last..<whole.lowerBound]
            let url = String(s[urlR])
            let label = replace(String(s[textR]), "<[^>]+>", "").trimmingCharacters(in: .whitespaces)
            linked += safeLinkURL(url) != nil ? "[\(label.isEmpty ? url : label)](\(url))" : label
            last = whole.upperBound
        }
        s = linked + s[last...]
        let dotAll: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]
        s = replace(s, "<(strong|b)>(.*?)</\\1>", "**$2**", dotAll)
        s = replace(s, "<(em|i)>(.*?)</\\1>", "_$2_", dotAll)
        s = replace(s, "<code>(.*?)</code>", "`$1`", dotAll)
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
        "\\*\\*([^*]+)\\*\\*|__([^_]+)__|`([^`]+)`|\\[([^\\]]+)\\]\\(([^)\\s]+)\\)|(^|[^\\w*])[*_]([^*_\\n]+)[*_](?![\\w*])|(https?://[^\\s<>()]+[^\\s<>().,;:!?'\"])",
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
            let g7 = group(m, 7), g8 = group(m, 8)
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
            }
        }
        push(String(line[last...]))
        return out
    }

    /// The text as blocks: list items, and paragraphs (a single newline is a line break).
    public static func parse(_ markdown: String?) -> [Block] {
        var blocks: [Block] = []
        var para: [String] = []
        func flush() {
            if !para.isEmpty { blocks.append(.paragraph(parseInline(para.joined(separator: "\n")))) }
            para.removeAll()
        }
        let bullet = regex("^[-*•]\\s+(.*)$", [])
        let numbered = regex("^(\\d{1,3})[.)]\\s+(.*)$", [])
        for raw in (markdown ?? "").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)
            if let m = bullet.firstMatch(in: line, range: range), let r = Range(m.range(at: 1), in: line) {
                flush()
                blocks.append(.bullet(parseInline(String(line[r]))))
            } else if let m = numbered.firstMatch(in: line, range: range),
                      let nr = Range(m.range(at: 1), in: line), let tr = Range(m.range(at: 2), in: line) {
                flush()
                blocks.append(.numbered(Int(line[nr]) ?? 1, parseInline(String(line[tr]))))
            } else if line.isEmpty {
                flush()
            } else {
                para.append(replace(line, "^#{1,6}\\s+", "", []))
            }
        }
        flush()
        return blocks
    }

    /// Plain text of the blocks (accessibility, transcript, notifications).
    public static func plainText(_ blocks: [Block]) -> String {
        blocks.map { block -> String in
            let text = block.inlines.map { $0.text }.joined()
            switch block {
            case .bullet: return "• \(text)"
            case .numbered(let n, _): return "\(n). \(text)"
            case .paragraph: return text
            }
        }.joined(separator: "\n")
    }
}
