//
//  WidgetTheme.swift
//  Conferbot
//
//  The widget theme as the web widget applies it (conferbot-widget
//  src/ts/theme/themeTokens.ts, base.css and the theme sheets):
//
//    widgetTheme      one of 27 themes ("classic" when unset or unknown)
//    themeAppearance  light | dark | auto (auto follows the phone)
//    themeColors      brand (the owner's colours) | theme (the theme's palette)
//
//  Classic in light is the widget as it always was: no tokens, no shape.
//  Classic in dark repaints the surfaces only. Every other theme brings its
//  surfaces, text colours and shape; an owner setting (bubble radius, option
//  radius, a chat background of their own) still wins over the theme. Pure.
//

import Foundation

/// Surfaces and text, every value a six-digit hex (rgba flattened onto the surface).
public struct ThemeTokens: Equatable {
    /// Panel, conversation, composer and footer.
    public var bg: String
    /// Canvas: home screen, help centre.
    public var bg2: String
    /// Cards, menus, chips.
    public var card: String
    /// Quiet fills: search field, tags.
    public var card2: String
    /// The composer's field.
    public var field: String
    public var menu: String
    public var ink: String
    public var text: String
    public var muted: String
    public var faint: String
    public var line: String
    public var line2: String
}

public struct BubbleBorder: Equatable {
    public var width: Double
    public var color: String
}

public struct ThemeShape: Equatable {
    public var rBubble: Double
    public var rTail: Double
    /// Option buttons (999 is a pill).
    public var rCtl: Double
    /// The composer's field.
    public var rField: Double
    public var rCard: Double
    /// An outline round every bubble (cartoon, neo-brutal, sketch...), or nil.
    public var bubbleBorder: BubbleBorder?
    public var displayWeight: Int
}

public struct ResolvedWidgetTheme: Equatable {
    public var id = "classic"
    public var label = "Classic"
    public var appearance = "light"
    public var scheme = "light"
    public var colors = "brand"
    /// Nil for classic in light: nothing changes.
    public var tokens: ThemeTokens?
    /// Nil for classic: radii stay the widget's.
    public var shape: ThemeShape?
    /// The theme's font family (a Google Fonts name) and what it covers.
    public var font: String?
    public var fontRole: String?

    public var isDark: Bool { scheme == "dark" }

    public init() {}
}

public enum WidgetTheme {
    public static var themes: [String] { WidgetThemesData.themes.map { $0.id } }

