//
//  FlowStepViewAnswerTests.swift
//  The chat's step views (UI/SwiftUI/FlowStepViews.swift) answer each step
//  with FlowStepAnswer. Here every visitor action of the shared flow
//  fixtures for those steps is played as the view sends it - the same
//  builders, the same view state (RankingOrder, MatrixPicks), the composer
//  for what is typed, the pills for what is picked from a list - and the
//  whole outcome must still be the web's: the answer is accepted, the
//  variables are saved and the step leaves by the right port.
//

import XCTest
@testable import Conferbot

@MainActor
final class FlowStepViewAnswerTests: XCTestCase {

    /// A fixture action as the step's view (or the composer / pills next to it) sends it.
    /// `handled` false: no view sends it (left to the driver, listed in `notFromAView`).
    static func viewAnswer(_ a: [String: Any], _ ui: NodeUIState?, _ node: [String: Any]?, _ memo: inout [String: Any]) throws -> (handled: Bool, answer: Any?) {
        let type = JS.text(node?["type"])
        let nodeId = JS.text(node?["id"])
        let data = JS.dict(node?["data"])
        switch JS.text(a["do"]) {
        case "choose":
            switch type {
            case "rating-choice-node", "user-rating-node", "opinion-scale-choice-node":
                // RatingStepView / ScaleStepView: the tapped star, face or number
                return (true, FlowStepAnswer.value(JS.toNumber(a["value"])))
            case "carousel-node", "product-card-node":
                // CardsStepView: a path button (with its card), or Continue
                guard let b = a["buttonId"].map({ JS.str($0) }) else { return (true, FlowStepAnswer.cardsContinue) }
                guard case .cards(let cards, _)? = ui, let card = cards.first(where: { $0.buttons.contains { $0.id == b } }) else {
                    throw FlowFixtureDriver.DriverError("no card shows button \(b)")
                }
                return (true, FlowStepAnswer.cardButton(b, cardId: card.id))
            case "dynamic-choices-node":
                // The pills: handleButtonClick sends the pill's id
                guard case .buttons(let buttons, _)? = ui else { throw FlowFixtureDriver.DriverError("no pills") }
                let i = Int(JS.toNumber(a["index"]))
                return (true, ["buttonId": buttons[i].id])
            default:
                return (false, nil)
            }
        case "slider":
            return (true, FlowStepAnswer.value(JS.toNumber(a["value"])))
        case "datetime":
            return (true, FlowStepAnswer.dateTime(JS.str(a["value"])))
        case "calendar":
            return (true, FlowStepAnswer.calendar(date: JS.str(a["date"]), slot: a["slot"].map { JS.str($0) }))
        case "file":
            let name = JS.text(a["name"])
            return (true, FlowStepAnswer.file(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name), name: name,
                                              type: JS.text(a["type"]), size: Int(JS.toNumber(a["size"]))))
        case "skip":
            return (true, FlowStepAnswer.skip)
        case "check":
            return (true, FlowStepAnswer.checked(JS.array(a["ids"]).map { JS.str($0) }))
        case "rankingMove":
            guard case .multiChoice(let items, _)? = ui else { throw FlowFixtureDriver.DriverError("no ranking") }
            var order = (memo[nodeId] as? RankingOrder) ?? RankingOrder(items.map { $0.id })
            order.move(JS.str(a["id"]), by: Int(JS.toNumber(a["dir"])))
            memo[nodeId] = order
            return (true, nil)
        case "rankingSubmit":
            guard case .multiChoice(let items, _)? = ui else { throw FlowFixtureDriver.DriverError("no ranking") }
            return (true, FlowStepAnswer.ranking(((memo[nodeId] as? RankingOrder) ?? RankingOrder(items.map { $0.id })).ids))
        case "matrix":
            var picks = (memo[nodeId] as? MatrixPicks) ?? MatrixPicks(mode: FlowRich.matrixMode(data))
            for (row, cols) in JS.dict(a["cells"]) {
                for col in (cols as? [Any]) ?? [cols] where !picks.isOn(row, JS.str(col)) { picks.tap(row, JS.str(col)) }
            }
            memo[nodeId] = picks
            if JS.bool(a["submit"]) == false { return (true, nil) }
            return (true, FlowStepAnswer.matrix(picks))
        case "consent":
            return (true, FlowStepAnswer.consent(agreed: JS.truthy(a["agreed"])))
        case "otpEmail":
            return (true, JS.str(a["email"])) // typed in the composer
        case "otpCode":
            return (true, JS.str(a["code"])) // typed in the composer
        case "otpSkip":
            return (true, FlowStepAnswer.otpSkip)
        case "addressManual":
            func f(_ k: String) -> String { JS.isNullish(a[k]) ? "" : JS.str(a[k]) }
            return (true, FlowStepAnswer.addressManual(line1: f("line1"), city: f("city"), region: f("region"), postal: f("postal"), country: f("country")))
        case "addressSearch":
            return (true, FlowStepAnswer.addressSearch(JS.str(a["q"])))
        case "addressPick":
            // The results are pills: handleChoiceSelection sends the pill's id (its index)
            guard case .singleChoice(let options, _)? = ui else { throw FlowFixtureDriver.DriverError("no results") }
            return (true, ["buttonId": options[Int(JS.toNumber(a["index"]))].id])
        case "signTyped":
            return (true, JS.str(a["name"])) // typed in the composer
        case "payOpen":
            return (true, FlowStepAnswer.payment("open"))
        case "payCancel":
            return (true, FlowStepAnswer.payment("cancel"))
        default:
            return (false, nil)
        }
    }

    /// Actions no view sends: an empty signature box (Sign is off until something is drawn).
    static let notFromAView: Set<String> = ["signEmpty", "wait", "serverEvent", "text"]

    /// Plays the fixtures as the view answers them; each must come out as the web's.
    private func check(_ files: [String], file: StaticString = #filePath, line: UInt = #line) async {
        for name in files {
            let fx = FlowFixtureTests.load("\(name).json")
            var fromDriver: [String] = []
            let result = await FlowFixtureDriver.run(fx) { a, ui, node, memo in
                let r = try Self.viewAnswer(a, ui, node, &memo)
                if !r.handled && !Self.notFromAView.contains(JS.text(a["do"])) { fromDriver.append(JS.text(a["do"])) }
                return r
            }
            let diffs = result.problems.map { "problem: \($0)" } + FlowFixtureTests.compare(fx, result.outcome)
            XCTAssertTrue(diffs.isEmpty, "\(name)\n  \(diffs.joined(separator: "\n  "))", file: file, line: line)
            XCTAssertEqual(fromDriver, [], "\(name): actions no view answered", file: file, line: line)
        }
    }

    func testRatingView() async {
        await check(["rating-choice.stars", "rating-choice.smiley-and-ten", "legacy.user-rating"])
    }

    func testOpinionScaleView() async {
        await check(["opinion-scale.port-is-offset-from-start", "opinion-scale.blank-range-is-0-to-10"])
    }

    func testSliderView() async {
        await check(["slider.value"])
    }

    func testDateTimeView() async {
        await check(["datetime.date-rules", "datetime.time-mode"])
        // The picker's moment as the step's value, on the visitor's clock
        let utc = TimeZone(identifier: "UTC")!
        let d = Date(timeIntervalSince1970: 1_792_419_000) // 2026-10-19T14:10:00Z
        XCTAssertEqual(FlowStepAnswer.dateTimeValue(d, mode: "date", timeZone: utc), "2026-10-19")
        XCTAssertEqual(FlowStepAnswer.dateTimeValue(d, mode: "time", timeZone: utc), "14:10")
        XCTAssertEqual(FlowStepAnswer.dateTimeValue(d, mode: "datetime", timeZone: TimeZone(identifier: "Asia/Dubai")!), "2026-10-19T18:10")
    }

    func testCalendarView() async {
        await check(["calendar.date-only", "calendar.with-slots"])
        // The slot the view offers is the one the step books
        let fx = FlowFixtureTests.load("calendar.with-slots.json")
        let cal = JS.dicts(JS.dict(fx["flow"])["nodes"]).first { JS.text($0["id"]) == "cal" }!
        let starts = CalendarNodeHandler.slots(JS.dict(cal["data"]), "2026-10-21", now: FlowVirtualClock.base).map { $0.start }
        XCTAssertTrue(starts.contains("09:30"), "\(starts)")
    }

    func testFileView() async {
        await check(["ask-file.upload", "ask-file.rules-and-skip", "ask-file.upload-fails"])
    }

    func testCheckOptionsView() async {
        await check(["n-check.list-order"])
    }

    func testRankingView() async {
        await check(["ranking.reorder"])
        var order = RankingOrder(["a", "b", "c"])
        order.move("a", by: -1)
        order.move("c", by: 1)
        XCTAssertEqual(order.ids, ["a", "b", "c"], "nothing moves past either end")
        order.move("c", by: -1)
        XCTAssertEqual(order.ids, ["a", "c", "b"])
    }

    func testCardsView() async {
        await check(["carousel.path-button", "carousel.links-only-continue", "product-card.buy-button"])
    }

    func testMatrixView() async {
        await check(["matrix.single-require-all", "matrix.multiple"])
        var single = MatrixPicks(mode: "single")
        single.tap("r0", "c0")
        single.tap("r0", "c1")
        XCTAssertEqual(single.selection, ["r0": ["c1"]], "single: one column per row")
        var multi = MatrixPicks(mode: "multiple")
        multi.tap("r0", "c0")
        multi.tap("r0", "c1")
        multi.tap("r0", "c0")
        XCTAssertEqual(multi.selection, ["r0": ["c1"]], "multiple: a second tap unticks")
    }

    func testConsentView() async {
        await check(["consent.required", "consent.optional-declined"])
    }

    func testPaymentView() async {
        await check(["payment.paid", "payment.cancelled-without-failed-edge-ends"])
    }

    func testOtpView() async {
        await check(["otp.verified", "otp.skip-without-failed-edge-takes-source", "otp.wrong-code-then-locked"])
    }

    func testAddressView() async {
        await check(["address.manual", "address.search-and-pick"])
    }

    func testSignatureView() async {
        await check(["signature.typed"])
    }

    func testDynamicChoicesPills() async {
        await check(["dynamic-choices.from-variable"])
    }

    /// The QA - All Nodes bot end to end, every card answered as its view does.
    func testQaAllNodesTour() async {
        await check(["real.qa-all-nodes-tour"])
    }

    #if os(iOS)
    /// A drawn signature: the view's PNG is accepted, uploaded and leaves by "source".
    func testDrawnSignatureIsAccepted() async {
        guard #available(iOS 15.0, *) else { return }
        var fx = FlowFixtureTests.load("signature.typed.json")
        fx["inputs"] = [["at": "sg2", "do": "signDrawn"]]
        let png = SignatureStepView.png([[CGPoint(x: 10, y: 10), CGPoint(x: 120, y: 60), CGPoint(x: 200, y: 30)]])
        XCTAssertNotNil(png)
        let result = await FlowFixtureDriver.run(fx) { a, _, _, _ in
            JS.text(a["do"]) == "signDrawn" ? (true, FlowStepAnswer.signDrawn(png: png!, width: 280, height: 140)) : (false, nil)
        }
        XCTAssertEqual(result.problems, [])
        XCTAssertEqual(JS.json(result.outcome["ports"]), JS.json([["node": "sg2", "handle": "source", "wired": true]]))
        let answer = JS.dicts(result.outcome["answers"]).first { JS.text($0["shape"]) == "user-signature" }
        XCTAssertEqual(JS.text(answer?["method"]), "drawn")
        XCTAssertEqual(JS.text(answer?["url"]), "https://api.test/media/sig1")
    }
    #endif
}
