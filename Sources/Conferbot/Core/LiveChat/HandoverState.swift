//
//  HandoverState.swift
//  Conferbot
//
//  Where a live-chat handover stands, read from the record, and the
//  "Connecting you with the team…" line that marks it. Ported from the React
//  Native SDK (src/core/handoverState.ts), itself from the web widget:
//  conferbot-widget src/ts/chat/handoverState.ts (the record reading),
//  src/core/events/agentListeners.ts (agent-left reasons, agent-accepted),
//  src/ts/chat/handlers/special.ts (_handleHandoverAccepted, the queue's
//  leave) and src/index.ts (the restore path).
//
//    bot / AI  ->  connecting (an AI agent passed the visitor on: the line
//                  with its typing dots)  ->  one of
//      joined       a person accepted              "Connected with the team"
//      unavailable  nobody could (the AI took the  "The team couldn't join just now"
//                   chat back, or the fallback ran)
//      cancelled    the visitor left the queue     "You left the queue"
//      ended        the chat ended first           "Chat ended before the team joined"
//
//  Pure: no socket, no UI. The record is the server record (ChatState
//  serverRecord): entries are dictionaries with a `type` (or `shape`).
//  Functions that change entries return a new list and leave the input alone.
//

import Foundation

public enum HandoverOutcome: String, Equatable {
    case joined, unavailable, cancelled, ended
}

public enum HandoverPhase: String, Equatable {
    case none, connecting, joined
}

public enum HandoverState {

    public typealias Entry = [String: Any]

    /// The web's English strings (ts/i18n/en.ts handover.*, system.*).
    public static let pendingText = "Connecting you with the team\u{2026}"

    public static func text(_ outcome: HandoverOutcome) -> String {
        switch outcome {
        case .joined: return "Connected with the team"
        case .unavailable: return "The team couldn't join just now"
        case .cancelled: return "You left the queue"
        case .ended: return "Chat ended before the team joined"
        }
    }

    /// The note under a person's join after an AI handed the visitor on.
    public static let handedOverNote = "They can see your conversation so far"

    /// The line's words: pending, or how the wait ended.
    public static func lineText(_ outcome: HandoverOutcome?) -> String {
        outcome.map(text) ?? pendingText
    }

    /// "<name> joined the chat" (web agentJoinedDivider.ts).
    public static func joinedText(_ name: String?) -> String {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(n.isEmpty ? "An agent" : n) joined the chat"
    }

    /// "<name> left the chat", or the pending line for a handover (web agentLeftDivider.ts).
    public static func agentLeftText(_ name: String?, handover: Bool) -> String {
        if handover { return lineText(nil) }
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(n.isEmpty ? "The agent" : n) left the chat"
    }

    // MARK: - Reading the record

    static func typeOf(_ r: Entry) -> String {
        if let t = r["type"] as? String, !t.isEmpty { return t }
        return r["shape"] as? String ?? ""
    }

    private static func isJoin(_ t: String) -> Bool { t == "agent-joined-message" || t == "agent-joined" }

    /// The id of the agent on an entry: `agentId`, or its `agentDetails._id`.
    static func agentId(_ r: Entry) -> String {
        if let id = r["agentId"] { return "\(id)" }
        if let details = r["agentDetails"] as? [String: Any] {
            if let id = details["_id"] ?? details["id"] { return "\(id)" }
        }
        return ""
    }

    /// An AI agent's join (recorded by a flow bot's visible AI handover).
    public static func isAIJoin(_ r: Entry) -> Bool {
        if r["ai"] as? Bool == true { return true }
        if (r["agentDetails"] as? [String: Any])?["isAIAgent"] as? Bool == true { return true }
        return agentId(r).hasPrefix("ai-agent-")
    }

    /// Things that close a live-chat episode for good.
    public static let closers: Set<String> = ["agent-chat-ended", "agent-declined-message", "queue-self-resolved", "ai-agent-inactive-close"]

    /// An agent-left entry that is an AI handing the visitor to the team.
    public static func isHandoverLeft(_ r: Entry) -> Bool {
        typeOf(r) == "agent-left-chat" && r["handover"] as? Bool == true
    }

    static func settledOf(_ r: Entry) -> HandoverOutcome? {
        (r["settled"] as? String).flatMap(HandoverOutcome.init(rawValue:))
    }

