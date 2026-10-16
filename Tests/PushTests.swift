//
//  PushTests.swift
//  ConferbotTests
//
//  Push notifications (#97; embed-server #189 docs/mobile-push.md, RN #77):
//  the payload, the bodies, the server's answers, the registrar per
//  conversation, a tap opening its conversation, and the HTTP routes (mocked;
//  never APNs or FCM).
//

import XCTest
@testable import Conferbot

private func payload(_ extra: [String: Any] = [:]) -> [AnyHashable: Any] {
    var p: [AnyHashable: Any] = [
        "aps": ["alert": ["title": "Maya", "body": "Your order ships today"], "thread-id": "s1", "mutable-content": 1],
        "source": "conferbot", "type": "conferbot_message", "botId": "bot1", "chatSessionId": "s1",
        "messageId": "m1", "senderType": "agent", "senderName": "Maya", "body": "Your order ships today",
    ]
    for (k, v) in extra { p[k] = v }
    return p
}

// MARK: - The payload and bodies

final class PushPayloadTests: XCTestCase {

    func testParse_theServersAPNsPayload() {
        let p = ConferbotPush.parse(payload())
        XCTAssertEqual(p, ConferbotPush(botId: "bot1", chatSessionId: "s1", messageId: "m1",
                                        senderType: .agent, senderName: "Maya", body: "Your order ships today"))
        XCTAssertTrue(isConferbotPush(payload()))
        XCTAssertEqual(parseConferbotPush(payload())?.chatSessionId, "s1")
    }

    func testParse_notOurs() {
        XCTAssertNil(ConferbotPush.parse(nil))
        XCTAssertNil(ConferbotPush.parse(["aps": ["alert": "hi"]]))
        XCTAssertNil(ConferbotPush.parse(payload(["source": "other"])))
        XCTAssertNil(ConferbotPush.parse(payload(["type": "conferbot_other"])))
        XCTAssertNil(ConferbotPush.parse(payload(["botId": ""])))
        XCTAssertNil(ConferbotPush.parse(payload(["chatSessionId": "  "])))
        // The old check took any type == conferbot_message.
        XCTAssertNil(ConferbotPush.parse(["type": "conferbot_message", "botId": "bot1", "chatSessionId": "s1"]))
    }

    func testParse_aiSenderEmptyMessageIdNestedData() {
        let p = ConferbotPush.parse(payload(["senderType": "bot", "messageId": ""]))
        XCTAssertEqual(p?.senderType, .bot)
        XCTAssertEqual(p?.messageId, "")
        XCTAssertEqual(ConferbotPush.parse(payload(["senderType": "weird"]))?.senderType, .bot)
        let nested: [AnyHashable: Any] = ["data": ["source": "conferbot", "type": "conferbot_message", "botId": "b", "chatSessionId": "c"]]
        XCTAssertEqual(ConferbotPush.parse(nested)?.botId, "b")
        XCTAssertEqual(ConferbotPush.parse(payload(["messageId": 42]))?.messageId, "42")
    }

    func testTokenTypeAndHex() {
        let apns = String(repeating: "ab", count: 32)
        XCTAssertEqual(Push.tokenType(of: apns), .apns)
        XCTAssertEqual(Push.tokenType(of: apns.uppercased()), .apns)
        XCTAssertEqual(Push.tokenType(of: "fcm:APA91b-token"), .fcm)
        XCTAssertEqual(Push.tokenType(of: apns, type: .fcm), .fcm)
        XCTAssertEqual(Push.hex(Data([0x00, 0x0f, 0xab, 0xff])), "000fabff")
    }

    func testRegisterBody_noVisitorId() {
        let b = Push.registerBody(token: "t", chatSessionId: "s", tokenType: .apns, deviceInfo: ["model": "iPhone"])
        XCTAssertEqual(b["token"] as? String, "t")
        XCTAssertEqual(b["chatSessionId"] as? String, "s")
        XCTAssertEqual(b["tokenType"] as? String, "apns")
        XCTAssertEqual(b["deviceInfo"] as? [String: String], ["model": "iPhone"])
        XCTAssertNil(b["visitorId"])
        XCTAssertNil(b["platform"])
        XCTAssertNil(Push.registerBody(token: "t", chatSessionId: "s", tokenType: .fcm, deviceInfo: [:])["deviceInfo"])
        XCTAssertEqual(Push.unregisterBody(token: "t") as? [String: String], ["token": "t"])
    }

