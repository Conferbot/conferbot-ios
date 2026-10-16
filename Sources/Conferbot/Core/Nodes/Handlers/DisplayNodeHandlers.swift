//
//  DisplayNodeHandlers.swift
//  Conferbot
//
//  The steps that show something and move on: welcome, message, image,
//  video, audio, file, html, user-redirect - and navigate, which waits for
//  Done. Field names and behaviour follow the flow-node spec
//  (conferbot-react-native scripts/parity/flows/nodes.spec.json) and the web
//  widget's ts/chat/displayStep.ts. The engine paces the typing dots and
//  moves on (images and videos when their media settles, at 4000 ms at most).
//

import Foundation

/// Where a redirect / navigate link goes: answers filled in, a same-site path kept (web redirectHref).
func redirectHref(_ link: Any?, _ state: ChatState) -> String {
    let filled = FlowText.fillLinkVariables(link) { state.lookupVariable($0) }
    let href = FlowInputs.linkHref(filled)
    if !href.isEmpty { return href }
    return filled.matches("^[/#?](?!/)") ? filled : ""
}

/// The file name a download card shows, from the URL.
private func fileNameOf(_ url: String) -> String {
    let path = url.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? url
    let last = path.components(separatedBy: "/").last ?? ""
    let name = last.removingPercentEncoding ?? last
    return name.isEmpty ? "download" : name
}

// MARK: - Welcome

/// welcome-node: data.text, then data.image unless disableImage.
public final class WelcomeNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "welcome-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        let html = FlowKit.filledHtml(state, data["text"])
        FlowKit.botSay(state, html: html, nodeId: nodeId, nodeType: nodeType)
        let image = (data["image"] as? String)?.trimmed ?? ""
        if !image.isEmpty, !JS.truthy(data["disableImage"]) {
            FlowKit.botSay(state, text: "", nodeId: nodeId, nodeType: nodeType, data: ["imageUrl": image])
        }
        return .displayUI(.message(text: FlowText.bubbleText(html), typing: false))
    }
}

// MARK: - Message

/// message-node: data.text, filled from the answers. Blank text is skipped by the engine.
public final class MessageNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.sendMessage }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let html = FlowKit.filledHtml(state, FlowKit.data(node)["text"])
        FlowKit.botSay(state, html: html, nodeId: FlowKit.id(node), nodeType: nodeType)
        return .displayUI(.message(text: FlowText.bubbleText(html), typing: false))
    }
}

// MARK: - Media

/// image-node: data.image (not filled). Moves on when it loads, or at the cap.
public final class ImageNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.sendImage }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let nodeId = FlowKit.id(node)
        let url = JS.text(FlowKit.data(node)["image"]).trimmed
        FlowKit.botSay(state, text: "", nodeId: nodeId, nodeType: nodeType, data: ["imageUrl": url, "mediaNodeId": nodeId])
        return .displayUI(.image(url: url, caption: nil))
    }
}

/// video-node: data.video (an mp4), allowDownload only when true.
public final class VideoNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.sendVideo }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let nodeId = FlowKit.id(node)
        let data = FlowKit.data(node)
        let url = (data["video"] as? String)?.trimmed ?? ""
        FlowKit.botSay(state, text: url, nodeId: nodeId, nodeType: nodeType,
                       data: ["videoUrl": url, "mediaNodeId": nodeId, "allowDownload": JS.bool(data["allowDownload"]) == true])
        return .displayUI(.video(url: url, caption: nil))
    }
}

/// audio-node: data.audio. Some live nodes saved a list there, which the web
/// does not read (a broken player) - the step still moves on.
public final class AudioNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.sendAudio }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let url = (FlowKit.data(node)["audio"] as? String)?.trimmed ?? ""
        FlowKit.botSay(state, text: url, nodeId: FlowKit.id(node), nodeType: nodeType, data: ["audioUrl": url])
        return .displayUI(.audio(url: url))
    }
}

/// file-node: a download card for data.file, named from the URL.
public final class FileNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.sendFile }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let url = (FlowKit.data(node)["file"] as? String)?.trimmed ?? ""
        let name = url.isEmpty ? "download" : fileNameOf(url)
        FlowKit.botSay(state, text: url, nodeId: FlowKit.id(node), nodeType: nodeType, data: ["fileUrl": url, "fileName": name])
        return .displayUI(.file(url: url, name: name))
    }
}

