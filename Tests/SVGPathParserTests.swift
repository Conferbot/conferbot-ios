import XCTest
@testable import Conferbot

final class SVGPathParserTests: XCTestCase {

    func testReadsAbsoluteAndRelativeLinesAndClose() {
        let s = SVGPathParser.parse("M10 10 h5 v5 L10 15 z")
        XCTAssertEqual(s, [.move(CGPoint(x: 10, y: 10)), .line(CGPoint(x: 15, y: 10)), .line(CGPoint(x: 15, y: 15)), .line(CGPoint(x: 10, y: 15)), .close])
    }

    func testTreatsPairsAfterAMoveAsLines() {
        let s = SVGPathParser.parse("m1,1 2,0 0,2")
        XCTAssertEqual(s, [.move(CGPoint(x: 1, y: 1)), .line(CGPoint(x: 3, y: 1)), .line(CGPoint(x: 3, y: 3))])
    }

    func testReadsCompactNumbersAndCurves() {
        let s = SVGPathParser.parse("M0 0C1-1 2-1 3 0s2 1 3 0Q7-1 8 0t2 0")
        XCTAssertEqual(s.count, 5)
        if case .cubic(let c1, _, let end) = s[2] {
            XCTAssertEqual(c1, CGPoint(x: 4, y: 1)) // reflection of (2,-1) through (3,0)
            XCTAssertEqual(end, CGPoint(x: 6, y: 0))
        } else { XCTFail("S should be a cubic") }
        if case .cubic(_, _, let end) = s[4] { XCTAssertEqual(end, CGPoint(x: 10, y: 0)) } else { XCTFail("T should be a cubic") }
    }

    func testTurnsArcsIntoCubicsEndingAtTheTarget() {
        let s = SVGPathParser.parse("M0 0 A5 5 0 0 1 10 0")
        XCTAssertGreaterThanOrEqual(s.count, 2)
        if case .cubic(_, _, let end) = s.last! { XCTAssertEqual(end, CGPoint(x: 10, y: 0)) } else { XCTFail("arc should end in a cubic") }
        // Flags written without separators.
        let t = SVGPathParser.parse("M0 0a5 5 0 1010 0")
        if case .cubic(_, _, let end) = t.last! { XCTAssertEqual(end, CGPoint(x: 10, y: 0)) } else { XCTFail("compact arc flags") }
    }
}
