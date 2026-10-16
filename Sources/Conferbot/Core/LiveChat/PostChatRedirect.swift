//
//  PostChatRedirect.swift
//  Conferbot
//
//  Post-chat redirect (Customize > Conversations > Post-chat redirect, the
//  bot's redirectUrl), ported from React Native's core/postChatRedirect.ts
//  and the web widget's ts/chat/postChatRedirect.ts
//  (docs/redirect-after-chat.md). When a conversation ends - the flow
//  reaches its end, or an agent ends a chat they took over - and the
//  post-chat rating is sent or put away (or there is none), a quiet line
//  counts down 10 seconds with Cancel, then the owner's URL opens outside
//  the chat.
//
//    - only http(s) URLs with a host: javascript:, data:, mailto:, a bare
//      domain and anything with a user:password@ part are ignored
//    - the app's `onPostChatRedirect(url)` is asked first: true means the
//      app handled it (or wants none), and no countdown is shown
//    - once per conversation: remembered when the countdown starts, so a
//      cancelled one, an agent ending the chat again or a restored ended
//      chat does not count down a second time
//    - it stops on Cancel, a new conversation, the chat closed, a block, a
//      person back in it, the app in the background
//    - when the system cannot open it, the line becomes "Continue to
//      example.com" the visitor can tap
//
//  Owned by ConferBot (`conferBot.postChatRedirect`); no UIKit here (it
//  builds on Linux too). ConferBot opens the URL with UIApplication.shared.open.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

public enum PostChatRedirect {
    /// Seconds the line counts down.
    public static let seconds = 10
    /// The rating shows 1.5 s after the end (web index.ts); the line waits for it.
    public static let settleSeconds: TimeInterval = 1.5
    /// The device remembers an offered conversation under this + chatSessionId.
    public static let doneKeyPrefix = "conferbot_redirect_done_"
    static let maxURLLength = 2048

    private struct Parts { let scheme: String; let host: String; let port: String; let rest: String }

    private static func matches(_ pattern: String, _ s: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: s) else { return "" }
            return String(s[range])
        }
    }

    // A host may not hold these (WHATWG forbidden host code points).
    private static let forbiddenHost = "[\\s#%/:<>?@\\[\\\\\\]^|\\x00-\\x1f\\x7f]"

    private static func parse(_ href: String) -> Parts? {
        guard let m = matches("^(https?)://([^/?#\\\\]*)([\\s\\S]*)$", href, options: [.caseInsensitive]) else { return nil }
        let scheme = m[1].lowercased()
        let authority = m[2]
        // A user:password@ (or any user@) part.
        if authority.contains("@") { return nil }
        var host = authority
        var port = ""
        if let v6 = matches("^(\\[[0-9a-fA-F:.]+\\])(?::(\\d*))?$", authority) {
            host = v6[1]
            port = v6[2]
        } else {
            if let at = authority.lastIndex(of: ":") {
                port = String(authority[authority.index(after: at)...])
                host = String(authority[..<at])
                if matches("^\\d*$", port) == nil { return nil }
            }
            if host.isEmpty || matches(forbiddenHost, host) != nil || matches("^\\.+$", host) != nil { return nil }
        }
        if !port.isEmpty, (Int(port) ?? Int.max) > 65535 { return nil }
        host = host.lowercased()
        while port.count > 1 && port.hasPrefix("0") { port.removeFirst() }
        if port == (scheme == "http" ? "80" : "443") { port = "" }
        // The path, query and fragment as a browser writes them.
        var rest = m[3].replacingOccurrences(of: "\\", with: "/").replacingOccurrences(of: " ", with: "%20")
        rest = String(String.UnicodeScalarView(rest.unicodeScalars.filter { $0.value > 0x1f && $0.value != 0x7f }))
        if !rest.hasPrefix("/") { rest = "/" + rest }
        return Parts(scheme: scheme, host: host, port: port, rest: rest)
    }

    /// The owner's URL when it is a plain http(s) address, else nil.
    public static func safeURL(_ raw: Any?) -> String? {
        guard let s = raw as? String else { return nil }
        let value = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maxURLLength, let u = parse(value) else { return nil }
        return "\(u.scheme)://\(u.host)\(u.port.isEmpty ? "" : ":\(u.port)")\(u.rest)"
    }

    /// "www.example.com" -> "example.com", for the line the visitor reads.
    public static func host(_ href: String) -> String {
        guard let u = parse(href.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "" }
        return u.host.hasPrefix("www.") ? String(u.host.dropFirst(4)) : u.host
    }

    /// This conversation already counted down (or was cancelled, or the app took it).
    public static func alreadyOffered(_ chatSessionId: String, store: RedirectStore?) -> Bool {
        guard !chatSessionId.isEmpty, let store = store else { return false }
        return store.read(doneKeyPrefix + chatSessionId) == "1"
    }
}

