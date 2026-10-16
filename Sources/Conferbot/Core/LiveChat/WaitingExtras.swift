//
//  WaitingExtras.swift
//  Conferbot
//
//  While the visitor waits for a person, as the web widget has it: the help
//  card (the articles for their question 6s in, or the server's queue-help
//  pick with "That solved it"), the games offer 2.5s after the waiting
//  signal, and a help article opened in the app. The rules are in
//  WaitArticles.swift, WaitingGames.swift and GamesCard.swift (ported from
//  the React Native SDK's core files, themselves from the web's
//  waitArticles.ts, games/wire.ts, games/ui.ts and handlers/special.ts
//  _wireQueue); this class feeds them the signals and the socket, as RN's
//  context/hooks/useWaitingExtras.ts does.
//
//  Each card sits in the conversation after the message that was last when
//  it was drawn (`helpAnchor`, `gamesAnchor`), so later messages come under
//  it. The cards are never in `messages`, the record the server keeps or
//  anything saved on the device.
//
//  Owned by ConferBot (`conferBot.waiting`). Main thread.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

public final class WaitingExtras: ObservableObject {

    /// What it needs from the SDK (closures, so it can be tested without a socket).
    struct Hooks {
        var sessionId: () -> String?
        var emitWithAck: (_ event: String, _ data: [String: Any], _ timeout: Double, _ done: @escaping (Any?) -> Void) -> Void
        /// The bot's customizations as the widget applies them.
        var customizations: () -> [String: Any]?
        /// The conversation's record (the server's).
        var record: () -> [[String: Any]]
        /// The id of the last message on screen (where a new card goes).
        var lastMessageId: () -> String?
        /// Out of the queue because an article helped: the line, the record, the flow on.
        var leftQueueHelped: () -> Void
        /// Open a help article in the app (the help centre); false when it can't.
        var openArticle: (String) -> Bool
        /// The phone asks for reduced motion.
        var reducedMotion: () -> Bool
        var schedule: ConnectingSignal.Schedule = ConnectingSignal.mainQueueTimer
    }

    /// The help card ("While you wait, this might help"), or nil.
    @Published public private(set) var helpCard: HelpCardState?
    /// The message the help card is drawn after (nil: at the end).
    @Published public private(set) var helpAnchor: String?
    /// The games card on screen, or nil.
    @Published public private(set) var gamesCard: GamesCard?
    /// The message the games card is drawn after (nil: at the end).
    @Published public private(set) var gamesAnchor: String?

    private let hooks: Hooks
    // The bot's help centre from fetched-chatbot-data (knowledgeBaseData).
    private var kbCategories: [[String: Any]] = []
    private var kbRecent: [[String: Any]] = []
    /// Chat screens that draw the cards (the SwiftUI chats); none: no games offered.
    private var drawers = 0
    private var gamesSeq = 0
    private var signalOffs: [() -> Void] = []

    private(set) lazy var help = WaitHelp(.init(
        customizations: { [weak self] in self?.hooks.customizations() },
        question: { [weak self] in WaitArticles.waitQuestion(self?.hooks.record() ?? []) },
        articles: { [weak self] in (self?.kbCategories ?? [], self?.kbRecent ?? []) },
        joined: { [weak self] in HandoverState.phase(self?.hooks.record() ?? []) == .joined },
        onChange: { [weak self] card in self?.helpChanged(card) },
        schedule: hooks.schedule
    ))

    private(set) lazy var offer = GamesOffer(
        enabled: { [weak self] in WaitingGames.settings(self?.hooks.customizations()).enabled },
        mount: { [weak self] mode in self?.mountGames(mode) },
        schedule: hooks.schedule
    )

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    private func helpChanged(_ card: HelpCardState?) {
        // A new card (its key) is drawn after the conversation so far.
        if let card = card, card.key != helpCard?.key { helpAnchor = hooks.lastMessageId() }
        if card == nil { helpAnchor = nil }
        helpCard = card
    }

