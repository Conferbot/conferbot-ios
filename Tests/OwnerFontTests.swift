//
//  OwnerFontTests.swift
//  Conferbot
//
//  The owner's font and the theme's (RN __tests__/core/ownerFont.test.ts;
//  web ts/fonts/ownerFont.ts, ts/theme/themeTokens.ts, applyTheme.ts
//  loadThemeFont), and the loader registering a real TrueType file.
//

import XCTest
@testable import Conferbot

final class OwnerFontTests: XCTestCase {

    typealias F = OwnerFont

    static let googleTTF = """
    @font-face {
      font-family: 'Inter';
      font-style: normal;
      font-weight: 400;
      font-display: swap;
      src: url(https://fonts.gstatic.com/s/inter/v20/a.ttf) format('truetype');
    }
    @font-face {
      font-family: 'Inter';
      font-style: normal;
      font-weight: 700;
      font-display: swap;
      src: url(https://fonts.gstatic.com/s/inter/v20/b.ttf) format('truetype');
    }
    @font-face {
      font-family: 'Inter';
      font-style: italic;
      font-weight: 400;
      src: url(https://fonts.gstatic.com/s/inter/v20/c.ttf) format('truetype');
    }
    @font-face {
      font-family: 'Inter';
      font-weight: 400;
      src: url(https://fonts.gstatic.com/s/inter/v20/d.woff2) format('woff2');
    }
    """

    func testKnowsTheDefaultsThatMeanNoFontWasPicked() {
        XCTAssertTrue(F.isDefaultFont(""))
        XCTAssertTrue(F.isDefaultFont("Arial"))
        XCTAssertTrue(F.isDefaultFont("Gill Sans, sans-serif;"))
        XCTAssertTrue(F.isDefaultFont(nil))
        XCTAssertFalse(F.isDefaultFont("Inter"))
    }

    func testFindsACatalogFontByFamilyStackIdOrPrefixedName() {
        XCTAssertEqual(F.findCatalogFont("Inter")?.id, "inter")
        XCTAssertEqual(F.findCatalogFont("'Plus Jakarta Sans', sans-serif")?.id, "plus-jakarta-sans")
        XCTAssertEqual(F.findCatalogFont("dm-sans")?.family, "DM Sans")
        XCTAssertEqual(F.findCatalogFont("CB Font Poppins")?.id, "poppins")
        XCTAssertNil(F.findCatalogFont("Charlesworth"))
        XCTAssertEqual(F.firstFamily("\"Gill Sans\", serif"), "Gill Sans")
    }

    func testReadsGoogleFontsTrueTypeFacesSkippingWoff2() {
        XCTAssertEqual(F.parseFontFaces(Self.googleTTF), [
            F.FontFace(weight: 400, style: "normal", url: "https://fonts.gstatic.com/s/inter/v20/a.ttf"),
            F.FontFace(weight: 700, style: "normal", url: "https://fonts.gstatic.com/s/inter/v20/b.ttf"),
            F.FontFace(weight: 400, style: "italic", url: "https://fonts.gstatic.com/s/inter/v20/c.ttf"),
        ])
        XCTAssertEqual(F.parseFontFaces(""), [])
        XCTAssertEqual(F.googleFontUrl("Inter:wght@400;700"), "https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap")
    }

    func testNamesFacesAsTheWidgetDoes() {
        XCTAssertEqual(F.faceName("Inter", 400), "CB Font Inter")
        XCTAssertEqual(F.faceName("Inter", 700), "CB Font Inter 700")
    }

    func testPutsTheOwnersFontOverTheThemesEverywhere() {
        let inter = F.FontPick(family: "Inter", google: "Inter:wght@400;500;600;700")
        XCTAssertEqual(F.chatFontsFor("Inter", themeFont: "Fraunces", themeFontRole: "display"), F.ChatFonts(body: inter, display: inter))
        // A system font is used by name; system-ui is the platform's own.
        let georgia = F.FontPick(family: "Georgia", google: nil)
        XCTAssertEqual(F.chatFontsFor("Georgia", themeFont: nil, themeFontRole: nil), F.ChatFonts(body: georgia, display: georgia))
        XCTAssertEqual(F.chatFontsFor("system-ui", themeFont: nil, themeFontRole: nil), F.ChatFonts(body: nil, display: nil))
        // An older bot's unknown font stays a plain family name.
        XCTAssertEqual(F.chatFontsFor("Charlesworth", themeFont: nil, themeFontRole: nil).body, F.FontPick(family: "Charlesworth", google: nil))
    }

