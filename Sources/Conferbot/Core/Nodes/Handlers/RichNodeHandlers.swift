//
//  RichNodeHandlers.swift
//  Conferbot
//
//  The rich steps (conferbot-widget/src/ts/chat/richNodes.ts and
//  richNodesView.ts), as the React Native SDK's RichNodeHandlers.ts runs
//  them: dynamic-choices, hidden-fields, consent, product-card, slider,
//  datetime, ranking, otp, address, matrix, ai-extract, ai-route,
//  kb-answer, signature and payment. The rules are the web's, ported in
//  Core/Flow/FlowRich.swift; each step draws through this SDK's existing UI
//  states (buttons, cards, a scale, the calendar, the composer) and takes
//  the answer those send, or the explicit actions listed on each handler.
//
//  Gates stay gates: payment leaves by "source" only when the server says
//  paid, OTP only when otp/verify says verified (the web's documented
//  fallback aside), required consent only once agreed.
//

import Foundation

/// A server call as the rich steps read it (web richApi.ts richPost).
private struct RichReply {
    let ok: Bool
    let status: Int
    let data: Any?
    let code: String?
}

@MainActor
private func richPost(_ ctx: FlowContext, _ path: String, _ body: [String: Any], timeoutMs: Double = 15000) async -> RichReply {
    let r = await ctx.api(path, body, timeoutMs: timeoutMs)
    if let e = r.error { return RichReply(ok: false, status: 0, data: nil, code: e) }
    var code: String?
    if !r.ok {
        let c = JS.dict(r.body)["code"]
        code = JS.truthy(c) ? JS.str(c) : (r.status == 429 ? "rate_limited" : "error")
    }
    return RichReply(ok: r.ok, status: r.status, data: r.body, code: code)
}

/// Who a code / payment belongs to: the chat session (web richSessionId).
private func sessionOf(_ state: ChatState) -> String {
    let s = state.sessionId.isEmpty ? (state.visitorId ?? (state.getVariable(name: "_visitorId") as? String) ?? "anonymous") : state.sessionId
    return s.jsSlice(0, 100)
}

/// A variable read the way the rich steps read it: the answers, by name.
private func lookup(_ state: ChatState) -> VariableLookup {
    { key in state.hasAnswerVariable(key) ? state.answerValue(key) : nil }
}

/// Fills the step's own variable (registered when shown) and the rest by name.
private func saveVars(_ state: ChatState, _ node: [String: Any], _ vars: FlowVars) {
    let key = JS.text(FlowKit.data(node)["answerVariable"]).trimmed
    let nodeId = FlowKit.id(node)
    for (k, v) in vars {
        if k == key { state.setAnswerVariable(nodeId: nodeId, value: v) } else { state.saveVariableByName(k, value: v) }
    }
}

/// The visitor's answer (web richNodesView answer()): record, transcript, the step's variable.
private func answer(_ state: ChatState, _ node: [String: Any], _ entry: [String: Any], _ text: String, _ value: Any) {
    var e = entry
    e["id"] = FlowKit.id(node)
    FlowKit.pushAnswer(state, e)
    FlowKit.userSay(state, text, FlowKit.id(node))
    if JS.truthy(FlowKit.data(node)["answerVariable"]) { state.setAnswerVariable(nodeId: FlowKit.id(node), value: value) }
}

/// The step's prompt (questionText, or a default when it is blank), filled.
private func prompt(_ node: [String: Any], _ state: ChatState, _ fallback: String = "") -> String {
    let q = FlowKit.data(node)["questionText"]
    return FlowKit.filledHtml(state, FlowText.plainText(q).isEmpty ? fallback : q)
}

private func say(_ state: ChatState, _ html: String, _ node: [String: Any]) {
    if !FlowText.bubbleText(html).isEmpty { FlowKit.botSay(state, html: html, nodeId: FlowKit.id(node), nodeType: JS.text(node["type"])) }
}

// MARK: - Dynamic choices

/// dynamic-choices-node: options from the list in data.sourceVariable
/// (labelField / valueField); saves the item's value and <var>_label when
/// it differs. Nothing to choose: emptyMessage and source-empty (or
/// "source" when only that is wired). "webhook" waits up to 8 s for the list.
public final class DynamicChoicesNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "dynamic-choices-node" }
    private var shown: [String: [FlowRich.DynamicOption]] = [:]

    @MainActor
    private func sourceValue(_ node: [String: Any], _ state: ChatState, _ ctx: FlowContext) async -> Any? {
        let key = FlowRich.dynamicSourceVariable(FlowKit.data(node))
        let read = { key.isEmpty ? nil : lookup(state)(key) }
        var v = read()
        if !JS.isNullish(v) || JS.text(FlowKit.data(node)["source"]) != "webhook" { return v }
        let started = Flow.ms(ctx.now())
        while Flow.ms(ctx.now()) - started <= 8000 {
            await ctx.delay(250)
            v = read()
            if !JS.isNullish(v) { return v }
        }
        return v
    }

    private func ui(_ node: [String: Any], _ options: [FlowRich.DynamicOption]) -> NodeUIState {
        .buttons(buttons: options.map { ButtonOption(id: $0.id, label: $0.label) }, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let ctx = ctxOf(node, state)
        let nodeId = FlowKit.id(node)
        let options = FlowRich.dynamicOptions(FlowKit.data(node), await sourceValue(node, state, ctx))
        state.addRecord(["_id": nodeId, "id": nodeId, "type": nodeType, "options": options.map { ["label": $0.label, "value": $0.value] }])
        if options.isEmpty {
            let empty = JS.truthy(FlowKit.data(node)["emptyMessage"]) ? FlowKit.data(node)["emptyMessage"] : "<p>\(FlowI18n.t("rich.nothingToChoose"))</p>"
            say(state, FlowKit.filledHtml(state, empty), node)
            return .port(FlowRich.dynamicEmptyHandle, fallback: "source")
        }
        say(state, prompt(node, state), node)
        shown[nodeId] = options
        return .displayUI(ui(node, options))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let options = shown[nodeId] ?? []
        let id = FlowKit.pickedId(response)
        let index = JS.dict(response)["index"].map { Int(JS.toNumber($0)) }
        guard let o = options.first(where: { $0.id == id }) ?? index.flatMap({ $0 >= 0 && $0 < options.count ? options[$0] : nil }) else {
            return .displayUI(ui(node, options))
        }
        answer(state, node, ["shape": "user-selected-dynamic-choice", "selectedChoice": o.label, "value": o.value], o.label, o.value)
        let key = JS.text(FlowKit.data(node)["answerVariable"])
        if !key.isEmpty && JS.str(o.value) != o.label { state.saveVariableByName("\(key)_label", value: o.label) }
        shown[nodeId] = nil
        return .port("source")
    }
}

