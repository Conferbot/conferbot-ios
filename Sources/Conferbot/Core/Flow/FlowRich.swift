//
//  FlowRich.swift
//  Conferbot
//
//  The rich steps' rules, the pure half - ported from the web widget
//  (conferbot-widget/src/ts/chat/richNodes.ts) through the React Native SDK
//  (src/core/flow/rich.ts), with the widget's English texts. Keep it in step
//  with the web file.
//
//  Values a step saves under several names are ordered lists of
//  (name, value): the order is the order they are saved in, which the
//  answer variables keep.
//

import Foundation

public typealias FlowVars = [(String, Any)]

enum FlowRich {

    static let types: Set<String> = [
        "dynamic-choices-node", "hidden-fields-node", "consent-node", "product-card-node", "slider-node", "datetime-node",
        "ranking-node", "otp-node", "address-node", "matrix-node", "ai-extract-node", "ai-route-node", "kb-answer-node",
        "signature-node", "payment-node",
    ]

    static func plainText(_ v: Any?) -> String { FlowText.plainText(v) }
    static func t(_ key: String, _ vars: [String: Any]? = nil) -> String { FlowI18n.t(key, vars) }

    // MARK: Paths into data ("data.items", "items[0].name")

    /// Read a dotted path; nil when any step is missing.
    static func getPath(_ value: Any?, _ path: Any?) -> Any? {
        let p = JS.text(path).trimmed
        if p.isEmpty { return value }
        let parts = p.replacing("\\[([0-9]+)\\]", with: ".$1").split(separator: ".").map(String.init).filter { !$0.isEmpty }
        var cur = value
        for key in parts {
            if JS.isNullish(cur) { return nil }
            if let o = cur as? [String: Any] { cur = o[key] }
            else if let a = cur as? [Any] {
                guard let i = Int(key), i >= 0, i < a.count else { return nil }
                cur = a[i]
            } else { return nil }
        }
        return cur
    }

    /// A variable's value as data: JSON text (a webhook reply saved as text) is parsed.
    static func asData(_ value: Any?) -> Any? {
        guard let s = value as? String else { return value }
        let t = s.trimmed
        guard t.hasPrefix("[") || t.hasPrefix("{"), let parsed = JS.parse(t) else { return value }
        return parsed
    }

    // MARK: (1) Dynamic choices

    struct DynamicOption {
        let id: String
        let label: String
        /// What is saved: the item's value as it came (number, text, boolean).
        let value: Any
    }

    static let dynamicEmptyHandle = "source-empty"

    static func dynamicSourceVariable(_ data: [String: Any]) -> String { JS.text(data["sourceVariable"]).trimmed }

    private static func scalar(_ v: Any?) -> Bool { v is NSNull || v is String || JS.isNumber(v) || JS.isBool(v) }

    /// The options a dynamic choice node offers, from the value of its source variable.
    static func dynamicOptions(_ data: [String: Any], _ sourceValue: Any?) -> [DynamicOption] {
        let root = asData(sourceValue)
        guard let list = asData(getPath(root, data["listPath"])) as? [Any] else { return [] }
        let labelField = JS.text(data["labelField"]).trimmed
        let valueField = JS.text(data["valueField"]).trimmed
        let maxRaw = JS.toNumber(data["maxOptions"]).rounded(.down)
        let maxOpt = max(1, min(50, maxRaw.isFinite && maxRaw != 0 ? Int(maxRaw) : 10))
        var seen = Set<String>()
        var out: [DynamicOption] = []
        for item in list {
            if out.count >= maxOpt { break }
            var label: Any?
            var value: Any?
            if scalar(item) {
                if item is NSNull { continue }
                label = item
                value = item
            } else if let o = item as? [String: Any] {
                label = labelField.isEmpty ? [o["label"], o["name"], o["title"], o["text"]].first(where: { !JS.isNullish($0) }) ?? nil : getPath(o, labelField)
                value = valueField.isEmpty ? [o["value"], o["id"], label].first(where: { !JS.isNullish($0) }) ?? nil : getPath(o, valueField)
            } else {
                continue
            }
            let text = plainText(scalar(label) ? label : "")
            if text.isEmpty { continue }
            if !scalar(value) || JS.isNullish(value) { value = text }
            let key = "\(text)\u{0000}\(JS.str(value))"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(DynamicOption(id: "opt-\(out.count)", label: text, value: value!))
        }
        return out
    }

    // MARK: (2) Hidden fields

    static func hiddenParams(_ data: [String: Any]) -> [(name: String, variable: String)] {
        JS.dicts(data["params"]).map { (JS.text($0["name"]).trimmed, JS.text($0["variable"]).trimmed) }.filter { !$0.0.isEmpty && !$0.1.isEmpty }
    }

    private static func clip(_ v: Any?) -> String { JS.text(v).trimmed.jsSlice(0, 500) }

    static func isWebAddress(_ v: Any?) -> Bool { JS.text(v).matches("^https?://", .caseInsensitive) }

