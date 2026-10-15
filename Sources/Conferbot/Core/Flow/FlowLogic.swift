//
//  FlowLogic.swift
//  Conferbot
//
//  The rules behind the logic steps, ported unchanged from the web widget
//  (conferbot-widget/src/ts/chat/handlers/conditionEval.ts for condition-node;
//  handlers/logicValues.ts for math, boolean, variable, random split,
//  jump-to and business hours) through the React Native SDK
//  (src/core/flow/logic.ts). Pure: the variable lookup, clock and random
//  number are passed in.
//

import Foundation

public enum FlowLogic {

    private static func stringify(_ value: Any?) -> String {
        if JS.isNullish(value) { return "" }
        if value is [Any] || value is [String: Any] { return JS.json(value) }
        return JS.str(value)
    }

    /// "${name}" / "{name}" typed into the variable field still means `name`.
    private static func variableKey(_ raw: Any?) -> String {
        let key = stringify(raw).trimmed
        if let m = Re("^\\$?\\{([A-Za-z0-9_]+)\\}$").match(key), let k = m[1] { return k }
        return key
    }

    /// Fill `${name}` placeholders in a typed value; unknown names stay as written.
    public static func interpolate(_ text: Any?, _ lookup: VariableLookup) -> String {
        Re("\\$\\{([A-Za-z0-9_]+)\\}").replace(stringify(text)) { g in
            let value = lookup(g[1] ?? "")
            return JS.isNullish(value) ? (g[0] ?? "") : stringify(value)
        }
    }

    /// A number or a quoted word, as typed: never an answer variable's name.
    private static func literalOf(_ raw: Any?) -> String? {
        let text = stringify(raw).trimmed
        if text.matches("^[-+]?[0-9]+(?:\\.[0-9]+)?$") { return text }
        if let m = Re("^\"(.*)\"$|^'(.*)'$").match(text) { return m[1] ?? m[2] }
        return nil
    }

    /// One side of the rule: the typed literal, or the variable's value.
    public static func resolveOperand(_ raw: Any?, _ isCustom: Any?, _ lookup: VariableLookup) -> Any? {
        if JS.truthy(isCustom) { return interpolate(raw, lookup) }
        let value = lookup(variableKey(raw))
        if !JS.isNullish(value) { return value }
        if let literal = literalOf(raw) { return literal }
        return value
    }

    private static let operatorAliases: [String: String] = [
        "==": "=", "equals": "=", "not_equals": "!=", "greater_than": ">", "less_than": "<",
        "greater_than_or_equal": ">=", "less_than_or_equal": "<=", "not_contains": "does not contain",
        "starts_with": "starts with", "ends_with": "ends with", "does_not_match": "does not match",
    ]

    /// The long-standing Number(...) reading (empty/missing -> 0).
    private static func asNumber(_ value: Any?) -> Double {
        if let d = JS.number(value) { return d }
        if let s = value as? String { return JS.toNumber(s.trimmed) }
        return JS.toNumber(value)
    }

    private static func isNumeric(_ value: Any?) -> Bool {
        if let d = JS.number(value) { return d.isFinite }
        let text = stringify(value).trimmed
        return !text.isEmpty && JS.toNumber(text).isFinite
    }

    /// Ratings used to be stored as their emoji ("⭐⭐⭐", "😊"); a rule an
    /// owner wrote against the old emoji keeps working.
    private static let ratingFaces = ["😡", "😐", "😊", "😀", "😁"]
    public static func ratingAlias(_ value: Any?) -> Any? {
        guard let s = value as? String else { return value }
        let v = s.trimmed
        if !v.isEmpty, v.allSatisfy({ $0 == "⭐" }) { return String(v.count) }
        if let face = ratingFaces.firstIndex(of: v) { return String(face + 1) }
        return value
    }

