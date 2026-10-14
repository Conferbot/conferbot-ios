import XCTest
@testable import Conferbot

final class WidgetThemeTests: XCTestCase {

    private func isHex(_ s: String) -> Bool { s.range(of: "^#[0-9a-f]{6}$", options: .regularExpression) != nil }

    func testKnowsTheTwentySevenWebThemesClassicFirst() {
        XCTAssertEqual(WidgetTheme.themes.count, 27)
        XCTAssertEqual(WidgetTheme.themes.first, "classic")
        XCTAssertTrue(["minimal", "glass", "neobrutal", "midnight", "space"].allSatisfy(WidgetTheme.themes.contains))
    }

    func testFallsBackToClassicLightBrand() {
        XCTAssertEqual(WidgetTheme.normalizeTheme("NOPE"), "classic")
        XCTAssertEqual(WidgetTheme.normalizeTheme(" Minimal "), "minimal")
        XCTAssertEqual(WidgetTheme.normalizeAppearance("purple"), "light")
        XCTAssertEqual(WidgetTheme.normalizeAppearance("AUTO"), "auto")
        XCTAssertEqual(WidgetTheme.normalizeThemeColors("theme"), "theme")
        XCTAssertEqual(WidgetTheme.normalizeThemeColors(nil), "brand")
    }

    func testResolvesTheScheme() {
        XCTAssertEqual(WidgetTheme.resolveScheme("midnight", appearance: "light", prefersDark: false), "dark")
        XCTAssertEqual(WidgetTheme.resolveScheme("classic", appearance: "dark", prefersDark: false), "dark")
        XCTAssertEqual(WidgetTheme.resolveScheme("classic", appearance: "auto", prefersDark: true), "dark")
        XCTAssertEqual(WidgetTheme.resolveScheme("classic", appearance: "auto", prefersDark: false), "light")
        XCTAssertEqual(WidgetTheme.resolveScheme("minimal", appearance: "light", prefersDark: true), "light")
    }

    func testChangesNothingForClassicInLight() {
        let t = WidgetTheme.resolve([:], prefersDark: false)
        XCTAssertEqual(t.id, "classic")
        XCTAssertNil(t.tokens)
        XCTAssertNil(t.shape)
    }

    func testRepaintsOnlySurfacesForClassicInDark() {
        let t = WidgetTheme.resolve(["themeAppearance": "dark"], prefersDark: false)
        XCTAssertEqual(t.tokens?.bg, "#14161c")
        XCTAssertEqual(t.tokens?.ink, "#f1f3f7")
        XCTAssertNil(t.shape)
        XCTAssertTrue(t.isDark)
    }

    func testGivesEveryThemeConcreteColours() {
        for id in WidgetTheme.themes {
            for appearance in ["light", "dark"] {
                let t = WidgetTheme.resolve(["widgetTheme": id, "themeAppearance": appearance, "headerBgColor": "#0F766E"], prefersDark: false)
                guard let k = t.tokens else { continue }
                for v in [k.bg, k.bg2, k.card, k.card2, k.field, k.menu, k.ink, k.text, k.muted, k.faint, k.line, k.line2] {
                    XCTAssertTrue(isHex(v), "\(id) \(appearance) \(v)")
                }
            }
        }
    }

    func testBringsTheThemeShape() {
        let minimal = WidgetTheme.resolve(["widgetTheme": "minimal"], prefersDark: false).shape
        XCTAssertEqual(minimal?.rBubble, 14)
        XCTAssertEqual(minimal?.rCtl, 10)
        XCTAssertEqual(minimal?.rField, 12)
        XCTAssertEqual(WidgetTheme.resolve(["widgetTheme": "neobrutal"], prefersDark: false).shape?.bubbleBorder, BubbleBorder(width: 2, color: "#000000"))
    }

    func testTintsBrandMixedSurfaces() {
        let red = WidgetTheme.resolve(["widgetTheme": "clay", "headerBgColor": "#ff0000"], prefersDark: false).tokens!.bg
        let blue = WidgetTheme.resolve(["widgetTheme": "clay", "headerBgColor": "#0000ff"], prefersDark: false).tokens!.bg
        XCTAssertTrue(isHex(red))
        XCTAssertNotEqual(red, blue)
    }