// MARK: - Hidden fields

/// hidden-fields-node: shows nothing; saves the page's query parameters,
/// its URL and the referrer by name. An app has no page: the host app
/// supplies one (NodeFlowEngine.Config.page, e.g. a deep link) or nothing
/// is captured.
public final class HiddenFieldsNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "hidden-fields-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let page = ctxOf(node, state).page
        let captured = FlowRich.captureHiddenFields(FlowKit.data(node), href: page?.url, referrer: page?.referrer)
        for (k, v) in captured { state.saveVariableByName(k, value: v) }
        var dict: [String: Any] = [:]
        for (k, v) in captured { dict[k] = v }
        state.addRecord(["_id": FlowKit.id(node), "id": FlowKit.id(node), "type": nodeType, "captured": dict])
        return .port("source")
    }
}

// MARK: - Consent

/// consent-node: the consent text and Continue. Answers: ["agreed": Bool]
/// (the box ticked or not, then Continue), or the buttons "agree" /
/// "continue". Required and not agreed: "Please tick the box to continue."
/// and it waits. Saves true / false and <var>_at; always leaves by "source".
public final class ConsentNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "consent-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        let data = FlowKit.data(node)
        let text = FlowRich.markdownLitePlain(data["consentText"])
        return .buttons(buttons: [
            ButtonOption(id: "agree", label: text.isEmpty ? I18n.t("sdk.consent.agree") : "✓ \(text)"),
            ButtonOption(id: "continue", label: FlowRich.consentContinueLabel(data)),
        ], nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        say(state, prompt(node, state), node)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let data = FlowKit.data(node)
        let r = JS.dict(response)
        let agreed = JS.bool(r["agreed"]) ?? (FlowKit.pickedId(response) == "agree")
        let required = FlowRich.consentRequired(data)
        if required && !agreed { return .invalid(FlowI18n.t("consent.tickBox"), uiState: ui(node), inCard: true) }
        let at = Flow.iso(ctxOf(node, state).now())
        let reply = FlowRich.consentReply(data["consentText"], agreed)
        answer(state, node, [
            "shape": "user-consent", "agreed": agreed, "agreedAt": agreed ? at : NSNull(),
            "consentText": FlowRich.markdownLitePlain(data["consentText"]), "documents": FlowRich.consentDocuments(data["consentText"]),
            "required": required, "selectedChoice": reply,
        ], reply, agreed)
        let k = JS.text(data["answerVariable"])
        if !k.isEmpty && agreed { state.saveVariableByName("\(k)_at", value: at) }
        return .port("source")
    }
}

// MARK: - Product card

/// product-card-node: one card (image, title, price, description) with up
/// to three buttons. A path button leaves by "source-" + its id and saves
/// its label; with only link buttons, Continue leaves by "source".
public final class ProductCardNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "product-card-node" }

    private func card(_ node: [String: Any]) -> Carousel.Card? { Carousel.cards(FlowRich.productCarouselData(FlowKit.data(node))).first }

    private func ui(_ node: [String: Any], _ state: ChatState) -> NodeUIState {
        Carousel.ui(card(node).map { [$0] } ?? [], FlowKit.id(node), state)
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        say(state, prompt(node, state), node)
        return .displayUI(ui(node, state))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let c = card(node)
        let id = JS.text(JS.dict(response)["action"]) == "continue" ? nil : FlowKit.pickedId(response)
        let button = c?.buttons.first { $0.id == id && $0.action == "path" }
        if id != nil && button == nil { return .displayUI(ui(node, state)) }
        if let b = button, let c = c {
            answer(state, node, ["shape": "user-selected-product-card", "selectedChoice": b.label, "selectedButtonId": b.id,
                                 "product": ["title": c.title, "price": c.price]], b.label, b.label)
            return .port("source-\(b.id)")
        }
        if c?.buttons.contains(where: { $0.action == "path" }) == true { return .displayUI(ui(node, state)) }
        FlowKit.pushAnswer(state, ["id": FlowKit.id(node), "shape": "user-selected-product-card", "selectedChoice": Carousel.continueLabel, "selectedButtonId": NSNull()])
        FlowKit.userSay(state, Carousel.continueLabel, FlowKit.id(node))
        return .port("source")
    }
}

// MARK: - Slider

/// slider-node: min / max / step / unit; the value snapped to the step,
/// saved as a number. Drawn as a scale (min..max). Answer ["value": n] or a number.
public final class SliderNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "slider-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        let cfg = FlowRich.sliderConfig(FlowKit.data(node))
        return .opinionScale(min: Int(cfg.min), max: Int(cfg.max), minLabel: nil, maxLabel: nil, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        say(state, prompt(node, state), node)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let cfg = FlowRich.sliderConfig(FlowKit.data(node))
        let raw = Rating.picked(response)
        guard raw.isFinite else { return .displayUI(ui(node)) }
        let value = FlowRich.snapToStep(raw, cfg.min, cfg.max, cfg.step)
        let text = FlowRich.sliderLabel(value, cfg)
        answer(state, node, ["shape": "user-slider", "value": JS.num(value), "display": text, "min": JS.num(cfg.min), "max": JS.num(cfg.max), "unit": cfg.unit], text, JS.num(value))
        return .port("source")
    }
}

// MARK: - Date / time

