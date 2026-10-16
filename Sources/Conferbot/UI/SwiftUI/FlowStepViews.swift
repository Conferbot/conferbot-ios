//
//  FlowStepViews.swift
//  Conferbot
//
//  The views for the flow steps that wait for the visitor, drawn under the
//  bot's question in the chat (the web widget's cards: ts/chat/displayStep.ts
//  and richNodesView.ts). Each sends the flow-node spec's answer shape
//  (FlowStepAnswer) to its step through ConferBot.answerStep; the visitor's
//  bubble is the step's own reply. Steps typed in the composer (ask-*, AI,
//  KB) draw nothing here, OTP / address / signature add their extras above
//  the composer.
//
//  The look is the bot's: option colour and text colour, font size and
//  option corner radius (Customizations), as the choice pills. Nothing moves
//  on its own.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Style

/// The bot's option look, for every step view: options filled in the option
/// colours (as the web's choice bubbles), Send / Submit and the stars in the
/// accent (the header colour).
@available(iOS 15.0, *)
struct StepStyle {
    /// Options: the option bubble colour and its text colour.
    let option: Color
    let optionInk: Color
    /// Send / Submit, stars, picked marks: the accent and its text colour.
    let accent: Color
    let ink: Color
    let radius: CGFloat
    let fontSize: CGFloat
    let card: Color
    let text: Color
    let muted: Color

    @MainActor static var current: StepStyle {
        let bot = ConferBot.shared
        if bot.hasServerLook {
            let look = bot.customizations
            let tokens = look.theme.tokens
            return StepStyle(
                option: Color(hex: look.optionBubbleColor),
                optionInk: Color(hex: look.optionTextColor),
                accent: Color(hex: look.accent),
                ink: look.accentInk.map { Color(hex: $0) } ?? .white,
                radius: CGFloat(look.optionRadius),
                fontSize: CGFloat(look.fontSize),
                card: tokens.map { Color(hex: $0.card) } ?? Color(UIColor.secondarySystemBackground),
                text: tokens.map { Color(hex: $0.text) } ?? .primary,
                muted: tokens.map { Color(hex: $0.muted) } ?? .secondary
            )
        }
        let accent = bot.customization?.primaryColor.map { Color($0) } ?? .blue
        return StepStyle(option: accent, optionInk: .white, accent: accent, ink: .white, radius: 10, fontSize: 15,
                         card: Color(UIColor.secondarySystemBackground), text: .primary, muted: .secondary)
    }

    var font: Font { .system(size: fontSize) }
    var bold: Font { .system(size: fontSize, weight: .semibold) }
}

