//
//  ConferbotTests.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import XCTest
@testable import Conferbot

final class ConferbotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset singleton state before each test
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Model Tests

    func testAgentDecoding() throws {
        let json = """
        {
            "id": "agent-123",
            "name": "John Doe",
            "email": "john@example.com",
            "avatar": "https://example.com/avatar.jpg",
            "title": "Support Agent",
            "status": "online"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let agent = try decoder.decode(Agent.self, from: json)

        XCTAssertEqual(agent.id, "agent-123")
        XCTAssertEqual(agent.name, "John Doe")
        XCTAssertEqual(agent.email, "john@example.com")
        XCTAssertEqual(agent.title, "Support Agent")
    }

    func testUserMessageRecordDecoding() throws {
        let json = """
        {
            "_id": "msg-123",
            "type": "user-message",
            "time": "2025-11-25T12:00:00Z",
            "text": "Hello, I need help"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let message = try decoder.decode(UserMessageRecord.self, from: json)

        XCTAssertEqual(message.id, "msg-123")
        XCTAssertEqual(message.type, .userMessage)
        XCTAssertEqual(message.text, "Hello, I need help")
    }

    func testBotMessageRecordDecoding() throws {
        let json = """
        {
            "_id": "msg-456",
            "type": "bot-message",
            "time": "2025-11-25T12:01:00Z",
            "text": "How can I help you?"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let message = try decoder.decode(BotMessageRecord.self, from: json)

        XCTAssertEqual(message.id, "msg-456")
        XCTAssertEqual(message.type, .botMessage)
        XCTAssertEqual(message.text, "How can I help you?")
    }

    func testConferBotUserEncoding() throws {
        let user = ConferBotUser(
            id: "user-123",
            name: "Jane Doe",
            email: "jane@example.com",
            phone: "+1234567890",
            metadata: [
                "plan": AnyCodable("premium"),
                "signupDate": AnyCodable("2024-01-15")
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(user)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["id"] as? String, "user-123")
        XCTAssertEqual(json["name"] as? String, "Jane Doe")
        XCTAssertEqual(json["email"] as? String, "jane@example.com")
        XCTAssertNotNil(json["metadata"])
    }

    // MARK: - Constants Tests

    func testConstants() {
        XCTAssertEqual(ConferBotConstants.platformIdentifier, "ios")
        XCTAssertEqual(ConferBotConstants.maxMessageLength, 5000)
        XCTAssertEqual(ConferBotConstants.maxFileSize, 10485760)
        XCTAssertEqual(ConferBotConstants.apiTimeout, 30.0)
    }

    // MARK: - Socket Events Tests

    func testSocketEvents() {
        XCTAssertEqual(SocketEvents.mobileInit, "mobile-init")
        XCTAssertEqual(SocketEvents.sendVisitorMessage, "send-visitor-message")
        XCTAssertEqual(SocketEvents.botResponse, "bot-response")
        XCTAssertEqual(SocketEvents.agentMessage, "agent-message")
        XCTAssertEqual(SocketEvents.connect, "connect")
    }

    // MARK: - Message Type Tests

    func testMessageTypeRawValues() {
        XCTAssertEqual(MessageType.userMessage.rawValue, "user-message")
        XCTAssertEqual(MessageType.botMessage.rawValue, "bot-message")
        XCTAssertEqual(MessageType.agentMessage.rawValue, "agent-message")
        XCTAssertEqual(MessageType.systemMessage.rawValue, "system-message")
    }

    // MARK: - Configuration Tests

    func testDefaultConfig() {
        let config = ConferBotConfig()

        XCTAssertTrue(config.enableNotifications)
        XCTAssertTrue(config.enableOfflineMode)
        XCTAssertEqual(config.apiBaseURL, ConferBotConstants.defaultApiBaseURL)
        XCTAssertEqual(config.socketURL, ConferBotConstants.defaultSocketURL)
    }

    func testCustomConfig() {
        let config = ConferBotConfig(
            enableNotifications: false,
            enableOfflineMode: false,
            apiBaseURL: "https://custom.api.com",
            socketURL: "https://custom.socket.com"
        )

        XCTAssertFalse(config.enableNotifications)
        XCTAssertFalse(config.enableOfflineMode)
        XCTAssertEqual(config.apiBaseURL, "https://custom.api.com")
        XCTAssertEqual(config.socketURL, "https://custom.socket.com")
    }

    // MARK: - AnyCodable Tests

    func testAnyCodableWithString() throws {
        let value = AnyCodable("test string")
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)

        XCTAssertEqual(decoded.value as? String, "test string")
    }

    func testAnyCodableWithInt() throws {
        let value = AnyCodable(42)
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)

        XCTAssertEqual(decoded.value as? Int, 42)
    }

    func testAnyCodableWithDictionary() throws {
        let dict: [String: Any] = ["key": "value", "number": 123]
        let value = AnyCodable(dict)
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)

        let decodedDict = decoded.value as? [String: Any]
        XCTAssertNotNil(decodedDict)
        XCTAssertEqual(decodedDict?["key"] as? String, "value")
    }

    // MARK: - Error Tests

    func testConferBotErrors() {
        let notInitialized = ConferBotError.notInitialized
        XCTAssertNotNil(notInitialized.errorDescription)

        let httpError = ConferBotError.httpError(404)
        XCTAssertTrue(httpError.errorDescription!.contains("404"))

        let apiError = ConferBotError.apiError("Custom error message")
        XCTAssertEqual(apiError.errorDescription, "Custom error message")
    }

    // MARK: - Performance Tests

    func testMessageDecodingPerformance() throws {
        let json = """
        {
            "_id": "msg-123",
            "type": "user-message",
            "time": "2025-11-25T12:00:00Z",
            "text": "Hello, I need help"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        measure {
            for _ in 0..<1000 {
                _ = try? decoder.decode(UserMessageRecord.self, from: json)
            }
        }
    }

    // MARK: - Integration Tests

    func testAPIClientInitialization() {
        let client = APIClient(
            apiKey: "test-key",
            botId: "test-bot",
            baseURL: "https://test.com"
        )

        // Verify client is created (no crash)
        XCTAssertNotNil(client)
    }

    func testSocketClientInitialization() {
        let client = SocketClient(
            apiKey: "test-key",
            botId: "test-bot",
            socketURL: "https://test.com"
        )

        XCTAssertNotNil(client)
        XCTAssertFalse(client.isConnected)
    }
}
