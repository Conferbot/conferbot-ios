//
//  ChoiceNodeHandlers.swift
//  Conferbot
//
//  The choice steps: n-choices, image-choice, yes-or-no, rating-choice,
//  opinion-scale, n-select-option, n-check-options and carousel. Fields,
//  ports, saved values and records follow the flow-node spec and the web
//  widget (ts/chat/displayStep.ts, handlers/flowOperations.ts,
//  handlers/askQuestions.ts), as the React Native SDK's ChoiceNodeHandlers.ts:
//
//  - n-choices / image-choice / yes-or-no / carousel leave by
//    "source-" + the picked item's id; rating by source-<value-1>; opinion
//    scale by source-<value-from>. No edge there ends the chat.
//  - n-select-option and n-check-options have no ports: the first edge,
//    600 ms after the pick.
//  - Labels are shown with the answers filled in; what is saved is the
//    option's own text, HTML stripped.
//

import Foundation

/// A prompt said, then buttons.
private func sayPrompt(_ state: ChatState, _ node: [String: Any], _ field: String, _ type: String) {
    FlowKit.botSay(state, html: FlowKit.filledHtml(state, FlowKit.data(node)[field]), nodeId: FlowKit.id(node), nodeType: type)
}

// MARK: - N choices

/// n-choices-node: choicePrompt, choices [{id, choiceText}] (blank ones hidden).
public final class NChoicesNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.nChoices }

    private func choices(_ node: [String: Any]) -> [[String: Any]] {
        JS.dicts(FlowKit.data(node)["choices"]).filter { !JS.text($0["choiceText"]).trimmed.isEmpty }
    }

    private func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        .buttons(buttons: choices(node).map { ButtonOption(id: JS.str($0["id"]), label: FlowKit.shownLabel(state, $0["choiceText"])) }, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        sayPrompt(state, node, "choicePrompt", nodeType)
        return .displayUI(ui(node, state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let id = FlowKit.pickedId(response)
        guard let choice = choices(node).first(where: { JS.str($0["id"]) == id }) else { return .displayUI(ui(node, state)) }
        let text = FlowKit.savedText(choice["choiceText"])
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-selected-choice", "choices": FlowKit.data(node), "selectedChoice": text])
        FlowKit.userSay(state, text, nodeId)
        state.setAnswerVariable(nodeId: nodeId, value: text)
        return .port("source-\(JS.str(choice["id"]))")
    }
}

// MARK: - Image choice

/// image-choice-node: questionText, images [{id, image, label}] (both non-blank to show).
public final class ImageChoiceNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "image-choice-node" }

    private func images(_ node: [String: Any]) -> [[String: Any]] {
        JS.dicts(FlowKit.data(node)["images"]).filter { !JS.text($0["image"]).trimmed.isEmpty && !JS.text($0["label"]).trimmed.isEmpty }
    }

    private func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        .singleChoice(options: images(node).map {
            ChoiceOption(id: JS.str($0["id"]), label: FlowKit.shownLabel(state, $0["label"]), value: FlowKit.savedText($0["label"]), imageUrl: JS.text($0["image"]))
        }, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        sayPrompt(state, node, "questionText", nodeType)
        return .displayUI(ui(node, state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let id = FlowKit.pickedId(response)
        guard let image = images(node).first(where: { JS.str($0["id"]) == id }) else { return .displayUI(ui(node, state)) }
        let label = FlowKit.savedText(image["label"])
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-selected-image-choice", "images": FlowKit.data(node), "selectedImageLabel": label, "selectedImage": image["image"] ?? ""])
        FlowKit.userSay(state, label, nodeId)
        state.setAnswerVariable(nodeId: nodeId, value: label)
        return .port("source-\(JS.str(image["id"]))")
    }
}

// MARK: - Yes or no

/// yes-or-no-choice-node: questionText, options [{id, label}] (default Yes "1" / No "2").
public final class YesOrNoChoiceNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "yes-or-no-choice-node" }

    private func options(_ node: [String: Any]) -> [[String: Any]] {
        let list = JS.dicts(FlowKit.data(node)["options"])
        return list.isEmpty ? [["id": "1", "label": "Yes"], ["id": "2", "label": "No"]] : list
    }

    private func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        .buttons(buttons: options(node).map { ButtonOption(id: JS.str($0["id"]), label: FlowKit.shownLabel(state, $0["label"])) }, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        sayPrompt(state, node, "questionText", nodeType)
        return .displayUI(ui(node, state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let id = FlowKit.pickedId(response)
        guard let option = options(node).first(where: { JS.str($0["id"]) == id }) else { return .displayUI(ui(node, state)) }
        let text = FlowKit.savedText(option["label"])
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-selected-yes-or-no-choice", "options": FlowKit.data(node), "selectedYesOrNoChoice": text])
        FlowKit.userSay(state, text, nodeId)
        state.setAnswerVariable(nodeId: nodeId, value: text)
        return .port("source-\(JS.str(option["id"]))")
    }
}

// MARK: - Rating

enum Rating {
    /// What the faces have always recorded (web nodeKit FACE_VALUES).
    static let faceValues = ["😡", "😐", "😊", "😀", "😁"]
    static let faceLabels = ["Very unhappy", "Unhappy", "Neutral", "Happy", "Very happy"]

    static func count(_ ratingType: Any?) -> Int {
        if JS.text(ratingType) == "smiley" { return 5 }
        let n = JS.toNumber(ratingType)
        return max(1, min(10, n.isFinite && n != 0 ? Int(n) : 5))
    }

    /// What each score means (web nodeKit ratingWords, English).
    static func words(_ ratingType: Any?, _ n: Int) -> [String] {
        if JS.text(ratingType) == "smiley" { return faceLabels }
        if n == 3 { return ["Bad", "Okay", "Great"] }
        if n == 5 { return ["Terrible", "Bad", "Okay", "Good", "Amazing"] }
        return (1...max(1, n)).map { "\($0) out of \(n)" }
    }

    /// The value a rating button records: stars, or the face.
    static func value(_ ratingType: Any?, _ i: Int) -> String {
        JS.text(ratingType) == "smiley" ? (i >= 1 && i <= 5 ? faceValues[i - 1] : "😊") : String(repeating: "⭐", count: i)
    }

    /// A picked score: {value} / {rating} / a number / a button id.
    static func picked(_ response: Any) -> Double {
        if let d = response as? [String: Any] {
            let v = [d["value"], d["rating"], d["buttonId"]].first(where: { !JS.isNullish($0) }) ?? nil
            return JS.toNumber(v)
        }
        return JS.toNumber(response)
    }
}

/// rating-choice-node: ratingType 1..10 stars or "smiley" (five faces).
/// Saves the NUMBER; leaves by source-<value-1>.
public final class RatingChoiceNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "rating-choice-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        let type = FlowKit.data(node)["ratingType"]
        let n = Rating.count(type)
        let style: RatingStyle = JS.text(type) == "smiley" ? .emojis : .stars
        return .rating(max: n, style: style, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        sayPrompt(state, node, "questionText", nodeType)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let type = FlowKit.data(node)["ratingType"]
        let n = Rating.count(type)
        let v = Rating.picked(response)
        guard v.isFinite, v == v.rounded(), v >= 1, v <= Double(n) else { return .displayUI(ui(node)) }
        let value = Int(v)
        let selected = Rating.value(type, value)
        var entry: [String: Any] = [
            "id": nodeId, "shape": "user-selected-rating-choice", "options": FlowKit.data(node), "selectedRatingChoice": selected,
            "value": value, "label": Rating.words(type, n)[value - 1],
        ]
        if let type = type { entry["ratingType"] = type }
        FlowKit.pushAnswer(state, entry)
        FlowKit.userSay(state, selected, nodeId)
        state.setAnswerVariable(nodeId: nodeId, value: value)
        return .port("source-\(value - 1)")
    }
}

