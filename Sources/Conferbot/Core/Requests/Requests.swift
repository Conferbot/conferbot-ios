//
//  Requests.swift
//  Conferbot
//
//  "Your requests" (web conferbot-widget src/ts/home/requests/; ported from
//  the React Native SDK's src/core/requests.ts): a visitor's own
//  conversations with the team, where each one stands in plain words, and a
//  reply box that reaches the team. A reply to a solved request opens it
//  again.
//
//  Pure: the words (web words.ts), what the device remembers (web store.ts,
//  as values in and out; YourRequests keeps them in UserDefaults), which
//  visitor is asking (web api.ts `who`) and the socket calls with an answer
//  (web api.ts, embed-server socket/handlers/visitorRequestsHandler.js and
//  services/chatbot/visitorRequests.js). The screens are RequestsPortal.swift.
//
//  Whose requests: the server lists a conversation only when its id is one
//  this device started AND its visitor id matches (the ids are random and
//  shown nowhere else), or when the app signed its user in (`hash`, identity
//  verification) - then their verified conversations on this bot from any
//  device. Only conversations a person on the team handles are requests; a
//  chat the AI answered alone is not one.
//
//  English only for now (the web's i18n `requests.*`, `when.*` keys).
//

import Foundation

// MARK: - Types

/// As the server sends them (visitorRequests.js `summary`).
public struct RequestSummary: Equatable, Identifiable {
    public enum Status: String { case open, solved }
    public enum From: String { case you, team }

    public var id: String
    public var title: String
    public var status: Status
    public var startedAt: String?
    public var lastAt: String?
    public var lastFrom: From
    public var lastText: String
    public var teamName: String

    public init(id: String, title: String, status: Status = .open, startedAt: String? = nil, lastAt: String? = nil,
                lastFrom: From = .you, lastText: String = "", teamName: String = "") {
        self.id = id
        self.title = title
        self.status = status
        self.startedAt = startedAt
        self.lastAt = lastAt
        self.lastFrom = lastFrom
        self.lastText = lastText
        self.teamName = teamName
    }

    /// One from the server's JSON; nil without an id.
    public init?(json: Any?) {
        guard let d = json as? [String: Any], let id = d["id"] as? String, !id.isEmpty else { return nil }
        self.init(
            id: id,
            title: d["title"] as? String ?? "",
            status: (d["status"] as? String) == "solved" ? .solved : .open,
            startedAt: Requests.timeString(d["startedAt"]),
            lastAt: Requests.timeString(d["lastAt"]),
            lastFrom: (d["lastFrom"] as? String) == "team" ? .team : .you,
            lastText: d["lastText"] as? String ?? "",
            teamName: d["teamName"] as? String ?? ""
        )
    }
}

/// visitorRequests.js `messagesOf`.
public struct RequestMessage: Equatable, Identifiable {
    public var id: String
    public var from: RequestSummary.From
    public var name: String
    public var text: String
    public var at: String?

    public init(id: String, from: RequestSummary.From, name: String = "", text: String, at: String? = nil) {
        self.id = id
        self.from = from
        self.name = name
        self.text = text
        self.at = at
    }

    public init?(json: Any?) {
        guard let d = json as? [String: Any] else { return nil }
        self.init(
            id: (d["id"] as? String) ?? (d["id"].map { "\($0)" } ?? ""),
            from: (d["from"] as? String) == "team" ? .team : .you,
            name: d["name"] as? String ?? "",
            text: d["text"] as? String ?? "",
            at: Requests.timeString(d["at"])
        )
    }
}

public struct RequestDetail: Equatable, Identifiable {
    public var summary: RequestSummary
    public var messages: [RequestMessage]
    public var id: String { summary.id }

    public init(summary: RequestSummary, messages: [RequestMessage]) {
        self.summary = summary
        self.messages = messages
    }

    public init?(json: Any?) {
        guard let s = RequestSummary(json: json) else { return nil }
        let list = (json as? [String: Any])?["messages"] as? [Any] ?? []
        self.init(summary: s, messages: list.compactMap { RequestMessage(json: $0) })
    }
}

public enum RequestState: String { case replied, waiting, solved }

