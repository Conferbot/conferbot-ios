//
//  FlowInputs.swift
//  Conferbot
//
//  Checks on what the visitor types or picks, ported from the web widget
//  (conferbot-widget/src/ts/chat/nodeKit.ts, nodeLogic.ts,
//  utils/emailTypos.ts) through the React Native SDK (src/core/flow/inputs.ts),
//  with the widget's English messages (ts/i18n/en.ts).
//

import Foundation

public enum FlowInputs {

    /// English texts the steps say (web i18n en.ts).
    public enum EN {
        public static let emailInvalid = "Please enter a valid email address"
        public static func emailTypo(_ email: String) -> String { "Did you mean \(email)? Press Enter to send it, or edit it." }
        public static let phoneInvalid = "Please enter a valid phone number"
        public static let numberLike = "Please enter a number, like 42"
        public static func numberBetween(_ min: Double, _ max: Double) -> String { "Please enter a number between \(JS.numberText(min)) and \(JS.numberText(max))" }
        public static func numberMin(_ min: Double) -> String { "Please enter \(JS.numberText(min)) or more" }
        public static func numberMax(_ max: Double) -> String { "Please enter \(JS.numberText(max)) or less" }
        public static let link = "Please enter a link, like example.com"
        public static func uploadOverSize(_ mb: Double) -> String { "That file is over \(JS.numberText(mb)) MB - choose a smaller one." }
        public static func uploadNotAllowed(_ types: String) -> String { "That file can't be sent here - choose \(types)." }
        public static let uploadRetry = "That didn't upload - tap to try again."
        public static let skipped = "Skipped"
        public static let done = "Done"
        public static let somethingWrong = "Something went wrong. Please try again."
    }

    /// The owner's own error text, or the default when they left it empty or
    /// kept the stock English (web i18n ownerTextOr).
    public static func ownerTextOr(_ value: Any?, _ fallback: String, _ stockEnglish: [String] = []) -> String {
        let v = (value as? String).map { FlowText.plainText($0) } ?? ""
        if v.isEmpty || ([fallback] + stockEnglish).contains(where: { FlowText.plainText($0) == v }) { return fallback }
        return value as? String ?? fallback
    }

    private static let emailRe = Re("^(([^<>()\\[\\]\\\\.,;:\\s@\"]+(\\.[^<>()\\[\\]\\\\.,;:\\s@\"]+)*)|(\".+\"))@((\\[[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\])|(([a-zA-Z\\-0-9]+\\.)+[a-zA-Z]{2,}))$")

    public static func isValidEmail(_ value: Any?) -> Bool { emailRe.test(JS.text(value).trimmed.lowercased()) }

    /// "+1 (555) 123-4567" -> "+15551234567"; a leading "00" becomes "+".
    public static func normalizePhone(_ value: Any?) -> String {
        let raw = JS.text(value).trimmed
        let plus = raw.hasPrefix("+") || raw.hasPrefix("00") ? "+" : ""
        var digits = raw.replacing("[\\s().\\-/\\x{00a0}]", with: "").replacing("^\\+", with: "")
        if !plus.isEmpty, digits.hasPrefix("00") { digits = String(digits.dropFirst(2)) }
        return plus + digits
    }

    public static func isValidPhone(_ value: Any?) -> Bool { normalizePhone(value).matches("^\\+?[0-9]{6,15}$") }

    /// "1,200" -> 1200, "3,5" -> 3.5; anything else nil.
    public static func parseNumberInput(_ value: Any?) -> Double? {
        let raw = JS.text(value).trimmed.replacing("[\\s_'\\x{00a0}]", with: "")
        guard raw.matches("^[-+]?([0-9]+|[0-9]{1,3}(,[0-9]{3})+)?([.,][0-9]+)?$"), raw.matches("[0-9]") else { return nil }
        let normalized: String
        if raw.matches("^[-+]?[0-9]{1,3}(,[0-9]{3})+(\\.[0-9]+)?$") {
            normalized = raw.replacingOccurrences(of: ",", with: "")
        } else if let r = raw.range(of: ",") {
            normalized = raw.replacingCharacters(in: r, with: ".")
        } else {
            normalized = raw
        }
        let n = JS.parseNumber(normalized)
        return n.isFinite ? n : nil
    }

