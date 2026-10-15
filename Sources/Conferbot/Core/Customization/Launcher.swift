//
//  Launcher.swift
//  Conferbot
//
//  The closed chat button as the web widget draws it on a phone
//  (conferbot-widget templates/shared.ts generateWidgetIcon,
//  ts/launcher/launcherStyle.ts, launcherShape.ts, layout/ownerLayout.ts
//  and the phone rules in css/liveChat/responsive*.css). Pure: the floating
//  widget reads the result.
//

import Foundation

public struct ResolvedLauncher: Equatable {
    public var position = "right"
    /// The button's height (and width, except for tab, peek and the label pill).
    public var size: Double = 50
    /// Width of the button: the size, or the tab's narrower width.
    public var width: Double = 50
    /// Distance from the bottom and from the screen side (0 for tab and peek).
    public var bottom: Double = 16
    public var side: Double = 16
    /// Peek: how far the tab is tucked off screen.
    public var tucked: Double = 0
    public var shape = "bubble"
    public var corners = BubbleCorners(topLeft: 25, topRight: 25, bottomRight: 6, bottomLeft: 25)
    /// The two stops of a left-to-right gradient, or nil for a solid launcher.
    public var gradient: [String]?
    /// The launcher's own colour as one solid (a gradient's first stop).
    public var solid = "#1b55f3"
    /// Icon ink: dark on a light launcher, else white.
    public var ink = "#ffffff"
    /// The soft glow round the button: the header colour.
    public var glow = "#1b55f3"
    /// The style drawn: an uploaded image or a missing avatar fall back to the icon.
    public var style = "icon"
    public var label = Launcher.defaultLabel
    public var avatar: String?
    public var imageUrl: String?
    public var iconId: String?
    /// Icon size inside the button.
    public var glyph: Double = 30
    public var animation = "subtle"
    /// The greeting next to the button, when the owner turned it on.
    public var ctaText: String?

    public init() {}
}

public enum Launcher {
    public static let shapes = ["circle", "squircle", "bubble", "tab", "peek"]
    public static let styles = ["icon", "label", "avatar", "mascot"]
    public static let labelMax = 24
    public static let defaultLabel = "Chat with us"
    /// The web folds the label back to the round button at this width and under.
    public static let labelMinWidth: Double = 480

