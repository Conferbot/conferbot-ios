//
//  IntegrationNodeHandlers.swift
//  Conferbot
//
//  The integration steps, as the web widget runs them (conferbot-widget
//  ts/chat/handlers/integrations.ts, gptRequest.ts, special.ts,
//  resultPaths.ts) and the flow-node spec checks them; the React Native
//  SDK's IntegrationNodeHandlers.ts is the same port.
//
//  - The server runs the native integrations (gmail, sheets, hubspot,
//    slack...): the step's data goes out as "execute-integration" with the
//    step's own id, and the flow does not wait - except google-meet, a
//    google-calendar "book", stripe and the result steps (mailchimp,
//    segment, salesforce), which wait for "integration-result" (30 s at most).
//  - gpt-node asks the server (POST /api/v1/bot/:id/gpt): the owner's key
//    stays on the server.
//  - email-node and zapier-node are relayed through the server's socket.
//  - stripe-node shows the payment link and moves on 500 ms later; it is not
//    a gate (payment-node is).
//

import Foundation

/// The transcript as the server reads it: [{by, message}].
@MainActor
private func transcriptOf(_ state: ChatState, last: Int? = nil) -> [[String: Any]] {
    let list: [[String: Any]] = state.getTranscript().compactMap { e in
        let type = JS.text(e["type"])
        guard type == "bot" || type == "user" else { return nil }
        let text = JS.text(e["html"]).isEmpty ? JS.text(e["message"]) : JS.text(e["html"])
        return text.trimmed.isEmpty ? nil : ["by": type, "message": text]
    }
    guard let n = last, list.count > n else { return list }
    return Array(list.suffix(n))
}

/// The step's data as the server wants it (no client-only keys).
private func serverData(_ node: [String: Any]) -> [String: Any] {
    var d = FlowKit.data(node)
    d.removeValue(forKey: "socketClient")
    return d
}

// MARK: - Server-run integrations

/// Runs a step on the embed server: emits "execute-integration" with the
/// step's own data and resolves with the "integration-result" for this
/// step, or a failure after 30 s. On success, result.answerVariable =
/// answerValue and every columnMappedValues entry are saved by name (web
/// _executeNativeIntegration).
@MainActor
func executeNativeIntegration(_ ctx: FlowContext, _ state: ChatState, nodeType: String, nodeId: String, data: [String: Any], timeoutMs: Double = 30_000) async -> [String: Any] {
    let once = FlowOnce<[String: Any]>()
    var off: () -> Void = {}
    off = ctx.on("integration-result") { result in
        guard JS.text(result["nodeId"]) == nodeId else { return }
        if JS.truthy(result["success"]) {
            let key = JS.text(result["answerVariable"])
            if !key.isEmpty, result["answerValue"] != nil { state.saveVariableByName(key, value: result["answerValue"]) }
            for (name, value) in JS.dict(result["columnMappedValues"]) where !name.isEmpty {
                state.saveVariableByName(name, value: value)
            }
        }
        once.resume(result)
    }
    let sent = ctx.emit("execute-integration", [
        "nodeType": nodeType,
        "nodeId": nodeId,
        "nodeData": data,
        "chatSessionId": state.sessionId,
        "chatbotId": state.botId,
        "workspaceId": state.workspaceId ?? (state.getVariable(name: "_workspaceId") as? String) ?? "",
        "answerVariables": state.getAnswerVariablesList(),
        "visitorData": [String: Any](),
    ])
    if !sent {
        off()
        return ["success": false, "error": "Socket not connected"]
    }
    let timer = ctx.schedule(timeoutMs) { once.resume(["success": false, "error": "Integration execution timed out", "continueFlow": true]) }
    let result = await once.value()
    timer.cancel()
    off()
    return result
}

/// A server-run integration that does not hold the flow (gmail, google
/// sheets / docs / drive, slack, discord, airtable, hubspot, notion,
/// zohocrm): the step data goes to the server and the flow moves on at
/// once; values that come back later fill variables.
public class NativeIntegrationHandler: BaseNodeHandler {
    private let type: String
    public override var nodeType: String { type }

    public init(_ nodeType: String) {
        type = nodeType
        super.init()
    }