    func testRegisterResult() {
        XCTAssertEqual(Push.registerResult(status: 200, data: ["success": true]), PushRegisterResult(ok: true))
        XCTAssertEqual(Push.registerResult(status: 200, data: ["success": false]).error, .server)
        XCTAssertEqual(Push.registerResult(status: 400, data: ["error": "MISSING_TOKEN"]).error, .missingToken)
        XCTAssertEqual(Push.registerResult(status: 400, data: ["error": "INVALID_TOKEN"]).error, .invalidToken)
        XCTAssertEqual(Push.registerResult(status: 400, data: ["error": "MISSING_SESSION"]).error, .missingSession)
        XCTAssertEqual(Push.registerResult(status: 403, data: ["error": "SESSION_FORBIDDEN"]).error, .sessionForbidden)
        XCTAssertEqual(Push.registerResult(status: 404, data: ["error": "SESSION_NOT_FOUND"]).error, .sessionNotFound)
        XCTAssertEqual(Push.registerResult(status: 404, data: nil).error, .sessionNotFound)
        XCTAssertEqual(Push.registerResult(status: 500, data: ["error": "NETWORK"]).error, .server)
        XCTAssertEqual(Push.registerResult(status: 502, data: nil).error, .server)
    }

    func testRetryable() {
        XCTAssertTrue(Push.retryable(.sessionNotFound))
        XCTAssertTrue(Push.retryable(.network))
        XCTAssertTrue(Push.retryable(.server))
        XCTAssertFalse(Push.retryable(.invalidToken))
        XCTAssertFalse(Push.retryable(.sessionForbidden))
        XCTAssertFalse(Push.retryable(.missingToken))
        XCTAssertFalse(Push.retryable(nil))
    }
}

// MARK: - The registrar

@MainActor
private final class FakeServer {
    var registers: [[String: Any]] = []
    var unregisters: [String] = []
    var answers: [PushRegisterResult] = []

    func register(_ body: [String: Any]) async -> PushRegisterResult {
        registers.append(body)
        return answers.isEmpty ? PushRegisterResult(ok: true) : answers.removeFirst()
    }

    func unregister(_ token: String) async -> Bool {
        unregisters.append(token)
        return true
    }

    var pairs: [String] { registers.map { "\($0["token"] as? String ?? "")@\($0["chatSessionId"] as? String ?? "")" } }
}

@MainActor
final class PushRegistrarTests: XCTestCase {
    private var server: FakeServer!
    private var reg: PushRegistrar!

    override func setUp() async throws {
        server = FakeServer()
        let s = server!
        reg = PushRegistrar(register: { await s.register($0) }, unregister: { await s.unregister($0) },
                            deviceInfo: { ["model": "iPhone"] })
    }

    func testWaitsForTokenAndConversation_thenOncePerPair() async {
        await reg.setSession("s1")
        XCTAssertTrue(server.registers.isEmpty)
        await reg.setToken("tok", type: .fcm)
        await reg.poke()
        await reg.setSession("s1")
        XCTAssertEqual(server.pairs, ["tok@s1"])
        XCTAssertEqual(server.registers.first?["tokenType"] as? String, "fcm")
        XCTAssertEqual(server.registers.first?["deviceInfo"] as? [String: String], ["model": "iPhone"])
        XCTAssertEqual(reg.registered?.chatSessionId, "s1")
    }

    func testNewConversation_registeredAgain() async {
        await reg.setToken("tok", type: .apns)
        await reg.setSession("s1")
        await reg.setSession("s2")
        XCTAssertEqual(server.pairs, ["tok@s1", "tok@s2"])
    }

    func testSessionNotFound_retriedAsTheChatGoesOn() async {
        server.answers = [PushRegisterResult(ok: false, error: .sessionNotFound), PushRegisterResult(ok: false, error: .network)]
        await reg.setToken("tok", type: .apns)
        await reg.setSession("s1")
        await reg.poke()
        await reg.poke()
        await reg.poke()
        XCTAssertEqual(server.pairs, ["tok@s1", "tok@s1", "tok@s1"])
        XCTAssertNotNil(reg.registered)
    }

    func testRefused_neverAgainForThatPair() async {
        server.answers = [PushRegisterResult(ok: false, error: .sessionForbidden)]
        await reg.setToken("tok", type: .apns)
        await reg.setSession("s1")
        await reg.poke()
        XCTAssertEqual(server.pairs, ["tok@s1"])
        // A new conversation is tried.
        await reg.setSession("s2")
        XCTAssertEqual(server.pairs, ["tok@s1", "tok@s2"])
    }

    func testRefreshedToken_unregistersTheOld() async {
        await reg.setSession("s1")
        await reg.setToken("old", type: .fcm)
        await reg.setToken("new", type: .fcm)
        XCTAssertEqual(server.unregisters, ["old"])
        XCTAssertEqual(server.pairs, ["old@s1", "new@s1"])
    }