/// datetime-node: mode date / time / datetime with minDate / maxDate,
/// disabledWeekdays, minTime / maxTime. A refused pick says why. Saves the
/// ISO value and <var>_display. Answer ["value": "2026-10-19" | "14:30" |
/// "2026-10-19T14:30"], the calendar's ["date", "time"], or a picked Date.
public final class DateTimeNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "datetime-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        let mode = FlowRich.dateMode(FlowKit.data(node))
        return .calendar(mode: mode == "time" ? .time : mode == "datetime" ? .dateTime : .date, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        say(state, prompt(node, state), node)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let data = FlowKit.data(node)
        let ctx = ctxOf(node, state)
        let zone = TimeZone(identifier: ctx.visitorTimeZone) ?? .current
        let mode = FlowRich.dateMode(data)
        var raw: Any?
        if let d = response as? Date {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            let ymd = "\(String(c.year!).padStart(4))-\(String(c.month!).padStart(2))-\(String(c.day!).padStart(2))"
            let hm = "\(String(c.hour!).padStart(2)):\(String(c.minute!).padStart(2))"
            raw = mode == "time" ? hm : mode == "datetime" ? "\(ymd)T\(hm)" : ymd
        } else if let r = response as? [String: Any] {
            raw = [r["value"], r["datetime"]].first(where: { !JS.isNullish($0) }) ?? nil
            if raw == nil, JS.truthy(r["date"]) { raw = mode == "datetime" ? "\(JS.text(r["date"]))T\(JS.text(r["time"]))" : r["date"] }
            if raw == nil, JS.truthy(r["time"]) { raw = r["time"] }
        } else {
            raw = response
        }
        let iso = FlowRich.isoFromInput(mode, raw)
        if let problem = FlowRich.dateTimeError(data, iso, today: ctx.now(), zone: zone) { return .invalid(problem, uiState: ui(node), inCard: true) }
        let display = FlowRich.dateTimeDisplay(data, iso)
        answer(state, node, ["shape": "user-datetime", "value": iso, "display": display, "mode": mode], display, iso)
        let k = JS.text(data["answerVariable"])
        if !k.isEmpty { state.saveVariableByName("\(k)_display", value: display) }
        return .port("source")
    }
}

// MARK: - Ranking

/// ranking-node: the items in the visitor's order. Answer ["order": [ids]],
/// or the multi-select ids in the order tapped (unpicked items follow).
public final class RankingNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "ranking-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        .multiChoice(options: FlowRich.rankingItems(FlowKit.data(node)).map { ChoiceOption(id: $0.id, label: $0.text, value: $0.text) }, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        say(state, prompt(node, state), node)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let items = FlowRich.rankingItems(FlowKit.data(node))
        let r = JS.dict(response)
        let ids = ((r["order"] as? [Any]) ?? (r["buttonIds"] as? [Any]) ?? []).map { JS.str($0) }
        var picked: [FlowRich.RankItem] = []
        for id in ids { if let it = items.first(where: { $0.id == id }), !picked.contains(where: { $0.id == it.id }) { picked.append(it) } }
        let order = picked + items.filter { it in !picked.contains { $0.id == it.id } }
        let text = FlowRich.rankingText(order)
        let values = order.map { $0.text }
        answer(state, node, ["shape": "user-ranking", "order": order.map { ["id": $0.id, "text": $0.text] }, "value": values, "display": text], text, values)
        return .port("source")
    }
}

// MARK: - OTP

/// otp-node: an e-mail, then a six-digit code checked on the server
/// (POST otp/send, otp/verify). Answers: ["action": "send", "email"] (or
/// the typed e-mail), ["action": "verify", "code"] (or six typed digits),
/// ["action": "skip"] (allowSkip). Verified leaves by "source"; locked,
/// skipped, sms or a failed send by "source-failed" - or "source" when only
/// that edge is drawn (the web's goPort fallback). A network error says so
/// and keeps waiting.
public final class OtpNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "otp-node" }

    private func key(_ node: [String: Any]) -> String { "_otp_\(FlowKit.id(node))" }

    private func ui(_ node: [String: Any], _ stage: String) -> NodeUIState {
        .textInput(placeholder: stage == "email" ? I18n.t("otp.emailPlaceholder") : "123456", validation: nil, nodeId: FlowKit.id(node))
    }

    @MainActor
    private func finish(_ node: [String: Any], _ state: ChatState, _ verified: Bool, _ email: String, _ reason: String? = nil) -> NodeResult {
        let text = FlowRich.otpReplyText(verified, email)
        var entry: [String: Any] = ["id": FlowKit.id(node), "shape": "user-otp", "verified": verified, "channel": "email", "at": Flow.iso(Date())]
        if verified { entry["email"] = email }
        if let r = reason { entry["reason"] = r }
        FlowKit.pushAnswer(state, entry)
        FlowKit.userSay(state, text, FlowKit.id(node))
        let k = JS.text(FlowKit.data(node)["answerVariable"]).trimmed
        if !k.isEmpty {
            if verified { state.setAnswerVariable(nodeId: FlowKit.id(node), value: email) }
            state.saveVariableByName("\(k)_verified", value: verified)
        }
        state.deleteVariable(name: key(node))
        return verified ? .port("source") : .port("source-failed", fallback: "source")
    }

    @MainActor
    private func send(_ node: [String: Any], _ state: ChatState, _ to: String) async -> NodeResult {
        let ctx = ctxOf(node, state)
        if !FlowRich.isEmailAddress(to) { return .invalid(FlowRich.otpErrorText("invalid_email"), uiState: ui(node, "email"), inCard: true) }
        let target = to.trimmed.lowercased()
        let r = await richPost(ctx, "otp/send", ["nodeId": FlowKit.id(node), "sessionId": sessionOf(state), "email": target])
        if r.ok || r.code == "resend_wait" {
            state.setVariable(name: key(node), value: ["stage": "code", "email": target])
            let sentTo = JS.text(JS.dict(r.data)["sentTo"])
            FlowKit.botSay(state, text: I18n.t("otp.sentTo", ["n": FlowRich.otpLength, "email": sentTo.isEmpty ? target : sentTo]), nodeId: FlowKit.id(node), nodeType: nodeType)
            if r.code == "resend_wait" {
                return .invalid(FlowRich.otpErrorText("resend_wait", retryAfter: JS.dict(r.data)["retryAfter"]), uiState: ui(node, "code"), inCard: true)
            }
            return .displayUI(ui(node, "code"))
        }
        if FlowRich.otpEndsStep(r.code) {
            return finish(node, state, false, "", r.code == "locked" ? "locked" : r.code == "sms_unavailable" ? "sms_unavailable" : "send_failed")
        }
        return .invalid(FlowRich.otpErrorText(r.code), uiState: ui(node, "email"), inCard: true)
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        state.deleteVariable(name: key(node))
        if FlowRich.otpChannel(FlowKit.data(node)) == "sms" { return finish(node, state, false, "", "sms_unavailable") }
        say(state, prompt(node, state), node)
        let preset = FlowRich.otpPresetEmail(FlowKit.data(node), lookup(state))
        if !preset.isEmpty { return await send(node, state, preset) }
        return .displayUI(ui(node, "email"))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let st = JS.dict(state.getVariable(name: key(node)))
        let stage = JS.text(st["stage"]).isEmpty ? "email" : JS.text(st["stage"])
        let r = JS.dict(response)
        let action = JS.text(r["action"])
        if action == "skip" {
            if !JS.truthy(FlowKit.data(node)["allowSkip"]) { return .displayUI(ui(node, stage)) }
            return finish(node, state, false, "", "skipped")
        }
        if action == "send" || action == "resend" || (action.isEmpty && stage == "email") {
            let to = action == "resend" ? JS.text(st["email"]) : (r["email"] != nil ? JS.text(r["email"]) : FlowKit.typedText(response))
            return await send(node, state, to)
        }
        // verify
        let code = (r["code"] != nil ? JS.text(r["code"]) : FlowKit.typedText(response)).replacing("[^0-9]", with: "")
        if code.count != FlowRich.otpLength { return .invalid(FlowRich.otpErrorText("invalid_code"), uiState: ui(node, "code"), inCard: true) }
        let reply = await richPost(ctxOf(node, state), "otp/verify", ["nodeId": FlowKit.id(node), "sessionId": sessionOf(state), "code": code])
        let res: [String: Any] = reply.ok ? JS.dict(reply.data) : ["verified": false, "code": reply.code ?? NSNull()]
        if JS.truthy(res["verified"]) {
            let email = JS.text(res["email"]).isEmpty ? JS.text(st["email"]) : JS.text(res["email"])
            return finish(node, state, true, email.lowercased())
        }
        if JS.text(res["code"]) == "locked" { return finish(node, state, false, "", "locked") }
        return .invalid(FlowRich.otpErrorText(res["code"], attemptsLeft: res["attemptsLeft"]), uiState: ui(node, "code"), inCard: true)
    }
}