    func testMakesGlassOpaque() {
        XCTAssertEqual(WidgetTheme.resolve(["widgetTheme": "glass"], prefersDark: false).tokens?.bg, "#fafbfd")
    }

    func testSwapsInThePaletteOnlyForThemeColours() {
        let owner: [String: Any] = ["widgetTheme": "minimal", "headerBgColor": "#0F766E", "chatBgType": "pattern", "logo": "x"]
        XCTAssertEqual(WidgetTheme.withThemePalette(owner, prefersDark: false)["headerBgColor"] as? String, "#0F766E")
        var themed = owner
        themed["themeColors"] = "theme"
        let p = WidgetTheme.withThemePalette(themed, prefersDark: false)
        XCTAssertEqual(p["headerBgColor"] as? String, "#09090b")
        XCTAssertEqual(p["userMsgColor"] as? String, "#2563eb")
        XCTAssertEqual(p["chatBgType"] as? String, "solid")
        XCTAssertEqual(p["chatBgColor"] as? String, "#ffffff")
        XCTAssertEqual(p["logo"] as? String, "x")
        themed["themeAppearance"] = "dark"
        XCTAssertEqual(WidgetTheme.withThemePalette(themed, prefersDark: false)["headerBgColor"] as? String, "#18181b")
    }

    func testOnlyPlainWhiteIsTheDefaultBackground() {
        XCTAssertFalse(WidgetTheme.ownsChatBackground([:]))
        XCTAssertFalse(WidgetTheme.ownsChatBackground(["chatBgColor": "#ffffff"]))
        XCTAssertTrue(WidgetTheme.ownsChatBackground(["chatBgColor": "#f8fafc"]))
        XCTAssertTrue(WidgetTheme.ownsChatBackground(["chatBgType": "gradient"]))
    }

    func testTakesThemeRadiiUnlessTheOwnerSetTheirOwn() {
        let theme = WidgetTheme.resolve(["widgetTheme": "minimal"], prefersDark: false)
        let c = Customizations.resolve(["bubbleBorderRadius": 10, "optionBubbleBorderRadius": 10], theme: theme)
        XCTAssertEqual(c.botBubble, .all(14))
        XCTAssertEqual(c.optionRadius, 10)
        XCTAssertEqual(c.fieldRadius, 12)
        let own = Customizations.resolve(["bubbleBorderRadius": 4, "optionBubbleBorderRadius": 20], theme: theme)
        XCTAssertEqual(own.botBubble.bottomLeft, 4)
        XCTAssertEqual(own.optionRadius, 20)
    }

    func testKeepsClassicWithoutATheme() {
        let c = Customizations.resolve(["optionBubbleBorderRadius": 10])
        XCTAssertEqual(c.botBubble.bottomLeft, 6)
        XCTAssertEqual(c.fieldRadius, 25)
        XCTAssertNil(c.surface)
        XCTAssertNil(c.bubbleBorder)
    }

    func testPaintsTheSurfaceUnlessTheOwnerHasABackground() {
        let theme = WidgetTheme.resolve(["widgetTheme": "midnight"], prefersDark: false)
        XCTAssertEqual(Customizations.resolve([:], theme: theme).surface, theme.tokens?.bg)
        XCTAssertNil(Customizations.resolve(["chatBgType": "gradient"], theme: theme).surface)
    }

    func testUsesThePaletteSendColours() {
        let raw = WidgetTheme.withThemePalette(["widgetTheme": "aurora", "themeColors": "theme", "themeAppearance": "dark"], prefersDark: false)
        let c = Customizations.resolve(raw)
        XCTAssertEqual(c.accent, "#a78bfa")
        XCTAssertEqual(c.accentInk, "#0c0d18")
        XCTAssertNil(Customizations.resolve(["headerBgColor": "#0F766E"]).accentInk)
    }
}
