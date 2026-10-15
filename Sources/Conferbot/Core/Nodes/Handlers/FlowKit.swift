//
//  FlowKit.swift
//  Conferbot
//
//  Small helpers the step handlers share (the React Native SDK's
//  handlers/flowKit.ts): owner text filled from the answers as the visitor
//  sees it, record entries in the web's shapes, bot and visitor lines on the
//  transcript (which the chat draws).
//

import Foundation

enum FlowKit {

    /// Owner HTML with the answers filled in (values escaped).
    static func filledHtml(_ state: ChatState, _ html: Any?) -> String { state.resolveVariables(html: JS.text(html)) }

    /// Owner HTML filled in, as one native bubble's text.
    static func shownText(_ state: ChatState, _ html: Any?) -> String { FlowText.bubbleText(filledHtml(state, html)) }

    /// Owner HTML filled in, as one line (labels of buttons and options).
    static func shownLabel(_ state: ChatState, _ html: Any?) -> String { FlowText.plainText(filledHtml(state, html)) }

    /// What an option saves: its own text, HTML stripped and entities decoded (never filled).
    static func savedText(_ html: Any?) -> String { FlowText.stripHtmlAndDecode(html) }

    /// A non-blank text after stripping tags.
    static func notBlank(_ v: Any?) -> Bool { !FlowText.plainText(v).isEmpty }

    /// The visitor's answer on the record (shape "user-..."), merged as the web does.
    static func pushAnswer(_ state: ChatState, _ entry: [String: Any]) {
        var e = entry
        e["_id"] = entry["id"] ?? NSNull()
        e["time"] = Flow.iso(Date())
        state.addRecord(e)
    }

    /// A bot line in the chat: the owner's HTML filled in (the bubble draws
    /// it formatted), with its plain text for the transcript.
    static func botSay(_ state: ChatState, html: String, nodeId: String, nodeType: String, data: [String: Any]? = nil) {
        state.addBotEntry(text: FlowText.bubbleText(html), html: html, nodeId: nodeId, nodeType: nodeType, data: data)
    }

    /// A bot line of plain text.
    static func botSay(_ state: ChatState, text: String, nodeId: String, nodeType: String, data: [String: Any]? = nil) {
        state.addBotEntry(text: text, html: nil, nodeId: nodeId, nodeType: nodeType, data: data)
    }

    /// The visitor's line on the transcript (as typed: the transcript is never masked).
    static func userSay(_ state: ChatState, _ text: String, _ nodeId: String) {
        state.addUserMessage(text, nodeId: nodeId)
    }

    /// A typed answer, trimmed: from a string or the text input's {value}.
    static func typedText(_ response: Any) -> String {
        if let s = response as? String { return s.trimmed }
        if let d = response as? [String: Any] {
            let v = [d["value"], d["text"], d["message"]].first(where: { !JS.isNullish($0) }) ?? nil
            if let v = v, !(v is [Any] || v is [String: Any]) { return JS.str(v).trimmed }
        }
        if JS.isNumber(response) { return JS.str(response) }
        return ""
    }

    /// The id of the button / option the visitor picked.
    static func pickedId(_ response: Any) -> String? {
        if let d = response as? [String: Any] {
            let id = [d["buttonId"], d["choiceId"], d["optionId"], d["id"], d["selectedId"]].first(where: { !JS.isNullish($0) }) ?? nil
            return id.map { JS.str($0) }
        }
        if JS.isNullish(response) { return nil }
        return JS.str(response)
    }

    /// A text field as the RN SDK's getString reads it: text as it is, any
    /// other value as text, null or missing the default.
    static func string(_ data: [String: Any], _ key: String, _ fallback: String = "") -> String {
        guard let v = data[key], !JS.isNullish(v) else { return fallback }
        return JS.str(v)
    }

    /// The node's data.
    static func data(_ node: [String: Any]) -> [String: Any] { JS.dict(node["data"]) }

    /// The node's id.
    static func id(_ node: [String: Any]) -> String { JS.text(node["id"]) }

    /// Choice options for the pills.
    static func options(_ list: [(id: String, label: String, value: String)]) -> [ButtonOption] {
        list.map { ButtonOption(id: $0.id, label: $0.label, url: nil, action: nil) }
    }
}