    /// What a hidden fields node captures, in the order it saves them.
    static func captureHiddenFields(_ data: [String: Any], href: String?, referrer: String?) -> FlowVars {
        var out: FlowVars = []
        func put(_ k: String, _ v: String) {
            out.removeAll { $0.0 == k }
            out.append((k, v))
        }
        let query = href.flatMap { URLComponents(string: $0)?.queryItems } ?? []
        for p in hiddenParams(data) {
            if let v = query.first(where: { $0.name == p.name })?.value, !clip(v).isEmpty { put(p.variable, clip(v)) }
        }
        let pageVar = JS.text(data["pageUrlVariable"]).trimmed
        if JS.bool(data["capturePageUrl"]) != false, !pageVar.isEmpty, isWebAddress(href) { put(pageVar, clip(href)) }
        let refVar = JS.text(data["referrerVariable"]).trimmed
        if JS.bool(data["captureReferrer"]) != false, !refVar.isEmpty, isWebAddress(referrer) { put(refVar, clip(referrer)) }
        return out
    }

    // MARK: (3) Consent - markdown-lite text

    static func safeLink(_ url: Any?) -> String {
        let raw = JS.text(url).trimmed
        if raw.matches("^(https?://|mailto:)\\S+$", .caseInsensitive) { return raw }
        if raw.matches("^[a-z0-9-]+(\\.[a-z0-9-]+)+(/\\S*)?$", .caseInsensitive) { return "https://\(raw)" }
        return ""
    }

    private static let mdLink = Re("\\[([^\\]\\n]{1,200})\\]\\(((?:[^()\\s]|\\([^()\\s]*\\)){1,500})\\)")

    /// The text as plain words: "I agree to the Terms and Privacy Policy".
    static func markdownLitePlain(_ md: Any?) -> String {
        JS.text(md)
            .replacing(mdLink.re.pattern, with: "$1")
            .replacing("\\*\\*([^*\\n]+)\\*\\*", with: "$1")
            .replacing("(^|[\\s(])[*_]([^*_\\n]+)[*_](?=[\\s).,!?:;]|$)", with: "$1$2")
            .replacing("\\s+", with: " ")
            .trimmed
    }

    /// The documents a consent text links to: ["Terms", "Privacy Policy"].
    static func consentDocuments(_ md: Any?) -> [String] {
        var out: [String] = []
        for g in mdLink.matches(JS.text(md)) {
            let t = (g[1] ?? "").trimmed
            if !t.isEmpty, !safeLink(g[2]).isEmpty, !out.contains(t) { out.append(t) }
        }
        return out
    }

    /// "Terms and Privacy Policy", "A, B and C".
    static func joinAnd(_ items: [String]) -> String {
        items.count <= 1 ? items.joined() : "\(items.dropLast().joined(separator: ", ")) \(t("common.and")) \(items[items.count - 1])"
    }

    static func consentReply(_ md: Any?, _ agreed: Bool) -> String {
        if !agreed { return t("consent.declined") }
        let docs = consentDocuments(md)
        return docs.isEmpty ? t("consent.agreed") : t("consent.agreedTo", ["docs": joinAnd(docs)])
    }

    static func consentContinueLabel(_ data: [String: Any]) -> String {
        let s = JS.text(data["continueLabel"]).trimmed
        return s.isEmpty ? t("common.continue") : s
    }

    /// Required unless the owner made it optional.
    static func consentRequired(_ data: [String: Any]) -> Bool { JS.bool(data["required"]) != false }

    // MARK: (4) Product card

    static let productCardId = "product"

    /// The product as carousel data, so the carousel's rules read it.
    static func productCarouselData(_ data: [String: Any]) -> [String: Any] {
        let buttons = Array(JS.array(data["buttons"]).prefix(3))
        return ["cards": [[
            "id": productCardId,
            "image": data["image"] ?? "",
            "title": data["title"] ?? "",
            "description": data["description"] ?? "",
            "price": data["price"] ?? "",
            "buttons": buttons,
        ] as [String: Any]]]
    }

    // MARK: (5a) Slider

    private static func numOr(_ v: Any?, _ d: Double) -> Double {
        if JS.isNullish(v) || (v as? String) == "" { return d }
        let n = JS.toNumber(v)
        return n.isFinite ? n : d
    }

    struct SliderConfig {
        let min: Double
        let max: Double
        let step: Double
        let start: Double
        let unit: String
        let unitPosition: String
    }

    private static func decimalsOf(_ n: Double) -> Int {
        let s = JS.numberText(n)
        return s.contains(".") ? s.components(separatedBy: ".")[1].count : 0
    }

    /// Onto the step grid (counted from min), inside the range.
    static func snapToStep(_ value: Double, _ min: Double, _ max: Double, _ step: Double) -> Double {
        // Math.round: halves go up
        let steps = ((value - min) / step + 0.5).rounded(.down)
        let v = Swift.min(max, Swift.max(min, min + steps * step))
        let digits = Swift.max(decimalsOf(step), decimalsOf(min))
        return Double(String(format: "%.\(digits)f", v)) ?? v
    }

