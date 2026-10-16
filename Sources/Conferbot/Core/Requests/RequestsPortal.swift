//
//  RequestsPortal.swift
//  Conferbot
//
//  "Your requests": the screens as states (web conferbot-widget
//  src/ts/home/requests/view.ts mountRequestsView; ported from the React
//  Native SDK's src/core/requestsPortal.ts). One thing at a time:
//
//    list      each request's question and where it stands, in words
//    request   a banner saying where it stands and what happens next, the
//              conversation, and a reply box with a Send button. A reply to
//              a solved request opens it again; the banner says so first.
//
//  Back always goes one step back. Team replies arrive live while a request
//  is open (`my-request-update`), keeping what the visitor was typing and
//  any reply that did not go out. The views draw `state` and call the
//  actions; nothing here touches SwiftUI.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

/// A reply on its way, or one that did not go (web `.cb-req__msg.is-pending`).
public struct PendingReply: Equatable, Identifiable {
    public enum Status: String { case sending, failed, locked }
    public var entryId: String
    public var text: String
    public var at: String
    public var status: Status
    public var id: String { entryId }
}

public struct RequestsPortalState: Equatable {
    public enum Screen: String { case closed, list, request }

    public var screen: Screen = .closed
    /// The bar's title.
    public var title = ""
    public var loading = false
    /// It could not be read: "We couldn't load this just now." and Try again (`reload`).
    public var failed = false
    /// The list screen's requests, newest replies first; nil until read.
    public var list: [RequestSummary]?
    /// When each was last read here, for "New reply".
    public var seen: [String: Double] = [:]
    /// The open request.
    public var request: RequestDetail?
    public var requestState: RequestState?
    /// The banner: where it stands and what happens next.
    public var banner: (label: String, detail: String)?
    public var pending: [PendingReply] = []
    public var draft = ""
    public var placeholder = Requests.Text.replyPlaceholder
    public var canSend = false

    public init() {}

    public static func == (a: RequestsPortalState, b: RequestsPortalState) -> Bool {
        a.screen == b.screen && a.title == b.title && a.loading == b.loading && a.failed == b.failed && a.list == b.list
            && a.seen == b.seen && a.request == b.request && a.requestState == b.requestState
            && a.banner?.label == b.banner?.label && a.banner?.detail == b.banner?.detail
            && a.pending == b.pending && a.draft == b.draft && a.placeholder == b.placeholder && a.canSend == b.canSend
    }
}

@MainActor
public final class RequestsPortal: ObservableObject {

    public struct Deps {
        public var api: RequestsApi
        /// When each request was last read here, and marking one read.
        public var seen: () -> [String: Double]
        public var markSeen: (_ id: String, _ at: Double) -> Void
        /// The request is the chat on screen right now: open that instead.
        public var isCurrentChat: (_ id: String) -> Bool
        public var openChat: () -> Void
        /// Something changed (the portal closed): read the list again.
        public var onChanged: (() -> Void)?
        public var now: () -> Double = { Date().timeIntervalSince1970 * 1000 }
        public var rand: () -> Double = { Double.random(in: 0..<1) }

        public init(api: RequestsApi, seen: @escaping () -> [String: Double], markSeen: @escaping (String, Double) -> Void,
                    isCurrentChat: @escaping (String) -> Bool, openChat: @escaping () -> Void, onChanged: (() -> Void)? = nil) {
            self.api = api
            self.seen = seen
            self.markSeen = markSeen
            self.isCurrentChat = isCurrentChat
            self.openChat = openChat
            self.onChanged = onChanged
        }
    }

    @Published public private(set) var state = RequestsPortalState()

    private let deps: Deps
    private var openId: String?
    private var fromList = false
    private var drafts: [String: String] = [:]
    private var lastLoad: (() async -> Void)?
    private var offUpdate: (() -> Void)?

    public init(_ deps: Deps) {
        self.deps = deps
        // A team reply or "solved" while it is open: read it again, keeping
        // whatever they were typing and a reply that did not go out.
        offUpdate = deps.api.onUpdate { [weak self] id in
            Task { @MainActor in await self?.updated(id) }
        }
    }

    deinit { offUpdate?() }

    public var isOpen: Bool { state.screen != .closed }