// MARK: - HTML

/// html-node: data.html, answers filled (escaped), then sanitised.
public final class HTMLNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "html-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let content = FlowText.sanitizeOwnerHtml(FlowText.fillVariables(FlowKit.data(node)["html"] ?? "", { state.lookupVariable($0) }))
        FlowKit.botSay(state, text: FlowKit.shownText(state, content), nodeId: FlowKit.id(node), nodeType: nodeType, data: ["html": content])
        return .displayUI(.embed(html: content))
    }
}

// MARK: - Redirect

/// user-redirect-node: a link card - redirectPrompt as its label, data.link
/// as where it goes. It never navigates by itself; the flow moves on.
public final class RedirectNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "user-redirect-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = FlowKit.data(node)
        let href = redirectHref(data["link"], state)
        let label = FlowText.fillVariables(FlowText.stripHtmlAndDecode(data["redirectPrompt"] ?? ""), { state.lookupVariable($0) }, mode: .raw).trimmed
        FlowKit.botSay(state, text: href.isEmpty ? label : "\(label)\n\(href)", nodeId: FlowKit.id(node), nodeType: nodeType,
                       data: ["linkUrl": href, "linkLabel": label, "openInNewTab": data["openInNewTab"] ?? true])
        return .displayUI(href.isEmpty ? .message(text: label, typing: false) : .link(url: href, text: label))
    }
}

// MARK: - Navigate

/// navigate-node: the prompt, one button per navigateOptions link (blank
/// ones hidden) and Done. A link opens its page and does not move on;
/// Done moves on after 600 ms.
public final class NavigateNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "navigate-node" }

    private func options(_ data: [String: Any]) -> [[String: Any]] {
        JS.dicts(data["navigateOptions"]).filter { !JS.text($0["navigateText"]).trimmed.isEmpty }
    }

    private func doneLabel(_ data: [String: Any]) -> String {
        let s = JS.text(data["doneNavigatingText"]).trimmed
        return s.isEmpty ? I18n.t("common.done") : s
    }

    private func label(_ o: [String: Any], _ state: ChatState) -> String {
        FlowText.fillVariables(FlowText.stripHtmlAndDecode(o["navigateText"] ?? ""), { state.lookupVariable($0) }, mode: .raw).trimmed
    }

    private func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        let data = FlowKit.data(node)
        var buttons = options(data).enumerated().map { i, o in
            ButtonOption(id: "link-\(i)", label: label(o, state), url: redirectHref(o["navigateLink"], state), action: "link")
        }
        buttons.append(ButtonOption(id: "done", label: doneLabel(data), url: nil, action: "done"))
        return .buttons(buttons: buttons, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let html = FlowKit.filledHtml(state, FlowKit.data(node)["navigatePrompt"])
        if !FlowText.bubbleText(html).isEmpty { FlowKit.botSay(state, html: html, nodeId: FlowKit.id(node), nodeType: nodeType) }
        return .displayUI(ui(node, state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        let r = JS.dict(response)
        let id = JS.text(r["buttonId"])
        let isLink = JS.text(r["action"]) == "link" || id.hasPrefix("link-")
        if isLink {
            let index = JS.text(r["action"]) == "link" ? Int(JS.toNumber(r["index"])) : Int(id.dropFirst(5)) ?? -1
            let opts = options(data)
            if index >= 0, index < opts.count {
                let o = opts[index]
                FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-navigate-link-click", "text": label(o, state), "url": redirectHref(o["navigateLink"], state)])
            }
            // A link opens its page; the step keeps waiting for Done.
            return .displayUI(ui(node, state))
        }
        let text = doneLabel(data)
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-navigate-done", "text": text])
        FlowKit.userSay(state, text, nodeId)
        return .delayedProceed(0.6, nil)
    }
}

/// The display steps.
enum DisplayNodeHandlers {
    static var all: [NodeHandler] {
        [WelcomeNodeHandler(), MessageNodeHandler(), ImageNodeHandler(), VideoNodeHandler(), AudioNodeHandler(),
         FileNodeHandler(), HTMLNodeHandler(), RedirectNodeHandler(), NavigateNodeHandler()]
    }
}
