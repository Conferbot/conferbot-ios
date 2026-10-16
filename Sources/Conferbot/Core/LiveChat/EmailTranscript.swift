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

    /// What the card says when it did not go: the server's words in English
    /// (it words them in English), ours in the other languages (web
    /// emailTranscript.ts).
    public static func errorText(_ r: TranscriptEmailResult?) -> String {
        if I18n.isEnglish, let r = r, !r.ok, let m = r.message { return m }
        return Copy.sendFailed
    }

    /// The web's strings (ts/chat/emailTranscript.ts: chat.menu.emailChat,
    /// mailchat.*, form.*, common.*), in the active language.
    public enum Copy {
        public static var menu: String { I18n.t("chat.menu.emailChat") }
        public static var title: String { I18n.t("chat.menu.emailChat") }
        public static var sub: String { I18n.t("mailchat.sub") }
        public static var placeholder: String { I18n.t("form.emailPlaceholder") }
        public static var label: String { I18n.t("form.yourEmail") }
        public static var send: String { I18n.t("common.send") }
        public static var sending: String { I18n.t("common.sendingEllipsis") }
        public static var cancel: String { I18n.t("common.cancel") }
        public static var checkEmail: String { I18n.t("form.checkEmail") }
        public static var sendFailed: String { I18n.t("form.sendFailed") }
        public static func sent(_ email: String) -> String { I18n.t("mailchat.sent", ["email": email]) }
    }
}
