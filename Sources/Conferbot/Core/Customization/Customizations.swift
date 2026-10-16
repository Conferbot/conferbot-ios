//
//  Customizations.swift
//  Conferbot
//
//  The bot's customizations as the web widget applies them (conferbot-widget
//  core/customizations.ts buildCustomizationsRef and the polish / owner
//  sheets): defaults, the values that count as unset, and what each one turns
//  into on screen. Pure: the SwiftUI and UIKit screens read the result.
//

import Foundation

public struct BubbleCorners: Equatable {
    public var topLeft: Double
    public var topRight: Double
    public var bottomRight: Double
    public var bottomLeft: Double

    public static func all(_ r: Double) -> BubbleCorners { BubbleCorners(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }
}

public struct ResolvedCustomizations: Equatable {
    /// "Powered by Conferbot" hidden (the server forces false on Free/Starter).
    public var hideBrand = false
    /// The owner's footer text instead of "Powered by", when turned on.
    public var customBrand: String?
    /// Header title: logoText (or the bot name), cut to 18 characters.
    public var title = "Chat"
    /// Header logo: the owner's, else the Conferbot logo (as the web).
    public var logo = Customizations.defaultLogo
    public var hideLogo = false
    /// Under the title: the tagline when turned on, else "Online" (unless hidden).
    public var tagline: String?
    public var showOnline = true
    /// Bot avatar beside messages (the logo when no avatar of its own).
    public var avatar = Customizations.defaultLogo
    public var hideAvatar = false
    public var avatarSize: Double = 32
    public var avatarShape = "circle"
    public var avatarRadius: Double = 16
    /// Bubble corners: the web's 18/6 shapes unless the owner set a radius.
    public var botBubble = BubbleCorners(topLeft: 18, topRight: 18, bottomRight: 18, bottomLeft: 6)
    public var userBubble = BubbleCorners(topLeft: 18, topRight: 18, bottomRight: 6, bottomLeft: 18)
    public var optionRadius: Double = 10
    /// An outline round each bubble, from the theme (cartoon, neo-brutal...), or nil.
    public var bubbleBorder: BubbleBorder?
    /// The composer field's corner radius: 25 (a pill) unless the theme has its own.
    public var fieldRadius: Double = 25
    /// The chat surface the theme paints when the owner kept the default white, else nil.
    public var surface: String?
    /// Message text size: 14.5 unless the owner set something other than 14.
    public var fontSize: Double = 14.5
    /// Colours as hex strings, with the web's defaults and fallbacks.
    public var headerBg = "#0b4eb8"
    public var headerText = "#ffffff"
    public var botBubbleColor = "#0b4eb8"
    public var botTextColor = "#ffffff"
    public var userBubbleColor = "#f0f0f0"
    public var userTextColor = "#000000"
    public var optionBubbleColor = "#0b4eb8"
    public var optionTextColor = "#ffffff"
    /// dots, wave, shimmer, pencil or mascot.
    public var typingStyle = "dots"
    /// The owner's mascot (art3d mascotLookOf): the idle call, the mascot typing and launcher styles, the greeting card.
    public var mascot = MascotArt.Look()
    /// The colour the mascot is drawn in when the owner chose none: the launcher's (widgetIconBgColor, else the header's).
    public var mascotAccent = "#4f46e5"
    /// The mascot greets on the greeting card, by its name, in place of the avatar.
    public var mascotInGreeting = false
    /// How the greeting card and its figure move: lively, subtle or off.
    public var mascotMotion = MascotMotion.defaultMode
    /// The mascot's size in the launcher, % of the button (70-150, default 112).
    public var mascotLauncherScale = MascotArt.scaleDefault
    /// Send button: the theme palette's accent when it supplied the colours, else the header colour.
    public var accent = "#0b4eb8"
    /// Ink on the send button: the theme palette's, else nil (picked for contrast).
    public var accentInk: String?
    /// The widget theme in force (WidgetTheme).
    public var theme = ResolvedWidgetTheme()

    public init() {}
}

public enum Customizations {
    /// The web widget's default logo (utils/constants BOT_LOGO): header and bot avatar.
    public static let defaultLogo = "https://www.conferbot.com/img/logo/conferbot-logo.png"

    private static let typingStyles: Set<String> = ["dots", "wave", "shimmer", "pencil", "mascot"]

