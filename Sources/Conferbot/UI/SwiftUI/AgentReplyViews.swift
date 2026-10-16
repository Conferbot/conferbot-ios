//
//  AgentReplyViews.swift
//  Conferbot
//
//  What an AI agent's reply draws, as on the web widget: its text formatted
//  (lists, bold, links), the sources it was grounded in, the pages it points
//  to, a facts or result card, an action to confirm, and "Helpful?". Also
//  the agent's rich messages and the one-tap question chips.
//

import SwiftUI

/// An agent message's text: the markdown subset of Utils/ChatMarkdown.swift,
/// drawn as the web's agentHtml.ts: lists, headings (bold; level 3 at 1.17x,
/// 4-6 at 1.07x), quotes with a left bar, code blocks in monospace, and
/// tables in a sideways scroll (#49). `muted`: a fallback reply, italic at 85%.
@available(iOS 15.0, *)
struct ChatMarkdownText: View {
    let text: String
    let color: Color
    var muted = false

    var body: some View {
        let blocks = ChatMarkdown.parse(text)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let inlines):
                    Text(Self.attributed(inlines, italic: muted))
                case .bullet(let inlines):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}")
                        Text(Self.attributed(inlines, italic: muted))
                    }
                case .numbered(let n, let inlines):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(n).")
                        Text(Self.attributed(inlines, italic: muted))
                    }
                case .heading(let level, let inlines):
                    Text(Self.attributed(inlines, italic: muted))
                        .font(.system(size: UIFont.preferredFont(forTextStyle: .body).pointSize * (level == 3 ? 1.17 : 1.07), weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                case .quote(let inlines):
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(color.opacity(0.35)).frame(width: 3)
                        Text(Self.attributed(inlines, italic: muted)).opacity(0.85)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                case .pre(let code):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(8)
                    }
                    .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.08)))
                case .table(let head, let rows):
                    MarkdownTableView(head: head, rows: rows, color: color)
                }
            }
        }
        .foregroundColor(color)
        .tint(color)
        .opacity(muted ? 0.85 : 1)
        .fixedSize(horizontal: false, vertical: true)
    }

    static func attributed(_ inlines: [ChatMarkdown.Inline], italic: Bool = false) -> AttributedString {
        var out = AttributedString()
        for inline in inlines {
            var run = AttributedString(inline.text)
            if italic { run.inlinePresentationIntent = .emphasized }
            switch inline {
            case .bold: run.inlinePresentationIntent = italic ? [.stronglyEmphasized, .emphasized] : .stronglyEmphasized
            case .italic: run.inlinePresentationIntent = .emphasized
            case .code: run.inlinePresentationIntent = .code
            case .strike: run.strikethroughStyle = .single
            case .link(_, let url):
                run.link = URL(string: url)
                run.underlineStyle = .single
            case .plain: break
            }
            out += run
        }
        return out
    }
}

/// A markdown table in a sideways scroll: cells 5/9 padding, the head bold
/// over a 2pt rule, rows over a hairline at 18% of the text colour (web agentHtml.ts).
@available(iOS 15.0, *)
private struct MarkdownTableView: View {
    let head: [[ChatMarkdown.Inline]]
    let rows: [[[ChatMarkdown.Inline]]]
    let color: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(head, bold: true)
                Rectangle().fill(color.opacity(0.18)).frame(height: 2)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                    row(cells, bold: false)
                    if index < rows.count - 1 { Rectangle().fill(color.opacity(0.18)).frame(height: 0.5) }
                }
            }
        }
        .font(.footnote)
    }

    private func row(_ cells: [[ChatMarkdown.Inline]], bold: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(ChatMarkdownText.attributed(cell))
                    .fontWeight(bold ? .semibold : .regular)
                    .frame(minWidth: 60, alignment: .leading)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 9)
            }
        }
    }
}

/// Wraps its chips onto as many lines as they need.
@available(iOS 15.0, *)
struct ChipWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    let alignment: HorizontalAlignment
    let content: (Item) -> Content

    var body: some View {
        // A vertical stack of full-width chips: simple, readable, and never
        // clipped on narrow screens (a free-form flow layout needs iOS 16).
        VStack(alignment: alignment, spacing: 6) {
            ForEach(items, id: \.self) { content($0) }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

@available(iOS 15.0, *)
struct AgentPill: View {
    let label: String
    var accent: Color = .accentColor
    var filled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(filled ? .white : accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(filled ? accent : Color(UIColor.systemBackground)))
                .overlay(Capsule().stroke(accent, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 15.0, *)
private struct CardSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(UIColor.separator), lineWidth: 0.5))
    }
}

