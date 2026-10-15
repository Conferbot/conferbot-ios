//
//  ReplyTimeTests.swift
//  The header's status (Core/LiveChat/ReplyTime), the same cases as the
//  React Native SDK's replyTime.test.ts (the web widget's
//  tests/replyTime.test.js), plus a person in the chat (web headerPresence.ts).
//

import XCTest
@testable import Conferbot

final class ReplyTimeTests: XCTestCase {

    let utc = TimeZone(identifier: "UTC")!

    private func online(_ bucket: String?) -> [String: Any] {
        var rt: [String: Any] = ["mode": "auto", "handover": true, "state": "online", "leaveMessage": true]
        rt["bucket"] = bucket
        return rt
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    func testABucketReadsAsAnHonestPhrase() {
        XCTAssertEqual(ReplyTime.headerLine(online("few_minutes")), "Typically replies in a few minutes")
        XCTAssertEqual(ReplyTime.headerLine(online("day")), "Typically replies within a day")
    }

    func testNoDataAnOlderServerOrNoHandoverKeepsOnline() {
        XCTAssertNil(ReplyTime.headerLine(online(nil)))
        XCTAssertNil(ReplyTime.headerLine(nil))
        XCTAssertNil(ReplyTime.headerLine(online("few_minutes").merging(["handover": false]) { $1 }))
    }

    func testAwayOnlineAndWhenTheTeamIsBack() {
        let now = date(2026, 10, 3, 20)
        var rt = online("few_minutes")
        rt["state"] = "away"
        rt["backAt"] = iso(date(2026, 10, 5, 9))
        XCTAssertEqual(ReplyTime.headerLine(rt, now: now, timeZone: utc), "Online \u{00B7} team back Monday 9 AM")
        rt["backAt"] = nil
        XCTAssertEqual(ReplyTime.headerLine(rt, now: now, timeZone: utc), "Online \u{00B7} team replies by email")
        XCTAssertEqual(ReplyTime.backWhen(iso(date(2026, 10, 4, 9, 30)), now: now, timeZone: utc), "tomorrow 9:30 AM")
        XCTAssertEqual(ReplyTime.backWhen(iso(date(2026, 10, 3, 22)), now: now, timeZone: utc), "at 10 PM")
        XCTAssertEqual(ReplyTime.backWhen(iso(date(2026, 10, 12, 9)), now: now, timeZone: utc), "Mon, Oct 12 9 AM")
        XCTAssertEqual(ReplyTime.backWhen("nope", now: now, timeZone: utc), "")
    }

    func testOfflineEmailOnlyWhenLeaveAMessageIsOn() {
        var rt = online("few_minutes")
        rt["state"] = "offline"
        XCTAssertEqual(ReplyTime.headerLine(rt), "Online \u{00B7} team replies by email")
        rt["leaveMessage"] = false
        XCTAssertEqual(ReplyTime.headerLine(rt), "Online \u{00B7} team away right now")
    }

    func testTheOwnersFixedWordsOrNothingAnAIAgentBotShowsNone() {
        XCTAssertEqual(ReplyTime.headerLine(online(nil).merging(["mode": "fixed", "text": "We reply within 2 hours"]) { $1 }), "We reply within 2 hours")
        XCTAssertNil(ReplyTime.headerLine(["mode": "hide", "handover": true]))
        XCTAssertNil(ReplyTime.headerLine(online("few_minutes"), agent: true))
    }

    func testHeaderStatusReplyTimeBeforeAnyoneJoinsPlainOnlineOnceAPersonIsIn() {
        var rt = online("few_minutes")
        rt["state"] = "offline"
        XCTAssertEqual(ReplyTime.headerStatus(rt), "Online \u{00B7} team replies by email")
        XCTAssertEqual(ReplyTime.headerStatus(rt, personInChat: true), "Online")
        XCTAssertEqual(ReplyTime.headerStatus(nil), "Online")
        XCTAssertNil(ReplyTime.headerStatus(rt, hidden: true))
    }
}
