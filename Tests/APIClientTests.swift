//
//  APIClientTests.swift
//  ConferbotTests
//
//  Comprehensive tests for the APIClient service covering session initialization,
//  message sending, file uploads, error handling, and response parsing.
//

import XCTest
@testable import Conferbot

final class APIClientTests: XCTestCase {

    var sut: APIClient!
    var mockSession: URLSession!
    let testApiKey = "test-api-key-123"
    let testBotId = "test-bot-456"
    let testBaseURL = "https://test.conferbot.com/api/v1/mobile"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        mockSession = createMockURLSession()
        sut = APIClient(
            apiKey: testApiKey,
            botId: testBotId,
            baseURL: testBaseURL,
            session: mockSession
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        mockSession = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization_withDefaultURL() {
        let client = APIClient(apiKey: testApiKey, botId: testBotId)
        XCTAssertNotNil(client)
    }

    func testInitialization_withCustomURL() {
        let client = APIClient(
            apiKey: testApiKey,
            botId: testBotId,
            baseURL: testBaseURL
        )
        XCTAssertNotNil(client)
    }

    func testInitialization_withCustomSession() {
        let customSession = URLSession(configuration: .ephemeral)
        let client = APIClient(
            apiKey: testApiKey,
            botId: testBotId,
            session: customSession
        )
        XCTAssertNotNil(client)
    }

    // MARK: - Session Initialization Tests

    func testInitSession_success() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                "_id": "session-id-123",
                "chatSessionId": "chat-session-456",
                "botId": testBotId,
                "visitorId": "visitor-789",
                "record": [],
                "isActive": true
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("/session/init") == true)
            XCTAssertEqual(request.value(forHTTPHeaderField: ConferBotConstants.headerApiKey), self.testApiKey)
            XCTAssertEqual(request.value(forHTTPHeaderField: ConferBotConstants.headerBotId), self.testBotId)
            XCTAssertEqual(request.value(forHTTPHeaderField: ConferBotConstants.headerPlatform), "ios")

            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let session = try await sut.initSession()

