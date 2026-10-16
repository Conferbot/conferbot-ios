//
//  HomeScreen.swift
//  Conferbot
//
//  The home screen in the SDK (web conferbot-widget
//  src/ts/home/firstImpression.ts enhanceHome / goToChat, index.ts's view
//  switches, ts/home/visitorMemory.ts, ts/knowledgeBase/kbContent.ts
//  remoteSearch; ported from the React Native SDK's
//  context/hooks/useHomeScreen.ts). Holds:
//
//    - which view the open chat shows: the home screen, the conversation or
//      the help centre (Home.safeView: the home only while the owner has it
//      on). It starts on the home and keeps the last view while the app
//      runs, as the web keeps it for the page;
//    - what the device remembers for "Welcome back" (per bot in
//      UserDefaults): the first real question of the latest conversation the
//      visitor typed in, their first name once a flow asked for it, when
//      they last wrote;
//    - the help centre's data from fetched-chatbot-data, for the home's
//      cards, and the server's search inside article text.
//
//  Owned by ConferBot (`ConferBot.shared.home`). Main actor.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

@MainActor
public final class HomeScreen: ObservableObject {

    /// The web's wait for the server's article search (kbContent.ts SEARCH_TIMEOUT_MS).
    public static let searchTimeoutMs: Double = 5000
    /// Into the chat, then the question: the same pause the greeting card's "send" has.
    public static let askAfterMs: Double = 400

    /// What it needs from the SDK (closures, so it can be tested without a socket).
    struct Hooks {
        /// The bot's settings (themed, personalised).
        var customizations: () -> [String: Any]?
        var botName: () -> String?
        /// The bot's AI agent (a no-flow agent bot), else nil.
        var agent: () -> Home.Agent?
        /// The conversation on the device.
        var sessionId: () -> String?
        /// The visitor's requests (nil until read) and when each was last read here.
        var requests: () -> (list: [RequestSummary]?, seen: [String: Double])
        var isConnected: () -> Bool
        var emitWithAck: (_ event: String, _ data: [String: Any], _ timeoutSeconds: Double, _ done: @escaping (Any?) -> Void) -> Void
        /// Send the visitor's words (ConferBot.sendMessage).
        var send: (String) -> Void
        /// The home screen came into view: read the requests again (at most every 15s).
        var onHomeShown: () -> Void
        var defaults: UserDefaults = .standard
        var now: () -> Double = { Date().timeIntervalSince1970 * 1000 }
        var after: (_ ms: Double, _ fn: @escaping () -> Void) -> Void = { ms, fn in
            DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000, execute: fn)
        }
    }

    /// The view the visitor picked (nil: where the chat opens).
    @Published private var chosen: HomeView?
    /// The topic the help centre opened on, if any.
    @Published public private(set) var helpCategoryId: String?
    /// What the device remembers for "Welcome back".
    @Published public private(set) var memory: Home.Memory?
    /// The help centre's data as fetched-chatbot-data sent it (published articles without bodies).
    @Published public private(set) var categories: [[String: Any]] = []
    @Published public private(set) var recentArticles: [[String: Any]] = []

    private let hooks: Hooks
    private var botId = ""
    private var lastName = ""
    private var searches: [String: [Home.RemoteHit]] = [:]

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    // MARK: - The view

    /// The view the open chat shows.
    public var view: HomeView { Home.safeView(hooks.customizations(), chosen) }

    /// The owner has a home screen.
    public var isOn: Bool { Home.homeOn(hooks.customizations()) }

    private func choose(_ next: HomeView) {
        let before = view
        chosen = next
        // The home screen came back into view: its requests card reads again.
        if view == .home && before != .home { hooks.onHomeShown() }
    }

    /// Back to the home screen (nothing when the owner has none).
    public func showHome() {
        if isOn { choose(.home) }
    }

    /// To the conversation; with `text`, ask it there as the visitor (400ms later).
    public func showChat(_ text: String? = nil) {
        choose(.chat)
        let words = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        hooks.after(Self.askAfterMs) { [weak self] in self?.hooks.send(words) }
    }

    /// The help centre, on one topic or its list.
    public func showHelp(categoryId: String? = nil) {
        helpCategoryId = categoryId
        choose(.help)
    }

    // MARK: - The model

    /// What the home screen shows now; nil while the owner has no home screen.
    public func model(hour: Double? = nil) -> Home.Model? {
        let r = hooks.requests()
        return Home.model(.init(
            c: hooks.customizations(),
            botName: hooks.botName(),
            agent: hooks.agent(),
            categories: categories,
            recentArticles: recentArticles,
            memory: memory,
            chatSessionId: hooks.sessionId(),
            requests: r.list,
            seen: r.seen,
            now: hooks.now(),
            hour: hour
        ))
    }

    /// Every article as sent (the ask box asks the server only when one has no body).
    public var rawArticles: [[String: Any]] {
        recentArticles + categories.flatMap { ($0["articles"] as? [[String: Any]]) ?? [] }
    }

    // MARK: - Memory

    /// What the device remembers for this bot (initialize).
    func load(botId: String) {
        self.botId = botId
        lastName = ""
        searches = [:]
        memory = Home.parseMemory(hooks.defaults.string(forKey: Home.memoryKey(botId)), now: hooks.now())
    }

    private func save(_ next: Home.Memory?) {
        guard let next = next else { return }
        memory = next
        hooks.defaults.set(Home.serializeMemory(next), forKey: Home.memoryKey(botId))
    }

    /// The visitor typed this in a live (or agent) chat (web special.ts _handleHumanHandoverInputSubmit).
    func rememberText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        save(Home.withMessage(memory, session: hooks.sessionId(), text: text, now: hooks.now()))
    }

    /// A flow asked for their name (web index.ts _setUserMetaData "name").
    func rememberName(_ name: String?) {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != lastName else { return }
        lastName = n
        save(Home.withName(memory, name: n, now: hooks.now()))
    }

    // MARK: - The help centre

    /// fetched-chatbot-data's knowledgeBaseData.
    func setKnowledgeBase(_ json: Any?) {
        let kb = json as? [String: Any]
        categories = kb?["categories"] as? [[String: Any]] ?? []
        recentArticles = kb?["recentArticles"] as? [[String: Any]] ?? []
    }

    /// Matches inside article text from the server ([] on failure): web
    /// kbContent.ts remoteSearch, `search-kb-articles`, cached per query
    /// when it answered.
    public func searchArticleText(_ query: String) async -> [Home.RemoteHit] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard key.count >= 2 else { return [] }
        if let hit = searches[key] { return hit }
        guard hooks.isConnected() else { return [] }
        let payload: [String: Any] = ["chatbotId": botId, "query": key, "limit": 10]
        let reply: Any? = await withCheckedContinuation { cont in
            hooks.emitWithAck("search-kb-articles", payload, Self.searchTimeoutMs / 1000) { cont.resume(returning: $0) }
        }
        let d = reply as? [String: Any]
        guard d?["success"] as? Bool == true else { return [] }
        // Failures are not kept, so the next keystroke can try again.
        let list = ((d?["articles"] as? [[String: Any]]) ?? []).compactMap { a -> Home.RemoteHit? in
            let id = Home.idOf(a["_id"])
            return id.isEmpty ? nil : Home.RemoteHit(id: id, snippet: (a["snippet"] as? String) ?? "")
        }
        searches[key] = list
        return list
    }
}
