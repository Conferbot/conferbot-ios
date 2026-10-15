//
//  FlowFixtureDriver.swift
//  A headless driver for the shared flow-node fixtures
//  (Tests/Resources/flows, from conferbot-react-native
//  scripts/parity/flows; README "Using the fixtures in an SDK"), the same
//  driver as the React Native SDK's __tests__/parity/flowDriver.ts.
//
//  One case = one fresh ChatState, registry (registerAllHandlers) and
//  NodeFlowEngine. The clock is virtual (setTimeout / setInterval / now),
//  the bot API answers from the case's `server.http`, and a fake socket
//  answers `execute-integration` and `initiate-handover` from
//  `server.integration` and `server.handover`. Each visitor action is
//  played through engine.submitResponse with the answer the SDK's UI would
//  send for it.
//

import Foundation
@testable import Conferbot

// MARK: - Virtual clock (web/env.js)

/// 2026-10-15 10:00 UTC, a Thursday; time moves only when the driver says.
final class FlowVirtualClock: FlowClock {
    static let base = Date(timeIntervalSince1970: 1_792_058_400) // 2026-10-15T10:00:00Z

    final class Timer: FlowTimer {
        let id: Int
        var at: Double
        let every: Double
        let fn: @MainActor () -> Void
        weak var clock: FlowVirtualClock?

        init(id: Int, at: Double, every: Double, fn: @escaping @MainActor () -> Void) {
            self.id = id
            self.at = at
            self.every = every
            self.fn = fn
        }

        func cancel() { clock?.timers[id] = nil }
    }

    var nowMs: Double = 0
    private var seq = 0
    fileprivate var timers: [Int: Timer] = [:]

    func now() -> Date { Self.base.addingTimeInterval(nowMs / 1000) }

    @MainActor func sleep(ms: Double) async {
        let once = FlowOnce<Void>()
        _ = schedule(ms: ms, repeats: false) { once.resume(()) }
        await once.value()
    }

    func schedule(ms: Double, repeats: Bool, _ fn: @escaping @MainActor () -> Void) -> FlowTimer {
        add(ms: ms, repeats: repeats, fn)
    }

    /// setTimeout / setInterval (the driver runs on the main thread).
    @discardableResult
    func add(ms: Double, repeats: Bool, _ fn: @escaping @MainActor () -> Void) -> FlowTimer {
        seq += 1
        let wait = max(0, ms.isFinite ? ms : 0)
        let t = Timer(id: seq, at: nowMs + wait, every: repeats ? max(1, wait) : 0, fn: fn)
        t.clock = self
        timers[seq] = t
        return t
    }

    /// Let every task that can run, run (the web harness's microtask flush).
    @MainActor func flush() async {
        for _ in 0..<80 { await Task.yield() }
    }

    /// Run until the engine waits for the visitor: every timeout in time
    /// order; when only repeating timers are left (a countdown, a status
    /// poll) it stops. With `waitMs`, time runs on - intervals included - that long.
    @MainActor func settle(_ waitMs: Double? = nil) async {
        let explicit = waitMs != nil
        let limit = nowMs + (waitMs ?? 30 * 60 * 1000)
        for _ in 0..<200_000 {
            await flush()
            let next = timers.values
                .filter { explicit || $0.every == 0 }
                .min { $0.at != $1.at ? $0.at < $1.at : $0.id < $1.id }
            guard let t = next, t.at <= limit else {
                if explicit { nowMs = max(nowMs, limit) }
                await flush()
                return
            }
            nowMs = max(nowMs, t.at)
            if t.every > 0 { t.at = nowMs + t.every } else { timers[t.id] = nil }
            t.fn()
        }
    }

    func reset() {
        nowMs = 0
        seq = 0
        timers = [:]
    }
}

// MARK: - Bot API, scripted by server.http (web/driver.js)

final class FlowFakeTransport: FlowTransport {
    private let scripted: [String: Any]
    private var calls: [String: Int] = [:]
    var http: [[String: Any]] = []

    init(server: [String: Any]) {
        scripted = JS.dict(server["http"])
    }