    private func mountGames(_ mode: GamesOffer.Mode) -> OfferCard? {
        guard drawers > 0 else { return nil }
        var o = GamesCard.Options(customizations: hooks.customizations())
        o.categories = kbCategories
        o.recentArticles = kbRecent
        o.mode = mode
        o.reducedMotion = hooks.reducedMotion()
        o.schedule = hooks.schedule
        o.onDismiss = { [weak self] in self?.offer.dismissed() }
        guard let card = GamesCard(o) else { return nil }
        gamesSeq += 1
        let n = gamesSeq
        // Gone (Not now, the x, the wait over, a person joined before it was played): off the screen.
        card.subscribe { [weak self] s in
            guard let self = self, s.view == .gone, self.gamesSeq == n else { return }
            self.gamesCard = nil
            self.gamesAnchor = nil
        }
        gamesAnchor = hooks.lastMessageId()
        gamesCard = card
        return card
    }

    // MARK: - Wiring

    /// A chat screen that draws the cards appeared (true) or went (false).
    /// Without one, the games are not offered and "play" is sent as words.
    public func setDrawing(_ on: Bool) {
        drawers = max(0, drawers + (on ? 1 : -1))
    }

    /// The handover's signals (HandoverLifecycle.signals).
    func listen(to bus: WidgetSignalBus) {
        signalOffs.forEach { $0() }
        signalOffs = [
            bus.on(.waitingForHuman) { [weak self] _ in self?.offer.waiting() },
            bus.on(.humanJoined) { [weak self] d in
                self?.help.endWait()
                self?.offer.joined(d.name)
            },
            bus.on(.waitOver) { [weak self] _ in
                self?.help.endWait()
                self?.offer.waitOver()
            },
        ]
    }

    private func own(_ data: [String: Any]?) -> Bool {
        guard let id = data?["chatSessionId"] as? String, !id.isEmpty, let mine = hooks.sessionId(), !mine.isEmpty else { return true }
        return id == mine
    }

    /// The socket: the server's pick of help, and the queue it keeps.
    func setupListeners(on socket: SocketClient) {
        socket.on(SocketEvents.queueHelp) { [weak self] data, _ in
            let d = data.first as? [String: Any]
            DispatchQueue.main.async { self?.onQueueHelp(d) }
        }
        socket.on(SocketEvents.queueLeft) { [weak self] data, _ in
            let d = data.first as? [String: Any]
            DispatchQueue.main.async { self?.onQueueLeft(d) }
        }
    }

    func onQueueHelp(_ data: [String: Any]?) {
        if own(data) { help.queueHelp(data) }
    }

    func onQueueLeft(_ data: [String: Any]?) {
        if own(data) && data?["reason"] as? String == "self_service" { help.left() }
    }

    /// queue-status, from the event or the poll's answer (LiveChatExtras).
    func onQueueStatus(_ data: [String: Any]?) {
        if let data = data, own(data) { help.queueStatus(data) }
    }

    /// fetched-chatbot-data's knowledgeBaseData.
    func setKnowledgeBase(_ json: Any?) {
        let kb = json as? [String: Any]
        kbCategories = kb?["categories"] as? [[String: Any]] ?? []
        kbRecent = kb?["recentArticles"] as? [[String: Any]] ?? []
    }

    /// Where the handover begins a wait for a person (with no AI agent first).
    func waitStarted() { help.startWait() }

    /// Wherever a wait for a person ends.
    func waitEnded() { help.endWait() }

    // MARK: - Actions

    /// "That solved it": queue-self-resolve with the article; ok leaves the
    /// queue. `done` gets ok on the main thread.
    public func solveWait(_ done: @escaping (Bool) -> Void = { _ in }) {
        guard let item = help.solving() else { return done(false) }
        let sid = hooks.sessionId() ?? ""
        hooks.emitWithAck(SocketEvents.queueSelfResolve, HandoverState.queueSelfResolvePayload(sid, articleId: item.id), WaitArticles.solveTimeoutMs / 1000) { [weak self] res in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let ok = (res as? [String: Any])?["ok"] as? Bool == true
                self.help.solved(ok)
                if ok { self.hooks.leftQueueHelped() }
                done(ok)
            }
        }
    }

    /// A row of the help card was tapped: an article opens in the app (a
    /// page is opened in the browser by the view). It is the one "That
    /// solved it" names.
    public func openHelpItem(_ item: HelpItem) {
        help.open(item.id)
        if item.kind == .article { _ = hooks.openArticle(item.id) }
    }

    /// The visitor's words while waiting: "play" opens the games instead (true: do not send).
    public func interceptPlay(_ text: String) -> Bool { offer.play(text) }

    /// A new conversation.
    func reset() {
        help.reset()
        offer.reset()
        gamesCard?.remove()
        gamesSeq += 1
        gamesCard = nil
        gamesAnchor = nil
    }
}