// MARK: - Opinion scale

/// A scale's range; blank is 0 to 10 (web nodeKit scaleRange).
func scaleRange(_ rawFrom: Any?, _ rawTo: Any?) -> (from: Double, to: Double) {
    func blank(_ v: Any?) -> Bool { JS.isNullish(v) || (v as? String) == "" || !JS.toNumber(v).isFinite }
    let from = blank(rawFrom) ? 0 : JS.toNumber(rawFrom)
    let to = blank(rawTo) || JS.toNumber(rawTo) < from ? max(from, 10) : JS.toNumber(rawTo)
    return (from, to)
}

/// opinion-scale-choice-node: from..to buttons; saves the NUMBER; leaves by source-<value-from>.
public final class OpinionScaleChoiceNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "opinion-scale-choice-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        let d = FlowKit.data(node)
        let r = scaleRange(d["from"], d["to"])
        return .opinionScale(min: Int(r.from), max: Int(r.to), minLabel: d["fromLabel"] as? String, maxLabel: d["toLabel"] as? String, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        sayPrompt(state, node, "questionText", nodeType)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let d = FlowKit.data(node)
        let r = scaleRange(d["from"], d["to"])
        let v = Rating.picked(response)
        guard v.isFinite, v >= r.from, v <= r.to else { return .displayUI(ui(node)) }
        let value = JS.num(v)
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-selected-opinion-scale-choice", "options": d, "selectedOpinionScaleChoice": JS.numberText(v), "value": value])
        FlowKit.userSay(state, JS.numberText(v), nodeId)
        state.setAnswerVariable(nodeId: nodeId, value: value)
        return .port("source-\(JS.numberText(v - r.from))")
    }
}