/// A filled button in the option colour (Send, Continue, Submit).
@available(iOS 15.0, *)
private struct StepPrimaryButton: View {
    let title: String
    let style: StepStyle
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(style.bold)
                .foregroundColor(style.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .frame(minWidth: 96)
                .background(style.accent)
                .clipShape(RoundedRectangle(cornerRadius: style.radius))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// An option in the bot's option colours (as the choice pills); a picked
/// one is ringed in the accent and its mark filled.
@available(iOS 15.0, *)
private struct StepOptionButton: View {
    let title: String
    let style: StepStyle
    var picked = false
    var leading: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = leading { Image(systemName: icon).foregroundColor(picked ? style.accent : style.optionInk.opacity(0.6)) }
                Text(title).multilineTextAlignment(.leading)
            }
            .font(.system(size: style.fontSize, weight: .medium))
            .foregroundColor(style.optionInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(style.option)
            .clipShape(RoundedRectangle(cornerRadius: style.radius))
            .overlay(RoundedRectangle(cornerRadius: style.radius).stroke(style.accent, lineWidth: picked ? 2 : 0))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// The card a step view sits on.
@available(iOS 15.0, *)
private struct StepCard<Content: View>: View {
    let style: StepStyle
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(14)
            .frame(maxWidth: 320, alignment: .leading)
            .background(style.card)
            .clipShape(RoundedRectangle(cornerRadius: max(style.radius, 12)))
    }
}

// MARK: - The router

extension NodeUIState {
    /// The step a waiting state belongs to (nil for messages and the like).
    var stepNodeId: String? {
        switch self {
        case .textInput(_, _, let id), .singleChoice(_, let id), .multiChoice(_, let id), .buttons(_, let id), .quickReplies(_, let id),
             .cards(_, let id), .rating(_, _, let id), .opinionScale(_, _, _, _, let id), .calendar(_, let id), .fileUpload(_, _, let id),
             .payment(_, _, _, _, let id), .rich(_, _, let id):
            return id
        default:
            return nil
        }
    }
}

/// The view for the step waiting for the visitor: what `currentUIState`
/// asks for, refined by the step's type (a slider is drawn as a slider, a
/// ranking as a list to reorder...). Used by ChatView and ChatViewWithKBSheet.
@available(iOS 15.0, *)
struct FlowStepView: View {
    let uiState: NodeUIState
    @ObservedObject private var bot = ConferBot.shared

    init(uiState: NodeUIState) { self.uiState = uiState }

    var body: some View {
        let style = StepStyle.current
        HStack(alignment: .top) {
            Spacer().frame(width: 40)
            content(style)
            Spacer(minLength: 0)
        }
    }

    private func step(_ nodeId: String) -> (type: String, data: [String: Any]) {
        bot.waitingStep(nodeId) ?? ("", [:])
    }

    private func answer(_ nodeId: String) -> (Any) -> Void {
        { bot.answerStep($0, forNodeId: nodeId) }
    }

    @ViewBuilder
    private func content(_ style: StepStyle) -> some View {
        switch uiState {
        case .singleChoice(let options, let nodeId), .quickReplies(let options, let nodeId):
            ChoicePillsView(
                pills: options.map { ChoicePillsView.Pill(id: $0.id, label: $0.label) },
                selectedLabel: nil, isFrozen: false, primaryColor: style.option, ink: bot.hasServerLook ? style.optionInk : nil,
                onTap: { bot.handleChoiceSelection(optionId: $0.id, forNodeId: nodeId) }
            )
        case .buttons(let buttons, let nodeId):
            switch step(nodeId).type {
            case "consent-node":
                ConsentStepView(data: step(nodeId).data, style: style, send: answer(nodeId)).id(nodeId)
            case "payment-node":
                PaymentStepView(buttons: buttons, style: style, send: answer(nodeId))
            default:
                ChoicePillsView(
                    pills: buttons.map { ChoicePillsView.Pill(id: $0.id, label: $0.label) },
                    selectedLabel: nil, isFrozen: false, primaryColor: style.option, ink: bot.hasServerLook ? style.optionInk : nil,
                    onTap: { bot.handleButtonClick(buttonId: $0.id, forNodeId: nodeId) }
                )
            }
        case .rating(let max, let ratingStyle, let nodeId):
            RatingStepView(count: max, faces: ratingStyle == .emojis, style: style, send: answer(nodeId)).id(nodeId)
        case .opinionScale(let min, let max, let minLabel, let maxLabel, let nodeId):
            if step(nodeId).type == "slider-node" {
                SliderStepView(data: step(nodeId).data, style: style, send: answer(nodeId)).id(nodeId)
            } else {
                ScaleStepView(from: min, to: max, fromLabel: minLabel, toLabel: maxLabel, style: style, send: answer(nodeId)).id(nodeId)
            }
        case .calendar(let mode, let nodeId):
            if step(nodeId).type == "datetime-node" {
                DateTimeStepView(data: step(nodeId).data, style: style, send: answer(nodeId)).id(nodeId)
            } else {
                CalendarStepView(data: step(nodeId).data, withTime: mode == .dateTime, style: style, send: answer(nodeId)).id(nodeId)
            }
        case .fileUpload(let types, let maxSize, let nodeId):
            FileStepView(allowedTypes: types, maxBytes: maxSize, optional: FlowInputs.isOptionalUpload(step(nodeId).data) && step(nodeId).type == "ask-file-node",
                         style: style, send: answer(nodeId)).id(nodeId)
        case .multiChoice(let options, let nodeId):
            if step(nodeId).type == "ranking-node" {
                RankingStepView(items: options, submitLabel: FlowRich.submitLabel(step(nodeId).data), style: style, send: answer(nodeId)).id(nodeId)
            } else {
                CheckOptionsStepView(options: options, style: style, send: answer(nodeId)).id(nodeId)
            }
        case .cards(let cards, let nodeId):
            CardsStepView(cards: cards, style: style, send: answer(nodeId))
        case .rich(let type, let data, let nodeId) where type == "matrix-node":
            MatrixStepView(data: data, style: style, send: answer(nodeId)).id(nodeId)
        case .textInput(let placeholder, _, let nodeId):
            switch step(nodeId).type {
            case "otp-node":
                OtpStepView(codeStage: placeholder?.contains("@") == false, allowSkip: JS.truthy(step(nodeId).data["allowSkip"]), style: style, send: answer(nodeId))
            case "address-node":
                AddressStepView(allowManual: JS.bool(step(nodeId).data["allowManual"]) != false, style: style, send: answer(nodeId)).id(nodeId)
            case "signature-node":
                SignatureStepView(config: FlowRich.signatureConfig(step(nodeId).data), style: style, send: answer(nodeId)).id(nodeId)
            default:
                EmptyView()
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Rating

/// rating-choice / user-rating: 1...n stars, or the five faces. A tap answers.
@available(iOS 15.0, *)
struct RatingStepView: View {
    let count: Int
    let faces: Bool
    let style: StepStyle
    let send: (Any) -> Void
    @State private var picked = 0

    var body: some View {
        HStack(spacing: count > 7 ? 4 : 8) {
            ForEach(1...max(1, count), id: \.self) { i in
                Button {
                    picked = i
                    send(FlowStepAnswer.value(Double(i)))
                } label: {
                    if faces {
                        Text(Rating.faceValues[min(i, 5) - 1])
                            .font(.system(size: 28))
                            .opacity(picked == 0 || picked == i ? 1 : 0.4)
                            .frame(width: 40, height: 40)
                    } else {
                        Image(systemName: i <= picked ? "star.fill" : "star")
                            .font(.system(size: count > 7 ? 20 : 26))
                            .foregroundColor(style.accent)
                            .frame(width: count > 7 ? 26 : 34, height: 36)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(faces ? Rating.faceLabels[min(i, 5) - 1] : I18n.t("sdk.rating.rate", ["n": i, "max": count]))
            }
        }
        .disabled(picked != 0)
    }
}

// MARK: - Opinion scale

/// opinion-scale: from...to numbers, the end labels under them. A tap answers.
@available(iOS 15.0, *)
struct ScaleStepView: View {
    let from: Int
    let to: Int
    let fromLabel: String?
    let toLabel: String?
    let style: StepStyle
    let send: (Any) -> Void
    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 48), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(from...max(from, to), id: \.self) { n in
                    Button {
                        picked = n
                        send(FlowStepAnswer.value(Double(n)))
                    } label: {
                        Text("\(n)")
                            .font(.system(size: style.fontSize, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundColor(picked == n ? style.ink : style.optionInk)
                            .background(picked == n ? style.accent : style.option)
                            .clipShape(RoundedRectangle(cornerRadius: style.radius))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            if FlowKit.notBlank(fromLabel) || FlowKit.notBlank(toLabel) {
                HStack {
                    Text(FlowText.plainText(fromLabel))
                    Spacer()
                    Text(FlowText.plainText(toLabel))
                }
                .font(.caption)
                .foregroundColor(style.muted)
            }
        }
        .frame(maxWidth: 300)
        .disabled(picked != nil)
    }
}

// MARK: - Slider

/// slider-node: min...max on the step's grid, its unit, then Send.
@available(iOS 15.0, *)
struct SliderStepView: View {
    let config: FlowRich.SliderConfig
    let submit: String
    let style: StepStyle
    let send: (Any) -> Void
    @State private var value: Double

    init(data: [String: Any], style: StepStyle, send: @escaping (Any) -> Void) {
        let cfg = FlowRich.sliderConfig(data)
        self.config = cfg
        self.submit = FlowRich.submitLabel(data)
        self.style = style
        self.send = send
        _value = State(initialValue: cfg.start)
    }

    private var snapped: Double { FlowRich.snapToStep(value, config.min, config.max, config.step) }

    var body: some View {
        StepCard(style: style) {
            Text(FlowRich.sliderLabel(snapped, config))
                .font(.system(size: style.fontSize + 6, weight: .semibold))
                .foregroundColor(style.text)
                .frame(maxWidth: .infinity)
            Slider(value: $value, in: config.min...config.max, step: config.step)
                .tint(style.accent)
            HStack {
                Text(FlowRich.sliderLabel(config.min, config))
                Spacer()
                Text(FlowRich.sliderLabel(config.max, config))
            }
            .font(.caption)
            .foregroundColor(style.muted)
            StepPrimaryButton(title: submit, style: style) { send(FlowStepAnswer.value(snapped)) }
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Date / time

/// datetime-node: a date, a time or both, inside the step's range, then Send.
/// A day or time the step refuses is said under it (the step's own words).
@available(iOS 15.0, *)
struct DateTimeStepView: View {
    let mode: String
    let range: ClosedRange<Date>?
    let submit: String
    let style: StepStyle
    let send: (Any) -> Void
    @State private var date: Date

    init(data: [String: Any], style: StepStyle, send: @escaping (Any) -> Void) {
        let mode = FlowRich.dateMode(data)
        self.mode = mode
        self.submit = FlowRich.submitLabel(data)
        self.style = style
        self.send = send
        let zone = TimeZone.current
        func day(_ bound: Any?) -> Date? {
            guard let ymd = FlowRich.resolveDateBound(bound, today: Date(), zone: zone) else { return nil }
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.timeZone = zone
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: ymd)
        }
        let lo = mode == "time" ? nil : day(data["minDate"])
        let hi = mode == "time" ? nil : day(data["maxDate"]).map { $0.addingTimeInterval(86399) }
        let lower = lo ?? Date.distantPast
        let upper = hi ?? Date.distantFuture
        self.range = (lo != nil || hi != nil) && lower <= upper ? lower...upper : nil
        var start = Date()
        if let r = range, !r.contains(start) { start = r.lowerBound }
        _date = State(initialValue: start)
    }

    private var components: DatePickerComponents {
        mode == "time" ? .hourAndMinute : mode == "datetime" ? [.date, .hourAndMinute] : .date
    }

    @ViewBuilder private var picker: some View {
        if let r = range {
            DatePicker("", selection: $date, in: r, displayedComponents: components)
        } else {
            DatePicker("", selection: $date, displayedComponents: components)
        }
    }

    var body: some View {
        StepCard(style: style) {
            Group {
                if mode == "time" { picker.datePickerStyle(.wheel) } else { picker.datePickerStyle(.graphical) }
            }
            .labelsHidden()
            // Day and month names in the visitor's language (Core/I18n).
            .environment(\.locale, I18n.locale)
            .tint(style.accent)
            StepPrimaryButton(title: submit, style: style) {
                send(FlowStepAnswer.dateTime(FlowStepAnswer.dateTimeValue(date, mode: mode)))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Calendar

/// calendar-node: a month from today; with time selection, the day's free
/// slots (on the bot's clock, shown with the visitor's time too) - a slot
/// answers. Without it, Confirm answers with the day.
@available(iOS 15.0, *)
struct CalendarStepView: View {
    let data: [String: Any]
    let withTime: Bool
    let style: StepStyle
    let send: (Any) -> Void
    @State private var day = Calendar.current.startOfDay(for: Date())

    private var dayKey: String { FlowStepAnswer.dayKey(day) }

    private var slots: [FlowCalendar.Slot] { CalendarNodeHandler.slots(data, dayKey, now: Date()) }

    /// A day the owner closed: past days (unless shown), excluded weekdays and dates (web displayStep calendar).
    private var unavailable: Bool {
        let today = FlowStepAnswer.dayKey(Date())
        if JS.bool(data["showPastDates"]) != true && dayKey < today { return true }
        let weekday = FlowLogic.dayNames[Calendar.current.component(.weekday, from: day) - 1]
        if JS.array(data["excludeDays"]).contains(where: { JS.str($0) == weekday }) { return true }
        return JS.array(data["excludeDates"]).contains { JS.str($0) == dayKey }
    }

    /// A slot's start and end on the visitor's clock.
    private func local(_ slot: FlowCalendar.Slot) -> String {
        let zone = CalendarNodeHandler.zone(data)
        let me = TimeZone.current.identifier
        let a = FlowCalendar.hhmmInZone(FlowCalendar.wallTimeInZone(dayKey, slot.start, zone), me)
        let b = FlowCalendar.hhmmInZone(FlowCalendar.wallTimeInZone(dayKey, slot.end, zone), me)
        return "\(a) - \(b)"
    }

    var body: some View {
        StepCard(style: style) {
            Group {
                if JS.bool(data["showPastDates"]) == true {
                    DatePicker("", selection: $day, displayedComponents: .date)
                } else {
                    DatePicker("", selection: $day, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                }
            }
            .labelsHidden()
            .datePickerStyle(.graphical)
            .environment(\.locale, I18n.locale)
            .tint(style.accent)
            if unavailable {
                Text(I18n.t("sdk.calendar.dayClosed")).font(.caption).foregroundColor(style.muted)
            } else if withTime {
                let list = slots
                if list.isEmpty {
                    Text(I18n.t("sdk.calendar.noTimes")).font(.caption).foregroundColor(style.muted)
                } else {
                    Text(I18n.t("calendar.localTime")).font(.caption).foregroundColor(style.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(list, id: \.start) { slot in
                            StepOptionButton(title: local(slot), style: style) {
                                send(FlowStepAnswer.calendar(date: dayKey, slot: slot.start))
                            }
                        }
                    }
                }
            } else {
                StepPrimaryButton(title: I18n.t("action.confirm"), style: style) { send(FlowStepAnswer.calendar(date: dayKey)) }
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - File upload

/// ask-file / user-input (file): pick a file (the step checks its type and
/// size, then uploads it), or Skip when it is optional.
@available(iOS 15.0, *)
struct FileStepView: View {
    let allowedTypes: [String]
    let maxBytes: Int?
    let optional: Bool
    let style: StepStyle
    let send: (Any) -> Void
    @State private var picking = false
    @State private var sending: String?

    private var hint: String {
        var parts: [String] = []
        if let max = maxBytes, max > 0 { parts.append(I18n.t("sdk.file.upTo", ["size": ByteCountFormatter.string(fromByteCount: Int64(max), countStyle: .binary)])) }
        let types = allowedTypes.map { $0.trimmed }.filter { !$0.isEmpty }
        if !types.isEmpty { parts.append(types.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// The picker's types: extensions and media types the step allows, else anything.
    private var contentTypes: [UTType] {
        let list = allowedTypes.compactMap { raw -> UTType? in
            let t = raw.trimmed.lowercased()
            if t.isEmpty { return nil }
            if t.hasSuffix("/*") || t.hasSuffix("/") {
                switch t.components(separatedBy: "/")[0] {
                case "image": return .image
                case "video": return .movie
                case "audio": return .audio
                case "text": return .text
                default: return nil
                }
            }
            if t.contains("/") { return UTType(mimeType: t) }
            return UTType(filenameExtension: t.hasPrefix(".") ? String(t.dropFirst()) : t)
        }
        return list.isEmpty ? [.item] : list
    }

    var body: some View {
        StepCard(style: style) {
            if let name = sending {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(I18n.t("sdk.file.sendingName", ["name": name])).font(style.font).foregroundColor(style.text)
                }
            }
            HStack(spacing: 10) {
                StepPrimaryButton(title: sending == nil ? I18n.t("sdk.file.choose") : I18n.t("sdk.file.chooseAnother"), style: style) { picking = true }
                if optional {
                    StepOptionButton(title: I18n.t("common.skip"), style: style) { send(FlowStepAnswer.skip) }
                }
            }
            if !hint.isEmpty {
                Text(hint).font(.caption).foregroundColor(style.muted)
            }
        }
        .sheet(isPresented: $picking) {
            DocumentPicker(types: contentTypes) { url in
                picking = false
                guard let url = url, let copy = Self.localCopy(url) else { return }
                sending = copy.lastPathComponent
                let size = (try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let type = UTType(filenameExtension: copy.pathExtension)?.preferredMIMEType ?? ""
                send(FlowStepAnswer.file(url: copy, name: copy.lastPathComponent, type: type, size: size))
            }
        }
    }

    /// The picked file copied where the app can read it (the picker's URL is security-scoped).
    static func localCopy(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("conferbot-uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }
}

/// The system document picker (one file).
@available(iOS 15.0, *)
private struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(_ onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
    }
}

// MARK: - Check options

/// n-check-options: tick any, then Submit (the step keeps its own order).
@available(iOS 15.0, *)
struct CheckOptionsStepView: View {
    let options: [ChoiceOption]
    let style: StepStyle
    let send: (Any) -> Void
    @State private var ticked: [String] = []
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options) { o in
                let on = ticked.contains(o.id)
                StepOptionButton(title: o.label, style: style, picked: on, leading: on ? "checkmark.square.fill" : "square") {
                    if on { ticked.removeAll { $0 == o.id } } else { ticked.append(o.id) }
                }
            }
            StepPrimaryButton(title: I18n.t("common.submit"), style: style, enabled: !ticked.isEmpty) {
                sent = true
                send(FlowStepAnswer.checked(ticked))
            }
        }
        .disabled(sent)
    }
}

// MARK: - Ranking

/// ranking-node: the items in order, moved up / down, then Submit.
@available(iOS 15.0, *)
struct RankingStepView: View {
    let items: [ChoiceOption]
    let submitLabel: String
    let style: StepStyle
    let send: (Any) -> Void
    @State private var order: RankingOrder
    @State private var sent = false

    init(items: [ChoiceOption], submitLabel: String, style: StepStyle, send: @escaping (Any) -> Void) {
        self.items = items
        self.submitLabel = submitLabel
        self.style = style
        self.send = send
        _order = State(initialValue: RankingOrder(items.map { $0.id }))
    }

    private func label(_ id: String) -> String { items.first { $0.id == id }?.label ?? id }

    var body: some View {
        StepCard(style: style) {
            ForEach(Array(order.ids.enumerated()), id: \.element) { i, id in
                HStack(spacing: 10) {
                    Text("\(i + 1)")
                        .font(style.bold)
                        .foregroundColor(style.ink)
                        .frame(width: 26, height: 26)
                        .background(style.accent)
                        .clipShape(Circle())
                    Text(label(id)).font(style.font).foregroundColor(style.text)
                    Spacer(minLength: 4)
                    Button { order.move(id, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(i == 0)
                        .accessibilityLabel(I18n.t("ranking.moveUp", ["item": label(id)]))
                    Button { order.move(id, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(i == order.ids.count - 1)
                        .accessibilityLabel(I18n.t("ranking.moveDown", ["item": label(id)]))
                }
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(style.accent)
            }
            StepPrimaryButton(title: submitLabel, style: style) {
                sent = true
                send(FlowStepAnswer.ranking(order.ids))
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(sent)
    }
}

// MARK: - Cards

/// carousel / product-card: cards side by side (image, title, price and
/// description, up to three buttons). A path button answers; a link button
/// opens its page; with no path button anywhere, Continue answers.
@available(iOS 15.0, *)
struct CardsStepView: View {
    let cards: [CardData]
    let style: StepStyle
    let send: (Any) -> Void

    private var hasPath: Bool { cards.contains { $0.buttons.contains { $0.action != "link" } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(cards) { card in cardView(card) }
                }
            }
            if !hasPath {
                StepPrimaryButton(title: I18n.t("common.continue"), style: style) { send(FlowStepAnswer.cardsContinue) }
            }
        }
    }

    private func cardView(_ card: CardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = card.imageUrl, let url = URL(string: image) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { style.muted.opacity(0.15) }
                    .frame(width: 220, height: 130)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 4) {
                if !card.title.isEmpty { Text(card.title).font(style.bold).foregroundColor(style.text) }
                if let sub = card.subtitle { Text(sub).font(.system(size: style.fontSize - 1)).foregroundColor(style.muted).lineLimit(4) }
            }
            .padding(.horizontal, 10)
            VStack(spacing: 6) {
                ForEach(card.buttons) { b in
                    StepOptionButton(title: b.label, style: style, leading: b.action == "link" ? "arrow.up.right.square" : nil) {
                        if b.action == "link" {
                            if let link = b.url, let url = URL(string: link) { UIApplication.shared.open(url) }
                        } else {
                            send(FlowStepAnswer.cardButton(b.id, cardId: card.id))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding([.horizontal, .bottom], 10)
        }
        .frame(width: 220, alignment: .leading)
        .background(style.card)
        .clipShape(RoundedRectangle(cornerRadius: max(style.radius, 12)))
    }
}

// MARK: - Matrix

/// matrix-node: each row with its columns (one per row, or several), then Submit.
@available(iOS 15.0, *)
struct MatrixStepView: View {
    let rows: [FlowRich.MatrixItem]
    let columns: [FlowRich.MatrixItem]
    let submit: String
    let style: StepStyle
    let send: (Any) -> Void
    @State private var picks: MatrixPicks

    init(data: [String: Any], style: StepStyle, send: @escaping (Any) -> Void) {
        rows = FlowRich.matrixRows(data)
        columns = FlowRich.matrixColumns(data)
        submit = FlowRich.submitLabel(data)
        self.style = style
        self.send = send
        _picks = State(initialValue: MatrixPicks(mode: FlowRich.matrixMode(data)))
    }

    var body: some View {
        StepCard(style: style) {
            ForEach(rows, id: \.id) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.text).font(style.bold).foregroundColor(style.text)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(columns, id: \.id) { col in
                            let on = picks.isOn(row.id, col.id)
                            StepOptionButton(title: col.text, style: style, picked: on,
                                             leading: picks.mode == "multiple" ? (on ? "checkmark.square.fill" : "square") : (on ? "largecircle.fill.circle" : "circle")) {
                                picks.tap(row.id, col.id)
                            }
                        }
                    }
                }
            }
            StepPrimaryButton(title: submit, style: style, enabled: !picks.isEmpty) { send(FlowStepAnswer.matrix(picks)) }
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Consent

/// consent-node: the consent text (its links open) with a box to tick, then Continue.
@available(iOS 15.0, *)
struct ConsentStepView: View {
    let text: AttributedString
    let continueLabel: String
    let style: StepStyle
    let send: (Any) -> Void
    @State private var agreed = false

    init(data: [String: Any], style: StepStyle, send: @escaping (Any) -> Void) {
        let md = JS.text(data["consentText"])
        let plain = FlowRich.markdownLitePlain(md)
        text = (try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(plain.isEmpty ? I18n.t("sdk.consent.agree") : plain)
        continueLabel = FlowRich.consentContinueLabel(data)
        self.style = style
        self.send = send
    }

    var body: some View {
        StepCard(style: style) {
            HStack(alignment: .top, spacing: 10) {
                Button { agreed.toggle() } label: {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundColor(style.accent)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(agreed ? I18n.t("consent.agreed") : I18n.t("consent.declined"))
                Text(text).font(style.font).foregroundColor(style.text).tint(style.accent)
            }
            StepPrimaryButton(title: continueLabel, style: style) { send(FlowStepAnswer.consent(agreed: agreed)) }
        }
    }
}

// MARK: - Payment

/// payment-node: Pay now (opens the secure checkout), I've paid once it is
/// open, Cancel. The step watches for the payment itself.
@available(iOS 15.0, *)
struct PaymentStepView: View {
    let buttons: [ButtonOption]
    let style: StepStyle
    let send: (Any) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(buttons) { b in
                if b.id == "open" {
                    StepPrimaryButton(title: b.label, style: style, enabled: b.url != nil) {
                        if let link = b.url, let url = URL(string: link) { UIApplication.shared.open(url) }
                        send(FlowStepAnswer.payment("open"))
                    }
                } else {
                    StepOptionButton(title: b.label, style: style) { send(FlowStepAnswer.payment(b.id)) }
                }
            }
        }
    }
}

// MARK: - OTP

/// otp-node: the e-mail and the code are typed in the composer; here,
/// Resend (once a code is sent) and Skip (when the step allows it).
@available(iOS 15.0, *)
struct OtpStepView: View {
    let codeStage: Bool
    let allowSkip: Bool
    let style: StepStyle
    let send: (Any) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(codeStage ? I18n.t("sdk.otp.typeCode", ["n": FlowRich.otpLength]) : I18n.t("sdk.otp.typeEmail"))
                .font(.caption)
                .foregroundColor(style.muted)
            if codeStage || allowSkip {
                HStack(spacing: 8) {
                    if codeStage { StepOptionButton(title: I18n.t("otp.resend"), style: style) { send(FlowStepAnswer.otpResend) } }
                    if allowSkip { StepOptionButton(title: I18n.t("common.skip"), style: style) { send(FlowStepAnswer.otpSkip) } }
                }
            }
        }
    }
}

// MARK: - Address

/// address-node: search (results come back as options to pick), or the
/// address typed by hand. The street line alone can also go in the composer.
@available(iOS 15.0, *)
struct AddressStepView: View {
    let allowManual: Bool
    let style: StepStyle
    let send: (Any) -> Void
    @State private var query = ""
    @State private var manual = false
    @State private var line1 = ""
    @State private var city = ""
    @State private var region = ""
    @State private var postal = ""
    @State private var country = ""

    var body: some View {
        StepCard(style: style) {
            if !manual {
                HStack(spacing: 8) {
                    TextField(I18n.t("address.placeholder"), text: $query)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.fullStreetAddress)
                        .submitLabel(.search)
                        .onSubmit(search)
                    StepPrimaryButton(title: I18n.t("sdk.address.search"), style: style, enabled: query.trimmed.count >= 3, action: search)
                }
                if allowManual {
                    Button(I18n.t("address.manual")) { manual = true }
                        .font(.caption)
                        .foregroundColor(style.accent)
                }
            } else {
                Group {
                    TextField(I18n.t("address.street"), text: $line1).textContentType(.streetAddressLine1)
                    TextField(I18n.t("address.city"), text: $city).textContentType(.addressCity)
                    TextField(I18n.t("address.region"), text: $region).textContentType(.addressState)
                    TextField(I18n.t("address.postal"), text: $postal).textContentType(.postalCode)
                    TextField(I18n.t("address.country"), text: $country).textContentType(.countryName)
                }
                .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    StepPrimaryButton(title: I18n.t("sdk.address.save"), style: style, enabled: !line1.trimmed.isEmpty) {
                        send(FlowStepAnswer.addressManual(line1: line1, city: city, region: region, postal: postal, country: country))
                    }
                    StepOptionButton(title: I18n.t("sdk.address.searchInstead"), style: style) { manual = false }
                }
            }
        }
    }

    private func search() {
        guard query.trimmed.count >= 3 else { return }
        send(FlowStepAnswer.addressSearch(query.trimmed))
    }
}

// MARK: - Signature

/// signature-node: a box to sign in with a finger (sent as a PNG), the
/// full name when the step asks for it; or the name typed in the composer
/// when typed signatures are allowed.
@available(iOS 15.0, *)
struct SignatureStepView: View {
    let config: FlowRich.SignatureConfig
    let style: StepStyle
    let send: (Any) -> Void
    @State private var strokes: [[CGPoint]] = []
    @State private var drawing = false
    @State private var fullName = ""

    private static let size = CGSize(width: 280, height: 140)

    var body: some View {
        StepCard(style: style) {
            Canvas { ctx, _ in
                for stroke in strokes { ctx.stroke(Self.path(stroke), with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)) }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(style.muted.opacity(0.5), lineWidth: 1))
            .overlay(Group { if strokes.isEmpty { Text(I18n.t("signature.here")).font(.caption).foregroundColor(style.muted) } })
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let p = CGPoint(x: min(max(g.location.x, 0), Self.size.width), y: min(max(g.location.y, 0), Self.size.height))
                    if !drawing || strokes.isEmpty { strokes.append([p]) } else { strokes[strokes.count - 1].append(p) }
                    drawing = true
                }
                .onEnded { _ in drawing = false })
            .accessibilityLabel(I18n.t("sdk.signature.pad"))
            if config.requireName {
                TextField(I18n.t("signature.namePlaceholder"), text: $fullName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)
            }
            HStack(spacing: 8) {
                StepPrimaryButton(title: I18n.t("signature.sign"), style: style, enabled: !strokes.isEmpty) {
                    guard let png = Self.png(strokes) else { return }
                    send(FlowStepAnswer.signDrawn(png: png, width: Int(Self.size.width), height: Int(Self.size.height), fullName: config.requireName ? fullName : nil))
                }
                StepOptionButton(title: I18n.t("signature.clear"), style: style) { strokes = [] }
            }
            if config.allowTyped {
                Text(I18n.t("sdk.signature.orType")).font(.caption).foregroundColor(style.muted)
            }
        }
    }

    private static func path(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        if points.count == 1 { p.addLine(to: CGPoint(x: first.x + 0.5, y: first.y + 0.5)) }
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }

    /// The strokes as a PNG, dark ink on white.
    static func png(_ strokes: [[CGPoint]]) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1).setStroke()
            for stroke in strokes {
                let bez = UIBezierPath(cgPath: path(stroke).cgPath)
                bez.lineWidth = 2.5
                bez.lineCapStyle = .round
                bez.lineJoinStyle = .round
                bez.stroke()
            }
        }
        return image.pngData()
    }
}
