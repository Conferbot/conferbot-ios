//
//  HumanTouches.swift
//  Conferbot
//
//  The conversation's human touches, wired (Delight.swift; RN
//  context/hooks/useDelight.ts; web ts/chat/delight/index.ts, which watches
//  the transcript):
//
//    - the bot reacts to an answer that deserves it, 550 ms after it lands;
//    - bookings, payments and perfect scores celebrate (not with Reduce Motion);
//    - a question that waits a long while gets a gentle nudge;
//    - the latest answer can be changed with one tap ("Edit"), which takes
//      the conversation back to that question (NodeFlowEngine.rewindTo).
//
//  An answer is a visitor row ConferBot stamps with `answerOf` in its
//  metadata ({nodeId, type, text}). Each touch follows the owner's setting
//  (botReactions, celebrations, stallNudges, allowChangeAnswer; all on
//  unless false). `ConferBot.shared.touches` holds it; both chats read it.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class HumanTouches: ObservableObject {

    /// What an answer row shows: the bot's tapback, and a burst (a new value restarts it).
    public struct Touch: Equatable {
        public var reaction: String?
        public var celebrate: Int?
    }

    @Published public private(set) var touches: [String: Touch] = [:]
    /// The visitor row with "Edit" under it, if any.
    @Published public private(set) var changeRowId: String?
    /// "No rush - ..." under a question that has waited.
    @Published public private(set) var stallHint: String?

    struct Hooks {
        var customizations: () -> [String: Any]?
        var engine: () -> NodeFlowEngine?
        var messages: () -> [any RecordItem]
        var setMessages: ([any RecordItem]) -> Void
        /// A person or the AI agent is in the conversation, or it is over: no going back.
        var locked: () -> Bool
        var botBusy: () -> Bool
        /// The chat open, on the conversation, and the app in front.
        var chatVisible: () -> Bool
        var reducedMotion: () -> Bool
        var afterRewind: () -> Void
    }

    private let hooks: Hooks
    private var composer = ""
    private var seen: Set<String> = []
    private var started = false
    private var armedFor: String?
    private var changeCheck: DispatchWorkItem?
    private var counter = 0
    private lazy var stall: Delight.StallWatch = Delight.StallWatch(
        isVisible: { [weak self] in self?.hooks.chatVisible() ?? false },
        composerValue: { [weak self] in self?.composer ?? "" },
        show: { [weak self] hint in self?.stallHint = hint },
        hide: { [weak self] in self?.stallHint = nil },
        now: { Date().timeIntervalSince1970 * 1000 },
        setTimer: { ms, fn in
            let item = DispatchWorkItem(block: fn)
            DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000, execute: item)
            return item
        },
        clearTimer: { ($0 as? DispatchWorkItem)?.cancel() }
    )

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    /// What a visitor row says it answered, or nil.
    nonisolated public static func answerOf(_ row: any RecordItem) -> (nodeId: String, type: String, text: String)? {
        let meta = (row as? UserMessageRecord)?.metadata ?? (row as? UserInputResponseRecord)?.metadata
        guard let a = meta?["answerOf"]?.value as? [String: Any], let nodeId = a["nodeId"] as? String,
              let type = a["type"] as? String else { return nil }
        return (nodeId, type, a["text"] as? String ?? "")
    }

    /// The `answerOf` stamp for a visitor row.
    nonisolated static func stamp(nodeId: String, type: String, text: String) -> [String: AnyCodable] {
        ["answerOf": AnyCodable(["nodeId": nodeId, "type": type, "text": text])]
    }

    nonisolated private static func isVisitorRow(_ row: any RecordItem) -> Bool {
        row.type == .userMessage || row.type == .userInputResponse
    }

    // MARK: - The nudge

    /// The step on screen changed: a new question (re)arms the nudge.
    func uiStateChanged(_ ui: NodeUIState?, stepType: (String) -> String) {
        if case .loading? = ui { return } // the typing dots before the next step: keep what is up
        let nodeId = ui?.stepNodeId
        let type = nodeId.map(stepType) ?? ""
        let key = nodeId.map { "\($0):\(type)" }
        defer { scheduleChangeCheck() }
        if key == armedFor { return }
        armedFor = key
        stall.disarm()
        if key != nil, Delight.touchOn(hooks.customizations(), .stallNudges), Delight.nudgesWhileWaiting(type) { stall.arm(type) }
    }

    /// The visitor touched, scrolled or typed in the chat.
    public func noteActivity() { stall.touch() }

    /// What is in the composer (a nudge waits while something is typed).
    public func setComposerValue(_ text: String) {
        composer = text
        stall.touch()
    }

    // MARK: - Reactions and celebrations

    /// The conversation's rows changed: fresh answers get their touches a beat later.
    func messagesChanged(_ rows: [any RecordItem]) {
        let ids = Set(rows.map { $0.id })
        defer {
            seen = ids
            scheduleChangeCheck()
        }
        // What was on screen when the chat opened (restored) gets nothing.
        guard started else {
            started = true
            return
        }
        let now = Date()
        let fresh = rows.filter { !seen.contains($0.id) && now.timeIntervalSince($0.time) < 30 && Self.answerOf($0) != nil }
        for row in fresh {
            stall.disarm()
            guard let answer = Self.answerOf(row) else { continue }
            let id = row.id
            let text = answer.text.isEmpty ? ((row as? UserMessageRecord)?.text ?? "") : answer.text
            DispatchQueue.main.asyncAfter(deadline: .now() + Delight.reactAfterMs / 1000) { [weak self] in
                guard let self = self else { return }
                let touch = Delight.touchesFor(self.hooks.customizations(), answer.type, text, reducedMotion: self.hooks.reducedMotion())
                guard touch.reaction != nil || touch.celebrate else { return }
                self.counter += 1
                self.touches[id] = Touch(reaction: touch.reaction, celebrate: touch.celebrate ? self.counter : nil)
            }
        }
    }

    /// The burst is over.
    public func clearBurst(_ id: String) {
        guard touches[id]?.celebrate != nil else { return }
        touches[id]?.celebrate = nil
    }

    // MARK: - "Edit" on the latest answer

    /// The bot went quiet, the conversation or the lock changed: "Edit" is
    /// worked out again 900 ms later.
    func scheduleChangeCheck() {
        changeCheck?.cancel()
        if changeRowId != nil { changeRowId = nil }
        let item = DispatchWorkItem { [weak self] in self?.checkChange() }
        changeCheck = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Delight.quietBeforeChangeMs / 1000, execute: item)
    }

    private func latestPoint() -> (row: any RecordItem, point: NodeFlowEngine.QuestionPoint)? {
        guard let engine = hooks.engine(), let last = hooks.messages().last(where: Self.isVisitorRow),
              let answer = Self.answerOf(last),
              let point = engine.questionPoints.last(where: { $0.nodeId == answer.nodeId }) else { return nil }
        return (last, point)
    }

    private func checkChange() {
        guard let engine = hooks.engine(), let (row, point) = latestPoint() else { return }
        let show = Delight.showChangeFor(customizations: hooks.customizations(), locked: hooks.locked() || engine.isEnded,
                                         botBusy: hooks.botBusy(), isLatestAnswer: true,
                                         questionType: point.type, typesSince: engine.typesSince(point))
        changeRowId = show ? row.id : nil
    }

    /// "Edit": the conversation cut back to the question (its own rows above
    /// the answer go too), and the question asked again.
    public func changeAnswer() {
        guard let id = changeRowId, let engine = hooks.engine() else { return }
        let rows = hooks.messages()
        guard let index = rows.firstIndex(where: { $0.id == id }), let answer = Self.answerOf(rows[index]),
              let point = engine.questionPoints.last(where: { $0.nodeId == answer.nodeId }) else { return }
        let nodeIds: [String?] = rows.map { (($0 as? BotMessageRecord)?.nodeData?["nodeId"]?.value as? String) }
        let cut = Delight.cutIndex(nodeIds, answerIndex: index, nodeId: answer.nodeId)
        changeRowId = nil
        stall.disarm()
        armedFor = nil
        hooks.setMessages(Array(rows.prefix(cut)))
        seen = Set(rows.prefix(cut).map { $0.id })
        Task { @MainActor in
            await engine.rewindTo(point.id)
            self.hooks.afterRewind()
        }
    }
}
