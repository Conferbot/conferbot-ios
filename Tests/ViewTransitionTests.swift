//
//  ViewTransitionTests.swift
//  The owner's view transition between home, chat and help centre
//  (Core/Home/ViewTransition.swift): the React Native SDK's
//  viewTransition.test.ts cases (web ts/layout/viewTransition.ts).
//

import XCTest
@testable import Conferbot

final class ViewTransitionTests: XCTestCase {

    func testUnsetIsTheHoneycombUnknownValuesToo() {
        XCTAssertEqual(ViewTransition.normalize(nil), "honeycomb")
        XCTAssertEqual(ViewTransition.normalize("nope"), "honeycomb")
        XCTAssertEqual(ViewTransition.normalize("fade"), "fade")
        XCTAssertEqual(ViewTransition.normalizeDirection("x"), "auto")
    }

    func testDeeperViewsAreForwardComingBackReversesTheSweep() {
        XCTAssertEqual(ViewTransition.directionBetween("home", "chat"), .forward)
        XCTAssertEqual(ViewTransition.directionBetween("chat", "home"), .back)
        XCTAssertEqual(ViewTransition.directionBetween("home", "help"), .forward)
        XCTAssertEqual(ViewTransition.directionBetween("help", "home"), .back)
        func v(_ s: String, _ d: Double) -> [Double] { let r = ViewTransition.sweepVector(s, d); return [r.x, r.y] }
        XCTAssertEqual(v("auto", 1), [1, 0])
        XCTAssertEqual(v("auto", -1), [-1, 0])
        XCTAssertEqual(v("rtl", 1), [-1, 0])
        XCTAssertEqual(v("ttb", -1), [0, -1])
    }

    func testClassicAndNoneSwitchAtOnceTheSameViewDoesNotMove() {
        XCTAssertEqual(ViewTransition.motion("classic", "auto", from: "home", to: "chat"), .none)
        XCTAssertEqual(ViewTransition.motion("none", "auto", from: "home", to: "chat"), .none)
        XCTAssertEqual(ViewTransition.motion("fade", "auto", from: "chat", to: "chat"), .none)
    }

    func testFadeAndSlideAreTheWebsTheRestSlideReducedMotionIsAShortFade() {
        XCTAssertEqual(ViewTransition.motion("fade", "auto", from: "home", to: "chat"), .fade(duration: 340, delay: 40, scaleFrom: 1.035))
        XCTAssertEqual(ViewTransition.motion("slide", "auto", from: "home", to: "chat"), .slide(duration: 420, dx: 1, dy: 0))
        XCTAssertEqual(ViewTransition.motion("slide", "auto", from: "chat", to: "home"), .slide(duration: 420, dx: -1, dy: 0))
        XCTAssertEqual(ViewTransition.motion(nil, "btt", from: "home", to: "chat"), .slide(duration: 420, dx: 0, dy: -1))
        XCTAssertEqual(ViewTransition.motion("iris", "auto", from: "home", to: "help", reduced: true), .reduced(duration: 200))
        XCTAssertEqual(ViewTransition.motion("classic", "auto", from: "home", to: "help", reduced: true), .none)
    }
}