/// Where an offered conversation is remembered.
public protocol RedirectStore: AnyObject {
    func read(_ key: String) -> String?
    func write(_ key: String, _ value: String)
}

/// The device's UserDefaults (the web's localStorage).
public final class UserDefaultsRedirectStore: RedirectStore {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func read(_ key: String) -> String? { defaults.string(forKey: key) }
    public func write(_ key: String, _ value: String) { defaults.set(value, forKey: key) }
}

/// The line under the conversation.
public struct RedirectLine: Equatable {
    public enum Phase: Equatable {
        /// "Taking you to x in Ns" with Cancel.
        case counting
        /// "Taking you to x…": it opened.
        case going
        /// "Continue to x": the system could not open it, the visitor can.
        case continueLink
    }
    public let href: String
    public let host: String
    public var phase: Phase
    public var secondsLeft: Int
    /// What the line shows now.
    public var text: String
    /// What a screen reader hears: the first sentence, said once (not every tick).
    public var said: String
    /// The Cancel button's text and its accessible label.
    public let cancelText: String
    public let cancelLabel: String
}

/// One per chat: when to start, the countdown, the conversations already
/// offered, the line.
public final class PostChatRedirectController: ObservableObject {
    public enum Start: Equatable { case none, handled, counting }

    struct Hooks {
        /// The bot's redirectUrl (fetched-chatbot-data).
        var redirectUrl: () -> Any?
        var sessionId: () -> String?
        /// The chat is on screen.
        var chatVisible: () -> Bool
        /// The workspace blocked this visitor.
        var blocked: () -> Bool
        /// A person (or a handover) is in the conversation.
        var live: () -> Bool
        /// The post-chat rating is up and not answered yet.
        var ratingPending: () -> Bool
        /// Opens the URL outside the chat; done(false) when the system refused.
        var open: (_ href: String, _ done: @escaping (Bool) -> Void) -> Void
        /// The app's config: never redirect.
        var disabled: () -> Bool = { false }
        /// The app's hook, asked first: true = handled, no countdown.
        var onPostChatRedirect: () -> ((String) -> Bool)? = { nil }
        var store: () -> RedirectStore? = { nil }
        var appInForeground: () -> Bool = { true }
    }

    @Published public private(set) var line: RedirectLine?

    private let hooks: Hooks
    private let schedule: ConnectingSignal.Schedule
    private let countdown: Int
    private var offeredHere = Set<String>()
    // One try per end, as the web's _afterPostChat (an offered conversation
    // is never offered again: offeredHere and the store).
    private var tried = Set<String>()
    private var ended: String?
    private var active: String?
    private var tick: SignalTimer?
    private var settle: SignalTimer?

    init(hooks: Hooks, seconds: Int = PostChatRedirect.seconds, schedule: @escaping ConnectingSignal.Schedule = ConnectingSignal.mainQueueTimer) {
        self.hooks = hooks
        self.countdown = max(1, seconds)
        self.schedule = schedule
    }

    /// The conversation the countdown (or the line) is for.
    public var activeSession: String? { active }

    private func canGo(_ session: String) -> Bool {
        ended == session && (hooks.sessionId() ?? "") == session && hooks.chatVisible()
            && !hooks.blocked() && !hooks.live() && hooks.appInForeground()
    }