// MARK: - Address

/// address-node: search (POST geo/search, results to pick) or typed by
/// hand (street required). Answers: ["action": "search", "q"], ["action":
/// "pick", "index"], ["action": "manual", line1, city, region, postal,
/// country], or the typed address (the street line). Saves the formatted
/// address and <var>_line1 / _city / _region / _postal / _country /
/// _country_code / _lat / _lng.
public final class AddressNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "address-node" }
    private var results: [String: [FlowRich.AddressValue]] = [:]

    private func ui(_ node: [String: Any], _ found: [FlowRich.AddressValue] = []) -> NodeUIState {
        if found.isEmpty { return .textInput(placeholder: I18n.t("address.street"), validation: nil, nodeId: FlowKit.id(node)) }
        return .singleChoice(options: found.enumerated().map { ChoiceOption(id: String($0.offset), label: $0.element.formatted, value: $0.element.formatted) }, nodeId: FlowKit.id(node))
    }

    @MainActor
    private func finish(_ node: [String: Any], _ state: ChatState, _ value: FlowRich.AddressValue, _ source: String) -> NodeResult {
        FlowKit.pushAnswer(state, ["id": FlowKit.id(node), "shape": "user-address", "value": value.dict, "display": value.formatted, "source": source, "at": Flow.iso(Date())])
        FlowKit.userSay(state, value.formatted, FlowKit.id(node))
        let k = JS.text(FlowKit.data(node)["answerVariable"]).trimmed
        if !k.isEmpty { saveVars(state, node, FlowRich.addressVariables(k, value)) }
        results[FlowKit.id(node)] = nil
        return .port("source")
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        say(state, prompt(node, state), node)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let r = JS.dict(response)
        let action = JS.text(r["action"])
        if action == "search" {
            let q = JS.text(r["q"]).trimmed
            if q.count < 3 { return .displayUI(ui(node)) }
            let reply = await richPost(ctxOf(node, state), "geo/search", ["nodeId": nodeId, "q": q])
            let found = reply.ok ? Array(JS.array(JS.dict(reply.data)["results"]).map { FlowRich.normalizeAddress($0) }.filter { !$0.formatted.isEmpty }.prefix(5)) : []
            results[nodeId] = found
            if !reply.ok { return .invalid(FlowRich.addressErrorText(reply.code), uiState: ui(node), inCard: true) }
            if found.isEmpty { return .invalid(FlowRich.addressErrorText("no_results"), uiState: ui(node), inCard: true) }
            return .displayUI(ui(node, found))
        }
        let found = results[nodeId] ?? []
        if action == "pick" || (action.isEmpty && !found.isEmpty && JS.dict(response)["buttonId"] != nil) {
            let i = action == "pick" ? Int(JS.toNumber(r["index"])) : Int(JS.text(r["buttonId"])) ?? -1
            guard i >= 0, i < found.count else { return .displayUI(ui(node, found)) }
            return finish(node, state, found[i], "search")
        }
        let fields: [String: Any] = action == "manual" ? r : ["line1": (response as? String) ?? JS.text(r["address"])]
        guard JS.bool(FlowKit.data(node)["allowManual"]) != false, let value = FlowRich.manualAddress(fields) else {
            return .invalid(I18n.t("sdk.flow.streetRequired"), uiState: ui(node), inCard: true)
        }
        return finish(node, state, value, "manual")
    }
}

// MARK: - Matrix