    private static func lower(_ v: Any?) -> String {
        ((v as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func normalizeTheme(_ v: Any?) -> String {
        WidgetThemesData.byId[lower(v)] != nil ? lower(v) : "classic"
    }

    public static func normalizeAppearance(_ v: Any?) -> String {
        let s = lower(v)
        return s == "dark" || s == "auto" ? s : "light"
    }

    public static func normalizeThemeColors(_ v: Any?) -> String { lower(v) == "theme" ? "theme" : "brand" }

    /// Light or dark: always-dark themes, then the appearance (auto: the phone's setting).
    public static func resolveScheme(_ theme: String, appearance: String, prefersDark: Bool) -> String {
        if WidgetThemesData.byId[theme]?.alwaysDark == true { return "dark" }
        if appearance == "dark" { return "dark" }
        if appearance == "auto" { return prefersDark ? "dark" : "light" }
        return "light"
    }

    /// r, g, b (0-255) and alpha (0-1).
    public struct RGBA: Equatable {
        public var r: Double, g: Double, b: Double, a: Double = 1
    }

    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }

    /// "#abc", "#aabbcc", "#aabbccdd", "rgb(1,2,3)", "rgba(1,2,3,.5)", white, black.
    public static func parseColor(_ value: Any?) -> RGBA? {
        let v = lower(value)
        if v == "white" { return RGBA(r: 255, g: 255, b: 255) }
        if v == "black" { return RGBA(r: 0, g: 0, b: 0) }
        if let m = match("^#([0-9a-f]{3,8})$", v) {
            var h = m[1]
            if h.count == 3 || h.count == 4 { h = h.map { "\($0)\($0)" }.joined() }
            guard h.count == 6 || h.count == 8 else { return nil }
            let chars = Array(h)
            func byte(_ i: Int) -> Double { Double(Int(String(chars[i..<i + 2]), radix: 16) ?? 0) }
            return RGBA(r: byte(0), g: byte(2), b: byte(4), a: h.count == 8 ? byte(6) / 255 : 1)
        }
        if let m = match("^rgba?\\(\\s*([\\d.]+)[\\s,]+([\\d.]+)[\\s,]+([\\d.]+)(?:[\\s,/]+([\\d.]+))?\\s*\\)$", v) {
            func c(_ s: String) -> Double { min(255, max(0, (Double(s) ?? 0).rounded())) }
            let a = m[4].isEmpty ? 1 : min(1, max(0, Double(m[4]) ?? 1))
            return RGBA(r: c(m[1]), g: c(m[2]), b: c(m[3]), a: a)
        }
        return nil
    }

    static func hex(_ c: RGBA) -> String {
        "#" + [c.r, c.g, c.b].map { String(format: "%02x", Int(min(255, max(0, $0.rounded())))) }.joined()
    }

    private static func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
        RGBA(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t, a: a.a + (b.a - a.a) * t)
    }

    /// A colour with alpha laid over an opaque one.
    private static func over(_ top: RGBA, _ under: RGBA) -> RGBA {
        var solid = top
        solid.a = 1
        return mix(under, solid, top.a)
    }

    private static func channel(_ c: Double) -> Double {
        let s = c / 255
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }

    private static func luminance(_ c: RGBA) -> Double { 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b) }

    private static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// The brand lightened until it reads on a dark surface (4.5:1 on #14161c), as the web's accentOnDark.
    public static func accentOnDark(_ brand: RGBA) -> RGBA {
        let surface = RGBA(r: 20, g: 22, b: 28)
        var c = brand
        var t = 0.0
        while t <= 1.0001 && contrast(c, surface) < 4.5 {
            let m = mix(brand, RGBA(r: 255, g: 255, b: 255), t)
            c = RGBA(r: m.r.rounded(), g: m.g.rounded(), b: m.b.rounded())
            t += 0.05
        }
        return c
    }

    /// A token value: hex / rgb(a), "mix:N:<colour>" or "accent:<alpha>".
    private static func tokenColor(_ value: String?, brand: RGBA) -> RGBA? {
        guard let value = value else { return nil }
        if let m = match("^mix:([\\d.]+):(.+)$", value) {
            guard let base = parseColor(m[2]) else { return nil }
            return mix(base, brand, (Double(m[1]) ?? 0) / 100)
        }
        if let m = match("^accent:([\\d.]+)$", value) {
            var a = accentOnDark(brand)
            a.a = Double(m[1]) ?? 1
            return a
        }
        return parseColor(value)
    }

    /// The owner's chat background counts as theirs (the theme leaves it
    /// alone) unless it is the default plain white; gradients, patterns and
    /// images always are.
    public static func ownsChatBackground(_ c: [String: Any]?) -> Bool {
        let type = lower(c?["chatBgType"]).isEmpty ? "solid" : lower(c?["chatBgType"])
        if type == "image" || type == "gradient" || type == "pattern" { return true }
        guard let color = parseColor(c?["chatBgColor"]) else { return false }
        return !(color.r >= 250 && color.g >= 250 && color.b >= 250)
    }

    private static func palette(_ theme: String, colors: String, scheme: String) -> [String: String]? {
        guard theme != "classic", colors == "theme", let d = WidgetThemesData.byId[theme] else { return nil }
        return (scheme == "dark" ? d.paletteDark : d.paletteLight) ?? d.paletteLight
    }

