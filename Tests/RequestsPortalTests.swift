//
//  RequestsPortalTests.swift
//  "Your requests" screens as states (Core/Requests/RequestsPortal.swift;
//  web conferbot-widget src/ts/home/requests/view.ts mountRequestsView).
//  The same cases as the React Native SDK's requestsPortal.test.ts, and the
//  store around it (YourRequests: remembered chats, asked only for a
//  returning visitor, read marks in UserDefaults).
//

import XCTest
@testable import Conferbot

/// An answer the test hands over when it chooses.
private final class Gate<T> {
    private var k: CheckedContinuation<T, Never>?
    private var value: T?
    func wait() async -> T {
        if let v = value { return v }
        return await withCheckedContinuation { self.k = $0 }
    }
    func open(_ v: T) {
        if let k = k { self.k = nil; k.resume(returning: v) } else { value = v }
    }
}

@MainActor
final class RequestsPortalTests: XCTestCase {

    private let now = Double(Date(timeIntervalSince1970: 1_792_152_000).timeIntervalSince1970 * 1000) // 2026-10-16 12:00 UTC

    private func summary(_ id: String = "mobile_1_abcdef", status: RequestSummary.Status = .open, lastFrom: RequestSummary.From = .team) -> RequestSummary {
        RequestSummary(id: id, title: "My invoice is wrong", status: status, lastAt: Requests.iso(now - 60000),
                       lastFrom: lastFrom, lastText: "Fixed it", teamName: "Ada")
    }

    private func detail(status: RequestSummary.Status = .open, lastFrom: RequestSummary.From = .team, extra: [RequestMessage] = []) -> RequestDetail {
        RequestDetail(summary: summary(status: status, lastFrom: lastFrom), messages: [
            RequestMessage(id: "m1", from: .you, text: "My invoice is wrong", at: Requests.iso(now - 120000)),
            RequestMessage(id: "m2", from: .team, name: "Ada", text: "Fixed it", at: Requests.iso(now - 60000)),
        ] + extra)
    }

    /// The fake server: each call answers from its queue (or the default), or waits at a gate.
    private final class FakeApi {
        var list: [[RequestSummary]?] = []
        var listDefault: [RequestSummary]?
        var open: [Any] = []                 // RequestDetail? or Gate<RequestDetail?>
        var openDefault: RequestDetail?
        var reply: [Any] = []                // ReplyResult or Gate<ReplyResult>
        var replyDefault = ReplyResult(ok: false, reason: "error")
        var listCalls = 0, openCalls = 0
        var replies: [(id: String, text: String, entryId: String)] = []
        var closed: [String] = []
        var update: ((String) -> Void)?
        var onUpdateCalls = 0

        var api: RequestsApi {
            RequestsApi(
                list: {
                    self.listCalls += 1
                    return self.list.isEmpty ? self.listDefault : self.list.removeFirst()
                },
                open: { _ in
                    self.openCalls += 1
                    let next: Any? = self.open.isEmpty ? nil : self.open.removeFirst()
                    if let g = next as? Gate<RequestDetail?> { return await g.wait() }
                    if let next = next { return next as? RequestDetail }
                    return self.openDefault
                },
                close: { id in self.closed.append(id) },
                reply: { id, text, entryId in
                    self.replies.append((id, text, entryId))
                    let next: Any? = self.reply.isEmpty ? nil : self.reply.removeFirst()
                    if let g = next as? Gate<ReplyResult> { return await g.wait() }
                    return (next as? ReplyResult) ?? self.replyDefault
                },
                onUpdate: { fn in
                    self.onUpdateCalls += 1
                    self.update = fn
                    return { [weak self] in self?.update = nil }
                }
            )
        }
    }

    private var fake: FakeApi!
    private var seen: [String: Double] = [:]
    private var marks: [(String, Double)] = []
    private var chatOpened = 0
    private var changed = 0