    func testNilToken_unregisters() async {
        await reg.setSession("s1")
        await reg.setToken("tok", type: .fcm)
        await reg.setToken(nil)
        XCTAssertEqual(server.unregisters, ["tok"])
        XCTAssertNil(reg.token)
        await reg.setSession("s2")
        XCTAssertEqual(server.pairs, ["tok@s1"])
    }

    func testUnregister_notAgainUntilANewConversation() async {
        await reg.setSession("s1")
        await reg.setToken("tok", type: .fcm)
        await reg.unregister()
        await reg.poke()
        XCTAssertEqual(server.unregisters, ["tok"])
        XCTAssertEqual(server.pairs, ["tok@s1"])
        XCTAssertNil(reg.registered)
        await reg.setSession("s2")
        XCTAssertEqual(server.pairs, ["tok@s1", "tok@s2"])
    }
}

// MARK: - Wired into the chat

@MainActor
final class PushNotificationsTests: XCTestCase {
    private var server: FakeServer!
    private var push: PushNotifications!
    private var botId: String? = "bot1"
    private var session: String?
    private var onScreen = false
    private var log: [String] = []
    private var unread = 0

    override func setUp() async throws {
        server = FakeServer()
        botId = "bot1"
        session = nil
        onScreen = false
        log = []
        unread = 0
        let s = server!
        push = PushNotifications(hooks: .init(
            botId: { [unowned self] in self.botId },
            chatSessionId: { [unowned self] in self.session },
            chatOnScreen: { [unowned self] in self.onScreen },
            openChat: { [unowned self] p in self.log.append("open:\(p.chatSessionId)") },
            showChat: { [unowned self] in self.log.append("chat") },
            openRequest: { [unowned self] id in self.log.append("request:\(id)") },
            bumpUnread: { [unowned self] in self.unread += 1 },
            register: { await s.register($0) },
            unregister: { await s.unregister($0) },
            retryDelay: 0
        ))
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func testToken_registeredWithTheConversationAndEachNewOne() async {
        session = "s1"
        await push.setToken("tok", type: .apns)
        XCTAssertEqual(server.pairs, ["tok@s1"])
        session = "s2"
        push.sessionChanged("s2")
        await settle()
        XCTAssertEqual(server.pairs, ["tok@s1", "tok@s2"])
    }

    func testRecordGrowing_retriesANotYetStoredConversation() async {
        server.answers = [PushRegisterResult(ok: false, error: .sessionNotFound)]
        session = "s1"
        await push.setToken("tok", type: .apns)
        push.recordChanged()
        await settle()
        XCTAssertEqual(server.pairs, ["tok@s1", "tok@s1"])
    }

    func testSignOutOrAnotherUser_unregisters() async {
        session = "s1"
        await push.setToken("tok", type: .apns)
        push.userChanged("u1")
        await settle()
        XCTAssertTrue(server.unregisters.isEmpty)
        push.userChanged(nil)
        await settle()
        XCTAssertEqual(server.unregisters, ["tok"])
        push.userChanged("u2")
        push.userChanged("u3")
        await settle()
        XCTAssertEqual(server.unregisters, ["tok", "tok"])
    }

    func testTap_opensTheChatOnItsConversation() {
        session = "s1"
        XCTAssertTrue(push.handle(payload(), open: true))
        XCTAssertEqual(log, ["open:s1", "chat"])
        // No conversation on the device yet: the chat.
        log = []
        session = nil
        XCTAssertTrue(push.handle(payload(), open: true))
        XCTAssertEqual(log, ["open:s1", "chat"])
    }

    func testTap_olderConversation_inYourRequests() {
        session = "s2"
        XCTAssertTrue(push.handle(payload(), open: true))
        XCTAssertEqual(log, ["open:s1", "request:s1"])
    }

    func testAnotherBotsOrNotOurs_false() {
        XCTAssertFalse(push.handle(payload(["botId": "other"]), open: true))
        XCTAssertFalse(push.handle(["aps": ["alert": "x"]], open: true))
        XCTAssertTrue(log.isEmpty)
        XCTAssertEqual(unread, 0)
    }

    func testForeground_onlyUnreadUnlessOnScreen() {
        session = "s1"
        XCTAssertTrue(push.handle(payload(), open: false))
        XCTAssertEqual(unread, 1)
        onScreen = true
        XCTAssertTrue(push.handle(payload(), open: false))
        XCTAssertEqual(unread, 1)
        // On screen, but another conversation.
        session = "s2"
        XCTAssertTrue(push.handle(payload(), open: false))
        XCTAssertEqual(unread, 2)
        XCTAssertTrue(log.isEmpty)
    }

    func testTapBeforeInitialize_openedOnceReady() {
        botId = nil
        XCTAssertTrue(push.handle(payload(), open: true))
        XCTAssertTrue(log.isEmpty)
        botId = "bot1"
        push.ready()
        XCTAssertEqual(log, ["open:s1", "chat"])
        push.ready()
        XCTAssertEqual(log.count, 2)
    }

    func testTapBeforeInitialize_anotherBot_dropped() {
        botId = nil
        XCTAssertTrue(push.handle(payload(), open: true))
        botId = "otherBot"
        push.ready()
        XCTAssertTrue(log.isEmpty)
    }
}

// MARK: - The routes (MockURLProtocol)

final class PushAPITests: XCTestCase {
    private var sut: APIClient!
    private let base = "https://test.conferbot.com/api/v1/mobile"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        sut = APIClient(apiKey: "key", botId: "bot1", baseURL: base, session: createMockURLSession())
    }

