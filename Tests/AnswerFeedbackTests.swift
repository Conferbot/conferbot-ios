//
//  AnswerFeedbackTests.swift
//  "Helpful?" under an AI answer as the web's answerFeedback.ts (#43): a No
//  goes at once, then a reason and a comment; Talk to a person, Ask another
//  way; the vote can change; only the newest unrated answer asks. The same
//  cases as the React Native SDK's answerFeedback.test.ts.
//

import XCTest
@testable import Conferbot

final class AnswerFeedbackTests: XCTestCase {

    private func play(_ start: HelpfulRow.State, _ taps: HelpfulRow.Tap...) -> (state: HelpfulRow.State, sent: [AnswerFeedback]) {
        var s = start
        var sent: [AnswerFeedback] = []
        for tap in taps {
            let r = HelpfulRow.step(s, tap)
            if let fb = r.send { sent.append(fb) }
            s = r.state
        }
        return (s, sent)
    }

    func testANoIsSentAtOnceWithoutWaitingForAReason() {
        let r = HelpfulRow.step(HelpfulRow.start(nil), .vote(false))
        XCTAssertEqual(r.send, AnswerFeedback(helpful: false))
        XCTAssertEqual(r.state.view, .down)
    }

    func testAReasonThenACommentEachGoAsTheyAreGiven() {
        let (s, sent) = play(HelpfulRow.start(nil), .vote(false), .reason("outdated"), .comment("  the   price changed \n"))
        XCTAssertEqual(sent, [
            AnswerFeedback(helpful: false),
            AnswerFeedback(helpful: false, reason: "outdated"),
            AnswerFeedback(helpful: false, reason: "outdated", comment: "the price changed"),
        ])
        XCTAssertTrue(s.commented)
        XCTAssertEqual(HelpfulRow.ratedLabel(s.current), "Not helpful \u{00B7} Outdated")
        // Once only.
        XCTAssertNil(HelpfulRow.step(s, .comment("again")).send)
    }

    func testACommentWithoutAReasonAndAnEmptyOneSendsNothing() {
        XCTAssertEqual(play(HelpfulRow.start(nil), .vote(false), .comment("meh")).sent.last, AnswerFeedback(helpful: false, comment: "meh"))
        let (s, sent) = play(HelpfulRow.start(nil), .vote(false), .comment("   "))
        XCTAssertEqual(sent, [AnswerFeedback(helpful: false)])
        XCTAssertTrue(s.commented)
    }

    func testYesThanksThenSettlesIntoTheRatedLine() {
        let (s, sent) = play(HelpfulRow.start(nil), .vote(true))
        XCTAssertEqual(sent, [AnswerFeedback(helpful: true)])
        XCTAssertEqual(s.view, .thanks)
        XCTAssertEqual(HelpfulRow.step(s, .settle).state.view, .rated)
        XCTAssertEqual(HelpfulRow.ratedLabel(s.current), "Helpful")
    }

    func testTheVoteCanChangeAndTheSameThumbAgainSendsNothing() {
        let start = HelpfulRow.start(AnswerFeedback(helpful: true))
        XCTAssertEqual(start.view, .rated)
        XCTAssertNil(HelpfulRow.step(start, .vote(true)).send)
        let (s, sent) = play(start, .vote(false))
        XCTAssertEqual(sent, [AnswerFeedback(helpful: false)])
        XCTAssertEqual(s.view, .down)
        // A settle after switching to No does not hide the reasons.
        XCTAssertEqual(HelpfulRow.step(s, .settle).state.view, .down)
    }

    func testTalkToAPersonAsksInTheVisitorsWordsAskAnotherWayFocuses() {
        let down = play(HelpfulRow.start(nil), .vote(false)).state
        let human = HelpfulRow.step(down, .human)
        XCTAssertEqual(human.ask, "I'd like to talk to a person, please.")
        XCTAssertEqual(human.state.view, .rated)
        let retry = HelpfulRow.step(down, .retry)
        XCTAssertTrue(retry.focus)
        XCTAssertEqual(retry.state.view, .rated)
    }

    func testAStoredVoteIsReadAsTheWebDoes() {
        XCTAssertNil(HelpfulRow.normalize(nil))
        XCTAssertEqual(HelpfulRow.normalize(AnswerFeedback(helpful: true, reason: "wrong", comment: "x")), AnswerFeedback(helpful: true))
        XCTAssertEqual(HelpfulRow.normalize(AnswerFeedback(helpful: false, reason: "bogus", comment: " ok ")), AnswerFeedback(helpful: false, comment: "ok"))
        XCTAssertEqual(HelpfulRow.normalize(AnswerFeedback(helpful: false, comment: String(repeating: "a", count: 600)))?.comment?.count, 500)
        // A stored vote decodes without a comment (older saves).
        let old = try? JSONDecoder().decode(AnswerFeedback.self, from: Data(#"{"helpful":false,"reason":"wrong"}"#.utf8))
        XCTAssertEqual(old, AnswerFeedback(helpful: false, reason: "wrong"))
    }

    func testTheVoteIsKeptOnTheAnswersRecordEntry() {
        let record: [[String: Any]] = [["id": "a1", "shape": "agent-message", "text": "x"], ["id": "u1", "shape": "user-message"]]
        let out = HelpfulRow.withFeedback(record, agentMessageId: "a1", AnswerFeedback(helpful: false, reason: "wrong"), at: "2026-10-16T10:00:00.000Z")
        let fb = out?[0]["feedback"] as? [String: Any]
        XCTAssertEqual(fb?["helpful"] as? Bool, false)
        XCTAssertEqual(fb?["reason"] as? String, "wrong")
        XCTAssertEqual(fb?["at"] as? String, "2026-10-16T10:00:00.000Z")
        XCTAssertNil(out?[1]["feedback"])
        XCTAssertNil(HelpfulRow.withFeedback(record, agentMessageId: "nope", AnswerFeedback(helpful: true), at: "t"))
    }

    func testOnlyTheNewestUnratedAnswerAsks() {
        let ai = AgentDetails(id: "ai-agent-1", name: "Ava", email: "", isAIAgent: true)
        let a = AgentMessageRecord(id: "0123456789abcdef01234567", time: Date(), text: "one", agentDetails: ai)
        let b = AgentMessageRecord(id: "0123456789abcdef01234568", time: Date(), text: "two", agentDetails: ai)
        let greeting = AgentMessageRecord(id: "agent-greeting-s1", time: Date(), text: "hi", agentDetails: ai)
        let rateable = { (m: AgentMessageRecord) in AgentBotParser.canRate(m.id) }
        let list: [any RecordItem] = [a, b, greeting]
        XCTAssertFalse(HelpfulRow.asksFor(a.id, in: list, rateable: rateable))
        XCTAssertTrue(HelpfulRow.asksFor(b.id, in: list, rateable: rateable))
    }

    func testTheVoteGoesWithItsCommentAsTheWebSendsIt() {
        let p = AnswerFeedback(helpful: false, reason: "other", comment: "late").payload
        XCTAssertEqual(p["helpful"] as? Bool, false)
        XCTAssertEqual(p["reason"] as? String, "other")
        XCTAssertEqual(p["comment"] as? String, "late")
        XCTAssertEqual(AnswerFeedback(helpful: true).payload.count, 1)
    }
}