    static func sliderConfig(_ data: [String: Any]) -> SliderConfig {
        let min = numOr(data["min"], 0)
        var max = numOr(data["max"], 100)
        if max <= min { max = min + 1 }
        var step = numOr(data["step"], 1)
        if !(step > 0) || step > max - min {
            let s = Swift.min(1, max - min)
            step = s == 0 ? 1 : s
        }
        let wanted = numOr(data["defaultValue"], (min + max) / 2)
        return SliderConfig(
            min: min, max: max, step: step,
            start: snapToStep(wanted, min, max, step),
            unit: JS.text(data["unit"]).trimmed,
            unitPosition: JS.text(data["unitPosition"]) == "prefix" ? "prefix" : "suffix"
        )
    }

    /// "50 kg", "$50".
    static func sliderLabel(_ value: Double, _ cfg: SliderConfig) -> String {
        let v = JS.numberText(value)
        if cfg.unit.isEmpty { return v }
        return cfg.unitPosition == "prefix" ? "\(cfg.unit)\(v)" : "\(v) \(cfg.unit)"
    }

    static func submitLabel(_ data: [String: Any]) -> String {
        let s = JS.text(data["submitLabel"]).trimmed
        return s.isEmpty ? t("common.send") : s
    }

    // MARK: (5b) Date / time picker

    static func dateMode(_ data: [String: Any]) -> String {
        let m = JS.text(data["mode"])
        return m == "time" || m == "datetime" ? m : "date"
    }

    static let weekdays = FlowLogic.dayNames
    private static let dateRe = Re("^([0-9]{4})-([0-9]{2})-([0-9]{2})$")
    private static let timeRe = Re("^([01][0-9]|2[0-3]):([0-5][0-9])$")

