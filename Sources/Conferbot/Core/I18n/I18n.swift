//
//  I18n.swift
//  Conferbot
//
//  The SDK's own words, in the visitor's language. A port of the React
//  Native SDK's src/core/i18n.ts (itself the web widget's
//  conferbot-widget/src/ts/i18n.ts). The tables are the shared
//  scripts/parity/i18n/strings.json of conferbot-react-native (the web's
//  ts/i18n/{en,nl,fr,de,es}.ts with the same keys, plus the words only the
//  SDKs draw, `sdk.*`), copied by scripts/sync-i18n.sh into the bundled
//  resource Resources/i18n-strings.json and read once at run time.
//
//    I18n.t(key, vars)            the active language's string, {name} filled in
//    I18n.tFor(lang, key, vars)   the same for a given language (pure, for tests)
//    I18n.tPlural(base, n)        `base.one` for 1, else `base.other`
//    I18n.resolve(setting, deviceLanguages)
//                                 "auto" (or absent, or unknown) picks the first
//                                 supported device language, else English
//    I18n.setWidgetLanguage(setting)
//                                 when the bot's settings arrive, before the chat
//                                 is drawn (ConferBot does it)
//
//  In an app "auto" means the phone's languages, most preferred first
//  (Locale.preferredLanguages, then the region's locale; the web reads
//  navigator.languages). Only the SDK's chrome lives here; what the owner
//  wrote (greetings, starters, bot messages) is shown as written, except a
//  stock English default the owner never changed (ownerTextOr / stockText).
//
//  A key missing from a language falls back to English, then to the key
//  itself, so a half-finished translation never shows a blank.
//

import Foundation

/// A language the SDK draws its own words in.
public enum WidgetLanguage: String, CaseIterable {
    case en, nl, fr, de, es

    /// The language's own name, for pickers ("Deutsch").
    public var name: String {
        switch self {
        case .en: return "English"
        case .nl: return "Nederlands"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }
}

public enum I18n {

    public static let supported: [WidgetLanguage] = WidgetLanguage.allCases

    // MARK: - The tables (the bundled strings.json)

    struct Tables {
        var strings: [String: [String: String]] = [:]
        var sdkKeys: [String] = []
        var trivia: [String: [[String: Any]]] = [:]
        var words: [String: [[String: Any]]] = [:]
    }

