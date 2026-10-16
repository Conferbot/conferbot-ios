//
//  I18nTests.swift
//  ConferbotTests
//
//  The SDK's own words in five languages (Core/I18n, a port of the React
//  Native SDK's src/core/i18n.ts and its __tests__/core/i18n.test.ts): how
//  the language is chosen, the fallbacks, {name} and plurals, every key in
//  every language, and the bundled table the same as RN's strings.json.
//

import XCTest
@testable import Conferbot

final class I18nTests: XCTestCase {

    override func tearDown() {
        I18n.setWidgetLanguage("en", languages: [])
        super.tearDown()
    }

    private var keys: [String] { Array(I18n.english.keys) }

    private func placeholders(_ s: String) -> String {
        let re = try! NSRegularExpression(pattern: "\\{\\w+\\}")
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s))
            .compactMap { Range($0.range, in: s).map { String(s[$0]) } }
            .sorted().joined(separator: ",")
    }

    // MARK: - Which language

    func testTheChosenLanguageWinsOverThePhone() {
        XCTAssertEqual(I18n.resolve("de", deviceLanguages: ["fr-FR"]), .de)
        XCTAssertEqual(I18n.resolve(" NL ", deviceLanguages: ["fr-FR"]), .nl)
    }

    func testAutoAbsentOrUnknownFollowsTheFirstSupportedPhoneLanguage() {
        XCTAssertEqual(I18n.resolve("auto", deviceLanguages: ["ja-JP", "es-MX", "de-DE"]), .es)
        XCTAssertEqual(I18n.resolve(nil, deviceLanguages: ["fr_CA"]), .fr)
        XCTAssertEqual(I18n.resolve("klingon", deviceLanguages: ["nl-BE"]), .nl)
        XCTAssertEqual(I18n.resolve(NSNull(), deviceLanguages: ["de"]), .de)
        XCTAssertEqual(I18n.resolve(42, deviceLanguages: ["es"]), .es)
    }

    func testEnglishWhenNothingFits() {
        XCTAssertEqual(I18n.resolve("auto", deviceLanguages: ["ja-JP", "pt-BR"]), .en)
        XCTAssertEqual(I18n.resolve("auto", deviceLanguages: []), .en)
    }

    func testAStoredSettingIsASupportedCodeOrAuto() {
        XCTAssertEqual(I18n.normalizeSetting("es"), "es")
        XCTAssertEqual(I18n.normalizeSetting("pt"), "auto")
        XCTAssertEqual(I18n.normalizeSetting(42), "auto")
        XCTAssertEqual(I18n.baseLanguage(of: "nl-BE"), .nl)
        XCTAssertNil(I18n.baseLanguage(of: "pt-PT"))
    }

    func testThePhonesLanguagesThePreferredListFirstThenTheRegionBCP47NoRepeats() {
        XCTAssertEqual(I18n.deviceLanguagesOf(preferred: ["ja-JP", "de-AT"], current: "de_AT"), ["ja-JP", "de-AT"])
        XCTAssertEqual(I18n.deviceLanguagesOf(preferred: ["ja"], current: "fr_FR@calendar=gregorian"), ["ja", "fr-FR"])
        XCTAssertEqual(I18n.resolve("auto", deviceLanguages: I18n.deviceLanguagesOf(preferred: [], current: "es_ES")), .es)
    }

    func testSetWidgetLanguageKeepsARegionalTagForDates() {
        XCTAssertEqual(I18n.setWidgetLanguage("auto", languages: ["nl-BE", "en-GB"]), .nl)
        XCTAssertEqual(I18n.language, .nl)
        XCTAssertEqual(I18n.localeTag, "nl-BE")
        I18n.setWidgetLanguage("de", languages: ["nl-BE"])
        XCTAssertEqual(I18n.localeTag, "de")
        I18n.setWidgetLanguage("fr", languages: ["fr_CA"])
        XCTAssertEqual(I18n.localeTag, "fr-CA")
    }

    // MARK: - The words

    func testTDrawsTheActiveLanguage() {
        XCTAssertEqual(I18n.t("chat.composer.send"), "Send")
        I18n.setWidgetLanguage("de", languages: [])
        XCTAssertEqual(I18n.t("chat.composer.send"), I18n.table(.de)["chat.composer.send"])
        XCTAssertNotEqual(I18n.t("chat.composer.send"), "Send")
    }

    func testPlaceholdersAreFilledAMissingValueKeepsItsBraces() {
        XCTAssertEqual(I18n.tFor(.en, "rating.outOf", ["n": 3, "max": 5]), "3 out of 5")
        XCTAssertEqual(I18n.tFor(.en, "rating.outOf", ["n": 3]), "3 out of {max}")
        XCTAssertEqual(I18n.tFor(.en, "rating.outOf", ["n": 3.0, "max": NSNull()]), "3 out of {max}")
        XCTAssertTrue(I18n.tFor(.fr, "mailchat.sent", ["email": "a@b.co"]).contains("a@b.co"))
    }

    func testPluralsOneForOneOtherOtherwise() {
        XCTAssertEqual(I18n.tPlural("otp.wrongLeft", 1), "That code isn't right. 1 try left.")
        XCTAssertEqual(I18n.tPlural("otp.wrongLeft", 2), "That code isn't right. 2 tries left.")
        XCTAssertEqual(I18n.tPlural("otp.wrongLeft", 0), "That code isn't right. 0 tries left.")
        I18n.setWidgetLanguage("es", languages: [])
        XCTAssertEqual(I18n.tPlural("otp.wrongLeft", 1), I18n.table(.es)["otp.wrongLeft.one"]!.replacingOccurrences(of: "{n}", with: "1"))
    }

    func testAKeyALanguageLacksFallsBackToEnglishThenToTheKey() {
        let json = #"{"strings":{"en":{"common.close":"Close","only.en":"Only"},"de":{"common.close":"Schließen"}}}"#
        let tables = I18n.parse(Data(json.utf8))
        XCTAssertEqual(I18n.tFor(.de, "common.close", nil, in: tables), "Schließen")
        XCTAssertEqual(I18n.tFor(.de, "only.en", nil, in: tables), "Only")
        XCTAssertEqual(I18n.tFor(.de, "no.such.key", nil, in: tables), "no.such.key")
        XCTAssertEqual(I18n.tFor(.de, "no.such.key"), "no.such.key")
    }

    func testOwnerFieldsTheStockEnglishShowsTranslatedTheOwnersOwnWordsAsWritten() {
        I18n.setWidgetLanguage("de", languages: [])
        XCTAssertEqual(I18n.ownerTextOr("", "common.close"), I18n.t("common.close"))
        XCTAssertEqual(I18n.ownerTextOr(nil, "common.close"), I18n.t("common.close"))
        XCTAssertEqual(I18n.ownerTextOr("Close.", "common.close"), I18n.t("common.close"))
        XCTAssertEqual(I18n.ownerTextOr("<b>close</b>!", "common.close"), I18n.t("common.close"))
        XCTAssertEqual(I18n.ownerTextOr("Schließen bitte", "common.close"), "Schließen bitte")
        XCTAssertEqual(I18n.ownerTextOr("Shut it", "common.close", stockEnglish: ["Shut it"]), I18n.t("common.close"))
        XCTAssertEqual(I18n.stockText("", "common.close"), "")
        XCTAssertEqual(I18n.stockText(nil, "common.close"), "")
        XCTAssertEqual(I18n.stockText("close", "common.close"), I18n.t("common.close"))
        XCTAssertEqual(I18n.stockText("Bye", "common.close"), "Bye")
    }

    func testDayAndMonthNamesInTheLanguageEnglishKeepsItsOwn() {
        XCTAssertEqual(I18n.weekdayNames("short", english: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])[1], "Mon")
        XCTAssertEqual(I18n.monthNames("short", english: ["Jan"])[0], "Jan")
        I18n.setWidgetLanguage("de", languages: [])
        XCTAssertEqual(I18n.weekdayNames("long"), ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"])
        XCTAssertEqual(I18n.monthNames("long").first, "Januar")
        XCTAssertEqual(I18n.monthNames("long").count, 12)
    }

    func testTheGamesListsPerLanguageEnglishForAnyOther() {
        XCTAssertFalse(I18n.trivia("de").isEmpty)
        XCTAssertNotEqual(I18n.trivia("de").first?["q"] as? String, I18n.trivia("en").first?["q"] as? String)
        XCTAssertEqual(I18n.words("xx").first?["w"] as? String, I18n.words("en").first?["w"] as? String)
    }

    // MARK: - The tables

    func testEveryKeyIsInAllFiveLanguagesNoneEmpty() {
        XCTAssertGreaterThan(keys.count, 800)
        for lang in I18n.supported {
            let dict = I18n.table(lang)
            let missing = keys.filter { (dict[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            XCTAssertEqual(missing, [], "\(lang) is missing keys")
            XCTAssertEqual(dict.keys.filter { I18n.english[$0] == nil }, [], "\(lang) has keys English lacks")
        }
    }

    func testEachTranslationHasTheSamePlaceholdersAsTheEnglish() {
        for lang in I18n.supported {
            let dict = I18n.table(lang)
            // queue.position: the web passes both {n} and {ord}; English says
            // "{ord}", the others "{n}".
            let off = keys.filter { $0 != "queue.position" && placeholders(dict[$0] ?? "") != placeholders(I18n.english[$0] ?? "") }
            XCTAssertEqual(off.sorted(), [], "\(lang) placeholders differ")
        }
    }

    func testEveryOneHasItsOther() {
        let lonely = keys.filter {
            $0.hasSuffix(".one") && I18n.english[String($0.dropLast(4)) + ".other"] == nil
                && !["sources.one", "requests.one"].contains($0)
        }
        XCTAssertEqual(lonely, [])
    }

    /// The bundled table is RN's scripts/parity/i18n/strings.json as it is now
    /// (run scripts/sync-i18n.sh after it changes). Skipped without RN beside
    /// this repo.
    func testTheBundledTableIsRNsStringsJson() throws {
        let rn = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("conferbot-react-native/scripts/parity/i18n/strings.json")
        guard let theirs = try? Data(contentsOf: rn) else {
            throw XCTSkip("conferbot-react-native is not checked out beside this repo")
        }
        let url = try XCTUnwrap(I18n.resourceURL, "i18n-strings.json is not in the SDK's resources")
        let ours = try Data(contentsOf: url)
        XCTAssertTrue(ours == theirs, "Resources/i18n-strings.json is stale: run scripts/sync-i18n.sh")
        // And what was loaded is that file.
        XCTAssertEqual(I18n.english.count, I18n.parse(theirs).strings["en"]?.count)
    }
}
