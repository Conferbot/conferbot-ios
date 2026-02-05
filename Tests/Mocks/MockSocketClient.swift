//
//  MockSocketClient.swift
//  ConferbotTests
//
//  Mock SocketClient for testing services that depend on socket communication.
//

import Foundation
@testable import Conferbot

/// Mock SocketClient for testing
class MockSocketClient {

    // MARK: - Properties

    var isConnected: Bool = false
    var emittedEvents: [(event: String, data: Any)] = []
    var registeredHandlers: [String: Any] = []
    var connectCallCount = 0
    var disconnectCallCount = 0

    // MARK: - Configuration

    let apiKey: String
    let botId: String
    let socketURL: String

    // MARK: - Callbacks for testing

    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onEmit: ((String, Any) -> Void)?

    // MARK: - Initialization

    init(
        apiKey: String = "test-api-key",
        botId: String = "test-bot-id",
        socketURL: String = "https://test.conferbot.com"
    ) {
        self.apiKey = apiKey
        self.botId = botId
        self.socketURL = socketURL
    }

    // MARK: - Mock Methods

    func connect() {
        connectCallCount += 1
        isConnected = true
        onConnect?()
    }

    func disconnect() {
        disconnectCallCount += 1
        isConnected = false
        onDisconnect?()
    }

    func emit(_ event: String, _ data: Any) {
        guard isConnected else { return }
        emittedEvents.append((event: event, data: data))
        onEmit?(event, data)
    }

    func emit(event: String, data: [String: Any]) {
        guard isConnected else { return }
        emittedEvents.append((event: event, data: data))
        onEmit?(event, data)
    }

    func on(_ event: String, callback: @escaping ([Any], Any) -> Void) {
        registeredHandlers[event] = callback
    }

    func off(_ event: String) {
        registeredHandlers.removeValue(forKey: event)
    }

    // MARK: - Test Helpers

    /// Simulate receiving an event from the server
    func simulateEvent(_ event: String, data: [Any]) {
        if let handler = registeredHandlers[event] as? ([Any], Any) -> Void {
            handler(data, ())
        }
    }

    /// Get the last emitted event for a specific event type
    func lastEmittedData(for event: String) -> Any? {
        return emittedEvents.last { $0.event == event }?.data
    }

    /// Get all emitted events for a specific event type
    func allEmittedData(for event: String) -> [Any] {
        return emittedEvents.filter { $0.event == event }.map { $0.data }
    }

    /// Reset all state
    func reset() {
        isConnected = false
        emittedEvents = []
        registeredHandlers = [:]
        connectCallCount = 0
        disconnectCallCount = 0
    }
}

/// Protocol for socket client abstraction (for dependency injection in tests)
protocol SocketClientProtocol: AnyObject {
    var isConnected: Bool { get }
    func connect()
    func disconnect()
    func emit(_ event: String, _ data: Any)
    func emit(event: String, data: [String: Any])
}
