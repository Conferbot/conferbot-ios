//
//  FlowFixtureTests.swift
//  The shared flow-node spec, run through this SDK's NodeFlowEngine and
//  handlers (Tests/Resources/flows, copied from conferbot-react-native
//  scripts/parity/flows by scripts/sync-flow-fixtures.sh: nodes.spec.json +
//  156 fixtures whose outcomes come from running the web widget's own code).
//
//  Compared, per the fixtures README ("SDK tests should"), as the React
//  Native SDK's __tests__/parity/flows.test.ts does:
//    path (node, type, via), ports, variables (key + value), end,
//    errors (count + node), answers (shape + value fields), rendered plain
//    text, emits, unsupported, http (path + body keys), flowVariables, and
//    the typing pace between shown steps (+-50 ms) where it is not skipped
//    on purpose (timingSkip).
//
//  Cases for node types this SDK does not run yet are listed in
//  pendingTypes and skipped - every other case, the engine rules included,
//  must pass.
//

import XCTest
@testable import Conferbot

@MainActor
final class FlowFixtureTests: XCTestCase {

    /// Node types not run by this SDK yet: their cases are pending.
    static let pendingTypes: Set<String> = []

    /// Cases whose typing pace differs on purpose, with the reason.
    /// Everything else in them is still compared.
    static let timingSkip: [String: String] = [
        // In the web harness the visitor's next action is played once every
        // timer has run, the card's own UI timers included (focus 30-50 ms,
        // a debounce, an animation). They move the web clock, not the flow;
        // this SDK's cards are native views with no such timers.
        "navigate.links-then-done": "web link-click timers before Done (420 ms)",
        "rating-choice.smiley-and-ten": "web rating animation before the next pick (300 ms)",
        "otp.verified": "web OTP card focus timers (50 + 30 ms)",
        "otp.wrong-code-then-locked": "web OTP card focus timers (50 + 30 ms)",
        "address.search-and-pick": "web address search debounce and focus (300 + 50 ms)",
        "payment.paid": "web payment card focus timer (60 ms)",
        "real.qa-all-nodes-tour": "the card timers above, added up over the tour",
    ]

    static var fixturesURL: URL {
        Bundle.module.url(forResource: "flows", withExtension: nil)!
    }

