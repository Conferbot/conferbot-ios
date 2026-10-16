//
//  AnswerFeedback.swift
//  Conferbot
//
//  "Helpful?" under an AI answer, as the web widget's ts/chat/answerFeedback.ts
//  (ported from the React Native SDK's src/core/answerFeedback.ts).
//
//    ask     "Helpful?" with a thumb up and a thumb down, on the newest
//            answer only (an older unrated one steps aside).
//    up      sent at once ({helpful:true}); "Thanks for letting us know!",
//            then the quiet rated line.
//    down    sent at once ({helpful:false}) - a No never waits for a reason.
//            "Sorry about that. What went wrong?" with four reasons; a reason
//            is sent too and opens an optional comment. "Talk to a person"
//            (only while nobody is coming or here) and "Ask another way"
//            stay right there.
//    rated   both thumbs, the chosen one pressed, and the reason. Tapping
//            the other thumb changes the vote. A restored answer draws this.
//
//  Pure: `HelpfulRow.step` says what a tap does (the vote to send and the
//  view next); ConferBot sends it (`ai-answer-feedback`) and keeps it on the
//  answer's message and record entry so a restore draws it.
//

import Foundation

/// A visitor's vote on one AI answer.
public struct AnswerFeedback: Codable, Equatable {
    public let helpful: Bool
    public let reason: String?
    public let comment: String?

    public init(helpful: Bool, reason: String? = nil, comment: String? = nil) {
        self.helpful = helpful
        self.reason = reason
        self.comment = comment
    }

    /// The payload's own fields (web: {helpful, reason?, comment?}).
    public var payload: [String: Any] {
        var out: [String: Any] = ["helpful": helpful]
        if let reason = reason { out["reason"] = reason }
        if let comment = comment { out["comment"] = comment }
        return out
    }
}

public enum HelpfulText {
    public static let ask = "Helpful?"
    public static let groupLabel = "Was this answer helpful?"
    public static let yes = "Yes, helpful"
    public static let no = "No, not helpful"
    public static let ratedUp = "Helpful"
    public static let ratedDown = "Not helpful"
    public static let thanks = "Thanks for letting us know!"
    public static let sorry = "Sorry about that. What went wrong?"
    public static let comment = "Add a comment (optional)"
    public static let sendFeedback = "Send feedback"
    public static let retry = "Ask another way"
    public static let thanksComment = "Thanks, that helps us improve."
    public static let talkToPerson = "Talk to a person"
    public static let talkToPersonAsk = "I'd like to talk to a person, please."
}

public enum HelpfulRow {

    public enum View: String { case ask, thanks, down, rated }

    /// The reasons and their words (web FEEDBACK_REASONS, i18n en).
    public static let reasons: [(key: String, label: String)] = [
        ("wrong", "Wrong"), ("outdated", "Outdated"), ("unanswered", "Didn't answer"), ("other", "Other"),
    ]

    /// How long "Thanks for letting us know!" shows before the rated line (web: 1800 ms).
    public static let thanksSeconds: Double = 1.8

    public static func reasonLabel(_ r: String?) -> String {
        reasons.first { $0.key == r }?.label ?? ""
    }

    /// A stored vote, or nil when it is not one (web normalizeFeedback).
    public static func normalize(_ raw: AnswerFeedback?) -> AnswerFeedback? {
        guard let raw = raw else { return nil }
        if raw.helpful { return AnswerFeedback(helpful: true) }
        let reason = reasons.contains { $0.key == raw.reason } ? raw.reason : nil
        let comment = cleanComment(raw.comment)
        return AnswerFeedback(helpful: false, reason: reason, comment: comment.isEmpty ? nil : comment)
    }

    /// The rated line's words: "Helpful", or "Not helpful · Outdated".
    public static func ratedLabel(_ fb: AnswerFeedback?) -> String {
        guard let fb = fb else { return "" }
        if fb.helpful { return HelpfulText.ratedUp }
        let reason = reasonLabel(fb.reason)
        return reason.isEmpty ? HelpfulText.ratedDown : "\(HelpfulText.ratedDown) \u{00B7} \(reason)"
    }