    /// The bundle holding Resources/i18n-strings.json: the package's own
    /// with SwiftPM, the pod's Conferbot.bundle with CocoaPods.
    static var resourceBundle: Bundle? {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let host = Bundle(for: BundleToken.self)
        if let url = host.url(forResource: "Conferbot", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        return host
        #endif
    }

    /// The bundled resource's location (tests compare it with RN's).
    static var resourceURL: URL? { resourceBundle?.url(forResource: "i18n-strings", withExtension: "json") }

    static func parse(_ data: Data) -> Tables {
        var out = Tables()
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return out }
        for (lang, table) in (root["strings"] as? [String: Any]) ?? [:] {
            out.strings[lang] = (table as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
        }
        out.sdkKeys = (root["sdkKeys"] as? [String]) ?? []
        let games = (root["games"] as? [String: Any]) ?? [:]
        for (lang, list) in (games["trivia"] as? [String: Any]) ?? [:] { out.trivia[lang] = list as? [[String: Any]] ?? [] }
        for (lang, list) in (games["words"] as? [String: Any]) ?? [:] { out.words[lang] = list as? [[String: Any]] ?? [] }
        return out
    }

    /// Read once, on first use (thread-safe: a static let).
    static let tables: Tables = {
        guard let url = resourceURL, let data = try? Data(contentsOf: url) else {
            print("[ConferBot] i18n-strings.json is missing from the SDK's resources; the SDK's words show as their keys.")
            return Tables()
        }
        return parse(data)
    }()

    /// One language's table (English for any other).
    public static func table(_ lang: WidgetLanguage) -> [String: String] { tables.strings[lang.rawValue] ?? [:] }

    /// The English table: the keys every language has.
    public static var english: [String: String] { table(.en) }

    // MARK: - Choosing the language

    /// A stored setting: a supported code, else "auto" (old bots have none).
    public static func normalizeSetting(_ raw: Any?) -> String {
        let v = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return WidgetLanguage(rawValue: v) != nil ? v : "auto"
    }

    /// "nl-BE" -> nl; anything unsupported -> nil.
    public static func baseLanguage(of tag: String?) -> WidgetLanguage? {
        guard let tag = tag else { return nil }
        let base = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return WidgetLanguage(rawValue: base)
    }

    /// The language to draw in: the chosen one, or the first supported device language, or English.
    public static func resolve(_ setting: Any?, deviceLanguages: [String]) -> WidgetLanguage {
        if let chosen = WidgetLanguage(rawValue: normalizeSetting(setting)) { return chosen }
        for tag in deviceLanguages {
            if let base = baseLanguage(of: tag) { return base }
        }
        return .en
    }

    /// The phone's languages, most preferred first, as BCP 47 (the web's
    /// navigator.languages): the whole preferred list, then the region's
    /// locale. Repeats dropped.
    public static func deviceLanguagesOf(preferred: [String], current: String?) -> [String] {
        var out: [String] = []
        for raw in preferred + [current ?? ""] {
            let tag = DeviceLanguage.normalize(raw)
            if !tag.isEmpty && !out.contains(tag) { out.append(tag) }
        }
        return out
    }

    /// The phone's languages now.
    public static var deviceLanguages: [String] {
        deviceLanguagesOf(preferred: Locale.preferredLanguages, current: Locale.current.identifier)
    }

    private static let lock = NSLock()
    private static var active: WidgetLanguage = .en
    private static var activeTag = "en"

    /// Picks the language to draw in (the app's `widgetLanguage`, else the
    /// owner's, else "auto"); returns it.
    @discardableResult
    public static func setWidgetLanguage(_ setting: Any?, languages: [String]? = nil) -> WidgetLanguage {
        let languages = languages ?? deviceLanguages
        let lang = resolve(setting, deviceLanguages: languages)
        // A regional tag of the same language keeps its region for dates and
        // numbers (nl-BE writes dates the Belgian way).
        let regional = languages.first { baseLanguage(of: $0) == lang }
        var tag = lang.rawValue
        if let r = regional, r.range(of: "^[A-Za-z]{2}[-_][A-Za-z]{2}$", options: .regularExpression) != nil {
            tag = r.replacingOccurrences(of: "_", with: "-")
        }
        lock.lock()
        active = lang
        activeTag = tag
        lock.unlock()
        return lang
    }

    /// The language being drawn in.
    public static var language: WidgetLanguage {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    /// A BCP 47 tag for dates and numbers ("nl-BE").
    public static var localeTag: String {
        lock.lock(); defer { lock.unlock() }
        return activeTag
    }

    /// The Locale for formatters.
    public static var locale: Locale { Locale(identifier: localeTag) }

    // MARK: - Words

    /// `{name}` placeholders filled; a missing value keeps its braces.
    static func fill(_ text: String, _ vars: [String: Any]?) -> String {
        guard let vars = vars, !vars.isEmpty, text.contains("{") else { return text }
        return placeholder.replace(text) { g in
            guard let v = vars[g[1] ?? ""], !JS.isNullish(v) else { return g[0] ?? "" }
            return JS.str(v)
        }
    }

    private static let placeholder = Re("\\{(\\w+)\\}")

    /// A string in a given language, {name} placeholders filled.
    public static func tFor(_ lang: WidgetLanguage, _ key: String, _ vars: [String: Any]? = nil) -> String {
        tFor(lang, key, vars, in: tables)
    }

    static func tFor(_ lang: WidgetLanguage, _ key: String, _ vars: [String: Any]?, in tables: Tables) -> String {
        let text = tables.strings[lang.rawValue]?[key] ?? tables.strings["en"]?[key] ?? key
        return fill(text, vars)
    }

    /// A string in the active language.
    public static func t(_ key: String, _ vars: [String: Any]? = nil) -> String { tFor(language, key, vars) }

    /// "{n} thing" vs "{n} things": the `.one` key for 1, else `.other`.
    public static func tPlural(_ base: String, _ n: Int, _ vars: [String: Any]? = nil) -> String {
        var all: [String: Any] = ["n": n]
        for (k, v) in vars ?? [:] { all[k] = v }
        return t("\(base).\(n == 1 ? "one" : "other")", all)
    }

    /// Is the active language English (server texts and English-only words).
    public static var isEnglish: Bool { language == .en }

    // MARK: - Dates

    private static func names(_ count: Int, _ format: String, _ date: (Int) -> Date) -> [String] {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(format)
        return (0..<count).map { f.string(from: date($0)) }
    }

    /// The week's day names, Sunday first, in the widget's language: "long",
    /// "short" (Sun, zo, dim.) or "narrow" (S, Z, D). English keeps the
    /// SDK's own spellings when given.
    public static func weekdayNames(_ style: String = "short", english: [String]? = nil) -> [String] {
        if isEnglish, let english = english { return english }
        let template = style == "long" ? "EEEE" : style == "narrow" ? "EEEEE" : "EEE"
        // 2023-01-01 was a Sunday.
        return names(7, template) { Date(timeIntervalSince1970: 1_672_531_200 + Double($0) * 86_400) }
    }

    /// Month names, January first, in the widget's language ("short": Jan, janv.).
    public static func monthNames(_ style: String = "short", english: [String]? = nil) -> [String] {
        if isEnglish, let english = english { return english }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return names(12, style == "long" ? "MMMM" : "MMM") {
            cal.date(from: DateComponents(year: 2023, month: $0 + 1, day: 15)) ?? Date()
        }
    }

    // MARK: - Owner texts

    /// Compared without tags, extra spaces, a final "." or "!", or case.
    static func plainText(_ s: String) -> String {
        var v = s.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        v = v.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if let last = v.last, last == "." || last == "!" { v.removeLast() }
        return v.lowercased()
    }

    private static func isStock(_ value: String, _ key: String, _ stockEnglish: [String]) -> Bool {
        let v = plainText(value)
        return ([english[key] ?? ""] + stockEnglish).contains { !$0.isEmpty && plainText($0) == v }
    }

    /// An owner field that may still hold the stock English default (stored
    /// by an older dashboard): empty or the default is shown in the
    /// visitor's language, a value the owner wrote as written.
    public static func ownerTextOr(_ value: Any?, _ key: String, stockEnglish: [String] = []) -> String {
        guard let s = value as? String, !plainText(s).isEmpty, !isStock(s, key, stockEnglish) else { return t(key) }
        return s
    }

    /// A field a new bot is created with in English ("Hi there 👋"): that
    /// exact stock value is shown in the visitor's language. Empty stays
    /// empty, and anything the owner wrote is theirs.
    public static func stockText(_ value: Any?, _ key: String, stockEnglish: [String] = []) -> String {
        guard let s = value as? String else { return "" }
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        return isStock(s, key, stockEnglish) ? t(key) : s
    }

    // MARK: - The games' lists

    /// The quiz in a language (English for one without its own).
    public static func trivia(_ lang: String) -> [[String: Any]] {
        let list = tables.trivia[lang] ?? []
        return list.isEmpty ? (tables.trivia["en"] ?? []) : list
    }

    /// The word scramble's words in a language (English for one without its own).
    public static func words(_ lang: String) -> [[String: Any]] {
        let list = tables.words[lang] ?? []
        return list.isEmpty ? (tables.words["en"] ?? []) : list
    }
}

#if !SWIFT_PACKAGE
private final class BundleToken {}
#endif