/// What a reply came back with: ok and the request, or the server's reason
/// (locked, not_found, empty, error; no answer is offline).
public struct ReplyResult: Equatable {
    public var ok: Bool
    public var request: RequestDetail?
    public var reason: String?

    public init(ok: Bool, request: RequestDetail? = nil, reason: String? = nil) {
        self.ok = ok
        self.request = request
        self.reason = reason
    }
}

// MARK: - What the device remembers

/// The ids of the chats this device started (newest first) and when each request was last read here.
public struct RequestMemory: Equatable {
    public var sessions: [String]
    /// Request id -> when it was last read here (ms).
    public var seen: [String: Double]
    /// The read marks' order, oldest first (JS objects keep insertion order; the newest 60 are kept).
    var seenOrder: [String]

    public init(sessions: [String] = [], seen: [String: Double] = [:]) {
        self.sessions = sessions
        self.seen = seen
        self.seenOrder = seen.keys.sorted { (seen[$0] ?? 0, $0) < (seen[$1] ?? 0, $1) }
    }

    public static func == (a: RequestMemory, b: RequestMemory) -> Bool { a.sessions == b.sessions && a.seen == b.seen }
}

/// The app's signed-in user, as the server checks it (ConferBotUser).
public struct RequestsUser: Equatable {
    public var id: String?
    public var email: String?
    public var hash: String?

    public init(id: String? = nil, email: String? = nil, hash: String? = nil) {
        self.id = id
        self.email = email
        self.hash = hash
    }
}

/// Every call says which visitor this is (web api.ts `who`).
public struct RequestsWho: Equatable {
    public var visitorId: String
    public var sessions: [String]
    public var user: RequestsUser?

    public var payload: [String: Any] {
        var out: [String: Any] = ["visitorId": visitorId, "sessions": sessions]
        if let u = user {
            var d: [String: Any] = [:]
            if let v = u.id { d["id"] = v }
            if let v = u.email { d["email"] = v }
            if let v = u.hash { d["hash"] = v }
            out["user"] = d
        }
        return out
    }
}

// MARK: - The socket

/// What the SDK's socket offers the calls (closures, so tests need no socket).
public struct RequestsSocket {
    /// Emit and hand back the first ack item, or nil when offline / after the timeout (seconds).
    public var emitWithAck: (_ event: String, _ data: [String: Any], _ timeout: Double, _ done: @escaping (Any?) -> Void) -> Void
    public var emit: (_ event: String, _ data: [String: Any]) -> Void
    /// Listen; returns the unsubscribe. `connect` is the socket's local event on every (re)connect.
    public var on: (_ event: String, _ listener: @escaping (Any?) -> Void) -> () -> Void

    public init(emitWithAck: @escaping (String, [String: Any], Double, @escaping (Any?) -> Void) -> Void,
                emit: @escaping (String, [String: Any]) -> Void,
                on: @escaping (String, @escaping (Any?) -> Void) -> () -> Void) {
        self.emitWithAck = emitWithAck
        self.emit = emit
        self.on = on
    }
}

/// The calls (web api.ts requestsApi).
public struct RequestsApi {
    public var list: () async -> [RequestSummary]?
    public var open: (_ id: String) async -> RequestDetail?
    /// No more live updates for it.
    public var close: (_ id: String) -> Void
    public var reply: (_ id: String, _ text: String, _ entryId: String) async -> ReplyResult
    /// A request changed on the server (a team reply, solved). Returns the unsubscribe.
    public var onUpdate: (_ listener: @escaping (String) -> Void) -> () -> Void

    public init(list: @escaping () async -> [RequestSummary]?,
                open: @escaping (String) async -> RequestDetail?,
                close: @escaping (String) -> Void,
                reply: @escaping (String, String, String) async -> ReplyResult,
                onUpdate: @escaping (@escaping (String) -> Void) -> () -> Void) {
        self.list = list
        self.open = open
        self.close = close
        self.reply = reply
        self.onUpdate = onUpdate
    }
}

/// A few listeners per event, each with its own unsubscribe (SocketClient's
/// `off` drops every listener of an event). ConferBot feeds it.
public final class RequestsEventHub {
    private var listeners: [String: [(Int, (Any?) -> Void)]] = [:]
    private var seq = 0
    private let lock = NSLock()

