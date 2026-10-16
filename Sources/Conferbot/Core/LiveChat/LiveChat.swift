//
//  LiveChat.swift
//  Conferbot
//
//  Live chat around a person or the AI, as the web widget shows it: where the
//  visitor stands in the queue, the "Sent / Delivered / Seen" line under their
//  latest message, an agent's translated message, the cards that keep a
//  conversation going when nobody can join (leave a message, an email for the
//  reply), and the post-chat rating. The shapes are the embed-server's
//  (queueService, readReceipts, liveTranslation, aiFallback, handoverHandler).
//  Pure: works on the dictionaries the socket JSON is decoded to.
//

import Foundation

public struct QueueStatus: Equatable {
    public let status: String
    public let position: Int?
    public let ahead: Int?
    public let agentsOnline: Int?
    public let estimateLabel: String?
    /// The server's estimate bucket (under_minute, about_1 ... longer), worded here.
    public var estimateBucket: String? = nil
    /// The routed team's usual first reply (embed-server replyTimeService): its bucket and words.
    public var typicalBucket: String? = nil
    public var typicalWait: String? = nil

    /// queue-status `typical` as replyTime reads it.
    public var typical: [String: Any]? {
        guard typicalBucket != nil || typicalWait != nil else { return nil }
        var t: [String: Any] = [:]
        if let b = typicalBucket { t["bucket"] = b }
        if let w = typicalWait { t["wait"] = w }
        return t
    }
}

public struct HandoverWaiting: Equatable {
    public let offline: Bool
    public let reason: String
    public let backAt: String?
    public var askEmail: Bool
    public var email: String?
}

public struct AgentTranslation: Codable, Equatable {
    public let from: String
    public let to: String
    public let original: String
}

public struct ReceiptMarks: Equatable {
    public var deliveredMessageId: String = ""
    public var seenMessageId: String = ""
    public init(deliveredMessageId: String = "", seenMessageId: String = "") {
        self.deliveredMessageId = deliveredMessageId
        self.seenMessageId = seenMessageId
    }
}

public enum ReceiptState: String, Equatable {
    case sent, delivered, seen
}

public struct VisitorReceipt: Equatable {
    public let id: String
    public let state: ReceiptState
}

/// Post-chat rating: from the bot's csatConfig; on only with enabled = true.
public struct CsatConfig: Equatable {
    public let ratingType: String
    public let titleText: String
    public let subtitleText: String
    public let thankYouText: String
    public let showFeedbackInput: Bool
    public let feedbackPlaceholder: String
}

/// A record entry as the receipt logic needs it.
public struct LiveEntry: Equatable {
    public let id: String
    public let kind: String
    public init(id: String, kind: String) {
        self.id = id
        self.kind = kind
    }
}

public enum LiveChat {

    /// What "Talk to a person" sends, in the visitor's language.
    public static var talkToPersonAsk: String { I18n.t("chat.talkToPersonAsk") }
    public static let queuePollSeconds: TimeInterval = 20

