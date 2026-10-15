//
//  FlowValues.swift
//  Conferbot
//
//  Reading the builder's saved node data the way the web widget's
//  JavaScript reads it. Node data arrives as JSON ([String: Any] with
//  NSNumber, NSNull...), and the flow rules (ported from
//  conferbot-widget/src/ts/chat) lean on JavaScript's conversions:
//  String(v), Number(v), truthiness, "1,200"... These helpers give the
//  same answers so the ported rules read the same.
//

import Foundation

enum JS {

    /// A JSON null or a missing value.
    static func isNullish(_ v: Any?) -> Bool {
        guard let v = v else { return true }
        if v is NSNull { return true }
        // An Optional.none boxed in Any
        let m = Mirror(reflecting: v)
        return m.displayStyle == .optional && m.children.isEmpty
    }

    /// A real boolean (a JSON true/false or a Swift Bool), never a number.
    static func isBool(_ v: Any?) -> Bool {
        guard let v = v, !isNullish(v) else { return false }
        if v is Bool, !(v is NSNumber) { return true }
        if let n = v as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() }
        return false
    }

    static func bool(_ v: Any?) -> Bool? {
        guard isBool(v) else { return nil }
        return (v as? NSNumber)?.boolValue ?? (v as? Bool)
    }

    /// A number (not a boolean): Int, Double, NSNumber.
    static func number(_ v: Any?) -> Double? {
        guard let v = v, !isNullish(v), !isBool(v) else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let i = v as? Int { return Double(i) }
        if let d = v as? Double { return d }
        return nil
    }

    static func isNumber(_ v: Any?) -> Bool { number(v) != nil }

    static func isString(_ v: Any?) -> Bool { v is String || v is NSString }

    static func isArray(_ v: Any?) -> Bool { v is [Any] }

    static func isObject(_ v: Any?) -> Bool { v is [String: Any] }

    /// JavaScript's Number -> String: 3 -> "3", 2.5 -> "2.5".
    static func numberText(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
        if d == d.rounded(), abs(d) < 1e21 {
            if d == 0 { return "0" }
            return String(format: "%.0f", d)
        }
        var s = "\(d)"
        // Swift writes 1e-07; JavaScript 1e-7
        if let e = s.range(of: "e-0") { s.replaceSubrange(e, with: "e-") }
        if let e = s.range(of: "e+0") { s.replaceSubrange(e, with: "e+") }
        if s.contains("e"), !s.contains("e-"), !s.contains("e+") { s = s.replacingOccurrences(of: "e", with: "e+") }
        return s
    }

    /// JavaScript's String(v) for a value that is there (null -> "null").
    static func str(_ v: Any?) -> String {
        guard let v = v else { return "undefined" }
        if v is NSNull { return "null" }
        if let b = bool(v) { return b ? "true" : "false" }
        if let d = number(v) { return numberText(d) }
        if let s = v as? String { return s }
        if let a = v as? [Any] { return a.map { isNullish($0) ? "" : str($0) }.joined(separator: ",") }
        if v is [String: Any] { return "[object Object]" }
        return String(describing: v)
    }

    /// `String(v ?? "")`: null and missing are "".
    static func text(_ v: Any?) -> String { isNullish(v) ? "" : str(v) }

    /// `String(v ?? "").trim()`
    static func trimmed(_ v: Any?) -> String { text(v).trimmingCharacters(in: .whitespacesAndNewlines) }

    /// JavaScript's Number(v): "" -> 0, null -> 0, missing -> NaN, "12px" -> NaN.
    static func toNumber(_ v: Any?) -> Double {
        guard let v = v else { return .nan }
        if v is NSNull { return 0 }
        if let b = bool(v) { return b ? 1 : 0 }
        if let d = number(v) { return d }
        if let s = v as? String { return parseNumber(s) }
        if let a = v as? [Any] {
            if a.isEmpty { return 0 }
            if a.count == 1 { return toNumber(a[0] is [Any] ? a[0] : str(a[0])) }
            return .nan
        }
        return .nan
    }

    /// Number("...") for text.
    static func parseNumber(_ raw: String) -> Double {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return 0 }
        let lower = s.lowercased()
        if lower.hasPrefix("0x"), let n = UInt64(s.dropFirst(2), radix: 16) { return Double(n) }
        if lower.hasPrefix("0b"), let n = UInt64(s.dropFirst(2), radix: 2) { return Double(n) }
        if lower.hasPrefix("0o"), let n = UInt64(s.dropFirst(2), radix: 8) { return Double(n) }
        if s == "Infinity" || s == "+Infinity" { return .infinity }
        if s == "-Infinity" { return -.infinity }
        guard s.range(of: "^[-+]?(\\d+\\.?\\d*|\\.\\d+)([eE][-+]?\\d+)?$", options: .regularExpression) != nil else { return .nan }
        return Double(s) ?? .nan
    }

    /// JavaScript's parseFloat.
    static func parseFloat(_ v: Any?) -> Double {
        let s = text(v).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = s.range(of: "^[-+]?(\\d+\\.?\\d*|\\.\\d+)([eE][-+]?\\d+)?", options: .regularExpression) else { return .nan }
        return Double(s[r]) ?? .nan
    }

    static func isFinite(_ v: Any?) -> Bool { toNumber(v).isFinite }

    /// JavaScript truthiness.
    static func truthy(_ v: Any?) -> Bool {
        guard let v = v, !isNullish(v) else { return false }
        if let b = bool(v) { return b }
        if let d = number(v) { return d != 0 && !d.isNaN }
        if let s = v as? String { return !s.isEmpty }
        return true
    }

    /// A Swift value for a JS number: whole numbers as Int (so they read and compare as 3, not 3.0).
    static func num(_ d: Double) -> Any {
        if d.isFinite, d == d.rounded(), abs(d) < 9e15 { return Int(d) }
        return d
    }

    static func dict(_ v: Any?) -> [String: Any] { (v as? [String: Any]) ?? [:] }

    static func array(_ v: Any?) -> [Any] { (v as? [Any]) ?? [] }

    static func dicts(_ v: Any?) -> [[String: Any]] {
        array(v).map { ($0 as? [String: Any]) ?? [:] }
    }

    /// Two values equal as the same JSON.
    static func same(_ a: Any?, _ b: Any?) -> Bool { json(a) == json(b) }

    /// A value as JSON text (keys sorted; whole numbers without ".0").
    static func json(_ v: Any?) -> String {
        guard let v = v, !isNullish(v) else { return "null" }
        if let b = bool(v) { return b ? "true" : "false" }
        if let d = number(v) { return d.isFinite ? numberText(d) : "null" }
        if let s = v as? String { return quote(s) }
        if let a = v as? [Any] { return "[" + a.map { json($0) }.joined(separator: ",") + "]" }
        if let o = v as? [String: Any] {
            return "{" + o.keys.sorted().map { "\(quote($0)):\(json(o[$0]))" }.joined(separator: ",") + "}"
        }
        return quote(String(describing: v))
    }

    /// JSON.stringify of a value, keys in the dictionary's own order is not
    /// knowable in Swift: sorted keys, otherwise the same text.
    static func stringify(_ v: Any?) -> String { json(v) }

    static func quote(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 { out += String(format: "\\u%04x", ch.value) } else { out.unicodeScalars.append(ch) }
            }
        }
        return out + "\""
    }

    /// JSON.parse; nil when it isn't JSON.
    static func parse(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// A deep copy made safe for JSONSerialization (dates as ISO text, unknown values dropped).
    static func plain(_ v: Any?) -> Any? {
        guard let v = v else { return nil }
        if v is NSNull { return v }
        if isBool(v) || isNumber(v) || v is String { return v }
        if let a = v as? [Any] { return a.compactMap { plain($0) ?? NSNull() } }
        if let o = v as? [String: Any] { return o.compactMapValues { plain($0) } }
        if let d = v as? Date { return Flow.iso(d) }
        return nil
    }
}

