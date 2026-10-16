//
//  RestoredMessagesTests.swift
//  A conversation saved and read back after a restart draws as it was
//  (#65): a bot message keeps its node data (a standalone image, answered
//  choice pills, its step), and every kind of message comes back as itself.
//

import XCTest
@testable import Conferbot

final class RestoredMessagesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var storage: UserDefaultsSessionStorage!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "RestoredMessagesTests")
        defaults.removePersistentDomain(forName: "RestoredMessagesTests")
        storage = UserDefaultsSessionStorage(userDefaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "RestoredMessagesTests")
        super.tearDown()
    }

    func testABotMessageKeepsItsNodeDataAcrossARestart() throws {
        let time = Date(timeIntervalSince1970: 1_792_058_400)
        let text = BotMessageRecord(id: "bot-1", time: time, text: "<p>Hi <b>there</b></p>",
                                    nodeData: ["nodeId": AnyCodable("n1"), "nodeType": AnyCodable("message-node")])
        let image = BotMessageRecord(id: "bot-2", time: time, text: nil, nodeData: ["imageUrl": AnyCodable("https://a.co/x.png")])
        let pills = BotMessageRecord(id: "choices-1", time: time, text: nil,
                                     nodeData: ["choices": AnyCodable(["Yes", "No"]), "selectedChoice": AnyCodable("No")])
        let agent = AgentMessageRecord(id: "0123456789abcdef01234567", time: time, text: "Answer",
                                       agentDetails: AgentDetails(id: "ai-agent-1", name: "Ava", email: "", isAIAgent: true),
                                       feedback: AnswerFeedback(helpful: false, reason: "wrong", comment: "late"))
        let user = UserMessageRecord(id: "u1", time: time, text: "Hello")
        let ended = SystemMessageRecord(id: "agent-chat-ended-1", time: time, text: "Chat has ended")

        try storage.saveMessages(messages: [text, image, pills, agent, user, ended], sessionId: "s1")
        let back = storage.loadMessages(sessionId: "s1")
        XCTAssertEqual(back.count, 6)

        let t = try XCTUnwrap(back[0] as? BotMessageRecord)
        XCTAssertEqual(t.text, "<p>Hi <b>there</b></p>")
        XCTAssertEqual(t.nodeData?["nodeType"]?.value as? String, "message-node")
        XCTAssertEqual(t.time, time)
        XCTAssertEqual((back[1] as? BotMessageRecord)?.nodeData?["imageUrl"]?.value as? String, "https://a.co/x.png")
        let p = try XCTUnwrap(back[2] as? BotMessageRecord)
        XCTAssertEqual(p.nodeData?["choices"]?.value as? [String], ["Yes", "No"])
        XCTAssertEqual(p.nodeData?["selectedChoice"]?.value as? String, "No")
        let a = try XCTUnwrap(back[3] as? AgentMessageRecord)
        XCTAssertEqual(a.agentDetails.isAIAgent, true)
        XCTAssertEqual(a.feedback, AnswerFeedback(helpful: false, reason: "wrong", comment: "late"))
        XCTAssertEqual((back[4] as? UserMessageRecord)?.text, "Hello")
        XCTAssertEqual((back[5] as? SystemMessageRecord)?.text, "Chat has ended")
    }
}
