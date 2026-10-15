//
//  HandoverLifecycle.swift
//  Conferbot
//
//  The handover's lifecycle on screen: the "Connecting you with the team…"
//  line and how it settles, the 20s waiting signal, the AI escalation's
//  max-wait nudge, leaving the queue, and picking a live chat back up after
//  the app restarts. The logic is in HandoverState.swift and
//  HandoverWaiting.swift; this class applies it to the record, the messages
//  and the socket, as the React Native SDK's useHandoverLifecycle does
//  (web: handoverState.ts, handoverWaiting.ts, special.ts, index.ts).
//
//  Owned by ConferBot (`conferBot.handover`). Main thread.
//

import Foundation

public final class HandoverLifecycle {

    /// What the lifecycle needs from the SDK (closures, so it can be tested without a socket).
    struct Hooks {
        var sessionId: () -> String?
        var emit: (_ event: String, _ data: [String: Any]) -> Void
        var emitWithAck: (_ event: String, _ data: [String: Any], _ timeout: Double, _ done: @escaping (Any?) -> Void) -> Void
        var joinRoom: (_ chatSessionId: String) -> Void
        var chatState: () -> ChatState
        var messages: () -> [any RecordItem]
        var setMessages: ([any RecordItem]) -> Void
        var engine: () -> NodeFlowEngine?
        /// The chat is on screen (the 20s signal waits for it).
        var chatVisible: () -> Bool
        /// A flow's handover step is waiting for a person.
        var waitingForPerson: () -> Bool
        /// The handover step's data (max wait, assignment): the flow's, or an agent bot's.
        var handoverStepData: () -> [String: Any]?
        var setLive: (Bool) -> Void
        var setAgent: (Agent?, AgentDetails?) -> Void
        var save: () -> Void
    }

    public let signals = WidgetSignalBus()
    private let hooks: Hooks
    private let schedule: ConnectingSignal.Schedule
    private(set) lazy var connecting = ConnectingSignal(
        fire: { [weak self] in
            self?.signals.emit(.waitingForHuman, HandoverWait.waitingDetail(["offline": false, "reason": "busy"]))
        },
        canFire: { [weak self] in self?.hooks.chatVisible() ?? false },
        schedule: schedule
    )
    private var nudge: SignalTimer?

    init(hooks: Hooks, schedule: @escaping ConnectingSignal.Schedule = ConnectingSignal.mainQueueTimer) {
        self.hooks = hooks
        self.schedule = schedule
    }

    private var record: [[String: Any]] { hooks.chatState().getServerRecord() }

    private func own(_ data: [String: Any]?) -> Bool {
        guard let id = data?["chatSessionId"] as? String, !id.isEmpty, let mine = hooks.sessionId() else { return true }
        return id == mine
    }

    private static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    // Its own id per entry: two lines in the same millisecond must not merge.
    private static func entryId(_ kind: String) -> String {
        "\(kind)-\(Int(Date().timeIntervalSince1970 * 1000))-\(String(UInt32.random(in: 0...UInt32.max), radix: 36))"
    }

    /// A line on screen and (with `server`) in the conversation's record.
    private func add(_ item: any RecordItem, server: [String: Any]? = nil) {
        if let server = server { hooks.chatState().pushServerEntry(server) }
        var list = hooks.messages()
        guard !list.contains(where: { $0.id == item.id }) else { return }
        list.append(item)
        hooks.setMessages(list)
    }

    private static func details(_ raw: Any?) -> AgentDetails? {
        guard let dict = raw as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(AgentDetails.self, from: data)
    }

    // MARK: - The line

    /// The Connecting line has its answer: settled on screen and in the record.
    func settle(_ outcome: HandoverOutcome) {
        hooks.chatState().updateServerRecord { HandoverState.settle($0, outcome).record }
        let list = hooks.messages()
        guard list.contains(where: { ($0 as? AgentLeftMessageRecord)?.isPendingHandover == true }) else { return }
        hooks.setMessages(list.map { item in
            guard let line = item as? AgentLeftMessageRecord, line.isPendingHandover else { return item }
            return line.settling(outcome)
        })
    }

