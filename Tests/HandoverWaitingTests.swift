//
//  HandoverWaitingTests.swift
//  The connecting wait's signal, the signal bus and the AI escalation's
//  nudge (Core/LiveChat/HandoverWaiting), the same cases as the React
//  Native SDK's handoverWaiting.test.ts (the web widget's
//  tests/waitingSignal.test.js), on a fake clock.
//

import XCTest
@testable import Conferbot

/// A clock the tests move by hand.
final class FakeClock {
    private final class T: SignalTimer {
        let fn: () -> Void
        let at: TimeInterval
        var cancelled = false
        init(_ fn: @escaping () -> Void, _ at: TimeInterval) { self.fn = fn; self.at = at }
        func cancel() { cancelled = true }
    }
    private(set) var now: TimeInterval = 0
    private var timers: [T] = []

    func schedule(_ seconds: TimeInterval, _ fn: @escaping () -> Void) -> SignalTimer {
        let t = T(fn, now + seconds)
        timers.append(t)
        return t
    }

    var pending: Int { timers.filter { !$0.cancelled }.count }

    func tick(_ seconds: TimeInterval) {
        let until = now + seconds
        while let next = timers.filter({ !$0.cancelled && $0.at <= until }).min(by: { $0.at < $1.at }) {
            timers.removeAll { $0 === next }
            now = next.at
            next.fn()
        }
        timers.removeAll { $0.cancelled }
        now = until
    }
}

final class HandoverWaitingTests: XCTestCase {

    func testSignalsAfter20sOnce() {
        let c = FakeClock()
        var fired = 0
        let sig = ConnectingSignal(fire: { fired += 1 }, canFire: { true }, schedule: c.schedule)
        XCTAssertEqual(HandoverWait.connectingSignalSeconds, 20)
        sig.start()
        sig.start()
        c.tick(19.999)
        XCTAssertEqual(fired, 0)
        c.tick(0.001)
        XCTAssertEqual(fired, 1)
        XCTAssertFalse(sig.pending)
        c.tick(60)
        XCTAssertEqual(fired, 1)
    }

    func testAJoinNobodyAvailableLeavingOrTheChatEndingMeansNoSignal() {
        let c = FakeClock()
        var fired = 0
        let sig = ConnectingSignal(fire: { fired += 1 }, canFire: { true }, schedule: c.schedule)
        sig.start()
        c.tick(10)
        sig.end()
        c.tick(60)
        XCTAssertEqual(fired, 0)
        XCTAssertEqual(c.pending, 0)
        sig.start()
        c.tick(20)
        XCTAssertEqual(fired, 1)
    }

    func testDueWhileTheChatIsClosedHeldUntilItOpens() {
        let c = FakeClock()
        var fired = 0
        var open = false
        let sig = ConnectingSignal(fire: { fired += 1 }, canFire: { open }, schedule: c.schedule)
        sig.start()
        c.tick(30)
        XCTAssertEqual(fired, 0)
        open = true
        c.tick(HandoverWait.connectingRecheckSeconds)
        XCTAssertEqual(fired, 1)
        open = false
        sig.start()
        c.tick(25)
        sig.end()
        open = true
        c.tick(10)
        XCTAssertEqual(fired, 1)
    }

    func testNamesAsOnTheWebDetailsCarryNoPersonalData() {
        XCTAssertEqual(WidgetSignal.waitingForHuman.rawValue, "cb:waiting-for-human")
        XCTAssertEqual(WidgetSignal.humanJoined.rawValue, "cb:human-joined")
        XCTAssertEqual(WidgetSignal.waitOver.rawValue, "cb:wait-over")
        XCTAssertEqual(HandoverWait.waitingDetail(["offline": false, "reason": "busy", "email": "a@b.co"]),
                       WidgetSignalDetail(offline: false, reason: "busy", backAt: nil, emailCaptured: true))
        XCTAssertEqual(HandoverWait.waitingDetail(["reason": "offline", "backAt": "2026-10-16T09:00:00Z"]),
                       WidgetSignalDetail(offline: false, reason: "offline", backAt: "2026-10-16T09:00:00Z", emailCaptured: false))
    }

    func testTheBusListenersGetTheDetailAndUnsubscribe() {
        let bus = WidgetSignalBus()
        var got: [WidgetSignalDetail] = []
        let off = bus.on(.waitOver) { got.append($0) }
        XCTAssertEqual(bus.emit(.waitOver, WidgetSignalDetail(reason: "cancelled")), 1)
        XCTAssertEqual(got, [WidgetSignalDetail(reason: "cancelled")])
        off()
        bus.emit(.waitOver, WidgetSignalDetail(reason: "ended"))
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(bus.emit(.humanJoined, WidgetSignalDetail(name: "Sam")), 0)
    }

    func testTheAIEscalationNudgeWaitsTheMaxWaitPlus30s() {
        XCTAssertEqual(HandoverWait.serverGraceSeconds, 30)
        XCTAssertEqual(HandoverWait.aiEscalationNudgeSeconds(nil), 150)
        XCTAssertEqual(HandoverWait.aiEscalationNudgeSeconds(5), 330)
        XCTAssertEqual(HandoverWait.aiEscalationNudgeSeconds("0.5"), 60)
        // 0 or below is unset (#93).
        XCTAssertEqual(HandoverWait.aiEscalationNudgeSeconds(0), 150)
        XCTAssertEqual(HandoverWait.aiEscalationNudgeSeconds(-3), 150)
    }

    func testOnlyAnAIAgentHandingOnStartsTheEscalationWait() {
        XCTAssertTrue(HandoverWait.startsEscalationWait(["reason": "escalated", "agentDetails": ["isAIAgent": true]]))
        XCTAssertTrue(HandoverWait.startsEscalationWait(["agentDetails": ["isAIAgent": true]]))
        XCTAssertFalse(HandoverWait.startsEscalationWait(["reason": "visitor_inactive", "agentDetails": ["isAIAgent": true]]))
        XCTAssertFalse(HandoverWait.startsEscalationWait(["reason": "escalated", "agentDetails": ["name": "Sam"]]))
        XCTAssertFalse(HandoverWait.startsEscalationWait(nil))
    }

    func testTheEscalationsStepIsTheFlowsElseTheLatestHandoverStepInTheRecord() {
        let record: [[String: Any]] = [
            ["id": "a", "type": "human-handover-node", "data": ["maxWaitTime": 1]],
            ["id": "m", "type": "bot-message"],
            ["id": "b", "shape": "human-handover-node", "data": ["maxWaitTime": 4]],
        ]
        XCTAssertEqual(HandoverWait.escalationHandoverData(["maxWaitTime": 9], record: record)?["maxWaitTime"] as? Int, 9)
        XCTAssertEqual(HandoverWait.escalationHandoverData(nil, record: record)?["maxWaitTime"] as? Int, 4)
        XCTAssertNil(HandoverWait.escalationHandoverData(nil, record: [["id": "m", "type": "bot-message"]]))
    }
}
