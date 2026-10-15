import XCTest
@testable import Conferbot

final class LauncherTests: XCTestCase {

    func testIsASpeechBubbleSixteenFromTheCornerByDefault() {
        let l = Launcher.resolve([:])
        XCTAssertEqual(l.shape, "bubble")
        XCTAssertEqual(l.position, "right")
        XCTAssertEqual(l.size, 50)
        XCTAssertEqual(l.bottom, 16)
        XCTAssertEqual(l.side, 16)
        XCTAssertEqual(l.corners, BubbleCorners(topLeft: 25, topRight: 25, bottomRight: 6, bottomLeft: 25))
        XCTAssertEqual(Launcher.resolve(["widgetPosition": "left"]).corners.bottomLeft, 6)
    }

    func testKeepsAnOwnerRoundedButtonRound() {
        XCTAssertEqual(Launcher.normalizeShape(nil, radius: 12), "circle")
        XCTAssertEqual(Launcher.normalizeShape(nil, radius: 50), "bubble")
        XCTAssertEqual(Launcher.normalizeShape("peek", radius: 12), "peek")
        XCTAssertEqual(Launcher.resolve(["widgetBorderRadius": 12, "widgetSize": 60]).corners.topLeft, 12)
    }

    func testUsesThePhoneSizeAndOffsetsClamped() {
        let l = Launcher.resolve(["widgetSize": 70, "mobileWidgetSize": 200, "mobileOffsetBottom": 90, "mobileOffsetSide": -5])
        XCTAssertEqual(l.size, 80)
        XCTAssertEqual(l.bottom, 90)
        XCTAssertEqual(l.side, 0)
        XCTAssertEqual(Launcher.resolve(["widgetSize": 64]).size, 64)
    }

    func testDrawsSquircleTabAndPeek() {
        XCTAssertEqual(Launcher.resolve(["launcherShape": "squircle", "widgetSize": 50]).corners.topLeft, 15)
        let tab = Launcher.resolve(["launcherShape": "tab", "widgetSize": 50])
        XCTAssertEqual(tab.width, 41)
        XCTAssertEqual(tab.side, 0)
        XCTAssertEqual(tab.corners, BubbleCorners(topLeft: 15, topRight: 0, bottomRight: 0, bottomLeft: 15))
        XCTAssertEqual(Launcher.resolve(["launcherShape": "peek", "widgetSize": 50]).tucked, 17)
    }

    func testReadsColoursWithDarkInkOnLightOnes() {
        XCTAssertEqual(Launcher.resolve(["widgetIconBgColor": "#0F766E"]).solid, "#0F766E")
        XCTAssertEqual(Launcher.resolve(["widgetIconBgColor": "#0F766E"]).ink, "#ffffff")
        XCTAssertEqual(Launcher.resolve(["widgetIconBgColor": "#fef3c7"]).ink, "#111827")
        let g = Launcher.resolve(["widgetIconThemeType": "Gradient", "widgetGradientBgOne": "#7c3aed", "widgetGradientBgTwo": "#0d9488"])
        XCTAssertEqual(g.gradient, ["#7c3aed", "#0d9488"])
        XCTAssertEqual(g.solid, "#7c3aed")
        XCTAssertEqual(Launcher.resolve(["headerBgColor": "#123456"]).solid, "#123456")
    }

    func testFallsBackToTheIconForImageMissingAvatarAndLabelOnPhones() {
        XCTAssertEqual(Launcher.resolve(["launcherStyle": "avatar", "avatar": "https://x/a.png"]).style, "avatar")
        XCTAssertEqual(Launcher.resolve(["launcherStyle": "avatar"]).style, "icon")
        XCTAssertEqual(Launcher.resolve(["launcherStyle": "avatar", "avatar": "a", "widgetIconType": "Image", "widgetIconImage": "https://x/i.png"]).style, "icon")
        XCTAssertEqual(Launcher.resolve(["launcherStyle": "label"], screenWidth: 400).style, "icon")
        XCTAssertEqual(Launcher.resolve(["launcherStyle": "label"], screenWidth: 800).style, "label")
    }

    func testCapsTheLabelAndShowsTheGreetingOnlyWhenOn() {
        XCTAssertEqual(Launcher.normalizeLabel("  Talk   to the   team about your order today  "), "Talk to the team about y")
        XCTAssertEqual(Launcher.resolve([:]).label, "Chat with us")
        XCTAssertNil(Launcher.resolve(["chatIconCtaText": "Hi there"]).ctaText)
        XCTAssertEqual(Launcher.resolve(["chatIconCta": true, "chatIconCtaText": "Hi there"]).ctaText, "Hi there")
    }

    func testReadsTheMotionSubtleByDefault() {
        XCTAssertEqual(Launcher.resolve([:]).animation, "subtle")
        XCTAssertEqual(Launcher.resolve(["launcherAnimation": "off"]).animation, "off")
        XCTAssertEqual(Launcher.resolve(["launcherAnimation": "wild"]).animation, "subtle")
    }
}
