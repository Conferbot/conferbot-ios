//
//  HandoverWaiting.swift
//  Conferbot
//
//  Waiting for a person, and the signals app code can listen to. Ported
//  from the React Native SDK (src/core/handoverWaiting.ts), itself from the
//  web widget: conferbot-widget src/ts/chat/handoverWaiting.ts
//  (createConnectingSignal, armAIEscalationNudge, the signal names and
//  details). The web dispatches the signals on its window; here they go
//  through a small bus (WidgetSignalBus), exposed as
//  `ConferBot.shared.onWidgetSignal`.
//
//    cb:waiting-for-human  the visitor now waits for a person. From the
//                          server's handover-waiting, or the SDK's own
//                          connecting wait after 20s.
//    cb:human-joined       a person (never the AI) joined.
//    cb:wait-over          the wait ended without a person.
//
//  No personal data (the visitor's email) is ever put in a detail.
//

import Foundation

public enum WidgetSignal: String, CaseIterable {
    case waitingForHuman = "cb:waiting-for-human"
    case humanJoined = "cb:human-joined"
    case waitOver = "cb:wait-over"
}

/// What a signal says. Only the fields of its kind are set.
public struct WidgetSignalDetail: Equatable {
    /// cb:waiting-for-human: the team is offline (not just busy).
    public var offline: Bool = false
    /// cb:waiting-for-human: "offline" or "busy". cb:wait-over: "unavailable", "cancelled" or "ended".
    public var reason: String?
    /// cb:waiting-for-human: when the team is back (ISO date), if known.
    public var backAt: String?
    /// cb:waiting-for-human: the visitor gave an email for the reply.
    public var emailCaptured: Bool = false
    /// cb:human-joined: the person's name.
    public var name: String?

    public init(offline: Bool = false, reason: String? = nil, backAt: String? = nil, emailCaptured: Bool = false, name: String? = nil) {
        self.offline = offline
        self.reason = reason
        self.backAt = backAt
        self.emailCaptured = emailCaptured
        self.name = name
    }
}

public enum HandoverWait {

    /// A connecting wait with nobody yet after this long counts as waiting for a person.
    public static let connectingSignalSeconds: TimeInterval = 20
    /// Chat closed when it was due: checked again this often until it opens.
    public static let connectingRecheckSeconds: TimeInterval = 2
    /// After an AI escalation's max wait, how much longer the SDK gives the
    /// server before nudging it (handover-timeout).
    public static let serverGraceSeconds: TimeInterval = 30

    /// The server's handover-waiting payload as a signal detail.
    public static func waitingDetail(_ data: [String: Any]?, emailCaptured: Bool = false) -> WidgetSignalDetail {
        let offline = data?["offline"] as? Bool == true
        let email = data?["email"] as? String
        return WidgetSignalDetail(
            offline: offline,
            reason: offline || data?["reason"] as? String == "offline" ? "offline" : "busy",
            backAt: data?["backAt"] as? String,
            emailCaptured: emailCaptured || !(email ?? "").isEmpty
        )
    }

    /// An AI escalation's wait: after the handover step's max wait plus the
    /// grace, the SDK asks the server to decide (handover-timeout) and
    /// draws nothing itself (web armAIEscalationNudge).
    public static func aiEscalationNudgeSeconds(_ maxWaitTime: Any?) -> TimeInterval {
        LiveChat.waitSeconds(maxWaitTime) + serverGraceSeconds
    }
}

/// A one-shot timer the signal can be tested with.
public protocol SignalTimer: AnyObject { func cancel() }

/// The connecting wait's own cb:waiting-for-human, once per wait.
///
///   start()   a wait for a person began (or a restore re-entered one): fire
///             after 20s unless it ends first. A second start() during the
///             same wait changes nothing.
///   end()     a person joined, nobody could, the visitor left the queue,
///             the chat ended, or the server sent its own handover-waiting.
///
/// Due while the chat is closed (canFire false), it waits for the chat to
/// open rather than offering something nobody can see.
public final class ConnectingSignal {
    public typealias Schedule = (_ seconds: TimeInterval, _ fn: @escaping () -> Void) -> SignalTimer

    private let fire: () -> Void
    private let canFire: () -> Bool
    private let schedule: Schedule
    private var timer: SignalTimer?
    private var active = false

    public init(fire: @escaping () -> Void,
                canFire: @escaping () -> Bool = { true },
                schedule: @escaping Schedule = ConnectingSignal.mainQueueTimer) {
        self.fire = fire
        self.canFire = canFire
        self.schedule = schedule
    }

    public var pending: Bool { active }

    public func start() {
        // Already counting for this wait: once per wait, not once per event.
        guard !active else { return }
        active = true
        cancel()
        timer = schedule(HandoverWait.connectingSignalSeconds) { [weak self] in self?.due() }
    }

    public func end() {
        active = false
        cancel()
    }

    private func cancel() {
        timer?.cancel()
        timer = nil
    }

    private func due() {
        timer = nil
        guard active else { return }
        guard canFire() else {
            timer = schedule(HandoverWait.connectingRecheckSeconds) { [weak self] in self?.due() }
            return
        }
        active = false
        fire()
    }

    private final class WorkItemTimer: SignalTimer {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    /// The default clock: the main queue.
    public static func mainQueueTimer(_ seconds: TimeInterval, _ fn: @escaping () -> Void) -> SignalTimer {
        let item = DispatchWorkItem(block: fn)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return WorkItemTimer(item)
    }
}

/// A listener bus for the widget signals. emit never throws.
public final class WidgetSignalBus {
    private var listeners: [WidgetSignal: [UUID: (WidgetSignalDetail) -> Void]] = [:]
    private let lock = NSLock()

    public init() {}

    /// Listen to a signal. Returns the unsubscribe.
    @discardableResult
    public func on(_ signal: WidgetSignal, _ fn: @escaping (WidgetSignalDetail) -> Void) -> () -> Void {
        let id = UUID()
        lock.lock()
        listeners[signal, default: [:]][id] = fn
        lock.unlock()
        return { [weak self] in
            self?.lock.lock()
            self?.listeners[signal]?[id] = nil
            self?.lock.unlock()
        }
    }

    /// Tell every listener; returns how many there were.
    @discardableResult
    public func emit(_ signal: WidgetSignal, _ detail: WidgetSignalDetail) -> Int {
        lock.lock()
        let fns = Array((listeners[signal] ?? [:]).values)
        lock.unlock()
        fns.forEach { $0(detail) }
        return fns.count
    }
}
