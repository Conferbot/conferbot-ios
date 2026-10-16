//
//  EmailTranscriptTests.swift
//  "Email me this chat" (#39): the address check, the request the SDK sends
//  (POST {mobile base}/chat/transcript-email with the SDK's headers; the bot
//  is X-Bot-ID's) and how each answer reads. A URLProtocol stub answers:
//  nothing is ever mailed. The same cases as the React Native SDK's
//  emailTranscript.test.ts.
//

import XCTest
@testable import Conferbot

private final class TranscriptStub: URLProtocol {
    static var reply: (status: Int, body: Any) = (200, ["success": true])
    static var seen: [URLRequest] = []
    static var bodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.append(request)
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            Self.bodies.append(data)
        } else {
            Self.bodies.append(request.httpBody ?? Data())
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.reply.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: Self.reply.body)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class EmailTranscriptTests: XCTestCase {

    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranscriptStub.self]
        return APIClient(apiKey: "conf_test", botId: "bot-1", baseURL: "http://localhost:8001/api/v1/mobile", session: URLSession(configuration: config))
    }

    override func setUp() {
        super.setUp()
        TranscriptStub.seen = []
        TranscriptStub.bodies = []
        TranscriptStub.reply = (200, ["success": true])
    }

    func testTheAddressIsCheckedAsTheWebChecksIt() {
        XCTAssertTrue(EmailTranscript.isEmail(" sam@example.com "))
        XCTAssertFalse(EmailTranscript.isEmail("sam@example"))
        XCTAssertFalse(EmailTranscript.isEmail("sam@example.c"))
        XCTAssertFalse(EmailTranscript.isEmail("sam example@x.com"))
        XCTAssertFalse(EmailTranscript.isEmail(nil))
    }

    func testTheAnswerReadsAsTheWebReadsIt() {
        XCTAssertEqual(EmailTranscript.result(status: 200, data: ["success": true]), TranscriptEmailResult(ok: true))
        XCTAssertEqual(EmailTranscript.result(status: 200, data: ["success": false]), TranscriptEmailResult(ok: false))
        XCTAssertEqual(EmailTranscript.result(status: 400, data: ["success": false, "message": "Please enter a valid email address."]),
                       TranscriptEmailResult(ok: false, message: "Please enter a valid email address."))
        XCTAssertEqual(EmailTranscript.result(status: 429, data: ["message": "Too many requests"]), TranscriptEmailResult(ok: false, message: "Too many requests"))
        XCTAssertEqual(EmailTranscript.result(status: 500, data: nil), TranscriptEmailResult(ok: false))
        XCTAssertEqual(EmailTranscript.errorText(TranscriptEmailResult(ok: false, message: "Too many requests")), "Too many requests")
        XCTAssertEqual(EmailTranscript.errorText(TranscriptEmailResult(ok: false)), "We couldn't send it just now. Please try again.")
        XCTAssertEqual(EmailTranscript.Copy.sent("sam@example.com"), "Sent! Check your inbox at sam@example.com")
    }

    func testTheRequestGoesToTheMobileRouteWithTheSDKsHeaders() async throws {
        let r = await client().sendTranscriptEmail(chatSessionId: "s1", email: "  sam@example.com ")
        XCTAssertEqual(r, TranscriptEmailResult(ok: true))
        let request = try XCTUnwrap(TranscriptStub.seen.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8001/api/v1/mobile/chat/transcript-email")
        XCTAssertEqual(request.value(forHTTPHeaderField: ConferBotConstants.headerBotId), "bot-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: ConferBotConstants.headerApiKey), "conf_test")
        XCTAssertNotNil(request.value(forHTTPHeaderField: ConferBotConstants.headerPlatform))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(TranscriptStub.bodies.first)) as? [String: Any])
        XCTAssertEqual(body["chatSessionId"] as? String, "s1")
        XCTAssertEqual(body["email"] as? String, "sam@example.com")
        // The bot is the header's, never the body's.
        XCTAssertNil(body["botId"])
    }

    func testARefusalComesBackWithTheServersWords() async {
        TranscriptStub.reply = (429, ["success": false, "message": "Too many requests, please try again later."])
        let r = await client().sendTranscriptEmail(chatSessionId: "s1", email: "sam@example.com")
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.message, "Too many requests, please try again later.")
    }

    func testANetworkFailureReadsAsNotSent() async {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        let api = APIClient(apiKey: "k", botId: "b", baseURL: "http://127.0.0.1:9/api/v1/mobile", session: URLSession(configuration: config))
        let r = await api.sendTranscriptEmail(chatSessionId: "s1", email: "sam@example.com")
        XCTAssertEqual(r, TranscriptEmailResult(ok: false))
    }
}