/// matrix-node: rows x columns, one column per row (single) or several
/// (multiple). requireAll: every row; else at least one. Saves {row:
/// column} (or {row: [columns]}). No rows, or fewer than two columns:
/// straight on by "source". Answer ["cells": [rowId: colId | [colIds]]].
/// There is no native grid yet: it is drawn as `.rich("matrix-node")`.
public final class MatrixNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "matrix-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        .rich(type: nodeType, data: FlowKit.data(node), nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = FlowKit.data(node)
        if FlowRich.matrixRows(data).isEmpty || FlowRich.matrixColumns(data).count < 2 { return .port("source") }
        say(state, prompt(node, state), node)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let data = FlowKit.data(node)
        let rows = FlowRich.matrixRows(data)
        let cols = FlowRich.matrixColumns(data)
        let mode = FlowRich.matrixMode(data)
        let r = JS.dict(response)
        let cells = JS.dict(r["cells"] ?? r["formData"])
        var sel = FlowRich.MatrixSelection()
        for (rowId, picked) in cells {
            let list: [Any] = (picked as? [Any]) ?? (JS.isNullish(picked) ? [] : [picked])
            for colId in list { sel = FlowRich.matrixToggle(sel, rowId, JS.str(colId), mode) }
        }
        let problem = FlowRich.matrixError(sel, rows, FlowRich.matrixRequireAll(data))
        if !problem.isEmpty { return .invalid(problem, uiState: ui(node), inCard: true) }
        let ordered = FlowRich.matrixValue(sel, rows, cols, mode)
        var value: [String: Any] = [:]
        for (k, v) in ordered { value[k] = v }
        let display = FlowRich.matrixDisplay(ordered)
        answer(state, node, ["shape": "user-matrix", "value": value, "rows": FlowRich.matrixRowAnswers(sel, rows, cols, mode), "mode": mode, "display": display, "at": Flow.iso(Date())], display, value)
        return .port("source")
    }
}

// MARK: - AI extract / AI route / KB answer

/// The text an AI or KB step reads without asking (source last_message / variable), else nil.
@MainActor
private func presetText(_ node: [String: Any], _ state: ChatState) -> String? {
    let data = FlowKit.data(node)
    let transcript = state.getTranscript().map { (by: JS.text($0["type"]), message: $0["message"] as? String) }
    let variable: Any? = FlowRich.aiSource(data) == "variable" ? lookup(state)(JS.text(data["sourceVariable"]).trimmed) : nil
    return FlowRich.aiPresetText(data, lastUserText: FlowRich.lastUserMessage(transcript), variableValue: variable)
}

/// Thinking dots for at least 500 ms around the server call.
@MainActor
private func think<T>(_ ctx: FlowContext, _ work: () async -> T) async -> T {
    let started = Flow.ms(ctx.now())
    let result = await work()
    let wait = FlowRich.aiMinThinkMs - (Flow.ms(ctx.now()) - started)
    if wait > 0 { await ctx.typing(wait) }
    return result
}

/// ai-extract-node: the visitor's reply (or the last message / a variable)
/// goes to POST ai/extract {nodeId, text}; every field is saved by name,
/// <var> = all values, <var>_missing = what is missing. ok -> "source";
/// missing or failed -> "source-missing" (or "source" when only that is
/// wired). Answer: the typed reply (#31).
public final class AiExtractNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "ai-extract-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState { .textInput(placeholder: I18n.t("composer.answer"), validation: nil, nodeId: FlowKit.id(node)) }

    @MainActor
    private func run(_ node: [String: Any], _ state: ChatState, _ text: String, asked: Bool) async -> NodeResult {
        let data = FlowKit.data(node)
        let ctx = ctxOf(node, state)
        let input = text.trimmed.jsSlice(0, FlowRich.aiMaxInput)
        let r = await think(ctx) { await richPost(ctx, "ai/extract", ["nodeId": FlowKit.id(node), "text": input], timeoutMs: FlowRich.aiClientTimeoutMs) }
        let ex = FlowRich.aiExtractResult(data, r.ok ? r.data : nil, failed: r.ok ? nil : r.code)
        var entry: [String: Any] = ["id": FlowKit.id(node), "shape": "user-ai-extract", "asked": asked, "input": input, "values": ex.values, "missing": ex.missing, "ok": ex.ok, "at": Flow.iso(Date())]
        if let e = ex.error { entry["error"] = e }
        FlowKit.pushAnswer(state, entry)
        saveVars(state, node, FlowRich.aiExtractVariables(data, ex))
        if asked { FlowKit.userSay(state, input, FlowKit.id(node)) }
        return ex.ok ? .port("source") : .port("source-missing", fallback: "source")
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        if let preset = presetText(node, state), !preset.isEmpty { return await run(node, state, preset, asked: false) }
        say(state, prompt(node, state, "<p>\(I18n.t("sdk.flow.aiExtractPrompt"))</p>"), node)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let text = FlowKit.typedText(response)
        if text.isEmpty { return .displayUI(ui(node)) }
        return await run(node, state, text, asked: true)
    }
}

/// ai-route-node: POST ai/route {nodeId, text} -> an intent. Leaves by
/// "source-" + the intent id when that edge is drawn; no match, a failure
/// or an intent with no edge -> "source-fallback" (no further fallback: no
/// edge there ends the chat). Saves <var> (the intent name, "" on no match)
/// and <var>_confidence (#31).
public final class AiRouteNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "ai-route-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState { .textInput(placeholder: I18n.t("composer.answer"), validation: nil, nodeId: FlowKit.id(node)) }

    @MainActor
    private func run(_ node: [String: Any], _ state: ChatState, _ text: String, asked: Bool) async -> NodeResult {
        let data = FlowKit.data(node)
        let ctx = ctxOf(node, state)
        let input = text.trimmed.jsSlice(0, FlowRich.aiMaxInput)
        let r = await think(ctx) { await richPost(ctx, "ai/route", ["nodeId": FlowKit.id(node), "text": input], timeoutMs: FlowRich.aiClientTimeoutMs) }
        let rt = FlowRich.aiRouteResult(r.ok ? r.data : nil, failed: r.ok ? nil : r.code)
        var entry: [String: Any] = [
            "id": FlowKit.id(node), "shape": "user-ai-route", "asked": asked, "input": input,
            "intentId": rt.intentId ?? NSNull(), "intent": rt.intent ?? NSNull(), "confidence": JS.num(rt.confidence), "fallback": rt.fallback, "at": Flow.iso(Date()),
        ]
        if let e = rt.error { entry["error"] = e }
        FlowKit.pushAnswer(state, entry)
        saveVars(state, node, FlowRich.aiRouteVariables(data, rt))
        if asked { FlowKit.userSay(state, input, FlowKit.id(node)) }
        if !rt.fallback, let id = rt.intentId, ctx.wired("source-\(id)") { return .port("source-\(id)") }
        return .port("source-fallback")
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        if let preset = presetText(node, state), !preset.isEmpty { return await run(node, state, preset, asked: false) }
        say(state, prompt(node, state, "<p>\(I18n.t("sdk.flow.aiExtractPrompt"))</p>"), node)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let text = FlowKit.typedText(response)
        if text.isEmpty { return .displayUI(ui(node)) }
        return await run(node, state, text, asked: true)
    }
}

