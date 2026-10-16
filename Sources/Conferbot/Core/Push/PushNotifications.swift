//
//  PushNotifications.swift
//  Conferbot
//
//  Push notifications wired into the chat (Core/Push/Push.swift; React
//  Native's context/hooks/usePushNotifications.ts, Flutter's PushExtras).
//  Opt-in: nothing happens until the app passes its APNs or FCM token to
//  `ConferBot.setPushToken`; the SDK never loads Firebase.
//
//  - The token is registered with the current conversation, again for each
//    new one, and tried again as the conversation goes on while the server
//    does not have it yet (a new chat is stored when the visitor answers).
//  - Unregistered on a sign-out (`identify(user: nil)`) or another user, on
//    `clearStoredSession()`, or `unregisterPush()`.
//  - `handle(userInfo)` recognises a Conferbot notification for this bot and
//    opens its conversation: the chat when it is the one on the device, else
//    that conversation in "Your requests".
//
//  Owned by ConferBot (`ConferBot.shared.push`); no UI here.
//

import Foundation

@MainActor
public final class PushNotifications {
    /// A burst of messages is one retry.
    nonisolated static let retryDebounce: TimeInterval = 1

    struct Hooks {
        var botId: () -> String?
        var chatSessionId: () -> String?
        /// The chat is on screen on its conversation (not the home screen).
        var chatOnScreen: () -> Bool
        /// Bring the chat up (the launcher's sheet, the app's own screen).
        var openChat: (ConferbotPush) -> Void
        /// The conversation, past the home screen.
        var showChat: () -> Void
        /// Another of the visitor's conversations, in "Your requests".
        var openRequest: (String) -> Void
        var bumpUnread: () -> Void
        var register: PushRegistrar.Register
        var unregister: PushRegistrar.Unregister
        var deviceInfo: () -> [String: String]? = { nil }
        var retryDelay: TimeInterval = PushNotifications.retryDebounce
    }

    private let hooks: Hooks
    public let registrar: PushRegistrar

    private var session: String?
    private var userId: String?
    private var retry: Task<Void, Never>?
    /// A tap that came before `initialize` (the app started from it).
    private(set) var pending: ConferbotPush?

    init(hooks: Hooks) {
        self.hooks = hooks
        self.registrar = PushRegistrar(register: hooks.register, unregister: hooks.unregister, deviceInfo: hooks.deviceInfo)
    }

    /// The app's token; nil unregisters.
    func setToken(_ token: String?, type: PushTokenType?) async {
        session = hooks.chatSessionId()
        await registrar.setSession(session)
        await registrar.setToken(token, type: type)
    }

    /// Stop this device's pushes. The token is kept for the next conversation.
    func stop() async { await registrar.unregister() }

    /// The conversation on the device changed: registered with the new one.
    func sessionChanged(_ id: String?) {
        guard id != session else { return }
        session = id
        Task { await registrar.setSession(id) }
    }

    /// The conversation went on: a registration still waiting tries again (debounced).
    func recordChanged() {
        guard registrar.token != nil else { return }
        retry?.cancel()
        let delay = hooks.retryDelay
        retry = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, let self = self else { return }
            await self.registrar.poke()
        }
    }

    /// The signed-in user: a sign-out or another user stops the old pushes.
    func userChanged(_ id: String?) {
        let before = userId
        userId = id
        if let before = before, before != id { Task { await registrar.unregister() } }
    }

    /// The SDK is initialized: a tap kept for it is opened (when it is this bot's).
    func ready() {
        guard let push = pending else { return }
        pending = nil
        if push.botId == hooks.botId() { open(push) }
    }

    private func open(_ push: ConferbotPush) {
        let current = hooks.chatSessionId()
        hooks.openChat(push)
        if current == nil || current == push.chatSessionId {
            hooks.showChat()
        } else {
            // Another of the visitor's conversations: that one, in "Your requests".
            hooks.openRequest(push.chatSessionId)
        }
    }

    /// A notification the app received or the visitor tapped: true when it
    /// is this bot's Conferbot message, and its conversation is opened
    /// (`open` false: only counted as unread unless it is on screen).
    /// Before `initialize` a Conferbot tap is kept and opened then, if it is
    /// that bot's.
    func handle(_ userInfo: [AnyHashable: Any]?, open shouldOpen: Bool) -> Bool {
        guard let push = ConferbotPush.parse(userInfo) else { return false }
        guard let botId = hooks.botId() else {
            if shouldOpen { pending = push }
            return true
        }
        guard push.botId == botId else { return false }
        if !shouldOpen {
            if !(hooks.chatOnScreen() && hooks.chatSessionId() == push.chatSessionId) { hooks.bumpUnread() }
            return true
        }
        open(push)
        return true
    }
}
