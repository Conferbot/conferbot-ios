//
//  EmailTranscript.swift
//  Conferbot
//
//  "Email me this chat" (web ts/chat/emailTranscript.ts; ported from the
//  React Native SDK's src/core/emailTranscript.ts): the visitor gets the
//  whole conversation in their inbox, and the address they give is kept on
//  the conversation like any email they leave.
//
//  Sent by the embed server, only ever to the address typed here, and
//  rate-limited (5 per 15 minutes per IP, shared with the web route). The web
//  posts to /api/v1/chat/transcript-email with the botId in the body; an app
//  posts to the mobile base path, /api/v1/mobile/chat/transcript-email, and
//  the bot comes from its X-Bot-ID header (embed-server #193).
//
//  Pure: the request's path and body, and how its answer reads.
//

import Foundation

public struct TranscriptEmailResult: Equatable {
    public let ok: Bool
    public let message: String?

    public init(ok: Bool, message: String? = nil) {
        self.ok = ok
        self.message = message
    }
}

public enum EmailTranscript {

    /// Under the mobile API base (".../api/v1/mobile").
    public static let path = "/chat/transcript-email"

    /// The web's address check (emailTranscript.ts EMAIL_RE).
    public static func isEmail(_ email: String?) -> Bool {
        let e = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return e.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$", options: .regularExpression) != nil
    }

    public static func body(chatSessionId: String, email: String) -> [String: Any] {
        ["chatSessionId": chatSessionId, "email": email.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    /// The server's answer read as the web reads it: sent only on a 2xx with
    /// `success: true`; otherwise its message, if it gave one (an invalid
    /// address is a 400, an unknown session a 200 with success false, the
    /// rate limit a 429 with `message`).
    public static func result(status: Int, data: [String: Any]?) -> TranscriptEmailResult {
        let ok = (200..<300).contains(status) && data?["success"] as? Bool == true
        if ok { return TranscriptEmailResult(ok: true) }
        let raw = ((data?["message"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptEmailResult(ok: false, message: raw.isEmpty ? nil : String(raw.prefix(200)))
    }

    /// What the card says when it did not go: the server's words (it words
    /// them in English, as the SDK is), else ours.
    public static func errorText(_ r: TranscriptEmailResult?) -> String {
        if let r = r, !r.ok, let m = r.message { return m }
        return Copy.sendFailed
    }

    /// The web's English strings (i18n en: chat.menu.emailChat, mailchat.*, form.*).
    public enum Copy {
        public static let menu = "Email me this chat"
        public static let title = "Email me this chat"
        public static let sub = "We'll send the whole conversation to your inbox."
        public static let placeholder = "you@company.com"
        public static let label = "Your email"
        public static let send = "Send"
        public static let sending = "Sending\u{2026}"
        public static let cancel = "Cancel"
        public static let checkEmail = "Please check the email address."
        public static let sendFailed = "We couldn't send it just now. Please try again."
        public static func sent(_ email: String) -> String { "Sent! Check your inbox at \(email)" }
    }
}