    /// true -> the "yes" branch (source-0), false -> "no" (source-1).
    public static func evaluateCondition(_ data: [String: Any], _ lookup: VariableLookup) -> Bool {
        let isNumber = JS.truthy(data["isNumber"])
        let rawOperator = stringify(JS.truthy(data["operator"]) ? data["operator"] : "=").trimmed
        let op = operatorAliases[rawOperator] ?? rawOperator

        let left = ratingAlias(resolveOperand(data["leftValue"], data["customLeftValue"], lookup))
        let right = ratingAlias(resolveOperand(data["rightValue"], data["customRightValue"], lookup))

        if op == "is_set" { return !stringify(left).trimmed.isEmpty }
        if op == "is_not_set" { return stringify(left).trimmed.isEmpty }

        let ci = JS.truthy(data["caseInsensitive"])
        func text(_ v: Any?) -> String { ci ? stringify(v).lowercased() : stringify(v) }

        switch op {
        case "=", "!=":
            let equal: Bool
            if isNumber { equal = asNumber(left) == asNumber(right) }
            else if isNumeric(left) && isNumeric(right) { equal = asNumber(left) == asNumber(right) }
            else { equal = text(left) == text(right) }
            return op == "=" ? equal : !equal
        case "<", ">", "<=", ">=":
            if !isNumber && !(isNumeric(left) && isNumeric(right)) { return false }
            let l = asNumber(left)
            let r = asNumber(right)
            if l.isNaN || r.isNaN { return false }
            switch op {
            case "<": return l < r
            case ">": return l > r
            case "<=": return l <= r
            default: return l >= r
            }
        case "contains": return !isNumber && jsIncludes(text(left), text(right))
        case "does not contain": return !isNumber && !jsIncludes(text(left), text(right))
        case "starts with": return !isNumber && text(left).hasPrefix(text(right))
        case "ends with": return !isNumber && text(left).hasSuffix(text(right))
        case "matches":
            guard !isNumber, let re = Re.safe(stringify(right), ci ? [.caseInsensitive] : []) else { return false }
            return re.test(stringify(left))
        case "does not match":
            guard !isNumber, let re = Re.safe(stringify(right), ci ? [.caseInsensitive] : []) else { return false }
            return !re.test(stringify(left))
        default:
            return false
        }
    }

    /// JavaScript's includes: "" is in every text.
    private static func jsIncludes(_ s: String, _ part: String) -> Bool { part.isEmpty || s.contains(part) }

    // MARK: - handlers/logicValues.ts

    private static func present(_ v: Any?) -> Bool { !JS.isNullish(v) }

    /// A name that reads like a variable: "price", "order.total", "_tmp".
    private static let identifier = Re("^[A-Za-z_][A-Za-z0-9_.]*$")
    private static let booleanWords: Set<String> = ["true", "false", "yes", "no", "on", "off"]
    private static let placeholder = Re("\\$?\\{([A-Za-z_][A-Za-z0-9_.]*)\\}")

    private static func wholePlaceholder(_ text: String) -> String? {
        Re("^\\$?\\{([A-Za-z_][A-Za-z0-9_.]*)\\}$").match(text)?[1] ?? nil
    }

    /// A saved value as text: lists read "a, b", other objects stay JSON.
    private static func asText(_ value: Any?) -> String {
        if let a = value as? [Any], a.allSatisfy({ JS.isNullish($0) || !($0 is [Any] || $0 is [String: Any]) }) {
            return a.map { JS.isNullish($0) ? "" : JS.str($0) }.joined(separator: ", ")
        }
        if value is [Any] || value is [String: Any] { return JS.json(value) }
        return JS.str(value)
    }

    /// Fill ${name} and {name} from the variables; unknown ones stay as written.
    public static func fillPlaceholders(_ text: Any?, _ lookup: VariableLookup) -> String {
        placeholder.replace(JS.text(text)) { g in
            let value = lookup(g[1] ?? "")
            return present(value) ? asText(value) : (g[0] ?? "")
        }
    }

    private static func unquote(_ text: String) -> String {
        if let m = Re("^([\"'])([\\s\\S]*)\\1$").match(text), let inner = m[2] { return inner }
        return text
    }

    /// One side of a rule: a variable's value when `raw` names one that has
    /// a value; nil when it names a variable with no answer yet; otherwise
    /// the typed text, with any placeholders inside it filled in.
    public static func valueOf(_ raw: Any?, _ lookup: VariableLookup) -> Any? {
        guard present(raw) else { return nil }
        guard let s = raw as? String else { return raw }
        let text = s.trimmed
        let wrapped = wholePlaceholder(text)
        let name = wrapped ?? text
        if !name.isEmpty {
            let value = lookup(name)
            if present(value) { return value }
        }
        if wrapped != nil { return nil }
        if identifier.test(text) && !booleanWords.contains(text.lowercased()) { return nil }
        return fillPlaceholders(unquote(text), lookup)
    }

    /// A value as a number: NaN when it isn't one (never 0 for empty).
    public static func toNumber(_ v: Any?) -> Double {
        if let d = JS.number(v) { return d }
        if let b = JS.bool(v) { return b ? 1 : 0 }
        guard let s = v as? String else { return .nan }
        var text = s.trimmed.replacing("\\s+", with: "")
        if text.isEmpty { return .nan }
        if text.matches("^[-+]?[0-9]{1,3}(,[0-9]{3})+(\\.[0-9]+)?$") { text = text.replacingOccurrences(of: ",", with: "") }
        if !text.matches("^[-+]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][-+]?[0-9]+)?$") { return .nan }
        return JS.parseNumber(text)
    }

    private static let falseWords: Set<String> = ["false", "no", "n", "0", "off", "none", "null", "undefined", ""]

