//
//  Push.swift
//  Conferbot
//
//  Push notifications (embed-server #189, docs/mobile-push.md), ported from
//  React Native's src/core/push.ts (#77).
//
//  When an agent or the AI replies and the visitor has no live socket in
//  that chat, embed-server sends a push (APNs on iOS, FCM on Android) to the
//  tokens registered for that conversation. The SDK has no push library of
//  its own: the app gets its APNs device token (or its FCM token, with
//  Firebase Messaging), hands it to `ConferBot.setPushToken`, and forwards
//  notifications it receives or the visitor taps to `handlePushNotification`.
//
//  Pure: the payload's shape, the request bodies, how the server's answers
//  read, and the registrar that keeps one token registered with the current
//  conversation (again for each new one, unregistered on logout).
//

import Foundation

/// Which kind of token the app passes: its APNs device token, or an FCM
/// registration token (an iOS app using Firebase Messaging).
public enum PushTokenType: String, Equatable {
    case apns
    case fcm
}

/// A Conferbot notification's data (all strings, as the server sends them,
/// beside `aps` in the APNs payload).
public struct ConferbotPush: Equatable {
    public enum SenderType: String, Equatable {
        /// A person on the team.
        case agent
        /// The AI.
        case bot
    }

    public let botId: String
    /// The conversation to open (also the notification's `thread-id`).
    public let chatSessionId: String
    /// The reply's id, may be "".
    public let messageId: String
    public let senderType: SenderType
    public let senderName: String
    public let body: String

    public init(botId: String, chatSessionId: String, messageId: String = "",
                senderType: SenderType = .bot, senderName: String = "", body: String = "") {
        self.botId = botId
        self.chatSessionId = chatSessionId
        self.messageId = messageId
        self.senderType = senderType
        self.senderName = senderName
        self.body = body
    }

