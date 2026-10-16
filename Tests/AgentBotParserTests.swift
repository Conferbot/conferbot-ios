//
//  AgentBotParserTests.swift
//  Conferbot
//
//  AI agent bots (Agent Studio): the agentBot config, the shell nodes, the
//  reply extras cleaned like the web widget, and the message text format.
//

import XCTest
@testable import Conferbot

final class AgentBotParserTests: XCTestCase {

    func testReadsAgentBotOnlyWhenWellFormed() {
        XCTAssertNil(AgentBotParser.parseAgentBot([:]))
        XCTAssertNil(AgentBotParser.parseAgentBot(["agentBot": NSNull()]))
        XCTAssertNil(AgentBotParser.parseAgentBot(["agentBot": ["displayName": "x"]]))
        let bot = AgentBotParser.parseAgentBot([
            "name": "Shop",
            "agentBot": [
                "agentId": "a1",
                "greeting": " Hi there ",
                "starters": ["Pricing?", "pricing?", "", ["text": "Refunds"]],
                "avatar": "https://x/a.png"
            ] as [String: Any]
        ])
        XCTAssertEqual(bot, AgentBot(agentId: "a1", displayName: "Shop", greeting: "Hi there", starters: ["Pricing?", "Refunds"], avatar: "https://x/a.png"))
        XCTAssertEqual(bot?.agentDetailsId, "ai-agent-a1")
    }

    func testKnowsAnAIAgentFromAPerson() {
        XCTAssertTrue(AgentBotParser.isAIAgent(["isAIAgent": true]))
        XCTAssertTrue(AgentBotParser.isAIAgent(["_id": "ai-agent-x"]))
        XCTAssertFalse(AgentBotParser.isAIAgent(["_id": "64f0", "name": "Sam"]))
        XCTAssertFalse(AgentBotParser.isAIAgent(nil))
    }

    func testUsesOnlyTheAgentsOwnHandover() {
        let nodes: [[String: Any]] = [
            ["id": "w", "type": "welcome-node"],
            ["id": "h1", "type": "human-handover-node", "data": ["assignedAIAgents": ["other"]]],
            ["id": "h2", "type": "human-handover-node", "data": ["assignedAIAgents": ["a1"], "enablePreChatQuestions": true, "handoverMessage": "wait", "priority": "high"] as [String: Any]]
        ]
        let shell = AgentBotParser.agentShellNodes(nodes, agentId: "a1")
        XCTAssertEqual(shell.welcome?["id"] as? String, "w")
        XCTAssertEqual(shell.handover?["id"] as? String, "h2")
        XCTAssertNil(AgentBotParser.agentShellNodes(Array(nodes.prefix(2)), agentId: "a1").handover)
        let data = AgentBotParser.agentHandoverData(shell.handover?["data"] as? [String: Any], agentId: "a1")
        XCTAssertEqual(data["assignedAIAgents"] as? [String], ["a1"])
        XCTAssertEqual(data["handoverMessage"] as? String, "")
        XCTAssertEqual(data["enablePreChatQuestions"] as? Bool, false)
        XCTAssertEqual(data["priority"] as? String, "high")
    }

    func testKnowsWhenTheAIIsStillAnswering() {
        XCTAssertTrue(AgentBotParser.isAgentAIActive([]))
        XCTAssertFalse(AgentBotParser.isAgentAIActive(["agent-left-chat"]))
        XCTAssertTrue(AgentBotParser.isAgentAIActive(["ai-agent-inactive-close", "ai-agent-resumed"]))
    }

    func testCleansSourcesButtonsAndCards() {
        let sources = AgentBotParser.normalizeSources([
            ["title": "Pricing", "url": "https://www.acme.com/pricing"],
            ["title": "dup", "url": "https://www.acme.com/pricing"],
            ["title": "bad", "url": "javascript:alert(1)"],
            ["title": "Refunds", "articleId": "0123456789abcdef01234567"],
            ["url": "https://acme.com/a"],
            ["url": "https://acme.com/b"]
        ])
        XCTAssertEqual(sources.map { $0.title }, ["Pricing", "Refunds", "acme.com"])
        XCTAssertEqual(AgentBotParser.sourceHost("https://www.conferbot.com/pricing"), "conferbot.com")
        XCTAssertEqual(
            AgentBotParser.answerActions([["label": "See pricing", "url": "https://a.co/p"], ["label": "x", "url": "ftp://a"], ["label": "Again", "url": "https://a.co/p"]]),
            [AnswerAction(label: "See pricing", url: "https://a.co/p")]
        )
        XCTAssertNil(AgentBotParser.answerCard(["rows": [["Pro", "$49"]]]))
        XCTAssertEqual(
            AgentBotParser.answerCard(["title": "Plans", "rows": [["Pro", "$49"], ["Team", 99]], "url": "http://insecure"] as [String: Any]),
            AnswerCard(title: "Plans", rows: [CardRow(label: "Pro", value: "$49"), CardRow(label: "Team", value: "99")], note: nil, url: nil)
        )
        let result = AgentBotParser.resultCard(["title": "Order", "status": "In transit", "tone": "weird", "link": ["url": "https://t.co/1"]] as [String: Any])
        XCTAssertEqual(result?.tone, "neutral")
        XCTAssertEqual(result?.linkLabel, "Open")
        XCTAssertEqual(
            AgentBotParser.actionRequest(["token": "t", "name": "Cancel order", "summary": [["label": "Order", "value": 1042], ["nope": 1]]] as [String: Any]),
            ActionRequest(token: "t", name: "Cancel order", summary: [CardRow(label: "Order", value: "1042")])
        )
        XCTAssertNil(AgentBotParser.actionRequest(["name": "x"]))
        XCTAssertEqual(AgentBotParser.followUps(["a", "", 3, "b", "c", "d"]), ["a", "b", "c"])
    }