    private func setup(current: String? = nil) -> RequestsPortal {
        fake = FakeApi()
        fake.listDefault = [summary()]
        fake.openDefault = detail()
        seen = [:]
        marks = []
        chatOpened = 0
        changed = 0
        var deps = RequestsPortal.Deps(
            api: fake.api,
            seen: { [unowned self] in self.seen },
            markSeen: { [unowned self] id, at in self.marks.append((id, at)); self.seen[id] = at },
            isCurrentChat: { $0 == current },
            openChat: { [unowned self] in self.chatOpened += 1 },
            onChanged: { [unowned self] in self.changed += 1 }
        )
        deps.now = { [unowned self] in self.now }
        deps.rand = { 0.5 }
        return RequestsPortal(deps)
    }

    private func flush() async {
        for _ in 0..<30 { await Task.yield() }
    }

    // MARK: - The list

    func testListLoadingThenOrderedBackLeaves() async {
        let p = setup()
        fake.listDefault = [summary("old_aaaaaa", lastFrom: .you), summary()]
        let gate = Gate<Void>()
        Task { await p.openList(); gate.open(()) }
        await Task.yield()
        XCTAssertEqual(p.state.screen, .list)
        XCTAssertEqual(p.state.title, "Your requests")
        await gate.wait()
        XCTAssertFalse(p.state.loading)
        XCTAssertEqual(p.state.list?.map(\.id), ["mobile_1_abcdef", "old_aaaaaa"])
        p.back()
        XCTAssertEqual(p.state.screen, .closed)
        XCTAssertEqual(changed, 1)
        XCTAssertTrue(fake.closed.isEmpty)
    }

    func testEmptyList() async {
        let p = setup()
        fake.listDefault = []
        await p.openList()
        XCTAssertEqual(p.state.list, [])
    }

    func testFailedThenTryAgain() async {
        let p = setup()
        fake.list = [nil]
        await p.openList()
        XCTAssertTrue(p.state.failed)
        XCTAssertFalse(p.state.loading)
        p.reload()
        await flush()
        XCTAssertFalse(p.state.failed)
        XCTAssertEqual(p.state.list, [summary()])
    }

    // MARK: - One request

    func testFromListBannerMessagesReadBackToList() async {
        let p = setup()
        await p.openList()
        await p.pick("mobile_1_abcdef")
        let s = p.state
        XCTAssertEqual(s.screen, .request)
        XCTAssertEqual(s.title, "Your request")
        XCTAssertEqual(s.requestState, .replied)
        XCTAssertEqual(s.placeholder, "Write your reply...")
        XCTAssertEqual(s.banner?.label, "We replied")
        XCTAssertEqual(s.request?.messages.count, 2)
        XCTAssertEqual(marks.first?.0, "mobile_1_abcdef")
        XCTAssertEqual(marks.first?.1, now)
        p.back()
        XCTAssertEqual(fake.closed, ["mobile_1_abcdef"])
        await flush()
        XCTAssertEqual(p.state.screen, .list)
        p.back()
        XCTAssertEqual(p.state.screen, .closed)
    }

    func testOpenedStraightAwayBackLeaves() async {
        let p = setup()
        await p.openRequest("mobile_1_abcdef")
        p.back()
        XCTAssertEqual(p.state.screen, .closed)
        XCTAssertEqual(fake.closed, ["mobile_1_abcdef"])
    }

    func testSolvedSaysAReplyOpensItAgain() async {
        let p = setup()
        fake.openDefault = detail(status: .solved)
        await p.openRequest("mobile_1_abcdef")
        XCTAssertEqual(p.state.requestState, .solved)
        XCTAssertEqual(p.state.placeholder, "Write here to open it again...")
        XCTAssertTrue(p.state.banner?.detail.contains("pick it up again") == true)
    }

    func testTheChatOnScreenOpensInstead() async {
        let p = setup(current: "mobile_1_abcdef")
        await p.openRequest("mobile_1_abcdef")
        XCTAssertEqual(fake.openCalls, 0)
        XCTAssertEqual(chatOpened, 1)
        XCTAssertEqual(p.state.screen, .closed)
    }

