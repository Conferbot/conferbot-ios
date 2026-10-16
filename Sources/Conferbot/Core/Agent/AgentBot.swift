//
//  AgentBot.swift
//  Conferbot
//
//  AI agent bots (Agent Studio): bots with no flow of their own, answered
//  by an AI agent from the first message.
//
//  The server marks one with `chatbotData.agentBot` on fetched-chatbot-data
//  (embed-server chatbotController getChatbotElementsSocket). Such a bot
//  still ships a one-node shell flow (welcome -> handover to the agent) for
//  older clients, but running it as-is stages a handover the visitor should
//  never see. With agentBot set the SDK opens straight into the agent chat
//  and reuses the handover socket path silently underneath (silentStart),
//  as the web widget does (conferbot-widget index.ts _startAgentBotChat,
//  ts/chat/agentShell.ts).
//
//  Also here: the AI reply's extras as the server sends them on
//  agent-message (sources, follow-ups, action buttons, cards, an action to
//  confirm), cleaned the same way the web widget cleans them. Pure:
//  Foundation only, so it builds and is tested on Linux too.
//

import Foundation

public struct AgentBot: Equatable {
    public let agentId: String
    public let displayName: String
    public let greeting: String
    /// Suggested first questions, shown as chips under the greeting.
    public let starters: [String]
    public let avatar: String?

    /// The agent as the chat presents it - the id the server sends in agentDetails.
    public var agentDetailsId: String { "ai-agent-\(agentId)" }
}

public struct AgentSource: Codable, Equatable {
    public let title: String
    public let url: String?
    public let articleId: String?
    public let snippet: String?
}

public struct AnswerAction: Codable, Equatable {
    public let label: String
    public let url: String
}

public struct CardRow: Codable, Equatable {
    public let label: String
    public let value: String
}

public struct AnswerCard: Codable, Equatable {
    public let title: String?
    public let rows: [CardRow]
    public let note: String?
    public let url: String?
}

public struct ResultCard: Codable, Equatable {
    public let title: String
    public let status: String?
    /// done | moving | problem | neutral
    public let tone: String
    public let rows: [CardRow]
    public let linkURL: String?
    public let linkLabel: String?
}

public struct ActionRequest: Codable, Equatable {
    public let token: String
    public let name: String
    public let summary: [CardRow]
}

/// An article, quick replies or a card from the agent (agent-message-rich).
public enum RichEntry: Equatable {
    case article(articleId: String, title: String, snippet: String, url: String?)
    case quickReplies(text: String, options: [String])
    case card(title: String, description: String, imageURL: String?, buttonLabel: String?, buttonURL: String?)
}

/// What an AI reply carries besides its text.
public struct AIReplyExtras: Codable, Equatable {
    public var sources: [AgentSource] = []
    public var actions: [AnswerAction] = []
    public var card: AnswerCard? = nil
    public var resultCard: ResultCard? = nil
    public var actionRequest: ActionRequest? = nil
    public var isFallback: Bool = false

    public var isEmpty: Bool {
        sources.isEmpty && actions.isEmpty && card == nil && resultCard == nil && actionRequest == nil
    }
}

/// The AI reply as it is being written: one live bubble, replaced by the
/// finished agent-message.
public struct AgentStream: Equatable {
    public let id: String
    public let text: String
    public let agentDetails: AgentDetails
}

public enum AgentBotParser {
    public static let defaultAgentName = "AI Assistant"
    public static let defaultGreeting = "Hi! How can I help you today?"
    public static let maxSources = 3
    /// The "Helpful?" reasons (AnswerFeedback.swift).
    public static var feedbackReasons: [(key: String, label: String)] { HelpfulRow.reasons }

    /// How long the "writing a reply" dots wait for the AI (web
    /// agentListeners.ts AWAITING_REPLY_MAX_MS): the AI path stays silent when
    /// the provider fails twice, so without a ceiling they would run forever.
    public static let awaitReplySeconds: Double = 45
    /// Said when that ceiling is hit, so the dots do not just vanish (web chat.replyTimeout).
    public static let replyTimeoutText = "That took too long. Try again, or ask for a human."

    /// The notice as an on-screen line: not part of the conversation's record, as on the web.
    public static func replyTimeoutNotice(now: Date = Date()) -> SystemMessageRecord {
        SystemMessageRecord(id: "reply-timeout-\(Int(now.timeIntervalSince1970 * 1000))", time: now, text: replyTimeoutText)
    }

    // MARK: - Helpers