    /// A value as true / false: "No", "off", "0" and empty are false.
    public static func toBool(_ v: Any?) -> Bool {
        if !present(v) { return false }
        if let s = v as? String, s.isEmpty { return false }
        if let b = JS.bool(v) { return b }
        if let d = JS.number(v) { return d != 0 }
        if let s = v as? String { return !falseWords.contains(s.trimmed.lowercased()) }
        if let a = v as? [Any] { return !a.isEmpty }
        return true
    }

    // MARK: Math step

    public static let defaultMathVariable = "math_operations"

    /// The variable a math step saves its result under.
    public static func mathVariableName(_ data: [String: Any]) -> String {
        let name = JS.text(data["answerVariable"]).trimmed
        return name.isEmpty ? defaultMathVariable : name
    }

    /// The math step's result, or "" when it can't be worked out.
    public static func mathResult(_ data: [String: Any], _ lookup: VariableLookup) -> Any {
        let l = toNumber(valueOf(data["leftValue"], lookup))
        let r = toNumber(valueOf(data["rightValue"], lookup))
        if l.isNaN || r.isNaN { return "" }
        let opText = JS.text(data["operator"]).trimmed
        let op = opText.isEmpty ? "+" : opText
        var x: Double
        switch op {
        case "+": x = l + r
        case "-": x = l - r
        case "*": x = l * r
        case "/":
            if r == 0 { return "" }
            x = l / r
        default: return ""
        }
        if !x.isFinite { return "" }
        // Number(x.toFixed(10))
        x = Double(String(format: "%.10f", x)) ?? x
        return JS.num(x)
    }

    // MARK: Boolean step

    /// The boolean step's answer: true takes source-0, false source-1.
    public static func booleanResult(_ data: [String: Any], _ lookup: VariableLookup) -> Bool {
        let l = toBool(valueOf(data["leftValue"], lookup))
        let r = toBool(valueOf(data["rightValue"], lookup))
        let opText = JS.text(data["operator"]).trimmed.uppercased()
        switch opText.isEmpty ? "AND" : opText {
        case "AND": return l && r
        case "OR": return l || r
        case "NOT": return l && !r
        case "XOR": return l != r
        case "NAND": return !(l && r)
        case "NOR": return !(l || r)
        case "XNOR": return l == r
        default: return false
        }
    }

    // MARK: Variable step

    /// The value a variable step stores: placeholders filled, a number when asked.
    public static func variableValue(_ data: [String: Any], _ lookup: VariableLookup) -> Any {
        let text = fillPlaceholders(present(data["value"]) ? data["value"] : "", lookup)
        if JS.truthy(data["isNumber"]) {
            let n = toNumber(text)
            if !n.isNaN { return JS.num(n) }
        }
        return text
    }

    // MARK: Random split

    /// A handle no edge uses: routing to it ends the flow.
    public static let noPath = "__no_path__"

    private static func weightOf(_ b: [String: Any]) -> Double {
        let n = toNumber(b["weight"])
        return n.isFinite && n > 0 ? n : 0
    }

    private static func pickWeighted<T>(_ items: [T], _ weights: [Double], _ rand: Double) -> T {
        let total = weights.reduce(0, +)
        if total <= 0 { return items[min(items.count - 1, Int((rand * Double(items.count)).rounded(.down)))] }
        let target = rand * total
        var acc = 0.0
        for i in 0..<items.count {
            acc += weights[i]
            if weights[i] > 0 && target < acc { return items[i] }
        }
        for i in stride(from: items.count - 1, through: 0, by: -1) where weights[i] > 0 { return items[i] }
        return items[items.count - 1]
    }

    /// The handle a random split leaves by, or nil when no branch has a line
    /// (the flow ends). Branches are matched by id (source-<id>); position
    /// handles only for flows saved before branches had ids.
    public static func pickRandomHandle(_ branches: Any?, _ edgeHandles: [String?], _ rand: Double) -> String? {
        let list = JS.dicts(branches)
        let wired = Set(edgeHandles.compactMap { $0 })
        func idOf(_ b: [String: Any]) -> String? {
            guard present(b["id"]), JS.str(b["id"]) != "" else { return nil }
            return JS.str(b["id"])
        }
        let byId = list.filter { b in idOf(b).map { wired.contains("source-\($0)") } ?? false }
        if !byId.isEmpty {
            let picked = pickWeighted(byId, byId.map(weightOf), rand)
            return "source-\(idOf(picked) ?? "")"
        }
        let byPosition = list.enumerated().filter { wired.contains("source-\($0.offset)") }
        if !byPosition.isEmpty {
            let picked = pickWeighted(byPosition, byPosition.map { weightOf($0.element) }, rand)
            return "source-\(picked.offset)"
        }
        return nil
    }

    // MARK: Jump to

