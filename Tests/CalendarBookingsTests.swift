//
//  CalendarBookingsTests.swift
//  Conferbot
//
//  Booked calendar slots (RN __tests__/core/AdvancedInputHandlers.test.ts
//  "booked slots"; web displayStep.ts daySlotsFor, nodeLogic.ts
//  isDayFullyBooked): the bot data's calendarBookings and the node's own
//  bookings, for this node only, on the bot's clock.
//

import XCTest
@testable import Conferbot

@MainActor
final class CalendarBookingsTests: XCTestCase {

    private let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private var data: [String: Any] {
        [
            "timeZone": "Asia/Dubai",
            "showTimeSelection": true,
            "slotDuration": 30,
            "weeklyHours": days.map { ["dayName": $0, "available": true, "slots": [["start": "09:00", "end": "10:00"]]] },
            "answerVariable": "meeting",
        ]
    }

    private func ahead(_ n: Double) -> String { FlowCalendar.dayKeyInZone(Date().addingTimeInterval(n * 86400), "Asia/Dubai") }
    private func booking(_ day: String, _ slot: String, nodeId: String? = nil) -> [String: Any] {
        var b: [String: Any] = ["date": "\(day)T08:00:00.000Z", "timeSlotSelected": slot]
        if let n = nodeId { b["nodeId"] = n }
        return b
    }

    func testReadsBookingsOnTheBotsClockForThisNodeOnly() {
        let bookings: [Any] = [
            ["date": "2026-11-02T21:30:00.000Z", "timeSlotSelected": "09:00 - 09:30"], // 01:30 on the 3rd in Dubai
            ["date": "2026-11-03T08:00:00.000Z", "timeSlotSelected": "10:00 - 10:30", "nodeId": "cal"],
            ["date": "2026-11-03T08:00:00.000Z", "timeSlotSelected": "11:00 - 11:30", "nodeId": "x"],
            NSNull(),
        ]
        XCTAssertEqual(FlowCalendar.bookedLabels(bookings, nodeId: "cal", nodeData: nil, dayKey: "2026-11-03", timeZone: "Asia/Dubai"),
                       ["09:00 - 09:30", "10:00 - 10:30"])
        XCTAssertEqual(FlowCalendar.bookedLabels(bookings, nodeId: "cal", nodeData: nil, dayKey: "2026-11-02", timeZone: "UTC"), ["09:00 - 09:30"])
        XCTAssertTrue(FlowCalendar.isDayFullyBooked([FlowCalendar.Slot(start: "09:00", end: "09:30")], ["09:00 - 09:30"]))
        XCTAssertFalse(FlowCalendar.isDayFullyBooked([], []))
    }

    func testATakenSlotIsRefusedAnotherNodesBookingDoesNotCount() async {
        let day = ahead(3)
        let state = ChatState()
        state.setSession(sessionId: "s1", botId: "b1")
        let ctx = FlowContext.standalone(state)
        ctx.calendarBookings = [booking(day, "09:00 - 09:30"), booking(day, "09:30 - 10:00", nodeId: "other")]
        let node: [String: Any] = ["id": "cal", "type": "calendar-node", "data": data, "ctx": ctx]
        XCTAssertEqual(CalendarNodeHandler.booked(data, nodeId: "cal", bookings: ctx.calendarBookings, day), ["09:00 - 09:30"])
        let handler = CalendarNodeHandler()
        let refused = await handler.handleResponse(["date": day, "slot": "09:00"], node: node, state: state)
        if case .displayUI? = refused {} else { XCTFail("a booked slot is refused, got \(String(describing: refused))") }
        XCTAssertNil(state.answerValue("meeting") as? String)
        let taken = await handler.handleResponse(["date": day, "slot": "09:30"], node: node, state: state)
        if case .delayedProceed? = taken {} else { XCTFail("a free slot is booked, got \(String(describing: taken))") }
    }

    func testADayWithEverySlotTakenIsNotOffered() {
        let day = ahead(4)
        var d = data
        d["bookings"] = [booking(day, "09:30 - 10:00")]
        let bookings = [booking(day, "09:00 - 09:30", nodeId: "cal")]
        XCTAssertTrue(CalendarNodeHandler.isFullyBooked(d, nodeId: "cal", bookings: bookings, day, now: Date()))
        XCTAssertFalse(CalendarNodeHandler.isFullyBooked(d, nodeId: "cal", bookings: bookings, ahead(5), now: Date()))
    }
}