    @MainActor func send(_ request: URLRequest) async -> (status: Int, body: Data?)? {
        let url = request.url?.absoluteString ?? ""
        let key = Re("/api/v1/bot/[^/]+/(.+?)(\\?|$)").match(url)?[1] ?? url
        calls[key, default: 0] += 1
        let body: Any? = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        var entry: [String: Any] = ["path": key]
        if key != "media", let b = body { entry["body"] = b }
        http.append(entry)
        var r: Any? = scripted[key]
        if let list = r as? [Any] { r = list[min(calls[key]! - 1, list.count - 1)] }
        if r == nil && key == "media" { r = ["status": 200, "body": ["url": "https://api.test/media/qa-file"]] }
        guard let reply = r as? [String: Any] else { return nil } // missing or "network"
        let status = JS.isNumber(reply["status"]) ? Int(JS.toNumber(reply["status"])) : 200
        let data = (try? JSONSerialization.data(withJSONObject: JS.plain(reply["body"]) ?? NSNull(), options: [.fragmentsAllowed])) ?? Data("null".utf8)
        return (status, data)
    }
}

// MARK: - The fake socket (web/fakeSocket.js)

final class FlowFakeSocket: FlowSocket {
    private let server: [String: Any]
    private let clock: FlowVirtualClock
    private let hub = FlowEventHub()
    var emits: [String] = []

    init(server: [String: Any], clock: FlowVirtualClock) {
        self.server = server
        self.clock = clock
    }

    var isConnected: Bool { true }

    func on(_ event: String, _ listener: @escaping ([String: Any]) -> Void) -> () -> Void { hub.on(event, listener) }

    func fire(_ event: String, _ payload: [String: Any]) { hub.fire(event, payload) }

    func sendResponseRecord(_ data: [String: Any]) {}

    func emit(_ event: String, _ payload: [String: Any]) {
        // The record resend and the room join are transport, not flow events.
        if event != "response-record" && event != "join-chat-room-visitor" { emits.append(event) }
        if event == "execute-integration" {
            let integration = JS.dict(server["integration"])
            let r = integration[JS.text(payload["nodeId"])] ?? integration[JS.text(payload["nodeType"])] ?? ["success": true]
            if (r as? String) != "none", let result = r as? [String: Any] {
                var out = result
                out["nodeId"] = payload["nodeId"]
                let delay = JS.isNumber(result["delayMs"]) ? JS.toNumber(result["delayMs"]) : 50
                clock.add(ms: delay, repeats: false) { [weak self] in self?.fire("integration-result", out) }
            }
        }
        if event == "initiate-handover", JS.text(server["handover"]) == "no-agents" {
            let id = payload["chatSessionId"] ?? NSNull()
            clock.add(ms: 1000, repeats: false) { [weak self] in self?.fire("no-agents-available", ["chatSessionId": id]) }
        }
    }
}

// MARK: - The driver

struct FlowFixtureResult {
    var outcome: [String: Any]
    var problems: [String]
}

@MainActor
enum FlowFixtureDriver {

    static let pageURL = "https://shop.example/pricing?utm_source=newsletter&utm_campaign=fall"
    static let referrer = "https://www.google.com/"

    /// The buttons / options the step drew, in order.
    private static func shownOptions(_ ui: NodeUIState?) -> [(id: String, label: String, value: String)] {
        switch ui {
        case .buttons(let buttons, _)?: return buttons.map { ($0.id, $0.label, $0.label) }
        case .singleChoice(let options, _)?, .multiChoice(let options, _)?, .quickReplies(let options, _)?:
            return options.map { ($0.id, $0.label, $0.value) }
        case .cards(let cards, _)?: return cards.flatMap { $0.buttons.map { ($0.id, $0.label, $0.label) } }
        default: return []
        }
    }

