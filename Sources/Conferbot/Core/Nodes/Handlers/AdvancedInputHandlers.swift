//
//  AdvancedInputHandlers.swift
//  Conferbot
//
//  calendar-node and ask-multiple-questions-node, per the flow-node spec
//  and the web widget (ts/chat/displayStep.ts calendar-node,
//  handlers/askQuestions.ts _handleAskMultipleQuestions*), as the React
//  Native SDK's AdvancedInputHandlers.ts.
//

import Foundation

// MARK: - Calendar

/// calendar-node: a month calendar on the bot's clock (data.timeZone,
/// default UTC). Without time selection the picked day is saved as the
/// visitor's long date ("Tuesday, October 20, 2026"); with it, the day's
/// weeklyHours cut into slotDuration slots, and the saved value names both
/// clocks. Moves on 400 ms after the pick. Answer: {date: "YYYY-MM-DD",
/// slot?: "HH:MM"} (slot start on the bot's clock; `time` is read the
/// same), or a picked Date / ISO text.
public final class CalendarNodeHandler: BaseNodeHandler {
    public override var nodeType: String { NodeTypes.Display.calendar }

    /// The bot's clock (data.timeZone, default UTC).
    static func zone(_ data: [String: Any]) -> String {
        let z = JS.text(data["timeZone"])
        return z.isEmpty ? "UTC" : z
    }

    private func zone(_ data: [String: Any]) -> String { Self.zone(data) }

    private func slotsFor(_ data: [String: Any], _ dayKey: String, _ now: Date) -> [FlowCalendar.Slot] { Self.slots(data, dayKey, now: now) }

    /// A day's bookable slots on the bot's clock (the chat's calendar view lists these).
    static func slots(_ data: [String: Any], _ dayKey: String, now: Date) -> [FlowCalendar.Slot] {
        let z = zone(data)
        let dayName = FlowCalendar.dayNameInZone(FlowCalendar.noonInZone(dayKey, z), z)
        guard let schedule = JS.dicts(data["weeklyHours"]).first(where: { JS.text($0["dayName"]) == dayName }), JS.truthy(schedule["available"]) else { return [] }
        return FlowCalendar.futureSlots(FlowCalendar.expandSlots(schedule["slots"], data["slotDuration"], data["bufferMinutes"]), dayKey, z, now: now)
    }

    private func ui(_ node: [String: Any]) -> NodeUIState {
        .calendar(mode: JS.truthy(FlowKit.data(node)["showTimeSelection"]) ? .dateTime : .date, nodeId: FlowKit.id(node))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        FlowKit.botSay(state, html: FlowKit.filledHtml(state, FlowKit.data(node)["calendarPrompt"]), nodeId: FlowKit.id(node), nodeType: nodeType)
        return .displayUI(ui(node))
    }