    /// The node type the server runs (google-sheets runs as its read / write node).
    func serverType(_ data: [String: Any]) -> String { type }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = serverData(node)
        let nodeId = FlowKit.id(node)
        let ctx = ctxOf(node, state)
        let shape = type
        let serverType = self.serverType(data)
        Task { @MainActor in
            let result = await executeNativeIntegration(ctx, state, nodeType: serverType, nodeId: nodeId, data: data)
            state.addRecord(["_id": nodeId, "id": nodeId, "shape": shape, "data": ["result": ["success": JS.truthy(result["success"]), "error": result["error"] ?? NSNull()]], "time": Flow.iso(Date())])
        }
        return .next
    }
}

/// google-sheets-node: runs on the server as google-sheets-read-node or -write-node (data.operation).
public final class GoogleSheetsNodeHandler: NativeIntegrationHandler {
    public init() { super.init("google-sheets-node") }

    override func serverType(_ data: [String: Any]) -> String {
        let op = JS.text(data["operation"]).isEmpty ? JS.text(JS.dict(data["inputs"])["operation"]) : JS.text(data["operation"])
        return op == "write" ? "google-sheets-write-node" : "google-sheets-read-node"
    }
}

/// google-calendar-node: an operation other than "book" runs in the
/// background and the flow moves on at once; "book" waits for the server
/// (the web's slot picker is web-only) and then moves on.
public final class GoogleCalendarNodeHandler: NativeIntegrationHandler {
    public init() { super.init("google-calendar-node") }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = serverData(node)
        if (JS.text(data["operation"]).isEmpty ? "list" : JS.text(data["operation"])) != "book" { return await super.handle(node: node, state: state) }
        _ = await executeNativeIntegration(ctxOf(node, state), state, nodeType: nodeType, nodeId: FlowKit.id(node), data: data)
        return .next
    }
}

/// google-meet-node: waits for the server's result (30 s at most), then the first edge.
public final class GoogleMeetNodeHandler: NativeIntegrationHandler {
    public init() { super.init("google-meet-node") }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = serverData(node)
        let nodeId = FlowKit.id(node)
        let result = await executeNativeIntegration(ctxOf(node, state), state, nodeType: nodeType, nodeId: nodeId, data: data)
        if JS.truthy(result["success"]) && !JS.truthy(result["waitForInput"]) {
            let r = JS.dict(result["data"])
            state.addRecord(["_id": nodeId, "id": nodeId, "shape": "google-meet-node", "data": [
                "summary": data["summary"] ?? NSNull(),
                "meetingUri": r["meetingUri"] ?? NSNull(),
                "eventLink": r["eventLink"] ?? NSNull(),
                "booking": r["booking"] ?? NSNull(),
                "result": ["success": true, "error": NSNull()],
            ], "time": Flow.iso(Date())])
        }
        return .next
    }
}

/// stripe-node: the server makes the payment link; it is shown and the flow
/// moves on 500 ms later. It never waits for the payment (payment-node does) (#53).
public final class StripeNodeHandler: NativeIntegrationHandler {
    public init() { super.init("stripe-node") }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = serverData(node)
        let nodeId = FlowKit.id(node)
        let operation = JS.text(data["operation"]).isEmpty ? "createPaymentLink" : JS.text(data["operation"])
        let result = await executeNativeIntegration(ctxOf(node, state), state, nodeType: nodeType, nodeId: nodeId, data: data)
        let r = JS.dict(result["data"])
        state.addRecord(["_id": nodeId, "id": nodeId, "shape": "stripe-node", "data": [
            "operation": operation,
            "url": r["url"] ?? NSNull(),
            "id": r["id"] ?? NSNull(),
            "customerId": r["customerId"] ?? NSNull(),
            "message": result["message"] ?? NSNull(),
            "result": ["success": JS.truthy(result["success"]), "error": result["error"] ?? NSNull()],
        ], "time": Flow.iso(Date())])
        let url = JS.text(r["url"])
        if JS.truthy(result["success"]) && !url.isEmpty {
            if operation == "createPaymentLink" || operation == "createCheckoutSession" {
                let text = [JS.text(result["message"]), url].filter { !$0.isEmpty }.joined(separator: "\n")
                FlowKit.botSay(state, text: text, nodeId: nodeId, nodeType: nodeType, data: ["linkUrl": url])
            }
            return .delayedProceed(0.5, nil)
        }
        return .next
    }
}

