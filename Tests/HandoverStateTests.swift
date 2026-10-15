//
//  HandoverStateTests.swift
//  The handover lifecycle read from the record (Core/LiveChat/HandoverState),
//  the same cases as the React Native SDK's handoverState.test.ts (itself
//  the web widget's tests/handoverLifecycle.test.js), plus the socket
//  readings (agent-left reasons, agent-accepted, queue-self-resolve,
//  live-chat-state).
//

import XCTest
@testable import Conferbot

final class HandoverStateTests: XCTestCase {

    typealias E = [String: Any]
    let aiJoin: E = ["type": "agent-joined-message", "agentId": "ai-agent-1", "name": "Ava"]
    let escalated: E = ["type": "agent-left-chat", "name": "Ava", "handover": true]
    let human: E = ["type": "agent-joined-message", "agentId": "u1", "name": "admin"]
    let humanLeft: E = ["type": "agent-left-chat", "name": "admin"]
    let ended: E = ["type": "agent-chat-ended"]
    let reply: E = ["shape": "agent-message", "text": "hi"]

    private func with(_ e: E, _ extra: E) -> E { e.merging(extra) { $1 } }

    // MARK: - handoverState (web handoverState.ts)

    func testPhaseBotConnectingJoinedLeftEnded() {
        XCTAssertEqual(HandoverState.phase([]), .none)
        XCTAssertEqual(HandoverState.phase(nil), .none)
        XCTAssertEqual(HandoverState.phase([reply]), .none)
        XCTAssertEqual(HandoverState.phase([aiJoin, reply]), .none)
        XCTAssertEqual(HandoverState.phase([aiJoin, reply, escalated]), .connecting)
        XCTAssertEqual(HandoverState.phase([escalated, with(aiJoin, ["ai": true]), reply]), .connecting)
        XCTAssertEqual(HandoverState.phase([escalated, human, reply]), .joined)
        XCTAssertEqual(HandoverState.phase([escalated, human, humanLeft]), .none)
        XCTAssertEqual(HandoverState.phase([escalated, human, ended]), .none)
        XCTAssertEqual(HandoverState.phase([escalated, ["type": "agent-declined-message"]]), .none)
        XCTAssertEqual(HandoverState.phase([escalated, ["type": "queue-self-resolved"]]), .none)
        XCTAssertEqual(HandoverState.phase([["type": "agent-joined-message", "agentId": "u2", "takeover": true]]), .joined)
        // This SDK's own entries: the AI's join carries its agentDetails.
        XCTAssertEqual(HandoverState.phase([["type": "agent-joined-message", "agentDetails": ["_id": "x", "isAIAgent": true]]]), .none)
    }

    func testTalkToAPersonOnlyWhenNobodyIsComingOrHere() {
        XCTAssertTrue(HandoverState.talkToPersonAllowed([aiJoin, reply]))
        XCTAssertFalse(HandoverState.talkToPersonAllowed([aiJoin, escalated]))
        XCTAssertFalse(HandoverState.talkToPersonAllowed([escalated, human]))
        XCTAssertTrue(HandoverState.talkToPersonAllowed([escalated, human, humanLeft, reply]))
    }

    func testTheSameAgentAgainIsARepeatAnotherIsNews() {
        XCTAssertTrue(HandoverState.isRepeatJoin([escalated, human], agentId: "u1"))
        XCTAssertTrue(HandoverState.isRepeatJoin([escalated, human, reply], agentId: "u1"))
        XCTAssertFalse(HandoverState.isRepeatJoin([escalated, human], agentId: "u2"))
        XCTAssertFalse(HandoverState.isRepeatJoin([escalated, human, humanLeft], agentId: "u1"))
        XCTAssertFalse(HandoverState.isRepeatJoin([escalated], agentId: "u1"))
        XCTAssertFalse(HandoverState.isRepeatJoin([escalated, human], agentId: nil))
    }

    func testOutcomeOfAHandoverLineFromWhatCameAfter() {
        XCTAssertNil(HandoverState.outcome(at: 0, in: [escalated]))
        XCTAssertNil(HandoverState.outcome(at: 0, in: [escalated, reply]))
        XCTAssertEqual(HandoverState.outcome(at: 0, in: [escalated, human]), .joined)
        XCTAssertEqual(HandoverState.outcome(at: 0, in: [escalated, ["type": "agent-joined-message", "agentId": "u2", "takeover": true]]), .joined)
        XCTAssertEqual(HandoverState.outcome(at: 0, in: [escalated, aiJoin]), .unavailable)
        XCTAssertEqual(HandoverState.outcome(at: 0, in: [escalated, ["type": "agent-declined-message"]]), .unavailable)
        XCTAssertEqual(HandoverState.outcome(at: 0, in: [escalated, ["type": "queue-self-resolved"]]), .cancelled)
        XCTAssertEqual(HandoverState.outcome(at: 0, in: [escalated, ended]), .ended)
        XCTAssertEqual(HandoverState.outcome(at: 0, in: [escalated, ["type": "ai-agent-inactive-close"]]), .ended)
        XCTAssertEqual(HandoverState.outcome(at: 0, in: [escalated, reply, escalated]), .unavailable)
        XCTAssertEqual(HandoverState.outcome(at: 0, in: [with(escalated, ["settled": "unavailable"]), human]), .unavailable)
    }

