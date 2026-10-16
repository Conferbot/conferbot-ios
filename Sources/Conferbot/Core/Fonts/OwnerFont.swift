//
//  OwnerFont.swift
//  Conferbot
//
//  The owner's font and the theme's font, as the web widget picks them.
//  Ported from the React Native SDK (src/core/ownerFont.ts), itself from
//  conferbot-widget src/ts/fonts/ownerFont.ts (findCatalogFont, the
//  "CB Font " prefixed family, ownerFontUrl), src/ts/theme/themeTokens.ts
//  (isDefaultFont, parseFontFaces, themeFontUrl, the owner's font over the
//  theme's: --cb-o-font) and src/ts/theme/applyTheme.ts (loadThemeFont).
//
//  Which font the chat's text uses:
//    - the owner's font (customizations.font) when it is not a default
//      ("", "Arial", "Gill Sans, sans-serif"): everything, body and headings;
//    - else the theme's font: a "body" theme font for all text, a "display"
//      one for headings only (the header's title, card titles);
//    - else the system font.
//  A catalog web font (or a theme font) is fetched from Google Fonts at run
//  time (TrueType, as Google sends to a client that is not a browser) and
//  registered with Core Text for this process (FontLoader.swift); a system
//  or unknown font is used by its family name when the phone (or the app)
//  has it, else the system font. Pure.
//

import Foundation

public enum OwnerFont {

    public struct CatalogFont: Equatable {
        public let id: String
        public let label: String
        public let family: String
        public let category: String
        public let stack: String
        public let google: String?
    }

    public static let prefix = "CB Font "

    /// Fonts that mean "the owner never picked one" (dashboard / model defaults).
    static let defaultFonts: Set<String> = ["", "arial", "gill sans, sans-serif", "gill sans"]
    static let systemSans = "-apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"