    /// Where the latest live episode stands:
    ///   joined      a person (not the AI) joined and has not left;
    ///   connecting  an AI handed the visitor to the team and no person has joined yet;
    ///   none        anything else (bot only, the person left, the chat ended).
    public static func phase(_ record: [Entry]?) -> HandoverPhase {
        for r in (record ?? []).reversed() {
            let t = typeOf(r)
            if closers.contains(t) { return .none }
            if isJoin(t) {
                if isAIJoin(r) { continue }
                return .joined
            }
            if t == "agent-left-chat" { return r["handover"] as? Bool == true ? .connecting : .none }
        }
        return .none
    }

    /// "Talk to a person" is offered only when nobody is coming or here (web quickActions.ts).
    public static func talkToPersonAllowed(_ record: [Entry]?) -> Bool {
        phase(record) == .none
    }

    /// The same person joining again (a repeat agent-accepted after a
    /// reconnect or from a second device): nothing new to announce.
    public static func isRepeatJoin(_ record: [Entry]?, agentId id: String?) -> Bool {
        guard let id = id, !id.isEmpty else { return false }
        for r in (record ?? []).reversed() {
            let t = typeOf(r)
            if isJoin(t) { return agentId(r) == id }
            if t == "agent-left-chat" || closers.contains(t) { return false }
        }
        return false
    }

    /// How the handover line at `index` ended, from what the record says came
    /// after it; nil while it is still pending. A `settled` already written wins.
    public static func outcome(at index: Int, in record: [Entry]) -> HandoverOutcome? {
        guard record.indices.contains(index) else { return nil }
        if let s = settledOf(record[index]) { return s }
        for r in record.dropFirst(index + 1) {
            let t = typeOf(r)
            if isJoin(t) { return isAIJoin(r) ? .unavailable : .joined }
            if t == "agent-declined-message" { return .unavailable }
            if t == "queue-self-resolved" { return .cancelled }
            if t == "agent-chat-ended" || t == "ai-agent-inactive-close" { return .ended }
            // Escalated again: this earlier wait was over one way or another.
            if isHandoverLeft(r) { return .unavailable }
        }
        return nil
    }

    /// Is a handover line still waiting (so a repeat escalation draws none)?
    public static func hasPendingLine(_ record: [Entry]?) -> Bool {
        (record ?? []).contains { isHandoverLeft($0) && settledOf($0) == nil }
    }

    private static func settled(_ r: Entry, _ outcome: HandoverOutcome) -> Entry {
        var e = r
        e["settled"] = outcome.rawValue
        if e["text"] != nil { e["text"] = lineText(outcome) }
        return e
    }

    /// Settle every pending handover line: `settled` is written, and an entry
    /// that carries display `text` gets the settled words.
    public static func settle(_ record: [Entry], _ outcome: HandoverOutcome) -> (record: [Entry], settled: Int) {
        var count = 0
        let next = record.map { r -> Entry in
            guard isHandoverLeft(r), settledOf(r) == nil else { return r }
            count += 1
            return settled(r, outcome)
        }
        return (count > 0 ? next : record, count)
    }

    /// Before a restored record is drawn: settle every handover line whose
    /// outcome the record already knows, and mark a person's join that
    /// followed an AI handover (it draws "They can see your conversation so far").
    public static func annotateRestored(_ record: [Entry]) -> (record: [Entry], changed: Int) {
        var changed = 0
        var handedOver = false
        var next: [Entry] = []
        for (i, r) in record.enumerated() {
            if isHandoverLeft(r) {
                handedOver = true
                if settledOf(r) == nil, let o = outcome(at: i, in: record) {
                    changed += 1
                    next.append(settled(r, o))
                } else {
                    next.append(r)
                }
                continue
            }
            let t = typeOf(r)
            var out = r
            if isJoin(t) && handedOver && !isAIJoin(r) && r["afterAI"] as? Bool != true {
                changed += 1
                out["afterAI"] = true
                out["note"] = handedOverNote
            }
            if closers.contains(t) { handedOver = false }
            next.append(out)
        }
        return (changed > 0 ? next : record, changed)
    }

    /// Did an AI agent hand this chat to a person (so the person has read it)?
    public static func aiHandedOver(_ record: [Entry]?) -> Bool {
        (record ?? []).contains(where: isHandoverLeft)
    }

    // MARK: - Socket events

