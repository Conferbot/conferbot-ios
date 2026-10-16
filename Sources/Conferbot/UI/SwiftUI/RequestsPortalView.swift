//
//  RequestsPortalView.swift
//  Conferbot
//
//  "Your requests": the screens (web conferbot-widget
//  src/ts/home/requests/view.ts, its CSS src/css/polish-requests.css;
//  ported from the React Native SDK's components/Requests/RequestsPortal.tsx).
//  Draws the portal's state (Core/Requests/RequestsPortal.swift): the list,
//  one request with its banner, the conversation and the reply box. Back
//  goes one step back.
//
//  Calm: the theme's page, card and ink (system colours without a server
//  look), one accent for the Back link, the visitor's bubbles and Send
//  (Requests.accent, the web's --cb-accent). It slides in 14pt over 220ms
//  unless Reduce Motion is on, and stays still after.
//

import SwiftUI

@available(iOS 15.0, *)
struct RequestsLook {
    let page: Color
    let card: Color
    let ink: Color
    let muted: Color
    let line: Color
    let accent: Color

    static let solved = Color(hex: "16a34a")
    static let error = Color(hex: "dc2626")

    @MainActor
    static func of(_ bot: ConferBot) -> RequestsLook {
        let accent = Color(hex: Requests.accent(bot.serverCustomizations))
        if bot.hasServerLook, let t = bot.customizations.theme.tokens {
            return RequestsLook(page: Color(hex: t.bg), card: Color(hex: t.card), ink: Color(hex: t.ink),
                                muted: Color(hex: t.muted), line: Color(hex: t.line), accent: accent)
        }
        return RequestsLook(page: Color(UIColor.systemGroupedBackground), card: Color(UIColor.secondarySystemGroupedBackground),
                            ink: Color(UIColor.label), muted: Color(UIColor.secondaryLabel),
                            line: Color(UIColor.separator), accent: accent)
    }
}

/// The "Your requests" screens over whatever they are placed in. Nothing
/// is drawn while the portal is closed. Open it with
/// `ConferBot.shared.requests.open()`; the stock chat's menu does.
@available(iOS 15.0, *)
@MainActor
public struct RequestsPortalView: View {
    @ObservedObject private var portal: RequestsPortal
    @ObservedObject private var conferBot = ConferBot.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var shown = false

    public init(portal: RequestsPortal? = nil) {
        _portal = ObservedObject(wrappedValue: portal ?? ConferBot.shared.requests.portal)
    }