    private func set(_ patch: (inout RequestsPortalState) -> Void) {
        var s = state
        patch(&s)
        if s.screen == .request {
            let draft = openId.flatMap { drafts[$0] } ?? ""
            s.draft = draft
            s.canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        state = s
    }

    private func leave() {
        if let id = openId { deps.api.close(id) }
        openId = nil
        let was = state.screen
        state = RequestsPortalState()
        if was != .closed { deps.onChanged?() }
    }

    // MARK: - All requests

    /// The list screen, loading (what happens at once).
    private func beginList() {
        if let id = openId { deps.api.close(id) }
        openId = nil
        lastLoad = { [weak self] in await self?.showList() }
        set {
            $0.screen = .list; $0.title = Requests.Text.title; $0.loading = true; $0.failed = false
            $0.request = nil; $0.requestState = nil; $0.banner = nil; $0.pending = []
        }
    }

    private func showList() async {
        beginList()
        await loadList()
    }

    private func loadList() async {
        let list = await deps.api.list()
        guard state.screen == .list, openId == nil else { return }
        guard let got = list else { return set { $0.loading = false; $0.failed = true } }
        let seen = deps.seen()
        set { $0.loading = false; $0.failed = false; $0.list = Requests.ordered(got, seen: seen); $0.seen = seen }
    }

    // MARK: - One request

    private func draw(_ r: RequestDetail, pending: [PendingReply]) {
        let rs = Requests.stateOf(r.summary)
        deps.markSeen(r.id, Requests.seenAt(r.summary.lastAt, now: deps.now()))
        let words = Requests.stateWords(rs)
        set {
            $0.loading = false; $0.failed = false; $0.request = r; $0.requestState = rs
            $0.banner = words; $0.pending = pending
            $0.placeholder = rs == .solved ? Requests.Text.reopenPlaceholder : Requests.Text.replyPlaceholder
        }
    }

    private func showRequest(_ id: String) async {
        if deps.isCurrentChat(id) {
            leave()
            deps.openChat()
            return
        }
        openId = id
        lastLoad = { [weak self] in await self?.showRequest(id) }
        set {
            $0.screen = .request; $0.title = Requests.Text.one; $0.loading = true; $0.failed = false
            $0.request = nil; $0.requestState = nil; $0.banner = nil; $0.pending = []
        }
        let r = await deps.api.open(id)
        guard openId == id, state.screen == .request else { return }
        guard let got = r else { return set { $0.loading = false; $0.failed = true } }
        draw(got, pending: [])
    }

    private func withPending(_ entryId: String, _ status: PendingReply.Status?) -> [PendingReply] {
        guard let status = status else { return state.pending.filter { $0.entryId != entryId } }
        return state.pending.map { p in
            var p = p
            if p.entryId == entryId { p.status = status }
            return p
        }
    }

    private func sendText(_ id: String, entryId: String, text: String) async {
        set { [self] in $0.pending = withPending(entryId, .sending) }
        let out = await deps.api.reply(id, text, entryId)
        guard openId == id, state.screen == .request else { return }
        if out.ok, let r = out.request {
            drafts[id] = nil
            draw(r, pending: withPending(entryId, nil))
            return
        }
        let status: PendingReply.Status = out.reason == "locked" ? .locked : .failed
        set { [self] in $0.pending = withPending(entryId, status) }
    }

    private func updated(_ id: String) async {
        guard id == openId, state.screen == .request else { return }
        let r = await deps.api.open(id)
        guard let got = r, openId == id, state.screen == .request, !state.pending.contains(where: { $0.status == .sending }) else { return }
        draw(got, pending: state.pending)
    }

    // MARK: - Actions

    /// All requests (web openList). Back leaves the portal.
    public func openList() async {
        fromList = false
        await showList()
    }

    /// One request (web openRequest). Back leaves the portal.
    public func openRequest(_ id: String) async {
        fromList = false
        await showRequest(id)
    }

    /// From the list: Back comes back to the list.
    public func pick(_ id: String) async {
        fromList = true
        await showRequest(id)
    }

    /// One step back: a request opened from the list goes to the list, else the portal closes.
    public func back() {
        if state.screen == .request && fromList {
            fromList = false
            beginList()
            Task { await loadList() }
        } else {
            leave()
        }
    }

    /// Leave the portal.
    public func close() { leave() }

    /// Try again after a failed load.
    public func reload() {
        guard state.failed, let load = lastLoad else { return }
        Task { await load() }
    }

    public func setDraft(_ text: String) {
        guard let id = openId, state.screen == .request else { return }
        drafts[id] = text
        set { _ in }
    }

    /// Send the draft as a reply.
    public func send() {
        guard let id = openId, state.screen == .request, state.request != nil else { return }
        let text = (drafts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        drafts[id] = ""
        let now = deps.now()
        let entryId = Requests.replyEntryId(now: now, rand: deps.rand)
        set { $0.pending.append(PendingReply(entryId: entryId, text: text, at: Requests.iso(now), status: .sending)) }
        Task { await sendText(id, entryId: entryId, text: text) }
    }

    /// Try again on a reply that did not go.
    public func retry(_ entryId: String) {
        guard let p = state.pending.first(where: { $0.entryId == entryId }), p.status == .failed, let id = openId else { return }
        Task { await sendText(id, entryId: entryId, text: p.text) }
    }

    /// A new conversation: the drafts go.
    public func reset() { drafts = [:] }

    /// No more live updates.
    public func destroy() {
        offUpdate?()
        offUpdate = nil
    }
}