/// mailchimp / segment / salesforce: the flow waits for the server, then
/// success leaves by "source" (or an edge with no handle), failure by
/// "source-failure" - or the success edge when no failure edge is drawn.
public final class ResultIntegrationHandler: NativeIntegrationHandler {
    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let ctx = ctxOf(node, state)
        let result = await executeNativeIntegration(ctx, state, nodeType: nodeType, nodeId: FlowKit.id(node), data: serverData(node))
        let outgoing = ctx.edges()
        func isSuccess(_ e: [String: Any]) -> Bool { (e["sourceHandle"] as? String) == "source" || JS.isNullish(e["sourceHandle"]) }
        let success = outgoing.first(where: isSuccess)
        let edge = JS.truthy(result["success"]) ? success : (outgoing.first { ($0["sourceHandle"] as? String) == "source-failure" } ?? success)
        guard let e = edge else { return .next }
        if JS.isNullish(e["sourceHandle"]) { return .jumpTo(JS.text(e["target"])) }
        return .port(JS.text(e["sourceHandle"]))
    }
}

// MARK: - GPT

/// gpt-node: the server makes the AI call with the owner's key (it strips
/// apiKey from every flow it sends): POST {api}/api/v1/bot/:botId/gpt with
/// {nodeId, transcript (last 30 {by, message})} -> {reply}. The reply is
/// shown after 1000 ms of typing; a failed call shows nothing. Either way
/// the flow moves on along the first edge (web gptRequest.ts) (#26).
public final class GPTNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "gpt-node" }
    static let maxTurns = 30

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let nodeId = FlowKit.id(node)
        let ctx = ctxOf(node, state)
        let reply = await ctx.api("gpt", ["nodeId": nodeId, "transcript": transcriptOf(state, last: Self.maxTurns)])
        let text = reply.ok ? JS.text(JS.dict(reply.body)["reply"]) : ""
        if text.isEmpty {
            state.setVariable(name: "_gptSuccess", value: false)
            state.setVariable(name: "_gptError", value: reply.error ?? "HTTP \(reply.status)")
            return .next
        }
        state.addRecord(["_id": nodeId, "id": nodeId, "shape": "gpt-node-response", "value": text, "time": Flow.iso(Date())])
        await ctx.typing(1000)
        FlowKit.botSay(state, text: text, nodeId: nodeId, nodeType: nodeType)
        state.setVariable(name: "_gptSuccess", value: true)
        return .next
    }
}

// MARK: - Human handover