    func testNotFoundFailed() async {
        let p = setup()
        fake.openDefault = nil
        await p.openRequest("mobile_1_abcdef")
        XCTAssertEqual(p.state.screen, .request)
        XCTAssertTrue(p.state.failed)
    }

    // MARK: - A reply

    func testSentShownAsSendingThenReplaced() async {
        let p = setup()
        let answer = Gate<ReplyResult>()
        fake.reply = [answer]
        await p.openRequest("mobile_1_abcdef")
        XCTAssertFalse(p.state.canSend)
        p.setDraft("  Thanks!  ")
        XCTAssertEqual(p.state.draft, "  Thanks!  ")
        XCTAssertTrue(p.state.canSend)
        p.send()
        await flush()
        let sent = fake.replies[0]
        XCTAssertEqual(sent.text, "Thanks!")
        XCTAssertTrue(sent.entryId.hasPrefix("request-reply-"))
        XCTAssertEqual(p.state.pending, [PendingReply(entryId: sent.entryId, text: "Thanks!", at: Requests.iso(now), status: .sending)])
        XCTAssertEqual(p.state.draft, "")
        XCTAssertFalse(p.state.canSend)
        answer.open(ReplyResult(ok: true, request: detail(lastFrom: .you, extra: [RequestMessage(id: sent.entryId, from: .you, text: "Thanks!")])))
        await flush()
        XCTAssertEqual(p.state.pending, [])
        XCTAssertEqual(p.state.request?.messages.count, 3)
        XCTAssertEqual(p.state.requestState, .waiting)
    }

    func testNotSentTryAgainSameEntryLockedNoTryAgain() async {
        let p = setup()
        fake.replyDefault = ReplyResult(ok: false, reason: "offline")
        await p.openRequest("mobile_1_abcdef")
        p.setDraft("Hello")
        p.send()
        await flush()
        let first = p.state.pending[0]
        XCTAssertEqual(first.status, .failed)
        fake.reply = [ReplyResult(ok: false, reason: "locked")]
        p.retry(first.entryId)
        await flush()
        XCTAssertEqual(fake.replies[1].entryId, first.entryId)
        XCTAssertEqual(p.state.pending[0].status, .locked)
        p.retry(first.entryId)
        await flush()
        XCTAssertEqual(fake.replies.count, 2)
    }

    func testEmptyDraftSendsNothingDraftsKeptUntilReset() async {
        let p = setup()
        await p.openRequest("mobile_1_abcdef")
        p.setDraft("   ")
        p.send()
        await flush()
        XCTAssertTrue(fake.replies.isEmpty)
        p.setDraft("half written")
        p.close()
        await p.openRequest("mobile_1_abcdef")
        XCTAssertEqual(p.state.draft, "half written")
        p.reset()
        p.close()
        await p.openRequest("mobile_1_abcdef")
        XCTAssertEqual(p.state.draft, "")
    }

    // MARK: - Live updates

    func testOpenRequestReadAgainKeepingDraftAndFailedReply() async {
        let p = setup()
        fake.replyDefault = ReplyResult(ok: false, reason: "error")
        await p.openRequest("mobile_1_abcdef")
        p.setDraft("one")
        p.send()
        await flush()
        p.setDraft("still typing")
        fake.open = [detail(status: .solved) as Any]
        fake.update?("mobile_1_abcdef")
        await flush()
        XCTAssertEqual(p.state.requestState, .solved)
        XCTAssertEqual(p.state.draft, "still typing")
        XCTAssertEqual(p.state.pending.map(\.status), [.failed])
    }

    func testOtherRequestClosedPortalOrReplyOnItsWayNothing() async {
        let p = setup()
        let answer = Gate<ReplyResult>()
        fake.reply = [answer]
        fake.update?("mobile_1_abcdef")
        await flush()
        await p.openRequest("mobile_1_abcdef")
        fake.update?("other_123456")
        await flush()
        XCTAssertEqual(fake.openCalls, 1)
        p.setDraft("x")
        p.send()
        await flush()
        fake.open = [detail(status: .solved) as Any]
        fake.update?("mobile_1_abcdef")
        await flush()
        XCTAssertEqual(p.state.requestState, .replied)
        answer.open(ReplyResult(ok: false, reason: "error"))
        await flush()
    }