/// kb-answer-node: POST kb/answer {nodeId, question}; the answer is shown
/// with its sources and saved (<var>, <var>_found, <var>_sources). Found ->
/// "source"; not found or failed -> notFoundMessage and "source-notfound"
/// (or "source" when only that is wired).
public final class KbAnswerNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "kb-answer-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState { .textInput(placeholder: I18n.t("sdk.flow.questionPlaceholder"), validation: nil, nodeId: FlowKit.id(node)) }

    @MainActor
    private func run(_ node: [String: Any], _ state: ChatState, _ text: String, asked: Bool) async -> NodeResult {
        let data = FlowKit.data(node)
        let ctx = ctxOf(node, state)
        let input = text.trimmed.jsSlice(0, 1000)
        let res = await think(ctx) { await richPost(ctx, "kb/answer", ["nodeId": FlowKit.id(node), "question": input], timeoutMs: FlowRich.kbClientTimeoutMs) }
        let r = FlowRich.kbResult(data, res.ok ? res.data : nil, errorCode: res.ok ? nil : res.code)
        let shown = r.found ? r.answer : FlowText.plainText(FlowRich.kbNotFoundHtml(data))
        let sources = r.found && !r.sources.isEmpty ? "\n\n" + r.sources.map { "• \($0.title)\($0.url.isEmpty ? "" : " (\($0.url))")" }.joined(separator: "\n") : ""
        FlowKit.botSay(state, text: "\(shown)\(sources)", nodeId: FlowKit.id(node), nodeType: nodeType, data: r.found ? ["sources": r.sources.map { $0.dict }] : nil)
        var entry: [String: Any] = ["id": FlowKit.id(node), "shape": "kb-answer", "asked": asked, "input": input, "found": r.found, "sources": r.sources.map { $0.dict }, "at": Flow.iso(Date())]
        if r.found { entry["answer"] = r.answer }
        if let e = r.error { entry["error"] = e }
        FlowKit.pushAnswer(state, entry)
        if asked { FlowKit.userSay(state, input, FlowKit.id(node)) }
        saveVars(state, node, FlowRich.kbVariables(data, r))
        return r.found ? .port("source") : .port("source-notfound", fallback: "source")
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        if let preset = presetText(node, state), !preset.isEmpty { return await run(node, state, preset, asked: false) }
        say(state, prompt(node, state, "<p>\(FlowI18n.t("kb.askPrompt"))</p>"), node)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let text = FlowKit.typedText(response)
        if text.isEmpty { return .displayUI(ui(node)) }
        return await run(node, state, text, asked: true)
    }
}

// MARK: - Signature

/// A typed name drawn as a signature image (SVG), sized to the name.
func typedSignatureSvg(_ name: String) -> (data: Data, width: Int, height: Int) {
    let clean = FlowRich.cleanSignatureName(name)
    let width = max(96, Int((Double(clean.jsLength) * 16 + 64).rounded()))
    let height = 114
    let escaped = clean.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\"><text x=\"50%\" y=\"62%\" text-anchor=\"middle\" font-family=\"Segoe Script, Bradley Hand, Snell Roundhand, cursive\" font-style=\"italic\" font-size=\"40\" fill=\"#111827\">\(escaped)</text></svg>"
    return (Data(svg.utf8), width, height)
}