    /// The conversation on screen ended (the flow's end, an agent ending it).
    public func conversationEnded() {
        let session = hooks.sessionId() ?? ""
        guard !session.isEmpty else { return }
        ended = session
        tried.remove(session)
        settle?.cancel()
        settle = nil
        update()
    }

    /// Anything the chat shows changed: wait for the rating, try once after
    /// the settle; a countdown that can no longer go stops.
    public func update() {
        if let a = active, !canGo(a) { cancel() }
        guard let e = ended else { return }
        if (hooks.sessionId() ?? "") != e {
            ended = nil
            settle?.cancel()
            settle = nil
            return
        }
        guard !tried.contains(e) else { return }
        if hooks.ratingPending() {
            settle?.cancel()
            settle = nil
            return
        }
        guard settle == nil else { return }
        settle = schedule(PostChatRedirect.settleSeconds) { [weak self] in
            guard let self = self else { return }
            self.settle = nil
            guard self.ended == e, !self.hooks.ratingPending() else { return }
            self.tried.insert(e)
            _ = self.start(e)
        }
    }

    /// The app's hook, else the countdown. none when there is nothing to do
    /// (no valid URL, turned off, already offered, not on screen).
    @discardableResult
    public func start(_ session: String) -> Start {
        guard let href = PostChatRedirect.safeURL(hooks.redirectUrl()), !hooks.disabled() else { return .none }
        guard !offeredHere.contains(session), active == nil else { return .none }
        let store = hooks.store()
        if PostChatRedirect.alreadyOffered(session, store: store) {
            offeredHere.insert(session)
            return .none
        }
        guard canGo(session) else { return .none }
        offeredHere.insert(session)
        if !session.isEmpty { store?.write(PostChatRedirect.doneKeyPrefix + session, "1") }

        if let hook = hooks.onPostChatRedirect(), hook(href) { return .handled }

        let host = PostChatRedirect.host(href)
        let first = I18n.t("redirect.countdown", ["host": host, "n": countdown])
        active = session
        line = RedirectLine(
            href: href, host: host, phase: .counting, secondsLeft: countdown,
            text: first, said: first,
            cancelText: I18n.t("common.cancel"),
            cancelLabel: I18n.t("redirect.cancel", ["host": host])
        )
        scheduleTick(session, left: countdown)
        return .counting
    }

    private func scheduleTick(_ session: String, left: Int) {
        tick = schedule(1) { [weak self] in
            guard let self = self, self.active == session, var l = self.line else { return }
            guard self.canGo(session) else { return self.cancel() }
            let now = left - 1
            if now > 0 {
                l.secondsLeft = now
                l.text = I18n.t("redirect.countdown", ["host": l.host, "n": now])
                self.line = l
                return self.scheduleTick(session, left: now)
            }
            self.tick = nil
            self.go(l, session)
        }
    }

    private func go(_ l: RedirectLine, _ session: String) {
        hooks.open(l.href) { [weak self] opened in
            guard let self = self, self.active == session, var line = self.line else { return }
            let text = opened ? I18n.t("redirect.going", ["host": l.host]) : I18n.t("redirect.continue", ["host": l.host])
            line.phase = opened ? .going : .continueLink
            line.secondsLeft = 0
            line.text = text
            line.said = text
            self.line = line
        }
    }

    /// "Continue to example.com" tapped: open it now.
    public func continueNow(_ done: @escaping (Bool) -> Void = { _ in }) {
        guard let l = line, l.phase == .continueLink else { return done(false) }
        hooks.open(l.href) { [weak self] opened in
            if opened, self?.line == l { self?.cancel() }
            done(opened)
        }
    }

    /// Stop a countdown and take the line away (Cancel, a restart, the chat
    /// closed, the app in the background).
    public func cancel() {
        tick?.cancel()
        tick = nil
        active = nil
        if line != nil { line = nil }
    }

    /// A restart: the countdown stops and the next conversation gets its own.
    public func reset() {
        cancel()
        settle?.cancel()
        settle = nil
        ended = nil
    }
}