@available(iOS 15.0, *)
private struct CardRows: View {
    let rows: [CardRow]

    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            if index > 0 { Divider() }
            HStack {
                Text(row.label).font(.footnote).foregroundColor(.secondary)
                Spacer(minLength: 12)
                Text(row.value).font(.footnote.weight(.medium)).multilineTextAlignment(.trailing)
            }
        }
    }
}

/// Under an AI reply: sources, buttons, cards, an action to confirm, "Helpful?".
@available(iOS 15.0, *)
struct AgentReplyExtrasView: View {
    let message: AgentMessageRecord
    let accent: Color
    @ObservedObject private var conferBot = ConferBot.shared
    @Environment(\.openURL) private var openURL

    private var showHelpful: Bool {
        guard Self.rateable(message), AgentBotParser.answerFeedbackOn(conferBot.serverCustomizations) else { return false }
        // A rated answer keeps its line; only the newest unrated one asks (#43).
        return message.feedback != nil || HelpfulRow.asksFor(message.id, in: conferBot.messages, rateable: Self.rateable)
    }

    /// An AI answer stored under its server id, not a fallback or deleted.
    static func rateable(_ m: AgentMessageRecord) -> Bool {
        m.agentDetails.isAIAgent && m.extras?.isFallback != true && !m.deleted && AgentBotParser.canRate(m.id)
    }

    var body: some View {
        let extras = message.extras
        if (extras == nil || extras!.isEmpty) && !showHelpful {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array((extras?.sources ?? []).enumerated()), id: \.offset) { _, source in
                    // A help article opens in the help centre (the web's
                    // agentSources openArticle); a page in the browser.
                    let inApp = source.articleId != nil && conferBot.isHelpCentreOn
                    Button {
                        if inApp, let id = source.articleId {
                            conferBot.openHelpArticle(id: id)
                        } else if let url = source.url.flatMap(URL.init(string:)) {
                            openURL(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if source.articleId != nil {
                                Image(systemName: "doc.text").font(.caption2).foregroundColor(.secondary)
                            }
                            Text(source.title).font(.footnote.weight(.medium)).lineLimit(1).foregroundColor(.primary)
                            if inApp {
                                Text(I18n.t("kb.helpArticle") + " \u{203A}").font(.caption2).foregroundColor(.secondary)
                            } else if let url = source.url {
                                Text("\(AgentBotParser.sourceHost(url)) \u{2197}").font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.systemBackground)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(UIColor.separator), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!inApp && source.url == nil)
                }

                if let card = extras?.card {
                    CardSurface {
                        if let title = card.title { Text(title).font(.subheadline.weight(.semibold)) }
                        CardRows(rows: card.rows)
                        if let note = card.note { Text(note).font(.caption2).foregroundColor(.secondary) }
                        if let url = card.url.flatMap(URL.init(string:)) {
                            Button(I18n.t("sdk.card.learnMore") + " \u{2197}") { openURL(url) }.font(.footnote.weight(.semibold)).foregroundColor(accent)
                        }
                    }
                }

                if let result = extras?.resultCard {
                    CardSurface {
                        HStack {
                            Text(result.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            if let status = result.status {
                                Text(status).font(.caption2.weight(.semibold)).foregroundColor(toneColor(result.tone))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .overlay(Capsule().stroke(toneColor(result.tone), lineWidth: 1))
                            }
                        }
                        CardRows(rows: result.rows)
                        if let url = result.linkURL.flatMap(URL.init(string:)) {
                            Button("\(result.linkLabel ?? I18n.t("result.open")) \u{2197}") { openURL(url) }.font(.footnote.weight(.semibold)).foregroundColor(accent)
                        }
                    }
                }

                if let request = extras?.actionRequest {
                    ActionCardView(request: request, accent: accent)
                }

                if let actions = extras?.actions, !actions.isEmpty {
                    ChipWrap(items: actions.map { $0.label }, alignment: .leading) { label in
                        AgentPill(label: "\(label) \u{2197}", accent: accent) {
                            guard let action = actions.first(where: { $0.label == label }), let url = URL(string: action.url) else { return }
                            conferBot.trackConversion(goalId: "answer-action:\(action.label)", conversionEvent: AgentBotParser.conversionEvent(label: action.label, url: action.url))
                            openURL(url)
                        }
                    }
                }

                if showHelpful { HelpfulView(message: message, accent: accent) }
            }
        }
    }

    private func toneColor(_ tone: String) -> Color {
        switch tone {
        case "done": return .green
        case "moving": return .blue
        case "problem": return .red
        default: return .secondary
        }
    }
}

@available(iOS 15.0, *)
private struct ActionCardView: View {
    let request: ActionRequest
    let accent: Color
    @State private var state = "ask"

