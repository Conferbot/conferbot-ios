//
//  LegacyNodeHandlers.swift
//  Conferbot
//
//  The v1 steps still found in live bots: two-choices, three-choices,
//  select-option, user-input, user-range, user-rating and quiz. Fields and
//  behaviour follow the flow-node spec and the web widget
//  (ts/chat/handlers/_legacy.ts, flowOperations.ts, displayStep.ts), as
//  the React Native SDK's LegacyNodeHandlers.ts. Legacy steps never register
//  an answer variable.
//

import Foundation

/// Numbered options (choiceText1.., option1..) as buttons, ids "1".."n".
private func numberedButtons(_ state: ChatState, _ data: [String: Any], _ key: String, _ count: Int, _ hidden: (Int) -> Bool) -> [ButtonOption] {
    (1...count).filter { !hidden($0) }.map { n in ButtonOption(id: String(n), label: FlowKit.shownLabel(state, data["\(key)\(n)"])) }
}

/// The number of a picked numbered option: its id, or index + 1.
private func pickedNumber(_ response: Any) -> Int? {
    if let id = FlowKit.pickedId(response), let n = Int(id) { return n }
    let r = JS.dict(response)
    let i = JS.toNumber(r["index"])
    return i.isFinite ? Int(i) + 1 : nil
}

// MARK: - Two / three choices