/// human-handover-node: the builder's pre-chat questions first (each after
/// 2000 ms of typing, an e-mail or phone checked), then handoverMessage
/// after 1000 ms and "initiate-handover" with the step's settings. The flow
/// waits on the step: a person or the AI takes the chat (agent-accepted),
/// or nobody is free - the owner's fallbackMessage, then the flow carries
/// on (with "leave a message" off; otherwise once it is sent or skipped).
/// When the live chat ends (["action": "ended"], the chat-ended event) the
/// step's post-chat survey questions are asked, as typed questions, when it
/// has them, then the flow carries on (web agentListeners.ts onChatEnded).
/// Answers: typed pre-chat and post-chat answers, ["action": "continue" |
/// "cancel" | "endChat" | "ended" | "surveySubmit" | "surveySkip"].
public final class HumanHandoverNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Special.humanHandover }

    private func preKey(_ nodeId: String) -> String { "_preChat_\(nodeId)" }
    private func postKey(_ nodeId: String) -> String { "_postChat_\(nodeId)" }

    private func preChat(_ data: [String: Any]) -> [[String: Any]] {
        JS.truthy(data["enablePreChatQuestions"]) ? JS.dicts(data["preChatQuestions"]) : []
    }

    /// The step's post-chat survey questions, when it has them on (web
    /// enablePostChatSurveyQuestions + postChatSurveyQuestions).
    private func postChat(_ data: [String: Any]) -> [[String: Any]] {
        JS.truthy(data["enablePostChatSurveyQuestions"]) ? JS.dicts(data["postChatSurveyQuestions"]) : []
    }

    /// Post-chat question `index`, after 2000 ms of typing (web
    /// _handlePostChatSurveyQuestionsLooper): its line, its record entry.
    @MainActor
    private func askPostChat(_ node: [String: Any], _ state: ChatState, _ index: Int) async -> NodeResult {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        let qs = postChat(data)
        guard index < qs.count else {
            state.setVariable(name: postKey(nodeId), value: "done")
            return .next
        }
        let q = qs[index]
        let ctx = ctxOf(node, state)
        await ctx.typing(2000)
        if ctx.isStale() { return .displayUI(.textInput(placeholder: "Type your answer...", validation: nil, nodeId: nodeId)) }
        state.setVariable(name: postKey(nodeId), value: index)
        let raw = JS.text(q["questionText"])
        let question = FlowText.bubbleText(state.resolveVariables(html: raw))
        if !question.isEmpty { FlowKit.botSay(state, text: question, nodeId: nodeId, nodeType: nodeType) }
        let qid = JS.str(q["id"])
        state.addRecord(["_id": qid, "id": qid, "shape": "post-chat-survey-question", "type": "post-chat-survey-question",
                         "text": raw, "time": Flow.iso(Date())])
        return .displayUI(.textInput(placeholder: "Type your answer...", validation: nil, nodeId: nodeId))
    }

    /// An answer to a post-chat question: checked, saved, then the next one or on.
    @MainActor
    private func answerPostChat(_ response: Any, _ node: [String: Any], _ state: ChatState, _ index: Int) async -> NodeResult {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        let qs = postChat(data)
        let q = index < qs.count ? qs[index] : [:]
        let value = FlowKit.typedText(response)
        let ui = NodeUIState.textInput(placeholder: "Type your answer...", validation: nil, nodeId: nodeId)
        if value.isEmpty { return .displayUI(ui) }
        let variable = JS.text(q["answerVariable"])
        if variable == "email" && !FlowInputs.isValidEmail(value) {
            return .invalid(FlowInputs.ownerTextOr(q["incorrectEmailResponse"], FlowInputs.EN.emailInvalid, ["Please enter a valid email"]), uiState: ui, inCard: false)
        }
        if (variable == "mobile" || variable == "phone") && !FlowInputs.isValidPhone(value) {
            return .invalid(FlowInputs.ownerTextOr(q["incorrectPhoneNumberResponse"], FlowInputs.EN.phoneInvalid), uiState: ui, inCard: false)
        }
        if variable == "name" { state.updateMetadata(key: "name", value: value) }
        if variable == "email" { state.updateMetadata(key: "email", value: value) }
        if variable == "mobile" || variable == "phone" { state.updateMetadata(key: "phone", value: FlowInputs.normalizePhone(value)) }
        let entryId = "post-chat-answer-\(nodeId)-\(index)"
        var entry: [String: Any] = [
            "_id": entryId, "id": entryId,
            "shape": "post-chat-survey-question-response", "type": "post-chat-survey-question-response", "text": value, "time": Flow.iso(Date()),
        ]
        if let qid = q["id"] { entry["questionId"] = qid }
        state.addRecord(entry)
        FlowKit.userSay(state, value, nodeId)
        state.setAnswerVariable(nodeId: JS.str(q["id"]), value: value)
        return await askPostChat(node, state, index + 1)
    }

    /// The live chat ended: the post-chat survey when the step has one, else on.
    @MainActor
    private func ended(_ node: [String: Any], _ state: ChatState) async -> NodeResult {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        state.setVariable(name: "_handoverEnded", value: true)
        let qs = postChat(data)
        guard !qs.isEmpty, state.getVariable(name: postKey(nodeId)) == nil else { return .next }
        for q in qs {
            let key = JS.text(q["answerVariable"])
            if !key.isEmpty { state.registerAnswerVariable(nodeId: JS.str(q["id"]), key: key) }
        }
        return await askPostChat(node, state, 0)
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        let ctx = ctxOf(node, state)
        let questions = preChat(data)
        if !questions.isEmpty && state.getVariable(name: preKey(nodeId)) == nil {
            for q in questions {
                let key = JS.text(q["answerVariable"])
                if !key.isEmpty { state.registerAnswerVariable(nodeId: JS.str(q["id"]), key: key) }
            }
            return await askPreChat(node, state, 0)
        }

        // The builder writes it as rich text (<p>...</p>).
        let raw = FlowKit.string(data, "handoverMessage", FlowKit.string(data, "waitMessage", "Please wait while we connect you with an agent..."))
        let message = FlowText.bubbleText(state.resolveVariables(html: raw))
        if !message.isEmpty {
            await ctx.typing(1000)
            FlowKit.botSay(state, text: message, nodeId: nodeId, nodeType: nodeType)
        }

        // In the chat room, and the record first: the server builds the
        // ticket from it (socket.io keeps the order on one connection).
        let sessionId = state.sessionId
        ctx.emit(SocketEvents.joinChatRoomVisitor, ["chatSessionId": sessionId])
        ctx.emit(SocketEvents.responseRecord, state.buildResponseData(chatSessionId: sessionId, botId: state.botId))
        ctx.emit(SocketEvents.initiateHandover, AgentHandover.payload(state: state, chatSessionId: sessionId, botId: state.botId, nodeData: data))
        state.setVariable(name: "_handoverInitiated", value: true)
        state.setVariable(name: "_handoverStartTime", value: Flow.iso(ctx.now()))

        // Nobody free (web special.ts): the owner's fallback as the bot's
        // message after a beat of typing; with "leave a message" off the
        // flow carries on along the first edge (otherwise the leave-a-message
        // card carries it on once sent or skipped).
        var off: () -> Void = {}
        off = ctx.on(SocketEvents.noAgentsAvailable) { _ in
            off()
            Task { @MainActor in
                let fallbackRaw = JS.text(data["fallbackMessage"])
                let fallback = FlowText.bubbleText(state.resolveVariables(html: fallbackRaw))
                if !fallback.isEmpty {
                    await ctx.typing(1000)
                    if ctx.isStale() { return }
                    FlowKit.botSay(state, text: fallback, nodeId: nodeId, nodeType: "human-handover-node")
                    state.addRecord(["_id": fallbackRaw, "id": fallbackRaw, "type": "agent-declined-message", "message": fallback, "renderedText": fallback, "time": Flow.iso(Date())])
                }
                if JS.bool(ctx.customizations["chatLeaveMessage"]) == false { ctx.respond(["action": "continue"]) }
            }
        }
        return .displayUI(.humanHandover(message: message.isEmpty ? nil : message))
    }

    /// Pre-chat question `index`, after 2000 ms of typing.
    @MainActor
    private func askPreChat(_ node: [String: Any], _ state: ChatState, _ index: Int) async -> NodeResult {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        let qs = preChat(data)
        let q = index < qs.count ? qs[index] : [:]
        await ctxOf(node, state).typing(2000)
        state.setVariable(name: preKey(nodeId), value: index)
        let question = FlowText.bubbleText(state.resolveVariables(html: JS.text(q["questionText"])))
        if !question.isEmpty { FlowKit.botSay(state, text: question, nodeId: nodeId, nodeType: nodeType) }
        return .displayUI(.textInput(placeholder: "Type your answer...", validation: nil, nodeId: nodeId))
    }

    /// An answer to a pre-chat question: checked, saved, then the next one or the handover.
    @MainActor
    private func answerPreChat(_ response: Any, _ node: [String: Any], _ state: ChatState, _ index: Int) async -> NodeResult {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        let qs = preChat(data)
        let q = index < qs.count ? qs[index] : [:]
        let value = FlowKit.typedText(response)
        let ui = NodeUIState.textInput(placeholder: "Type your answer...", validation: nil, nodeId: nodeId)
        if value.isEmpty { return .displayUI(ui) }
        let variable = JS.text(q["answerVariable"])
        if variable == "email" && !FlowInputs.isValidEmail(value) {
            return .invalid(FlowInputs.ownerTextOr(q["incorrectEmailResponse"], FlowInputs.EN.emailInvalid, ["Please enter a valid email"]), uiState: ui, inCard: false)
        }
        if (variable == "mobile" || variable == "phone") && !FlowInputs.isValidPhone(value) {
            return .invalid(FlowInputs.ownerTextOr(q["incorrectPhoneNumberResponse"], FlowInputs.EN.phoneInvalid), uiState: ui, inCard: false)
        }
        if variable == "name" { state.updateMetadata(key: "name", value: value) }
        if variable == "email" { state.updateMetadata(key: "email", value: value) }
        if variable == "mobile" || variable == "phone" { state.updateMetadata(key: "phone", value: FlowInputs.normalizePhone(value)) }
        var entry: [String: Any] = [
            "_id": "pre-chat-answer-\(nodeId)-\(index)", "id": "pre-chat-answer-\(nodeId)-\(index)",
            "shape": "pre-chat-question-response", "type": "pre-chat-question-response", "text": value, "time": Flow.iso(Date()),
        ]
        if let qid = q["id"] { entry["questionId"] = qid }
        state.addRecord(entry)
        FlowKit.userSay(state, value, nodeId)
        state.setAnswerVariable(nodeId: JS.str(q["id"]), value: value)
        if index + 1 < qs.count { return await askPreChat(node, state, index + 1) }
        state.setVariable(name: preKey(nodeId), value: "done")
        return await handle(node: node, state: state)
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let r = JS.dict(response)
        let action = JS.text(r["action"])
        if let index = state.getVariable(name: preKey(nodeId)) as? Int, action.isEmpty, JS.isNullish(r["status"]) {
            return await answerPreChat(response, node, state, index)
        }
        if let index = state.getVariable(name: postKey(nodeId)) as? Int, action.isEmpty, JS.isNullish(r["status"]) {
            return await answerPostChat(response, node, state, index)
        }
        let ctx = ctxOf(node, state)
        switch action.isEmpty ? JS.text(r["status"]) : action {
        case "cancel":
            state.setVariable(name: "_handoverCancelled", value: true)
            // Out of the queue: the team must stop seeing the visitor waiting
            // (web special.ts, queue-self-resolve). The chat sends it itself
            // and waits for the answer (queueLeft); a headless caller gets it here.
            if JS.bool(r["queueLeft"]) != true { ctx.emit(SocketEvents.queueSelfResolve, HandoverState.queueSelfResolvePayload(state.sessionId)) }
            return .next
        case "endChat":
            state.setVariable(name: "_handoverEnded", value: true)
            ctx.emit(SocketEvents.queueSelfResolve, HandoverState.queueSelfResolvePayload(state.sessionId))
            return .next
        case "ended":
            return await ended(node, state)
        case "surveySubmit":
            // The rating as the web widget sends it: submit-chat-rating (the
            // server has no handover:survey) (#59).
            let survey = JS.dict(r["surveyResponse"])
            state.setVariable(name: "_surveySubmitted", value: true)
            if let rating = LiveChat.surveyRatingPayload(chatSessionId: state.sessionId, style: JS.text(JS.dict(FlowKit.data(node)["surveyConfig"])["ratingStyle"]), response: survey) {
                ctx.emit(SocketEvents.submitChatRating, rating)
            }
            return .next
        case "continue", "surveySkip", "noAgents", "no_agents", "timeout":
            return .next
        default:
            return .displayUI(.humanHandover(message: nil))
        }
    }
}

