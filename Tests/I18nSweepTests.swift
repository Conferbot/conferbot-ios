//
//  I18nSweepTests.swift
//  ConferbotTests
//
//  The core's words come out in German under widgetLanguage "de" (as the
//  React Native SDK's __tests__/core/i18nCore.test.ts and its sweep): each
//  text producer the views draw from is read in German and checked to hold
//  no English table value, then English again after.
//

import XCTest
@testable import Conferbot

final class I18nSweepTests: XCTestCase {

    override func setUp() {
        super.setUp()
        I18n.setWidgetLanguage("de", languages: [])
    }

    override func tearDown() {
        I18n.setWidgetLanguage("en", languages: [])
        super.tearDown()
    }

    /// German for a key.
    func de(_ key: String, _ vars: [String: Any]? = nil) -> String { I18n.tFor(.de, key, vars) }

    /// The English table's values that are English only: not also a German
    /// value, nor inside one ("OK", "Chat", "E-Mail" are both), at least 6
    /// characters so names and short words don't count.
    static let englishOnly: [String] = {
        let deValues = Set(I18n.table(.de).values)
        let deText = deValues.joined(separator: "\n")
        return Set(I18n.english.values)
            .map { $0.replacingOccurrences(of: "\\{\\w+\\}", with: "\u{1}", options: .regularExpression) }
            .flatMap { $0.components(separatedBy: "\u{1}") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { $0.count >= 6 && $0.contains(" ") && !deText.contains($0) }
            .sorted { $0.count > $1.count }
    }()

    /// Whole English values that German never uses ("Continue", "Helpful?").
    static let englishWords: Set<String> = {
        let deValues = Set(I18n.table(.de).values)
        return Set(I18n.english.values.filter { !deValues.contains($0) && $0.count >= 3 })
    }()

    /// Fails when `text` is an English-only value, or holds an English-only table value (or a piece of one
    /// between its placeholders).
    func assertNoEnglish(_ text: String?, _ what: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard let text = text, !text.isEmpty else { return }
        if Self.englishWords.contains(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            XCTFail("English \"\(text)\" in \(what)", file: file, line: line)
            return
        }
        if let hit = Self.englishOnly.first(where: { text.contains($0) }) {
            XCTFail("English \"\(hit)\" in \(what.isEmpty ? "" : what + ": ")\"\(text)\"", file: file, line: line)
        }
    }

    func testTheCheckPassesEveryGermanValueAndCatchesEnglish() {
        for (key, value) in I18n.table(.de) { assertNoEnglish(value, key) }
        XCTAssertTrue(Self.englishOnly.contains { "Thanks for letting us know!".contains($0) })
    }
}