    var body: some View {
        CardSurface {
            Text(request.name).font(.subheadline.weight(.semibold))
            CardRows(rows: request.summary)
            if state == "ask" || state == "busy" {
                HStack(spacing: 8) {
                    Button { answer(true) } label: {
                        ZStack {
                            if state == "busy" { ProgressView().tint(.white) } else { Text(I18n.t("action.confirm")).font(.footnote.weight(.semibold)) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundColor(.white)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                    }
                    Button { answer(false) } label: {
                        Text(I18n.t("common.notNow")).font(.footnote)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator), lineWidth: 1))
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .disabled(state != "ask")
                .padding(.top, 4)
            } else {
                Text(state == "done" ? I18n.t("sdk.action.confirmed") : state == "declined" ? I18n.t("common.notNow") : I18n.t("sdk.action.notThroughAsk"))
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private func answer(_ accept: Bool) {
        guard state == "ask" else { return }
        state = "busy"
        ConferBot.shared.decideAction(token: request.token, accept: accept) { ok, code in
            state = ok ? (accept ? "done" : "declined") : (code == "declined" ? "declined" : "failed")
        }
    }
}

/// "Helpful?" under an AI answer (web ts/chat/answerFeedback.ts, #43): a No
/// is sent at once, then the reasons, an optional comment, "Talk to a person"
/// (only while nobody is coming or here) and "Ask another way"; the rated
/// line's thumbs change the vote. The steps are HelpfulRow's.
@available(iOS 15.0, *)
private struct HelpfulView: View {
    let message: AgentMessageRecord
    let accent: Color
    @ObservedObject private var conferBot = ConferBot.shared
    @State private var row: HelpfulRow.State
    @State private var comment = ""

    init(message: AgentMessageRecord, accent: Color) {
        self.message = message
        self.accent = accent
        _row = State(initialValue: HelpfulRow.start(message.feedback))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch row.view {
            case .ask:
                HStack(spacing: 6) {
                    Text(HelpfulText.ask).font(.caption2).foregroundColor(.secondary)
                    thumb(up: true, pressed: false)
                    thumb(up: false, pressed: false)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(HelpfulText.groupLabel)
            case .thanks:
                Text(HelpfulText.thanks).font(.caption2).foregroundColor(.secondary)
            case .down:
                downPanel
            case .rated:
                HStack(spacing: 6) {
                    thumb(up: true, pressed: row.current?.helpful == true)
                    thumb(up: false, pressed: row.current?.helpful == false)
                    Text(HelpfulRow.ratedLabel(row.current)).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    private var downPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(HelpfulText.sorry).font(.caption2).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HelpfulRow.reasons, id: \.key) { reason in
                        smallPill(reason.label, selected: row.current?.reason == reason.key) { tap(.reason(reason.key)) }
                    }
                }
            }
            if row.current?.reason != nil {
                if row.commented {
                    Text(HelpfulText.thanksComment).font(.caption2).foregroundColor(.secondary)
                } else {
                    HStack(spacing: 6) {
                        TextField(HelpfulText.comment, text: $comment)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(UIColor.separator), lineWidth: 0.5))
                            .submitLabel(.send)
                            .onSubmit { tap(.comment(comment)) }
                        smallPill(HelpfulText.sendFeedback) { tap(.comment(comment)) }
                    }
                }
            }
            HStack(spacing: 6) {
                if HandoverState.talkToPersonAllowed(conferBot.chatState.getServerRecord()) {
                    smallPill(HelpfulText.talkToPerson) { tap(.human) }
                }
                smallPill(HelpfulText.retry) { tap(.retry) }
            }
        }
    }

    private func tap(_ t: HelpfulRow.Tap) {
        let out = HelpfulRow.step(row, t)
        row = out.state
        let id = message.id
        if let fb = out.send {
            Task { @MainActor in ConferBot.shared.sendAnswerFeedback(agentMessageId: id, feedback: fb) }
        }
        if let ask = out.ask {
            Task { try? await ConferBot.shared.sendMessage(ask) }
        }
        if out.state.view == .thanks {
            DispatchQueue.main.asyncAfter(deadline: .now() + HelpfulRow.thanksSeconds) {
                row = HelpfulRow.step(row, .settle).state
            }
        }
    }

    private func thumb(up: Bool, pressed: Bool) -> some View {
        Button { tap(.vote(up)) } label: {
            Image(systemName: up ? (pressed ? "hand.thumbsup.fill" : "hand.thumbsup") : (pressed ? "hand.thumbsdown.fill" : "hand.thumbsdown"))
                .font(.caption)
                .foregroundColor(pressed ? accent : .secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(Capsule().stroke(pressed ? accent : Color(UIColor.separator), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(up ? HelpfulText.yes : HelpfulText.no)
        .accessibilityAddTraits(pressed ? .isSelected : [])
    }

    private func smallPill(_ label: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption).foregroundColor(selected ? .white : .primary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(selected ? accent : Color.clear))
                .overlay(Capsule().stroke(selected ? accent : Color(UIColor.separator), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// An agent's article, quick replies or card.
@available(iOS 15.0, *)
struct RichAgentMessageView: View {
    let record: AgentRichMessageRecord
    let accent: Color
    let bubbleColor: Color
    @ObservedObject private var conferBot = ConferBot.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch record.rich {
        case .quickReplies(let text, let options)?:
            VStack(alignment: .leading, spacing: 6) {
                let prompt = text.isEmpty ? record.text : text
                if !prompt.isEmpty {
                    Text(prompt).padding(12).background(bubbleColor).foregroundColor(.white).cornerRadius(16)
                }
                ChipWrap(items: options, alignment: .leading) { option in
                    AgentPill(label: option, accent: accent, filled: record.answered == option) {
                        guard record.answered == nil else { return }
                        let id = record.id
                        Task { @MainActor in ConferBot.shared.answerRichMessage(messageId: id, label: option) }
                    }
                    .opacity(record.answered != nil && record.answered != option ? 0.45 : 1)
                }
            }
        case .article(let articleId, let title, let snippet, let url)?:
            CardSurface {
                Text(I18n.t("kb.helpArticle")).font(.caption2).foregroundColor(.secondary)
                Text(title).font(.subheadline.weight(.semibold))
                if !snippet.isEmpty { Text(snippet).font(.footnote).foregroundColor(.secondary).lineLimit(3) }
                // In the help centre by id (the web's agentRich openArticle),
                // else the public page when there is one.
                if HelpCentre.canOpenArticle(conferBot.serverCustomizations, articleId: articleId) {
                    Button(I18n.t("sdk.kb.readArticle") + " \u{203A}") { conferBot.openHelpArticle(id: articleId) }.font(.footnote.weight(.semibold)).foregroundColor(accent)
                } else if let link = url.flatMap(URL.init(string:)) {
                    Button(I18n.t("sdk.kb.readArticle") + " \u{2197}") { openURL(link) }.font(.footnote.weight(.semibold)).foregroundColor(accent)
                }
            }
        case .card(let title, let description, let imageURL, let buttonLabel, let buttonURL)?:
            CardSurface {
                if let image = imageURL.flatMap(URL.init(string:)) {
                    AsyncImage(url: image) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() } else { Color(UIColor.tertiarySystemFill) }
                    }
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(title).font(.subheadline.weight(.semibold))
                if !description.isEmpty { Text(description).font(.footnote).foregroundColor(.secondary) }
                if let label = buttonLabel, let link = buttonURL.flatMap(URL.init(string:)) {
                    Button { openURL(link) } label: {
                        Text(label).font(.footnote.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                            .foregroundColor(.white).background(RoundedRectangle(cornerRadius: 10).fill(accent))
                    }
                    .buttonStyle(.plain)
                }
            }
        case nil:
            EmptyView()
        }
    }
}

/// One-tap questions: the agent's starters, then each answer's follow-ups.
@available(iOS 15.0, *)
struct SuggestionChipsView: View {
    let items: [String]
    let accent: Color
    let onPick: (String) -> Void

    var body: some View {
        if !items.isEmpty {
            ChipWrap(items: items, alignment: .trailing) { question in
                AgentPill(label: question, accent: accent) { onPick(question) }
            }
        }
    }
}
