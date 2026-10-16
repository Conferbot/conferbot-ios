//
//  AskNodeHandlers.swift
//  Conferbot
//
//  The question steps answered in the composer (ask-name, ask-email,
//  ask-phone-number, ask-number, ask-url, ask-location,
//  ask-custom-question) and the file step (ask-file). Field names, checks,
//  records and saved values follow the flow-node spec and the web widget's
//  ts/chat/handlers/askQuestions.ts (the React Native SDK's
//  AskNodeHandlers.ts):
//
//  - the prompt is data.questionText;
//  - the answer fills the variable the step registered when it was shown
//    (data.answerVariable) - a step without one stores nothing;
//  - phone numbers are saved normalised, numbers as numbers, bare links as
//    https;
//  - a refused answer says why and the step keeps waiting.
//

import Foundation

/// A composer question: shows questionText, takes typed text.
open class BaseAskHandler: BaseNodeHandler {
    var shape: String { "user-ask-custom-question-response" }
    var placeholder: String { I18n.t("composer.answer") }

    func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        .textInput(placeholder: placeholder, validation: nil, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        FlowKit.botSay(state, html: FlowKit.filledHtml(state, FlowKit.data(node)["questionText"]), nodeId: FlowKit.id(node), nodeType: nodeType)
        return .displayUI(ui(node, state))
    }

    /// The refusal message, or nil when the answer is fine.
    func problem(_ value: String, _ node: [String: Any], _ state: ChatState) -> String? { nil }

    /// What is saved and recorded for the answer.
    func saved(_ value: String) -> (variable: Any, text: String) { (value, value) }

    /// After the answer is saved: by default, on along the first edge.
    @MainActor func after(_ value: String, _ node: [String: Any], _ state: ChatState) async -> NodeResult { .next }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let value = FlowKit.typedText(response)
        let nodeId = FlowKit.id(node)
        if value.isEmpty { return .displayUI(ui(node, state)) }
        if let problem = problem(value, node, state) { return .invalid(problem, uiState: ui(node, state), inCard: false) }
        let s = saved(value)
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": shape, "text": s.text])
        FlowKit.userSay(state, s.text, nodeId)
        state.setAnswerVariable(nodeId: nodeId, value: s.variable)
        return await after(value, node, state)
    }
}

// MARK: - Ask name

/// ask-name-node: any text. The full answer is saved; nameGreetResponse
/// greets by the first name after 2000 ms of typing (none set: the default
/// greeting; cleared in the builder: no greeting).
public final class AskNameHandler: BaseAskHandler {
    public override var nodeType: String { NodeTypes.Display.askName }
    override var shape: String { "user-ask-name-response" }
    override var placeholder: String { I18n.t("composer.name") }

    override func after(_ value: String, _ node: [String: Any], _ state: ChatState) async -> NodeResult {
        let nodeId = FlowKit.id(node)
        state.updateMetadata(key: "name", value: value)
        let data = FlowKit.data(node)
        let greeting = FlowText.nameGreetingHtml(data.keys.contains("nameGreetResponse") ? data["nameGreetResponse"] : nil, value)
        if greeting.isEmpty { return .next }
        await ctxOf(node, state).typing(2000)
        state.addRecord([
            "_id": nodeId, "id": nodeId, "shape": "ask-name-response-greet", "type": "ask-name-response-greet",
            "text": greeting, "renderedText": FlowText.fillVariables(greeting, { state.lookupVariable($0) }), "time": Flow.iso(Date()),
        ])
        FlowKit.botSay(state, html: FlowKit.filledHtml(state, greeting), nodeId: nodeId, nodeType: nodeType)
        return .next
    }
}

// MARK: - Ask email

/// ask-email-node: the widget's e-mail check (incorrectEmailResponse, else
/// the default). A likely domain typo is refused once with the fix offered;
/// the same address sent again is kept as typed.
public final class AskEmailHandler: BaseAskHandler {
    public override var nodeType: String { NodeTypes.Display.askEmail }
    override var shape: String { "user-ask-email-response" }
    override var placeholder: String { I18n.t("composer.email") }

    override func problem(_ value: String, _ node: [String: Any], _ state: ChatState) -> String? {
        if !FlowInputs.isValidEmail(value) {
            return FlowInputs.ownerTextOr(FlowKit.data(node)["incorrectEmailResponse"], FlowInputs.EN.emailInvalid, ["Please enter a valid email"])
        }
        let typed = value.trimmed.lowercased()
        if let fix = FlowInputs.suggestEmailFix(value), (state.getVariable(name: "_lastEmailTypo") as? String) != typed {
            state.setVariable(name: "_lastEmailTypo", value: typed)
            return FlowInputs.EN.emailTypo(fix)
        }
        state.setVariable(name: "_lastEmailTypo", value: "")
        return nil
    }

    override func after(_ value: String, _ node: [String: Any], _ state: ChatState) async -> NodeResult {
        state.updateMetadata(key: "email", value: value)
        return .next
    }
}

// MARK: - Ask phone

/// ask-phone-number-node: 6-15 digits once normalised; saved normalised.
public final class AskPhoneHandler: BaseAskHandler {
    public override var nodeType: String { NodeTypes.Display.askPhone }
    override var shape: String { "user-ask-phone-number-response" }
    override var placeholder: String { I18n.t("composer.phone") }

    override func problem(_ value: String, _ node: [String: Any], _ state: ChatState) -> String? {
        FlowInputs.isValidPhone(value) ? nil : FlowInputs.phoneErrorText(FlowKit.data(node))
    }