    private static func str(_ v: Any?) -> String { ((v as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func num(_ v: Any?) -> Double? {
        if let n = v as? Double, n.isFinite { return n }
        if let n = v as? Int { return Double(n) }
        if let s = v as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// A number in [lo, hi] (clamped, rounded), or nil when unset / junk (ownerLayout ownerRange).
    private static func range(_ v: Any?, _ lo: Double, _ hi: Double) -> Double? {
        num(v).map { min(hi, max(lo, $0.rounded())) }
    }

    /// The shape: unset is the speech bubble, unless the owner rounded the button (a radius under 50) themselves.
    public static func normalizeShape(_ value: Any?, radius: Any?) -> String {
        if let s = value as? String, shapes.contains(s) { return s }
        if let r = num(radius), r < 50 { return "circle" }
        return "bubble"
    }

    public static func normalizeLabel(_ value: Any?) -> String {
        guard let s = value as? String else { return "" }
        let collapsed = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(labelMax))
    }

    private static func channel(_ c: Double) -> Double {
        let s = c / 255
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }

    public static func resolve(_ raw: [String: Any]?, screenWidth: Double = 0) -> ResolvedLauncher {
        let c = raw ?? [:]
        var r = ResolvedLauncher()
        r.position = (c["widgetPosition"] as? String) == "left" ? "left" : "right"
        // Phones: the owner's phone size and offsets, else the launcher's size at 16px from the edges.
        let size = range(c["mobileWidgetSize"], 36, 80) ?? num(c["widgetSize"]).flatMap { $0 > 0 ? $0 : nil } ?? 50
        r.size = size
        r.width = size
        r.bottom = range(c["mobileOffsetBottom"], 0, 400) ?? 16
        r.side = range(c["mobileOffsetSide"], 0, 400) ?? 16
        r.shape = normalizeShape(c["launcherShape"], radius: c["widgetBorderRadius"])

        let isGradient = (c["widgetIconThemeType"] as? String) == "Gradient" && !str(c["widgetGradientBgOne"]).isEmpty && !str(c["widgetGradientBgTwo"]).isEmpty
        let solidRaw = isGradient ? c["widgetGradientBgOne"] : c["widgetIconBgColor"]
        r.solid = WidgetTheme.parseColor(solidRaw) != nil ? str(solidRaw) : (str(c["headerBgColor"]).isEmpty ? "#1b55f3" : str(c["headerBgColor"]))
        if let rgb = WidgetTheme.parseColor(r.solid) {
            let lum = 0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b)
            r.ink = lum > 0.6 ? "#111827" : "#ffffff"
        }
        r.gradient = isGradient ? [str(c["widgetGradientBgOne"]), str(c["widgetGradientBgTwo"])] : nil
        r.glow = str(c["headerBgColor"]).isEmpty ? r.solid : str(c["headerBgColor"])

        r.imageUrl = (c["widgetIconType"] as? String) == "Image" && !str(c["widgetIconImage"]).isEmpty ? str(c["widgetIconImage"]) : nil
        let avatar = [str(c["avatar"]), str(c["logo"])].first { !$0.isEmpty }
        r.avatar = avatar
        var style = (c["launcherStyle"] as? String).flatMap { styles.contains($0) ? $0 : nil } ?? "icon"
        if r.imageUrl != nil || (style == "avatar" && avatar == nil) { style = "icon" }
        // The label folds back to the round button on phones, as on the web.
        if style == "label" && !(screenWidth > labelMinWidth) { style = "icon" }
        r.style = style

        let half = (size / 2).rounded()
        switch r.shape {
        case "squircle":
            r.corners = .all((size * 0.3).rounded())
        case "bubble":
            // The corner nearest the screen corner pinched into a tail.
            let tail = max(4, (size * 0.12).rounded())
            r.corners = r.position == "left"
                ? BubbleCorners(topLeft: half, topRight: half, bottomRight: half, bottomLeft: tail)
                : BubbleCorners(topLeft: half, topRight: half, bottomRight: tail, bottomLeft: half)
        case "tab", "peek":
            // Flush to the screen edge, rounded on its inner side.
            r.width = (size * 0.82).rounded()
            r.side = 0
            let round = (size * 0.3).rounded()
            if r.shape == "peek" { r.tucked = (r.width * 0.42).rounded() }
            r.corners = r.position == "left"
                ? BubbleCorners(topLeft: 0, topRight: round, bottomRight: round, bottomLeft: 0)
                : BubbleCorners(topLeft: round, topRight: 0, bottomRight: 0, bottomLeft: round)
        default:
            // The round button: the owner's corner radius, capped at half the size.
            let radius = num(c["widgetBorderRadius"]).map { min(half, max(0, $0)) } ?? half
            r.corners = .all(radius)
        }

        r.label = normalizeLabel(c["launcherLabel"]).isEmpty ? defaultLabel : normalizeLabel(c["launcherLabel"])
        r.iconId = str(c["widgetIconSVG"]).isEmpty ? nil : str(c["widgetIconSVG"])
        r.glyph = (size * (r.shape == "tab" || r.shape == "peek" ? 0.5 : 0.6)).rounded()
        if let a = c["launcherAnimation"] as? String, a == "lively" || a == "off" { r.animation = a }
        // Only when the owner turned the greeting on (templates/shared.ts: no chatIconCta, no bubble).
        r.ctaText = (c["chatIconCta"] as? Bool) == true && !str(c["chatIconCtaText"]).isEmpty ? str(c["chatIconCtaText"]) : nil
        return r
    }
}