    /// The customizations with the theme's palette in place of the owner's
    /// colours (themeColors "theme", any theme but classic); otherwise the
    /// same dictionary back. The chat background goes back to plain white,
    /// which the theme paints with its own surface. Logo, avatar and texts
    /// stay the owner's.
    public static func withThemePalette(_ c: [String: Any], prefersDark: Bool) -> [String: Any] {
        let theme = normalizeTheme(c["widgetTheme"])
        let scheme = resolveScheme(theme, appearance: normalizeAppearance(c["themeAppearance"]), prefersDark: prefersDark)
        guard let p = palette(theme, colors: normalizeThemeColors(c["themeColors"]), scheme: scheme) else { return c }
        var out = c
        out["headerBgColor"] = p["headerBg"]
        out["headerTextColor"] = p["headerText"]
        out["botMsgColor"] = p["botBg"]
        out["botTextColor"] = p["botText"]
        out["userMsgColor"] = p["userBg"]
        out["userTextColor"] = p["userText"]
        out["optionBubbleMsgColor"] = p["optionBg"]
        out["optionBubbleTextColor"] = p["optionText"]
        out["chatBgType"] = "solid"
        out["chatBgColor"] = "#ffffff"
        out["widgetIconThemeType"] = p["launcher2"] != nil ? "Gradient" : "Solid"
        out["widgetIconBgColor"] = p["launcher"]
        out["widgetGradientBgOne"] = p["launcher"]
        out["widgetGradientBgTwo"] = p["launcher2"] ?? p["launcher"]
        out["themeAccent"] = p["accent"]
        out["themeOnAccent"] = p["onAccent"]
        return out
    }

    /// The theme in force for these customizations, with every colour concrete.
    public static func resolve(_ c: [String: Any]?, prefersDark: Bool) -> ResolvedWidgetTheme {
        let theme = normalizeTheme(c?["widgetTheme"])
        var out = ResolvedWidgetTheme()
        out.id = theme
        out.appearance = normalizeAppearance(c?["themeAppearance"])
        out.colors = normalizeThemeColors(c?["themeColors"])
        out.scheme = resolveScheme(theme, appearance: out.appearance, prefersDark: prefersDark)
        guard let data = WidgetThemesData.byId[theme] else { return out }
        out.label = data.label
        out.font = data.font
        out.fontRole = data.fontRole
        let p = palette(theme, colors: out.colors, scheme: out.scheme)
        let brand = parseColor(p?["brand"]) ?? parseColor(c?["headerBgColor"]) ?? parseColor(c?["botMsgColor"])
            ?? RGBA(r: 27, g: 85, b: 243)

        let raw: [String: String]? = theme == "classic" && out.scheme == "light" ? nil
            : (out.isDark ? data.dark : (data.light ?? data.dark))
        if let t = raw {
            let fallback = out.isDark ? RGBA(r: 20, g: 22, b: 28) : RGBA(r: 255, g: 255, b: 255)
            let surface = over(tokenColor(t["bg"], brand: brand) ?? fallback, fallback)
            func flat(_ k: String) -> String { hex(over(tokenColor(t[k], brand: brand) ?? surface, surface)) }
            out.tokens = ThemeTokens(
                bg: hex(surface), bg2: flat("bg2"), card: flat("card"), card2: flat("card2"),
                field: flat("field"), menu: flat("menu"), ink: flat("ink"), text: flat("text"),
                muted: flat("muted"), faint: flat("faint"), line: flat("line"), line2: flat("line2"))
        }

        if let s = data.shape {
            var border: BubbleBorder?
            if s.bubbleBorderWidth > 0, let b = parseColor(s.bubbleBorderColor) {
                let under = out.tokens.flatMap { parseColor($0.bg) } ?? RGBA(r: 255, g: 255, b: 255)
                border = BubbleBorder(width: s.bubbleBorderWidth, color: hex(over(b, under)))
            }
            out.shape = ThemeShape(
                rBubble: s.rBubble ?? 18, rTail: s.rTail ?? 6, rCtl: s.rCtl ?? 12, rField: s.rField ?? 22,
                rCard: s.rCard ?? 16, bubbleBorder: border, displayWeight: s.displayWeight)
        }
        return out
    }
}