    /// A link people would type: no spaces, a dot, a 2+ letter ending.
    public static func isValidLink(_ value: Any?) -> Bool {
        let raw = JS.text(value).trimmed
        if raw.isEmpty || raw.matches("\\s") { return false }
        let noScheme = raw.replacing("^[a-z][a-z0-9+.-]*://", with: "", .caseInsensitive)
        let host = noScheme.components(separatedBy: CharacterSet(charactersIn: "/?#")).first ?? ""
        return host.replacing("^[^@]*@", with: "").matches("^[^.@]+(\\.[^.]+)*\\.[a-z]{2,}(:[0-9]+)?$", .caseInsensitive)
    }

    /// "conferbot.com" -> "https://conferbot.com"; mailto/tel kept; other schemes refused.
    public static func linkHref(_ value: Any?) -> String {
        let raw = JS.text(value).trimmed
        if raw.isEmpty || raw.matches("\\s") { return "" }
        if raw.matches("^(https?://|mailto:|tel:)", .caseInsensitive) { return raw }
        if raw.matches("^[a-z][a-z0-9+.-]*:", .caseInsensitive) || raw.hasPrefix("//") { return "" }
        return isValidLink(raw) ? "https://\(raw)" : ""
    }

    private static func numOrNil(_ v: Any?) -> Double? {
        if JS.isNullish(v) { return nil }
        if let s = v as? String, s.isEmpty { return nil }
        let n = JS.toNumber(v)
        return n.isFinite ? n : nil
    }

    /// ask-number-node: the refusal message, or nil when the answer is fine.
    public static func numberProblem(_ value: Any?, _ data: [String: Any]) -> String? {
        let n = parseNumberInput(value)
        let cond = JS.dict(data["enableConditions"])
        let min = numOrNil(cond["minVal"])
        let max = numOrNil(cond["maxVal"])
        var message: String?
        if let n = n {
            if let lo = min, let hi = max, n < lo || n > hi { message = EN.numberBetween(lo, hi) }
            else if let lo = min, n < lo { message = EN.numberMin(lo) }
            else if let hi = max, n > hi { message = EN.numberMax(hi) }
        } else {
            message = EN.numberLike
        }
        guard let msg = message else { return nil }
        let custom = JS.text(data["invalidNumberResponse"]).replacing("</?[^>]+(>|$)", with: "").trimmed
        if custom.isEmpty { return msg }
        func show(_ v: Any?) -> String { JS.isNullish(v) || (v as? String) == "" ? "" : JS.str(v) }
        return custom.replacingOccurrences(of: "{min}", with: show(cond["minVal"])).replacingOccurrences(of: "{max}", with: show(cond["maxVal"]))
    }

    /// The owner's phone error (new or older field name), or the default.
    public static func phoneErrorText(_ data: [String: Any]) -> String {
        func textOf(_ v: Any?) -> String { JS.text(v).replacing("</?[^>]+(>|$)", with: "").trimmed }
        let own = textOf(data["invalidPhoneResponse"])
        return ownerTextOr(own.isEmpty ? textOf(data["incorrectPhoneNumberResponse"]) : own, EN.phoneInvalid)
    }

    // MARK: - E-mail typos (utils/emailTypos.ts)