// MARK: - Regular expressions

/// Small helpers over NSRegularExpression for the ported rules.
struct Re {
    let re: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        // Patterns are constants: a bad one is a programming error.
        re = try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// nil when the pattern itself is bad (a regex the owner typed).
    static func safe(_ pattern: String, _ options: NSRegularExpression.Options = []) -> Re? {
        guard let r = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        return Re(compiled: r)
    }

    private init(compiled: NSRegularExpression) { re = compiled }

    func test(_ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// The groups of the first match ("" for a group that took no part), or nil.
    func match(_ s: String) -> [String?]? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return Re.groups(m, s)
    }

    func matches(_ s: String) -> [[String?]] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { Re.groups($0, s) }
    }

    static func groups(_ m: NSTextCheckingResult, _ s: String) -> [String?] {
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
            return String(s[range])
        }
    }

    /// String.replace with a function (every match).
    func replace(_ s: String, _ fn: ([String?]) -> String) -> String {
        var out = ""
        var last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s) else { continue }
            out += s[last..<whole.lowerBound]
            out += fn(Re.groups(m, s))
            last = whole.upperBound
        }
        return out + s[last...]
    }

    /// String.replace with a template ($1...).
    func replace(_ s: String, _ template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}

extension String {
    /// `replace(/pattern/g, template)`
    func replacing(_ pattern: String, with template: String, _ options: NSRegularExpression.Options = []) -> String {
        Re(pattern, options).replace(self, template)
    }

    func matches(_ pattern: String, _ options: NSRegularExpression.Options = []) -> Bool {
        Re(pattern, options).test(self)
    }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// JavaScript's padStart.
    func padStart(_ n: Int, _ pad: Character = "0") -> String {
        count >= n ? self : String(repeating: pad, count: n - count) + self
    }

    /// The first `n` characters (UTF-16 units, as JavaScript's slice).
    func jsSlice(_ from: Int, _ to: Int? = nil) -> String {
        let units = Array(utf16)
        let len = units.count
        func clamp(_ i: Int) -> Int { i < 0 ? max(0, len + i) : min(i, len) }
        let a = clamp(from)
        let b = to.map(clamp) ?? len
        guard a < b else { return "" }
        return String(utf16CodeUnits: Array(units[a..<b]), count: b - a)
    }

    var jsLength: Int { utf16.count }
}

// MARK: - Shared

/// Times and small bits the flow shares.
enum Flow {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// `new Date().toISOString()`: "2026-10-15T10:00:00.000Z".
    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    /// `Date.parse` of an ISO text, in ms; nil when it isn't one.
    static func parseISO(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    static func ms(_ date: Date) -> Double { (date.timeIntervalSince1970 * 1000).rounded() }
}
