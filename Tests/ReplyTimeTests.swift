//
//  ReplyTimeTests.swift
//  The header's status (Core/LiveChat/ReplyTime), the same cases as the
//  React Native SDK's replyTime.test.ts (the web widget's
//  tests/replyTime.test.js), plus a person in the chat (web headerPresence.ts)
//  and the home card's homeLine / homePeople.
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
    // MARK: - The home card (the web's tests/replyTime.test.js homeLine, homePeople)

    private func line(_ text: String, _ tone: ReplyTime.Tone) -> ReplyTime.HomeLine { .line(.init(text, tone)) }

    func testTheHomeCardLineForEachCase() {
        XCTAssertEqual(ReplyTime.homeLine(online("few_minutes")), line("The team typically replies in a few minutes", .online))
        XCTAssertNil(ReplyTime.homeLine(online(nil)))
        XCTAssertNil(ReplyTime.homeLine(nil))
        let now = date(2026, 10, 3, 20)
        var away = online("few_minutes")
        away["state"] = "away"
        away["backAt"] = iso(date(2026, 10, 5, 9))
        XCTAssertEqual(ReplyTime.homeLine(away, now: now, timeZone: utc), line("We're away right now \u{00B7} back Monday 9 AM", .away))
        var offline = online("few_minutes")
        offline["state"] = "offline"
        XCTAssertEqual(ReplyTime.homeLine(offline), line("The team is offline \u{00B7} we'll reply by email", .away))
        offline["leaveMessage"] = false
        XCTAssertEqual(ReplyTime.homeLine(offline), line("The team is offline right now", .away))
        XCTAssertEqual(ReplyTime.homeLine(["mode": "hide", "handover": true]), .hide)
        XCTAssertEqual(ReplyTime.homeLine(online("few_minutes"), agent: true), line("Answers instantly \u{00B7} team replies in a few minutes", .online))
        XCTAssertEqual(ReplyTime.homeLine(away, agent: true, now: now, timeZone: utc), line("Answers instantly \u{00B7} team back Monday 9 AM", .away))
        XCTAssertNil(ReplyTime.homeLine(["mode": "hide", "handover": true], agent: true))
    }

    func testTheHomeCardsPromisePlainWordsNeverASpeedPromiseWhenNobodyIsThere() {
        let now = date(2026, 10, 8, 22)
        func p(_ rt: [String: Any]?, agent: Bool = false) -> ReplyTime.Line { ReplyTime.homePeople(rt, agent: agent, now: now, timeZone: utc) }
        func with(_ extra: [String: Any]) -> [String: Any] { online("few_minutes").merging(extra) { $1 } }
        let tomorrow9 = iso(date(2026, 10, 9, 9))
        XCTAssertEqual(p(online("few_minutes")), .init("Usually replies in a few minutes", .online))
        XCTAssertEqual(p(with(["mode": "fixed", "text": "We reply within 2 hours"])), .init("We reply within 2 hours", .online))
        XCTAssertEqual(p(online(nil)), .init("Usually replies instantly", .online))
        XCTAssertEqual(p(nil), .init("Answers instantly, day or night", .online))
        XCTAssertEqual(p(with(["handover": false])), .init("Answers instantly, day or night", .online))
        XCTAssertEqual(p(with(["state": "offline"])).text, "Team replies by email")
        XCTAssertEqual(p(with(["state": "offline", "backAt": tomorrow9])).text, "Team back tomorrow 9 AM")
        XCTAssertEqual(p(with(["state": "away", "backAt": tomorrow9])).text, "Team back tomorrow 9 AM")
        XCTAssertEqual(p(with(["state": "away", "leaveMessage": false])).text, "Team away right now")
        XCTAssertEqual(p(["mode": "hide", "handover": true]).text, "")
        XCTAssertEqual(p(nil, agent: true), .init("Answers instantly, day or night", .online))
        XCTAssertEqual(p(with(["state": "offline"]), agent: true), .init("Answers instantly, day or night", .online))
        XCTAssertEqual(p(["mode": "hide", "handover": true], agent: true).text, "Answers instantly, day or night")
    }
}
