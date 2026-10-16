//
//  RequestsTests.swift
//  "Your requests" (Core/Requests/Requests.swift): the web's words.ts,
//  store.ts and api.ts (conferbot-widget src/ts/home/requests/), against the
//  payloads of embed-server socket/handlers/visitorRequestsHandler.js. The
//  same cases as the React Native SDK's __tests__/core/requests.test.ts.
//

import XCTest
@testable import Conferbot

final class RequestsTests: XCTestCase {

    // Fri 16 Oct 2026, 15:00 local
    private let now: Double = {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (2026, 10, 16, 15)
        return Calendar.current.date(from: c)!.timeIntervalSince1970 * 1000
    }()

    private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> String {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (y, m, d, h)
        return Requests.iso(Calendar.current.date(from: c)!.timeIntervalSince1970 * 1000)
    }

    private func req(_ id: String = "mobile_1_abcdef", status: RequestSummary.Status = .open, lastAt: String?? = nil,
                     lastFrom: RequestSummary.From = .team, teamName: String = "Ada") -> RequestSummary {
        RequestSummary(id: id, title: "My invoice is wrong", status: status,
                       lastAt: lastAt ?? Requests.iso(now - 2 * 3_600_000), lastFrom: lastFrom, lastText: "Fixed it", teamName: teamName)
    }

    // MARK: - The words

    func testStateWords() {
        XCTAssertEqual(Requests.stateOf(req()), .replied)
        XCTAssertEqual(Requests.stateOf(req(lastFrom: .you)), .waiting)
        XCTAssertEqual(Requests.stateOf(req(status: .solved)), .solved)
        XCTAssertEqual(Requests.stateWords(.replied).label, "We replied")
        XCTAssertEqual(Requests.stateWords(.waiting).label, "We're on it")
        XCTAssertEqual(Requests.stateWords(.solved).detail, "Still need help with this? Write below and we'll pick it up again.")
    }

    func testNewReply() {
        let r = req()
        XCTAssertTrue(Requests.isNewReply(r, seen: [:]))
        XCTAssertFalse(Requests.isNewReply(r, seen: [r.id: now]))
        XCTAssertFalse(Requests.isNewReply(req(status: .solved), seen: [:]))
        XCTAssertFalse(Requests.isNewReply(req(lastFrom: .you), seen: [:]))
        XCTAssertEqual(Requests.unreadCount([r, req("other_123", lastFrom: .you)], seen: [:]), 1)
        XCTAssertEqual(Requests.unreadCount(nil, seen: [:]), 0)
    }

    func testWhenWords() {
        XCTAssertEqual(Requests.whenWords(Requests.iso(now - 20000), now: now), "Just now")
        XCTAssertEqual(Requests.whenWords(Requests.iso(now - 5 * 60000), now: now), "5 min ago")
        XCTAssertEqual(Requests.whenWords(Requests.iso(now - 70 * 60000), now: now), "1 hour ago")
        XCTAssertEqual(Requests.whenWords(Requests.iso(now - 3 * 3_600_000), now: now), "3 hours ago")
        XCTAssertEqual(Requests.whenWords(local(2026, 10, 15, 20), now: now), "Yesterday")
        XCTAssertEqual(Requests.whenWords(local(2026, 10, 12, 9), now: now), "Monday")
        XCTAssertEqual(Requests.whenWords(local(2026, 10, 3, 9), now: now), "3 Oct")
        XCTAssertEqual(Requests.whenWords(local(2025, 12, 24, 9), now: now), "24 Dec 2025")
        XCTAssertEqual(Requests.whenWords(nil, now: now), "")
        XCTAssertEqual(Requests.whenWords("nonsense", now: now), "")
        // The server's dates without milliseconds read too.
        XCTAssertEqual(Requests.whenWords("2026-10-16T12:00:00Z", now: Requests.ms("2026-10-16T12:05:00.000Z")), "5 min ago")
    }

    func testRowLine() {
        XCTAssertEqual(Requests.rowLine(req(), seen: [:], now: now), "New reply from Ada · 2 hours ago")
        XCTAssertEqual(Requests.rowLine(req(teamName: ""), seen: [:], now: now), "New reply · 2 hours ago")
        XCTAssertEqual(Requests.rowLine(req(), seen: ["mobile_1_abcdef": now], now: now), "We replied · 2 hours ago")
        XCTAssertEqual(Requests.rowLine(req(lastAt: .some(nil), lastFrom: .you), seen: [:], now: now), "We're on it")
    }