    func testABodyThemeFontForAllTextADisplayOneForHeadingsOnly() {
        let manrope = F.FontPick(family: "Manrope", google: "Manrope:wght@400;500;600;700")
        XCTAssertEqual(F.chatFontsFor("Arial", themeFont: "Manrope", themeFontRole: "body"), F.ChatFonts(body: manrope, display: manrope))
        XCTAssertEqual(F.chatFontsFor("", themeFont: "Fraunces", themeFontRole: "display"),
                       F.ChatFonts(body: nil, display: F.FontPick(family: "Fraunces", google: F.themeFontQueries["Fraunces"])))
        XCTAssertEqual(F.chatFontsFor("", themeFont: nil, themeFontRole: nil), F.ChatFonts(body: nil, display: nil))
    }

    func testDrawsEachWeightWithTheNearestFaceItHasNothingUntilOneIsLoaded() {
        let pick = F.FontPick(family: "Inter", google: "Inter")
        XCTAssertNil(F.fontFamilyFor(pick, loaded: [], weight: 400))
        XCTAssertEqual(F.fontFamilyFor(pick, loaded: [400, 700], weight: 400), "CB Font Inter")
        XCTAssertEqual(F.fontFamilyFor(pick, loaded: [400, 700], weight: 600), "CB Font Inter 700")
        XCTAssertEqual(F.fontFamilyFor(pick, loaded: [400, 600], weight: 500), "CB Font Inter")
        XCTAssertEqual(F.fontFamilyFor(pick, loaded: [500], weight: 400), "CB Font Inter 500")
        XCTAssertEqual(F.fontFamilyFor(F.FontPick(family: "Georgia", google: nil), loaded: nil, weight: 700), "Georgia")
        XCTAssertNil(F.fontFamilyFor(nil, loaded: [400], weight: 400))
    }

    /// The catalog and theme queries are RN's fonts.data.ts (itself the widget's), unchanged.
    func testCarriesTheWidgetsCatalogAndThemeFontsUnchanged() throws {
        let rn = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("conferbot-react-native/src/core/fonts.data.ts")
        guard let src = try? String(contentsOf: rn, encoding: .utf8) else {
            throw XCTSkip("conferbot-react-native is not checked out beside this repo")
        }
        let cat = src.components(separatedBy: "FONT_CATALOG: CatalogFont[] =")[1].components(separatedBy: "];")[0] + "]"
        let fonts = try JSONSerialization.jsonObject(with: Data(cat.utf8)) as! [[String: Any]]
        XCTAssertEqual(fonts.count, F.catalog.count)
        for (a, b) in zip(fonts, F.catalog) {
            XCTAssertEqual(a["id"] as? String, b.id)
            XCTAssertEqual(a["family"] as? String, b.family)
            XCTAssertEqual(a["stack"] as? String, b.stack)
            XCTAssertEqual(a["google"] as? String, b.google)
        }
        let q = src.components(separatedBy: "THEME_FONT_QUERIES: Record<string, string> =")[1].components(separatedBy: "};")[0] + "}"
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(q.utf8)) as? [String: String], F.themeFontQueries)
    }

    /// A TrueType file registers for this process and is drawn by its
    /// PostScript name (the phone's own Helvetica stands in for a download).
    @MainActor
    func testTheLoaderRegistersAFaceAndPicksTheNearestWeight() throws {
        #if canImport(UIKit)
        let candidates = ["/System/Library/Fonts/Supplemental/Georgia.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf",
                          "/System/Library/Fonts/Core/Avenir.ttc", "/Library/Fonts/Arial Unicode.ttf"]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let data = FileManager.default.contents(atPath: path) else { throw XCTSkip("no TrueType file on this simulator") }
        let name = ChatFontLoader.register(data)
        XCTAssertNotNil(name)
        // A second registration (the app bundles it, a later load) still counts.
        XCTAssertEqual(ChatFontLoader.register(data), name)
        XCTAssertNil(ChatFontLoader.register(Data("not a font".utf8)))
        #endif
        let loader = ChatFontLoader()
        loader.cacheDir = nil
        loader.update(ownerFont: "Georgia", themeFont: nil, themeFontRole: nil)
        XCTAssertEqual(loader.faceName(.body), "Georgia")
        XCTAssertEqual(loader.faceName(.display, weight: 700), "Georgia")
        loader.update(ownerFont: "", themeFont: nil, themeFontRole: nil)
        XCTAssertNil(loader.faceName(.body))
        XCTAssertFalse(loader.isSet)
    }
}