    /// The step a jump-to goes to ("" when none is set).
    public static func jumpTarget(_ data: [String: Any]) -> String {
        for v in [data["nodeId"], data["targetNodeId"], data["jumpTo"]] where present(v) && !JS.str(v).trimmed.isEmpty {
            return JS.str(v).trimmed
        }
        return ""
    }

    // MARK: Business hours

    static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    static func validZone(_ zone: Any?) -> TimeZone? {
        let z = JS.text(zone).trimmed
        return z.isEmpty ? nil : TimeZone(identifier: z)
    }

    /// "9:00" -> "09:00"; nil when it isn't a time.
    private static func hhmm(_ t: Any?) -> String? {
        guard let m = Re("^([0-9]{1,2}):([0-9]{2})").match(JS.text(t).trimmed), let hs = m[1], let ms = m[2],
              let h = Int(hs), let mi = Int(ms), h <= 24, mi <= 59 else { return nil }
        return "\(String(h % 24).padStart(2)):\(ms)"
    }

    /// "25-12-2026", "2026-12-25" (or with / or .) -> "2026-12-25"; else nil.
    public static func normaliseDate(_ d: Any?) -> String? {
        let text = JS.text(d).trimmed
        if let m = Re("^([0-9]{4})[-/.]([0-9]{1,2})[-/.]([0-9]{1,2})$").match(text) {
            return "\(m[1]!)-\(m[2]!.padStart(2))-\(m[3]!.padStart(2))"
        }
        if let m = Re("^([0-9]{1,2})[-/.]([0-9]{1,2})[-/.]([0-9]{4})$").match(text) {
            return "\(m[3]!)-\(m[2]!.padStart(2))-\(m[1]!.padStart(2))"
        }
        return nil
    }

    struct ZonedNow {
        let date: String
        let time: String
        let dayIndex: Int
        let dayName: String
    }

    /// The time, date and weekday in a zone (an empty or invalid zone uses the fallback).
    static func zonedNow(_ now: Date, _ zone: Any?, _ fallbackZone: String?) -> ZonedNow {
        let tz = validZone(zone) ?? validZone(fallbackZone) ?? TimeZone.current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: now)
        let dayIndex = (c.weekday ?? 1) - 1
        return ZonedNow(
            date: "\(c.year!)-\(String(c.month!).padStart(2))-\(String(c.day!).padStart(2))",
            time: "\(String(c.hour!).padStart(2)):\(String(c.minute!).padStart(2))",
            dayIndex: dayIndex,
            dayName: dayNames[dayIndex]
        )
    }

    private static func previousDate(_ ymd: String) -> String {
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard p.count == 3, let d = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2] - 1)) else { return ymd }
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(String(c.month!).padStart(2))-\(String(c.day!).padStart(2))"
    }

    /// Whether the business is open at `now`, read in the owner's timezone.
    /// An overnight slot (22:00 - 02:00) is open from its start until
    /// midnight and, the next day, until its end.
    public static func isWithinBusinessHours(_ data: [String: Any], now: Date, fallbackZone: String? = nil) -> Bool {
        let at = zonedNow(now, data["timezone"], fallbackZone)
        let weekly = JS.dicts(data["weeklyHours"])
        let excludedDays = Set(JS.array(data["excludeDays"]).map { JS.str($0).trimmed.lowercased() })
        let excludedDates = Set(JS.array(data["excludeDates"]).compactMap { normaliseDate($0) })

        func isClosedDay(_ dayName: String, _ date: String) -> Bool {
            excludedDays.contains(dayName.lowercased()) || excludedDates.contains(date)
        }
        func hoursFor(_ dayIndex: Int) -> [String: Any]? {
            weekly.first(where: { JS.text($0["dayName"]).trimmed.lowercased() == dayNames[dayIndex].lowercased() })
                ?? weekly.first(where: { JS.toNumber($0["day"]) == Double(dayIndex) && present($0["day"]) && JS.text($0["day"]) != "" })
        }
        func slotsOf(_ day: [String: Any]?) -> [(start: String, end: String)] {
            guard let day = day, JS.truthy(day["available"]), let slots = day["slots"] as? [Any] else { return [] }
            return slots.compactMap { s in
                let d = JS.dict(s)
                guard let a = hhmm(d["start"]), let b = hhmm(d["end"]) else { return nil }
                return (a, b)
            }
        }

        if at.dayIndex < 0 || isClosedDay(at.dayName, at.date) { return false }
        for s in slotsOf(hoursFor(at.dayIndex)) {
            if s.start <= s.end ? (s.start <= at.time && at.time <= s.end) : at.time >= s.start { return true }
        }
        let yIndex = (at.dayIndex + 6) % 7
        let yDate = previousDate(at.date)
        if !isClosedDay(dayNames[yIndex], yDate) {
            for s in slotsOf(hoursFor(yIndex)) where s.end < s.start && at.time <= s.end { return true }
        }
        return false
    }
}