    public init() {}

    public func on(_ event: String, _ fn: @escaping (Any?) -> Void) -> () -> Void {
        lock.lock()
        seq += 1
        let n = seq
        listeners[event, default: []].append((n, fn))
        lock.unlock()
        return { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.listeners[event]?.removeAll { $0.0 == n }
            self.lock.unlock()
        }
    }

    public func fire(_ event: String, _ data: Any? = nil) {
        lock.lock()
        let fns = (listeners[event] ?? []).map { $0.1 }
        lock.unlock()
        fns.forEach { $0(data) }
    }
}

// MARK: - Requests

public enum Requests {

    // MARK: The words

    /// The web's English strings (i18n en `requests.*`, `common.*`, `transcript.you`).
    public enum Text {
        public static let title = "Your requests"
        public static let one = "Your request"
        public static let back = "Back"
        public static let loading = "Loading..."
        public static let loadFailed = "We couldn't load this just now."
        public static let tryAgain = "Try again"
        public static let empty = "Nothing here yet. When you ask us something, you can follow it here."
        public static let you = "You"
        public static let supportTeam = "Support team"
        public static let replyPlaceholder = "Write your reply..."
        public static let reopenPlaceholder = "Write here to open it again..."
        public static let yourReply = "Your reply"
        public static let send = "Send"
        public static let sending = "Sending..."
        public static let notSent = "Not sent."
        public static let locked = "This conversation is closed for replies."
        public static let newReply = "New reply"
        public static func newReplyFrom(_ name: String) -> String { "New reply from \(name)" }
        public static func seeAll(_ n: Int) -> String { "See all (\(n))" }
        /// The chat menu's item (the web has the home card instead).
        public static func menu(_ unread: Int) -> String { unread > 0 ? "\(title) · \(newReply)" : title }
    }

    /// Each state in a few plain words, never a ticket status (web words.ts STATE_WORDS).
    public static func stateWords(_ s: RequestState) -> (label: String, detail: String) {
        switch s {
        case .replied: return ("We replied", "Read it below. If you need anything else, just write back.")
        case .waiting: return ("We're on it", "We'll reply right here. You can close this - your message is safe with us.")
        case .solved: return ("Solved", "Still need help with this? Write below and we'll pick it up again.")
        }
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    /// A time from the server as text: ISO strings as sent, numbers (ms) as ISO.
    static func timeString(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        if let n = v as? NSNumber, !(v is Bool) { return iso(n.doubleValue) }
        return nil
    }

    static func iso(_ ms: Double) -> String { isoFrac.string(from: Date(timeIntervalSince1970: ms / 1000)) }

    /// Milliseconds, or 0 when it is not a time.
    static func ms(_ v: String?) -> Double {
        guard let s = v?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return 0 }
        if let d = isoFrac.date(from: s) ?? isoPlain.date(from: s) { return d.timeIntervalSince1970 * 1000 }
        if let n = Double(s), n.isFinite { return n }
        return 0
    }

    /// A reply from the team on an open request, not read on this device yet (web isNewReply).
    public static func isNewReply(_ r: RequestSummary, seen: [String: Double]) -> Bool {
        // A solved one is done: its last word is "Solved", not a reply to read.
        r.status != .solved && r.lastFrom == .team && ms(r.lastAt) > (seen[r.id] ?? 0)
    }