/// signature-node: a typed name (allowTyped) or a drawing the app exports
/// as a PNG, uploaded to POST media; saves the URL and <var>_at / _method /
/// _name. Answers: ["action": "sign", "method": "typed", "name",
/// "fullName"?], ["action": "sign", "method": "drawn", "image": Data (PNG),
/// "width", "height"] (no image: nothing drawn), or a typed name.
public final class SignatureNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "signature-node" }

    private func ui(_ node: [String: Any]) -> NodeUIState { .textInput(placeholder: I18n.t("signature.namePlaceholder"), validation: nil, nodeId: FlowKit.id(node)) }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        say(state, prompt(node, state, FlowI18n.t("signature.typeToSign")), node)
        return .displayUI(ui(node))
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let cfg = FlowRich.signatureConfig(FlowKit.data(node))
        let r = JS.dict(response)
        let typed = response is String || JS.text(r["method"]) == "typed"
        let method = typed ? "typed" : "drawn"
        let name = typed ? FlowRich.cleanSignatureName((response as? String) ?? r["name"]) : ""
        let fullName = FlowRich.cleanSignatureName(r["fullName"] ?? (cfg.requireName ? name : ""))
        if cfg.requireName && !FlowRich.isSignatureName(fullName) { return .invalid(I18n.t("sdk.flow.signatureName"), uiState: ui(node), inCard: true) }
        let drawn = (r["image"] as? Data) ?? (r["dataUrl"] as? String).flatMap { u in u.components(separatedBy: ",").last.flatMap { Data(base64Encoded: $0) } }
        if method == "drawn" && drawn == nil {
            return .invalid(cfg.allowTyped ? I18n.t("sdk.flow.signatureDrawOrType") : I18n.t("sdk.flow.signatureDraw"), uiState: ui(node), inCard: true)
        }
        if method == "typed" && (!cfg.allowTyped || !FlowRich.isSignatureName(name)) { return .invalid(I18n.t("sdk.flow.signatureType"), uiState: ui(node), inCard: true) }
        let ctx = ctxOf(node, state)
        let image: (data: Data, width: Int, height: Int) = method == "typed" ? typedSignatureSvg(name) : (drawn!, Int(JS.toNumber(r["width"]).isFinite ? JS.toNumber(r["width"]) : 0), Int(JS.toNumber(r["height"]).isFinite ? JS.toNumber(r["height"]) : 0))
        let up = await ctx.upload(FlowUploadFile(name: "signature-\(Int(Flow.ms(ctx.now()))).\(method == "typed" ? "svg" : "png")", type: method == "typed" ? "image/svg+xml" : "image/png", size: Double(image.data.count), data: image.data))
        guard up.ok, let url = up.url else { return .invalid(I18n.t("sdk.flow.signatureSaveFailed"), uiState: ui(node), inCard: true) }
        let at = Flow.iso(ctx.now())
        let shownName = fullName.isEmpty ? name : fullName
        var entry: [String: Any] = ["id": FlowKit.id(node), "shape": "user-signature", "url": url, "at": at, "method": method, "width": image.width, "height": image.height]
        if !shownName.isEmpty { entry["name"] = shownName }
        FlowKit.pushAnswer(state, entry)
        FlowKit.userSay(state, "Signed: \(url)", FlowKit.id(node))
        let k = JS.text(FlowKit.data(node)["answerVariable"]).trimmed
        if !k.isEmpty {
            state.setAnswerVariable(nodeId: FlowKit.id(node), value: url)
            for (vk, vv) in FlowRich.signatureVariables(k, url: url, at: at, name: shownName, method: method) where vk != k {
                state.saveVariableByName(vk, value: vv)
            }
        }
        return .port("source")
    }
}

// MARK: - Payment