    static func validYmd(_ s: Any?) -> Bool {
        guard let m = dateRe.match(JS.text(s)), let y = Int(m[1]!), let mo = Int(m[2]!), let d = Int(m[3]!) else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: DateComponents(year: y, month: mo, day: d)) else { return false }
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return c.year == y && c.month == mo && c.day == d
    }

    private static func ymd(_ date: Date, _ zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(String(c.year!).padStart(4))-\(String(c.month!).padStart(2))-\(String(c.day!).padStart(2))"
    }

    /// A bound as a date: "2026-10-05", "today", "+7" / "-3" (days from today).
    static func resolveDateBound(_ bound: Any?, today: Date, zone: TimeZone) -> String? {
        let b = JS.text(bound).trimmed.lowercased()
        if b.isEmpty { return nil }
        if b == "today" { return ymd(today, zone) }
        if let m = Re("^([+-])([0-9]{1,4})$").match(b) {
            let days = (m[1] == "-" ? -1 : 1) * (Int(m[2]!) ?? 0)
            return ymd(today.addingTimeInterval(Double(days) * 86400), zone)
        }
        return validYmd(b) ? b : nil
    }

    static func disabledWeekdays(_ data: [String: Any]) -> [Int] {
        var out: [Int] = []
        for v in JS.array(data["disabledWeekdays"]) {
            let n: Double = JS.toNumber(v)
            if n.isFinite && n == n.rounded() && n >= 0 && n <= 6 { out.append(Int(n)) }
        }
        return out
    }

    private static func weekdayOf(_ ymd: String) -> Int {
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard p.count == 3, let d = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return 0 }
        return cal.component(.weekday, from: d) - 1
    }

    /// Why an ISO value isn't allowed, or nil. Same rules as the channels'.
    static func dateTimeError(_ data: [String: Any], _ iso: String, today: Date, zone: TimeZone) -> String? {
        let mode = dateMode(data)
        let parts = iso.components(separatedBy: "T")
        let datePart = mode == "datetime" ? parts[0] : mode == "time" ? "" : iso
        let timePart = mode == "datetime" ? (parts.count > 1 ? parts[1] : "") : mode == "time" ? iso : ""
        if mode != "time" {
            if !validYmd(datePart) { return t("dates.pickDate") }
            if let min = resolveDateBound(data["minDate"], today: today, zone: zone), datePart < min { return t("dates.onOrAfter", ["date": min]) }
            if let max = resolveDateBound(data["maxDate"], today: today, zone: zone), datePart > max { return t("dates.onOrBefore", ["date": max]) }
            let wd = weekdayOf(datePart)
            if disabledWeekdays(data).contains(wd) { return t("dates.dayUnavailable", ["day": "\(weekdays[wd])s"]) }
        }
        if mode != "date" {
            if !timeRe.test(timePart) { return t("dates.pickTime") }
            let minT = JS.text(data["minTime"])
            if JS.truthy(data["minTime"]), timeRe.test(minT), timePart < minT { return t("dates.timeFrom", ["time": minT]) }
            let maxT = JS.text(data["maxTime"])
            if JS.truthy(data["maxTime"]), timeRe.test(maxT), timePart > maxT { return t("dates.timeUntil", ["time": maxT]) }
        }
        return nil
    }

    /// A picker's value as our ISO ("2026-10-05T14:30:00" -> "2026-10-05T14:30").
    static func isoFromInput(_ mode: String, _ value: Any?) -> String {
        let v = JS.text(value).trimmed
        if mode == "time" { return v.jsSlice(0, 5) }
        if mode == "datetime" { return v.jsSlice(0, 16) }
        return v.jsSlice(0, 10)
    }

    private static let shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func timeText(_ h: Int, _ m: Int) -> String {
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return "\(hour12):\(String(m).padStart(2)) \(h < 12 ? "AM" : "PM")"
    }

    /// The picked value for people (Intl en-US: "Oct 19, 2026", "2:30 PM", "Oct 19, 2026, 2:30 PM").
    static func dateTimeDisplay(_ data: [String: Any], _ iso: String) -> String {
        let mode = dateMode(data)
        if mode == "time" {
            let p = iso.split(separator: ":").map { Int($0) ?? 0 }
            guard p.count >= 2 else { return iso }
            return timeText(p[0], p[1])
        }
        let parts = iso.components(separatedBy: "T")
        let d = parts[0].split(separator: "-").map { Int($0) ?? 0 }
        guard d.count == 3, d[1] >= 1, d[1] <= 12 else { return iso }
        let date = "\(shortMonths[d[1] - 1]) \(d[2]), \(d[0])"
        if mode == "date" { return date }
        let tp = (parts.count > 1 ? parts[1] : "00:00").split(separator: ":").map { Int($0) ?? 0 }
        return "\(date), \(timeText(tp.first ?? 0, tp.count > 1 ? tp[1] : 0))"
    }

    // MARK: (6) Ranking

    struct RankItem {
        let id: String
        let text: String
    }

    static func rankingItems(_ data: [String: Any]) -> [RankItem] {
        Array(JS.array(data["items"]).enumerated().map { i, it -> RankItem in
            let d = JS.dict(it)
            return RankItem(id: JS.isNullish(d["id"]) ? String(i) : JS.str(d["id"]), text: plainText(d["text"]))
        }.filter { !$0.text.isEmpty }.prefix(10))
    }

    static func rankingText(_ order: [RankItem]) -> String {
        order.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: " · ")
    }

    // MARK: (7) Verification code (OTP)

    static let otpLength = 6
    static let otpResendSeconds = 30

    static func isEmailAddress(_ v: Any?) -> Bool {
        guard let s = v as? String, s.jsLength <= 254 else { return false }
        return s.trimmed.matches("^[^\\s@<>()\\[\\],;:\"]+@[^\\s@<>()\\[\\],;:\"]+\\.[^\\s@<>()\\[\\],;:\"]{2,}$")
    }

    static func otpChannel(_ data: [String: Any]) -> String { JS.text(data["channel"]) == "sms" ? "sms" : "email" }

    /// The address to verify without asking, when the step takes it from a variable.
    static func otpPresetEmail(_ data: [String: Any], _ lookup: VariableLookup) -> String {
        guard JS.text(data["emailSource"]) == "variable" else { return "" }
        let key = JS.text(data["emailVariable"]).trimmed
        let v = key.isEmpty ? "" : JS.text(lookup(key)).trimmed
        return isEmailAddress(v) ? v.lowercased() : ""
    }

    /// What to tell the visitor for a server answer (send or verify).
    static func otpErrorText(_ code: Any?, attemptsLeft: Any? = nil, retryAfter: Any? = nil) -> String {
        switch JS.text(code) {
        case "invalid_email": return t("otp.invalidEmail")
        case "wrong_code":
            let n = JS.toNumber(attemptsLeft)
            if JS.isNullish(attemptsLeft) || !n.isFinite { return t("otp.wrong") }
            return t(n == 1 ? "otp.wrongLeft.one" : "otp.wrongLeft.other", ["n": JS.num(n)])
        case "invalid_code": return t("otp.allDigits", ["n": otpLength])
        case "expired": return t("otp.expired")
        case "no_code": return t("otp.noCode")
        case "locked": return t("otp.locked")
        case "resend_wait":
            let n = JS.toNumber(retryAfter)
            return t("otp.resendWait", ["n": max(1, n.isFinite && n != 0 ? Int(n) : otpResendSeconds)])
        case "too_many_sends", "rate_limited": return t("otp.tooMany")
        case "sms_unavailable": return t("otp.smsUnavailable")
        default: return t("common.somethingWrong")
        }
    }

    /// Failures that end the step on its "not verified" path.
    static func otpEndsStep(_ code: Any?) -> Bool { ["locked", "sms_unavailable", "node_not_found", "send_failed"].contains(JS.text(code)) }

    static func otpReplyText(_ verified: Bool, _ email: String) -> String {
        verified ? t("otp.verifiedAs", ["email": email]) : t("otp.notVerified")
    }

    // MARK: (8) Address

    struct AddressValue {
        var formatted = ""
        var line1 = ""
        var city = ""
        var region = ""
        var postal = ""
        var country = ""
        var countryCode = ""
        var lat: Double?
        var lng: Double?

        var dict: [String: Any] {
            [
                "formatted": formatted, "line1": line1, "city": city, "region": region, "postal": postal,
                "country": country, "countryCode": countryCode, "lat": lat.map { JS.num($0) } ?? NSNull(), "lng": lng.map { JS.num($0) } ?? NSNull(),
            ]
        }
    }

    private static func clip200(_ v: Any?) -> String { JS.text(v).replacing("\\s+", with: " ").trimmed.jsSlice(0, 200) }

    private static func finiteOrNil(_ v: Any?) -> Double? {
        if JS.isNullish(v) || (v as? String) == "" { return nil }
        let n = JS.toNumber(v)
        return n.isFinite ? n : nil
    }

    static func formatAddress(_ v: AddressValue) -> String {
        let city = clip200(v.city)
        let region = clip200(v.region)
        let postal = clip200(v.postal)
        let regionPostal = [region != city ? region : "", postal].filter { !$0.isEmpty }.joined(separator: " ")
        let cityLine = [city, regionPostal].filter { !$0.isEmpty }.joined(separator: ", ")
        return [clip200(v.line1), cityLine, clip200(v.country)].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func normalizeAddress(_ raw: Any?) -> AddressValue {
        let v = JS.dict(raw)
        var out = AddressValue()
        out.formatted = clip200(v["formatted"])
        out.line1 = clip200(v["line1"])
        out.city = clip200(v["city"])
        out.region = clip200(v["region"])
        out.postal = clip200(v["postal"])
        out.country = clip200(v["country"])
        let cc = JS.text(v["countryCode"]).trimmed
        out.countryCode = cc.matches("^[a-z]{2}$", .caseInsensitive) ? cc.lowercased() : ""
        out.lat = finiteOrNil(v["lat"])
        out.lng = finiteOrNil(v["lng"])
        if out.lat == nil || out.lng == nil || abs(out.lat!) > 90 || abs(out.lng!) > 180 {
            out.lat = nil
            out.lng = nil
        }
        if out.formatted.isEmpty { out.formatted = formatAddress(out) }
        return out
    }

    /// The visitor's own entry; nil when not enough.
    static func manualAddress(_ fields: [String: Any]) -> AddressValue? {
        var f = fields
        f["formatted"] = ""
        f["countryCode"] = ""
        f["lat"] = NSNull()
        f["lng"] = NSNull()
        var v = normalizeAddress(f)
        if v.line1.isEmpty { return nil }
        v.formatted = formatAddress(v)
        return v
    }

    /// The variables an address saves: k (formatted), k_line1, k_city... (empty parts left out).
    static func addressVariables(_ key: Any?, _ value: AddressValue) -> FlowVars {
        let k = JS.text(key).trimmed
        guard !k.isEmpty else { return [] }
        var out: FlowVars = [(k, value.formatted)]
        let parts: [(String, Any?)] = [
            ("line1", value.line1), ("city", value.city), ("region", value.region), ("postal", value.postal),
            ("country", value.country), ("country_code", value.countryCode), ("lat", value.lat.map { JS.num($0) }), ("lng", value.lng.map { JS.num($0) }),
        ]
        for (suffix, v) in parts {
            guard let v = v, !JS.isNullish(v), (v as? String) != "" else { continue }
            out.append(("\(k)_\(suffix)", v))
        }
        return out
    }

    static func addressErrorText(_ code: Any?) -> String {
        switch JS.text(code) {
        case "denied": return t("address.denied")
        case "unavailable": return t("address.unavailable")
        case "busy", "rate_limited": return t("address.busy")
        case "no_results": return t("address.noResults")
        default: return t("address.failed")
        }
    }

    // MARK: (9) Matrix / Likert grid

    struct MatrixItem {
        let id: String
        let text: String
    }

    private static func matrixItems(_ list: Any?, _ maxCount: Int, _ prefix: String) -> [MatrixItem] {
        var seen = Set<String>()
        var out: [MatrixItem] = []
        for (i, it) in JS.array(list).enumerated() {
            let d = JS.dict(it)
            let text = plainText(d["text"])
            if text.isEmpty || out.count >= maxCount { continue }
            var id = JS.isNullish(d["id"]) ? "\(prefix)\(i)" : JS.str(d["id"])
            if seen.contains(id) { id = "\(id)_\(i)" }
            seen.insert(id)
            out.append(MatrixItem(id: id, text: text))
        }
        return out
    }

    static func matrixRows(_ data: [String: Any]) -> [MatrixItem] { matrixItems(data["rows"], 12, "r") }
    static func matrixColumns(_ data: [String: Any]) -> [MatrixItem] { matrixItems(data["columns"], 7, "c") }
    static func matrixMode(_ data: [String: Any]) -> String { JS.text(data["mode"]) == "multiple" ? "multiple" : "single" }
    static func matrixRequireAll(_ data: [String: Any]) -> Bool { JS.bool(data["requireAll"]) != false }

    /// What the visitor ticked: row id -> column ids (one for single).
    typealias MatrixSelection = [String: [String]]

    static func matrixToggle(_ sel: MatrixSelection, _ rowId: String, _ colId: String, _ mode: String, on: Bool = true) -> MatrixSelection {
        let cur = sel[rowId] ?? []
        let next: [String]
        if mode == "single" { next = on ? [colId] : cur.filter { $0 != colId } }
        else { next = on ? (cur.contains(colId) ? cur : cur + [colId]) : cur.filter { $0 != colId } }
        var out = sel
        out[rowId] = next.isEmpty ? nil : next
        return out
    }

    static func matrixMissing(_ sel: MatrixSelection, _ rows: [MatrixItem]) -> [MatrixItem] {
        rows.filter { (sel[$0.id] ?? []).isEmpty }
    }

    /// The saved value in row order: [(row text, column | [columns])]; unanswered rows left out.
    static func matrixValue(_ sel: MatrixSelection, _ rows: [MatrixItem], _ cols: [MatrixItem], _ mode: String) -> FlowVars {
        rows.compactMap { r in
            let picked = cols.filter { (sel[r.id] ?? []).contains($0.id) }.map { $0.text }
            if picked.isEmpty { return nil }
            return (r.text, mode == "single" ? picked[0] as Any : picked as Any)
        }
    }

    static func matrixRowAnswers(_ sel: MatrixSelection, _ rows: [MatrixItem], _ cols: [MatrixItem], _ mode: String) -> [[String: Any]] {
        rows.map { r in
            let picked = cols.filter { (sel[r.id] ?? []).contains($0.id) }.map { $0.text }
            let answer: Any = picked.isEmpty ? NSNull() : (mode == "single" ? picked[0] as Any : picked as Any)
            return ["id": r.id, "text": r.text, "answer": answer]
        }
    }

    /// "Speed: Good · Price: Fair, Poor" - the visitor's reply.
    static func matrixDisplay(_ value: FlowVars) -> String {
        value.map { k, v in "\(k): \((v as? [String])?.joined(separator: ", ") ?? JS.str(v))" }.joined(separator: " · ")
    }

    /// What blocks Submit, or "".
    static func matrixError(_ sel: MatrixSelection, _ rows: [MatrixItem], _ requireAll: Bool) -> String {
        let missing = matrixMissing(sel, rows)
        if requireAll && !missing.isEmpty { return t("matrix.everyRow", ["n": missing.count]) }
        if missing.count == rows.count { return t("matrix.oneRow") }
        return ""
    }

    // MARK: (10) AI extract / AI intent router

    static let aiMinThinkMs: Double = 500
    static let aiClientTimeoutMs: Double = 15000
    static let aiMaxInput = 2000

    static func aiSource(_ data: [String: Any]) -> String {
        let s = JS.text(data["source"])
        return s == "last_message" || s == "variable" ? s : "ask"
    }

    /// The text a step reads without asking. nil = ask; "" = nothing there yet (ask too).
    static func aiPresetText(_ data: [String: Any], lastUserText: String, variableValue: Any?) -> String? {
        let source = aiSource(data)
        if source == "ask" { return nil }
        let v: Any? = source == "variable" ? variableValue : lastUserText
        if JS.isNullish(v) { return "" }
        let text = v is [Any] || v is [String: Any] ? JS.json(v) : JS.str(v)
        return text.trimmed.jsSlice(0, aiMaxInput)
    }

    /// The visitor's latest message in a transcript of (by, message).
    static func lastUserMessage(_ transcript: [(by: String, message: String?)]) -> String {
        for e in transcript.reversed() where e.by == "user" {
            if let m = e.message, !plainText(m).isEmpty { return plainText(m) }
        }
        return ""
    }

    struct AiField {
        let name: String
        let type: String
        let required: Bool
    }

    static func aiFields(_ data: [String: Any]) -> [AiField] {
        let types = ["text", "number", "email", "phone", "date", "boolean", "list"]
        var out: [AiField] = []
        for f in JS.dicts(data["fields"]) {
            let name = JS.text(f["name"]).trimmed
            guard name.matches("^[A-Za-z_][A-Za-z0-9_]*$"), !out.contains(where: { $0.name == name }) else { continue }
            let type = JS.text(f["type"])
            out.append(AiField(name: name, type: types.contains(type) ? type : "text", required: JS.bool(f["required"]) == true))
            if out.count == 15 { break }
        }
        return out
    }

    struct AiExtractResult {
        let values: [String: Any]
        let missing: [String]
        let ok: Bool
        let error: String?
    }

    struct AiRouteResult {
        let intentId: String?
        let intent: String?
        let confidence: Double
        let fallback: Bool
        let error: String?
    }

    static func aiExtractResult(_ data: [String: Any], _ json: Any?, failed: String?) -> AiExtractResult {
        let required = aiFields(data).filter { $0.required }.map { $0.name }
        guard failed == nil, let j = json as? [String: Any] else {
            return AiExtractResult(values: [:], missing: required, ok: false, error: failed ?? "bad_reply")
        }
        let values = (j["values"] as? [String: Any]) ?? [:]
        let missing: [String] = (j["missing"] as? [Any]).map { $0.map { JS.str($0) } } ?? required.filter { values[$0] == nil }
        let error: String? = JS.truthy(j["error"]) ? JS.str(j["error"]) : nil
        return AiExtractResult(values: values, missing: missing, ok: JS.bool(j["ok"]) == true && missing.isEmpty, error: error)
    }

    static func aiRouteResult(_ json: Any?, failed: String?) -> AiRouteResult {
        let j = json as? [String: Any]
        let conf = JS.toNumber(j?["confidence"])
        let confidence = conf.isFinite ? conf : 0
        if failed != nil || j == nil || JS.truthy(j?["fallback"]) || !JS.truthy(j?["intentId"]) {
            let err = failed ?? (JS.truthy(j?["error"]) ? JS.str(j?["error"]) : "no_match")
            return AiRouteResult(intentId: nil, intent: nil, confidence: confidence, fallback: true, error: err)
        }
        return AiRouteResult(intentId: JS.str(j!["intentId"]), intent: JS.text(j!["intent"]), confidence: confidence, fallback: false, error: nil)
    }

    /// The variables an extract saves: each field, the whole object, and what's missing.
    static func aiExtractVariables(_ data: [String: Any], _ r: AiExtractResult) -> FlowVars {
        var out: FlowVars = []
        var all: [String: Any] = [:]
        for f in aiFields(data) {
            guard let v = r.values[f.name] else { continue }
            out.append((f.name, v))
            all[f.name] = v
        }
        let key = JS.text(data["answerVariable"]).trimmed
        if !key.isEmpty {
            out.append((key, all))
            out.append(("\(key)_missing", r.missing))
        }
        return out
    }

    /// The variables a route saves: the intent's name ("" on no match) and the confidence.
    static func aiRouteVariables(_ data: [String: Any], _ r: AiRouteResult) -> FlowVars {
        let key = JS.text(data["answerVariable"]).trimmed
        guard !key.isEmpty else { return [] }
        return [(key, r.fallback ? "" : (r.intent ?? "")), ("\(key)_confidence", JS.num(((r.confidence) * 100).rounded() / 100))]
    }

    // MARK: (11) Knowledge-base answer

    static let kbClientTimeoutMs: Double = 18000
    static let kbMaxAnswer = 700

    struct KbSource {
        let title: String
        let url: String
        let articleId: String?
        var dict: [String: Any] {
            var d: [String: Any] = ["title": title, "url": url, "type": articleId != nil ? "article" : "page"]
            if let a = articleId { d["articleId"] = a }
            return d
        }
    }

    struct KbResult {
        let found: Bool
        let answer: String
        let sources: [KbSource]
        let error: String?
    }

    static func kbMaxSources(_ data: [String: Any]) -> Int {
        let n = JS.toNumber(data["maxSources"]).rounded(.down)
        return n.isFinite ? min(5, max(1, Int(n))) : 3
    }

    static func kbResult(_ data: [String: Any], _ json: Any?, errorCode: String?) -> KbResult {
        let j = json as? [String: Any]
        let answer = plainText(j?["answer"]).jsSlice(0, kbMaxAnswer + 1)
        guard let body = j, JS.bool(body["found"]) == true, !answer.isEmpty else {
            let err = errorCode ?? ((j?["error"] as? String) ?? "not_found")
            return KbResult(found: false, answer: "", sources: [], error: err)
        }
        var seen = Set<String>()
        var sources: [KbSource] = []
        if JS.bool(data["showSources"]) != false {
            for s in JS.dicts(body["sources"]) {
                if sources.count >= kbMaxSources(data) { break }
                let rawUrl = JS.text(s["url"])
                let url = rawUrl.matches("^https?://", .caseInsensitive) ? rawUrl : ""
                let rawId = JS.text(s["articleId"])
                let articleId = rawId.matches("^[a-f0-9]{24}$", .caseInsensitive) ? rawId : ""
                let key = articleId.isEmpty ? url : "a:\(articleId)"
                if key.isEmpty || seen.contains(key) { continue }
                seen.insert(key)
                var title = plainText(s["title"]).jsSlice(0, 160)
                if title.isEmpty { title = url.isEmpty ? t("kb.helpArticle") : url.replacing("^https?://", with: "") }
                sources.append(KbSource(title: title, url: url, articleId: articleId.isEmpty ? nil : articleId))
            }
        }
        return KbResult(found: true, answer: answer, sources: sources, error: nil)
    }

    static func kbVariables(_ data: [String: Any], _ r: KbResult) -> FlowVars {
        let k = JS.text(data["answerVariable"]).trimmed
        guard !k.isEmpty else { return [] }
        return [
            (k, r.found ? r.answer : ""),
            ("\(k)_found", r.found),
            ("\(k)_sources", r.found ? r.sources.map { ["title": $0.title, "url": $0.url] } : [[String: Any]]()),
        ]
    }

    static func kbNotFoundHtml(_ data: [String: Any]) -> String {
        plainText(data["notFoundMessage"]).isEmpty ? "<p>\(t("kb.notFound"))</p>" : JS.str(data["notFoundMessage"])
    }

    // MARK: (12) Signature

    struct SignatureConfig {
        let allowTyped: Bool
        let requireName: Bool
    }

    static func signatureConfig(_ data: [String: Any]) -> SignatureConfig {
        SignatureConfig(allowTyped: JS.bool(data["allowTyped"]) != false, requireName: JS.bool(data["requireName"]) == true)
    }

    static func cleanSignatureName(_ v: Any?) -> String { JS.text(v).replacing("\\s+", with: " ").trimmed.jsSlice(0, 120) }

    /// A name that can stand as a signature: 2+ characters with at least one letter.
    static func isSignatureName(_ v: Any?) -> Bool {
        let t = JS.text(v).replacing("\\s+", with: " ").trimmed
        return t.jsLength >= 2 && t.jsLength <= 120 && t.matches("\\p{L}")
    }

    static func signatureVariables(_ k: String, url: String, at: String, name: String, method: String) -> FlowVars {
        let key = k.trimmed
        guard !key.isEmpty else { return [] }
        var out: FlowVars = [(key, url), ("\(key)_at", at), ("\(key)_method", method)]
        if !name.isEmpty { out.append(("\(key)_name", name)) }
        return out
    }

    // MARK: Payment (payment-node)

    static let paymentFailedHandle = "source-failed"
    static let paymentTimeoutHandle = "source-timeout"
    static let paymentPeekMs: Double = 5000

    private static let zeroDecimal = ["bif", "clp", "djf", "gnf", "jpy", "kmf", "krw", "mga", "pyg", "rwf", "ugx", "vnd", "vuv", "xaf", "xof", "xpf"]
    private static let threeDecimal = ["bhd", "jod", "kwd", "omr", "tnd"]

    static func paymentDecimals(_ currency: Any?) -> Int {
        let c = JS.text(currency).lowercased()
        return zeroDecimal.contains(c) ? 0 : threeDecimal.contains(c) ? 3 : 2
    }

    /// Minor units -> "$25.00" (en-US; falls back to "USD 25.00").
    static func paymentAmountText(_ minor: Any?, _ currency: Any?) -> String {
        let c = JS.text(currency).trimmed.uppercased()
        let n = JS.toNumber(minor)
        guard c.matches("^[A-Z]{3}$"), n.isFinite, !JS.isNullish(minor) else { return "" }
        let major = n / pow(10, Double(paymentDecimals(c)))
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .currency
        f.currencyCode = c
        return f.string(from: NSNumber(value: major)) ?? "\(c) \(String(format: "%.\(paymentDecimals(c))f", major))"
    }

    static func paymentTimeoutMs(_ data: [String: Any]) -> Double {
        let n = JS.toNumber(data["timeoutMinutes"]).rounded(.down)
        return (n.isFinite && n >= 1 ? min(n, 1440) : 15) * 60 * 1000
    }

    static func paymentOutcome(_ status: Any?) -> String? {
        ["paid": "paid", "failed": "failed", "cancelled": "failed", "timeout": "timeout", "expired": "timeout"][JS.text(status)]
    }

    static func paymentHandle(_ outcome: String) -> String {
        outcome == "paid" ? "source" : outcome == "timeout" ? paymentTimeoutHandle : paymentFailedHandle
    }

    /// Only a Stripe-hosted page may be opened from the card.
    static func isCheckoutUrl(_ url: Any?) -> Bool { JS.text(url).matches("^https://([a-z0-9-]+\\.)*stripe\\.com/", .caseInsensitive) }
    static func isReceiptUrl(_ url: Any?) -> Bool { isCheckoutUrl(url) }

    /// The variables a settled payment writes (mirror of paymentService.paymentVariables).
    static func paymentVariables(_ key: String, status: String, amount: Double?, currency: String, receiptUrl: String, paymentId: String) -> FlowVars {
        let k = key.trimmed
        guard !k.isEmpty else { return [] }
        let major: Any = amount.map { JS.num($0 / pow(10, Double(paymentDecimals(currency)))) } ?? NSNull()
        let cur = currency.uppercased()
        let receipt = isReceiptUrl(receiptUrl) ? receiptUrl : ""
        return [
            (k, ["status": status, "amount": major, "currency": cur, "receiptUrl": receipt, "paymentId": paymentId] as [String: Any]),
            ("\(k)_status", status),
            ("\(k)_amount", major),
            ("\(k)_currency", cur),
            ("\(k)_receipt_url", receipt),
        ]
    }

    static func paymentReplyText(_ outcome: String, _ amountText: String) -> String {
        if outcome == "paid" && !amountText.isEmpty { return t("pay.paidAmount", ["amount": amountText]) }
        return t(outcome == "paid" ? "pay.paid" : outcome == "timeout" ? "pay.timedOut" : "pay.cancelled")
    }

    static func paymentErrorText(_ code: Any?) -> String {
        switch JS.text(code) {
        case "not_configured": return t("pay.notConfigured")
        case "invalid_amount": return t("pay.invalidAmount")
        case "rate_limited": return t("pay.rateLimited")
        case "network", "timeout": return t("pay.network")
        default: return t("pay.failed")
        }
    }
}
