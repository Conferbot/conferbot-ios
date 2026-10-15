//
//  HandoverPayloadTests.swift
//  initiate-handover carries the handover step's own settings, as the web
//  widget sends them (#57; React Native #59, handoverTimeout.test.ts).
//

import XCTest
@testable import Conferbot

final class HandoverPayloadTests: XCTestCase {

    func testAnEmailTurnedOffOnTheStepStaysOffSoundAndSkillsGoToo() {
        let step: [String: Any] = [
            "enableHandoverEmail": false,
            "enableHandoverSound": true,
            "checkedSoundTab": "default",
            "selectedSound": "ding",
            "assignmentMethod": "skills",
            "requiredSkills": ["billing"],
        ]
        let p = AgentHandover.payload(state: ChatState.shared, chatSessionId: "s1", botId: "b1", nodeData: step)
        XCTAssertEqual(p["enableHandoverEmail"] as? Bool, false)
        XCTAssertEqual(p["enableHandoverSound"] as? Bool, true)
        XCTAssertEqual(p["checkedSoundTab"] as? String, "default")
        XCTAssertEqual(p["selectedSound"] as? String, "ding")
        XCTAssertEqual(p["assignmentMethod"] as? String, "skills")
        XCTAssertEqual(p["requiredSkills"] as? [String], ["billing"])
    }

    func testAStepThatFollowsTheWorkspaceSendsNoAssignmentOverrides() {
        let p = AgentHandover.stepSettings(["assignmentMethod": "workspace", "requiredSkills": [] as [String]])
        XCTAssertNil(p["assignmentMethod"])
        XCTAssertNil(p["requiredSkills"])
        XCTAssertTrue(AgentHandover.stepSettings([:]).isEmpty)
    }

    func testTheSilentStartKeepsItsOwnExtra() {
        let p = AgentHandover.payload(state: ChatState.shared, chatSessionId: "s1", botId: "b1",
                                      nodeData: ["enableHandoverEmail": true], extra: ["silentStart": true])
        XCTAssertEqual(p["silentStart"] as? Bool, true)
        XCTAssertEqual(p["enableHandoverEmail"] as? Bool, true)
    }
}
