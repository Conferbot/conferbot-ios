//
//  WaitCountdownTests.swift
//  The wait card's max-wait countdown (#35): the deadline LiveChatExtras
//  keeps while a flow's handover waits for a person, the handover-timeout
//  at that same deadline, a restored wait from the server's seconds left,
//  and the line's ticks. The same cases as the React Native SDK's
//  useLiveChatExtras.test.ts (#42) and WaitCountdown.test.tsx.
//

import XCTest
@testable import Conferbot

final class WaitCountdownTests: XCTestCase {

    private var live: LiveChatExtras!

    override func setUp() {
        super.setUp()
        live = LiveChatExtras(socket: { nil }, sessionId: { "s1" }, chatState: { ChatState.shared },
                              addMessage: { _ in }, sendRecord: {})
    }

    override func tearDown() {
        live.stopWaitTimer()
        super.tearDown()
    }

    func testAWaitCountsDownTheStepsMaxWaitAndTheTimeoutIsAtThatDeadline() throws {
        let now = Date()
        live.startWaitTimer(nodeData: ["maxWaitTime": 3], workspaceId: "w1", now: now)
        let ends = try XCTUnwrap(live.waitEndsAt)
        XCTAssertEqual(ends.timeIntervalSince(now), 180, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(live.waitTimerFiresAt).timeIntervalSince(ends), 0, accuracy: 0.5)
        // Once per wait: a second start keeps the deadline.
        live.startWaitTimer(nodeData: ["maxWaitTime": 9], workspaceId: "w1", now: now.addingTimeInterval(5))
        XCTAssertEqual(live.waitEndsAt, ends)
        // The wait is over: no countdown.
        live.stopWaitTimer()
        XCTAssertNil(live.waitEndsAt)
        XCTAssertNil(live.waitTimerFiresAt)
    }

    func testARestoredWaitGoesOnFromTheServersSecondsLeftOnce() throws {
        let now = Date()
        live.resumeWait(remainingSeconds: 65)
        live.startWaitTimer(nodeData: ["maxWaitTime": 10], workspaceId: nil, now: now)
        XCTAssertEqual(try XCTUnwrap(live.waitEndsAt).timeIntervalSince(now), 65, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(live.waitTimerFiresAt).timeIntervalSince(now), 65, accuracy: 0.5)
        XCTAssertEqual(LiveChat.maxWaitText(Double(LiveChat.secondsLeft(live.waitEndsAt!, now: now))), "Max wait 1:05")
        // The next wait is the step's own again.
        live.stopWaitTimer()
        live.startWaitTimer(nodeData: ["maxWaitTime": 10], workspaceId: nil, now: now)
        XCTAssertEqual(try XCTUnwrap(live.waitEndsAt).timeIntervalSince(now), 600, accuracy: 0.001)
    }

    func testANewConversationForgetsARestoredWait() throws {
        live.resumeWait(remainingSeconds: 5)
        live.reset()
        let now = Date()
        live.startWaitTimer(nodeData: nil, workspaceId: nil, now: now)
        XCTAssertEqual(try XCTUnwrap(live.waitEndsAt).timeIntervalSince(now), 120, accuracy: 0.001)
    }

    @available(iOS 15.0, *)
    func testTheLineTicksEachSecondAndStopsAtZero() {
        let now = Date(timeIntervalSince1970: 1000)
        let ends = now.addingTimeInterval(3)
        let ticks = MaxWaitLine.ticks(until: ends, now: now)
        XCTAssertEqual(ticks, [now, now.addingTimeInterval(1), now.addingTimeInterval(2), ends])
        XCTAssertEqual(ticks.map { LiveChat.clock(Double(LiveChat.secondsLeft(ends, now: $0))) }, ["0:03", "0:02", "0:01", "0:00"])
        // Past the deadline: only now, at 0:00.
        XCTAssertEqual(MaxWaitLine.ticks(until: ends, now: ends.addingTimeInterval(9)), [ends.addingTimeInterval(9)])
    }
}