    static func bareFont(_ font: Any?) -> String {
        var v = (font as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        while let last = v.last, last == ";" || last.isWhitespace { v.removeLast() }
        v = v.trimmingCharacters(in: .whitespacesAndNewlines)
        if v == systemSans { return "" }
        if v.hasSuffix(", \(systemSans)") { v = String(v.dropLast(systemSans.count + 2)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return v
    }

    public static func isDefaultFont(_ font: Any?) -> Bool {
        guard font is String else { return true }
        return defaultFonts.contains(bareFont(font).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "").lowercased())
    }

    static func unquote(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first family named in a font-family value, unquoted.
    public static func firstFamily(_ value: Any?) -> String {
        guard let s = value as? String else { return "" }
        return unquote(s.components(separatedBy: ",").first ?? "")
    }

    static let byName: [String: CatalogFont] = {
        var out: [String: CatalogFont] = [:]
        for f in catalog {
            out[f.family.lowercased()] = f
            out[f.id] = f
        }
        return out
    }()

    /// The catalog font a saved value names (by family, id, or our prefixed name), or nil.
    public static func findCatalogFont(_ value: Any?) -> CatalogFont? {
        var name = firstFamily(value).lowercased()
        if name.isEmpty { return nil }
        let p = prefix.lowercased()
        if name.hasPrefix(p) { name = String(name.dropFirst(p.count)) }
        return byName[name]
    }

    public static func googleFontUrl(_ query: String) -> String { "https://fonts.googleapis.com/css2?family=\(query)&display=swap" }

    public struct FontFace: Equatable {
        public let weight: Int
        public let style: String
        public let url: String
    }

    /// A Google Fonts stylesheet's faces: each @font-face block's weight,
    /// style and its TrueType / OpenType url (a woff2-only block is skipped:
    /// Core Text registers neither woff nor woff2 data). Variable ranges
    /// ("100 900") read as their start.
    public static func parseFontFaces(_ css: String) -> [FontFace] {
        var faces: [FontFace] = []
        for block in matches(css, #"@font-face\s*\{[^}]*\}"#) {
            guard let src = capture(block, #"src:\s*([^;]+);"#),
                  let url = capture(src, #"url\(\s*['"]?([^'")]+)['"]?\s*\)\s*format\(\s*['"]?(?:truetype|opentype)['"]?\s*\)"#, caseInsensitive: true)
            else { continue }
            let weight = Int(capture(block, #"font-weight:\s*(\d+)"#) ?? "400") ?? 400
            let style = block.range(of: #"font-style:\s*italic"#, options: .regularExpression) != nil ? "italic" : "normal"
            faces.append(FontFace(weight: weight, style: style, url: url))
        }
        return faces
    }

    private static func matches(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func capture(_ s: String, _ pattern: String, caseInsensitive: Bool = false) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []),
              let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)), m.numberOfRanges > 1,
              m.range(at: 1).location != NSNotFound else { return nil }
        return (s as NSString).substring(with: m.range(at: 1))
    }

    /// The name a face is known by in the SDK: the 400 face plain, others with their weight.
    public static func faceName(_ family: String, _ weight: Int) -> String {
        weight == 400 ? "\(prefix)\(family)" : "\(prefix)\(family) \(weight)"
    }

    /// A font the chat uses: its family, and the Google Fonts query to fetch
    /// it (nil: a system or unknown font, used by name).
    public struct FontPick: Equatable {
        public let family: String
        public let google: String?
        public init(family: String, google: String?) {
            self.family = family
            self.google = google
        }
    }

    public struct ChatFonts: Equatable {
        /// The owner's or the body theme font: all of the chat's text.
        public let body: FontPick?
        /// Headings: the owner's font, else the theme's (body or display).
        public let display: FontPick?
    }

    // A system pick: "system-ui" is the platform font (nothing to set).
    private static func systemPick(_ family: String) -> FontPick? {
        family.isEmpty || family == "system-ui" ? nil : FontPick(family: family, google: nil)
    }

    /// The fonts the chat uses for the owner's setting and the theme's font
    /// (WidgetTheme `font`, `fontRole`). The owner's own font wins over the
    /// theme's for both (web themeTokens --cb-o-font / --cb-o-font-display).
    public static func chatFontsFor(_ ownerFont: Any?, themeFont: String?, themeFontRole: String?) -> ChatFonts {
        if !isDefaultFont(ownerFont) {
            let pick: FontPick?
            if let cat = findCatalogFont(ownerFont) {
                pick = cat.google.map { FontPick(family: cat.family, google: $0) } ?? systemPick(cat.family)
            } else {
                pick = systemPick(firstFamily(ownerFont))
            }
            if let pick = pick { return ChatFonts(body: pick, display: pick) }
        }
        guard let tf = themeFont, !tf.isEmpty else { return ChatFonts(body: nil, display: nil) }
        let pick = FontPick(family: tf, google: themeFontQueries[tf] ?? findCatalogFont(tf)?.google)
        return themeFontRole == "display" ? ChatFonts(body: nil, display: pick) : ChatFonts(body: pick, display: pick)
    }

    /// The loaded weight nearest to `weight` (ties go heavier for bold text,
    /// lighter for normal); nil when nothing is loaded.
    public static func nearestWeight(_ loaded: [Int], _ weight: Int) -> Int? {
        loaded.sorted { a, b in
            let d = abs(a - weight) - abs(b - weight)
            if d != 0 { return d < 0 }
            return weight >= 600 ? a > b : a < b
        }.first
    }

    /// The face to draw `weight` with (RN fontFamilyFor): a web font's
    /// nearest loaded face by its SDK name, a system font by its family, nil
    /// until a web font is loaded (the system font draws it).
    public static func fontFamilyFor(_ pick: FontPick?, loaded: [Int]?, weight: Int = 400) -> String? {
        guard let pick = pick else { return nil }
        guard pick.google != nil else { return pick.family }
        guard let best = nearestWeight(loaded ?? [], weight) else { return nil }
        return faceName(pick.family, best)
    }
}