    /// A visitor action -> the answer the SDK's UI sends (nil: nothing to send).
    private static func answerFor(_ a: [String: Any], _ ui: NodeUIState?, _ node: [String: Any]?, _ memo: inout [String: Any]) throws -> Any? {
        let nodeId = JS.text(node?["id"])
        switch JS.text(a["do"]) {
        case "text":
            return JS.str(a["value"])
        case "choose":
            if let b = a["buttonId"] { return ["buttonId": JS.str(b)] }
            if let v = a["value"] { return ["value": v] }
            let list = shownOptions(ui)
            if let id = a["id"] {
                guard let b = list.first(where: { $0.id == JS.str(id) }) else { throw DriverError("no shown option with id \(JS.str(id))") }
                return ["buttonId": b.id, "label": b.label, "value": b.value]
            }
            if let i = a["index"] {
                let index = Int(JS.toNumber(i))
                guard index >= 0, index < list.count else { throw DriverError("no shown option at index \(index)") }
                let b = list[index]
                return ["buttonId": b.id, "label": b.label, "value": b.value, "index": index]
            }
            return ["action": "continue"]
        case "check":
            return ["buttonIds": a["ids"] ?? []]
        case "file":
            return ["file": ["name": a["name"] ?? "", "size": a["size"] ?? 0, "type": a["type"] ?? "", "uri": "file:///tmp/\(JS.text(a["name"]))"]]
        case "skip":
            return ["skip": true]
        case "navigateLink":
            return ["action": "link", "index": a["index"] ?? 0]
        case "navigateDone":
            return ["action": "done"]
        case "date":
            return JS.str(a["value"])
        case "calendar":
            var r: [String: Any] = ["date": a["date"] ?? ""]
            if let s = a["slot"] { r["slot"] = s }
            return r
        case "consent":
            return ["agreed": JS.truthy(a["agreed"])]
        case "slider", "datetime":
            return ["value": a["value"] ?? NSNull()]
        case "rankingMove":
            var order = (memo[nodeId] as? [String]) ?? shownOptions(ui).map { $0.id }
            if let i = order.firstIndex(of: JS.str(a["id"])) {
                let j = i + Int(JS.toNumber(a["dir"]))
                if j >= 0 && j < order.count { order.swapAt(i, j) }
            }
            memo[nodeId] = order
            return nil
        case "rankingSubmit":
            return ["order": (memo[nodeId] as? [String]) ?? shownOptions(ui).map { $0.id }]
        case "matrix":
            var cells = (memo[nodeId] as? [String: Any]) ?? [:]
            let multiple = JS.text(JS.dict(node?["data"])["mode"]) == "multiple"
            for (row, cols) in JS.dict(a["cells"]) {
                let list = (cols as? [Any]) ?? [cols]
                if multiple {
                    var cur = (cells[row] as? [Any]) ?? []
                    for c in list where !cur.contains(where: { JS.str($0) == JS.str(c) }) { cur.append(c) }
                    cells[row] = cur
                } else {
                    cells[row] = list.last ?? NSNull()
                }
            }
            memo[nodeId] = cells
            if JS.bool(a["submit"]) == false { return nil }
            return ["cells": cells]
        case "otpEmail": return ["action": "send", "email": a["email"] ?? ""]
        case "otpCode": return ["action": "verify", "code": JS.str(a["code"])]
        case "otpSkip": return ["action": "skip"]
        case "addressManual":
            return ["action": "manual", "line1": a["line1"] ?? NSNull(), "city": a["city"] ?? NSNull(), "region": a["region"] ?? NSNull(),
                    "postal": a["postal"] ?? NSNull(), "country": a["country"] ?? NSNull()]
        case "addressSearch": return ["action": "search", "q": a["q"] ?? ""]
        case "addressPick": return ["action": "pick", "index": a["index"] ?? 0]
        case "signTyped":
            var r: [String: Any] = ["action": "sign", "method": "typed", "name": a["name"] ?? ""]
            if let f = a["fullName"] { r["fullName"] = f }
            return r
        case "signEmpty": return ["action": "sign", "method": "drawn", "strokes": 0]
        case "payOpen": return ["action": "open"]
        case "payCancel": return ["action": "cancel"]
        case "wait": return nil
        default: throw DriverError("unknown action \(JS.text(a["do"]))")
        }
    }

    struct DriverError: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    private static let strip: Set<String> = ["time", "at", "agreedAt", "options", "choices", "images", "carousel", "_id"]

    /// A record entry minus times and copies of the node data (web/driver.js clean).
    static func clean(_ v: Any?) -> Any? {
        if let a = v as? [Any] { return a.map { clean($0) ?? NSNull() } }
        guard let o = v as? [String: Any] else { return v }
        var out: [String: Any] = [:]
        for (k, x) in o where !strip.contains(k) { out[k] = clean(x) }
        return out
    }

