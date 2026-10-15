//
//  FlowControl.swift
//  Conferbot
//
//  Loops and sub-flows, the pure half - ported unchanged from the web widget
//  (conferbot-widget/src/ts/chat/flowControl.ts) through the React Native
//  SDK (src/core/flow/flowControl.ts). NodeFlowEngine runs them.
//

import Foundation

public enum FlowControl {

    public static let loopType = "loop-node"
    public static let subflowType = "subflow-node"
    public static let runSubflowType = "run-subflow-node"
    public static let subflowReturnType = "subflow-return-node"
    public static let types: Set<String> = [loopType, subflowType, runSubflowType, subflowReturnType]

    public static let loopBodyHandle = "source-loop"
    public static let loopDoneHandle = "source-done"
    public static let runErrorHandle = "source-error"

    public static let loopDefaultCap = 20
    public static let loopHardCap = 100
    public static let subflowMaxDepth = 5
    private static let varRe = Re("^[A-Za-z_][A-Za-z0-9_]*$")

    public struct LoopState {
        /// Rounds started so far.
        var i: Int
        var total: Int
        var items: [Any]?
        /// The list or count was longer than the cap.
        var capped: Bool
    }

    public struct CallFrame {
        let runNodeId: String
        let subflowId: String
        let name: String
        let outputs: [(from: String, to: String)]
        let depth: Int
    }

    public struct State {
        var loops: [String: LoopState] = [:]
        var stack: [CallFrame] = []
    }

    private static func clean(_ v: Any?) -> String {
        JS.text(v).replacing("<[^>]*>", with: "").replacingOccurrences(of: "&nbsp;", with: " ").trimmed
    }

    /// Fill {var} placeholders from the lookup ("" for unknown ones).
    public static func fillText(_ text: Any?, _ lookup: VariableLookup) -> String {
        Re("\\$?\\{([A-Za-z0-9_]+)\\}").replace(JS.text(text)) { g in
            let v = lookup(g[1] ?? "")
            if JS.isNullish(v) { return "" }
            return v is [Any] || v is [String: Any] ? JS.json(v) : JS.str(v)
        }
    }

    /// The loop's variable name: data.variable, else "loop".
    public static func loopVarName(_ data: [String: Any]) -> String {
        let v = clean(data["variable"])
        return varRe.test(v) ? v : "loop"
    }

    /// The cap: data.maxIterations, 1..100, default 20.
    public static func loopCap(_ data: [String: Any]) -> Int {
        let n = JS.toNumber(data["maxIterations"]).rounded(.down)
        if !n.isFinite || n < 1 { return loopDefaultCap }
        return min(loopHardCap, Int(n))
    }