    static func load(_ file: String) -> [String: Any] {
        let data = try! Data(contentsOf: fixturesURL.appendingPathComponent(file))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    static var cases: [[String: Any]] {
        JS.dicts(load("index.json")["cases"])
    }

    private static func pendingReason(_ fx: [String: Any]) -> String? {
        var types = Set(JS.array(fx["covers"]).map { JS.str($0) })
        for n in JS.dicts(JS.dict(fx["flow"])["nodes"]) { types.insert(JS.text(n["type"])) }
        let pending = types.filter { pendingTypes.contains($0) }.sorted()
        return pending.isEmpty ? nil : pending.joined(separator: ", ")
    }

    private static func pick(_ o: Any?, _ keys: [String]) -> [String: Any] {
        let d = JS.dict(o)
        var out: [String: Any] = [:]
        for k in keys { if let v = d[k] { out[k] = v } }
        return out
    }

    private static let isoTime = Re("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$")

    /// A time the visitor acted at ("consent_at", "signature_at") depends on
    /// when the driver plays the action: compared as a timestamp.
    private static func stamp(_ v: Any?) -> Any? {
        if let s = v as? String, isoTime.test(s) { return "<timestamp>" }
        return v
    }

    private static func stampsIn(_ text: Any?) -> Any? {
        guard let s = text as? String else { return text }
        return s.replacing("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z", with: "<timestamp>")
    }

    /// The differences between what the web did and what this SDK did.
    static func compare(_ fx: [String: Any], _ got: [String: Any]) -> [String] {
        let exp = JS.dict(fx["expect"])
        var diffs: [String] = []
        func eq(_ label: String, _ a: Any?, _ b: Any?) {
            let ja = JS.json(a)
            let jb = JS.json(b)
            if ja != jb { diffs.append("\(label)\n    web: \(ja)\n    sdk: \(jb)") }
        }
        let pathKeys = ["node", "type", "via"]
        eq("path", JS.array(exp["path"]).map { pick($0, pathKeys) }, JS.array(got["path"]).map { pick($0, pathKeys) })
        eq("ports", exp["ports"], got["ports"])
        func vars(_ list: Any?) -> [[String: Any]] { JS.dicts(list).map { ["key": $0["key"] ?? NSNull(), "value": stamp($0["value"]) ?? NSNull()] } }
        eq("variables", vars(exp["variables"]), vars(got["variables"]))
        let expEnd = JS.dict(exp["end"])
        let endKeys = JS.truthy(expEnd["crashed"]) ? ["ended", "crashed", "at"] : JS.truthy(expEnd["ended"]) ? ["ended"] : ["ended", "waitingAt"]
        eq("end", pick(expEnd, endKeys), pick(got["end"], endKeys))
        eq("errors (node)", JS.dicts(exp["errors"]).map { $0["node"] ?? NSNull() }, JS.dicts(got["errors"]).map { $0["node"] ?? NSNull() })
        let ea = JS.array(exp["answers"])
        let ga = JS.array(got["answers"])
        if ea.count != ga.count {
            eq("answers", ea, ga)
        } else {
            for (i, a) in ea.enumerated() { eq("answers[\(i)]", a, pick(ga[i], Array(JS.dict(a).keys))) }
        }
        func plain(_ list: Any?) -> [[String: Any]] { JS.dicts(list).map { ["node": $0["node"] ?? NSNull(), "plain": stampsIn($0["plain"]) ?? NSNull()] } }
        eq("rendered", plain(exp["rendered"]), plain(got["rendered"]))
        eq("emits", exp["emits"], got["emits"])
        eq("unsupported", exp["unsupported"], got["unsupported"])
        func bodyKeys(_ list: Any?) -> [[String: Any]] {
            JS.dicts(list).map { ["path": $0["path"] ?? NSNull(), "keys": JS.dict($0["body"]).keys.sorted()] }
        }
        eq("http", bodyKeys(exp["http"]), bodyKeys(got["http"]))
        if exp["flowVariables"] != nil { eq("flowVariables", exp["flowVariables"], got["flowVariables"]) }

        if timingSkip[JS.text(fx["id"])] == nil {
            let es = JS.dicts(exp["shown"])
            let gs = JS.dicts(got["shown"])
            eq("shown (order)", es.map { $0["node"] ?? NSNull() }, gs.map { $0["node"] ?? NSNull() })
            func gaps(_ list: [[String: Any]]) -> [Double] {
                list.count < 2 ? [] : (1..<list.count).map { JS.toNumber(list[$0]["t"]) - JS.toNumber(list[$0 - 1]["t"]) }
            }
            let ge = gaps(es)
            let gg = gaps(gs)
            if ge.count == gg.count, zip(ge, gg).contains(where: { abs($0 - $1) > 50 }) {
                diffs.append("shown (pace)\n    web: \(JS.json(es))\n    sdk: \(JS.json(gs))")
            }
        }
        return diffs
    }

    /// Every fixture: one activity each; a failing case fails with its differences.
    func testEveryFlowFixturePassesThroughTheEngine() async {
        let all = Self.cases
        XCTAssertEqual(all.count, 156, "the fixture index lists every case")
        var passed = 0
        var pending: [String] = []
        var failed: [String] = []
        for c in all {
            let fx = Self.load(JS.text(c["file"]))
            let id = JS.text(fx["id"])
            if let reason = Self.pendingReason(fx) {
                pending.append("\(id) (pending: \(reason))")
                continue
            }
            let result = await FlowFixtureDriver.run(fx)
            let diffs = result.problems.map { "problem: \($0)" } + Self.compare(fx, result.outcome)
            if diffs.isEmpty {
                passed += 1
            } else {
                failed.append(id)
                XCTContext.runActivity(named: id) { _ in
                    XCTFail("\(id)\n  \(diffs.joined(separator: "\n  "))")
                }
            }
        }
        print("FLOW FIXTURES: \(passed) of \(all.count) pass, \(pending.count) pending, \(failed.count) failing")
        if !failed.isEmpty { print("FLOW FIXTURES FAILING: \(failed.joined(separator: " "))") }
        if !pending.isEmpty { print("FLOW FIXTURES PENDING: \(pending.joined(separator: "; "))") }
    }

    /// The comparison catches a different outcome: a wrong variable value,
    /// branch or end each fail the case.
    func testADifferentOutcomeIsCaught() async {
        let fx = Self.load("n-choices.port-is-choice-id.json")
        var got = await FlowFixtureDriver.run(fx).outcome
        XCTAssertTrue(Self.compare(fx, got).isEmpty)
        var vars = JS.dicts(got["variables"])
        vars[0]["value"] = "Message node"
        got["variables"] = vars
        var path = JS.dicts(got["path"])
        path[path.count - 1]["via"] = "edge:source"
        got["path"] = path
        got["end"] = ["ended": false, "waitingAt": "c"]
        let diffs = Self.compare(fx, got).map { $0.components(separatedBy: "\n")[0] }
        XCTAssertEqual(diffs, ["path", "variables", "end"])
    }

    /// Pending types really are missing (once one is implemented, its cases run).
    func testEveryPendingTypeIsStillMissingFromTheRegistry() {
        let registry = NodeHandlerRegistry()
        registry.registerAllHandlers()
        for t in Self.pendingTypes { XCTAssertFalse(registry.hasHandler(for: t), t) }
    }
}
