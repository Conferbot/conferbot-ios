//
//  HomeScreenView.swift
//  Conferbot
//
//  The home screen (web conferbot-widget src/ts/home/firstImpression.ts
//  enhanceHome, askBox.ts, trust.ts, requests/card.ts over
//  templates/shared.ts generateInitialPage; CSS src/css/polish.css "Home",
//  polish-home.css, polish-requests.css "Home card"; ported from the React
//  Native SDK's components/Home/HomeScreen.tsx). Draws `Home.Model` and
//  sends each tap where the web sends it:
//
//    "Talk to us" and a starter question     the conversation (asking it)
//    "Ask anything" rows                     ask the agent, open an article, or the chat
//    "Pick up where you left off"            the conversation, or ask again
//    "Your requests" rows / See all (n)      the requests portal over the home
//    a recent article / a topic / See all    the article over the home / the help centre
//    the cross                               closes the chat
//
//  Calm, as the web: the brand band, white (theme) cards, one accent; each
//  part rises 8pt into place once (the web's cb-rise), none with Reduce
//  Motion, and it stays still after.
//

import SwiftUI

@available(iOS 15.0, *)
@MainActor
public struct HomeScreenView: View {
    @ObservedObject private var conferBot = ConferBot.shared
    @ObservedObject private var home = ConferBot.shared.home
    @ObservedObject private var requests = ConferBot.shared.requests
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var helpQuery = ""
    @State private var remote: Home.RemoteHits?
    @State private var talkFrame: CGRect = .zero
    @State private var risen = false
    @State private var logosShown = false
    @FocusState private var askFocused: Bool
    @FocusState private var helpFocused: Bool

    /// The cross at the top: close the chat (nil: no cross).
    private let onClose: (() -> Void)?
    /// An article tapped on the home: shown over it.
    private let onArticle: (String) -> Void
    /// The app's own mascot spot, above the greeting, given the owner's mascot (look and colour).
    /// The web's home draws none, so nothing is drawn without it.
    private let mascot: ((Home.Mascot) -> AnyView)?

    public init(onClose: (() -> Void)? = nil, onArticle: ((String) -> Void)? = nil, mascot: AnyView? = nil) {
        self.onClose = onClose
        self.onArticle = onArticle ?? { id in _ = ConferBot.shared.openHelpArticle(id: id) }
        self.mascot = mascot.map { v in { _ in v } }
    }

    /// The mascot spot drawn from the owner's mascot, e.g.
    /// `HomeScreenView(renderMascot: { AnyView(MascotView($0, size: 72, mood: "wave")) })`.
    public init(onClose: (() -> Void)? = nil, onArticle: ((String) -> Void)? = nil, renderMascot: @escaping (Home.Mascot) -> AnyView) {
        self.onClose = onClose
        self.onArticle = onArticle ?? { id in _ = ConferBot.shared.openHelpArticle(id: id) }
        self.mascot = renderMascot
    }

    public var body: some View {
        if let m = home.model() {
            screen(m)
        }
    }

    // MARK: - Look

    private var pal: Home.Palette { Home.palette(conferBot.hasServerLook ? conferBot.customizations.theme.tokens : nil) }

