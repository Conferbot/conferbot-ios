//
//  DeviceLanguageTests.swift
//  The phone's language as the web's visitorInsights.language.browser on
//  every response record (#44). The same cases as the React Native SDK's
//  deviceLanguage.test.ts.
//

import XCTest
@testable import Conferbot

final class DeviceLanguageTests: XCTestCase {

    func testLocalesAreWrittenAsTheBrowserWritesThem() {
        XCTAssertEqual(DeviceLanguage.normalize("de_DE"), "de-DE")
        XCTAssertEqual(DeviceLanguage.normalize("en-US"), "en-US")
        XCTAssertEqual(DeviceLanguage.normalize("en_US@calendar=gregorian"), "en-US")
        XCTAssertEqual(DeviceLanguage.normalize("en-US-u-ca-buddhist"), "en-US")
        XCTAssertEqual(DeviceLanguage.normalize("zh-Hant-TW"), "zh-Hant-TW")
        XCTAssertEqual(DeviceLanguage.normalize("  fr  "), "fr")
        XCTAssertEqual(DeviceLanguage.normalize(""), "")
        XCTAssertEqual(DeviceLanguage.normalize("1234"), "")
        XCTAssertEqual(DeviceLanguage.normalize(nil), "")
        // Cut to 16 characters, as the web cuts it.
        XCTAssertEqual(DeviceLanguage.normalize("sr-Latn-RS-x-private-long"), "sr-Latn-RS-x-pri")
    }

    func testThePreferredLanguageWinsThenTheRegion() {
        XCTAssertEqual(DeviceLanguage.localeOf(preferred: ["de-DE", "en-US"], current: "en_GB"), "de-DE")
        XCTAssertEqual(DeviceLanguage.localeOf(preferred: [], current: "en_GB"), "en-GB")
        XCTAssertEqual(DeviceLanguage.localeOf(preferred: ["??"], current: nil), "")
    }

    func testTheInsightsCarryOnlyTheLanguage() {
        let insights = DeviceLanguage.visitorInsights("de-DE")
        XCTAssertEqual(insights?["v"] as? Int, 1)
        XCTAssertEqual((insights?["language"] as? [String: Any])?["browser"] as? String, "de-DE")
        XCTAssertEqual(insights?.count, 2)
        XCTAssertNil(DeviceLanguage.visitorInsights(""))
    }

    func testEveryResponseRecordCarriesTheDeviceLanguage() {
        let state = ChatState()
        state.deviceLanguage = { "de-DE" }
        let data = state.buildResponseData(chatSessionId: "s1", botId: "b1")
        let insights = data["visitorInsights"] as? [String: Any]
        XCTAssertEqual((insights?["language"] as? [String: Any])?["browser"] as? String, "de-DE")

        // Unknown: left out.
        state.deviceLanguage = { "" }
        XCTAssertNil(state.buildResponseData(chatSessionId: "s1", botId: "b1")["visitorInsights"])
    }

    func testThePhoneIsReadOnce() {
        DeviceLanguage.reset()
        let first = DeviceLanguage.current
        XCTAssertEqual(DeviceLanguage.current, first)
        XCTAssertEqual(first, DeviceLanguage.normalize(first))
    }
}