/// two-choices-node: choiceText1 -> source-1, choiceText2 -> source-2 (disableSecondChoice hides it).
public class TwoChoicesNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.twoChoices }
    var count: Int { 2 }

    func hidden(_ data: [String: Any], _ n: Int) -> Bool { n == 2 && JS.truthy(data["disableSecondChoice"]) }

    private func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        let data = FlowKit.data(node)
        return .buttons(buttons: numberedButtons(state, data, "choiceText", count) { self.hidden(data, $0) }, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        FlowKit.botSay(state, html: FlowKit.filledHtml(state, FlowKit.data(node)["choicePrompt"]), nodeId: FlowKit.id(node), nodeType: nodeType)
        return .displayUI(ui(node, state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let data = FlowKit.data(node)
        guard let n = pickedNumber(response), n >= 1, n <= count, !hidden(data, n) else { return .displayUI(ui(node, state)) }
        let text = FlowKit.savedText(data["choiceText\(n)"])
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-selected-choice", "choices": data, "selectedChoice": text])
        FlowKit.userSay(state, text, nodeId)
        return .port("source-\(n)")
    }
}

/// three-choices-node: choiceText1..3 -> source-1..3.
public final class ThreeChoicesNodeHandler: TwoChoicesNodeHandler {
    public override var nodeType: String { NodeTypes.Display.threeChoices }
    override var count: Int { 3 }
    override func hidden(_ data: [String: Any], _ n: Int) -> Bool { false }
}

// MARK: - Select option

/// select-option-node: option1..option5 (disableOption3..5); the first edge 600 ms after the pick.
public final class SelectOptionNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.selectOption }

    private func hidden(_ data: [String: Any], _ n: Int) -> Bool { n >= 3 && JS.truthy(data["disableOption\(n)"]) }

    private func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        let data = FlowKit.data(node)
        return .buttons(buttons: numberedButtons(state, data, "option", 5) { self.hidden(data, $0) }, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        FlowKit.botSay(state, html: FlowKit.filledHtml(state, FlowKit.data(node)["selectPrompt"]), nodeId: FlowKit.id(node), nodeType: nodeType)
        return .displayUI(ui(node, state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let data = FlowKit.data(node)
        guard let id = FlowKit.pickedId(response), let n = Int(id), n >= 1, n <= 5, !hidden(data, n) else { return .displayUI(ui(node, state)) }
        let text = FlowKit.savedText(data["option\(n)"])
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-selected-option", "options": data, "selectedOption": text])
        FlowKit.userSay(state, text, nodeId)
        return .delayedProceed(0.6, nil)
    }
}

// MARK: - User input

/// user-input-node: data.type name | email | number | url | date | file |
/// phone | mobile. email / number / url are checked (incorrect*Response);
/// name greets with nameGreet after 1000 ms of typing and moves on at 2000
/// ms; others at 500 ms; a date or a file at once.
public final class UserInputNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.userInput }

    private static let legacyUrl = Re("^(https?://)?([\\da-z.-]+)\\.([a-z.]{2,6})([/\\w .-]*)*/?$", [.caseInsensitive])

    private func ui(_ node: [String: Any]) -> NodeUIState {
        let type = JS.text(FlowKit.data(node)["type"])
        let nodeId = FlowKit.id(node)
        if type == "file" { return .fileUpload(allowedTypes: [], maxSize: 5_000_000, nodeId: nodeId) }
        return .textInput(placeholder: I18n.t("composer.answer"), validation: nil, nodeId: nodeId)
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        FlowKit.botSay(state, html: FlowKit.filledHtml(state, FlowKit.data(node)["inputPrompt"]), nodeId: FlowKit.id(node), nodeType: nodeType)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let data = FlowKit.data(node)
        let type = JS.text(data["type"])
        let nodeId = FlowKit.id(node)
        let ctx = ctxOf(node, state)
        let r = JS.dict(response)

        if type == "file" {
            var url = (r["url"] as? String) ?? (response as? String)
            if url == nil, let file = r["file"] as? [String: Any] {
                if JS.toNumber(file["size"]) > 5_000_000 { return .invalid(I18n.t("upload.tooBig", ["mb": 5]), uiState: ui(node), inCard: false) }
                let up = await ctx.upload(FlowUploadFile(file))
                guard up.ok else { return .invalid(I18n.t("upload.failed"), uiState: ui(node), inCard: false) }
                url = up.url
            }
            guard let u = url, !u.isEmpty else { return .displayUI(ui(node)) }
            FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-input-response", "type": type, "url": u])
            FlowKit.userSay(state, u, nodeId)
            return .next
        }

        let value = FlowKit.typedText(response)
        if value.isEmpty { return .displayUI(ui(node)) }
        if type == "email" && !FlowInputs.isValidEmail(value) {
            return .invalid(FlowInputs.ownerTextOr(data["incorrectEmailResponse"], FlowInputs.EN.emailInvalid, ["Please enter a valid email"]), uiState: ui(node), inCard: false)
        }
        if type == "number" && (value.trimmed.isEmpty || JS.parseNumber(value.trimmed).isNaN) {
            return .invalid(FlowInputs.ownerTextOr(data["incorrectNumberResponse"], FlowInputs.EN.numberInvalid), uiState: ui(node), inCard: false)
        }
        if type == "url" && !Self.legacyUrl.test(value.lowercased()) {
            return .invalid(FlowInputs.ownerTextOr(data["incorrectUrlResponse"], FlowInputs.EN.urlInvalid), uiState: ui(node), inCard: false)
        }
        if type == "name" { state.updateMetadata(key: "name", value: value) }
        if type == "email" { state.updateMetadata(key: "email", value: value) }
        if type == "phone" || type == "mobile" { state.updateMetadata(key: "phone", value: value) }

        var entry: [String: Any] = ["id": nodeId, "shape": "user-input-response", "text": value]
        if let t = data["type"] { entry["type"] = t }
        FlowKit.pushAnswer(state, entry)
        FlowKit.userSay(state, value, nodeId)

        if type == "date" { return .next }
        if type == "name" {
            let template: Any? = JS.truthy(data["nameGreet"]) ? data["nameGreet"] : nil
            let greeting = FlowText.nameGreetingHtml(template, value)
            await ctx.typing(1000)
            if !greeting.isEmpty { FlowKit.botSay(state, html: FlowKit.filledHtml(state, greeting), nodeId: nodeId, nodeType: nodeType) }
            return .delayedProceed(1.0, nil)
        }
        return .delayedProceed(0.5, nil)
    }
}

// MARK: - User range

/// user-range-node: a number; below minVal -> source-1, within -> source-2, above maxVal -> source-3.
public final class UserRangeNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.userRange }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        .textInput(placeholder: I18n.t("composer.number"), validation: nil, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        FlowKit.botSay(state, html: FlowKit.filledHtml(state, FlowKit.data(node)["rangePrompt"]), nodeId: FlowKit.id(node), nodeType: nodeType)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let data = FlowKit.data(node)
        let value = FlowKit.typedText(response)
        guard let n = FlowInputs.parseNumberInput(value) else { return .invalid(FlowInputs.EN.numberLike, uiState: ui(node), inCard: false) }
        var entry: [String: Any] = ["id": nodeId, "shape": "user-input-response-range", "text": value]
        if let t = data["type"] { entry["type"] = t }
        FlowKit.pushAnswer(state, entry)
        FlowKit.userSay(state, value, nodeId)
        let handle = n < JS.toNumber(data["minVal"]) ? "source-1" : n > JS.toNumber(data["maxVal"]) ? "source-3" : "source-2"
        return .port(handle)
    }
}