    func testLateAnswerForAGoneScreenDropped() async {
        let p = setup()
        let opened = Gate<RequestDetail?>()
        fake.open = [opened]
        let done = Gate<Void>()
        Task { await p.openRequest("mobile_1_abcdef"); done.open(()) }
        await flush()
        p.close()
        opened.open(detail())
        await done.wait()
        XCTAssertEqual(p.state.screen, .closed)
    }

    func testDestroyStopsUpdates() async {
        let p = setup()
        var heard = 0
        let sub = p.$state.sink { _ in heard += 1 }
        await p.openList()
        XCTAssertGreaterThan(heard, 1)
        sub.cancel()
        p.destroy()
        XCTAssertEqual(fake.onUpdateCalls, 1)
        XCTAssertNil(fake.update)
    }

    // MARK: - The store (YourRequests)

    private final class StoreSocket {
        var answers: [String: Any] = [:]
        var asked: [(String, [String: Any])] = []
        let hub = RequestsEventHub()
        var socket: RequestsSocket {
            RequestsSocket(
                emitWithAck: { e, d, _, done in self.asked.append((e, d)); done(self.answers[e]) },
                emit: { _, _ in },
                on: { e, fn in self.hub.on(e, fn) }
            )
        }
    }

    func testStoreRemembersAsksOnlyWhenThereIsSomethingAndSavesReadMarks() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RequestsPortalTests"))
        defaults.removePersistentDomain(forName: "RequestsPortalTests")
        let sock = StoreSocket()
        sock.answers["my-requests"] = ["ok": true, "requests": [["id": "mobile_1_abcdef", "title": "Help", "status": "open",
                                                                  "lastFrom": "team", "lastAt": Requests.iso(now - 1000), "lastText": "Hi", "teamName": "Ada"]]]
        sock.answers["my-request-open"] = ["ok": true, "request": ["id": "mobile_1_abcdef", "title": "Help", "status": "open",
                                                                   "lastFrom": "team", "lastAt": Requests.iso(now - 1000), "lastText": "Hi",
                                                                   "teamName": "Ada", "messages": [[String: Any]]()]]
        var record: [[String: Any]] = [["type": "bot-message"]]
        var user: RequestsUser?
        var clock = now
        let store = YourRequests(hooks: .init(
            socket: sock.socket, isConnected: { true }, sessionId: { "mobile_1_abcdef" }, record: { record },
            user: { user }, visitorId: { "v_1" }, defaults: defaults, now: { clock }))
        store.load(botId: "bot1")

        // A first-time visitor: nothing is asked.
        await store.refresh(force: true)
        XCTAssertTrue(sock.asked.isEmpty)
        XCTAssertFalse(store.hasRequests)

        // Signed in with a hash: asked, with the user.
        user = RequestsUser(id: "u1", hash: "h")
        await store.refresh(force: true)
        XCTAssertEqual((sock.asked.last?.1["user"] as? [String: String])?["hash"], "h")
        user = nil

        // The visitor wrote in this chat: remembered, saved, asked about.
        store.recordChanged()
        XCTAssertTrue(store.sessions.isEmpty)
        record.append(["type": "user-message"])
        store.recordChanged()
        XCTAssertEqual(store.sessions, ["mobile_1_abcdef"])
        XCTAssertEqual(Requests.parseMemory(defaults.string(forKey: "conferbot_requests_bot1")).sessions, ["mobile_1_abcdef"])
        clock += Requests.refreshGapMs
        await store.refresh()
        XCTAssertEqual(sock.asked.last?.0, "my-requests")
        XCTAssertEqual(sock.asked.last?.1["sessions"] as? [String], ["mobile_1_abcdef"])
        XCTAssertEqual(store.unread, 1)
        XCTAssertEqual(store.menuTitle, "Your requests · New reply")