    private func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let family = conferBot.customization?.fontFamily, !family.isEmpty { return .custom(family, size: size).weight(weight) }
        return .system(size: size, weight: weight)
    }

    private func color(_ hex: String) -> Color { Color(hex: hex) }
    /// CSS color-mix: `p` (0-1) of `top` over `under`.
    private func mix(_ under: String, _ top: String, _ p: Double) -> Color { Color(hex: MascotArt.mixColor(top, p * 100, under)) }

    private func gradient(_ m: Home.Model, angle: Double) -> LinearGradient {
        let r = angle * .pi / 180
        let x = sin(r) / 2, y = -cos(r) / 2
        return LinearGradient(colors: [color(m.band[0]), color(m.band[1])],
                              startPoint: UnitPoint(x: 0.5 - x, y: 0.5 - y), endPoint: UnitPoint(x: 0.5 + x, y: 0.5 + y))
    }

    private struct Card: ViewModifier {
        let fill: Color
        let padding: CGFloat
        let shadow: Double
        func body(content: Content) -> some View {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
                .shadow(color: Color(hex: "0f172a").opacity(shadow), radius: 7, x: 0, y: 8)
        }
    }

    /// The web's cb-rise: up 8pt and in, once, after `delay`.
    private struct Rise: ViewModifier {
        let risen: Bool
        let still: Bool
        let delay: Double
        func body(content: Content) -> some View {
            content
                .opacity(still || risen ? 1 : 0)
                .offset(y: still || risen ? 0 : 8)
                .animation(still ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.45).delay(delay), value: risen)
        }
    }

    private func rise(_ v: some View, _ delay: Double) -> some View {
        v.modifier(Rise(risen: risen, still: reduceMotion, delay: delay))
    }

    // MARK: - The screen

    private func screen(_ m: Home.Model) -> some View {
        let ink = m.light ? color("0f172a") : Color.white
        let asking = m.ask != nil && !query.trimmingCharacters(in: .whitespaces).isEmpty
        let shown = m.order.filter { !(asking && Home.hiddenWhileAsking.contains($0)) }
        // The band runs down to the middle of "Talk to us" (at most 72 into it).
        let band = asking || talkFrame == .zero ? 250 : talkFrame.minY + min(72, talkFrame.height / 2)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                rise(header(m, ink), 0.1)
                rise(Text(m.description)
                    .font(font(14.5))
                    .foregroundColor(ink.opacity(0.92))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16), 0.16)
                ForEach(shown, id: \.self) { part in
                    rise(section(part, m, ink), part == .help || part == .trust ? 0.3 : 0.22)
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .background(alignment: .top) {
                gradient(m, angle: 150).frame(height: max(0, band)).allowsHitTesting(false)
            }
            .coordinateSpace(name: "cb-home")
        }
        .background(color(pal.page).ignoresSafeArea())
        .onPreferenceChange(TalkFrameKey.self) { talkFrame = $0 }
        .onAppear { DispatchQueue.main.async { risen = true } }
        // The server's matches inside article text, 280ms after the last key (askBox.ts askRemote).
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard m.ask != nil, let key = Home.remoteQueryFor(q, articles: home.rawArticles) else { return }
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            let hits = await home.searchArticleText(key)
            if !Task.isCancelled { remote = Home.RemoteHits(query: q.lowercased(), hits: hits) }
        }
        .accessibilityIdentifier("cb-home")
    }

    private func header(_ m: Home.Model, _ ink: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                if let b = m.brand {
                    HStack(spacing: 10) {
                        if let url = URL(string: b.logo) {
                            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        }
                        if !b.name.isEmpty {
                            Text(b.name).font(font(15, .semibold)).foregroundColor(ink).lineLimit(1)
                        }
                    }
                    .padding(.bottom, 14)
                }
                if let mascot = mascot { mascot(m.mascot) }
                Text(m.hello)
                    .font(font(13.5, .semibold))
                    .foregroundColor(ink.opacity(0.82))
                if !m.title.isEmpty {
                    Text(m.title)
                        .font(font(24, .bold))
                        .foregroundColor(ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ink)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Home.Text.close)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func section(_ part: Home.Section, _ m: Home.Model, _ ink: Color) -> some View {
        switch part {
        case .ask: askCard(m)
        case .resume: resumeCard(m)
        case .requests: requestsCard(m)
        case .talk: talkCard(m, ink)
        case .help: helpCard(m)
        case .trust: trustRow(m)
        }
    }

    // MARK: - Pieces

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(font(11.5, .semibold))
            .tracking(0.46)
            .foregroundColor(color(pal.muted))
            .padding(.top, 8)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
    }

    private func seeAll(_ text: String, _ accent: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(font(12.5, .semibold)).foregroundColor(color(accent))
                .padding(.vertical, 4).padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }

    private func iconBox(_ symbol: String, _ accent: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(mix(pal.card, accent, 0.12))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundColor(color(accent)))
    }

    private func runs(_ list: [Home.TextRun], _ accent: String) -> SwiftUI.Text {
        list.reduce(SwiftUI.Text("")) { acc, r in
            // A mark as a stronger weight in the accent (Text has no background on iOS 15).
            acc + (r.mark ? SwiftUI.Text(r.text).foregroundColor(color(accent)) : SwiftUI.Text(r.text))
        }
    }

    /// A row of a card (polish.css .recent-articles .article-card / .cb-home-row).
    private func row<Lead: View, Trail: View>(lead: Lead, title: SwiftUI.Text, sub: String?, lines: Int = 1, weight: Font.Weight = .semibold,
                                              subColor: Color? = nil, subWeight: Font.Weight = .regular, chevron: Bool = true,
                                              trail: Trail, a11y: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                lead
                VStack(alignment: .leading, spacing: 2) {
                    title.font(font(14, weight)).foregroundColor(color(pal.ink)).lineLimit(lines).multilineTextAlignment(.leading)
                    if let sub = sub, !sub.isEmpty {
                        Text(sub).font(font(12.5, subWeight)).foregroundColor(subColor ?? color(pal.muted)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trail
                if chevron {
                    Text("\u{203A}").font(.system(size: 18)).foregroundColor(mix(pal.card, pal.muted, 0.8))
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y ?? "")
    }

    private func searchBox(_ text: Binding<String>, _ placeholder: String, _ a11y: String, focused: FocusState<Bool>.Binding,
                           isFocused: Bool, accent: String, send: Bool, onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundColor(color(pal.muted))
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(color(pal.muted)))
                .font(font(14.5))
                .foregroundColor(color(pal.ink))
                .focused(focused)
                .submitLabel(send ? .send : .search)
                .disableAutocorrection(true)
                .onSubmit(onSubmit)
                .accessibilityLabel(a11y)
                .onChange(of: text.wrappedValue) { v in if v.count > 300 { text.wrappedValue = String(v.prefix(300)) } }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color(isFocused ? pal.card : pal.soft)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isFocused ? mix(pal.card, accent, 0.35) : .clear, lineWidth: 2))
        .padding(4)
    }

    // MARK: - "Ask anything"

    private func runAsk(_ r: Home.AskRow?) {
        switch r {
        case .ask(let q, _)?: home.showChat(q)
        case .article(let id, _, _)?: onArticle(id)
        case .chat?: home.showChat()
        default: break
        }
    }

    private func askCard(_ m: Home.Model) -> some View {
        let ask = m.ask!
        let rows = Home.askRows(query, agentName: ask.agentName, articles: m.articles, remote: remote)
        let first = Home.askDefault(rows)
        return VStack(alignment: .leading, spacing: 0) {
            searchBox($query, ask.placeholder, ask.label, focused: $askFocused, isFocused: askFocused, accent: m.accent,
                      send: ask.agentName != nil) { runAsk(Home.askDefault(rows)) }
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.key) { r in
                        askRow(r, isFirst: r == first, m.accent)
                    }
                }
                .padding(.top, 4)
            }
        }
        .modifier(Card(fill: color(pal.card), padding: 6, shadow: 0.09))
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func askRow(_ r: Home.AskRow, isFirst: Bool, _ accent: String) -> some View {
        switch r {
        case .label(let text):
            label(text)
        case .none(let text):
            Text(text).font(font(13.5)).foregroundColor(color(pal.muted)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.top, 12).padding(.horizontal, 10).padding(.bottom, 4)
        case .ask(let q, let sub):
            // "Ask “q”" / "„q“ fragen": the query bold where the language puts it.
            let (before, after) = Home.Text.askQueryParts
            row(lead: iconBox("sparkles", accent), title: SwiftUI.Text(before) + SwiftUI.Text("\u{201C}\(q)\u{201D}").bold() + SwiftUI.Text(after),
                sub: sub, lines: 2, weight: .medium, chevron: false, trail: EmptyView(), a11y: I18n.t("home.askQuery", ["query": q])) { runAsk(r) }
                .background(isFirst ? RoundedRectangle(cornerRadius: 12).fill(mix(pal.card, accent, 0.08)) : nil)
        case .article(_, let title, let sub):
            row(lead: iconBox("doc.text", accent), title: runs(title, accent), sub: sub, chevron: false, trail: EmptyView(),
                a11y: title.map { $0.text }.joined()) { runAsk(r) }
                .background(isFirst ? RoundedRectangle(cornerRadius: 12).fill(mix(pal.card, accent, 0.08)) : nil)
        case .chat(let title, let sub):
            row(lead: iconBox("bubble.left", accent), title: SwiftUI.Text(title), sub: sub, chevron: false, trail: EmptyView(), a11y: title) { runAsk(r) }
                .background(isFirst ? RoundedRectangle(cornerRadius: 12).fill(mix(pal.card, accent, 0.08)) : nil)
        }
    }

    // MARK: - "Pick up where you left off"

    private func resumeCard(_ m: Home.Model) -> some View {
        let r = m.resume!
        return VStack(alignment: .leading, spacing: 0) {
            label(Home.Text.resume).padding(.top, -2)
            // The conversation is on the device: open it. Otherwise ask again.
            row(lead: iconBox("clock.arrow.circlepath", m.accent), title: SwiftUI.Text(r.topic), sub: r.line, lines: 2, trail: EmptyView(),
                a11y: "\(r.topic). \(r.line)") { home.showChat(r.resumable ? nil : r.topic) }
        }
        .modifier(Card(fill: color(pal.card), padding: 6, shadow: 0.09))
        .padding(.bottom, 14)
    }

    // MARK: - "Your requests"

    private func requestsCard(_ m: Home.Model) -> some View {
        let card = m.requests!
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                label(Home.Text.requestsTitle)
                Spacer()
                if let all = card.seeAll { seeAll(all, m.accent) { requests.open() }.padding(.trailing, 6) }
            }
            ForEach(card.rows, id: \.id) { r in
                let tint: Color = r.state == .solved ? RequestsLook.solved : r.state == .replied ? color(m.accent) : color(pal.ink)
                let bg: Color = r.state == .solved ? RequestsLook.solved.opacity(0.14) : r.state == .replied ? mix(pal.card, m.accent, 0.1) : mix(pal.card, pal.ink, 0.09)
                let symbol = r.state == .solved ? "checkmark.circle" : r.state == .replied ? "bubble.left" : "clock"
                row(lead: RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg).frame(width: 40, height: 40)
                        .overlay(Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundColor(tint)),
                    title: SwiftUI.Text(r.title), sub: r.line, lines: 2, weight: r.fresh ? .bold : .semibold,
                    subColor: color(pal.ink).opacity(r.fresh ? 1 : 0.72), subWeight: r.fresh ? .bold : .regular, chevron: !r.fresh,
                    trail: Group { if r.fresh { Circle().fill(color(m.accent)).frame(width: 9, height: 9) } },
                    a11y: "\(r.title). \(r.line)") { requests.open(requestId: r.id) }
            }
        }
        .modifier(Card(fill: color(pal.card), padding: 6, shadow: 0.09))
        .overlay(card.fresh ? RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(mix(pal.card, m.accent, 0.45), lineWidth: 1.5) : nil)
        .padding(card.fresh ? .bottom : .top, 14)
    }

    // MARK: - "Talk to us"

    private func talkCard(_ m: Home.Model, _ ink: Color) -> some View {
        let t = m.talk
        return VStack(alignment: .leading, spacing: 0) {
            if !m.message.isEmpty {
                Text(m.message).font(font(14)).foregroundColor(ink).padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        AsyncImage(url: URL(string: t.avatar)) { $0.resizable().scaledToFill() } placeholder: { mix(pal.card, pal.ink, 0.06) }
                            .frame(width: 46, height: 46)
                            .clipShape(Circle())
                        if t.dot {
                            Circle().fill(Color(hex: "22c55e"))
                                .frame(width: 11, height: 11)
                                .overlay(Circle().stroke(color(pal.card), lineWidth: 2.5))
                                .offset(x: 34, y: 34)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(font(15, .bold)).foregroundColor(color(pal.ink)).lineLimit(1)
                        if let tagline = t.tagline {
                            Text(tagline).font(font(13, .medium)).foregroundColor(color(pal.muted))
                        }
                        if let status = t.status {
                            Text(status).font(font(13, .medium)).foregroundColor(color(pal.muted)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !t.faces.isEmpty {
                        HStack(spacing: -7) {
                            ForEach(t.faces, id: \.self) { src in
                                AsyncImage(url: URL(string: src)) { $0.resizable().scaledToFill() } placeholder: { Color(hex: "e2e8f0") }
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(color(pal.card), lineWidth: 2))
                            }
                        }
                        .padding(.leading, 10)
                        .accessibilityElement()
                        .accessibilityLabel(Home.Text.ourTeam)
                    }
                }
                .padding(.bottom, 16)

                Button(action: { home.showChat() }) {
                    HStack(spacing: 8) {
                        Text(t.button).font(font(14.5, .semibold)).tracking(0.15)
                        Image(systemName: "paperplane.fill").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(gradient(m, angle: 135).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !t.starters.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(t.starters.enumerated()), id: \.offset) { _, s in
                            Button(action: { home.showChat(s) }) {
                                Text(s).font(font(13, .semibold)).foregroundColor(color(m.accent)).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8).padding(.horizontal, 12)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(mix(pal.card, m.accent, 0.07)))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(mix(pal.card, m.accent, 0.22), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 12)
                    .overlay(Rectangle().fill(color(pal.line)).frame(height: 1), alignment: .top)
                    .padding(.top, 12)
                }

                if let r = t.rating {
                    HStack(spacing: 5) {
                        stars(fill: r.fill)
                        Text(r.average).font(font(12.5, .medium)).foregroundColor(mix(pal.muted, pal.ink, 0.5))
                        Text("\u{00B7}").font(font(12.5)).foregroundColor(color(pal.muted).opacity(0.7))
                        Text(r.count).font(font(12.5)).foregroundColor(color(pal.muted))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .accessibilityElement()
                    .accessibilityLabel(r.label)
                }
            }
            .modifier(Card(fill: color(pal.card), padding: 16, shadow: 0.12))
            .background(GeometryReader { g in Color.clear.preference(key: TalkFrameKey.self, value: g.frame(in: .named("cb-home"))) })
        }
    }

    private func stars(fill: Double) -> some View {
        let row = HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { _ in Image(systemName: "star.fill").font(.system(size: 11)).foregroundColor(Color(hex: "f5b544")) }
        }
        return row.opacity(0.3).overlay(
            GeometryReader { g in
                row.frame(width: g.size.width, alignment: .leading)
                    .mask(Rectangle().frame(width: g.size.width * CGFloat(fill / 100)).frame(maxWidth: .infinity, alignment: .leading))
            }
        )
    }

    // MARK: - The help card

    private func helpCard(_ m: Home.Model) -> some View {
        let h = m.help!
        let found = h.search ? Home.helpSearch(helpQuery, articles: m.articles, hasAgent: conferBot.agentBot != nil) : nil
        return VStack(alignment: .leading, spacing: 0) {
            if h.search {
                searchBox($helpQuery, Home.Text.searchPlaceholder, Home.Text.searchLabel, focused: $helpFocused, isFocused: helpFocused,
                          accent: m.accent, send: false) {
                    if case .results(let rows)? = found, let first = rows.first { onArticle(first.id) }
                }
            }
            switch found {
            case .results(let rows)?:
                ForEach(rows, id: \.id) { r in
                    row(lead: iconBox("doc.text", m.accent), title: runs(r.title, m.accent), sub: r.sub, trail: EmptyView(),
                        a11y: r.title.map { $0.text }.joined()) { onArticle(r.id) }
                }
            case .empty(let text, let action, let asks)?:
                VStack(spacing: 10) {
                    Text(text).font(font(13.5)).foregroundColor(color(pal.muted)).multilineTextAlignment(.center)
                    Button(action: { home.showChat(asks ? helpQuery.trimmingCharacters(in: .whitespacesAndNewlines) : nil) }) {
                        Text(action).font(font(13.5, .semibold)).foregroundColor(.white)
                            .padding(.vertical, 8).padding(.horizontal, 14)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color(m.accent)))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14).padding(.horizontal, 10).padding(.bottom, 12)
            case nil:
                HStack(alignment: .firstTextBaseline) {
                    Text(h.title).font(font(13, .bold)).tracking(0.26).foregroundColor(color(pal.ink))
                        .padding(.top, 10).padding(.horizontal, 12).padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if h.seeAll { seeAll(Home.Text.seeAll, m.accent) { home.showHelp() }.padding(.trailing, 6) }
                }
                ForEach(h.recent, id: \.id) { a in
                    row(lead: articleLead(a, m.accent), title: SwiftUI.Text(a.title), sub: a.description, trail: EmptyView(), a11y: a.title) { onArticle(a.id) }
                }
                if !h.topics.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(h.topics, id: \.id) { tp in
                                Button(action: { home.showHelp(categoryId: tp.id) }) {
                                    HStack(spacing: 6) {
                                        Text(tp.name).font(font(12.5, .semibold)).foregroundColor(mix(pal.muted, pal.ink, 0.6))
                                        Text(String(tp.count)).font(font(11, .semibold)).foregroundColor(mix(pal.card, pal.muted, 0.75))
                                    }
                                    .padding(.vertical, 6).padding(.horizontal, 10)
                                    .background(Capsule().fill(color(pal.soft)))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(tp.name), \(tp.count)")
                            }
                        }
                        .padding(.top, 8).padding(.horizontal, 6).padding(.bottom, 6)
                    }
                    .overlay(Rectangle().fill(color(pal.line)).frame(height: 1), alignment: .top)
                    .padding(.top, 4).padding(.bottom, 2)
                }
            }
        }
        .modifier(Card(fill: color(pal.card), padding: 6, shadow: 0.09))
        .padding(.top, 14)
    }

    @ViewBuilder
    private func articleLead(_ a: Home.ArticleRow, _ accent: String) -> some View {
        if let image = a.image, let url = URL(string: image) {
            AsyncImage(url: url) { phase in
                if let img = phase.image { img.resizable().scaledToFill() } else { iconBox("doc.text", accent) }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            iconBox("doc.text", accent)
        }
    }

    // MARK: - The customer logos

    private func trustRow(_ m: Home.Model) -> some View {
        let t = m.trust!
        return VStack(spacing: 10) {
            // The line shows once a logo has really loaded (trust.ts): a label over nothing is a claim with no proof.
            if !t.label.isEmpty && logosShown {
                Text(t.label).font(font(12, .semibold)).foregroundColor(color(pal.muted)).multilineTextAlignment(.center)
            }
            HStack(spacing: 18) {
                ForEach(t.logos, id: \.self) { src in
                    AsyncImage(url: URL(string: src)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit().onAppear { logosShown = true }
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 88, height: 22)
                    .opacity(0.55)
                    .accessibilityLabel(Home.Text.customerLogo)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

/// Where "Talk to us" sits in the home's scroll content (the band ends behind its middle).
private struct TalkFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
