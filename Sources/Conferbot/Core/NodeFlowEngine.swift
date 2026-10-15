//
//  NodeFlowEngine.swift
//  Conferbot
//
//  Runs a bot flow the way the web widget does. The reference is the shared
//  flow-node spec (conferbot-react-native scripts/parity/flows:
//  nodes.spec.json "engine", made by running conferbot-widget's own code);
//  Tests/FlowFixtureTests.swift runs every fixture through this engine. The
//  React Native SDK's src/core/NodeFlowEngine.ts is the same engine.
//
//  - start: the FIRST welcome-node in nodes[].
//  - next: a step that does not branch leaves by the FIRST edge from it,
//    whatever its handle. No edge, or a target that does not exist: the chat
//    ends.
//  - port: a branching step leaves by an exact handle. No such edge: the chat
//    ends - never another edge. A wired edge to a missing node stops the chat
//    where it is (the web throws). Rich steps may name a fallback handle,
//    taken when only it is wired (web goPort).
//  - unknown step types (and a welcome-node reached mid-flow) show nothing
//    and continue along their first edge on the next tick.
//  - jump: to the target node; a missing target ends the chat.
//  - end: a sub-flow call returns to its caller; otherwise the chat is over
//    ("chat-flow-completed").
//  - pacing: typing dots before each displayed step for paceFor(), unless a
//    fixed typingDelay is configured.
//

import Foundation
import Combine

/// What the engine did, step by step (the flow-node spec's `expect`).
public enum FlowTraceEvent {
    case enter(node: String, type: String, via: String)
    case shown(node: String)
    case port(node: String, handle: String, wired: Bool)
    case unsupported(node: String, type: String)
    case error(node: String, message: String)
    case end
    case crash(node: String, reason: String)
}