    func testOrdered() {
        let a = req("aaaaaa", lastAt: Requests.iso(now - 1000), lastFrom: .you)
        let b = req("bbbbbb", lastAt: Requests.iso(now - 9000))
        let c = req("cccccc", lastAt: Requests.iso(now - 5000), lastFrom: .you)
        XCTAssertEqual(Requests.ordered([a, b, c], seen: [:]).map(\.id), ["bbbbbb", "aaaaaa", "cccccc"])
        XCTAssertEqual(Requests.ordered([a, b, c], seen: ["bbbbbb": now]).map(\.id), ["aaaaaa", "cccccc", "bbbbbb"])
    }

    func testSeenAt() {
        XCTAssertEqual(Requests.seenAt(Requests.iso(now + 60000), now: now), now + 60000)
        XCTAssertEqual(Requests.seenAt(nil, now: now), now)
    }

    func testLinkRuns() {
        let runs = Requests.linkRuns("See https://example.com/a?b=1. Thanks")
        XCTAssertEqual(runs.map(\.text), ["See ", "https://example.com/a?b=1", ". Thanks"])
        XCTAssertEqual(runs.map(\.url), [nil, "https://example.com/a?b=1", nil])
        XCTAssertEqual(Requests.linkRuns("no links").map(\.text), ["no links"])
        XCTAssertTrue(Requests.linkRuns("").isEmpty)
    }

    func testMenu() {
        XCTAssertEqual(Requests.Text.menu(0), "Your requests")
        XCTAssertEqual(Requests.Text.menu(2), "Your requests · New reply")
    }

    // MARK: - What the device remembers

    func testParseMemory() {
        let raw = #"{"sessions":["mobile_1_abcdef","bad id!",42,"x"],"seen":{"mobile_1_abcdef":5,"no way":3,"other_123":"x"}}"#
        XCTAssertEqual(Requests.parseMemory(raw), RequestMemory(sessions: ["mobile_1_abcdef"], seen: ["mobile_1_abcdef": 5]))
        XCTAssertEqual(Requests.parseMemory(nil), RequestMemory())
        XCTAssertEqual(Requests.parseMemory("{nope"), RequestMemory())
        XCTAssertEqual(Requests.storageKey("bot1"), "conferbot_requests_bot1")
    }

    func testSessionsFirstOnceThirtyKept() {
        var m = RequestMemory()
        for i in 0..<35 { m = Requests.withSession(m, "mobile_\(i)_abcdef") ?? m }
        XCTAssertEqual(m.sessions.count, 30)
        XCTAssertEqual(m.sessions.first, "mobile_34_abcdef")
        XCTAssertNil(Requests.withSession(m, "mobile_34_abcdef"))
        XCTAssertNil(Requests.withSession(m, "short"))
        XCTAssertEqual(Requests.withSession(m, "mobile_3_abcdef")?.sessions.first, "mobile_3_abcdef")
    }

    func testReadMarksForwardNewestSixtyKept() {
        var m = RequestMemory()
        m = Requests.withSeen(m, "mobile_1_abcdef", at: 10)!
        XCTAssertEqual(m.seen["mobile_1_abcdef"], 10)
        XCTAssertNil(Requests.withSeen(m, "mobile_1_abcdef", at: 5))
        for i in 0..<70 { m = Requests.withSeen(m, "mobile_\(i)_zzzzzz", at: Double(i + 1))! }
        let back = Requests.parseMemory(Requests.serializeMemory(m))
        XCTAssertEqual(back.seen.count, 60)
        XCTAssertEqual(back.seen["mobile_69_zzzzzz"], 70)
        XCTAssertNil(back.seen["mobile_1_abcdef"])
        // A mark read again moves last and is kept, whatever its time.
        m = Requests.withSeen(m, "mobile_0_zzzzzz", at: 100)!
        XCTAssertEqual(Requests.parseMemory(Requests.serializeMemory(m)).seen["mobile_0_zzzzzz"], 100)
    }

    func testVisitorEntry() {
        XCTAssertFalse(Requests.hasVisitorEntry([["type": "bot-message"]]))
        XCTAssertTrue(Requests.hasVisitorEntry([["type": "bot-message"], ["type": "user-message"]]))
        XCTAssertTrue(Requests.hasVisitorEntry([["shape": "user-live-message"]]))
        XCTAssertFalse(Requests.hasVisitorEntry(nil))
    }