    private static func str(_ v: Any?) -> String { ((v as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func num(_ v: Any?) -> Double? {
        if let n = v as? Double, n.isFinite { return n }
        if let n = v as? Int { return Double(n) }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func url(_ v: Any?) -> String? {
        let s = str(v)
        let lower = s.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("//") || lower.hasPrefix("data:image/") ? s : nil
    }

    /// "Live chat test (te..." - 18 characters, as the header cuts it.
    public static func headerTitle(_ name: String) -> String { name.count > 18 ? String(name.prefix(18)) + "..." : name }

    /// The avatar's corner radius for its shape: circle 50%, rounded 28%, square 4.
    public static func avatarRadius(_ shape: String?, size: Double) -> Double {
        switch shape {
        case "square": return 4
        case "rounded": return (size * 0.28).rounded()
        default: return size / 2
        }
    }

    public static func resolve(_ raw: [String: Any]?, botName: String = "", theme: ResolvedWidgetTheme? = nil) -> ResolvedCustomizations {
        let c = raw ?? [:]
        var r = ResolvedCustomizations()
        let name = [str(c["logoText"]), str(c["botName"]), botName].first { !$0.isEmpty } ?? "Chat"
        // The stock "We're here to help" a new bot has is shown in the visitor's
        // language (web core/customizations.ts stockText "header.tagline").
        let tagline = (c["enableTagline"] as? Bool) == true && !str(c["tagline"]).isEmpty ? I18n.stockText(str(c["tagline"]), "header.tagline") : nil
        r.hideBrand = (c["hideBrand"] as? Bool) == true
        r.customBrand = (c["enableCustomBrand"] as? Bool) == true && !str(c["customBrand"]).isEmpty ? str(c["customBrand"]) : nil
        r.title = headerTitle(name)
        let logo = url(c["logo"])
        r.logo = logo ?? defaultLogo
        r.hideLogo = (c["hideLogo"] as? Bool) == true
        r.tagline = tagline
        r.showOnline = tagline == nil && (c["hideOnlineStatus"] as? Bool) != true
        r.avatar = url(c["avatar"]) ?? logo ?? defaultLogo
        r.hideAvatar = (c["hideAvatar"] as? Bool) == true
        if let s = num(c["avatarSize"]), s > 0, s != 40 { r.avatarSize = s }
        let shape = c["avatarShape"] as? String
        r.avatarShape = shape == "square" || shape == "rounded" ? shape! : "circle"
        r.avatarRadius = avatarRadius(r.avatarShape, size: r.avatarSize)
        // A theme other than classic brings its own radii; the owner's still win.
        let themeShape = theme?.shape
        if let s = themeShape {
            r.botBubble = BubbleCorners(topLeft: s.rBubble, topRight: s.rBubble, bottomRight: s.rBubble, bottomLeft: s.rTail)
            r.userBubble = BubbleCorners(topLeft: s.rBubble, topRight: s.rBubble, bottomRight: s.rTail, bottomLeft: s.rBubble)
            r.optionRadius = s.rCtl
            r.fieldRadius = s.rField
            r.bubbleBorder = s.bubbleBorder
        }
        if let b = num(c["bubbleBorderRadius"]), b != 10 {
            r.botBubble = .all(b)
            r.userBubble = .all(b)
        }
        if let o = num(c["optionBubbleBorderRadius"]), o != 10 || themeShape == nil { r.optionRadius = o }
        if let t = theme?.tokens, !WidgetTheme.ownsChatBackground(c) { r.surface = t.bg }
        if let f = num(c["fontSize"]), f > 0, f != 14 { r.fontSize = f }
        r.headerBg = str(c["headerBgColor"]).isEmpty ? "#0b4eb8" : str(c["headerBgColor"])
        r.headerText = str(c["headerTextColor"]).isEmpty ? "#ffffff" : str(c["headerTextColor"])
        let bot = str(c["botMsgColor"]), botText = str(c["botTextColor"]), user = str(c["userMsgColor"])
        r.botBubbleColor = bot.isEmpty ? "#0b4eb8" : bot
        r.botTextColor = botText.isEmpty ? "#ffffff" : botText
        // The visitor's bubble: light grey with dark text, never the bot's colour.
        r.userBubbleColor = user.isEmpty ? "#f0f0f0" : user
        r.userTextColor = !str(c["userTextColor"]).isEmpty ? str(c["userTextColor"]) : (user.isEmpty ? "#000000" : "#ffffff")
        // Choices: the option colours, else the bot's, else grey with black text.
        r.optionBubbleColor = [str(c["optionBubbleMsgColor"]), bot].first { !$0.isEmpty } ?? "#e7e4e4"
        r.optionTextColor = [str(c["optionBubbleTextColor"]), botText].first { !$0.isEmpty } ?? "#000000"
        if let t = c["typingStyle"] as? String, typingStyles.contains(t) { r.typingStyle = t }
        r.mascot = MascotArt.lookOf(c)
        r.mascotAccent = [str(c["widgetIconBgColor"]), str(c["headerBgColor"])].first { !$0.isEmpty } ?? "#4f46e5"
        r.mascotInGreeting = (c["mascotInGreeting"] as? Bool) == true
        r.mascotMotion = MascotMotion.normalize(c["mascotMotion"])
        r.mascotLauncherScale = MascotArt.scaleOf(c)
        r.accent = [str(c["themeAccent"]), str(c["headerBgColor"])].first { !$0.isEmpty } ?? "#0b4eb8"
        r.accentInk = str(c["themeOnAccent"]).isEmpty ? nil : str(c["themeOnAccent"])
        if let theme = theme { r.theme = theme }
        return r
    }
}
