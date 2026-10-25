//
//  CitationMarkersTests.swift
//  Conferbot
//
//  Placeholder citation markers in AI answers (#110), the cases of
//  embed-server utils/citationMarkers.js stripPlaceholderMarkers.
//

import XCTest
@testable import Conferbot

final class CitationMarkersTests: XCTestCase {
    private func strip(_ s: String) -> String { CitationMarkers.stripPlaceholderMarkers(s) }

    func testPlaceholdersGoWithTheSpaceBefore() {
        XCTAssertEqual(strip("Wie Sie zit. [n] Als Kunde"), "Wie Sie zit. Als Kunde")
        XCTAssertEqual(strip("zit. [n] Als"), "zit. Als")
        XCTAssertEqual(strip("Plans start at $9 [1, n]."), "Plans start at $9.")
        XCTAssertEqual(strip("Yes [N]."), "Yes.")
        XCTAssertEqual(strip("See the guide [source]."), "See the guide.")
        XCTAssertEqual(strip("Open daily [web:2], weekends too"), "Open daily, weekends too")
    }

    func testNumbersWordsLinksAndCheckboxesStay() {
        XCTAssertEqual(strip("[Klik hier]"), "[Klik hier]")
        XCTAssertEqual(strip("See step [2]."), "See step [2].")
        XCTAssertEqual(strip("[n](https://x)"), "[n](https://x)")
        XCTAssertEqual(strip("- [x] done"), "- [x] done")
        XCTAssertEqual(strip("Nothing here . really"), "Nothing here . really")
    }
}