    /// The wait ended without a person: no waiting signal, no nudge, and cb:wait-over.
    private func waitOver(_ reason: String) {
        connecting.end()
        clearNudge()
        signals.emit(.waitOver, WidgetSignalDetail(reason: reason))
    }

    private var inWait: Bool {
        hooks.waitingForPerson() || connecting.pending || HandoverState.hasPendingLine(record)
    }

    /// A flow's handover waiting for a person straight away: the 20s signal
    /// (web special.ts startHandover; not when an AI agent takes it first).
    func flowWaitStarted(nodeData: [String: Any]?) {
        let ai = (nodeData?["assignedAIAgents"] as? [Any]) ?? []
        if ai.isEmpty { connecting.start() }
    }

    // MARK: - AI escalation's max wait (#36)

    /// After an AI escalates, the step's max wait plus 30s of grace, then
    /// handover-timeout so a server that lost its own timer still decides.
    /// Nothing is drawn: the server answers (handover-waiting, no-agents-available).
    private func armNudge() {
        clearNudge()
        let data = hooks.handoverStepData()
        nudge = schedule(HandoverWait.aiEscalationNudgeSeconds(data?["maxWaitTime"])) { [weak self] in
            guard let self = self, let id = self.hooks.sessionId() else { return }
            self.nudge = nil
            let workspaceId = self.hooks.chatState().workspaceId ?? (self.hooks.chatState().getVariable(name: "_workspaceId") as? String)
            self.hooks.emit(SocketEvents.handoverTimeout, LiveChat.handoverTimeoutPayload(chatSessionId: id, nodeData: data, workspaceId: workspaceId))
        }
    }

    private func clearNudge() {
        nudge?.cancel()
        nudge = nil
    }

    var nudgePending: Bool { nudge != nil }

    // MARK: - Socket events

    /// agent-left (web agentListeners.ts): an AI escalating draws one
    /// Connecting line and starts the wait; an idle pause draws nothing; a
    /// person leaving says so. Returns the kind.
    @discardableResult
    func onAgentLeft(_ data: [String: Any]?) -> HandoverState.AgentLeftKind {
        let kind = HandoverState.agentLeftKind(data)
        if kind == .ignore { return kind }
        let raw = data?["agentDetails"] as? [String: Any]
        let details = Self.details(raw) ?? AgentDetails(id: "", name: "", email: "")
        let handover = kind == .handover
        if handover {
            connecting.start()
            armNudge()
            // The same escalation again: one line is enough.
            if HandoverState.hasPendingLine(record) { return kind }
        }
        let id = Self.entryId("agent-left")
        var entry: [String: Any] = [
            "id": id, "_id": id, "type": "agent-left-chat", "time": Self.now(), "name": details.name,
            "agentId": details.id, "text": HandoverState.agentLeftText(details.name, handover: handover),
        ]
        if let raw = raw { entry["agentDetails"] = raw }
        if handover { entry["handover"] = true }
        add(AgentLeftMessageRecord(id: id, time: Date(), agentDetails: details, handover: handover ? true : nil), server: entry)
        hooks.save()
        return kind
    }

    /// agent-accepted (web special.ts _handleHandoverAccepted): the wait is
    /// over - a person joined, or the AI took the chat back. Settles the
    /// line, ends the waiting signal and the nudge, says cb:human-joined for
    /// a person. Returns the plan (announce: draw the join line).
    @discardableResult
    func onAccepted(_ data: [String: Any]?) -> HandoverState.AcceptedPlan {
        let plan = HandoverState.acceptedPlan(record, data: data)
        connecting.end()
        clearNudge()
        settle(plan.outcome)
        if plan.humanJoined {
            signals.emit(.humanJoined, WidgetSignalDetail(name: (data?["agentDetails"] as? [String: Any])?["name"] as? String))
        }
        return plan
    }

    /// The join line: "<name> joined the chat", with its note after an AI handover.
    func addJoin(_ details: AgentDetails, raw: [String: Any]?, plan: HandoverState.AcceptedPlan) {
        let id = Self.entryId("agent-joined")
        var entry: [String: Any] = [
            "id": id, "_id": id, "type": "agent-joined-message", "time": Self.now(), "name": details.name,
            "agentId": details.id, "text": "\(details.name) has joined the chat",
        ]
        entry["agentDetails"] = raw ?? ["_id": details.id, "name": details.name, "email": details.email]
        if plan.afterAI { entry["afterAI"] = true }
        if plan.ai { entry["ai"] = true }
        add(AgentJoinedMessageRecord(id: id, time: Date(), agentDetails: details, afterAI: plan.afterAI ? true : nil), server: entry)
    }