    /// What an agent-left means (web agentListeners.ts "agent-left").
    public enum AgentLeftKind: String {
        /// An AI pausing an idle visitor (reason visitor_inactive): it has
        /// not left, the visitor's next message brings it back.
        case ignore
        /// An AI passing the visitor to a person (reason escalated, or the
        /// leaver is an AI agent): the Connecting line.
        case handover
        /// A person left: "<name> left the chat".
        case left
    }

    public static func agentLeftKind(_ data: [String: Any]?) -> AgentLeftKind {
        if data?["reason"] as? String == "visitor_inactive" { return .ignore }
        let ai = (data?["agentDetails"] as? [String: Any])?["isAIAgent"] as? Bool == true
        if data?["reason"] as? String == "escalated" || data?["handover"] as? Bool == true || ai { return .handover }
        return .left
    }

    /// An agent-accepted from an AI agent (taking the chat, or taking it back).
    public static func isAIAccept(_ data: [String: Any]?) -> Bool {
        let details = data?["agentDetails"] as? [String: Any]
        if details?["isAIAgent"] as? Bool == true { return true }
        return details.map { "\($0["_id"] ?? "")" }?.hasPrefix("ai-agent-") ?? false
    }

    public struct AcceptedPlan: Equatable {
        public let ai: Bool
        /// How a pending Connecting line settles.
        public let outcome: HandoverOutcome
        /// Draw the join line (not for the same person again).
        public let announce: Bool
        /// The person follows an AI handover: the join line's note.
        public let afterAI: Bool
        public let humanJoined: Bool
    }

    /// agent-accepted, read against the record (web special.ts _handleHandoverAccepted).
    public static func acceptedPlan(_ record: [Entry]?, data: [String: Any]?) -> AcceptedPlan {
        let ai = isAIAccept(data)
        let id = ((data?["agentDetails"] as? [String: Any])?["_id"]).map { "\($0)" }
        let repeated = isRepeatJoin(record, agentId: id)
        return AcceptedPlan(ai: ai, outcome: ai ? .unavailable : .joined, announce: !repeated,
                            afterAI: !ai && aiHandedOver(record), humanJoined: !ai && !repeated)
    }

    // MARK: - Leaving the queue

    /// queue-self-resolve: the visitor leaves the queue (embed-server handoverHandler.js).
    public static func queueSelfResolvePayload(_ chatSessionId: String, articleId: String? = nil) -> [String: Any] {
        var p: [String: Any] = ["chatSessionId": chatSessionId]
        if let a = articleId, !a.isEmpty { p["articleId"] = a }
        return p
    }

    public enum QueueLeave: String { case leave, stay }

    /// The server's answer to queue-self-resolve: leave the wait (ok, nothing
    /// waiting any more, or no answer), or stay because a person already
    /// picked the chat up. agent_joined comes only while the ticket is still
    /// open; once a person accepted, the server answers not_waiting, so on
    /// not_waiting ask live-chat-state and pass it as `state`: live means stay.
    public static func queueLeaveResult(_ res: [String: Any]?, state: [String: Any]? = nil) -> QueueLeave {
        if res?["reason"] as? String == "agent_joined" { return .stay }
        if res?["ok"] as? Bool != true && state?["status"] as? String == "live" { return .stay }
        return .leave
    }

    /// Ask live-chat-state before leaving on this answer to queue-self-resolve?
    public static func queueLeaveNeedsState(_ res: [String: Any]?) -> Bool {
        res?["ok"] as? Bool != true && res?["reason"] as? String == "not_waiting"
    }

    // MARK: - Restore (live-chat-state)

    static let restoreLiveTypes: Set<String> = [
        "agent-joined-message", "agent-message", "agent-message-file", "agent-message-audio",
        "agent-message-rich", "user-live-message", "user-live-message-file", "agent-left-chat",
    ]
    static let episodeClosers: Set<String> = ["agent-declined-message", "agent-chat-ended", "queue-self-resolved"]

    private static func isLiveEntry(_ r: Entry) -> Bool {
        restoreLiveTypes.contains(r["type"] as? String ?? "") || restoreLiveTypes.contains(r["shape"] as? String ?? "")
    }