// MARK: - Delay

/// delay-node: shows nothing, waits data.delay seconds (missing: no wait,
/// at most 10 minutes), then the first edge.
public final class DelayNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "delay-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let seconds = JS.toNumber(FlowKit.data(node)["delay"])
        let delayMs = seconds.isFinite && seconds > 0 ? min(seconds * 1000, 10 * 60 * 1000) : 0
        state.setVariable(name: "_lastDelay", value: delayMs)
        if delayMs == 0 { return .next }
        return .delayedProceed(delayMs / 1000, nil)
    }
}

// MARK: - Email

/// email-node: emits "email-node-trigger" with the node data, the
/// transcript, the visitor and every answer, and moves on at once. Reached
/// by a jump-to-node it sends nothing and only moves on (web index.ts).
public final class EmailNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "email-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let ctx = ctxOf(node, state)
        if ctx.via == "jump" { return .next }
        var payload: [String: Any] = [
            "nodeData": serverData(node),
            "botName": state.getVariable(name: "_botName") as? String ?? "",
            "transcript": transcriptOf(state),
            "visitorName": state.userName ?? "",
            "visitorEmail": state.userEmail ?? "",
        ]
        for v in state.flowAnswerVariables() { payload[v.key] = v.value }
        payload["answerVariables"] = state.getAnswerVariablesList()
        payload["chatDate"] = Flow.iso(ctx.now())
        payload["workspaceId"] = state.workspaceId ?? (state.getVariable(name: "_workspaceId") as? String) ?? ""
        ctx.emit("email-node-trigger", payload)
        return .next
    }
}