    func testARestoredRecordSettlesFinishedWaitsAndKeepsTheNote() {
        let rec = [aiJoin, with(escalated, ["text": HandoverState.pendingText]), human, reply, humanLeft]
        let out = HandoverState.annotateRestored(rec)
        XCTAssertEqual(out.changed, 2)
        XCTAssertEqual(out.record[1]["settled"] as? String, "joined")
        XCTAssertEqual(out.record[1]["text"] as? String, "Connected with the team")
        XCTAssertEqual(out.record[2]["afterAI"] as? Bool, true)
        XCTAssertEqual(out.record[2]["note"] as? String, HandoverState.handedOverNote)
        XCTAssertNil(out.record[0]["afterAI"])
        // The input is left alone.
        XCTAssertNil(rec[1]["settled"])

        let waiting = HandoverState.annotateRestored([aiJoin, escalated, reply])
        XCTAssertEqual(waiting.changed, 0)

        let later = HandoverState.annotateRestored([escalated, ["type": "agent-chat-ended"], ["type": "agent-joined-message", "agentId": "u3"]]).record
        XCTAssertEqual(later[0]["settled"] as? String, "ended")
        XCTAssertNil(later[2]["afterAI"])
    }

    func testSettlingTouchesOnlyPendingHandoverEntries() {
        let rec = [with(escalated, ["settled": "unavailable"]), with(escalated, ["text": "x"]), humanLeft]
        let a = HandoverState.settle(rec, .joined)
        XCTAssertEqual(a.settled, 1)
        XCTAssertEqual(a.record[0]["settled"] as? String, "unavailable")
        XCTAssertEqual(a.record[1]["settled"] as? String, "joined")
        XCTAssertEqual(a.record[1]["text"] as? String, "Connected with the team")
        XCTAssertNil(a.record[2]["settled"])
        XCTAssertEqual(HandoverState.settle(a.record, .joined).settled, 0)
        XCTAssertTrue(HandoverState.hasPendingLine(rec))
        XCTAssertFalse(HandoverState.hasPendingLine(a.record))
    }

    func testTheLinePendingWordsThenEachOfTheFourOutcomes() {
        XCTAssertEqual(HandoverState.lineText(nil), "Connecting you with the team\u{2026}")
        XCTAssertEqual(HandoverState.lineText(.joined), "Connected with the team")
        XCTAssertEqual(HandoverState.lineText(.unavailable), "The team couldn't join just now")
        XCTAssertEqual(HandoverState.lineText(.cancelled), "You left the queue")
        XCTAssertEqual(HandoverState.lineText(.ended), "Chat ended before the team joined")
        XCTAssertEqual(HandoverState.agentLeftText("Ava", handover: true), "Connecting you with the team\u{2026}")
        XCTAssertEqual(HandoverState.agentLeftText("Sam", handover: false), "Sam left the chat")
        XCTAssertEqual(HandoverState.agentLeftText("", handover: false), "The agent left the chat")
        XCTAssertEqual(HandoverState.joinedText("Sam"), "Sam joined the chat")
        XCTAssertEqual(HandoverState.joinedText(nil), "An agent joined the chat")
    }

    func testTheOnScreenLineSettlesItsWords() {
        let line = AgentLeftMessageRecord(id: "l1", time: Date(), agentDetails: AgentDetails(id: "ai-agent-1", name: "Ava", email: ""), handover: true)
        XCTAssertTrue(line.isPendingHandover)
        XCTAssertEqual(line.text, "Connecting you with the team\u{2026}")
        let done = line.settling(.cancelled)
        XCTAssertFalse(done.isPendingHandover)
        XCTAssertEqual(done.text, "You left the queue")
        XCTAssertNotEqual(line, done)
        let left = AgentLeftMessageRecord(id: "l2", time: Date(), agentDetails: AgentDetails(id: "u1", name: "Sam", email: ""))
        XCTAssertEqual(left.text, "Sam left the chat")
    }