    /// A picked day (and slot) from the answer.
    private func picked(_ response: Any, _ botZone: String) -> (date: String, slot: String) {
        if let d = response as? Date {
            return (FlowCalendar.dayKeyInZone(d, botZone), FlowCalendar.hhmmInZone(d, botZone))
        }
        if let s = response as? String {
            if let d = Flow.parseISO(s) { return (FlowCalendar.dayKeyInZone(d, botZone), FlowCalendar.hhmmInZone(d, botZone)) }
            return (s.jsSlice(0, 10), "")
        }
        let r = JS.dict(response)
        let date = JS.text(JS.truthy(r["date"]) ? r["date"] : r["selectedDate"]).jsSlice(0, 10)
        let slot = JS.text(JS.truthy(r["slot"]) ? r["slot"] : r["time"]).trimmed
        return (date, slot)
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let data = FlowKit.data(node)
        let nodeId = FlowKit.id(node)
        let ctx = ctxOf(node, state)
        let botZone = zone(data)
        let visitorZone = ctx.visitorTimeZone
        let (dateString, slotStart) = picked(response, botZone)
        guard dateString.matches("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") else { return .displayUI(ui(node)) }

        let value: String
        let record: [String: Any]
        if !JS.truthy(data["showTimeSelection"]) {
            let botDate = FlowCalendar.noonInZone(dateString, botZone)
            let visitorDate = FlowCalendar.noonInZone(dateString, visitorZone)
            let date = FlowCalendar.longDate(botDate, botZone)
            let localDate = FlowCalendar.longDate(visitorDate, visitorZone, FlowCalendar.visitorLocale())
            let shown = localDate.isEmpty ? date : localDate
            record = ["date": shown, "selectedDate": dateString, "botTimeZone": botZone, "visitorTimeZone": visitorZone, "showTimeSelection": false]
            value = shown
            FlowKit.userSay(state, value, nodeId)
        } else {
            guard let slot = slotsFor(data, dateString, ctx.now()).first(where: { $0.start == slotStart }) else { return .displayUI(ui(node)) }
            let botDate = FlowCalendar.noonInZone(dateString, botZone)
            let visitorDate = FlowCalendar.noonInZone(FlowCalendar.dayKeyInZone(botDate, botZone), visitorZone)
            let date = FlowCalendar.longDate(botDate, botZone)
            let localDate = FlowCalendar.longDate(visitorDate, visitorZone, FlowCalendar.visitorLocale())
            let visitorStart = FlowCalendar.hhmmInZone(FlowCalendar.wallTimeInZone(dateString, slot.start, botZone), visitorZone)
            let visitorEnd = FlowCalendar.hhmmInZone(FlowCalendar.wallTimeInZone(dateString, slot.end, botZone), visitorZone)
            let timeSlotSelected = FlowCalendar.slotLabel(slot)
            let visitorTime = "\(visitorStart) - \(visitorEnd)"
            let shown = localDate.isEmpty ? date : localDate
            record = [
                "date": shown, "selectedDate": Flow.iso(botDate), "botTimeZone": botZone, "visitorTimeZone": visitorZone,
                "showTimeSelection": true, "timeSlotSelected": timeSlotSelected, "visitorTime": visitorTime,
            ]
            value = "\(shown) \(visitorTime) (Visitor's local time) / \(timeSlotSelected) (Bot's time)"
            FlowKit.userSay(state, "\(localDate), \(visitorTime) \(I18n.t("calendar.localTime"))", nodeId)
            ctx.emit("calendar-slot-selection-record", [
                "visitorId": state.visitorId ?? (state.getVariable(name: "_visitorId") as? String) ?? state.sessionId,
                "chatbotId": state.botId,
                "nodeId": nodeId,
                "selectedDate": Flow.iso(botDate),
                "botTimeZone": botZone,
                "visitorTimeZone": visitorZone,
                "timeSlotSelected": timeSlotSelected,
                "visitorTime": visitorTime,
            ])
        }
        FlowKit.pushAnswer(state, ["id": nodeId, "shape": "user-calendar-selection", "data": record])
        state.setAnswerVariable(nodeId: nodeId, value: value)
        return .delayedProceed(0.4, nil)
    }
}

// MARK: - Multiple questions