// MARK: - Zapier

/// zapier-node: when the bot has an active webhook for the node, relays the
/// answers through the server ("zapier-node-trigger"); moves on at once.
public final class ZapierNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "zapier-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = serverData(node)
        let nodeId = FlowKit.id(node)
        let hookNodeId = JS.isNullish(data["nodeId"]) ? nodeId : JS.str(data["nodeId"])
        let hooks = JS.dicts(state.getVariable(name: "_integrationWebhooks"))
        guard let hook = hooks.first(where: { JS.text($0["nodeId"]) == hookNodeId && JS.text($0["botId"]) == state.botId && JS.truthy($0["active"]) }),
              !JS.text(hook["webhookURL"]).isEmpty else { return .next }
        var nodeData = data
        nodeData["nodeId"] = hookNodeId
        nodeData["webhookURL"] = JS.text(hook["webhookURL"])
        var answers: [String: Any] = [:]
        for v in state.flowAnswerVariables() where answers[v.key] == nil { answers[v.key] = v.value }
        ctxOf(node, state).emit("zapier-node-trigger", [
            "nodeData": nodeData,
            "payload": answers,
            "chatSessionId": state.sessionId,
            "workspaceId": state.workspaceId ?? (state.getVariable(name: "_workspaceId") as? String) ?? "",
        ])
        return .next
    }
}

