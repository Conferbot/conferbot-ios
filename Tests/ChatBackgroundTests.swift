import XCTest
@testable import Conferbot

final class ChatBackgroundTests: XCTestCase {

    func testIsWhiteWhenNothingIsSet() {
        XCTAssertEqual(ChatBackgrounds.resolve(nil), .solid(color: "#ffffff"))
        XCTAssertEqual(ChatBackgrounds.resolve(["chatBgColor": "#f8fafc"]), .solid(color: "#f8fafc"))
    }

    func testRejectsColoursThatAreNotColours() {
        XCTAssertEqual(ChatBackgrounds.resolve(["chatBgColor": "red;background:url(x)"]), .solid(color: "#ffffff"))
    }

    func testReadsAGradient() {
        let bg = ChatBackgrounds.resolve([
            "chatBgType": "gradient", "chatBgGradientStyle": "mesh", "chatBgGradientAngle": 135,
            "chatBgGradientStops": ["#ccfbf1", "#e0f2fe", "#fef3c7"],
        ])
        XCTAssertEqual(bg, .gradient(color: "#ffffff", stops: ["#ccfbf1", "#e0f2fe", "#fef3c7"], angle: 135, style: "mesh"))
    }

    func testFallsBackToALinearGradientForAnUnknownStyle() {
        guard case .gradient(_, _, let angle, let style) = ChatBackgrounds.resolve(["chatBgType": "gradient", "chatBgGradientStyle": "conic", "chatBgGradientAngle": 999]) else {
            return XCTFail("expected a gradient")
        }
        XCTAssertEqual(style, "linear")
        XCTAssertEqual(angle, 360)
    }

    func testReadsAPattern() {
        let bg = ChatBackgrounds.resolve(["chatBgType": "pattern", "chatBgPattern": "doodles", "chatBgPatternColor": "#0F766E", "chatBgPatternOpacity": 18])
        XCTAssertEqual(bg, .pattern(color: "#ffffff", pattern: "doodles", ink: "#0F766E", alpha: 0.18))
    }

    func testUsesDotsForAnUnknownPattern() {
        guard case .pattern(_, let id, _, let alpha) = ChatBackgrounds.resolve(["chatBgType": "pattern", "chatBgPattern": "nope"]) else {
            return XCTFail("expected a pattern")
        }
        XCTAssertEqual(id, "dots")
        XCTAssertEqual(alpha, 0.12, accuracy: 0.0001)
    }

    func testEveryPatternHasShapesAndATile() {
        XCTAssertEqual(ChatBackgrounds.patterns.count, 13)
        for (id, tile) in ChatBackgrounds.patterns {
            XCTAssertGreaterThan(tile.w, 0, id)
            XCTAssertGreaterThan(tile.h, 0, id)
            XCTAssertTrue(tile.noise || !tile.shapes.isEmpty, id)
            for s in tile.shapes where s.t == "path" {
                XCTAssertFalse(SVGPathParser.parse(s.d ?? "").isEmpty, id)
            }
        }
    }

    func testReadsAnImageWithItsMask() {
        let bg = ChatBackgrounds.resolve(["chatBgType": "image", "chatBgImage": "https://x.test/a.jpg", "chatBgMaskColor": "#000", "chatBgMaskOpacity": 40])
        XCTAssertEqual(bg, .image(color: "#ffffff", url: "https://x.test/a.jpg", maskColor: "#000", maskAlpha: 0.4))
    }

    func testIgnoresAnEmptyOrScriptImage() {
        XCTAssertEqual(ChatBackgrounds.resolve(["chatBgType": "image", "chatBgImage": " "]), .solid(color: "#ffffff"))
        XCTAssertEqual(ChatBackgrounds.resolve(["chatBgType": "image", "chatBgImage": "javascript:alert(1)"]), .solid(color: "#ffffff"))
    }

    func testRimPointStartsAtTheTop() {
        let (x, y) = ChatBackgrounds.rimPoint(0)
        XCTAssertEqual(x, 0.5, accuracy: 0.001)
        XCTAssertEqual(y, 0.0, accuracy: 0.001)
    }

    func testPaperSpecklesAreStable() {
        XCTAssertEqual(ChatBackgrounds.paperSpeckles.count, 260)
        XCTAssertEqual(ChatBackgrounds.paperSpeckles[0], ChatBackgrounds.paperSpeckles[0])
        XCTAssertTrue(ChatBackgrounds.paperSpeckles.allSatisfy { $0[0] >= 0 && $0[0] <= 180 && $0[2] >= 0.4 })
    }
}