    /// The Conferbot notification in `userInfo`, or nil when it is not one
    /// (another service's, another type, no bot or conversation).
    public static func parse(_ userInfo: [AnyHashable: Any]?) -> ConferbotPush? {
        guard let d = Push.dataOf(userInfo), Push.str(d["type"]) == Push.typeMessage else { return nil }
        let botId = Push.str(d["botId"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let chatSessionId = Push.str(d["chatSessionId"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !botId.isEmpty, !chatSessionId.isEmpty else { return nil }
        return ConferbotPush(
            botId: botId,
            chatSessionId: chatSessionId,
            messageId: Push.str(d["messageId"]),
            senderType: Push.str(d["senderType"]) == "agent" ? .agent : .bot,
            senderName: Push.str(d["senderName"]),
            body: Push.str(d["body"])
        )
    }
}

/// The Conferbot notification in `userInfo`, or nil (RN `parseConferbotPush`).
public func parseConferbotPush(_ userInfo: [AnyHashable: Any]?) -> ConferbotPush? {
    ConferbotPush.parse(userInfo)
}

/// Whether `userInfo` is a Conferbot message notification (RN `isConferbotPush`).
public func isConferbotPush(_ userInfo: [AnyHashable: Any]?) -> Bool {
    ConferbotPush.parse(userInfo) != nil
}

/// The server's refusals (embed-server REGISTER_PUSH_FAILURES), the network or another failure.
public enum PushRegisterError: String, Equatable {
    case missingToken = "MISSING_TOKEN"
    case invalidToken = "INVALID_TOKEN"
    case missingSession = "MISSING_SESSION"
    case sessionForbidden = "SESSION_FORBIDDEN"
    case sessionNotFound = "SESSION_NOT_FOUND"
    case network = "NETWORK"
    case server = "SERVER"
}

public struct PushRegisterResult: Equatable {
    public let ok: Bool
    public let error: PushRegisterError?

    public init(ok: Bool, error: PushRegisterError? = nil) {
        self.ok = ok
        self.error = error
    }
}

public enum Push {
    /// `source` of every Conferbot push.
    public static let source = "conferbot"
    /// `type` of a new message.
    public static let typeMessage = "conferbot_message"
    /// The Android channel the server names (for reference; iOS has none).
    public static let channelId = "conferbot_messages"

    /// Under the mobile API base (ConferBotEndpoints.apiBaseURL, ".../api/v1/mobile").
    public static let registerPath = "/push/register"
    public static let unregisterPath = "/push/unregister"

    static func str(_ v: Any?) -> String {
        switch v {
        case nil, is NSNull: return ""
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let v?: return String(describing: v)
        }
    }

    /// The data map: the keys beside `aps` (APNs, and Firebase Messaging on
    /// iOS), or a nested `data` map.
    static func dataOf(_ userInfo: [AnyHashable: Any]?) -> [AnyHashable: Any]? {
        guard let userInfo = userInfo else { return nil }
        if str(userInfo["source"]) == source { return userInfo }
        if let nested = userInfo["data"] as? [AnyHashable: Any], str(nested["source"]) == source { return nested }
        return nil
    }

    /// The APNs device token as the server expects it: lowercase hex.
    public static func hex(_ deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    /// As the server decides when the SDK does not say: a 64-character hex
    /// token is APNs, anything else FCM.
    public static func tokenType(of token: String, type: PushTokenType? = nil) -> PushTokenType {
        if let type = type { return type }
        return token.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil ? .apns : .fcm
    }

    /// `POST /push/register`: no visitorId (the server takes the
    /// conversation's; one sent early in a chat is refused as SESSION_FORBIDDEN).
    public static func registerBody(token: String, chatSessionId: String, tokenType: PushTokenType,
                                    deviceInfo: [String: String]? = nil) -> [String: Any] {
        var body: [String: Any] = ["token": token, "chatSessionId": chatSessionId, "tokenType": tokenType.rawValue]
        if let info = deviceInfo, !info.isEmpty { body["deviceInfo"] = info }
        return body
    }

    public static func unregisterBody(token: String) -> [String: Any] { ["token": token] }

    /// Registered only on a 2xx with `success: true`; else the server's error
    /// code (a bare 404 is SESSION_NOT_FOUND).
    public static func registerResult(status: Int, data: [String: Any]?) -> PushRegisterResult {
        if (200...299).contains(status), data?["success"] as? Bool == true { return PushRegisterResult(ok: true) }
        let code = data?["error"] as? String ?? ""
        if let known = PushRegisterError(rawValue: code), known != .network, known != .server {
            return PushRegisterResult(ok: false, error: known)
        }
        if status == 404 { return PushRegisterResult(ok: false, error: .sessionNotFound) }
        return PushRegisterResult(ok: false, error: .server)
    }

    /// Worth trying again for the same token and conversation: the
    /// conversation is not on the server yet (a new chat is stored when the
    /// visitor first answers), or the network or server failed. A refused
    /// token or another visitor's conversation is not.
    public static func retryable(_ error: PushRegisterError?) -> Bool {
        error == .sessionNotFound || error == .network || error == .server
    }
}

/// One token registered with the current conversation: again for every new
/// conversation, once per (token, conversation) pair, and again on the next
/// `poke` while the server does not have the conversation yet. One request
/// at a time. RN `createPushRegistrar`.
@MainActor
public final class PushRegistrar {
    public typealias Register = ([String: Any]) async -> PushRegisterResult
    public typealias Unregister = (String) async -> Bool

    private let register: Register
    private let unregisterCall: Unregister
    private let deviceInfo: () -> [String: String]?

    public private(set) var token: String?
    private var type: PushTokenType = .fcm
    private var session: String?
    /// The token and conversation registered last.
    public private(set) var registered: (token: String, chatSessionId: String)?
    /// A pair the server refused for good (bad token, another visitor's chat).
    private var refused: String?
    private var inFlight: Task<Void, Never>?
    private var again = false

    public init(register: @escaping Register, unregister: @escaping Unregister,
                deviceInfo: @escaping () -> [String: String]? = { nil }) {
        self.register = register
        self.unregisterCall = unregister
        self.deviceInfo = deviceInfo
    }

    private var key: String { "\(token ?? "")\u{0}\(session ?? "")" }

    private func attempt() async {
        guard let t = token, let s = session else { return }
        if let done = registered, done.token == t, done.chatSessionId == s { return }
        if refused == key { return }
        let r = await register(Push.registerBody(token: t, chatSessionId: s, tokenType: type, deviceInfo: deviceInfo()))
        // Moved on meanwhile: the next run has it.
        guard t == token, s == session else { return }
        if r.ok { registered = (t, s) } else if !Push.retryable(r.error) { refused = key }
    }

    private func run() async {
        if let running = inFlight {
            again = true
            return await running.value
        }
        let task = Task { @MainActor in
            repeat {
                self.again = false
                await self.attempt()
            } while self.again
            self.inFlight = nil
        }
        inFlight = task
        await task.value
    }

    /// The app's token (nil or "" clears it: unregistered with the server).
    public func setToken(_ next: String?, type nextType: PushTokenType? = nil) async {
        let clean = next?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clean.isEmpty else {
            await unregister()
            token = nil
            return
        }
        let old = registered?.token
        token = clean
        refused = nil
        type = Push.tokenType(of: clean, type: nextType)
        // A refreshed token: the old one goes.
        if let old = old, old != clean {
            registered = nil
            _ = await unregisterCall(old)
        }
        await run()
    }

    /// The conversation now on the device (nil: none yet).
    public func setSession(_ id: String?) async {
        session = (id?.isEmpty ?? true) ? nil : id
        await run()
    }

    /// Something happened in the conversation: a registration that waits for
    /// it to reach the server tries again.
    public func poke() async { await run() }

    /// Logout / the visitor cleared: unregister, keep the token for the next
    /// conversation (not registered with this one again until a new one or
    /// a new `setToken`).
    public func unregister() async {
        let t = registered?.token ?? token
        registered = nil
        refused = (token != nil && session != nil) ? key : nil
        guard let t = t else { return }
        // Best effort: the server deactivates dead tokens on its own.
        _ = await unregisterCall(t)
    }
}
