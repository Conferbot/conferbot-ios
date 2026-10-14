import XCTest
@testable import Conferbot

final class CustomizationsTests: XCTestCase {

    func testUsesTheWebDefaultsWhenNothingIsSet() {
        let c = Customizations.resolve([:])
        XCTAssertFalse(c.hideBrand)
        XCTAssertNil(c.customBrand)
        XCTAssertTrue(c.showOnline)
        XCTAssertEqual(c.logo, Customizations.defaultLogo)
        XCTAssertEqual(c.avatar, Customizations.defaultLogo)
        XCTAssertEqual(c.avatarSize, 32)
        XCTAssertEqual(c.botBubble, BubbleCorners(topLeft: 18, topRight: 18, bottomRight: 18, bottomLeft: 6))
        XCTAssertEqual(c.userBubble, BubbleCorners(topLeft: 18, topRight: 18, bottomRight: 6, bottomLeft: 18))
        XCTAssertEqual(c.optionRadius, 10)
        XCTAssertEqual(c.fontSize, 14.5)
        XCTAssertEqual(c.userBubbleColor, "#f0f0f0")
        XCTAssertEqual(c.userTextColor, "#000000")
        XCTAssertEqual(c.optionBubbleColor, "#e7e4e4")
        XCTAssertEqual(c.typingStyle, "dots")
    }

    func testTreatsTheServerDefaultsAsUnset() {
        let c = Customizations.resolve(["bubbleBorderRadius": 10, "fontSize": 14, "avatarSize": 40])
        XCTAssertEqual(c.botBubble.bottomLeft, 6)
        XCTAssertEqual(c.fontSize, 14.5)
        XCTAssertEqual(c.avatarSize, 32)
    }

    func testAppliesTheOwnersValuesAndColourFallbacks() {
        let c = Customizations.resolve([
            "bubbleBorderRadius": 4, "optionBubbleBorderRadius": "20", "fontSize": 16, "avatarSize": 44, "avatarShape": "square",
            "hideBrand": true, "enableCustomBrand": true, "customBrand": " Acme ", "enableTagline": true, "tagline": "Here 24/7",
            "hideAvatar": true, "hideLogo": true, "typingStyle": "wave", "botMsgColor": "#0F766E", "botTextColor": "#ffffff", "userMsgColor": "#123456",
        ])
        XCTAssertEqual(c.botBubble, .all(4))
        XCTAssertEqual(c.optionRadius, 20)
        XCTAssertEqual(c.fontSize, 16)
        XCTAssertEqual(c.avatarRadius, 4)
        XCTAssertEqual(c.customBrand, "Acme")
        XCTAssertEqual(c.tagline, "Here 24/7")
        XCTAssertFalse(c.showOnline)
        XCTAssertTrue(c.hideAvatar)
        XCTAssertTrue(c.hideLogo)
        XCTAssertEqual(c.typingStyle, "wave")
        XCTAssertEqual(c.optionBubbleColor, "#0F766E")
        XCTAssertEqual(c.userTextColor, "#ffffff")
    }

    func testCutsTheTitleAndShapesAvatars() {
        XCTAssertEqual(Customizations.headerTitle("Live chat test (temporary) quick"), "Live chat test (te...")
        XCTAssertEqual(Customizations.resolve(["logoText": "Acme", "botName": "Bot"]).title, "Acme")
        XCTAssertEqual(Customizations.avatarRadius("rounded", size: 32), 9)
        XCTAssertEqual(Customizations.avatarRadius("circle", size: 32), 16)
        XCTAssertFalse(Customizations.resolve(["hideOnlineStatus": true]).showOnline)
        XCTAssertNil(Customizations.resolve(["customBrand": "Acme"]).customBrand)
    }
}
