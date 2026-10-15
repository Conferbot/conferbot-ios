import XCTest
@testable import Conferbot

final class LauncherIconsTests: XCTestCase {

    func testHasTheWebWidgetsFiftySixIcons() {
        XCTAssertEqual(LauncherIcons.all.count, 56)
        let ids = Set(LauncherIcons.all.map { $0.id })
        for n in 1...56 { XCTAssertTrue(ids.contains("WidgetBubbleIcon\(n)"), "\(n)") }
    }

    func testFallsBackToTheGlossyBubble() {
        XCTAssertEqual(LauncherIcons.defaultIcon, "WidgetBubbleIcon40")
        XCTAssertEqual(LauncherIcons.byId("nope")?.id, "WidgetBubbleIcon40")
        XCTAssertEqual(LauncherIcons.byId(nil)?.id, "WidgetBubbleIcon40")
        XCTAssertEqual(LauncherIcons.byId("WidgetBubbleIcon7")?.id, "WidgetBubbleIcon7")
    }

    func testReadsPaintsGradientsAndHiddenParts() {
        let glossy = LauncherIcons.byId("WidgetBubbleIcon40")!
        XCTAssertEqual(glossy.grads.count, 3)
        XCTAssertEqual(glossy.grads[0].stops[0].c, "ink")
        XCTAssertEqual(glossy.grads[0].stops[1].a, 0.84, accuracy: 1e-9)
        XCTAssertTrue(LauncherIcons.all.contains { $0.ops.contains { $0.op == 0 } })
        for icon in LauncherIcons.all {
            for o in icon.ops {
                XCTAssertGreaterThan(o.d.count, 3)
                XCTAssertFalse(SVGPathParser.parse(o.d).isEmpty, icon.id)
                for p in [o.fill, o.stroke].compactMap({ $0 }) {
                    if let g = p.g { XCTAssertLessThan(g, icon.grads.count) }
                }
            }
        }
    }

    func testDrawsTheIconAtSeventyPercent() {
        XCTAssertEqual(Launcher.resolve(["widgetSize": 50]).glyph, 35)
        XCTAssertEqual(Launcher.resolve(["widgetSize": 50, "launcherShape": "tab"]).glyph, 25)
    }
}
