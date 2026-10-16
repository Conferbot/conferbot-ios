//
//  AutoOpen.swift
//  Conferbot
//
//  Auto-open: the owner's botAutoOpen / botAutoOpenDelay (seconds) open the
//  chat on its own, for a first visit only. Ported from the React Native SDK
//  (src/core/autoOpen.ts), itself from conferbot-widget src/index.ts (the
//  live_chat / popup_chat auto-open, ~2003-2070) and
//  src/core/customizations.ts (autoOpen, autoOpenDelay):
//
//    - only while the visitor has not started a chat (a conversation they
//      already have is theirs to reopen: web `!chatStarted`);
//    - not when they closed the chat in the last 2 minutes (the web's
//      isChatOpen=false cookie lasts 120 s);
//    - once per launch of the app (the web: once per page load);
//    - when the delay is up and the chat is already open, nothing.
//
//  Pure, plus the app-launch memory (`AutoOpen.Memory`) the floating
//  launcher keeps per bot.
//

import Foundation

public enum AutoOpen {

    /// A close blocks auto-open this long (web: the isChatOpen cookie's 2 minutes).
    public static let closedBlocksMs: Double = 120_000

    /// The owner's delay in milliseconds (unset, junk or negative: at once).
    public static func delayMs(_ c: [String: Any]?) -> Double {
        let s = JS.toNumber(c?["botAutoOpenDelay"] ?? NSNull())
        return s.isFinite && s > 0 ? (s * 1000).rounded() : 0
    }

    /// In how many ms to open the chat, or nil for not at all.
    public static func plan(_ c: [String: Any]?, chatStarted: Bool, isOpen: Bool, alreadyAutoOpened: Bool,
                            closedAt: Double? = nil, now: Double = Date().timeIntervalSince1970 * 1000) -> Double? {
        guard let c = c, JS.truthy(c["botAutoOpen"]), !chatStarted, !isOpen, !alreadyAutoOpened else { return nil }
        if let closedAt = closedAt, closedAt > 0, now - closedAt < closedBlocksMs { return nil }
        return delayMs(c)
    }

    /// What this launch of the app remembers, per bot: auto-opened already,
    /// and when the chat was last closed.
    public enum Memory {
        private static var opened: Set<String> = []
        private static var closed: [String: Double] = [:]
        private static let lock = NSLock()

        public static func autoOpened(_ botId: String) -> Bool { lock.lock(); defer { lock.unlock() }; return opened.contains(botId) }
        public static func noteAutoOpened(_ botId: String) { lock.lock(); opened.insert(botId); lock.unlock() }
        public static func closedAt(_ botId: String) -> Double? { lock.lock(); defer { lock.unlock() }; return closed[botId] }
        public static func noteClosed(_ botId: String, at: Double = Date().timeIntervalSince1970 * 1000) {
            lock.lock(); closed[botId] = at; lock.unlock()
        }
        /// Tests only.
        static func reset() { lock.lock(); opened = []; closed = [:]; lock.unlock() }
    }
}