    private static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double, d.isFinite { return Int(d) }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }

    private static func str(_ v: Any?) -> String? {
        guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// queue-status as the visitor sees it, or nil when they are not waiting.
    public static func queueStatus(_ raw: [String: Any]?) -> QueueStatus? {
        guard let raw = raw, let status = raw["status"] as? String, status == "waiting" || status == "busy" else { return nil }
        let estimate = raw["estimate"] as? [String: Any]
        let typical = raw["typical"] as? [String: Any]
        return QueueStatus(status: status, position: int(raw["position"]), ahead: int(raw["ahead"]),
                           agentsOnline: int(raw["agentsOnline"]), estimateLabel: str(estimate?["label"]),
                           estimateBucket: estimate?["bucket"] as? String,
                           typicalBucket: typical?["bucket"] as? String, typicalWait: str(typical?["wait"]))
    }

    /// "1st", "2nd", "3rd", "11th"
    public static func ordinal(_ n: Int) -> String {
        let mod100 = n % 100
        if (11...13).contains(mod100) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// "You're next in line", "You're 3rd in line", "Connecting you to the team",
    /// in the active language (web queueCard.ts positionText: queue.*; {ord} is
    /// English's "3rd", the other languages say {n}).
    public static func queueLine(_ q: QueueStatus?) -> String {
        guard let p = q?.position else { return I18n.t("queue.connecting") }
        if p == 1 { return I18n.t("queue.next") }
        if p > 1 { return I18n.t("queue.position", ["n": p, "ord": ordinal(p)]) }
        return I18n.t("queue.connecting")
    }

    /// The server's label is already a phrase ("Under a minute", "About 2 min").
    public static func queueSubline(_ q: QueueStatus?) -> String {
        q?.estimateLabel ?? I18n.t("queue.soon")
    }

    /// The server's estimate buckets (embed-server liveChat/queueService), worded here (web queueCard.ts ESTIMATE_WORDS).
    static let estimateWords: [String: String] = [
        "under_minute": "queue.estimate.underMinute",
        "about_1": "queue.estimate.about1",
        "about_2": "queue.estimate.about2",
        "about_3": "queue.estimate.about3",
        "few": "queue.estimate.few",
        "longer": "queue.estimate.longer",
    ]

    /// The wait card's lines under the headline (web queueCard.ts
    /// estimateText and the card's third line): the live estimate in the
    /// visitor's language, else the usual wait ("Typical wait: a few
    /// minutes", ReplyTime.typicalWait), else a calm promise; then the usual
    /// wait again under a live estimate, when it says something else.
    public static func waitCardLines(_ q: QueueStatus?, typical: String?) -> (estimate: String, typical: String) {
        let estimate: String
        if let q = q, q.status == "waiting", let label = q.estimateLabel {
            estimate = q.estimateBucket.flatMap { estimateWords[$0] }.map { I18n.t($0) } ?? label
        } else {
            estimate = typical ?? I18n.t("queue.soon")
        }
        if let typical = typical, estimate != typical { return (estimate, typical) }
        return (estimate, "")
    }

    /// handover-waiting: nobody could take the chat (the AI took it back).
    public static func handoverWaiting(_ raw: [String: Any]?) -> HandoverWaiting? {
        guard let raw = raw else { return nil }
        return HandoverWaiting(
            offline: raw["offline"] as? Bool == true,
            reason: raw["reason"] as? String == "offline" ? "offline" : "busy",
            backAt: raw["backAt"] as? String,
            askEmail: raw["askEmail"] as? Bool == true,
            email: str(raw["email"])
        )
    }

    /// The line on that card.
    public static func handoverWaitingLine(_ w: HandoverWaiting, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let back = backAtLabel(w.backAt, now: now, timeZone: timeZone)
        let first = !w.offline ? I18n.t("sdk.waiting.busy")
            : back.map { I18n.t("sdk.waiting.offlineBack", ["when": $0]) } ?? I18n.t("sdk.waiting.offline")
        let second = w.email.map { I18n.t("sdk.waiting.replyTo", ["email": $0]) } ?? I18n.t("sdk.waiting.leaveEmail")
        return "\(first) \(second)"
    }

    /// An agent message sent in the visitor's language: the original kept.
    public static func agentTranslation(_ data: [String: Any]?) -> AgentTranslation? {
        guard let t = data?["translation"] as? [String: Any],
              let original = t["original"] as? String,
              let to = t["to"] as? String,
              !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return AgentTranslation(from: t["from"] as? String ?? "", to: to, original: original)
    }

    public static func receiptMarks(_ raw: [String: Any]?) -> ReceiptMarks {
        ReceiptMarks(deliveredMessageId: raw?["deliveredMessageId"] as? String ?? "",
                     seenMessageId: raw?["seenMessageId"] as? String ?? "")
    }

    private static let visitorKinds: Set<String> = ["user-live-message", "user-live-message-file"]
    private static let agentKinds: Set<String> = ["agent-message", "agent-message-file", "agent-message-audio", "agent-message-rich"]

    /// The line under the visitor's latest live message while it is the newest
    /// thing in the chat (an agent reply takes it away), or nil. Only while a
    /// person is on the other end - an AI answers at once.
    public static func visitorReceipt(_ record: [LiveEntry], marks: ReceiptMarks) -> VisitorReceipt? {
        for i in record.indices.reversed() {
            let r = record[i]
            if agentKinds.contains(r.kind) { return nil }
            if visitorKinds.contains(r.kind) {
                if r.id.isEmpty { return nil }
                let seenAt = marks.seenMessageId.isEmpty ? -1 : (record.firstIndex { $0.id == marks.seenMessageId } ?? -1)
                let deliveredAt = marks.deliveredMessageId.isEmpty ? -1 : (record.firstIndex { $0.id == marks.deliveredMessageId } ?? -1)
                let state: ReceiptState = seenAt >= i ? .seen : (deliveredAt >= i ? .delivered : .sent)
                return VisitorReceipt(id: r.id, state: state)
            }
        }
        return nil
    }

    public static func receiptLabel(_ state: ReceiptState) -> String {
        switch state {
        case .seen: return I18n.t("receipt.seen")
        case .delivered: return I18n.t("receipt.delivered")
        case .sent: return I18n.t("receipt.sent")
        }
    }

    /// The newest agent message id: what the visitor reports delivered / seen.
    public static func latestAgentMessageId(_ record: [LiveEntry]) -> String {
        record.last { agentKinds.contains($0.kind) }?.id ?? ""
    }

    public static func isEmail(_ v: String?) -> Bool {
        let s = (v ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$", options: .regularExpression) != nil
    }

    /// "9:00 AM" (same day) or "Friday 9:00 AM" from an ISO time; nil when unknown.
    public static func backAtLabel(_ iso: String?, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard let iso = iso, let date = parseISO(iso) else { return nil }
        // In the widget's language (English keeps the phone's own format).
        let locale: Locale? = I18n.isEnglish ? nil : I18n.locale
        let time = DateFormatter()
        if let locale = locale { time.locale = locale }
        time.timeZone = timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        if cal.isDate(date, inSameDayAs: now) { return time.string(from: date) }
        let day = DateFormatter()
        if let locale = locale { day.locale = locale }
        day.timeZone = timeZone
        day.dateFormat = "EEEE"
        return "\(day.string(from: date)) \(time.string(from: date))"
    }

    private static func parseISO(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }

    /// Visitor uploads in a live chat: on unless the owner turned them off.
    public static func visitorUploadsOn(_ customizations: [String: Any]?) -> Bool {
        (customizations?["enableVisitorFileUpload"] as? Bool) != false
    }

    public static func csatConfig(_ raw: [String: Any]?) -> CsatConfig? {
        guard let raw = raw, raw["enabled"] as? Bool == true else { return nil }
        let types: Set<String> = ["stars", "thumbs", "emoji", "nps"]
        let type = (raw["ratingType"] as? String).flatMap { types.contains($0) ? $0 : nil } ?? "stars"
        // The owner's words, else the web's (postChatRating.ts csat.*) in the
        // visitor's language; a stock English value shows translated too.
        func s(_ key: String, _ i18nKey: String, _ stock: [String] = []) -> String {
            I18n.ownerTextOr(str(raw[key]), i18nKey, stockEnglish: stock)
        }
        return CsatConfig(
            ratingType: type,
            titleText: s("titleText", "csat.title"),
            subtitleText: s("subtitleText", "csat.subtitle"),
            thankYouText: s("thankYouText", "csat.thanks"),
            showFeedbackInput: (raw["showFeedbackInput"] as? Bool) != false,
            feedbackPlaceholder: s("feedbackPlaceholder", "csat.placeholder", ["Tell us more..."])
        )
    }

    /// submit-chat-rating payload for a rating of the given type (value: Int, or Bool for thumbs).
    public static func ratingPayload(chatSessionId: String, type: String, value: Any, feedback: String? = nil) -> [String: Any] {
        var out: [String: Any] = ["chatSessionId": chatSessionId, "source": "post_chat_survey"]
        switch type {
        case "thumbs": out["thumbsUp"] = (value as? Bool) == true
        case "nps": out["npsScore"] = int(value) ?? 0
        default: out["csatScore"] = int(value) ?? 0
        }
        if let f = feedback?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            out["feedback"] = String(f.prefix(1000))
        }
        return out
    }

    /// The handover step's own survey as submit-chat-rating (the server has
    /// no handover:survey): thumbs up is 1, numbers are an NPS 0-10, stars
    /// and emojis a 1-5 score. nil when there is no rating to send (#59).
    public static func surveyRatingPayload(chatSessionId: String, style: String?, response: [String: Any]?) -> [String: Any]? {
        guard !chatSessionId.isEmpty, let rating = int(response?["rating"]) else { return nil }
        let feedback = (response?["feedback"] as? String) ?? (response?["comment"] as? String)
        switch style {
        case "thumbs": return ratingPayload(chatSessionId: chatSessionId, type: "thumbs", value: rating == 1, feedback: feedback)
        case "numbers": return ratingPayload(chatSessionId: chatSessionId, type: "nps", value: rating, feedback: feedback)
        default: return ratingPayload(chatSessionId: chatSessionId, type: "stars", value: rating, feedback: feedback)
        }
    }

    // "See original" / "See translation" in the visitor's language (the web
    // widget's list, ts/chat/translatedMessage.ts).
    private static let translationLabels: [String: (String, String)] = [
        "en": ("See original", "See translation"),
        "es": ("Ver original", "Ver traducción"),
        "fr": ("Voir l'original", "Voir la traduction"),
        "de": ("Original anzeigen", "Übersetzung anzeigen"),
        "pt": ("Ver original", "Ver tradução"),
        "it": ("Vedi originale", "Vedi traduzione"),
        "nl": ("Origineel bekijken", "Vertaling bekijken"),
        "pl": ("Zobacz oryginał", "Zobacz tłumaczenie"),
        "tr": ("Orijinali gör", "Çeviriyi gör"),
        "ru": ("Показать оригинал", "Показать перевод"),
        "uk": ("Показати оригінал", "Показати переклад"),
        "ar": ("عرض النص الأصلي", "عرض الترجمة"),
        "hi": ("मूल देखें", "अनुवाद देखें"),
        "ja": ("原文を表示", "翻訳を表示"),
        "ko": ("원문 보기", "번역 보기"),
        "zh": ("查看原文", "查看翻译"),
        "id": ("Lihat asli", "Lihat terjemahan"),
        "vi": ("Xem bản gốc", "Xem bản dịch"),
        "th": ("ดูต้นฉบับ", "ดูคำแปล"),
        "sv": ("Visa original", "Visa översättning"),
    ]

    public static func translationLabels(_ lang: String?) -> (String, String) {
        let key = (lang ?? "").lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return translationLabels[key] ?? translationLabels["en"]!
    }

    /// A file URL ready to open: the relative /media proxy on the API origin; never script / data URLs.
    public static func resolveMediaURL(_ url: String?, origin: String) -> URL? {
        let raw = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        let bare = raw.replacingOccurrences(of: "\\s", with: "", options: .regularExpression).lowercased()
        if bare.hasPrefix("javascript:") || bare.hasPrefix("vbscript:") || bare.hasPrefix("data:") { return nil }
        if raw.hasPrefix("/") {
            var o = origin
            while o.hasSuffix("/") { o.removeLast() }
            return URL(string: o + raw)
        }
        return URL(string: raw)
    }

    public static func isImageURL(_ url: String?, mimeType: String? = nil) -> Bool {
        if (mimeType ?? "").hasPrefix("image/") { return true }
        return (url ?? "").range(of: "\\.(png|jpe?g|gif|webp|heic|bmp)(\\?|#|$)", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The name on a file row: the record's own, or the URL's last part.
    public static func fileName(_ own: String?, url: String) -> String {
        if let own = own?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty { return own }
        let path = url.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? url
        let last = path.components(separatedBy: "/").last ?? ""
        let decoded = last.removingPercentEncoding ?? last
        return decoded.isEmpty ? I18n.t("file.file") : decoded
    }

    /// The builder's rich text as plain text (<p>...</p>, <br>, entities).
    public static func plainText(_ html: String) -> String {
        var t = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (k, v) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// handover-timeout, sent once the handover step's max wait passes with
    /// nobody joined: the server then decides (no-agents-available), as the
    /// web widget's maxWaitTimer does.
    public static func handoverTimeoutPayload(chatSessionId: String, nodeData: [String: Any]?, workspaceId: String?) -> [String: Any] {
        var assignment: [String: Any] = [:]
        assignment["assignmentType"] = nodeData?["assignmentType"]
        assignment["assignmentStrategy"] = nodeData?["agentAssignmentStrategy"]
        assignment["assignedAgents"] = nodeData?["assignedAgents"]
        var out: [String: Any] = ["chatSessionId": chatSessionId, "assignmentData": assignment]
        out["workspaceId"] = workspaceId
        return out
    }

    /// The max wait in seconds (minutes as the builder wrote them).
    public static func waitSeconds(_ v: Any?) -> Double {
        let m = waitMinutes(v)
        return ((m as? Double) ?? Double((m as? Int) ?? 2)) * 60
    }

    /// Minutes, as the builder wrote them: half a minute is 0.5, not 2 (the default).
    public static func waitMinutes(_ v: Any?) -> Any {
        if let i = v as? Int { return i }
        if let d = v as? Double { return d.truncatingRemainder(dividingBy: 1) == 0 ? Int(d) as Any : d as Any }
        if let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), let d = Double(s), d > 0 {
            return d.truncatingRemainder(dividingBy: 1) == 0 ? Int(d) as Any : d as Any
        }
        return 2
    }
}