    override func saved(_ value: String) -> (variable: Any, text: String) {
        let phone = FlowInputs.normalizePhone(value)
        return (phone, phone)
    }

    override func after(_ value: String, _ node: [String: Any], _ state: ChatState) async -> NodeResult {
        state.updateMetadata(key: "phone", value: FlowInputs.normalizePhone(value))
        return .next
    }
}

// MARK: - Ask number

/// ask-number-node: "1,200" is 1200, "3,5" is 3.5; enableConditions bounds;
/// invalidNumberResponse ({min}/{max} filled). Saved as a NUMBER.
public final class AskNumberHandler: BaseAskHandler {
    public override var nodeType: String { NodeTypes.Display.askNumber }
    override var shape: String { "user-ask-number-response" }
    override var placeholder: String { I18n.t("composer.number") }

    override func problem(_ value: String, _ node: [String: Any], _ state: ChatState) -> String? {
        FlowInputs.numberProblem(value, FlowKit.data(node))
    }

    override func saved(_ value: String) -> (variable: Any, text: String) {
        guard let n = FlowInputs.parseNumberInput(value) else { return (value, value) }
        return (JS.num(n), JS.numberText(n))
    }
}

// MARK: - Ask url

/// ask-url-node: a link people would type; a bare host is saved with https://.
public final class AskUrlHandler: BaseAskHandler {
    public override var nodeType: String { NodeTypes.Display.askUrl }
    override var shape: String { "user-ask-url-response" }

    override func problem(_ value: String, _ node: [String: Any], _ state: ChatState) -> String? {
        FlowInputs.isValidLink(value) ? nil : FlowInputs.EN.link
    }

    override func saved(_ value: String) -> (variable: Any, text: String) {
        let href = FlowInputs.linkHref(value)
        let url = href.isEmpty ? value.trimmed : href
        return (url, url)
    }
}

// MARK: - Ask location / custom question

/// ask-location-node: any text.
public final class AskLocationHandler: BaseAskHandler {
    public override var nodeType: String { "ask-location-node" }
    override var shape: String { "user-ask-location-response" }
    override var placeholder: String { I18n.t("composer.location") }
}

/// ask-custom-question-node: any text.
public final class AskCustomQuestionHandler: BaseAskHandler {
    public override var nodeType: String { NodeTypes.Display.askCustomQuestion }
}

// MARK: - Ask file

/// ask-file-node: an upload card. A file over maxFileSizeMB (default 5) or
/// not in allowedFileTypes is refused on the card; the picked file is
/// uploaded to POST /api/v1/bot/:id/media and its URL saved. A failed upload
/// keeps the step waiting. Optional ("(optional)" in the question, or
/// data.optional) offers Skip: recorded as skipped, no variable.
///
/// Answers: ["file": [uri, name, type, size]] (uploaded here), ["url",
/// "fileName"] (uploaded by the UI already), ["skip": true], or a file URL.
public final class AskFileHandler: BaseNodeHandler {
    public override var nodeType: String { "ask-file-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        let data = FlowKit.data(node)
        let types = JS.array(data["allowedFileTypes"]).map { JS.str($0) }
        let maxMb = JS.toNumber(data["maxFileSizeMB"]) > 0 ? JS.toNumber(data["maxFileSizeMB"]) : FlowInputs.defaultMaxFileMB
        return .fileUpload(allowedTypes: types, maxSize: Int(maxMb * 1024 * 1024), nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        FlowKit.botSay(state, html: FlowKit.filledHtml(state, FlowKit.data(node)["questionText"]), nodeId: FlowKit.id(node), nodeType: nodeType)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let data = FlowKit.data(node)
        let r = JS.dict(response)

        if JS.bool(r["skip"]) == true || JS.text(r["action"]) == "skip" {
            if !FlowInputs.isOptionalUpload(data) { return .displayUI(ui(node)) }
            FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-ask-file-response", "skipped": true])
            FlowKit.userSay(state, FlowInputs.EN.skipped, nodeId)
            return .next
        }

        var url: String? = (r["url"] as? String).flatMap { $0.trimmed.isEmpty ? nil : $0 } ?? (response as? String).flatMap { $0.matches("^(https?|file)://") ? $0 : nil }
        var fileName = JS.text(r["fileName"]).isEmpty ? (JS.text(JS.dict(r["file"])["name"]).isEmpty ? "file" : JS.text(JS.dict(r["file"])["name"])) : JS.text(r["fileName"])

        if url == nil {
            guard let file = r["file"] as? [String: Any] else { return .displayUI(ui(node)) }
            if let problem = FlowInputs.fileUploadProblem(file, data) { return .invalid(problem, uiState: ui(node), inCard: true) }
            let uploaded = await ctxOf(node, state).upload(FlowUploadFile(file))
            guard uploaded.ok, let u = uploaded.url else { return .invalid(FlowInputs.EN.uploadRetry, uiState: ui(node), inCard: true) }
            url = u
            if !JS.text(file["name"]).isEmpty { fileName = JS.text(file["name"]) }
        }

        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-ask-file-response", "fileName": fileName, "url": url!])
        FlowKit.userSay(state, url!, nodeId)
        state.setAnswerVariable(nodeId: nodeId, value: url!)
        return .next
    }
}

/// The question steps.
enum AskNodeHandlers {
    static var all: [NodeHandler] {
        [AskNameHandler(), AskEmailHandler(), AskPhoneHandler(), AskNumberHandler(), AskUrlHandler(),
         AskFileHandler(), AskLocationHandler(), AskCustomQuestionHandler()]
    }
}