        // Within 15s an unforced refresh asks nothing.
        let count = sock.asked.count
        await store.refresh()
        XCTAssertEqual(sock.asked.count, count)

        // Opened (not the chat on screen once it has ended... here it is the chat on
        // screen and not over, so the chat opens instead); another request is read.
        record.append(["type": "agent-chat-ended"])
        await store.portal.openRequest("mobile_1_abcdef")
        XCTAssertEqual(store.portal.state.screen, .request)
        XCTAssertEqual(store.unread, 0)
        XCTAssertEqual(store.menuTitle, "Your requests")
        XCTAssertNotNil(Requests.parseMemory(defaults.string(forKey: "conferbot_requests_bot1")).seen["mobile_1_abcdef"])

        // Another bot remembers nothing of this one.
        store.load(botId: "bot2")
        XCTAssertTrue(store.sessions.isEmpty)
        store.load(botId: "bot1")
        XCTAssertEqual(store.sessions, ["mobile_1_abcdef"])
        defaults.removePersistentDomain(forName: "RequestsPortalTests")
    }
    /// The list held until the test answers each ask.
    private final class HeldSocket {
        var pending: [(Any?) -> Void] = []
        var asked: [[String: Any]] = []
        let hub = RequestsEventHub()
        var socket: RequestsSocket {
            RequestsSocket(
                emitWithAck: { _, d, _, done in self.asked.append(d); self.pending.append(done) },
                emit: { _, _ in },
                on: { e, fn in self.hub.on(e, fn) }
            )
        }
    }

    private func until(_ ok: () -> Bool) async {
        for _ in 0..<200 where !ok() { await Task.yield() }
    }

    func testSignOutDropsTheListIgnoresAnAnswerForTheLastUserAndReadsForTheNextOne() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RequestsPortalTests86"))
        defaults.removePersistentDomain(forName: "RequestsPortalTests86")
        let sock = HeldSocket()
        var user: RequestsUser? = RequestsUser(id: "alice", hash: "ha")
        let store = YourRequests(hooks: .init(
            socket: sock.socket, isConnected: { true }, sessionId: { nil }, record: { [] },
            user: { user }, visitorId: { "v_1" }, defaults: defaults, now: { self.now }))
        store.load(botId: "bot1")
        func list(_ id: String) -> [String: Any] {
            ["ok": true, "requests": [["id": id, "title": id, "status": "open", "lastFrom": "team", "lastAt": Requests.iso(now - 1000)]]]
        }

        // Alice's list arrives.
        let first = Task { await store.refresh(force: true) }
        await until { sock.pending.count == 1 }
        sock.pending[0](list("mobile_1_alice"))
        await first.value
        XCTAssertEqual(store.requests?.map { $0.id }, ["mobile_1_alice"])

        // Alice asks again; she signs out before it answers, Bob signs in.
        let second = Task { await store.refresh(force: true) }
        await until { sock.pending.count == 2 }
        user = nil
        await store.userChanged()
        XCTAssertNil(store.requests, "the last user's list is dropped at once")
        user = RequestsUser(id: "bob", hash: "hb")
        await store.userChanged()
        sock.pending[1](list("mobile_1_alice"))
        // Her late answer is not shown; the list is read again, for Bob.
        await until { sock.pending.count == 3 }
        XCTAssertNil(store.requests)
        XCTAssertEqual((sock.asked.last?["user"] as? [String: String])?["id"], "bob")
        sock.pending[2](list("mobile_1_bob"))
        await second.value
        XCTAssertEqual(store.requests?.map { $0.id }, ["mobile_1_bob"])

        // Signed out with nothing on this device: nothing is asked, nothing shown.
        user = nil
        let asked = sock.asked.count
        await store.userChanged()
        XCTAssertNil(store.requests)
        XCTAssertEqual(sock.asked.count, asked)
        defaults.removePersistentDomain(forName: "RequestsPortalTests86")
    }
}