// MARK: - Webhook

/// webhook-node: its answerVariable is registered at once and filled later;
/// the call runs in the background and the flow moves on at once (web
/// integrations.ts _handleWebhookNode). Bearer, basic, API key, OAuth2 and
/// custom-token authentication; the reply fills the step's variable.
public final class WebhookNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "webhook-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        let key = JS.text(data["answerVariable"])
        if !key.isEmpty { state.registerAnswerVariable(nodeId: nodeId, key: key) }
        let ctx = ctxOf(node, state)
        Task { @MainActor in await Self.run(data, nodeId: nodeId, ctx: ctx, state: state) }
        return .next
    }

    /// The variables a webhook's text may use.
    @MainActor
    private static func fill(_ text: String, _ state: ChatState) -> String {
        FlowLogic.fillPlaceholders(text) { state.lookupVariable($0) }
    }

    @MainActor
    private static func run(_ data: [String: Any], nodeId: String, ctx: FlowContext, state: ChatState) async {
        let rawUrl = JS.text(data["url"]).isEmpty ? JS.text(data["webhookUrl"]) : JS.text(data["url"])
        let urlText = fill(rawUrl, state)
        guard urlText.matches("^https?://", .caseInsensitive), let url = URL(string: urlText) else { return }
        let method = (JS.text(data["method"]).isEmpty ? "POST" : JS.text(data["method"])).uppercased()
        var headers: [String: String] = [:]
        if let h = data["headers"] as? [String: Any] { for (k, v) in h { headers[k] = fill(JS.str(v), state) } }
        for h in JS.dicts(data["headers"]) where !JS.text(h["key"]).isEmpty { headers[JS.text(h["key"])] = fill(JS.text(h["value"]), state) }

        // Authentication
        let auth = JS.dict(data["authentication"])
        let type = authType(auth)
        switch type {
        case "bearer":
            headers["Authorization"] = "Bearer \(fill(JS.text(auth["token"] ?? auth["bearerToken"]), state))"
        case "basic":
            let pair = "\(fill(JS.text(auth["username"]), state)):\(fill(JS.text(auth["password"]), state))"
            headers["Authorization"] = "Basic \(Data(pair.utf8).base64EncodedString())"
        case "apiKey":
            let name = JS.text(auth["key"]).isEmpty ? (JS.text(auth["headerName"]).isEmpty ? "X-API-Key" : JS.text(auth["headerName"])) : JS.text(auth["key"])
            headers[name] = fill(JS.text(auth["value"]).isEmpty ? JS.text(auth["apiKey"]) : JS.text(auth["value"]), state)
        case "oauth2", "custom":
            guard let token = await fetchToken(type, auth, ctx: ctx, state: state) else { return }
            headers["Authorization"] = "Bearer \(token)"
        default:
            break
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if method != "GET" {
            var body: Any? = data["body"] ?? data["payload"]
            if let s = body as? String {
                body = s.trimmed.isEmpty ? nil : (JS.parse(fill(s, state)) ?? fill(s, state))
            }
            if JS.truthy(data["includeAnswerVariables"]), var o = body as? [String: Any] {
                o["answerVariables"] = state.getAnswerVariablesList()
                body = o
            }
            if let b = body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = (b as? String).map { Data($0.utf8) } ?? (try? JSONSerialization.data(withJSONObject: JS.plain(b) ?? [:]))
            }
        }
        guard let reply = await ctx.send(request), reply.status >= 200, reply.status < 300 else {
            state.setVariable(name: "_webhookSuccess", value: false)
            return
        }
        let json = reply.body.flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) } ?? reply.body.flatMap { String(data: $0, encoding: .utf8) }
        state.setAnswerVariable(nodeId: nodeId, value: json ?? NSNull())
    }

    /// The authentication the step uses (web WebhookUtils detectAuthType).
    private static func authType(_ auth: [String: Any]) -> String {
        if auth.isEmpty { return "none" }
        switch JS.text(auth["type"]).lowercased() {
        case "bearer": return "bearer"
        case "basic": return "basic"
        case "apikey", "api_key", "api-key": return "apiKey"
        case "oauth2", "oauth": return "oauth2"
        case "custom", "token": return "custom"
        case "none": return "none"
        default: break
        }
        if JS.truthy(auth["token"]) && !JS.truthy(auth["tokenUrl"]) { return "bearer" }
        if JS.truthy(auth["apiKey"]) || JS.truthy(auth["headerName"]) { return "apiKey" }
        if JS.truthy(auth["clientId"]) && JS.truthy(auth["clientSecret"]) { return "oauth2" }
        if JS.truthy(auth["tokenUrl"]) && JS.truthy(auth["username"]) { return "custom" }
        if JS.truthy(auth["username"]) && JS.truthy(auth["password"]) && !JS.truthy(auth["tokenUrl"]) { return "basic" }
        return "none"
    }

    /// An OAuth2 (client credentials) or custom (username / password) token.
    @MainActor
    private static func fetchToken(_ type: String, _ auth: [String: Any], ctx: FlowContext, state: ChatState) async -> String? {
        guard let url = URL(string: fill(JS.text(auth["tokenUrl"]), state)) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if type == "oauth2" {
            var form = "grant_type=\(FlowText.encodeURIComponent(JS.text(auth["grantType"]).isEmpty ? "client_credentials" : JS.text(auth["grantType"])))"
            form += "&client_id=\(FlowText.encodeURIComponent(fill(JS.text(auth["clientId"]), state)))"
            form += "&client_secret=\(FlowText.encodeURIComponent(fill(JS.text(auth["clientSecret"]), state)))"
            if JS.truthy(auth["scope"]) { form += "&scope=\(FlowText.encodeURIComponent(JS.text(auth["scope"])))" }
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(form.utf8)
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["username": fill(JS.text(auth["username"]), state), "password": fill(JS.text(auth["password"]), state)])
        }
        guard let reply = await ctx.send(request), reply.status >= 200, reply.status < 300,
              let json = reply.body.flatMap({ try? JSONSerialization.jsonObject(with: $0) }) else { return nil }
        let path = type == "oauth2" ? "access_token" : (JS.text(auth["tokenPath"]).isEmpty ? "access_token" : JS.text(auth["tokenPath"]))
        let token = FlowRich.getPath(json, path)
        return JS.truthy(token) ? JS.str(token) : nil
    }
}

/// The integration steps.
enum IntegrationNodeHandlers {
    static var all: [NodeHandler] {
        [
            WebhookNodeHandler(), GPTNodeHandler(), HumanHandoverNodeHandler(), DelayNodeHandler(), EmailNodeHandler(),
            NativeIntegrationHandler("gmail-node"), NativeIntegrationHandler("slack-node"), NativeIntegrationHandler("discord-node"),
            GoogleSheetsNodeHandler(), GoogleCalendarNodeHandler(), GoogleMeetNodeHandler(),
            NativeIntegrationHandler("google-docs-node"), NativeIntegrationHandler("google-drive-node"),
            NativeIntegrationHandler("hubspot-node"), ResultIntegrationHandler("salesforce-node"), ResultIntegrationHandler("segment-node"),
            NativeIntegrationHandler("zohocrm-node"), ResultIntegrationHandler("mailchimp-node"), ZapierNodeHandler(),
            NativeIntegrationHandler("airtable-node"), NativeIntegrationHandler("notion-node"), StripeNodeHandler(),
        ]
    }
}