/// ask-multiple-questions-node: data.message, then each of data.questions in
/// turn after 2000 ms of typing. An "email" answer is checked as an e-mail,
/// "phone" / "mobile" as a phone (saved normalised). Each answer fills the
/// variable registered as nodeId + index and is recorded as
/// "<nodeId>:<questionId>". After the last one, the first edge.
public final class MultipleQuestionsNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "ask-multiple-questions-node" }

    private func questions(_ node: [String: Any]) -> [[String: Any]] { JS.dicts(FlowKit.data(node)["questions"]) }

    private func indexKey(_ node: [String: Any]) -> String { "_mq_\(FlowKit.id(node))" }

    private func ui(_ node: [String: Any], _ index: Int) -> NodeUIState {
        let qs = questions(node)
        let q = index < qs.count ? qs[index] : [:]
        let variable = JS.text(q["answerVariable"]).lowercased()
        let validation: InputValidation? = nil
        _ = variable
        return .textInput(placeholder: I18n.t("composer.answer"), validation: validation, nodeId: FlowKit.id(node))
    }

    /// Ask question `index` (2000 ms of typing first).
    @MainActor
    private func ask(_ node: [String: Any], _ state: ChatState, _ index: Int) async -> NodeResult {
        let nodeId = FlowKit.id(node)
        let qs = questions(node)
        let q = index < qs.count ? qs[index] : [:]
        await ctxOf(node, state).typing(2000)
        state.setVariable(name: indexKey(node), value: index)
        let label = qs.count > 1 ? I18n.t("node.questionOf", ["n": index + 1, "total": qs.count]) + "\n" : ""
        FlowKit.botSay(state, text: "\(label)\(FlowKit.shownText(state, q["questionText"]))", nodeId: nodeId, nodeType: nodeType)
        let qid = JS.isNullish(q["id"]) ? String(index) : JS.str(q["id"])
        var entry: [String: Any] = [
            "_id": "\(nodeId):\(qid)", "id": "\(nodeId):\(qid)", "nodeId": nodeId, "questionId": qid,
            "shape": "ask-multiple-questions-question", "type": "ask-multiple-questions-question",
            "renderedText": FlowText.fillVariables(q["questionText"], { state.lookupVariable($0) }), "time": Flow.iso(Date()),
        ]
        if let v = q["answerVariable"] { entry["answerVariable"] = v }
        if let v = q["questionText"] { entry["questionText"] = v }
        state.addRecord(entry)
        return .displayUI(ui(node, index))
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let nodeId = FlowKit.id(node)
        let html = FlowKit.filledHtml(state, FlowKit.data(node)["message"])
        if !FlowText.bubbleText(html).isEmpty { FlowKit.botSay(state, html: html, nodeId: nodeId, nodeType: nodeType) }
        ctxOf(node, state).shown()
        if questions(node).isEmpty { return .next }
        return await ask(node, state, 0)
    }

    public override func handleResponse(_ response: Any, node: [String: Any], state: ChatState) async -> NodeResult? {
        let nodeId = FlowKit.id(node)
        let data = FlowKit.data(node)
        let qs = questions(node)
        let index = Int(JS.toNumber(state.getVariable(name: indexKey(node)) ?? 0))
        let q = index < qs.count ? qs[index] : [:]
        var value = FlowKit.typedText(response)
        if value.isEmpty { return .displayUI(ui(node, index)) }
        let variable = JS.text(q["answerVariable"])
        if variable == "email" && !FlowInputs.isValidEmail(value) {
            return .invalid(FlowInputs.ownerTextOr(data["incorrectEmailResponse"], FlowInputs.EN.emailInvalid, ["Please enter a valid email"]), uiState: ui(node, index), inCard: false)
        }
        if variable == "mobile" || variable == "phone" {
            if !FlowInputs.isValidPhone(value) { return .invalid(FlowInputs.phoneErrorText(data), uiState: ui(node, index), inCard: false) }
            value = FlowInputs.normalizePhone(value)
        }
        if variable == "name" { state.updateMetadata(key: "name", value: value) }
        if variable == "email" { state.updateMetadata(key: "email", value: value) }
        if variable == "phone" || variable == "mobile" { state.updateMetadata(key: "phone", value: value) }

        let qid = JS.isNullish(q["id"]) ? String(index) : JS.str(q["id"])
        var entry: [String: Any] = [
            "id": "\(nodeId):\(qid)", "nodeId": nodeId, "questionId": qid,
            "shape": "user-ask-multiple-questions-question-response", "type": "user-ask-multiple-questions-question-response", "text": value,
        ]
        if let v = q["answerVariable"] { entry["answerVariable"] = v }
        FlowKit.pushAnswer(state, entry)
        state.setAnswerVariable(nodeId: "\(nodeId)\(index)", value: value)
        FlowKit.userSay(state, value, nodeId)

        if index + 1 < qs.count { return await ask(node, state, index + 1) }
        state.deleteVariable(name: indexKey(node))
        return .next
    }
}

/// calendar-node and ask-multiple-questions-node.
enum AdvancedInputHandlers {
    static var all: [NodeHandler] { [CalendarNodeHandler(), MultipleQuestionsNodeHandler()] }
}