    static func run(_ fx: [String: Any]) async -> FlowFixtureResult {
        let clock = FlowVirtualClock()
        let server = JS.dict(fx["server"])
        let transport = FlowFakeTransport(server: server)
        let socket = FlowFakeSocket(server: server, clock: clock)
        var problems: [String] = []
        var trace: [(event: FlowTraceEvent, t: Double)] = []
        var randoms = JS.array(fx["random"]).map { JS.toNumber($0) }

        let state = ChatState()
        state.setSession(sessionId: "qa-session", botId: "qa-bot")
        state.setVariable(name: "_visitorId", value: "qa-visitor")
        let registry = NodeHandlerRegistry()
        registry.registerAllHandlers()
        var config = NodeFlowEngine.Config()
        config.clock = clock
        config.transport = transport
        config.socket = socket
        config.apiOrigin = "https://api.test"
        config.visitorTimeZone = (fx["visitorTimeZone"] as? String) ?? "UTC"
        config.customizations = JS.dict(fx["customizations"])
        config.page = FlowPage(url: pageURL, referrer: referrer)
        config.random = { randoms.count > 1 ? randoms.removeFirst() : (randoms.first ?? 0.5) }
        config.onTrace = { trace.append(($0, clock.nowMs)) }
        let engine = NodeFlowEngine(state: state, registry: registry, config: config)

        let flow = JS.dict(fx["flow"])
        engine.loadFlow(flow)
        Task { @MainActor in await engine.start() }
        await clock.settle()

        var memo: [String: Any] = [:]
        for (i, raw) in JS.array(fx["inputs"]).enumerated() {
            let a = JS.dict(raw)
            let action = JS.text(a["do"])
            let at = engine.currentNodeId
            if action != "serverEvent" {
                if let want = a["at"] as? String, want != at { problems.append("input \(i): waiting at \(at ?? "nil"), fixture expected \(want)") }
                if !engine.isWaitingForInput && action != "wait" { problems.append("input \(i) (\(action)): engine is not waiting (at \(at ?? "nil"))") }
            }
            do {
                if action == "serverEvent" {
                    socket.fire(JS.text(a["event"]), JS.dict(a["payload"]))
                } else if let response = try answerFor(a, engine.currentUIState, at.flatMap { engine.getNode($0) }, &memo) {
                    Task { @MainActor in await engine.submitResponse(response) }
                }
            } catch {
                problems.append("input \(i) (\(action)): \(error)")
            }
            let waitMs = a["waitMs"].map { JS.toNumber($0) }
            await clock.settle(waitMs)
            if waitMs != nil { await clock.settle() }
        }

        // The outcome (web/driver.js outcome)
        var path: [[String: Any]] = []
        var shownAt: [String: Double] = [:]
        var shownOrder: [String] = []
        var ports: [[String: Any]] = []
        var errors: [[String: Any]] = []
        var unsupported: [[String: Any]] = []
        var endT: Double?
        var crash: (node: String, reason: String)?
        for (e, t) in trace {
            switch e {
            case .enter(let node, let type, let via): path.append(["node": node, "type": type, "via": via, "t": t])
            case .shown(let node):
                if shownAt[node] == nil { shownAt[node] = t; shownOrder.append(node) }
            case .port(let node, let handle, let wired): ports.append(["node": node, "handle": handle, "wired": wired])
            case .unsupported(let node, let type): unsupported.append(["node": node, "type": type])
            case .error(let node, let message): errors.append(["node": node, "message": message])
            case .end: if endT == nil { endT = t }
            case .crash(let node, let reason): if crash == nil { crash = (node, reason) }
            }
        }
        let record = state.getServerRecord()
        let rendered: [[String: Any]] = record.compactMap { r in
            guard !JS.text(r["type"]).isEmpty, r["shape"] == nil, r["source"] == nil, let html = r["renderedText"] as? String else { return nil }
            return ["node": JS.text(r["id"]), "html": html, "plain": FlowText.plainText(html)]
        }
        let answers: [Any] = record.filter { r in
            if let shape = r["shape"] as? String, !shape.isEmpty { return shape.hasPrefix("user") }
            return JS.text(r["type"]).hasPrefix("user") && r["data"] == nil && r["position"] == nil
        }.map { clean($0) ?? NSNull() }
        var flowVariables: [String: Any] = [:]
        for (k, v) in state.variables where !k.hasPrefix("_") { flowVariables[k] = v }
        var end: [String: Any]
        if engine.isEnded {
            end = ["ended": true, "t": endT ?? NSNull()]
        } else {
            let at = engine.currentNodeId
            end = ["ended": false, "waitingAt": at ?? NSNull(), "type": at.flatMap { engine.getNode($0)?["type"] } ?? NSNull()]
        }
        if let c = crash { end = ["ended": false, "crashed": true, "at": c.node, "reason": c.reason] }
        var outcome: [String: Any] = [
            "path": path,
            "shown": shownOrder.map { ["node": $0, "t": shownAt[$0]!] },
            "rendered": rendered,
            "ports": ports,
            "answers": answers,
            "variables": state.flowAnswerVariables().map { ["key": $0.key, "value": $0.value, "nodeId": $0.nodeId] },
            "errors": errors,
            "http": transport.http,
            "emits": socket.emits,
            "unsupported": unsupported,
            "end": end,
            "transcript": state.getTranscript().map { ["by": JS.text($0["type"]), "message": $0["message"] ?? NSNull()] },
        ]
        if !flowVariables.isEmpty { outcome["flowVariables"] = flowVariables }
        clock.reset()
        return FlowFixtureResult(outcome: outcome, problems: problems)
    }
}