    /// A restored chat: should the server be asked where it stands
    /// (live-chat-state)? Only the latest live episode counts.
    /// `atHandover`: the flow was waiting on its handover step.
    public static func restoreNeedsLiveChatState(_ record: [Entry]?, atHandover: Bool = false) -> Bool {
        let list = record ?? []
        var start = 0
        for (i, r) in list.enumerated() {
            let t = r["type"] as? String ?? ""
            if (t == "agent-left-chat" && r["takeover"] as? Bool == true) || episodeClosers.contains(t) { start = i + 1 }
        }
        let ongoing = list.dropFirst(start).contains(where: isLiveEntry)
        let ended = list.contains { episodeClosers.contains($0["type"] as? String ?? "") } && !ongoing
        return ongoing || (atHandover && !ended)
    }

    public struct RestoredLiveChat: Equatable {
        public enum Status: String { case live, waiting, fallback, ended, none }
        public struct Person: Equatable {
            public let id: String
            public let name: String
            public let email: String?
        }
        public let status: Status
        /// The person on the chat (live only).
        public let agent: Person?
        /// How a pending Connecting line settles now; nil leaves it pending.
        public let settle: HandoverOutcome?
        /// Draw the join line the closed app missed.
        public let drawJoin: Bool
        /// That join follows an AI handover (its note).
        public let afterAI: Bool
        /// Seconds left of the handover's max wait (waiting only).
        public let remainingSeconds: Int?
    }

    /// The server's live-chat-state (embed-server liveChatSession
    /// getLiveChatState: { status, agentDetails, waitEndsAt, takeover })
    /// applied to a restored record.
    public static func restoredLiveChat(_ state: [String: Any]?, record: [Entry]?, now: Date = Date()) -> RestoredLiveChat {
        let raw = state?["status"] as? String ?? "none"
        let details = state?["agentDetails"] as? [String: Any]
        let person = details.flatMap { $0["isAIAgent"] as? Bool == true ? nil : $0 }
        if raw == "live", let p = person {
            let email = (p["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return RestoredLiveChat(
                status: .live,
                agent: .init(id: "\(p["_id"] ?? "")", name: p["name"] as? String ?? "", email: email),
                settle: .joined, drawJoin: phase(record) != .joined, afterAI: aiHandedOver(record), remainingSeconds: nil)
        }
        if raw == "waiting" {
            var remaining: Int?
            if let ends = (state?["waitEndsAt"] as? NSNumber)?.doubleValue ?? Double("\(state?["waitEndsAt"] ?? "")"), ends > 0 {
                remaining = max(5, Int(((ends - now.timeIntervalSince1970 * 1000) / 1000).rounded()))
            }
            return RestoredLiveChat(status: .waiting, agent: nil, settle: nil, drawJoin: false, afterAI: false, remainingSeconds: remaining)
        }
        if raw == "ended" {
            return RestoredLiveChat(status: .ended, agent: nil, settle: .ended, drawJoin: false, afterAI: false, remainingSeconds: nil)
        }
        if raw == "fallback" {
            return RestoredLiveChat(status: .fallback, agent: nil, settle: .unavailable, drawJoin: false, afterAI: false, remainingSeconds: nil)
        }
        // Live with nobody in it (every agent left), or no handover at all.
        return RestoredLiveChat(status: .none, agent: nil, settle: hasPendingLine(record) ? .unavailable : nil,
                                drawJoin: false, afterAI: false, remainingSeconds: nil)
    }

    /// What a restored chat does next, from the server's answer:
    ///   live      a person (or, still waiting after an AI escalation, the AI)
    ///             has the chat: live mode, the flow is not run again;
    ///   wait      still in the queue at the flow's handover step: back on
    ///             that step's wait, without asking for a person again;
    ///   continue  the wait or the live chat is over: the flow carries on
    ///             from its handover step;
    ///   ask       the flow was at its handover step but the request never
    ///             went out: run the step again;
    ///   start     nothing live to rejoin: as for any restored chat.
    public enum RestoreStep: String { case live, wait, `continue`, ask, start }

    public static func restoreStep(_ r: RestoredLiveChat, atHandover: Bool, record: [Entry]? = nil) -> RestoreStep {
        if r.status == .live { return .live }
        if r.status == .waiting { return atHandover ? .wait : .live }
        if !atHandover { return .start }
        let list = record ?? []
        let asked = list.contains(where: isLiveEntry)
        return r.status == .none && !asked && !hasPendingLine(list) ? .ask : .continue
    }
}
