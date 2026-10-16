//
//  LiveEvents.swift
//  Conferbot
//
//  Live chat events beyond the handover line (HandoverState.swift): the chat
//  going back to the queue, a transfer, the same end again, a blocked
//  visitor and the closed chat. Ported from the React Native SDK's
//  src/core/liveEvents.ts (web widget sources):
//
//    ts/chat/liveTakeover.ts   live-chat-requeued ("Connecting you to another
//                              agent..." / "Connecting you to Sales..."),
//                              live-chat-transferred (kept in the record)
//    utils/recordIds.ts        endedSinceLastLive: a repeated chat-ended is
//                              the same end, and draws nothing
//    ts/chat/closedState.ts    the closed chat ("This conversation has been
//                              closed."), index.ts _applyVisitorBlock
//
//  Pure.
//

import Foundation

public enum LiveEvents {

    /// Its own id per event entry: two in the same millisecond must not merge (web liveEventId).
    public static func eventId(_ kind: String, now: Date = Date()) -> String {
        "\(kind)-\(Int(now.timeIntervalSince1970 * 1000))-\(String(UInt32.random(in: 0...UInt32.max), radix: 36))"
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    // MARK: - Back in the queue (live-chat-requeued)

    public static let requeuedDefaultText = "Connecting you to another agent..."

    /// What the visitor reads when the chat goes back to the queue (web requeuedText).
    public static func requeuedText(teamName: Any?) -> String {
        let raw = (teamName as? String) ?? ""
        let team = String(raw.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        return team.isEmpty ? requeuedDefaultText : "Connecting you to \(team)..."
    }

    /// The requeued line's record entry (web: id, type, time, text).
    public static func requeuedEntry(_ data: [String: Any]?, now: Date = Date()) -> [String: Any] {
        let id = eventId("requeued", now: now)
        return ["id": id, "_id": id, "type": "live-chat-requeued", "shape": "live-chat-requeued",
                "time": iso(now), "text": requeuedText(teamName: data?["teamName"])]
    }

    // MARK: - Transferred (live-chat-transferred)

    /// The transfer line the server wrote into the record, as the widget
    /// keeps it in its own copy (so the next write keeps it). nil when
    /// malformed. Not drawn: the requeued line or the next agent's join says
    /// what happened.
    public static func transferEntry(_ data: [String: Any]?) -> [String: Any]? {
        guard let e = data?["entry"] as? [String: Any], let id = e["id"] as? String, let text = e["text"] as? String else { return nil }
        var out: [String: Any] = ["id": id, "_id": id, "shape": "live-chat-transfer", "type": "live-chat-transfer",
                                  "time": (e["time"] as? String) ?? iso(Date()), "text": String(text.prefix(200))]
        if let kind = e["kind"] { out["kind"] = "\(kind)" }
        return out
    }

    // MARK: - The same end again (chat-ended)

    /// A live chat going on again: someone joined, the AI came back, or a
    /// message went either way (web recordIds.ts LIVE_AGAIN).
    public static let liveAgain: Set<String> = [
        "agent-joined-message", "agent-joined", "ai-agent-resumed", "agent-message", "agent-message-file",
        "agent-message-audio", "agent-message-rich", "user-live-message", "user-live-message-file",
    ]

    /// Has the live chat already ended, with nothing live since? A repeated
    /// chat-ended is then the same end again: no second "Chat ended" line, no
    /// second survey (web endedSinceLastLive).
    public static func endedSinceLastLive(_ record: [[String: Any]]) -> Bool {
        for entry in record.reversed() {
            let type = entry["type"] as? String
            let shape = entry["shape"] as? String
            let kind = type ?? shape
            if kind == "agent-chat-ended" { return true }
            if let k = kind, liveAgain.contains(k) { return false }
            if let s = shape, liveAgain.contains(s) { return false }
        }
        return false
    }

    // MARK: - Blocked, and the closed chat

    /// The neutral line a blocked visitor sees (embed-server visitorBlock CLOSED_TEXT, web system.closed).
    public static let closedText = "This conversation has been closed."
    public static let chatEndedText = "Chat ended"
    public static let newChatText = "Start a new chat"

    /// The handshake refused a blocked visitor (connect_error "visitor_blocked").
    /// socket.io-client-swift hands the error's data to the "error" event.
    public static func isBlockedError(_ data: [Any]) -> Bool {
        data.contains { item in
            if let s = item as? String { return s == "visitor_blocked" }
            if let d = item as? [String: Any] { return d["message"] as? String == "visitor_blocked" }
            return false
        }
    }

    /// The visitor-blocked event's line: the server's words, else ours.
    public static func blockedText(_ data: [String: Any]?) -> String {
        let m = String(((data?["message"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        return m.isEmpty ? closedText : m
    }

    public struct ClosedState: Equatable {
        public enum Kind: String { case blocked, ended }
        public let kind: Kind
        public let text: String
        /// Offer "Start a new chat" (never to a blocked visitor: the server refuses them).
        public let newChat: Bool
        /// The composer takes no more input.
        public let inputOff: Bool
    }

    /// The chat's closed state, or nil while it is open:
    ///   blocked  the workspace blocked the visitor: the neutral line, no
    ///            input, no new chat.
    ///   ended    the live chat ended and nothing is going on (no step
    ///            waiting, no person, nothing live since the end): "Chat
    ///            ended" and a button to start a new chat; the composer is
    ///            off, as the web turns it off on chat-ended.
    public static func closedState(_ record: [[String: Any]], blocked: String?, stepWaiting: Bool, live: Bool) -> ClosedState? {
        if let b = blocked { return ClosedState(kind: .blocked, text: b, newChat: false, inputOff: true) }
        if stepWaiting || live { return nil }
        guard endedSinceLastLive(record) else { return nil }
        return ClosedState(kind: .ended, text: chatEndedText, newChat: true, inputOff: true)
    }
}