    public var body: some View {
        let s = portal.state
        if s.screen != .closed {
            let look = RequestsLook.of(conferBot)
            VStack(spacing: 0) {
                bar(s, look)
                ScrollViewReader { proxy in
                    ScrollView {
                        content(s, look)
                            .padding(16)
                            .padding(.bottom, 4)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .onAppear { if s.screen == .request { proxy.scrollTo("end") } }
                    .onChange(of: (s.request?.messages.count ?? 0) + s.pending.count * 1000) { _ in
                        if portal.state.screen == .request { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
                if s.screen == .request && s.request != nil {
                    composer(s, look)
                }
            }
            .background(look.page.ignoresSafeArea())
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(x: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !reduceMotion else { return shown = true }
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) { shown = true }
            }
            .onDisappear { shown = false }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityLabel(s.title)
        }
    }

    // MARK: - The bar

    private func bar(_ s: RequestsPortalState, _ look: RequestsLook) -> some View {
        HStack(spacing: 0) {
            Button(action: { portal.back() }) {
                HStack(spacing: 2) {
                    Text("\u{2039}").font(.system(size: 22)).offset(y: -1)
                    Text(Requests.Text.back).font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(look.accent)
                .padding(.vertical, 8)
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .frame(minWidth: 72, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Requests.Text.back)
            Text(s.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(look.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Color.clear.frame(width: 72, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(look.card)
        .overlay(Rectangle().fill(look.line).frame(height: 0.5), alignment: .bottom)
    }

    // MARK: - The body

    @ViewBuilder
    private func content(_ s: RequestsPortalState, _ look: RequestsLook) -> some View {
        if s.loading {
            note(look) { noteText(Requests.Text.loading, look) }
        } else if s.failed {
            note(look) {
                noteText(Requests.Text.loadFailed, look)
                Button(Requests.Text.tryAgain) { portal.reload() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(look.accent)
                    .buttonStyle(.plain)
            }
        } else if s.screen == .list {
            let list = s.list ?? []
            if list.isEmpty {
                note(look) { noteText(Requests.Text.empty, look) }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Rectangle().fill(look.line).frame(height: 0.5) }
                        row(r, s, look)
                    }
                }
                .background(look.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(look.line, lineWidth: 0.5))
            }
        } else if let r = s.request {
            VStack(alignment: .leading, spacing: 18) {
                banner(s, look)
                VStack(spacing: 14) {
                    ForEach(r.messages) { m in bubble(m, pending: nil, look) }
                    ForEach(s.pending) { p in
                        bubble(RequestMessage(id: p.entryId, from: .you, text: p.text, at: p.at), pending: p, look)
                    }
                }
            }
        }
    }

    private func note<C: View>(_ look: RequestsLook, @ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 8) { c() }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 8)
    }

    private func noteText(_ t: String, _ look: RequestsLook) -> some View {
        Text(t).font(.system(size: 15)).foregroundColor(look.muted).multilineTextAlignment(.center).lineSpacing(4)
    }

    private func iconBox(_ state: RequestState, size: CGFloat, round: Bool, _ look: RequestsLook) -> some View {
        let tint: Color = state == .solved ? RequestsLook.solved : state == .replied ? look.accent : look.ink
        let bg: Color = state == .solved ? RequestsLook.solved.opacity(0.14) : state == .replied ? look.accent.opacity(0.1) : look.ink.opacity(0.09)
        let symbol = state == .solved ? "checkmark.circle" : state == .replied ? "bubble.left" : "clock"
        return Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: round ? size / 2 : 10))
            .accessibilityHidden(true)
    }

    private func row(_ r: RequestSummary, _ s: RequestsPortalState, _ look: RequestsLook) -> some View {
        let fresh = Requests.isNewReply(r, seen: s.seen)
        let words = Requests.rowLine(r, seen: s.seen)
        return Button(action: { Task { await portal.pick(r.id) } }) {
            HStack(spacing: 12) {
                iconBox(Requests.stateOf(r), size: 40, round: false, look)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title)
                        .font(.system(size: 15, weight: fresh ? .bold : .semibold))
                        .foregroundColor(look.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(words)
                        .font(.system(size: 13, weight: fresh ? .bold : .regular))
                        .foregroundColor(look.ink.opacity(fresh ? 1 : 0.72))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if fresh { Circle().fill(look.accent).frame(width: 9, height: 9) }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(r.title). \(words)")
    }

    private func banner(_ s: RequestsPortalState, _ look: RequestsLook) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let st = s.requestState { iconBox(st, size: 38, round: true, look) }
            VStack(alignment: .leading, spacing: 2) {
                Text(s.banner?.label ?? "").font(.system(size: 16, weight: .bold)).foregroundColor(look.ink)
                Text(s.banner?.detail ?? "").font(.system(size: 14)).foregroundColor(look.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(look.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(look.line, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    /// Text with its links underlined and tappable (view.ts appendText).
    private func linked(_ text: String) -> AttributedString {
        var out = AttributedString()
        for run in Requests.linkRuns(text) {
            var a = AttributedString(run.text)
            if let u = run.url, let url = URL(string: u) {
                a.link = url
                a.underlineStyle = .single
            }
            out += a
        }
        return out
    }

    private func bubble(_ m: RequestMessage, pending: PendingReply?, _ look: RequestsLook) -> some View {
        let you = m.from == .you
        let who = you ? Requests.Text.you : (m.name.isEmpty ? Requests.Text.supportTeam : m.name)
        let when = Requests.whenWords(m.at)
        return HStack {
            if you { Spacer(minLength: 0) }
            VStack(alignment: you ? .trailing : .leading, spacing: 4) {
                Text(when.isEmpty ? who : "\(who) · \(when)")
                    .font(.system(size: 12.5)).foregroundColor(look.muted).padding(.horizontal, 4)
                Text(linked(m.text))
                    .font(.system(size: 15))
                    .foregroundColor(you ? .white : look.ink)
                    .tint(you ? .white : look.accent)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(you ? look.accent : look.card)
                    .clipShape(RequestBubbleShape(you: you))
                    .overlay(RequestBubbleShape(you: you).stroke(you ? Color.clear : look.line, lineWidth: 0.5))
                    .opacity(pending == nil ? 1 : 0.75)
                if let p = pending {
                    switch p.status {
                    case .sending:
                        Text(Requests.Text.sending).font(.system(size: 12.5)).foregroundColor(look.muted).padding(.horizontal, 4)
                    case .locked:
                        Text(Requests.Text.locked).font(.system(size: 12.5, weight: .semibold)).foregroundColor(RequestsLook.error).padding(.horizontal, 4)
                    case .failed:
                        HStack(spacing: 4) {
                            Text(Requests.Text.notSent)
                            Button(action: { portal.retry(p.entryId) }) { Text(Requests.Text.tryAgain).underline() }.buttonStyle(.plain)
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(RequestsLook.error)
                        .padding(.horizontal, 4)
                    }
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.86 - 32, alignment: you ? .trailing : .leading)
            if !you { Spacer(minLength: 0) }
        }
    }

    // MARK: - The reply box

    private func composer(_ s: RequestsPortalState, _ look: RequestsLook) -> some View {
        let draft = Binding<String>(
            get: { portal.state.draft },
            set: { portal.setDraft(String($0.prefix(Requests.maxReply))) }
        )
        return HStack(alignment: .bottom, spacing: 8) {
            ComposerField(text: draft, placeholder: s.placeholder, placeholderColor: look.muted, textColor: look.ink,
                          fontSize: 15, maxLines: 5, horizontalPadding: 14, verticalPadding: 13)
                .focused($focused)
                .background(look.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? look.accent : look.ink.opacity(0.24), lineWidth: 1.5))
                .accessibilityLabel(Requests.Text.yourReply)
            Button(action: { portal.send() }) {
                Text(Requests.Text.send)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(look.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(s.canSend ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!s.canSend)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(look.card)
        .overlay(Rectangle().fill(look.line).frame(height: 0.5), alignment: .top)
    }
}

/// Radius 16 with the speaker's bottom corner 4.
@available(iOS 15.0, *)
private struct RequestBubbleShape: Shape {
    let you: Bool
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 16, small: CGFloat = 4
        let bl = you ? r : small, br = you ? small : r
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}