    override func tearDown() {
        MockURLProtocol.reset()
        sut = nil
        super.tearDown()
    }

    /// URLProtocol sees the body as a stream.
    private func body(_ r: URLRequest) -> [String: Any]? {
        var data = r.httpBody
        if data == nil, let stream = r.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var d = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                d.append(buf, count: n)
            }
            data = d
        }
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func testRegister_postsTheBodyWithTheHeaders() async {
        var seen: [String: Any]?
        MockURLProtocol.requestHandler = { r in
            XCTAssertEqual(r.httpMethod, "POST")
            XCTAssertEqual(r.url?.absoluteString, "\(self.base)/push/register")
            XCTAssertEqual(r.value(forHTTPHeaderField: "X-Bot-ID"), "bot1")
            XCTAssertEqual(r.value(forHTTPHeaderField: "X-Platform"), ConferBotConstants.platformIdentifier)
            XCTAssertEqual(r.value(forHTTPHeaderField: "X-API-Key"), "key")
            seen = self.body(r)
            return (mockHTTPResponse(url: r.url!.absoluteString, statusCode: 200), mockJSONData(["success": true]))
        }
        let r = await sut.registerPushToken(Push.registerBody(token: "tok", chatSessionId: "s1", tokenType: .apns))
        XCTAssertEqual(r, PushRegisterResult(ok: true))
        XCTAssertEqual(seen?["token"] as? String, "tok")
        XCTAssertEqual(seen?["chatSessionId"] as? String, "s1")
        XCTAssertEqual(seen?["tokenType"] as? String, "apns")
        XCTAssertNil(seen?["visitorId"])
    }

    func testRegister_theServersErrors() async {
        for (status, code, expected) in [(400, "INVALID_TOKEN", PushRegisterError.invalidToken),
                                         (403, "SESSION_FORBIDDEN", .sessionForbidden),
                                         (404, "SESSION_NOT_FOUND", .sessionNotFound),
                                         (400, "MISSING_SESSION", .missingSession)] {
            MockURLProtocol.requestHandler = { r in
                (mockHTTPResponse(url: r.url!.absoluteString, statusCode: status), mockJSONData(["success": false, "error": code]))
            }
            let r = await sut.registerPushToken(Push.registerBody(token: "tok", chatSessionId: "s1", tokenType: .fcm))
            XCTAssertEqual(r, PushRegisterResult(ok: false, error: expected))
        }
    }

    func testRegister_networkFailure_neverThrows() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let r = await sut.registerPushToken(Push.registerBody(token: "tok", chatSessionId: "s1", tokenType: .fcm))
        XCTAssertEqual(r, PushRegisterResult(ok: false, error: .network))
    }

    func testUnregister() async {
        var seen: [String: Any]?
        MockURLProtocol.requestHandler = { r in
            XCTAssertEqual(r.url?.absoluteString, "\(self.base)/push/unregister")
            seen = self.body(r)
            return (mockHTTPResponse(url: r.url!.absoluteString, statusCode: 200), mockJSONData(["success": true]))
        }
        let ok = await sut.unregisterPushToken("tok")
        XCTAssertTrue(ok)
        XCTAssertEqual(seen as? [String: String], ["token": "tok"])

        MockURLProtocol.requestHandler = { _ in throw URLError(.timedOut) }
        let failed = await sut.unregisterPushToken("tok")
        XCTAssertFalse(failed)
    }
}

// MARK: - ConferBot's public API

final class ConferBotPushAPITests: XCTestCase {
    func testHandlePushNotification_notOurs_false() {
        XCTAssertFalse(ConferBot.shared.handlePushNotification(["aps": ["alert": "hi"]]))
        XCTAssertFalse(ConferBot.shared.handlePushNotification(["type": "conferbot_message"]))
    }
}