/// payment-node: POST pay/start makes a Stripe Checkout on the server. The
/// visitor opens it ("Pay now", a link button); while they are away the
/// status is peeked every 5 s (POST pay/status) and the socket's
/// "payment-status" counts too. Paid -> "source"; failed or cancelled ->
/// "source-failed" (never the paid path); timed out -> "source-timeout",
/// else "source-failed". Answers: ["action": "open"] (or the "open"
/// button), ["action": "check"], ["action": "cancel"].
public final class PaymentNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "payment-node" }

    private final class Session {
        var paymentId = ""
        var amount: Double?
        var currency: String
        var amountText = ""
        var deadline: Double
        var waiting = false
        var done = false
        var url = ""
        var timers: [FlowTimer] = []
        var off: () -> Void = {}

        init(currency: String, deadline: Double) {
            self.currency = currency
            self.deadline = deadline
        }

        func stop() {
            timers.forEach { $0.cancel() }
            timers = []
            off()
        }
    }

    private var sessions: [String: Session] = [:]

    private func ui(_ node: [String: Any], _ s: Session?) -> NodeUIState {
        let label = FlowText.plainText(FlowKit.data(node)["buttonLabel"]).nilIfEmpty ?? FlowI18n.t("pay.payNow")
        var buttons = [ButtonOption(id: "open", label: (s?.amountText).flatMap { $0.isEmpty ? nil : "\(label) · \($0)" } ?? label, url: s?.url.nilIfEmpty, action: "open")]
        if s?.waiting == true { buttons.append(ButtonOption(id: "check", label: FlowI18n.t("pay.ivePaid"))) }
        buttons.append(ButtonOption(id: "cancel", label: FlowI18n.t("common.cancel")))
        return .buttons(buttons: buttons, nodeId: FlowKit.id(node))
    }

    @MainActor
    private func finish(_ node: [String: Any], _ state: ChatState, _ s: Session, _ outcome: String, _ r: [String: Any] = [:]) -> NodeResult {
        s.done = true
        s.stop()
        sessions[FlowKit.id(node)] = nil
        let status = JS.truthy(r["status"]) ? JS.str(r["status"]) : (outcome == "paid" ? "paid" : outcome == "timeout" ? "timeout" : "cancelled")
        let receiptUrl = FlowRich.isReceiptUrl(r["receiptUrl"]) ? JS.str(r["receiptUrl"]) : ""
        if !JS.isNullish(r["amount"]), JS.toNumber(r["amount"]).isFinite { s.amount = JS.toNumber(r["amount"]) }
        if JS.truthy(r["currency"]) { s.currency = JS.str(r["currency"]).lowercased() }
        let shownAmount = s.amount.map { FlowRich.paymentAmountText($0, s.currency) } ?? s.amountText
        var entry: [String: Any] = [
            "id": FlowKit.id(node), "shape": "user-payment", "outcome": outcome, "status": status,
            "amount": s.amount.map { JS.num($0) } ?? NSNull(), "currency": s.currency, "amountText": shownAmount, "at": Flow.iso(Date()),
        ]
        if !receiptUrl.isEmpty { entry["receiptUrl"] = receiptUrl }
        if !s.paymentId.isEmpty { entry["paymentId"] = s.paymentId }
        FlowKit.pushAnswer(state, entry)
        FlowKit.userSay(state, FlowRich.paymentReplyText(outcome, shownAmount), FlowKit.id(node))
        saveVars(state, node, FlowRich.paymentVariables(JS.text(FlowKit.data(node)["answerVariable"]), status: status, amount: s.amount, currency: s.currency, receiptUrl: receiptUrl, paymentId: s.paymentId))
        if outcome == "timeout" { return .port(FlowRich.paymentTimeoutHandle, fallback: FlowRich.paymentFailedHandle) }
        return .port(FlowRich.paymentHandle(outcome))
    }

    @MainActor
    private func ask(_ ctx: FlowContext, _ node: [String: Any], _ state: ChatState, _ s: Session, _ action: String) async -> RichReply {
        await richPost(ctx, "pay/status", ["nodeId": FlowKit.id(node), "sessionId": sessionOf(state), "paymentId": s.paymentId, "action": action])
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        let ctx = ctxOf(node, state)
        say(state, prompt(node, state), node)
        let s = Session(currency: (JS.text(data["currency"]).isEmpty ? "usd" : JS.text(data["currency"])).lowercased(),
                        deadline: Flow.ms(ctx.now()) + FlowRich.paymentTimeoutMs(data))
        sessions[nodeId]?.stop()
        sessions[nodeId] = s
        let v = JS.text(data["amountVariable"]).trimmed
        var body: [String: Any] = ["nodeId": nodeId, "sessionId": sessionOf(state), "step": String(ctx.stepIndex)]
        if JS.text(data["amountMode"]) == "variable" && !v.isEmpty { body["variables"] = [v: lookup(state)(v) ?? NSNull()] }
        let res = await richPost(ctx, "pay/start", body)
        let d = JS.dict(res.data)
        if res.ok, JS.truthy(d["paymentId"]) {
            if let outcome = FlowRich.paymentOutcome(d["status"]) { return finish(node, state, s, outcome, d) }
            s.paymentId = JS.str(d["paymentId"])
            if !JS.isNullish(d["amount"]), JS.toNumber(d["amount"]).isFinite { s.amount = JS.toNumber(d["amount"]) }
            if JS.truthy(d["currency"]) { s.currency = JS.str(d["currency"]).lowercased() }
            s.amountText = s.amount.map { FlowRich.paymentAmountText($0, s.currency) } ?? ""
            if let e = d["expiresAt"] as? String, let at = Flow.parseISO(e) { s.deadline = Flow.ms(at) }
            s.url = FlowRich.isCheckoutUrl(d["url"]) ? JS.str(d["url"]) : ""
            // The server's word, from the socket.
            s.off = ctx.on("payment-status") { r in
                if !s.done, JS.text(r["paymentId"]) == s.paymentId, (JS.text(r["nodeId"]).isEmpty ? nodeId : JS.text(r["nodeId"])) == nodeId, FlowRich.paymentOutcome(r["status"]) != nil {
                    ctx.respond(["action": "__status", "status": r])
                }
            }
            // The countdown: at the deadline, ask the server once more, then time out.
            var asked = false
            s.timers.append(ctx.schedule(1000, repeats: true) { [weak self] in
                guard let self = self, !s.done, !asked, Flow.ms(ctx.now()) >= s.deadline else { return }
                asked = true
                Task { @MainActor in
                    let r = await self.ask(ctx, node, state, s, "timeout")
                    if s.done { return }
                    if r.ok, FlowRich.paymentOutcome(JS.dict(r.data)["status"]) != nil {
                        ctx.respond(["action": "__status", "status": JS.dict(r.data)])
                    } else if r.ok {
                        s.timers.append(ctx.schedule(6000) {
                            Task { @MainActor in
                                if s.done { return }
                                let r2 = await self.ask(ctx, node, state, s, "timeout")
                                if s.done { return }
                                let st: [String: Any] = r2.ok && FlowRich.paymentOutcome(JS.dict(r2.data)["status"]) != nil ? JS.dict(r2.data) : ["status": "timeout"]
                                ctx.respond(["action": "__status", "status": st])
                            }
                        })
                    } else {
                        ctx.respond(["action": "__status", "status": ["status": "timeout"]])
                    }
                }
            })
            return .displayUI(ui(node, s))
        }
        let code = res.code
        if code == "not_configured" || code == "invalid_amount" || code == "node_not_found" {
            FlowKit.botSay(state, text: FlowRich.paymentErrorText(code), nodeId: nodeId, nodeType: nodeType)
            await ctx.delay(1600)
            return finish(node, state, s, "failed", ["status": "failed"])
        }
        return .invalid(FlowRich.paymentErrorText(code), uiState: ui(node, s), inCard: true)
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let ctx = ctxOf(node, state)
        guard let s = sessions[FlowKit.id(node)], !s.done else { return await handle(node: node, state: state) }
        let r = JS.dict(response)
        let action = JS.text(r["action"]).isEmpty ? (FlowKit.pickedId(response) ?? "") : JS.text(r["action"])
        switch action {
        case "__status":
            let st = JS.dict(r["status"])
            return finish(node, state, s, FlowRich.paymentOutcome(st["status"]) ?? "timeout", st)
        case "open":
            if !s.waiting {
                s.waiting = true
                s.timers.append(ctx.schedule(FlowRich.paymentPeekMs, repeats: true) { [weak self] in
                    guard let self = self, !s.done else { return }
                    Task { @MainActor in
                        let reply = await self.ask(ctx, node, state, s, "peek")
                        if !s.done, reply.ok, FlowRich.paymentOutcome(JS.dict(reply.data)["status"]) != nil {
                            ctx.respond(["action": "__status", "status": JS.dict(reply.data)])
                        }
                    }
                })
            }
            return .displayUI(ui(node, s))
        case "check":
            let reply = await ask(ctx, node, state, s, "check")
            if reply.ok, let outcome = FlowRich.paymentOutcome(JS.dict(reply.data)["status"]) { return finish(node, state, s, outcome, JS.dict(reply.data)) }
            return .invalid(reply.ok ? FlowI18n.t("pay.notYet") : FlowRich.paymentErrorText(reply.code), uiState: ui(node, s), inCard: true)
        case "cancel":
            let reply = await ask(ctx, node, state, s, "cancel")
            var st: [String: Any] = ["status": "cancelled"]
            if reply.ok { for (k, v) in JS.dict(reply.data) { st[k] = v } }
            return finish(node, state, s, "failed", st)
        default:
            return .displayUI(ui(node, s))
        }
    }
}

/// The rich steps.
enum RichNodeHandlers {
    static var all: [NodeHandler] {
        [DynamicChoicesNodeHandler(), HiddenFieldsNodeHandler(), ConsentNodeHandler(), ProductCardNodeHandler(), SliderNodeHandler(),
         DateTimeNodeHandler(), RankingNodeHandler(), OtpNodeHandler(), AddressNodeHandler(), MatrixNodeHandler(),
         AiExtractNodeHandler(), AiRouteNodeHandler(), KbAnswerNodeHandler(), SignatureNodeHandler(), PaymentNodeHandler()]
    }
}