// MARK: - N select option

/// n-select-option-node: selectPrompt, options [{id, optionText}]; no ports - first edge after 600 ms.
public final class NSelectOptionNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.nSelectOption }

    private func options(_ node: [String: Any]) -> [[String: Any]] {
        JS.dicts(FlowKit.data(node)["options"]).filter { !JS.text($0["optionText"]).trimmed.isEmpty }
    }

    private func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        .singleChoice(options: options(node).map {
            ChoiceOption(id: JS.str($0["id"]), label: FlowKit.shownLabel(state, $0["optionText"]), value: FlowKit.savedText($0["optionText"]))
        }, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        sayPrompt(state, node, "selectPrompt", nodeType)
        return .displayUI(ui(node, state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let id = FlowKit.pickedId(response)
        guard let option = options(node).first(where: { JS.str($0["id"]) == id }) else { return .displayUI(ui(node, state)) }
        let text = FlowKit.savedText(option["optionText"])
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-selected-option", "options": FlowKit.data(node), "selectedOption": text])
        FlowKit.userSay(state, text, nodeId)
        state.setAnswerVariable(nodeId: nodeId, value: text)
        return .delayedProceed(0.6, nil)
    }
}

// MARK: - N check options

/// n-check-options-node: checkOptionsPrompt, options; the ticked texts in
/// LIST order joined ", "; first edge after 600 ms.
public final class NCheckOptionsNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.nCheckOptions }

    private func options(_ node: [String: Any]) -> [[String: Any]] {
        JS.dicts(FlowKit.data(node)["options"]).filter { !JS.text($0["optionText"]).trimmed.isEmpty }
    }

    private func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        .multiChoice(options: options(node).map {
            ChoiceOption(id: JS.str($0["id"]), label: FlowKit.shownLabel(state, $0["optionText"]), value: FlowKit.savedText($0["optionText"]))
        }, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        sayPrompt(state, node, "checkOptionsPrompt", nodeType)
        return .displayUI(ui(node, state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let opts = options(node)
        let r = JS.dict(response)
        let ids = (r["buttonIds"] as? [Any] ?? r["optionIds"] as? [Any] ?? []).map { JS.str($0) }
        let ticked = FlowText.inListOrder(ids, opts.map { JS.str($0["id"]) }).compactMap { id in opts.first { JS.str($0["id"]) == id } }
        if ticked.isEmpty { return .displayUI(ui(node, state)) }
        let text = ticked.map { FlowKit.savedText($0["optionText"]) }.joined(separator: ", ")
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-selected-check-options", "options": FlowKit.data(node), "selectedCheckOptions": text])
        FlowKit.userSay(state, text, nodeId)
        state.setAnswerVariable(nodeId: nodeId, value: text)
        return .delayedProceed(0.6, nil)
    }
}

// MARK: - Carousel

enum Carousel {
    static let continueLabel = "Continue"

    struct Button {
        let id: String
        let label: String
        let action: String
        let href: String
    }

    struct Card {
        let id: String
        let image: String
        let title: String
        let description: String
        let price: String
        let buttons: [Button]
    }

    /// The cards as the web reads them (nodeKit carouselCards): at most 10, 3 buttons each.
    static func cards(_ data: [String: Any]) -> [Card] {
        let list = JS.array(data["cards"]).enumerated().map { ci, raw -> Card in
            let card = JS.dict(raw)
            let buttons = JS.array(card["buttons"]).enumerated().map { bi, braw -> Button in
                let b = JS.dict(braw)
                let action = JS.text(b["action"]) == "link" ? "link" : "path"
                return Button(id: JS.isNullish(b["id"]) ? "\(ci)-\(bi)" : JS.str(b["id"]), label: JS.text(b["label"]).trimmed,
                              action: action, href: action == "link" ? FlowInputs.linkHref(b["url"]) : "")
            }.filter { !$0.label.isEmpty && ($0.action == "path" || !$0.href.isEmpty) }
            return Card(
                id: JS.isNullish(card["id"]) ? "card-\(ci)" : JS.str(card["id"]),
                image: JS.text(card["image"]).trimmed,
                title: JS.text(card["title"]).trimmed,
                description: JS.text(card["description"]).trimmed,
                price: JS.text(card["price"]).trimmed,
                buttons: Array(buttons.prefix(3))
            )
        }.filter { !$0.title.isEmpty || !$0.description.isEmpty || !$0.image.isEmpty }
        return Array(list.prefix(10))
    }

    static func ui(_ cards: [Card], _ nodeId: String, _ state: ChatState) -> NodeUIState {
        .cards(cards: cards.map { c in
            CardData(id: c.id, title: FlowKit.shownLabel(state, c.title),
                     subtitle: [c.price, c.description].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty,
                     imageUrl: c.image.nilIfEmpty,
                     buttons: c.buttons.map { ButtonOption(id: $0.id, label: $0.label, url: $0.href.nilIfEmpty, action: $0.action) })
        }, nodeId: nodeId)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// carousel-node: a path button leaves by "source-" + its id and saves
/// "Card title - Button label"; link buttons only open their page. With no
/// path button anywhere, Continue leaves by "source" and saves nothing.
/// Answers: {buttonId} (cardId optional) or {action: "continue"}.
public final class CarouselNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "carousel-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let html = FlowKit.filledHtml(state, FlowKit.data(node)["questionText"])
        if !FlowText.bubbleText(html).isEmpty { FlowKit.botSay(state, html: html, nodeId: FlowKit.id(node), nodeType: nodeType) }
        return .displayUI(Carousel.ui(Carousel.cards(FlowKit.data(node)), FlowKit.id(node), state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let cards = Carousel.cards(FlowKit.data(node))
        let r = JS.dict(response)
        let buttonId = JS.text(r["action"]) == "continue" ? nil : FlowKit.pickedId(response)
        var card: Carousel.Card?
        var button: Carousel.Button?
        for c in cards {
            if let b = c.buttons.first(where: { $0.id == buttonId && $0.action == "path" }), JS.text(r["cardId"]).isEmpty || JS.text(r["cardId"]) == c.id {
                card = c
                button = b
                break
            }
        }
        let ui = Carousel.ui(cards, nodeId, state)
        // A link button: it opens its page and the step keeps waiting.
        if buttonId != nil && button == nil { return .displayUI(ui) }
        let hasPath = cards.contains { $0.buttons.contains { $0.action == "path" } }
        if button == nil && hasPath { return .displayUI(ui) }
        let title = card?.title ?? ""
        let label = button?.label ?? ""
        let answer = button != nil ? (!title.isEmpty && !label.isEmpty ? "\(title) - \(label)" : (title.isEmpty ? label : title)) : Carousel.continueLabel
        let text = FlowKit.savedText(answer)
        FlowKit.pushAnswer(state, [
            "id": nodeId, "shape": "user-selected-carousel", "carousel": FlowKit.data(node), "selectedChoice": text,
            "selectedCardId": card?.id ?? NSNull(), "selectedButtonId": button?.id ?? NSNull(),
        ])
        FlowKit.userSay(state, text, nodeId)
        if button != nil { state.setAnswerVariable(nodeId: nodeId, value: text) }
        return .port(button.map { "source-\($0.id)" } ?? "source")
    }
}

/// The choice steps.
enum ChoiceNodeHandlers {
    static var all: [NodeHandler] {
        [NChoicesNodeHandler(), CarouselNodeHandler(), ImageChoiceNodeHandler(), NSelectOptionNodeHandler(), RatingChoiceNodeHandler(),
         OpinionScaleChoiceNodeHandler(), YesOrNoChoiceNodeHandler(), NCheckOptionsNodeHandler()]
    }
}