/// NodeFlowEngine is the core orchestration engine that processes chatbot flows.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class NodeFlowEngine: ObservableObject {

    /// How the engine runs: its clock, server, socket and the bot's settings.
    public struct Config {
        /// A fixed typing delay (ms) before each displayed step. nil: the web widget's pacing (paceFor).
        public var typingDelay: Double?
        /// Steps run without the visitor before the engine stops (a runaway loop guard).
        public var maxNodesPerCycle = 500
        /// How long one step may take (ms).
        public var nodeProcessingTimeout: Double = 90_000
        /// How long an image or video step waits for its media at most (ms, web: 4000).
        public var mediaAdvanceMs: Double = 4000
        /// The bot server origin for /api/v1/bot/:id/* ("https://embed.conferbot.com").
        public var apiOrigin: String?
        /// The bot's customizations (redactSensitive, chatLeaveMessage...).
        public var customizations: [String: Any] = [:]
        /// The page the chat runs on, when the host app has one (hidden-fields).
        public var page: FlowPage?
        /// The visitor's IANA time zone (default: the device's).
        public var visitorTimeZone: String?
        /// The random source (random-flow).
        public var random: (() -> Double)?
        public var clock: FlowClock = SystemFlowClock()
        public var transport: FlowTransport = URLSessionFlowTransport()
        public var socket: FlowSocket?
        /// Every step entered, port taken, step passed and the end.
        public var onTrace: ((FlowTraceEvent) -> Void)?

        public init() {}
    }

    // MARK: - Published Properties (Reactive State)

    /// The current UI state to render
    @Published public private(set) var currentUIState: NodeUIState?

    /// Indicates whether the engine is currently processing a node
    @Published public private(set) var isProcessing: Bool = false

    /// Current error message, if any
    @Published public private(set) var errorMessage: String?

    /// Indicates whether the flow has completed
    @Published public private(set) var isFlowComplete: Bool = false

    /// The ID of the currently active node
    @Published public private(set) var currentNodeId: String?

    /// The step waits for the visitor.
    @Published public private(set) var isWaitingForInput: Bool = false

    /// The last refused answer: the step and why (also said as a bot line).
    @Published public private(set) var validationError: (nodeId: String, message: String)?

    // MARK: - Steps that draw something / ask

    /// Steps that draw something, after the typing dots (web nodeTypeCategories DISPLAY_NODE_TYPES).
    public static let displayNodeTypes: Set<String> = [
        "two-choices-node", "three-choices-node", "select-option-node", "user-rating-node", "quiz-node", "user-input-node",
        "user-range-node", "welcome-node", "message-node", "image-node", "video-node", "audio-node", "file-node",
        "ask-name-node", "ask-email-node", "ask-phone-number-node", "ask-number-node", "ask-url-node", "ask-file-node",
        "ask-location-node", "ask-custom-question-node", "ask-multiple-questions-node", "calendar-node",
        "n-select-option-node", "n-check-options-node", "n-choices-node", "image-choice-node", "carousel-node",
        "rating-choice-node", "yes-or-no-choice-node", "opinion-scale-choice-node", "user-redirect-node", "html-node",
        "navigate-node", "dynamic-choices-node", "consent-node", "product-card-node", "slider-node", "datetime-node",
        "ranking-node", "otp-node", "address-node", "matrix-node", "ai-extract-node", "ai-route-node", "kb-answer-node",
        "signature-node", "payment-node",
    ]

    /// Question steps that register data.answerVariable when shown (web _nodeCategorizeHelper).
    static let registersAnswer: Set<String> = [
        "ask-name-node", "ask-email-node", "ask-phone-number-node", "ask-number-node", "ask-url-node", "ask-location-node",
        "ask-custom-question-node", "ask-file-node", "calendar-node", "n-select-option-node", "n-check-options-node",
        "n-choices-node", "image-choice-node", "rating-choice-node", "yes-or-no-choice-node", "opinion-scale-choice-node",
        "carousel-node",
        // rich steps (richNodesView categorizeRichNode)
        "dynamic-choices-node", "consent-node", "product-card-node", "slider-node", "datetime-node", "ranking-node",
        "otp-node", "address-node", "matrix-node", "ai-extract-node", "ai-route-node", "kb-answer-node", "signature-node",
        "payment-node",
    ]

    /// Steps that wait for the visitor once drawn.
    public static let waitingNodeTypes: Set<String> = [
        "ask-name-node", "ask-email-node", "ask-phone-number-node", "ask-number-node", "ask-url-node", "ask-location-node",
        "ask-custom-question-node", "ask-file-node", "ask-multiple-questions-node",
        "n-choices-node", "image-choice-node", "rating-choice-node", "yes-or-no-choice-node", "opinion-scale-choice-node",
        "n-select-option-node", "n-check-options-node", "calendar-node",
        // Waits on the team: agent-accepted / no-agents-available move it on
        "human-handover-node",
        "carousel-node", "navigate-node",
        "dynamic-choices-node", "consent-node", "product-card-node", "slider-node", "datetime-node", "ranking-node",
        "otp-node", "address-node", "matrix-node", "ai-extract-node", "ai-route-node", "kb-answer-node", "signature-node",
        "payment-node",
        "user-input-node", "user-range-node", "quiz-node", "two-choices-node", "three-choices-node", "select-option-node",
        "user-rating-node",
    ]

    /// Steps whose media decides when the flow moves on (load, or the cap).
    private static let mediaTypes: Set<String> = ["image-node", "video-node"]

    // MARK: - Private Properties

    private let state: ChatState
    private let registry: NodeHandlerRegistry
    public var config: Config

    private var flow: [String: Any]?
    private var nodes: [[String: Any]] = []
    private var nodesById: [String: [String: Any]] = [:]
    private var edges: [[String: Any]] = []
    private var startNodeId: String?

    private var ended = false
    /// Every step entered, in order (pacing reads the one before).
    private var steps: [[String: Any]] = []
    /// Bumped whenever the flow moves: a stale timer or reply does nothing.
    private var moveToken = 0
    /// The step whose "shown" was already reported for this visit.
    private var shownToken = -1
    /// Media that finished loading: the step moves on before the cap.
    private var mediaWaiters: [String: () -> Void] = [:]
    private var flowControl = FlowControl.State()
    private var nodesProcessedInCycle = 0

    // MARK: - Initialization

    /// Creates a new NodeFlowEngine instance
    /// - Parameters:
    ///   - state: The chat state to use (defaults to shared instance)
    ///   - registry: The handler registry to use (defaults to shared instance)
    ///   - config: Its clock, server, socket and the bot's settings
    public init(state: ChatState = .shared, registry: NodeHandlerRegistry = .shared, config: Config = Config()) {
        self.state = state
        self.registry = registry
        self.config = config
        if config.customizations["redactSensitive"] != nil {
            state.redactSensitive = JS.bool(config.customizations["redactSensitive"]) != false
        }
    }

    /// The bot's customizations (redactSensitive, chatLeaveMessage...).
    public func setCustomizations(_ customizations: [String: Any]?) {
        config.customizations = customizations ?? [:]
        state.redactSensitive = JS.bool(config.customizations["redactSensitive"]) != false
    }

    // MARK: - Flow Loading

    /// Loads a flow definition and prepares the engine for execution
    /// - Parameter flowData: The flow definition dictionary containing nodes and edges
    public func loadFlow(_ flowData: [String: Any]) {
        loadFlow(flowData, keepingState: false)
    }

    /// Loads a flow. `keepingState`: a restored conversation - its answers,
    /// transcript and record stay (the flow is not started again).
    public func loadFlow(_ flowData: [String: Any], keepingState: Bool) {
        flow = flowData
        let nested = flowData["flow"] as? [String: Any]
        nodes = (flowData["nodes"] as? [[String: Any]]) ?? (nested?["nodes"] as? [[String: Any]]) ?? []
        edges = (flowData["edges"] as? [[String: Any]]) ?? (nested?["edges"] as? [[String: Any]]) ?? (flowData["connections"] as? [[String: Any]]) ?? []
        nodesById = [:]
        for node in nodes {
            let id = JS.text(node["id"])
            if !id.isEmpty, nodesById[id] == nil { nodesById[id] = node }
        }
        startNodeId = findStartNode(given: flowData["startNodeId"] as? String)

        moveToken += 1
        currentUIState = nil
        isProcessing = false
        isWaitingForInput = false
        errorMessage = nil
        isFlowComplete = false
        currentNodeId = nil
        resetFlow()
        if !keepingState { state.resetConversation() }
        ConferBotLogger.info("[NodeFlowEngine] Loaded flow with \(nodes.count) nodes and \(edges.count) edges")
    }

    /// The first welcome-node in nodes[] starts the chat (web index.ts
    /// _findAndDisplayNode). A flow without one (a partial flow, a test)
    /// starts at the given start node, else at a node no edge leads to.
    private func findStartNode(given: String?) -> String? {
        if let welcome = nodes.first(where: { JS.text($0["type"]) == "welcome-node" }) { return JS.text(welcome["id"]) }
        if let given = given, nodesById[given] != nil { return given }
        let targets = Set(edges.map { JS.text($0["target"]) })
        if let entry = nodes.first(where: { !targets.contains(JS.text($0["id"])) }) { return JS.text(entry["id"]) }
        return nodes.first.map { JS.text($0["id"]) }
    }

    private func resetFlow() {
        steps = []
        ended = false
        nodesProcessedInCycle = 0
        flowControl = FlowControl.State()
        mediaWaiters = [:]
    }

    // MARK: - Flow Execution

    /// Starts the flow from the beginning (fire and forget).
    public func startFlow() {
        guard !nodes.isEmpty else {
            setError("No nodes loaded in flow")
            return
        }
        Task { @MainActor in await self.start() }
    }

    /// Starts the flow from the beginning and returns once it waits or ends.
    @MainActor
    public func start() async {
        guard let id = startNodeId, let node = nodesById[id] else {
            setError("Could not find start node in flow")
            return
        }
        resetFlow()
        isFlowComplete = false
        clearError()
        await enter(node, via: "start")
    }

    /// Restarts the flow from the beginning
    public func restartFlow() {
        moveToken += 1
        state.resetConversation()
        startFlow()
    }

    /// Runs a node by id (entered as along an edge)
    @MainActor
    public func processNode(_ nodeId: String) async {
        guard let node = nodesById[nodeId] else {
            setError("Node not found: \(nodeId)")
            return
        }
        await enter(node, via: "edge")
    }

    /// The handler registered for a type.
    private func handlerFor(_ type: String) -> NodeHandler? { registry.getHandler(for: type) }

    /// Enter a step: record it, pace it, run its handler.
    @MainActor
    private func enter(_ node: [String: Any], via: String) async {
        if ended { return }
        nodesProcessedInCycle += 1
        let nodeId = JS.text(node["id"])
        let type = JS.text(node["type"])
        if nodesProcessedInCycle > config.maxNodesPerCycle {
            setError("Max nodes per cycle exceeded (\(config.maxNodesPerCycle))")
            isProcessing = false
            return
        }

        moveToken += 1
        let token = moveToken
        currentNodeId = nodeId
        isWaitingForInput = false
        isProcessing = true
        errorMessage = nil
        state.currentNodeId = nodeId
        steps.append(node)
        trace(.enter(node: nodeId, type: type, via: via))

        // The step on the record, with its text as the visitor saw it (web _nodeRecord)
        var entry = node
        entry["_id"] = nodeId
        entry["id"] = nodeId
        entry["type"] = type
        entry["data"] = JS.dict(node["data"])
        if let rendered = FlowText.renderedText(node, { [weak self] in self?.state.lookupVariable($0) }) { entry["renderedText"] = rendered }
        entry["time"] = Flow.iso(config.clock.now())
        state.appendRecord(entry)

        // A welcome reached again is not a display step there: passed.
        if type == "welcome-node" && via != "start" {
            await passUnknown(node, token)
            return
        }
        if FlowControl.types.contains(type) {
            await runFlowControl(node, token)
            return
        }
        guard let handler = handlerFor(type) else {
            await passUnknown(node, token)
            return
        }

        if Self.displayNodeTypes.contains(type) {
            // A message with no text or an image with no picture: straight on.
            if FlowText.isEmptyContentStep(node) {
                await next(node, token)
                return
            }
            registerAnswerVariables(node)
            let previous = steps.count >= 2 ? steps[steps.count - 2] : nil
            let pace = config.typingDelay ?? FlowText.paceFor(previous: previous, next: node, followsBotStep: FlowText.followsAutoAdvanceStep(previous.map { JS.text($0["type"]) }))
            if pace > 0 {
                state.isTyping = true
                await config.clock.sleep(ms: pace)
                state.isTyping = false
                if token != moveToken || ended { return }
            }
            // Drawn now (web: the message sound plays as the step is drawn).
            shownToken = token
            trace(.shown(node: nodeId))
        }

        let result = await runHandler(handler, node, via: via, token: token)
        if token != moveToken || ended { return }
        await handleNodeResult(result, node, token)
    }

    /// A question step registers {nodeId, key, value: null} when shown.
    private func registerAnswerVariables(_ node: [String: Any]) {
        let id = JS.text(node["id"])
        let type = JS.text(node["type"])
        let d = JS.dict(node["data"])
        if type == "ask-multiple-questions-node" {
            for (i, q) in JS.dicts(d["questions"]).enumerated() {
                let key = JS.text(q["answerVariable"])
                if !key.isEmpty { state.registerAnswerVariable(nodeId: "\(id)\(i)", key: key) }
            }
            return
        }
        let key = JS.text(d["answerVariable"])
        if Self.registersAnswer.contains(type), JS.truthy(d["answerVariable"]), !key.isEmpty {
            state.registerAnswerVariable(nodeId: id, key: key)
        }
    }

    /// Runs a step's handler with the engine's context, under the step timeout.
    @MainActor
    private func runHandler(_ handler: NodeHandler, _ node: [String: Any], via: String, token: Int) async -> NodeResult {
        let withCtx = nodeWithContext(node, via: via, token: token)
        let state = self.state
        return await BotApi.race(clock: config.clock, ms: config.nodeProcessingTimeout,
                                 timedOut: .error("Node processing timed out after \(Int(config.nodeProcessingTimeout))ms")) {
            await handler.handle(node: withCtx, state: state)
        }
    }

    @MainActor
    private func nodeWithContext(_ node: [String: Any], via: String, token: Int) -> [String: Any] {
        var n = node
        n["ctx"] = contextFor(node, via: via, token: token)
        return n
    }

    /// The bot server origin for the steps' calls.
    private var apiOrigin: String {
        if let o = config.apiOrigin, !o.isEmpty { return o.replacing("/+$", with: "") }
        return Self.origin(of: ConferBotEndpoints.apiBaseURL)
    }

    /// "https://host/api/v1/mobile" -> "https://host".
    static func origin(of base: String) -> String {
        guard let u = URLComponents(string: base), let scheme = u.scheme, let host = u.host else { return base }
        return "\(scheme)://\(host)\(u.port.map { ":\($0)" } ?? "")"
    }

    /// What a handler may use: the bot API, the socket, timers, this step's edges.
    @MainActor
    private func contextFor(_ node: [String: Any], via: String, token: Int) -> FlowContext {
        let nodeId = JS.text(node["id"])
        let origin = apiOrigin
        let state = self.state
        let transport = config.transport
        let clock = config.clock
        let botId = state.botId
        let sessionId = state.sessionId
        let visitorId = state.visitorId ?? (state.getVariable(name: "_visitorId") as? String) ?? sessionId
        let stepIndex = max(0, steps.lastIndex(where: { JS.text($0["id"]) == nodeId }) ?? 0)
        return FlowContext(
            botId: botId,
            sessionId: sessionId,
            via: via,
            stepIndex: stepIndex,
            customizations: config.customizations,
            visitorTimeZone: config.visitorTimeZone ?? FlowCalendar.visitorTimeZone(),
            page: config.page,
            api: { path, body, timeout in
                await BotApi.post(transport: transport, clock: clock, origin: origin, botId: botId, path: path, body: body, timeoutMs: timeout)
            },
            upload: { file in
                await BotApi.upload(transport: transport, origin: origin, botId: botId, sessionId: sessionId, visitorId: visitorId, file: file)
            },
            send: { request in await transport.send(request) },
            emit: { [weak self] event, payload in self?.emit(event, payload) ?? false },
            on: { [weak self] event, listener in self?.config.socket?.on(event, listener) ?? {} },
            typing: { [weak self] ms in
                guard ms > 0 else { return }
                self?.state.isTyping = true
                await clock.sleep(ms: ms)
                self?.state.isTyping = false
            },
            clock: clock,
            edges: { [weak self] in self?.edgesFrom(nodeId) ?? [] },
            edgesOf: { [weak self] id in self?.edgesFrom(id) ?? [] },
            random: { [weak self] in self?.config.random?() ?? Double.random(in: 0..<1) },
            respond: { [weak self] response in
                guard let self = self, self.currentNodeId == nodeId, self.isWaitingForInput else { return }
                Task { @MainActor in await self.submitResponse(response) }
            },
            shown: { [weak self] in
                guard let self = self, self.shownToken != token, token == self.moveToken else { return }
                self.shownToken = token
                self.trace(.shown(node: nodeId))
            },
            isStale: { [weak self] in
                guard let self = self else { return true }
                return token != self.moveToken && self.currentNodeId != nodeId
            },
            node: { [weak self] id in self?.nodesById[id] }
        )
    }

    private func edgesFrom(_ nodeId: String) -> [[String: Any]] {
        edges.filter { JS.text($0["source"]) == nodeId }
    }

    /// Handles the result of processing a node
    @MainActor
    private func handleNodeResult(_ result: NodeResult, _ node: [String: Any], _ token: Int) async {
        switch result {
        case .displayUI(let ui):
            await handleDisplayUI(ui, node, token)
        case .proceed(let nextNodeId, let data):
            await handleProceed(nextNodeId, data, node, token)
        case .delayedProceed(let seconds, let nextNodeId):
            isProcessing = true
            await config.clock.sleep(ms: seconds * 1000)
            if token != moveToken || ended { return }
            await handleProceed(nextNodeId, nil, node, token)
        case .jumpTo(let target):
            sendResponseToServer()
            await jump(target, token)
        case .port(let handle, let fallback):
            isProcessing = false
            sendResponseToServer()
            await port(node, handle, fallback: fallback, token)
        case .invalid(let message, let ui, let inCard):
            await handleInvalid(message, node, token, ui: ui, inCard: inCard)
        case .end:
            await end("completed")
        case .error(let message):
            setError(message)
            isProcessing = false
        }
    }

    @MainActor
    private func handleDisplayUI(_ ui: NodeUIState, _ node: [String: Any], _ token: Int) async {
        let nodeId = JS.text(node["id"])
        let type = JS.text(node["type"])
        currentUIState = ui
        isProcessing = false
        state.isTyping = false
        if shownToken != token && Self.displayNodeTypes.contains(type) {
            shownToken = token
            trace(.shown(node: nodeId))
        }
        if Self.waitingNodeTypes.contains(type) {
            isWaitingForInput = true
            return
        }
        // Shown and moving on by itself
        sendResponseToServer()
        if Self.mediaTypes.contains(type) {
            await waitForMedia(nodeId, capMs: config.mediaAdvanceMs)
            if token != moveToken || ended { return }
        }
        await next(node, token)
    }

    /// Resolves when the media loads (mediaSettled) or after `capMs`.
    @MainActor
    private func waitForMedia(_ nodeId: String, capMs: Double) async {
        let once = FlowOnce<Void>()
        let timer = config.clock.schedule(ms: capMs, repeats: false) { once.resume(()) }
        mediaWaiters[nodeId] = { once.resume(()) }
        await once.value()
        timer.cancel()
        mediaWaiters[nodeId] = nil
    }

    /// An image or video step's media loaded (or failed): the flow moves on
    /// now instead of at the cap (web: load / loadedmetadata / error).
    public func mediaSettled(nodeId: String) {
        DispatchQueue.main.async { self.mediaWaiters[nodeId]?() }
    }

    @MainActor
    private func handleProceed(_ nextNodeId: String?, _ data: [String: Any]?, _ node: [String: Any], _ token: Int) async {
        isProcessing = false
        if JS.truthy(data?["flowComplete"]) {
            await end(JS.text(data?["completionStatus"]).isEmpty ? "completed" : JS.text(data?["completionStatus"]))
            return
        }
        sendResponseToServer()
        // Legacy port hints (_port / __targetPort) from older custom handlers
        let hint = (data?["_port"] as? String) ?? (data?["__targetPort"] as? String)
        if let id = nextNodeId, id.hasPrefix("__port:") {
            await port(node, String(id.dropFirst(7)), fallback: data?["fallbackPort"] as? String, token)
        } else if let id = nextNodeId {
            await jump(id, token)
        } else if let hint = hint {
            await port(node, hint, fallback: nil, token)
        } else {
            await next(node, token)
        }
    }

    // MARK: - Routing

    /// The FIRST edge from the step, whatever its handle; none ends the chat.
    @MainActor
    private func next(_ node: [String: Any], _ token: Int) async {
        if ended || token != moveToken { return }
        let nodeId = JS.text(node["id"])
        let edge = edges.first { JS.text($0["source"]) == nodeId }
        if let edge = edge { appendEdgeRecord(edge) }
        if let edge = edge, let target = nodesById[JS.text(edge["target"])] {
            let handle = JS.text(edge["sourceHandle"])
            await enter(target, via: handle.isEmpty ? "edge" : "edge:\(handle)")
        } else {
            await end("no_next_node")
        }
    }

    /// The edge from exactly this handle; none ends the chat.
    @MainActor
    private func port(_ node: [String: Any], _ handle: String, fallback: String?, _ token: Int) async {
        if ended || token != moveToken { return }
        let nodeId = JS.text(node["id"])
        func wired(_ h: String) -> Bool { edges.contains { JS.text($0["source"]) == nodeId && ($0["sourceHandle"] as? String) == h } }
        let h = (fallback.map { !wired(handle) && wired($0) } ?? false) ? fallback! : handle
        let edge = edges.first { JS.text($0["source"]) == nodeId && ($0["sourceHandle"] as? String) == h }
        trace(.port(node: nodeId, handle: h, wired: edge != nil))
        guard let found = edge else {
            await end("no_next_node")
            return
        }
        appendEdgeRecord(found)
        guard let target = nodesById[JS.text(found["target"])] else {
            // The web throws on nextNode.type here: the chat stops where it is.
            trace(.crash(node: nodeId, reason: "edge target missing"))
            isProcessing = false
            isWaitingForInput = false
            setError("Edge \(JS.text(found["id"])) leads to a missing node (\(JS.text(found["target"])))")
            return
        }
        await enter(target, via: "port:\(h)")
    }

    /// To a node by id; a missing target ends the chat.
    @MainActor
    private func jump(_ targetNodeId: String, _ token: Int) async {
        if ended || token != moveToken { return }
        guard !targetNodeId.isEmpty, let target = nodesById[targetNodeId] else {
            await end("jump_target_missing")
            return
        }
        await enter(target, via: "jump")
    }

    /// A step type this engine does not run: nothing shown, then its first edge.
    @MainActor
    private func passUnknown(_ node: [String: Any], _ token: Int) async {
        ConferBotLogger.warning("[ConferBot] step \"\(JS.text(node["type"]))\" is not supported here; continuing the flow")
        trace(.unsupported(node: JS.text(node["id"]), type: JS.text(node["type"])))
        await config.clock.sleep(ms: 0)
        if token != moveToken || ended { return }
        await next(node, token)
    }

    private func appendEdgeRecord(_ edge: [String: Any]) {
        var e = edge
        e["_id"] = edge["id"] ?? NSNull()
        e["time"] = Flow.iso(config.clock.now())
        state.appendRecord(e)
    }

    // MARK: - Loops and sub-flows (web flowControlRun.ts)

    private func flowLookup(_ key: String) -> Any? { state.lookupVariable(key) }

    private func setVars(_ vars: [(String, Any)]) {
        for (k, v) in vars { state.saveVariableByName(k, value: v) }
    }

    /// A trail entry on the step's latest record ("Loop 3 of 5").
    private func trail(_ node: [String: Any], _ extra: [String: Any]) {
        let nodeId = JS.text(node["id"])
        let type = JS.text(node["type"])
        let record = state.getServerRecord()
        guard var r = record.last(where: { JS.text($0["id"]) == nodeId && JS.text($0["type"]) == type && $0["shape"] == nil }) else { return }
        for (k, v) in extra { r[k] = v }
        state.addRecord(r)
    }

    @MainActor
    private func runFlowControl(_ node: [String: Any], _ token: Int) async {
        let d = JS.dict(node["data"])
        let nodeId = JS.text(node["id"])
        switch JS.text(node["type"]) {
        case FlowControl.loopType:
            let step = FlowControl.stepLoop(nodeId, d, &flowControl) { [weak self] in self?.flowLookup($0) }
            setVars(step.vars)
            var t = step.trail
            t["text"] = step.trailText
            trail(node, ["loop": t])
            sendResponseToServer()
            await config.clock.sleep(ms: 0)
            if token != moveToken || ended { return }
            await port(node, step.handle, fallback: nil, token)
        case FlowControl.runSubflowType:
            let call = FlowControl.callSubflow(node, nodes, &flowControl) { [weak self] in self?.flowLookup($0) }
            if !call.ok {
                trail(node, ["subflow": ["name": call.name ?? "", "error": call.error ?? ""]])
                sendResponseToServer()
                await config.clock.sleep(ms: 0)
                if token != moveToken || ended { return }
                let wiredError = edges.contains { JS.text($0["source"]) == nodeId && ($0["sourceHandle"] as? String) == FlowControl.runErrorHandle }
                await port(node, wiredError ? FlowControl.runErrorHandle : "source", fallback: nil, token)
                return
            }
            setVars(call.vars)
            var inputs: [String: Any] = [:]
            for (k, v) in call.vars { inputs[k] = v }
            trail(node, ["subflow": ["name": call.name ?? "", "inputs": inputs, "depth": call.frame?.depth ?? 1, "text": "Ran sub-flow \(call.name ?? "")"]])
            sendResponseToServer()
            await config.clock.sleep(ms: 0)
            if token != moveToken || ended { return }
            await jump(call.startId ?? "", token)
        case FlowControl.subflowType:
            trail(node, ["subflow": ["name": FlowControl.subflowName(node), "entered": true]])
            await config.clock.sleep(ms: 0)
            if token != moveToken || ended { return }
            await port(node, "source", fallback: nil, token)
        case FlowControl.subflowReturnType:
            if await returnFromSubflowPath(token) { return }
            await config.clock.sleep(ms: 0)
            if token != moveToken || ended { return }
            await next(node, token)
        default:
            break
        }
    }

    /// The end of a path inside a sub-flow: copy the outputs back and carry
    /// on from Run sub-flow's "source" edge (or one with no handle). True
    /// when it carried on.
    @MainActor
    private func returnFromSubflowPath(_ token: Int) async -> Bool {
        var ret = FlowControl.returnFromSubflow(&flowControl) { [weak self] in self?.flowLookup($0) }
        while let r = ret {
            setVars(r.vars)
            let runNodeId = r.frame.runNodeId
            let edge = edges.first { e in
                JS.text(e["source"]) == runNodeId && ((e["sourceHandle"] as? String) == "source" || JS.isNullish(e["sourceHandle"]) || (e["sourceHandle"] as? String) == "")
            }
            if let target = edge.map({ JS.text($0["target"]) }), !target.isEmpty {
                sendResponseToServer()
                await config.clock.sleep(ms: 0)
                if token != moveToken || ended { return true }
                await jump(target, token)
                return true
            }
            ret = FlowControl.returnFromSubflow(&flowControl) { [weak self] in self?.flowLookup($0) }
        }
        return false
    }

    // MARK: - User Input Handling

    /// The visitor's answer to the step waiting for one: typed text
    /// (String), a picked button (["buttonId": id]), a value (["value": 3]),
    /// a file (["file": [...]]), or a rich step's action.
    @MainActor
    public func submitResponse(_ response: Any) async {
        guard isWaitingForInput, let nodeId = currentNodeId else { return }
        // Typed text is trimmed; an empty send is ignored (web composer).
        if let s = response as? String, s.trimmed.isEmpty { return }
        guard let node = nodesById[nodeId] else {
            setError("Current node not found: \(nodeId)")
            return
        }
        guard let handler = handlerFor(JS.text(node["type"])) else {
            setError("Handler not found for: \(JS.text(node["type"]))")
            return
        }
        isWaitingForInput = false
        isProcessing = true
        validationError = nil
        nodesProcessedInCycle = 0
        let token = moveToken
        let withCtx = nodeWithContext(node, via: "edge", token: token)
        let result = await handler.handleResponse(response, node: withCtx, state: state) ?? .next
        if token != moveToken || ended { return }
        sendResponseToServer()
        await handleNodeResult(result, node, token)
    }

    /// A refused answer: say why, keep waiting at the step. A typed answer's
    /// reason comes as a bot line after 700 ms of typing (web helpers
    /// _displayErrorMessage); a card's at once (this SDK has no cards for
    /// them, so it is a bot line too).
    @MainActor
    private func handleInvalid(_ message: String, _ node: [String: Any], _ token: Int, ui: NodeUIState?, inCard: Bool) async {
        let nodeId = JS.text(node["id"])
        trace(.error(node: nodeId, message: message))
        isProcessing = false
        if !message.isEmpty && !inCard {
            state.isTyping = true
            await config.clock.sleep(ms: 700)
            state.isTyping = false
            if token != moveToken || ended { return }
        }
        if !message.isEmpty {
            state.addBotEntry(text: FlowText.bubbleText(message), html: message, nodeId: nodeId, nodeType: "validation-error")
        }
        validationError = (nodeId, FlowText.plainText(message))
        if let ui = ui { currentUIState = ui }
        isWaitingForInput = true
    }

    /// Handles user input for a specific node (typed text, a rating, a date...).
    @MainActor
    public func handleUserInput(_ input: Any, forNodeId nodeId: String) async {
        guard currentNodeId == nodeId else { return }
        await submitResponse(input)
    }

    /// Handles button click input
    @MainActor
    public func handleButtonClick(buttonId: String, forNodeId nodeId: String) async {
        guard currentNodeId == nodeId else { return }
        await submitResponse(["buttonId": buttonId])
    }

    /// Handles choice selection input
    @MainActor
    public func handleChoiceSelection(optionId: String, forNodeId nodeId: String) async {
        guard currentNodeId == nodeId else { return }
        await submitResponse(["buttonId": optionId])
    }

    /// Several options ticked (n-check-options), or a ranking's order.
    @MainActor
    public func handleMultipleChoice(optionIds: [String], forNodeId nodeId: String) async {
        guard currentNodeId == nodeId else { return }
        await submitResponse(["buttonIds": optionIds, "order": optionIds])
    }

    // MARK: - Human Handover

    /// Whether the flow is waiting on its handover step.
    public var isAtHandover: Bool {
        guard let id = currentNodeId, let node = nodesById[id] else { return false }
        return JS.text(node["type"]) == NodeTypes.Special.humanHandover
    }

    /// The handover step's data while the flow waits on it (its max wait, assignment).
    public var handoverNodeData: [String: Any]? {
        guard isAtHandover, let id = currentNodeId, let node = nodesById[id] else { return nil }
        return node["data"] as? [String: Any]
    }

    /// A person (or the AI) took the chat: the handover step's waiting card
    /// goes; the conversation is live from here.
    @MainActor
    public func handoverAccepted() {
        if case .humanHandover = currentUIState { currentUIState = nil }
    }

    /// A restored chat that was waiting on a step (a handover still in the
    /// queue): back on that step showing `uiState`, without running the step
    /// again - a second run would ask the server for a person a second time.
    /// False when the step is not in the flow.
    @MainActor
    @discardableResult
    public func waitAt(_ nodeId: String, uiState: NodeUIState) -> Bool {
        guard nodesById[nodeId] != nil else { return false }
        currentNodeId = nodeId
        state.currentNodeId = nodeId
        isProcessing = false
        isWaitingForInput = true
        state.isTyping = false
        currentUIState = uiState
        return true
    }

    /// Run a step again (a restored chat whose handover request never went out).
    @MainActor
    public func resumeFrom(_ nodeId: String) async {
        guard let node = nodesById[nodeId] else { return }
        nodesProcessedInCycle = 0
        ended = false
        await enter(node, via: "edge")
    }

    /// The handover is over (nobody was available, the visitor left a
    /// message or skipped it, or the chat ended): the flow carries on from
    /// the handover step, as the web widget does.
    @MainActor
    public func continueAfterHandover() async {
        guard isAtHandover else { return }
        if !isWaitingForInput { isWaitingForInput = true }
        await submitResponse(["action": "continue"])
    }

    // MARK: - Server communication

    private func emit(_ event: String, _ payload: [String: Any]) -> Bool {
        guard let socket = config.socket, socket.isConnected else { return false }
        socket.emit(event, payload)
        return true
    }

    /// The conversation's record to the server (web response-record).
    private func sendResponseToServer() {
        guard let socket = config.socket else { return }
        let sessionId = state.sessionId
        // Never without a session id: the server would file it under a shared record.
        guard !sessionId.isEmpty else { return }
        socket.sendResponseRecord(state.buildResponseData(chatSessionId: sessionId, botId: state.botId))
    }

    // MARK: - The end

    /// The end of a path: a sub-flow returns to its caller; otherwise the
    /// chat is over (web index.ts: hasChatEnded, record sent, chat-flow-completed).
    @MainActor
    private func end(_ reason: String) async {
        if ended { return }
        if !flowControl.stack.isEmpty, await returnFromSubflowPath(moveToken) { return }
        if ended { return }
        ended = true
        isProcessing = false
        isWaitingForInput = false
        state.isTyping = false
        currentUIState = nil
        state.markConversationComplete(reason: reason)
        state.updateRecord(["completed": true, "completedAt": Flow.iso(config.clock.now()), "finalNodeId": currentNodeId ?? ""])
        sendResponseToServer()
        _ = emit("chat-flow-completed", ["chatSessionId": state.sessionId])
        trace(.end)
        isFlowComplete = true
        ConferBotLogger.info("[NodeFlowEngine] Flow completed (\(reason))")
    }

    /// Whether the chat has ended (the flow reached its end).
    public var isEnded: Bool { ended }

    private func trace(_ event: FlowTraceEvent) {
        config.onTrace?(event)
    }

    // MARK: - Edge Routing (lookup helpers)

    /// The next node: with no port, along the step's FIRST edge (whatever
    /// its handle); with a port, along exactly that handle. nil: none.
    public func getNextNodeId(from currentNodeId: String, port: String? = nil) -> String? {
        let out = edgesFrom(currentNodeId)
        let edge: [String: Any]?
        if let p = port { edge = out.first { ($0["sourceHandle"] as? String) == p } } else { edge = out.first }
        return edge?["target"] as? String
    }

    /// Gets all outgoing edges from a node
    public func getOutgoingEdges(from nodeId: String) -> [[String: Any]] {
        edgesFrom(nodeId)
    }

    // MARK: - Error Handling

    private func setError(_ message: String) {
        errorMessage = message
        ConferBotLogger.error("[NodeFlowEngine] \(message)")
    }

    private func clearError() {
        errorMessage = nil
    }

    // MARK: - Flow Information

    /// Returns the total number of nodes in the flow
    public var nodeCount: Int { nodes.count }

    /// Returns the total number of edges in the flow
    public var edgeCount: Int { edges.count }

    /// Returns all node IDs in the flow
    public var allNodeIds: [String] { nodes.compactMap { $0["id"] as? String } }

    /// Checks if the flow has been loaded
    public var isFlowLoaded: Bool { flow != nil && !nodes.isEmpty }

    /// A node of the loaded flow by id.
    public func getNode(_ nodeId: String) -> [String: Any]? { nodesById[nodeId] }

    /// Gets information about a specific node
    public func getNodeInfo(_ nodeId: String) -> [String: Any]? {
        guard let node = nodesById[nodeId] else { return nil }
        return [
            "id": node["id"] as? String ?? "unknown",
            "type": node["type"] as? String ?? "unknown",
            "data": node["data"] as? [String: Any] ?? [:],
            "outgoingEdges": edgesFrom(nodeId).count,
        ]
    }
}