    /// A comment as sent: one line, trimmed, at most 500 characters.
    public static func cleanComment(_ text: String?) -> String {
        let one = (text ?? "").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return String(one.prefix(500))
    }

    public struct State: Equatable {
        public var view: View
        public var current: AnswerFeedback?
        /// The comment went: the field is replaced by "Thanks, that helps us improve."
        public var commented: Bool
    }

    public enum Tap: Equatable {
        case vote(Bool)
        case reason(String)
        case comment(String)
        case human
        case retry
        /// The thanks line's time is up.
        case settle
    }

    public struct Outcome: Equatable {
        public var state: State
        /// The vote to send, when there is one.
        public var send: AnswerFeedback?
        /// The visitor's words to send ("Talk to a person").
        public var ask: String?
        /// Focus the composer ("Ask another way").
        public var focus = false
    }

    /// Where a row starts: rated when the answer already has a vote.
    public static func start(_ initial: AnswerFeedback?) -> State {
        let current = normalize(initial)
        return State(view: current == nil ? .ask : .rated, current: current, commented: false)
    }

    /// What a tap does.
    public static func step(_ s: State, _ tap: Tap) -> Outcome {
        switch tap {
        case .vote(let helpful):
            // The same thumb again: nothing new.
            if let c = s.current, c.helpful == helpful { return Outcome(state: s) }
            let fb = AnswerFeedback(helpful: helpful)
            return Outcome(state: State(view: helpful ? .thanks : .down, current: fb, commented: false), send: fb)
        case .reason(let reason):
            guard s.view == .down, reasons.contains(where: { $0.key == reason }) else { return Outcome(state: s) }
            let fb = AnswerFeedback(helpful: false, reason: reason)
            var next = s
            next.current = fb
            return Outcome(state: next, send: fb)
        case .comment(let text):
            guard s.view == .down, !s.commented else { return Outcome(state: s) }
            let comment = cleanComment(text)
            var next = s
            next.commented = true
            // An empty comment sends nothing, and the field still says thanks (web).
            guard !comment.isEmpty else { return Outcome(state: next) }
            let fb = AnswerFeedback(helpful: false, reason: s.current?.reason, comment: comment)
            next.current = fb
            return Outcome(state: next, send: fb)
        case .human:
            var next = s
            next.view = .rated
            return Outcome(state: next, ask: HelpfulText.talkToPersonAsk)
        case .retry:
            var next = s
            next.view = .rated
            return Outcome(state: next, focus: true)
        case .settle:
            guard s.view == .thanks, s.current?.helpful == true else { return Outcome(state: s) }
            var next = s
            next.view = .rated
            return Outcome(state: next)
        }
    }

    /// The record with the vote kept on the answer's agent-message entry
    /// (web _sendAnswerFeedback: `entry.feedback = { ...feedback, at }`).
    /// nil when no entry matches.
    public static func withFeedback(_ record: [[String: Any]], agentMessageId: String, _ fb: AnswerFeedback, at: String) -> [[String: Any]]? {
        var hit = false
        let out = record.map { entry -> [String: Any] in
            let kind = (entry["shape"] as? String) ?? (entry["type"] as? String)
            let id = (entry["id"] as? String) ?? (entry["_id"] as? String)
            guard kind == "agent-message" || entry["type"] as? String == "agent-message", id == agentMessageId else { return entry }
            hit = true
            var e = entry
            var stored = fb.payload
            stored["at"] = at
            e["feedback"] = stored
            return e
        }
        return hit ? out : nil
    }

    /// Only the newest unrated AI answer asks; an older unrated one steps aside.
    public static func asksFor(_ messageId: String, in messages: [any RecordItem], rateable: (AgentMessageRecord) -> Bool) -> Bool {
        for item in messages.reversed() {
            guard let m = item as? AgentMessageRecord, rateable(m) else { continue }
            return m.id == messageId
        }
        return false
    }
}