    /// The server's own word on the wait (an AI escalation found nobody):
    /// its cb:waiting-for-human, never ours as well.
    func onHandoverWaiting(_ data: [String: Any]?) {
        guard own(data) else { return }
        connecting.end()
        clearNudge()
        settle(.unavailable)
        signals.emit(.waitingForHuman, HandoverWait.waitingDetail(data))
    }

    func onNoAgentsAvailable() {
        settle(.unavailable)
        waitOver("unavailable")
    }

    /// chat-ended or ai-agent-inactive-close: a wait still going ends with the chat.
    func onChatEnded(_ data: [String: Any]?) {
        guard own(data) else { return }
        let waiting = inWait
        settle(.ended)
        if waiting { waitOver("ended") } else { clearNudge() }
    }

    /// Left the queue from another device of this chat.
    func onQueueLeft(_ data: [String: Any]?) {
        guard own(data), data?["reason"] as? String == "self_service" else { return }
        if hooks.engine()?.isAtHandover == true && hooks.waitingForPerson() { leftQueue() }
    }

    func setupListeners(on socket: SocketClient) {
        socket.on(SocketEvents.handoverWaiting) { [weak self] data, _ in
            let d = data.first as? [String: Any]
            DispatchQueue.main.async { self?.onHandoverWaiting(d) }
        }
        socket.on(SocketEvents.queueLeft) { [weak self] data, _ in
            let d = data.first as? [String: Any]
            DispatchQueue.main.async { self?.onQueueLeft(d) }
        }
    }

    // MARK: - Leaving the queue (#34)

    /// Out of the queue: the line, the record, the signal, the flow moves on.
    private func leftQueue() {
        waitOver("cancelled")
        settle(.cancelled)
        let id = Self.entryId("queue-self-resolved")
        let text = HandoverState.text(.cancelled)
        add(SystemMessageRecord(id: id, time: Date(), text: text),
            server: ["id": id, "_id": id, "type": "queue-self-resolved", "time": Self.now(), "text": text])
        hooks.save()
        if let engine = hooks.engine(), engine.isAtHandover {
            Task { @MainActor in await engine.continueAfterHandover() }
        }
    }

