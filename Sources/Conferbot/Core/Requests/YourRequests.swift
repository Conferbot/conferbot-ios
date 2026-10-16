//
//  YourRequests.swift
//  Conferbot
//
//  "Your requests" in the SDK (web conferbot-widget
//  src/ts/home/requests/card.ts mountRequestsCard, store.ts, and index.ts
//  `_sendResponse` rememberSession; ported from the React Native SDK's
//  context/hooks/useRequestsPortal.ts). Holds:
//
//    - what the device remembers: the chats it started that the visitor
//      wrote in, and when each request was last read here, per bot in
//      UserDefaults (Requests.swift);
//    - the list as the home card has it, for the menu item and the app's
//      badge: read when the socket connects, when the chat opens or closes
//      (at most every 15s), when the portal closes, when a user signs in
//      or out (the last user's list dropped), and when a request changes
//      while the portal is closed;
//    - the portal's screens (RequestsPortal.swift).
//
//  Nothing is asked for a visitor with no chat on this device and no
//  signed-in user (`hash`): a first-time visitor has no requests.
//
//  Owned by ConferBot (`conferBot.requests`). Main actor.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

@MainActor
public final class YourRequests: ObservableObject {

    /// What it needs from the SDK (closures, so it can be tested without a socket).
    struct Hooks {
        var socket: RequestsSocket
        var isConnected: () -> Bool
        /// The conversation on screen, and its record (the server's).
        var sessionId: () -> String?
        var record: () -> [[String: Any]]
        /// The signed-in user (identify(user:)).
        var user: () -> RequestsUser?
        /// The visitor id the records carry, else the handshake's.
        var visitorId: () -> String?
        var defaults: UserDefaults = .standard
        var now: () -> Double = { Date().timeIntervalSince1970 * 1000 }
    }

    /// The visitor's requests (newest replies first), nil until read.
    @Published public private(set) var requests: [RequestSummary]?
    /// When each request was last read on this device.
    @Published public private(set) var seen: [String: Double] = [:]
    /// The portal is up.
    @Published public private(set) var isOpen = false

    /// Requests with a team reply not read here: the app's badge.
    public var unread: Int { Requests.unreadCount(requests, seen: seen) }
    /// The chat menu shows "Your requests" once the visitor has one.
    public var hasRequests: Bool { !(requests ?? []).isEmpty }
    /// "Your requests", or "Your requests · New reply" when one is unread.
    public var menuTitle: String { Requests.Text.menu(unread) }

    /// The screens: draw `portal.state`, call its actions.
    public private(set) var portal: RequestsPortal!

    private let hooks: Hooks
    private var api: RequestsApi!
    private var botId = ""
    private var memory = RequestMemory()
    private var lastLoad: Double = 0
    private var loading = false
    /// Bumped on each sign-in or sign-out, so a list read for the last user is dropped (#86).
    private var who = 0
    private var offUpdate: (() -> Void)?
    private var portalSub: AnyCancellable?

    init(hooks: Hooks) {
        self.hooks = hooks
        api = Requests.api(socket: hooks.socket) { [weak self] in
            guard let self = self else { return RequestsWho(visitorId: "", sessions: []) }
            return Requests.who(visitorId: self.hooks.visitorId(), memory: self.memory, user: self.hooks.user())
        }
        portal = RequestsPortal(.init(
            api: api,
            seen: { [weak self] in self?.memory.seen ?? [:] },
            markSeen: { [weak self] id, at in
                guard let self = self else { return }
                self.save(Requests.withSeen(self.memory, id, at: at))
            },
            // The chat on screen, not yet over: that chat instead (web index.ts isCurrentChat).
            isCurrentChat: { [weak self] id in
                guard let self = self else { return false }
                return id == self.hooks.sessionId() && !LiveEvents.endedSinceLastLive(self.hooks.record())
            },
            // The portal sits over the chat: leaving it shows the chat.
            openChat: {},
            onChanged: { [weak self] in Task { @MainActor in await self?.refresh(force: true) } }
        ))
        portalSub = portal.$state.map { $0.screen != .closed }.removeDuplicates().sink { [weak self] open in self?.isOpen = open }
        // A reply arrived while the portal is closed: the list says so.
        offUpdate = api.onUpdate { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.portal.isOpen else { return }
                await self.refresh(force: true)
            }
        }
    }

    deinit { offUpdate?() }

    // MARK: - Memory

    /// What the device remembers for this bot (initialize).
    func load(botId: String) {
        self.botId = botId
        memory = Requests.parseMemory(hooks.defaults.string(forKey: Requests.storageKey(botId)))
        seen = memory.seen
        requests = nil
        lastLoad = 0
    }

    private func save(_ next: RequestMemory?) {
        guard let next = next else { return }
        memory = next
        seen = next.seen
        hooks.defaults.set(Requests.serializeMemory(next), forKey: Requests.storageKey(botId))
    }

    /// The conversation changed: one the visitor wrote in may become a request (web _sendResponse).
    func recordChanged() {
        guard let id = hooks.sessionId(), Requests.hasVisitorEntry(hooks.record()) else { return }
        save(Requests.withSession(memory, id))
    }

    /// The chats this device remembers (newest first).
    public var sessions: [String] { memory.sessions }

    // MARK: - The list

    /// Read the list again: at most every 15s unless forced, only with
    /// something to ask about, only while connected.
    public func refresh(force: Bool = false) async {
        guard !loading, force || hooks.now() - lastLoad >= Requests.refreshGapMs else { return }
        guard Requests.canAsk(memory: memory, user: hooks.user()), hooks.isConnected() else { return }
        loading = true
        lastLoad = hooks.now()
        let asked = who
        let list = await api.list()
        loading = false
        // A list asked for the user before a sign-in or sign-out is not shown.
        if asked == who, let list = list { requests = Requests.ordered(list, seen: memory.seen) }
        // Someone else now: ask again for them.
        if asked != who { await refresh(force: true) }
    }

    /// Someone signed in or out (identify): the list read for the last user
    /// is dropped at once (with the screens and drafts), and read again for
    /// this one; an answer still on its way for the last user is ignored.
    public func userChanged() async {
        who += 1
        requests = nil
        lastLoad = 0
        portal.close()
        portal.reset()
        await refresh(force: true)
    }

    // MARK: - The portal

    /// The list, or one request straight away (Back then leaves).
    public func open(requestId: String? = nil) {
        Task {
            if let id = requestId { await portal.openRequest(id) } else { await portal.openList() }
        }
    }

    public func close() { portal.close() }

    /// A new conversation: the drafts go.
    func newConversation() { portal.reset() }
}