// MARK: - Publisher Extensions

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension NodeFlowEngine {

    /// Publisher for UI state changes
    var uiStatePublisher: AnyPublisher<NodeUIState?, Never> {
        $currentUIState.eraseToAnyPublisher()
    }

    /// Publisher for processing state changes
    var processingPublisher: AnyPublisher<Bool, Never> {
        $isProcessing.eraseToAnyPublisher()
    }

    /// Publisher for error messages
    var errorPublisher: AnyPublisher<String?, Never> {
        $errorMessage.eraseToAnyPublisher()
    }

    /// Publisher for flow completion
    var completionPublisher: AnyPublisher<Bool, Never> {
        $isFlowComplete.eraseToAnyPublisher()
    }

    /// Publisher for current node ID changes
    var currentNodePublisher: AnyPublisher<String?, Never> {
        $currentNodeId.eraseToAnyPublisher()
    }
}

// MARK: - Debugging Extensions

#if DEBUG
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension NodeFlowEngine {

    /// Prints the current flow structure for debugging
    func debugPrintFlow() {
        print("=== Flow Debug Info ===")
        print("Nodes: \(nodeCount)")
        for id in allNodeIds {
            print("  - \(id) (type: \(getNode(id)?["type"] as? String ?? "unknown"))")
        }
        print("Current Node: \(currentNodeId ?? "none"), complete: \(isFlowComplete)")
    }

    /// Manually sets the current node for testing
    func debugSetCurrentNode(_ nodeId: String) {
        currentNodeId = nodeId
    }

    /// Manually triggers flow completion for testing
    func debugCompleteFlow() {
        isFlowComplete = true
        currentUIState = NodeUIState.none
    }
}
#endif