    // MARK: - Socket readings (web agentListeners.ts / special.ts)

    func testAgentLeftAnAIEscalatingIsAHandoverAnIdlePauseIsNothing() {
        XCTAssertEqual(HandoverState.agentLeftKind(["reason": "escalated", "agentDetails": ["name": "Ava"]]), .handover)
        XCTAssertEqual(HandoverState.agentLeftKind(["handover": true, "agentDetails": ["name": "Ava"]]), .handover)
        XCTAssertEqual(HandoverState.agentLeftKind(["agentDetails": ["name": "Ava", "isAIAgent": true]]), .handover)
        XCTAssertEqual(HandoverState.agentLeftKind(["reason": "visitor_inactive", "agentDetails": ["isAIAgent": true]]), .ignore)
        XCTAssertEqual(HandoverState.agentLeftKind(["agentDetails": ["name": "Sam"]]), .left)
        XCTAssertEqual(HandoverState.agentLeftKind(nil), .left)
    }

    func testAgentAcceptedPersonJoinsAIBackIsUnavailableRepeatIsQuiet() {
        let p = HandoverState.acceptedPlan([aiJoin, escalated], data: ["agentDetails": ["_id": "u1", "name": "Sam"]])
        XCTAssertEqual(p, HandoverState.AcceptedPlan(ai: false, outcome: .joined, announce: true, afterAI: true, humanJoined: true))
        let back = HandoverState.acceptedPlan([aiJoin, escalated], data: ["agentDetails": ["_id": "ai-agent-1", "name": "Ava", "isAIAgent": true]])
        XCTAssertEqual(back.outcome, .unavailable)
        XCTAssertFalse(back.humanJoined)
        XCTAssertFalse(back.afterAI)
        let again = HandoverState.acceptedPlan([escalated, human], data: ["agentDetails": ["_id": "u1", "name": "admin"]])
        XCTAssertFalse(again.announce)
        XCTAssertFalse(again.humanJoined)
        // A flow handover with no AI before it: no note.
        XCTAssertFalse(HandoverState.acceptedPlan([], data: ["agentDetails": ["_id": "u1"]]).afterAI)
    }

    func testLeavingTheQueueStaysOnlyWhenAPersonHasIt() {
        XCTAssertEqual(HandoverState.queueSelfResolvePayload("s1") as NSDictionary, ["chatSessionId": "s1"])
        XCTAssertEqual(HandoverState.queueSelfResolvePayload("s1", articleId: "a9") as NSDictionary, ["chatSessionId": "s1", "articleId": "a9"])
        XCTAssertEqual(HandoverState.queueLeaveResult(["ok": true]), .leave)
        XCTAssertEqual(HandoverState.queueLeaveResult(["ok": false, "reason": "not_waiting"]), .leave)
        XCTAssertEqual(HandoverState.queueLeaveResult(nil), .leave)
        XCTAssertEqual(HandoverState.queueLeaveResult(["ok": false, "reason": "agent_joined"]), .stay)
        XCTAssertTrue(HandoverState.queueLeaveNeedsState(["ok": false, "reason": "not_waiting"]))
        XCTAssertFalse(HandoverState.queueLeaveNeedsState(["ok": true]))
        XCTAssertEqual(HandoverState.queueLeaveResult(["ok": false, "reason": "not_waiting"], state: ["status": "live"]), .stay)
        XCTAssertEqual(HandoverState.queueLeaveResult(["ok": false, "reason": "not_waiting"], state: ["status": "ended"]), .leave)
    }

    // MARK: - Restore (web index.ts live-chat-state)

    func testAsksTheServerOnlyForALiveEpisodeOrAtTheHandover() {
        XCTAssertFalse(HandoverState.restoreNeedsLiveChatState([]))
        XCTAssertFalse(HandoverState.restoreNeedsLiveChatState([["type": "bot-message"]]))
        XCTAssertTrue(HandoverState.restoreNeedsLiveChatState([["type": "bot-message"]], atHandover: true))
        XCTAssertTrue(HandoverState.restoreNeedsLiveChatState([human, ["type": "agent-message"]]))
        XCTAssertTrue(HandoverState.restoreNeedsLiveChatState([aiJoin, escalated]))
        XCTAssertFalse(HandoverState.restoreNeedsLiveChatState([human, ["type": "agent-message"], ended]))
        XCTAssertFalse(HandoverState.restoreNeedsLiveChatState([human, ended], atHandover: true))
        XCTAssertTrue(HandoverState.restoreNeedsLiveChatState([human, ended, ["type": "user-message", "shape": "user-live-message"]]))
    }