    private static let domains = [
        "gmail.com", "googlemail.com", "yahoo.com", "yahoo.co.uk", "hotmail.com", "hotmail.co.uk", "outlook.com", "live.com", "msn.com",
        "icloud.com", "me.com", "aol.com", "proton.me", "protonmail.com", "gmx.com", "gmx.de", "web.de", "yandex.com", "mail.com", "zoho.com",
    ]
    private static let tldFixes = ["con": "com", "cmo": "com", "ocm": "com", "comm": "com", "nt": "net", "orgg": "org"]

    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                d[i][j] = Swift.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = Swift.min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }

    /// "jamie@gmial.com" -> "jamie@gmail.com"; nil when the address looks right.
    public static func suggestEmailFix(_ email: String) -> String? {
        guard let m = Re("^([^\\s@]+)@([^\\s@]+)$").match(email.trimmed.lowercased()), let user = m[1], let domain = m[2] else { return nil }
        if domains.contains(domain) { return nil }
        var best: String?
        var bestD = 3
        for d in domains {
            let dist = distance(Array(domain), Array(d))
            if dist < bestD, dist <= (d.count > 8 ? 2 : 1) {
                bestD = dist
                best = d
            }
        }
        if let best = best { return "\(user)@\(best)" }
        let parts = domain.components(separatedBy: ".")
        if parts.count >= 2, let fix = tldFixes[parts[parts.count - 1]] {
            return "\(user)@\((parts.dropLast() + [fix]).joined(separator: "."))"
        }
        return nil
    }

    // MARK: - Files

    public static let defaultMaxFileMB: Double = 5

    /// The allowed types in words: "PNG or IMAGE/JPEG", "images or PDF".
    public static func fileTypesWords(_ types: Any?) -> String {
        var unique: [String] = []
        for t in JS.array(types) {
            let x = JS.str(t).trimmed.lowercased()
            if x.isEmpty { continue }
            var word: String
            if x.hasSuffix("/") {
                word = x == "image/" ? "images" : x == "video/" ? "videos" : x.replacingOccurrences(of: "/", with: "")
            } else {
                word = x.replacing("^\\.", with: "").replacing("^application/", with: "").uppercased()
            }
            if word == "JPEG" { word = "JPG" }
            if !unique.contains(word) { unique.append(word) }
        }
        if unique.isEmpty { return "" }
        return unique.count == 1 ? unique[0] : "\(unique.dropLast().joined(separator: ", ")) or \(unique[unique.count - 1])"
    }

    /// Why a picked file can't be sent, or nil (web nodeLogic.fileUploadProblem).
    public static func fileUploadProblem(_ file: [String: Any], _ data: [String: Any]) -> String? {
        let maxSetting = JS.toNumber(data["maxFileSizeMB"])
        let maxMb = maxSetting > 0 ? maxSetting : defaultMaxFileMB
        if JS.toNumber(file["size"]) > maxMb * 1024 * 1024 { return EN.uploadOverSize(maxMb) }
        let allowed = JS.array(data["allowedFileTypes"]).map { JS.str($0).trimmed.lowercased() }.filter { !$0.isEmpty }
        if allowed.isEmpty { return nil }
        let name = JS.text(file["name"]).lowercased()
        let ext = name.contains(".") ? (name.components(separatedBy: ".").last ?? "") : ""
        let mime = JS.text(file["type"]).lowercased()
        let ok = allowed.contains { t in
            if t.contains("/") {
                if t.hasSuffix("/") || t.hasSuffix("/*") { return mime.hasPrefix(t.replacing("\\*$", with: "")) }
                return mime == t
            }
            return ext == t.replacing("^\\.", with: "")
        }
        if ok { return nil }
        let words = fileTypesWords(allowed)
        return EN.uploadNotAllowed(words.isEmpty ? allowed.joined(separator: ", ") : words)
    }

    /// Optional upload: flagged, or "(optional)" in the question.
    public static func isOptionalUpload(_ data: [String: Any]) -> Bool {
        JS.bool(data["optional"]) == true || JS.text(data["questionText"]).matches("\\(optional\\)", .caseInsensitive)
    }
}