    /// A list from a variable's value: an array, a JSON array, or a comma /
    /// new-line separated text. Anything else is no list.
    public static func listOf(_ value: Any?) -> [Any] {
        if let a = value as? [Any] { return a }
        if JS.isNullish(value) || value is [String: Any] { return [] }
        let t = JS.str(value).trimmed
        if t.isEmpty { return [] }
        if t.hasPrefix("["), let parsed = JS.parse(t) as? [Any] { return parsed }
        return t.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmed }.filter { !$0.isEmpty }
    }

    /// How many rounds: a number, or a {var} holding one.
    public static func loopCount(_ data: [String: Any], _ lookup: VariableLookup) -> Int {
        let raw = data["count"]
        let n = JS.isNumber(raw) ? JS.toNumber(raw) : JS.toNumber(fillText(raw, lookup).trimmed)
        return n.isFinite && n > 0 ? Int(n.rounded(.down)) : 0
    }

    /// First arrival: how many rounds and over which items.
    public static func startLoop(_ data: [String: Any], _ lookup: VariableLookup) -> LoopState {
        let cap = loopCap(data)
        if JS.text(data["mode"]) == "each" {
            let key = clean(data["listVariable"]).replacing("^\\{|\\}$", with: "")
            let items = listOf(key.isEmpty ? nil : lookup(key))
            return LoopState(i: 0, total: min(items.count, cap), items: Array(items.prefix(cap)), capped: items.count > cap)
        }
        let n = loopCount(data, lookup)
        return LoopState(i: 0, total: min(n, cap), items: nil, capped: n > cap)
    }

    /// An item as variable text ({x_item}): plain values as they are, objects as JSON.
    public static func itemValue(_ item: Any?) -> Any? {
        item is [Any] || item is [String: Any] ? JS.json(item) : item
    }

    public struct LoopStep {
        let handle: String
        /// Variables to set (empty on Done).
        let vars: [(String, Any)]
        let trail: [String: Any]
        let trailText: String
    }

    /// The loop step: start the next round or leave by Done. Mutates `state`.
    public static func stepLoop(_ nodeId: String, _ data: [String: Any], _ state: inout State, _ lookup: VariableLookup) -> LoopStep {
        let name = loopVarName(data)
        var s = state.loops[nodeId] ?? startLoop(data, lookup)
        if s.i < s.total {
            s.i += 1
            state.loops[nodeId] = s
            let item: Any? = s.items.map { $0[s.i - 1] } ?? s.i
            let shownItem = itemValue(item)
            var trail: [String: Any] = ["iteration": s.i, "total": s.total, "variable": name]
            if s.items != nil, let si = shownItem { trail["item"] = si }
            let itemText: String = {
                guard s.items != nil, let si = shownItem, !JS.isNullish(si), JS.str(si) != "" else { return "" }
                return " · \(JS.str(si).jsSlice(0, 60))"
            }()
            return LoopStep(
                handle: loopBodyHandle,
                vars: [("\(name)_index", s.i), ("\(name)_item", shownItem ?? NSNull()), ("\(name)_count", s.total)],
                trail: trail,
                trailText: "Loop \(s.i) of \(s.total)\(itemText)"
            )
        }
        state.loops[nodeId] = nil
        var trail: [String: Any] = ["iteration": s.i, "total": s.total, "done": true, "variable": name]
        if s.capped { trail["capped"] = true }
        let rounds = "\(s.total) round\(s.total == 1 ? "" : "s")"
        return LoopStep(
            handle: loopDoneHandle,
            vars: [],
            trail: trail,
            trailText: s.capped ? "Loop stopped at the safety cap · \(rounds)" : "Loop done · \(rounds)"
        )
    }

    // MARK: - Sub-flows

    public static func subflowName(_ node: [String: Any]?) -> String {
        let n = clean(JS.dict(node?["data"])["name"])
        return n.isEmpty ? "Sub-flow" : n
    }

    public struct SubflowCall {
        let ok: Bool
        /// "missing" (no such start), "depth" (too deep), "recursion" (calls itself).
        let error: String?
        let startId: String?
        let name: String?
        let vars: [(String, Any)]
        let frame: CallFrame?
    }

    /// Run sub-flow: find the start, check depth / recursion, fill the inputs.
    /// Pushes the call frame onto `state.stack` when it can run.
    public static func callSubflow(_ runNode: [String: Any], _ nodes: [[String: Any]], _ state: inout State, _ lookup: VariableLookup) -> SubflowCall {
        let d = JS.dict(runNode["data"])
        guard let target = nodes.first(where: { JS.str($0["id"]) == JS.text(d["subflowId"]) && JS.text($0["type"]) == subflowType }) else {
            return SubflowCall(ok: false, error: "missing", startId: nil, name: nil, vars: [], frame: nil)
        }
        let name = subflowName(target)
        let targetId = JS.str(target["id"])
        if state.stack.count >= subflowMaxDepth { return SubflowCall(ok: false, error: "depth", startId: nil, name: name, vars: [], frame: nil) }
        if state.stack.contains(where: { $0.subflowId == targetId }) {
            return SubflowCall(ok: false, error: "recursion", startId: nil, name: name, vars: [], frame: nil)
        }
        var vars: [(String, Any)] = []
        for m in JS.dicts(d["inputs"]) {
            let key = clean(m["name"])
            if varRe.test(key) {
                vars.removeAll { $0.0 == key }
                vars.append((key, fillText(m["value"], lookup)))
            }
        }
        let outputs: [(from: String, to: String)] = JS.dicts(d["outputs"]).map { m in
            let from = clean(m["name"])
            let variable = clean(m["variable"])
            return (from, variable.isEmpty ? from : variable)
        }.filter { varRe.test($0.from) && varRe.test($0.to) }
        let frame = CallFrame(runNodeId: JS.str(runNode["id"]), subflowId: targetId, name: name, outputs: outputs, depth: state.stack.count + 1)
        state.stack.append(frame)
        return SubflowCall(ok: true, error: nil, startId: targetId, name: name, vars: vars, frame: frame)
    }

    /// The sub-flow ended: pop the frame and read its outputs. nil when not in one.
    public static func returnFromSubflow(_ state: inout State, _ lookup: VariableLookup) -> (frame: CallFrame, vars: [(String, Any)])? {
        guard let frame = state.stack.popLast() else { return nil }
        let vars: [(String, Any)] = frame.outputs.map { o in
            let v = lookup(o.from)
            return (o.to, JS.isNullish(v) ? "" : v!)
        }
        return (frame, vars)
    }

    public static let subflowErrors: [String: String] = [
        "missing": "The sub-flow it runs no longer exists",
        "depth": "Sub-flows can call each other at most \(subflowMaxDepth) deep",
        "recursion": "A sub-flow can't run itself",
    ]
}