    // MARK: - Who is asking

    func testWho() {
        let m = RequestMemory(sessions: ["mobile_1_abcdef"])
        let plain = Requests.who(visitorId: "v_1", memory: m, user: nil).payload
        XCTAssertEqual(plain["visitorId"] as? String, "v_1")
        XCTAssertEqual(plain["sessions"] as? [String], ["mobile_1_abcdef"])
        XCTAssertNil(plain["user"])
        let signed = Requests.who(visitorId: "v_1", memory: m, user: RequestsUser(id: "u1", email: "a@b.co", hash: "h")).payload
        XCTAssertEqual(signed["user"] as? [String: String], ["id": "u1", "email": "a@b.co", "hash": "h"])
        XCTAssertEqual(Requests.who(visitorId: nil, memory: m, user: nil).visitorId, "")
    }

    func testCanAsk() {
        XCTAssertFalse(Requests.canAsk(memory: RequestMemory(), user: nil))
        XCTAssertFalse(Requests.canAsk(memory: RequestMemory(), user: RequestsUser(id: "u1")))
        XCTAssertTrue(Requests.canAsk(memory: RequestMemory(), user: RequestsUser(id: "u1", hash: "h")))
        XCTAssertTrue(Requests.canAsk(memory: RequestMemory(sessions: ["mobile_1_abcdef"]), user: nil))
    }

    // MARK: - The server

    private final class FakeSocket {
        var answers: [String: Any] = [:]
        var acks: [(event: String, data: [String: Any], timeout: Double)] = []
        var emits: [(event: String, data: [String: Any])] = []
        let hub = RequestsEventHub()

        var socket: RequestsSocket {
            RequestsSocket(
                emitWithAck: { e, d, t, done in
                    self.acks.append((e, d, t))
                    done(self.answers[e])
                },
                emit: { e, d in self.emits.append((e, d)) },
                on: { e, fn in self.hub.on(e, fn) }
            )
        }
    }

    private let who = { RequestsWho(visitorId: "v_1", sessions: ["mobile_1_abcdef"]) }

    private func json(_ r: RequestSummary, messages: [[String: Any]]? = nil) -> [String: Any] {
        var d: [String: Any] = ["id": r.id, "title": r.title, "status": r.status.rawValue, "lastFrom": r.lastFrom.rawValue,
                                "lastText": r.lastText, "teamName": r.teamName]
        if let at = r.lastAt { d["lastAt"] = at }
        if let m = messages { d["messages"] = m }
        return d
    }

    func testList() async {
        let s = FakeSocket()
        s.answers["my-requests"] = ["ok": true, "requests": [json(req())]]
        let got = await Requests.api(socket: s.socket, who: who).list()
        XCTAssertEqual(got, [req()])
        XCTAssertEqual(s.acks.first?.event, "my-requests")
        XCTAssertEqual(s.acks.first?.data["visitorId"] as? String, "v_1")
        XCTAssertEqual(s.acks.first?.data["sessions"] as? [String], ["mobile_1_abcdef"])
        XCTAssertEqual(s.acks.first?.timeout, 10)
        let refused = FakeSocket()
        refused.answers["my-requests"] = ["ok": false]
        let none = await Requests.api(socket: refused.socket, who: who).list()
        XCTAssertNil(none)
        let silent = await Requests.api(socket: FakeSocket().socket, who: who).list()
        XCTAssertNil(silent)
    }