    func testKeepsOnlyDrawableRichMessages() {
        XCTAssertNil(AgentBotParser.safeRich(["kind": "quick_replies", "options": ["Yes"]]))
        XCTAssertEqual(AgentBotParser.safeRich(["kind": "quick_replies", "text": "Pick", "options": ["Yes", "No"]]), .quickReplies(text: "Pick", options: ["Yes", "No"]))
        XCTAssertEqual(
            AgentBotParser.safeRich(["kind": "card", "title": "Pro", "imageUrl": "http://x", "button": ["label": "Buy", "url": "https://b"]] as [String: Any]),
            .card(title: "Pro", description: "", imageURL: nil, buttonLabel: "Buy", buttonURL: "https://b")
        )
        XCTAssertNil(AgentBotParser.safeRich(["kind": "video"]))
        let card = RichEntry.card(title: "Pro", description: "d", imageURL: nil, buttonLabel: "Buy", buttonURL: "https://b")
        XCTAssertEqual(AgentBotParser.safeRich(AgentBotParser.richDictionary(card)), card)
    }

    func testExtrasOnlyOnAIRepliesAndOnlySourcesOnAFallback() {
        XCTAssertNil(AgentBotParser.aiReplyExtras(["agentDetails": ["_id": "u1"], "sources": [["url": "https://a.co"]]]))
        let ai: [String: Any] = ["_id": "ai-agent-a1", "isAIAgent": true]
        let fallback = AgentBotParser.aiReplyExtras(["agentDetails": ai, "isFallback": true, "actions": [["label": "x", "url": "https://a.co"]]])
        XCTAssertEqual(fallback?.isFallback, true)
        XCTAssertEqual(fallback?.actions, [])
        let reply = AgentBotParser.aiReplyExtras(["agentDetails": ai, "actions": [["label": "Go", "url": "https://a.co"]]])
        XCTAssertEqual(reply?.actions, [AnswerAction(label: "Go", url: "https://a.co")])
    }

    func testQuickActionsRatingsAndGoals() {
        let actions = AgentBotParser.quickActions(["chatQuickActions": [
            ["label": "Book a demo", "url": "https://cal.com/x"], ["label": "Mail", "url": "mailto:a@b.co"], ["label": "x", "url": "javascript:1"]
        ]])
        XCTAssertEqual(actions.map { $0.label }, ["Book a demo", "Mail"])
        XCTAssertFalse(AgentBotParser.answerFeedbackOn(["hideAnswerFeedback": true]))
        XCTAssertTrue(AgentBotParser.answerFeedbackOn(nil))
        XCTAssertTrue(AgentBotParser.canRate("0123456789abcdef01234567"))
        XCTAssertFalse(AgentBotParser.canRate("agent-greeting-s1"))
        XCTAssertEqual(AgentBotParser.conversionEvent(label: "Book a demo"), "demo_booked")
    }

    func testExtrasSurviveTheCodableRoundTrip() throws {
        let extras = AIReplyExtras(sources: [AgentSource(title: "Pricing", url: "https://a.co", articleId: nil, snippet: nil)],
                                   card: AnswerCard(title: "Plans", rows: [CardRow(label: "Pro", value: "$49"), CardRow(label: "Team", value: "$99")], note: nil, url: nil))
        let back = try JSONDecoder().decode(AIReplyExtras.self, from: JSONEncoder().encode(extras))
        XCTAssertEqual(back, extras)
    }

    // MARK: - Message text

    func testTurnsTheInboxHTMLIntoMarkdown() {
        XCTAssertEqual(ChatMarkdown.htmlToMarkdown("<p>Hi <strong>Sam</strong></p><p>See <a href=\"https://a.co/x\">this</a> &amp; that</p>"),
                       "Hi **Sam**\n\nSee [this](https://a.co/x) & that")
        XCTAssertEqual(ChatMarkdown.htmlToMarkdown("<a href=\"javascript:alert(1)\">click</a>"), "click")
        XCTAssertEqual(ChatMarkdown.htmlToMarkdown("<p>**Pro** is $49</p>"), "**Pro** is $49")
    }

    func testParsesInlineRuns() {
        XCTAssertEqual(ChatMarkdown.parseInline("a **b** _c_ `d` [e](https://e.co) https://f.co/x."), [
            .plain("a "), .bold("b"), .plain(" "), .italic("c"), .plain(" "), .code("d"), .plain(" "),
            .link(text: "e", url: "https://e.co"), .plain(" "), .link(text: "https://f.co/x", url: "https://f.co/x"), .plain(".")
        ])
        XCTAssertEqual(ChatMarkdown.parseInline("snake_case_name stays"), [.plain("snake_case_name stays")])
        XCTAssertEqual(ChatMarkdown.parseInline("[x](javascript:1)"), [.plain("x")])
    }

    func testParsesListsAndParagraphs() {
        let blocks = ChatMarkdown.parse("## Plans\nWe have:\n- Pro\n2. Team\n\nBye")
        // The heading is its own block (#49).
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(ChatMarkdown.plainText(blocks), "Plans\nWe have:\n• Pro\n2. Team\nBye")
    }
}