    private static func matches(_ value: String, _ pattern: String, caseInsensitive: Bool = true) -> Bool {
        let options: NSString.CompareOptions = caseInsensitive ? [.regularExpression, .caseInsensitive] : [.regularExpression]
        return value.range(of: pattern, options: options) != nil
    }

    private static func clean(_ value: Any?, _ max: Int) -> String {
        if let s = value as? String {
            let collapsed = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            return String(collapsed.prefix(max))
        }
        if let n = value as? Int { return String(n) }
        if let d = value as? Double {
            return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        }
        return ""
    }

    private static func httpURL(_ value: Any?) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespaces), matches(s, "^https?://[^\\s\"'<>]+$") else { return nil }
        return s
    }

    private static func httpsURL(_ value: Any?) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespaces), matches(s, "^https://[^\\s\"'<>]+$") else { return nil }
        return s
    }

    private static func isObjectId(_ value: String?) -> Bool {
        guard let v = value else { return false }
        return matches(v, "^[a-f0-9]{24}$")
    }

    private static func list(_ value: Any?) -> [Any] { value as? [Any] ?? [] }
    private static func dict(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

    // MARK: - Agent bot

    /// The agent bot config from chatbotData, or nil for every flow bot.
    public static func parseAgentBot(_ chatbotData: [String: Any]?) -> AgentBot? {
        guard let a = dict(chatbotData?["agentBot"]) else { return nil }
        let agentId: String
        if let s = a["agentId"] as? String { agentId = s } else if let n = a["agentId"] { agentId = "\(n)" } else { return nil }
        guard !agentId.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var seen = Set<String>()
        let starters = list(a["starters"]).map { item -> String in
            clean(item is String ? item : dict(item)?["text"], 80)
        }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        var name = clean(a["displayName"], 60)
        if name.isEmpty { name = clean(chatbotData?["name"], 60) }
        if name.isEmpty { name = defaultAgentName }
        let avatar = (a["avatar"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return AgentBot(
            agentId: agentId,
            displayName: name,
            greeting: (a["greeting"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            starters: Array(starters.prefix(4)),
            avatar: avatar
        )
    }

    /// The agentDetails dictionary the server sends for this agent.
    public static func agentDetails(of bot: AgentBot) -> [String: Any] {
        ["_id": bot.agentDetailsId, "name": bot.displayName, "avatar": bot.avatar ?? "", "isAIAgent": true]
    }

    /// Is this agentDetails an AI agent rather than a person?
    public static func isAIAgent(_ details: [String: Any]?) -> Bool {
        guard let d = details else { return false }
        if d["isAIAgent"] as? Bool == true { return true }
        return (d["_id"] as? String)?.hasPrefix("ai-agent-") == true
    }

    public static func isAgentShellHandover(_ node: [String: Any], agentId: String) -> Bool {
        guard node["type"] as? String == "human-handover-node" else { return false }
        return list(dict(node["data"])?["assignedAIAgents"]).map { "\($0)" }.contains(agentId)
    }

    /// The shell's welcome and handover nodes. A bot switched from a flow keeps
    /// the owner's flow too, so only the handover assigned to this agent counts.
    public static func agentShellNodes(_ nodes: [[String: Any]], agentId: String) -> (welcome: [String: Any]?, handover: [String: Any]?) {
        guard let handover = nodes.first(where: { isAgentShellHandover($0, agentId: agentId) }) else { return (nil, nil) }
        return (nodes.first { $0["type"] as? String == "welcome-node" }, handover)
    }

    /// Handover data for the agent chat: never a form, message or wait before it.
    public static func agentHandoverData(_ shellData: [String: Any]?, agentId: String) -> [String: Any] {
        var out: [String: Any] = ["assignmentType": "auto", "assignedAgents": [String]()]
        shellData?.forEach { out[$0.key] = $0.value }
        out["assignedAIAgents"] = [agentId]
        out["handoverMessage"] = ""
        out["enablePreChatQuestions"] = false
        out["preChatQuestions"] = [Any]()
        return out
    }

    /// Is the AI still answering? The latest word wins.
    public static func isAgentAIActive(_ recordTypes: [String?]) -> Bool {
        for type in recordTypes.reversed() {
            if type == "ai-agent-resumed" { return true }
            if type == "agent-left-chat" || type == "agent-chat-ended" || type == "ai-agent-inactive-close" { return false }
        }
        return true
    }

    // MARK: - Reply extras

    /// "https://www.conferbot.com/pricing" -> "conferbot.com"
    public static func sourceHost(_ url: String?) -> String {
        guard let url = url, let host = URL(string: url)?.host, matches(url, "^https?://") else { return "" }
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    /// Sources an AI reply was grounded in: http(s) pages or help articles, at most three.
    public static func normalizeSources(_ raw: Any?) -> [AgentSource] {
        var seen = Set<String>()
        var out: [AgentSource] = []
        for item in list(raw) {
            guard let m = dict(item) else { continue }
            let articleId = isObjectId(m["articleId"] as? String) ? m["articleId"] as? String : nil
            let url = ((m["url"] ?? m["sourceUrl"]) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let key = articleId.map { "article:\($0)" } ?? url
            if (articleId == nil && !matches(url, "^https?://")) || !seen.insert(key).inserted { continue }
            let snippetText = clean(m["snippet"] ?? m["description"] ?? m["excerpt"], 220)
            let snippet = snippetText.isEmpty ? nil : snippetText
            let title = clean(m["title"], 160)
            if let id = articleId {
                out.append(AgentSource(title: title.isEmpty ? "Help article" : title, url: httpURL(url), articleId: id, snippet: snippet))
            } else {
                out.append(AgentSource(title: title.isEmpty ? sourceHost(url) : title, url: url, articleId: nil, snippet: snippet))
            }
            if out.count >= maxSources { break }
        }
        return out
    }

    /// The buttons under an answer: labelled, http(s), at most two, once each.
    public static func answerActions(_ raw: Any?) -> [AnswerAction] {
        var seen = Set<String>()
        let actions: [AnswerAction] = list(raw).compactMap { item in
            guard let m = dict(item), let url = httpURL(m["url"]) else { return nil }
            let label = clean(m["label"], 28)
            guard !label.isEmpty, seen.insert(url).inserted else { return nil }
            return AnswerAction(label: label, url: url)
        }
        return Array(actions.prefix(2))
    }

    private static func rows(_ raw: Any?, _ max: Int) -> [CardRow] {
        let all: [CardRow] = list(raw).compactMap { item in
            guard let pair = item as? [Any], pair.count >= 2 else { return nil }
            let a = clean(pair[0], 40), b = clean(pair[1], 60)
            return a.isEmpty || b.isEmpty ? nil : CardRow(label: a, value: b)
        }
        return Array(all.prefix(max))
    }

    private static func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    /// Facts from the knowledge as a card: a title, two to six rows, a note, a link.
    public static func answerCard(_ raw: Any?) -> AnswerCard? {
        guard let m = dict(raw) else { return nil }
        let r = rows(m["rows"], 6)
        guard r.count >= 2 else { return nil }
        return AnswerCard(title: nonEmpty(clean(m["title"], 60)), rows: r, note: nonEmpty(clean(m["note"], 120)), url: httpsURL(m["url"]))
    }

    /// What an action did ("Order #1042 · In transit"), as a card.
    public static func resultCard(_ raw: Any?) -> ResultCard? {
        guard let m = dict(raw) else { return nil }
        let r = rows(m["rows"], 5)
        let status = nonEmpty(clean(m["status"], 30))
        guard !r.isEmpty || status != nil else { return nil }
        let toneRaw = m["tone"] as? String ?? ""
        let tone = ["done", "moving", "problem", "neutral"].contains(toneRaw) ? toneRaw : "neutral"
        let link = dict(m["link"])
        let url = httpsURL(link?["url"])
        let label = clean(link?["label"], 24)
        return ResultCard(
            title: nonEmpty(clean(m["title"], 50)) ?? "Done",
            status: status,
            tone: tone,
            rows: r,
            linkURL: url,
            linkLabel: url == nil ? nil : (label.isEmpty ? "Open" : label)
        )
    }

    /// An action the AI is about to take, for the visitor to confirm.
    public static func actionRequest(_ raw: Any?) -> ActionRequest? {
        guard let m = dict(raw), let token = m["token"] as? String, !token.isEmpty, let name = m["name"] as? String else { return nil }
        let summary: [CardRow] = list(m["summary"]).compactMap { item in
            guard let line = dict(item), let label = line["label"] as? String, let value = line["value"] else { return nil }
            let text = clean(value, 120)
            return CardRow(label: String(label.prefix(40)), value: text.isEmpty ? String("\(value)".prefix(120)) : text)
        }
        return ActionRequest(token: token, name: String(name.prefix(80)), summary: Array(summary.prefix(8)))
    }

    /// What the visitor may ask next: at most three short questions.
    public static func followUps(_ raw: Any?) -> [String] {
        Array(list(raw).compactMap { $0 as? String }.map { clean($0, 120) }.filter { !$0.isEmpty }.prefix(3))
    }

    /// An agent's rich message as it may be drawn, or nil.
    public static func safeRich(_ raw: Any?) -> RichEntry? {
        guard let m = dict(raw) else { return nil }
        switch m["kind"] as? String {
        case "article":
            let title = clean(m["title"], 80)
            guard !title.isEmpty else { return nil }
            return .article(articleId: clean(m["articleId"], 40), title: title, snippet: clean(m["snippet"], 200), url: httpsURL(m["url"]))
        case "quick_replies":
            let options = Array(list(m["options"]).map { clean($0, 40) }.filter { !$0.isEmpty }.prefix(4))
            guard options.count >= 2 else { return nil }
            return .quickReplies(text: clean(m["text"], 300), options: options)
        case "card":
            let title = clean(m["title"], 80)
            guard !title.isEmpty else { return nil }
            let button = dict(m["button"])
            let label = clean(button?["label"], 30)
            let url = httpsURL(button?["url"])
            let hasButton = !label.isEmpty && url != nil
            return .card(title: title, description: clean(m["description"], 300), imageURL: httpsURL(m["imageUrl"]),
                         buttonLabel: hasButton ? label : nil, buttonURL: hasButton ? url : nil)
        default:
            return nil
        }
    }

    /// A rich entry back in its server shape (for the record and persistence).
    public static func richDictionary(_ rich: RichEntry) -> [String: Any] {
        switch rich {
        case let .article(articleId, title, snippet, url):
            return ["kind": "article", "articleId": articleId, "title": title, "snippet": snippet, "url": url ?? NSNull()]
        case let .quickReplies(text, options):
            return ["kind": "quick_replies", "text": text, "options": options]
        case let .card(title, description, imageURL, buttonLabel, buttonURL):
            var d: [String: Any] = ["kind": "card", "title": title, "description": description, "imageUrl": imageURL ?? NSNull()]
            if let l = buttonLabel, let u = buttonURL { d["button"] = ["label": l, "url": u] }
            return d
        }
    }

    /// The owner's quick actions above the composer: labelled, safe links, at most three.
    public static func quickActions(_ customizations: [String: Any]?) -> [AnswerAction] {
        let actions: [AnswerAction] = list(customizations?["chatQuickActions"]).compactMap { item in
            guard let m = dict(item) else { return nil }
            let label = clean(m["label"], 30)
            let raw = (m["url"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let url = httpURL(raw) ?? (matches(raw, "^(mailto|tel):") ? raw : nil)
            guard !label.isEmpty, let u = url else { return nil }
            return AnswerAction(label: label, url: u)
        }
        return Array(actions.prefix(3))
    }

    /// "Helpful?" under AI answers unless the owner turned it off.
    public static func answerFeedbackOn(_ customizations: [String: Any]?) -> Bool {
        customizations?["hideAnswerFeedback"] as? Bool != true
    }

    /// Only an AI answer stored under its server id can be rated.
    public static func canRate(_ messageId: String?) -> Bool { isObjectId(messageId) }

    /// The conversion a link stands for, in the analytics vocabulary.
    public static func conversionEvent(label: String, url: String = "") -> String {
        let t = "\(label) \(url)".lowercased()
        if matches(t, "demo|book|meeting|call|calendly") { return "demo_booked" }
        if matches(t, "trial|sign ?up|register|get started|start free") { return "signup" }
        if matches(t, "buy|purchase|checkout|order|cart") { return "purchase" }
        if matches(t, "contact|email|quote") { return "contact_form" }
        if matches(t, "download") { return "download" }
        return "custom"
    }

    /// The extras of an agent-message payload; nil for a person's message.
    public static func aiReplyExtras(_ data: [String: Any]) -> AIReplyExtras? {
        guard isAIAgent(dict(data["agentDetails"])) else { return nil }
        let sources = normalizeSources(data["sources"] ?? data["citations"])
        if data["isFallback"] as? Bool == true {
            return AIReplyExtras(sources: sources, isFallback: true)
        }
        return AIReplyExtras(
            sources: sources,
            actions: answerActions(data["actions"]),
            card: answerCard(data["card"]),
            resultCard: resultCard(data["resultCard"]),
            actionRequest: actionRequest(data["actionRequest"])
        )
    }
}