        XCTAssertEqual(session.id, "session-id-123")
        XCTAssertEqual(session.chatSessionId, "chat-session-456")
        XCTAssertEqual(session.botId, testBotId)
        XCTAssertTrue(session.isActive)
    }

    func testInitSession_withUserId() async throws {
        let userId = "user-123"
        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                "_id": "session-id-123",
                "chatSessionId": "chat-session-456",
                "botId": testBotId,
                "visitorId": userId,
                "record": [],
                "isActive": true
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            // Verify userId is in request body
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                XCTAssertEqual(json["userId"] as? String, userId)
            }

            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let session = try await sut.initSession(userId: userId)
        XCTAssertEqual(session.visitorId, userId)
    }

    func testInitSession_httpError() async {
        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 500),
                mockJSONData(["error": "Internal Server Error"])
            )
        }

        do {
            _ = try await sut.initSession()
            XCTFail("Expected httpError to be thrown")
        } catch let error as ConferBotError {
            if case .httpError(let code) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected httpError")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testInitSession_apiError() async {
        let mockResponse: [String: Any] = [
            "success": false,
            "error": "Invalid API key"
        ]

        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 401),
                mockJSONData(mockResponse)
            )
        }

        do {
            _ = try await sut.initSession()
            XCTFail("Expected error to be thrown")
        } catch let error as ConferBotError {
            if case .apiError(let message) = error {
                XCTAssertEqual(message, "Invalid API key")
            } else if case .httpError(let code) = error {
                XCTAssertEqual(code, 401)
            } else {
                XCTFail("Unexpected ConferBotError type")
            }
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    func testInitSession_noData() async {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": NSNull()
        ]

        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        do {
            _ = try await sut.initSession()
            XCTFail("Expected noData error")
        } catch {
            // Expected error
            XCTAssertTrue(true)
        }
    }

    // MARK: - Get Session History Tests

    func testGetSessionHistory_success() async throws {
        let mockResponse: [String: Any] = [
            "data": [
                "record": [
                    [
                        "_id": "msg-1",
                        "type": "user-message",
                        "time": "2025-11-25T12:00:00Z",
                        "text": "Hello"
                    ],
                    [
                        "_id": "msg-2",
                        "type": "bot-message",
                        "time": "2025-11-25T12:01:00Z",
                        "text": "Hi there!"
                    ]
                ]
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("/session/") == true)

            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let history = try await sut.getSessionHistory(chatSessionId: "chat-session-123")

        XCTAssertEqual(history.count, 2)
    }

    func testGetSessionHistory_emptyHistory() async throws {
        let mockResponse: [String: Any] = [
            "data": [
                "record": []
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let history = try await sut.getSessionHistory(chatSessionId: "chat-session-123")

        XCTAssertEqual(history.count, 0)
    }

    func testGetSessionHistory_httpError() async {
        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 404),
                mockJSONData(["error": "Session not found"])
            )
        }

        do {
            _ = try await sut.getSessionHistory(chatSessionId: "invalid-session")
            XCTFail("Expected error")
        } catch let error as ConferBotError {
            if case .httpError(let code) = error {
                XCTAssertEqual(code, 404)
            } else {
                XCTFail("Expected httpError")
            }
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    // MARK: - Send Message Tests

    func testSendMessage_success() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                "messageId": "msg-123",
                "timestamp": "2025-11-25T12:00:00Z"
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("/message") == true)

            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                XCTAssertEqual(json["message"] as? String, "Test message")
            }

            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let response = try await sut.sendMessage(
            chatSessionId: "chat-session-123",
            message: "Test message"
        )

        XCTAssertEqual(response["messageId"] as? String, "msg-123")
    }

    func testSendMessage_withMetadata() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": ["messageId": "msg-123"]
        ]

        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                XCTAssertNotNil(json["metadata"])
            }

            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let metadata: [String: AnyCodable] = [
            "source": AnyCodable("test"),
            "priority": AnyCodable(1)
        ]

        _ = try await sut.sendMessage(
            chatSessionId: "chat-session-123",
            message: "Test message",
            metadata: metadata
        )
    }

    func testSendMessage_httpError() async {
        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 500),
                mockJSONData(["error": "Server error"])
            )
        }

        do {
            _ = try await sut.sendMessage(
                chatSessionId: "chat-session-123",
                message: "Test"
            )
            XCTFail("Expected error")
        } catch let error as ConferBotError {
            if case .httpError(let code) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected httpError")
            }
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    // MARK: - Register Push Token Tests

    func testRegisterPushToken_success() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("/push/register") == true)

            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                XCTAssertEqual(json["token"] as? String, "device-token-123")
                XCTAssertEqual(json["chatSessionId"] as? String, "session-456")
                XCTAssertEqual(json["platform"] as? String, "ios")
            }

            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(["success": true])
            )
        }

        try await sut.registerPushToken(
            token: "device-token-123",
            chatSessionId: "session-456"
        )

        // No error means success
        XCTAssertTrue(true)
    }

    func testRegisterPushToken_httpError() async {
        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 400),
                mockJSONData(["error": "Invalid token"])
            )
        }

        do {
            try await sut.registerPushToken(
                token: "invalid",
                chatSessionId: "session-456"
            )
            XCTFail("Expected error")
        } catch let error as ConferBotError {
            if case .httpError(let code) = error {
                XCTAssertEqual(code, 400)
            } else {
                XCTFail("Expected httpError")
            }
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    // MARK: - Request Headers Tests

    func testRequest_containsRequiredHeaders() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                "_id": "id",
                "chatSessionId": "chat",
                "botId": testBotId,
                "record": [],
                "isActive": true
            ]
        ]

        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        _ = try await sut.initSession()

        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: ConferBotConstants.headerApiKey), testApiKey)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: ConferBotConstants.headerBotId), testBotId)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: ConferBotConstants.headerPlatform), "ios")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: - Error Type Tests

    func testConferBotError_invalidResponse() {
        let error = ConferBotError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid server response")
    }

    func testConferBotError_httpError() {
        let error = ConferBotError.httpError(404)
        XCTAssertTrue(error.errorDescription!.contains("404"))
    }

    func testConferBotError_apiError() {
        let error = ConferBotError.apiError("Custom message")
        XCTAssertEqual(error.errorDescription, "Custom message")
    }

    func testConferBotError_noData() {
        let error = ConferBotError.noData
        XCTAssertEqual(error.errorDescription, "No data received")
    }

    func testConferBotError_notInitialized() {
        let error = ConferBotError.notInitialized
        XCTAssertTrue(error.errorDescription!.contains("initialize"))
    }

    func testConferBotError_socketNotConnected() {
        let error = ConferBotError.socketNotConnected
        XCTAssertTrue(error.errorDescription!.contains("not connected"))
    }

    // MARK: - Response Parsing Tests

    func testAPIResponse_decoding_success() throws {
        let json = """
        {
            "success": true,
            "data": {
                "_id": "test-id",
                "chatSessionId": "chat-123",
                "botId": "bot-456",
                "record": [],
                "isActive": true
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(APIResponse<ChatSession>.self, from: json)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.data)
        XCTAssertEqual(response.data?.chatSessionId, "chat-123")
    }

    func testAPIResponse_decoding_withError() throws {
        let json = """
        {
            "success": false,
            "error": "Something went wrong",
            "message": "Detailed error message"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(APIResponse<ChatSession>.self, from: json)

        XCTAssertFalse(response.success)
        XCTAssertNil(response.data)
        XCTAssertEqual(response.error, "Something went wrong")
        XCTAssertEqual(response.message, "Detailed error message")
    }

    // MARK: - Timeout Tests

    func testRequest_usesConfiguredTimeout() async throws {
        var capturedRequest: URLRequest?

        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                "_id": "id",
                "chatSessionId": "chat",
                "botId": testBotId,
                "record": [],
                "isActive": true
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        _ = try await sut.initSession()

        XCTAssertEqual(capturedRequest?.timeoutInterval, ConferBotConstants.apiTimeout)
    }

    // MARK: - Concurrent Request Tests

    func testConcurrentRequests_doNotInterfere() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                "_id": "id",
                "chatSessionId": "chat",
                "botId": testBotId,
                "record": [],
                "isActive": true
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            // Simulate network delay
            Thread.sleep(forTimeInterval: 0.1)
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        async let session1 = sut.initSession()
        async let session2 = sut.initSession()
        async let session3 = sut.initSession()

        let results = try await [session1, session2, session3]

        XCTAssertEqual(results.count, 3)
        for session in results {
            XCTAssertEqual(session.chatSessionId, "chat")
        }
    }
}