    public static func stateOf(_ r: RequestSummary) -> RequestState {
        r.status == .solved ? .solved : r.lastFrom == .team ? .replied : .waiting
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// "Just now", "5 min ago", "3 hours ago", "Yesterday", "Monday", "3 Oct" (web whenWords, English).
    public static func whenWords(_ v: String?, now: Double = Date().timeIntervalSince1970 * 1000, calendar: Calendar = .current) -> String {
        let t = ms(v)
        guard t > 0 else { return "" }
        let diff = max(0, now - t)
        if diff < 60_000 { return "Just now" }
        if diff < 3_600_000 { return "\(Int(diff / 60_000)) min ago" }
        let date = Date(timeIntervalSince1970: t / 1000)
        let today = Date(timeIntervalSince1970: now / 1000)
        let startOfToday = calendar.startOfDay(for: today).timeIntervalSince1970 * 1000
        if t >= startOfToday {
            let h = Int(diff / 3_600_000)
            return h <= 1 ? "1 hour ago" : "\(h) hours ago"
        }
        if t >= startOfToday - 86_400_000 { return "Yesterday" }
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        if t >= startOfToday - 6 * 86_400_000 { return days[(c.weekday ?? 1) - 1] }
        let year = calendar.component(.year, from: today)
        return "\(c.day ?? 1) \(months[(c.month ?? 1) - 1])\(c.year != year ? " \(c.year ?? year)" : "")"
    }

    /// The line under a request's title (web rowLine).
    public static func rowLine(_ r: RequestSummary, seen: [String: Double], now: Double = Date().timeIntervalSince1970 * 1000) -> String {
        let when = whenWords(r.lastAt, now: now)
        let head = isNewReply(r, seen: seen)
            ? (r.teamName.isEmpty ? Text.newReply : Text.newReplyFrom(r.teamName))
            : stateWords(stateOf(r)).label
        return when.isEmpty ? head : "\(head) · \(when)"
    }

    /// Newest replies first, then whatever moved last (web ordered). Stable, as Array.sort in JS.
    public static func ordered(_ list: [RequestSummary], seen: [String: Double]) -> [RequestSummary] {
        list.enumerated().sorted { a, b in
            let na = isNewReply(a.element, seen: seen), nb = isNewReply(b.element, seen: seen)
            if na != nb { return na }
            let ta = ms(a.element.lastAt), tb = ms(b.element.lastAt)
            if ta != tb { return ta > tb }
            return a.offset < b.offset
        }.map { $0.element }
    }

    /// How many requests have a team reply not read here: the app's badge.
    public static func unreadCount(_ list: [RequestSummary]?, seen: [String: Double]) -> Int {
        (list ?? []).filter { isNewReply($0, seen: seen) }.count
    }

    /// Read up to the newest message, by the server's clock too (web view.ts seenAt).
    public static func seenAt(_ lastAt: String?, now: Double) -> Double { max(now, ms(lastAt)) }

    /// The home card shows two; "See all" when there are more (web card.ts ON_HOME).
    public static let onHome = 2
    /// The list is read again at most this often when nothing forces it (web card.ts).
    public static let refreshGapMs: Double = 15000
    /// The reply box's limit (web view.ts maxLength, the server's MAX_REPLY).
    public static let maxReply = 4000

    // MARK: Links in a message

    private static let urlRe = try! NSRegularExpression(pattern: "\\bhttps?://[^\\s<>\"']+[^\\s<>\"'.,;:!?)\\]]", options: [.caseInsensitive])

    /// Text with its links as their own runs, everything else text (web view.ts appendText).
    public static func linkRuns(_ text: String) -> [(text: String, url: String?)] {
        let ns = text as NSString
        var out: [(text: String, url: String?)] = []
        var at = 0
        for m in urlRe.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > at { out.append((ns.substring(with: NSRange(location: at, length: m.range.location - at)), nil)) }
            let url = ns.substring(with: m.range)
            out.append((url, url))
            at = m.range.location + m.range.length
        }
        if at < ns.length { out.append((ns.substring(from: at), nil)) }
        return out
    }

    // MARK: What the device remembers