// MARK: - User rating

/// user-rating-node: type number (data.range buttons), star or smiley (five); the first edge.
public final class UserRatingNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.userRating }

    private func count(_ data: [String: Any]) -> Int {
        guard JS.text(data["type"]) == "number" else { return 5 }
        let n = JS.toNumber(data["range"])
        return max(1, n.isFinite && n != 0 ? Int(n) : 5)
    }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        let data = FlowKit.data(node)
        let style: RatingStyle = JS.text(data["type"]) == "smiley" ? .emojis : .stars
        return .rating(max: count(data), style: style, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        FlowKit.botSay(state, html: FlowKit.filledHtml(state, FlowKit.data(node)["ratingPrompt"]), nodeId: FlowKit.id(node), nodeType: nodeType)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let data = FlowKit.data(node)
        let v = Rating.picked(response)
        guard v.isFinite, v == v.rounded(), v >= 1, v <= Double(count(data)) else { return .displayUI(ui(node)) }
        var entry: [String: Any] = ["id": nodeId, "shape": "user-selected-rating", "rating": Int(v)]
        if let t = data["type"] { entry["type"] = t }
        FlowKit.pushAnswer(state, entry)
        FlowKit.userSay(state, String(Int(v)), nodeId)
        return .next
    }
}

// MARK: - Quiz

/// quiz-node: option1..5 (disableOption3..5), correctAnswer "optionN".
/// Wrong -> source-1, right -> source-2. When source-2 leads to a
/// variable-node, that step is not run: its value is ADDED to the flow
/// variable (the score) and the flow jumps to the step after it.
public final class QuizNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.quiz }

    private func hidden(_ data: [String: Any], _ n: Int) -> Bool { n >= 3 && JS.truthy(data["disableOption\(n)"]) }

    private func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        let data = FlowKit.data(node)
        return .buttons(buttons: numberedButtons(state, data, "option", 5) { self.hidden(data, $0) }, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        FlowKit.botSay(state, html: FlowKit.filledHtml(state, FlowKit.data(node)["quizPrompt"]), nodeId: FlowKit.id(node), nodeType: nodeType)
        return .displayUI(ui(node, state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        guard let id = FlowKit.pickedId(response), let n = Int(id), n >= 1, n <= 5, !hidden(data, n) else { return .displayUI(ui(node, state)) }
        let option = "option\(n)"
        let correctAnswer = data["correctAnswer"]
        var entry: [String: Any] = ["id": nodeId, "shape": "user-selected-quiz-option", "options": data, "correct": option == JS.text(correctAnswer)]
        if let v = data[option] { entry["selectedOption"] = v }
        if let c = correctAnswer { entry["correctAnswer"] = c }
        FlowKit.pushAnswer(state, entry)
        FlowKit.userSay(state, FlowKit.savedText(data[option]), nodeId)
        if option != JS.text(correctAnswer) { return .port("source-1") }

        let ctx = ctxOf(node, state)
        let rightEdge = ctx.edges().first { ($0["sourceHandle"] as? String) == "source-2" }
        if let target = rightEdge.map({ JS.text($0["target"]) }), let next = ctx.node(target), JS.text(next["type"]) == "variable-node" {
            let nd = JS.dict(next["data"])
            let name = JS.text(nd["name"])
            let current = state.getVariable(name: name)
            let add = JS.toNumber(nd["value"])
            let value = JS.truthy(current) ? JS.toNumber(current) + add : add
            state.setVariable(name: name, value: JS.num(value))
            if let after = ctx.edgesOf(target).first, !JS.text(after["target"]).isEmpty { return .jumpTo(JS.text(after["target"])) }
            return .port("source-1")
        }
        return .port("source-2")
    }
}

/// The legacy steps.
enum LegacyNodeHandlers {
    static var all: [NodeHandler] {
        [UserInputNodeHandler(), UserRangeNodeHandler(), QuizNodeHandler(), TwoChoicesNodeHandler(), ThreeChoicesNodeHandler(),
         SelectOptionNodeHandler(), UserRatingNodeHandler()]
    }
}
