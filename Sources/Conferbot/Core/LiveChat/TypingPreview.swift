//
//  TypingPreview.swift
//  Conferbot
//
//  Typing preview ("sneak peek"): while a person is chatting with the
//  visitor, the agent sees what the visitor is typing before it is sent.
//  Ported from the React Native SDK (src/core/typingPreview.ts), itself from
//  conferbot-widget src/ts/chat/typingPreview.ts (cleanDraft,
//  createDraftSender) and its wiring in src/index.ts (updateVisitorDraft:
//  off when the owner set visitorDraftPreview to false, never for a secret
//  field, only while a person is in the chat).
//
//  The composer calls update() on every change; drafts go out as
//  `visitor-draft {chatSessionId, draft}` at most every draftThrottleMs (the
//  latest text always follows, trailing), trimmed and capped at draftMax.
//  clear() sends one empty draft on send, or when the field is emptied, so
//  the agent's preview goes away at once. The server relays drafts only to
//  the conversation's agents and never keeps them (embed-server
//  liveChat/visitorDraft). Pure: the timers are injected.
//

import Foundation

public enum TypingPreview {

    public static let draftMax = 500
    public static let draftThrottleMs: Double = 300

    public static func cleanDraft(_ value: Any?) -> String {
        guard let s = value as? String else { return "" }
        return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(draftMax))
    }

    /// Never preview what looks like a secret or card data: a secure field,
    /// or a field whose content type is a password, a one-time code or a card.
    public static func isSensitiveField(secure: Bool = false, contentType: String? = nil) -> Bool {
        if secure { return true }
        let type = (contentType ?? "").lowercased()
        return type == "password" || type == "newpassword" || type == "onetimecode" || type.hasPrefix("creditcard")
    }

    /// Whether drafts go to the agent at all: the owner allows it and a person is in the chat.
    public static func draftPreviewOn(_ customizations: [String: Any]?, chattingWithPerson: Bool) -> Bool {
        (customizations?["visitorDraftPreview"] as? Bool) != false && chattingWithPerson
    }

    /// The throttled sender.
    public final class DraftSender {
        public typealias SetTimer = (_ ms: Double, _ fn: @escaping () -> Void) -> AnyObject
        public typealias ClearTimer = (AnyObject) -> Void

        private let send: (String) -> Void
        private let intervalMs: Double
        private let now: () -> Double
        private let setTimer: SetTimer
        private let clearTimer: ClearTimer
        private var lastSent = ""
        private var lastSentAt = -Double.infinity
        private var pending: String?
        private var timer: AnyObject?

        public init(send: @escaping (String) -> Void, intervalMs: Double = TypingPreview.draftThrottleMs,
                    now: @escaping () -> Double, setTimer: @escaping SetTimer, clearTimer: @escaping ClearTimer) {
            self.send = send
            self.intervalMs = intervalMs
            self.now = now
            self.setTimer = setTimer
            self.clearTimer = clearTimer
        }

        private func flush() {
            timer = nil
            guard let draft = pending else { return }
            pending = nil
            if draft == lastSent { return }
            lastSent = draft
            lastSentAt = now()
            send(draft)
        }

        public func update(_ text: String) {
            let draft = TypingPreview.cleanDraft(text)
            if draft.isEmpty { return clear() }
            pending = draft
            if timer != nil { return }
            let wait = intervalMs - (now() - lastSentAt)
            if wait <= 0 { flush() } else { timer = setTimer(wait) { [weak self] in self?.flush() } }
        }

        public func clear() {
            if let t = timer { clearTimer(t) }
            timer = nil
            pending = nil
            if lastSent.isEmpty { return }
            lastSent = ""
            lastSentAt = now()
            send("")
        }
    }
}