    func testLiveThePersonTheJoinItMissedTheLineSettled() {
        let r = HandoverState.restoredLiveChat(["status": "live", "agentDetails": ["_id": "u1", "name": "Sam", "email": "s@x.io"]], record: [aiJoin, escalated])
        XCTAssertEqual(r, HandoverState.RestoredLiveChat(status: .live, agent: .init(id: "u1", name: "Sam", email: "s@x.io"),
                                                         settle: .joined, drawJoin: true, afterAI: true, remainingSeconds: nil))
        XCTAssertFalse(HandoverState.restoredLiveChat(["status": "live", "agentDetails": ["_id": "u1", "name": "Sam"]], record: [escalated, human]).drawJoin)
        XCTAssertEqual(HandoverState.restoredLiveChat(["status": "live", "agentDetails": ["_id": "ai-agent-1", "isAIAgent": true]], record: [escalated]).status, .none)
    }

    func testWaitingKeepsTheLinePendingEndedAndFallbackSettleIt() {
        let now = Date(timeIntervalSince1970: 1000)
        let w = HandoverState.restoredLiveChat(["status": "waiting", "waitEndsAt": 1_000_000 + 61_000], record: [escalated], now: now)
        XCTAssertEqual(w.status, .waiting)
        XCTAssertNil(w.settle)
        XCTAssertEqual(w.remainingSeconds, 61)
        XCTAssertEqual(HandoverState.restoredLiveChat(["status": "waiting", "waitEndsAt": 1_000_000 - 5000], record: [], now: now).remainingSeconds, 5)
        XCTAssertEqual(HandoverState.restoredLiveChat(["status": "ended"], record: [escalated]).settle, .ended)
        XCTAssertEqual(HandoverState.restoredLiveChat(["status": "fallback"], record: [escalated]).status, .fallback)
        XCTAssertEqual(HandoverState.restoredLiveChat(["status": "fallback"], record: [escalated]).settle, .unavailable)
        XCTAssertNil(HandoverState.restoredLiveChat(["status": "none"], record: [reply]).settle)
        XCTAssertEqual(HandoverState.restoredLiveChat(nil, record: []).status, .none)
    }

    func testWhatARestoredChatDoesNext() {
        func at(_ status: String) -> HandoverState.RestoredLiveChat { HandoverState.restoredLiveChat(["status": status], record: []) }
        let live = HandoverState.restoredLiveChat(["status": "live", "agentDetails": ["_id": "u1", "name": "Sam"]], record: [])
        XCTAssertEqual(HandoverState.restoreStep(live, atHandover: true), .live)
        XCTAssertEqual(HandoverState.restoreStep(live, atHandover: false), .live)
        XCTAssertEqual(HandoverState.restoreStep(at("waiting"), atHandover: true), .wait)
        // Waiting after an AI escalation: the AI keeps the chat meanwhile.
        XCTAssertEqual(HandoverState.restoreStep(at("waiting"), atHandover: false), .live)
        XCTAssertEqual(HandoverState.restoreStep(at("ended"), atHandover: true, record: [human]), .continue)
        XCTAssertEqual(HandoverState.restoreStep(at("fallback"), atHandover: true, record: []), .continue)
        XCTAssertEqual(HandoverState.restoreStep(at("none"), atHandover: true, record: [["type": "bot-message"]]), .ask)
        XCTAssertEqual(HandoverState.restoreStep(at("none"), atHandover: true, record: [human, reply]), .continue)
        XCTAssertEqual(HandoverState.restoreStep(at("ended"), atHandover: false), .start)
        XCTAssertEqual(HandoverState.restoreStep(at("none"), atHandover: false), .start)
    }

    // MARK: - Storage (#22)

    func testTheServerRecordSurvivesStorage() {
        let rec: [E] = [with(escalated, ["time": Date(), "agentDetails": ["_id": "ai-agent-1", "isAIAgent": true]]), human]
        let data = ChatState.serverRecordJSON(rec)
        XCTAssertNotNil(data)
        let stored = StoredChatState(sessionId: "s1", answerVariables: [], userMetadata: UserMetadata(from: [:]), transcript: [], variables: [:],
                                     serverRecordJSON: data, currentNodeId: "h1")
        let decoded = try! JSONDecoder().decode(StoredChatState.self, from: try! JSONEncoder().encode(stored))
        let back = try! JSONSerialization.jsonObject(with: decoded.serverRecordJSON!) as! [E]
        XCTAssertEqual(HandoverState.phase(back), .joined)
        XCTAssertTrue(back[0]["time"] is String)
        XCTAssertEqual(decoded.currentNodeId, "h1")
    }
}