    /// The visitor leaves the queue (the wait card's Cancel):
    /// queue-self-resolve, as the web widget does, so the team stops seeing
    /// them waiting. `done(false)` when a person already picked the chat up
    /// (they stay). Main thread.
    public func leaveQueue(_ done: @escaping (Bool) -> Void = { _ in }) {
        let sid = hooks.sessionId() ?? ""
        hooks.emitWithAck(SocketEvents.queueSelfResolve, HandoverState.queueSelfResolvePayload(sid), 8) { [weak self] res in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let answer = res as? [String: Any]
                let finish = { (state: [String: Any]?) in
                    if HandoverState.queueLeaveResult(answer, state: state) == .stay { return done(false) }
                    self.leftQueue()
                    done(true)
                }
                // not_waiting: no queued ticket - or a person just took it (in progress).
                guard HandoverState.queueLeaveNeedsState(answer) else { return finish(nil) }
                self.hooks.emitWithAck(SocketEvents.liveChatState, ["chatSessionId": sid], 8) { state in
                    DispatchQueue.main.async { finish(state as? [String: Any]) }
                }
            }
        }
    }

    // MARK: - Restore (#22)

    /// Lines whose outcome the record knows are drawn settled, and a
    /// person's join after an AI handover gets its note.
    func annotateRestored() {
        let state = hooks.chatState()
        let annotated = HandoverState.annotateRestored(state.getServerRecord())
        guard annotated.changed > 0 else { return }
        state.setServerRecord(annotated.record)
        var byId: [String: [String: Any]] = [:]
        for e in annotated.record { if let id = e["id"] as? String { byId[id] = e } }
        hooks.setMessages(hooks.messages().map { item in
            if let line = item as? AgentLeftMessageRecord, line.isPendingHandover,
               let s = (byId[line.id]?["settled"] as? String).flatMap(HandoverOutcome.init(rawValue:)) {
                return line.settling(s)
            }
            if let join = item as? AgentJoinedMessageRecord, join.afterAI != true, byId[join.id]?["afterAI"] as? Bool == true {
                return AgentJoinedMessageRecord(id: join.id, time: join.time, agentDetails: join.agentDetails, afterAI: true)
            }
            return item
        })
    }

    /// A chat restored from the device: ask the server where its live chat
    /// stands (live-chat-state) and pick it back up - the person and the join
    /// line it missed, still in the queue, or over - instead of running the
    /// flow again. `done` gets what was done; `.start` leaves the chat as any
    /// restored chat. The flow must be loaded already. Main thread.
    func resumeRestored(sessionId: String, nodes: [[String: Any]], agentBot: Bool,
                        done: @escaping (HandoverState.RestoreStep) -> Void = { _ in }) {
        annotateRestored()
        let currentNode = hooks.chatState().currentNodeId
        let handoverNode = agentBot ? nil : nodes.first {
            ($0["id"] as? String) == currentNode && ($0["type"] as? String) == NodeTypes.Special.humanHandover
        }
        let atHandover = handoverNode != nil
        guard HandoverState.restoreNeedsLiveChatState(record, atHandover: atHandover) else { return done(.start) }

        // Back in the room first: the server answers only its own session.
        hooks.joinRoom(sessionId)
        hooks.emitWithAck(SocketEvents.liveChatState, ["chatSessionId": sessionId], 10) { [weak self] res in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let r = HandoverState.restoredLiveChat((res as? [String: Any]) ?? ["status": "none"], record: self.record)
                if let s = r.settle { self.settle(s) }
                let step = HandoverState.restoreStep(r, atHandover: atHandover, record: self.record)
                self.apply(step, r, handoverNode: handoverNode)
                self.hooks.save()
                done(step)
            }
        }
    }

    private func apply(_ step: HandoverState.RestoreStep, _ r: HandoverState.RestoredLiveChat, handoverNode: [String: Any]?) {
        let engine = hooks.engine()
        let nodeId = handoverNode?["id"] as? String
        let nodeData = handoverNode?["data"] as? [String: Any] ?? [:]
        let message = ((nodeData["handoverMessage"] as? String) ?? (nodeData["message"] as? String))
            .map { LiveChat.plainText(hooks.chatState().resolveVariables(text: $0)) }
            .flatMap { $0.isEmpty ? nil : $0 }
        switch step {
        case .live:
            hooks.setLive(true)
            if let p = r.agent {
                let details = AgentDetails(id: p.id, name: p.name, email: p.email ?? "", isAIAgent: false)
                hooks.setAgent(Agent(id: p.id, name: p.name, email: p.email), details)
                if r.drawJoin {
                    addJoin(details, raw: nil, plan: .init(ai: false, outcome: .joined, announce: true, afterAI: r.afterAI, humanJoined: true))
                }
            }
            if r.status == .waiting {
                connecting.start()
                armNudge()
            }
        case .wait:
            if let engine = engine, let id = nodeId {
                Task { @MainActor in engine.waitAt(id, uiState: .humanHandover(message: message)) }
                connecting.start()
            }
        case .continue:
            guard let engine = engine, let id = nodeId else { return }
            // Ended while the app was closed: say so, as the live event would.
            if r.status == .ended {
                let entryId = Self.entryId("chat-ended")
                add(SystemMessageRecord(id: entryId, time: Date(), text: "Chat has ended"),
                    server: ["id": entryId, "_id": entryId, "type": "agent-chat-ended", "time": Self.now()])
            }
            hooks.setLive(false)
            Task { @MainActor in
                if engine.waitAt(id, uiState: .humanHandover(message: message)) { await engine.continueAfterHandover() }
            }
        case .ask:
            if let engine = engine, let id = nodeId {
                Task { @MainActor in await engine.resumeFrom(id) }
            }
        case .start:
            break
        }
    }

    /// A new conversation: nothing is waiting.
    func reset() {
        connecting.end()
        clearNudge()
    }
}