    func testOpenCloseReply() async {
        let s = FakeSocket()
        let msgs: [[String: Any]] = [["id": "m1", "from": "you", "name": "", "text": "Hi", "at": NSNull()],
                                     ["id": "m2", "from": "team", "name": "Ada", "text": "Hello", "at": "2026-10-16T12:00:00.000Z"]]
        s.answers["my-request-open"] = ["ok": true, "request": json(req(), messages: msgs)]
        s.answers["my-request-reply"] = ["ok": false, "reason": "locked"]
        let api = Requests.api(socket: s.socket, who: who)
        let detail = await api.open("mobile_1_abcdef")
        XCTAssertEqual(detail?.summary, req())
        XCTAssertEqual(detail?.messages, [RequestMessage(id: "m1", from: .you, text: "Hi"),
                                          RequestMessage(id: "m2", from: .team, name: "Ada", text: "Hello", at: "2026-10-16T12:00:00.000Z")])
        XCTAssertEqual(s.acks.last?.event, "my-request-open")
        XCTAssertEqual(s.acks.last?.data["chatSessionId"] as? String, "mobile_1_abcdef")
        XCTAssertEqual(s.acks.last?.data["visitorId"] as? String, "v_1")

        let locked = await api.reply("mobile_1_abcdef", "hi", "request-reply-x")
        XCTAssertEqual(locked, ReplyResult(ok: false, reason: "locked"))
        let sent = s.acks.last!
        XCTAssertEqual(sent.event, "my-request-reply")
        XCTAssertEqual(sent.data["chatSessionId"] as? String, "mobile_1_abcdef")
        XCTAssertEqual(sent.data["text"] as? String, "hi")
        XCTAssertEqual(sent.data["entryId"] as? String, "request-reply-x")
        XCTAssertEqual(sent.data["sessions"] as? [String], ["mobile_1_abcdef"])
        XCTAssertEqual(sent.timeout, 10)

        api.close("mobile_1_abcdef")
        XCTAssertEqual(s.emits.last?.event, "my-request-close")
        XCTAssertEqual(s.emits.last?.data as? [String: String], ["chatSessionId": "mobile_1_abcdef"])

        let offline = await Requests.api(socket: FakeSocket().socket, who: who).reply("a", "b", "c")
        XCTAssertEqual(offline, ReplyResult(ok: false, reason: "offline"))
        let missing = FakeSocket()
        missing.answers["my-request-open"] = ["ok": false, "reason": "not_found"]
        let notFound = await Requests.api(socket: missing.socket, who: who).open("x")
        XCTAssertNil(notFound)
        for reason in ["not_found", "empty", "error"] {
            let f = FakeSocket()
            f.answers["my-request-reply"] = ["ok": false, "reason": reason]
            let r = await Requests.api(socket: f.socket, who: who).reply("a", "b", "c")
            XCTAssertEqual(r, ReplyResult(ok: false, reason: reason))
        }
    }

    func testUpdatesAndReconnect() async {
        let s = FakeSocket()
        s.answers["my-request-open"] = ["ok": true, "request": json(req(), messages: [])]
        let api = Requests.api(socket: s.socket, who: who)
        var seen: [String] = []
        let off = api.onUpdate { seen.append($0) }
        s.hub.fire("my-request-update", ["chatSessionId": "other_123"])
        s.hub.fire("my-request-update", [String: Any]())
        s.hub.fire("connect")
        XCTAssertEqual(seen, ["other_123"])
        _ = await api.open("mobile_1_abcdef")
        s.hub.fire("connect")
        XCTAssertEqual(seen, ["other_123", "mobile_1_abcdef"])
        api.close("mobile_1_abcdef")
        s.hub.fire("connect")
        off()
        s.hub.fire("my-request-update", ["chatSessionId": "other_123"])
        XCTAssertEqual(seen, ["other_123", "mobile_1_abcdef"])
    }

    func testReplyEntryId() {
        let id = Requests.replyEntryId(now: now, rand: { 0.123456789 })
        XCTAssertNotNil(id.range(of: "^request-reply-[A-Za-z0-9_-]{1,60}$", options: .regularExpression))
        XCTAssertTrue(id.hasPrefix("request-reply-\(String(Int64(now), radix: 36))"))
        // JS (0.123456789).toString(36).slice(2, 8)
        XCTAssertEqual(Requests.base36Fraction(0.123456789, digits: 6), "4fzzzx")
    }

    // MARK: - The accent

    func testAccent() {
        XCTAssertEqual(Requests.accent(["brandColor": "#0808EE", "headerBgColor": "#ff0000"]), "#0808EE")
        XCTAssertEqual(Requests.accent(["brandColor": "#0808EE", "_themePalette": true, "headerBgColor": "#123456"]), "#123456")
        XCTAssertEqual(Requests.accent(["brandColor": "#0808EE", "themeAccent": "#ffffff", "headerBgColor": "#123456"]), "#123456")
        XCTAssertEqual(Requests.accent(["headerBgColor": "#ffffff", "widgetIconBgColor": "#222222"]), "#222222")
        XCTAssertEqual(Requests.accent(["headerBgColor": "#fff"]), "#4F46E5")
        XCTAssertEqual(Requests.accent(nil), "#4F46E5")
    }
}