    public static let maxSessions = 30
    static let seenKept = 60
    /// A conversation id the server accepts (visitorRequests.js SESSION).
    public static func isSessionId(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z0-9_-]{6,64}$", options: .regularExpression) != nil
    }

    /// Per bot, in UserDefaults (the web keeps `cb_req_<botId>` in localStorage).
    public static func storageKey(_ botId: String) -> String { "conferbot_requests_\(botId.isEmpty ? "default" : botId)" }

    /// What was stored, cleaned (web readRequests). Anything unreadable is nothing.
    public static func parseMemory(_ raw: String?) -> RequestMemory {
        guard let data = (raw ?? "").data(using: .utf8),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return RequestMemory() }
        let sessions = ((m["sessions"] as? [Any]) ?? []).compactMap { $0 as? String }.filter(isSessionId).prefix(maxSessions)
        var mem = RequestMemory(sessions: Array(sessions))
        // JSONSerialization loses the order: oldest read first, as they were written.
        let src = (m["seen"] as? [String: Any]) ?? [:]
        let order = (m["seenOrder"] as? [String]) ?? []
        var pairs: [(String, Double)] = []
        for (k, v) in src where isSessionId(k) {
            guard let n = v as? NSNumber, !(v is Bool), n.doubleValue.isFinite else { continue }
            pairs.append((k, n.doubleValue))
        }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        pairs.sort { (rank[$0.0] ?? -1, $0.1, $0.0) < (rank[$1.0] ?? -1, $1.1, $1.0) }
        for (k, v) in pairs {
            mem.seen[k] = v
            mem.seenOrder.append(k)
        }
        return mem
    }

    /// What to store (web store.ts write): 30 sessions, the last 60 read marks.
    public static func serializeMemory(_ m: RequestMemory) -> String {
        let keep = m.seenOrder.filter { m.seen[$0] != nil }.suffix(seenKept)
        var seen: [String: Double] = [:]
        keep.forEach { seen[$0] = m.seen[$0] }
        let obj: [String: Any] = ["sessions": Array(m.sessions.prefix(maxSessions)), "seen": seen, "seenOrder": Array(keep)]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// A chat on this device was saved: it may become a request (web rememberSession). Nil when nothing changes.
    public static func withSession(_ m: RequestMemory, _ session: String?) -> RequestMemory? {
        let s = session ?? ""
        guard isSessionId(s), m.sessions.first != s else { return nil }
        var out = m
        out.sessions = Array(([s] + m.sessions.filter { $0 != s }).prefix(maxSessions))
        return out
    }

    /// They read this request up to `at` (web markSeen). Nil when nothing changes.
    public static func withSeen(_ m: RequestMemory, _ id: String, at: Double) -> RequestMemory? {
        guard !id.isEmpty, (m.seen[id] ?? 0) < at else { return nil }
        var out = m
        // Moved last, so the newest read marks are the ones kept.
        out.seenOrder.removeAll { $0 == id }
        out.seenOrder.append(id)
        out.seen[id] = at
        return out
    }

    /// The visitor wrote in this chat: remember it (web index.ts `_sendResponse`, a `user-` entry in the record).
    public static func hasVisitorEntry(_ record: [[String: Any]]?) -> Bool {
        (record ?? []).contains { e in
            let kind = (e["shape"] as? String) ?? (e["type"] as? String) ?? ""
            return kind.hasPrefix("user-")
        }
    }

    // MARK: Who is asking

    /// Every call says which visitor this is (web api.ts `who`): only what the server checks.
    public static func who(visitorId: String?, memory: RequestMemory, user: RequestsUser?) -> RequestsWho {
        RequestsWho(visitorId: visitorId ?? "", sessions: memory.sessions, user: user)
    }

    /// Nothing on this device and nobody signed in: nothing to ask about (web card.ts refresh).
    public static func canAsk(memory: RequestMemory, user: RequestsUser?) -> Bool {
        !memory.sessions.isEmpty || !(user?.hash ?? "").isEmpty
    }

    // MARK: The server

    /// web api.ts TIMEOUT_MS
    public static let timeoutMs: Double = 10000

    /// The socket events (embed-server visitorRequestsHandler.js).
    public enum Event {
        public static let list = "my-requests"
        public static let open = "my-request-open"
        public static let close = "my-request-close"
        public static let reply = "my-request-reply"
        public static let update = "my-request-update"
    }

    /// The calls (web api.ts requestsApi). `who` is read at each call. The
    /// socket's local `connect` fires on every connect: the server forgets a
    /// request's live updates when the connection drops, so the open one is
    /// read (and joined) again.
    public static func api(socket: RequestsSocket, who: @escaping () -> RequestsWho) -> RequestsApi {
        final class Current { var id: String? }
        let current = Current()
        func call(_ event: String, _ payload: [String: Any]) async -> [String: Any]? {
            await withCheckedContinuation { (k: CheckedContinuation<[String: Any]?, Never>) in
                let once = Once()
                socket.emitWithAck(event, payload, timeoutMs / 1000) { a in
                    if once.take() { k.resume(returning: a as? [String: Any]) }
                }
            }
        }
        return RequestsApi(
            list: {
                let a = await call(Event.list, who().payload)
                guard a?["ok"] as? Bool == true, let list = a?["requests"] as? [Any] else { return nil }
                return list.compactMap { RequestSummary(json: $0) }
            },
            open: { id in
                current.id = id
                var p = who().payload
                p["chatSessionId"] = id
                let a = await call(Event.open, p)
                guard a?["ok"] as? Bool == true else { return nil }
                return RequestDetail(json: a?["request"])
            },
            close: { id in
                if current.id == id { current.id = nil }
                socket.emit(Event.close, ["chatSessionId": id])
            },
            reply: { id, text, entryId in
                var p = who().payload
                p["chatSessionId"] = id
                p["text"] = text
                p["entryId"] = entryId
                guard let a = await call(Event.reply, p) else { return ReplyResult(ok: false, reason: "offline") }
                return ReplyResult(ok: a["ok"] as? Bool == true, request: RequestDetail(json: a["request"]), reason: a["reason"] as? String)
            },
            onUpdate: { fn in
                let offUpdate = socket.on(Event.update) { data in
                    if let id = (data as? [String: Any])?["chatSessionId"] as? String { fn(id) }
                }
                let offConnect = socket.on("connect") { _ in
                    if let id = current.id { fn(id) }
                }
                return {
                    offUpdate()
                    offConnect()
                }
            }
        )
    }

    /// A reply's id, so a retry is one message on the server (web view.ts;
    /// the server accepts `request-reply-[\w-]{1,60}`).
    public static func replyEntryId(now: Double = Date().timeIntervalSince1970 * 1000, rand: () -> Double = { Double.random(in: 0..<1) }) -> String {
        "request-reply-\(String(Int64(now), radix: 36))\(base36Fraction(rand(), digits: 6))"
    }

    /// The first digits of a fraction in base 36 (JS `rand().toString(36).slice(2, 8)`).
    static func base36Fraction(_ x: Double, digits: Int) -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var f = x - x.rounded(.down)
        var out = ""
        for _ in 0..<digits {
            f *= 36
            let d = Int(f.rounded(.down))
            out.append(chars[min(max(d, 0), 35)])
            f -= Double(d)
            if f <= 0 { break }
        }
        return out
    }

    // MARK: The look

    private static func hex(_ v: Any?) -> String? {
        guard let s = (v as? String)?.trimmingCharacters(in: .whitespaces),
              s.range(of: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", options: .regularExpression) != nil else { return nil }
        return s
    }

    private static func lightness(_ h: String) -> Double {
        var s = String(h.dropFirst())
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = [0, 2, 4].map { i -> Double in
            let start = s.index(s.startIndex, offsetBy: i)
            let c = Double(Int(s[start..<s.index(start, offsetBy: 2)], radix: 16) ?? 0) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]
    }

    /// The accent for the Back link, the visitor's bubbles and Send (web
    /// firstImpression.ts accentFor, brand/brand.ts brandColorOf): the brand
    /// colour (not with a theme palette), the header colour, the launcher's,
    /// unless too light to read (luminance over 0.55), then indigo.
    public static func accent(_ c: [String: Any]?) -> String {
        let palette = (c?["_themePalette"] as? Bool) == true || c?["themeAccent"] != nil
        let brand: Any? = (!palette ? hex(c?["brandColor"]) : nil) ?? c?["headerBgColor"]
        let launcher: [Any?]
        if c?["widgetIconThemeType"] as? String == "Gradient", c?["widgetGradientBgOne"] != nil, c?["widgetGradientBgTwo"] != nil {
            launcher = [c?["widgetGradientBgOne"], c?["widgetGradientBgTwo"]]
        } else {
            launcher = [c?["widgetIconBgColor"] ?? c?["headerBgColor"]]
        }
        for v in [brand, c?["headerBgColor"]] + launcher {
            if let h = hex(v), lightness(h) <= 0.55 { return h }
        }
        return "#4F46E5"
    }
}

/// An ack answers once (a late one after the timeout is dropped).
private final class Once {
    private var done = false
    private let lock = NSLock()
    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
