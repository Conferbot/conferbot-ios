// SocketIO shim for Linux compilation/CI
// Provides type stubs matching socket.io-client-swift's public API
// so the SDK core compiles without network access to GitHub.
// On iOS, the real SocketIO package is used instead.

import Foundation

// MARK: - SocketIO Protocol & Types

public protocol SocketData {}
extension String: SocketData {}
extension Dictionary: SocketData where Key == String {}
extension Array: SocketData where Element: SocketData {}
extension Int: SocketData {}
extension Double: SocketData {}
extension Bool: SocketData {}

public typealias NormalCallback = ([Any], SocketAckEmitter) -> ()

public class SocketAckEmitter {
    public func with(_ items: SocketData...) {}
}

public enum SocketIOStatus {
    case notConnected
    case disconnected
    case connecting
    case connected
}

public enum SocketClientEvent: String {
    case connect
    case disconnect
    case error
    case reconnect
    case reconnectAttempt
    case statusChange
    case ping
    case pong
    case websocketUpgrade
}

public enum SocketIOClientOption {
    case log(Bool)
    case compress
    case connectParams([String: Any])
    case extraHeaders([String: String])
    case reconnects(Bool)
    case reconnectAttempts(Int)
    case reconnectWait(Int)
    case reconnectWaitMax(Int)
    case forcePolling(Bool)
    case forceWebsockets(Bool)
    case path(String)
    case secure(Bool)
}

public typealias SocketIOClientConfiguration = [SocketIOClientOption]

public class SocketIOClient {
    public var status: SocketIOStatus = .notConnected
    public var sid: String = ""

    public func connect() {}
    public func disconnect() {}
    public func removeAllHandlers() {}

    public func emit(_ event: String, _ items: SocketData...) {}
    public func emit(_ event: String, _ items: [Any]) {}

    public func on(_ event: String, callback: @escaping NormalCallback) {
        // stub
    }

    public func on(clientEvent: SocketClientEvent, callback: @escaping NormalCallback) {
        // stub
    }

    public func off(_ event: String) {}
}

public class SocketManager {
    public var defaultSocket: SocketIOClient

    public init(socketURL: URL, config: SocketIOClientConfiguration = []) {
        self.defaultSocket = SocketIOClient()
    }
}
