//
//  GamesCardView.swift
//  Conferbot
//
//  The waiting games card, drawn from GamesCard's state. Ported from the
//  React Native SDK (LiveChat/GamesCard.tsx), itself from the web widget's
//  conferbot-widget src/ts/chat/games/ui.ts and its sheet
//  src/css/polish-games.css: the theme's card surface and text, the bot's
//  accent (pickAccent) for picks, wins and the main button. Motion is the
//  web's and no more: the card rises in, the hands shake for the rock paper
//  scissors reveal, a small cheer, confetti on a win; all of it off with
//  Reduce Motion. Memory cards turn without the web's 3D flip.
//

import SwiftUI

@available(iOS 15.0, *)
struct GamesLook {
    let card: Color
    let ink: Color
    let muted: Color
    let line: Color
    let accent: Color
    let dark: Bool

    /// A quiet tile (a pick, an option, a cell).
    var fill: Color { ink.opacity(dark ? 0.1 : 0.05) }
    var soft: Color { accent.opacity(0.09) }
    /// A cross in the accent on a dark card is lifted so it reads.
    var accentInk: Color { dark ? Color(hex: MascotArt.mixColor(accentHex, 50, "#ffffff")) : accent }
    let accentHex: String

    static func of(_ bot: ConferBot) -> GamesLook {
        let accentHex = WaitingGames.pickAccent(bot.serverCustomizations)
        if bot.hasServerLook, let t = bot.customizations.theme.tokens {
            let dark = (WaitingGames.luminance(t.card) ?? 1) < 0.4
            return GamesLook(card: Color(hex: t.card), ink: Color(hex: t.ink), muted: Color(hex: t.muted), line: Color(hex: t.line),
                             accent: Color(hex: accentHex), dark: dark, accentHex: accentHex)
        }
        return GamesLook(card: Color(UIColor.systemBackground), ink: Color(UIColor.label), muted: Color(UIColor.secondaryLabel),
                         line: Color(UIColor.separator), accent: Color(hex: accentHex),
                         dark: UITraitCollection.current.userInterfaceStyle == .dark, accentHex: accentHex)
    }
}

/// The games card ConferBot.waiting has up, if any.
@available(iOS 15.0, *)
public struct WaitingGamesCard: View {
    @ObservedObject private var waiting = ConferBot.shared.waiting
    public init() {}
    public var body: some View {
        if let card = waiting.gamesCard {
            GamesCardView(card: card)
        }
    }
}

@available(iOS 15.0, *)
struct GamesCardView: View {
    @ObservedObject var card: GamesCard
    @ObservedObject private var conferBot = ConferBot.shared
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var risen = false
    @State private var cheering = false

    var body: some View {
        let s = card.state
        let look = GamesLook.of(conferBot)
        if s.view != .gone {
            let win = s.result == "win"
            VStack(alignment: .leading, spacing: 0) {
                header(s, look)
                    .padding(.bottom, 10)
                if s.view == .menu {
                    menu(s, look)
                } else if s.view == .game, let b = s.board {
                    board(b, look)
                        .allowsHitTesting(!s.settled)
                }
                if !s.status.isEmpty {
                    Text(s.status)
                        .font(.system(size: 12.5, weight: s.result != nil ? .semibold : .regular))
                        .foregroundColor(look.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if !s.foot.isEmpty {
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        ForEach(s.foot, id: \.key) { f in
                            GamesFootButton(look: look, label: f.label, primary: f.primary) { card.press(f.key) }
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(12)
            .frame(maxWidth: 320, alignment: .leading)
            .background(look.card)
            .overlay(ConfettiBurst(look: look, burst: s.confetti, on: !reduced))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(win ? look.accent.opacity(0.55) : look.line, lineWidth: win ? 1.5 : 1))
            .scaleEffect(cheering ? 1.015 : 1)
            .opacity(risen || reduced ? 1 : 0)
            .offset(y: risen || reduced ? 0 : 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(GamesText.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 40)
            .onAppear {
                guard !reduced else { return risen = true }
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.45)) { risen = true }
            }
            .onChange(of: s.cheer) { _ in
                guard !reduced else { return }
                withAnimation(.easeOut(duration: 0.2)) { cheering = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeIn(duration: 0.3)) { cheering = false }
                }
            }
        }
    }

    private func header(_ s: GamesCardState, _ look: GamesLook) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                if !s.titleEmoji.isEmpty { Text(s.titleEmoji).font(.system(size: 17)).accessibilityHidden(true) }
                Text(s.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(look.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            if !s.meta.isEmpty {
                Text(s.meta)
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundColor(look.muted)
            }
            if s.closable {
                Button { card.dismiss() } label: {
                    Text("✕").font(.system(size: 14)).foregroundColor(look.muted).frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(GamesText.close)
                .padding(.trailing, -4)
            }
        }
    }

    @ViewBuilder
    private func menu(_ s: GamesCardState, _ look: GamesLook) -> some View {
        // Two per row, an odd last one full width.
        let rows = stride(from: 0, to: s.chips.count, by: 2).map { Array(s.chips[$0..<min($0 + 2, s.chips.count)]) }
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.id) { g in
                        Button { card.open(g.id) } label: {
                            HStack(spacing: 8) {
                                Text(g.emoji).font(.system(size: 18))
                                Text(g.name)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(look.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(look.soft)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(look.accent.opacity(0.16), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(g.name). \(g.blurb)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GamesText.pick)
    }

    @ViewBuilder
    private func board(_ b: GameBoard, _ look: GamesLook) -> some View {
        let act: (GameInput) -> Void = { card.input($0) }
        switch b {
        case .rps(let r): RpsBoardView(b: r, look: look, act: act, reduced: reduced)
        case .ttt(let t): TttBoardView(b: t, look: look, act: act)
        case .memory(let m): MemoryBoardView(b: m, look: look, act: act)
        case .choice(let c): ChoiceBoardView(b: c, look: look, act: act)
        case .reaction(let r): ReactionBoardView(b: r, look: look, act: act)
        case .scramble(let sc): ScrambleBoardView(b: sc, look: look, act: act, reduced: reduced)
        }
    }
}

// MARK: - Pieces

@available(iOS 15.0, *)
private struct GamesTile<Content: View>: View {
    let look: GamesLook
    var background: Color? = nil
    var disabled = false
    var label: String? = nil
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 12)
                .fill(background ?? look.fill)
                .overlay(content())
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // Not .disabled: it would dim the tile; the board's own opacity says so (web .cb-g-*).
        .allowsHitTesting(!disabled)
        .accessibilityLabel(label ?? "")
        .accessibilityAddTraits(disabled ? [] : .isButton)
    }
}

@available(iOS 15.0, *)
struct GamesFootButton: View {
    let look: GamesLook
    let label: String
    var primary = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(primary ? .white : look.ink)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(primary ? look.accent : Color.clear)
                .overlay(Capsule().stroke(primary ? Color.clear : look.line, lineWidth: 1))
                .clipShape(Capsule())
                .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!disabled)
    }
}

@available(iOS 15.0, *)
private struct RpsBoardView: View {
    let b: RpsBoard
    let look: GamesLook
    let act: (GameInput) -> Void
    let reduced: Bool
    @State private var up = false

    private func big(_ who: String) -> (opacity: Double, scale: CGFloat) {
        let won = (who == "you" && b.outcome == .win) || (who == "bot" && b.outcome == .lose)
        let lost = (who == "you" && b.outcome == .lose) || (who == "bot" && b.outcome == .win)
        return (lost ? 0.45 : 1, won ? 1.18 : 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                hand(b.you, big("you"), mirror: false)
                Text("VS").font(.system(size: 11, weight: .bold)).kerning(0.9).foregroundColor(look.muted)
                hand(b.bot, big("bot"), mirror: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .accessibilityHidden(true)
            HStack(spacing: 6) {
                ForEach(b.hands, id: \.hand) { h in
                    GamesTile(look: look, disabled: b.busy, label: h.name, action: { act(.rps(h.hand)) }) {
                        VStack(spacing: 3) {
                            Text(h.emoji).font(.system(size: 22))
                            Text(h.name).font(.system(size: 11.5, weight: .semibold)).foregroundColor(look.ink)
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(height: 58)
                    .opacity(b.busy ? 0.6 : 1)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pick your hand")
        }
        .onChange(of: b.shaking) { shaking in
            guard shaking, !reduced else { return up = false }
            // Three shakes in 900ms (web .cb-g-shake).
            withAnimation(.easeInOut(duration: 0.15).repeatCount(6, autoreverses: true)) { up = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { up = false }
        }
    }

    private func hand(_ e: String, _ s: (opacity: Double, scale: CGFloat), mirror: Bool) -> some View {
        Text(e)
            .font(.system(size: 40))
            .scaleEffect(x: mirror ? -s.scale : s.scale, y: s.scale)
            .opacity(s.opacity)
            .rotationEffect(.degrees(b.shaking && up ? -10 : 0))
            .offset(y: b.shaking && up ? -12 : 0)
    }
}

@available(iOS 15.0, *)
private struct TttBoardView: View {
    let b: TttBoard
    let look: GamesLook
    let act: (GameInput) -> Void

    private func label(_ i: Int) -> String {
        let who = b.cells[i] == .x ? "yours" : b.cells[i] == .o ? "the bot's" : "empty"
        return "Row \(i / 3 + 1), column \(i % 3 + 1), \(who)"
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { c in
                        let i = r * 3 + c
                        let cell = b.cells[i]
                        let inLine = b.line.contains(i)
                        GamesTile(look: look, background: inLine ? (cell == .o ? look.muted : look.accent) : look.fill,
                                  disabled: cell != nil || b.over || b.thinking, label: label(i), action: { act(.ttt(i)) }) {
                            Text(cell == .x ? "✕" : cell == .o ? "◯" : "")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(inLine ? .white : cell == .x ? look.accentInk : look.muted)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .opacity(b.over && !inLine ? 0.5 : 1)
                    }
                }
            }
        }
        .frame(maxWidth: 210)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tic-tac-toe board")
    }
}

@available(iOS 15.0, *)
private struct MemoryBoardView: View {
    let b: MemoryBoard
    let look: GamesLook
    let act: (GameInput) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { c in
                        let i = r * 4 + c
                        if i < b.cards.count {
                            let card = b.cards[i]
                            GamesTile(look: look, background: card.up ? (card.matched ? look.soft : look.fill) : look.accent,
                                      disabled: card.matched,
                                      label: "Card \(i + 1), \(card.up ? card.face : "face down")\(card.matched ? ", matched" : "")",
                                      action: { act(.memory(i)) }) {
                                Text(card.up ? card.face : "?")
                                    .font(.system(size: card.up ? 24 : 18, weight: card.up ? .regular : .bold))
                                    .foregroundColor(card.up ? look.ink : Color.white.opacity(0.75))
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(card.matched ? look.accent.opacity(0.45) : Color.clear, lineWidth: 1.5))
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memory cards")
    }
}

@available(iOS 15.0, *)
private struct ChoiceBoardView: View {
    let b: ChoiceBoard
    let look: GamesLook
    let act: (GameInput) -> Void

    var body: some View {
        let emoji = b.game == .emoji
        VStack(alignment: .leading, spacing: 8) {
            if let tag = b.tag {
                Text(tag)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(look.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(look.soft)
                    .clipShape(Capsule())
            }
            if let big = b.big {
                Text(big)
                    .font(.system(size: 40))
                    .kerning(3)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Emoji: \(big)")
            }
            Text(b.q)
                .font(emoji ? .system(size: 12) : .system(size: 13.5, weight: .semibold))
                .foregroundColor(emoji ? look.muted : look.ink)
                .frame(maxWidth: .infinity, alignment: emoji ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if emoji {
                VStack(spacing: 6) {
                    ForEach(Array(stride(from: 0, to: b.options.count, by: 2)), id: \.self) { r in
                        HStack(spacing: 6) {
                            ForEach(r..<min(r + 2, b.options.count), id: \.self) { i in option(i, center: true) }
                        }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(b.options.indices, id: \.self) { i in option(i, center: false) }
                }
            }
        }
    }

    private func option(_ i: Int, center: Bool) -> some View {
        let done = b.picked != nil
        let right = done && i == b.answer
        let wrong = done && i == b.picked && i != b.answer
        return Button { act(.choice(i)) } label: {
            HStack(spacing: 4) {
                if center { Spacer(minLength: 0) }
                Text(b.options[i])
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(right ? .white : look.ink)
                    .strikethrough(wrong)
                    .multilineTextAlignment(center ? .center : .leading)
                if !center { Spacer(minLength: 0) }
                if right { Text("✓").font(.system(size: 13, weight: .semibold)).foregroundColor(.white).padding(.leading, center ? 0 : 6) }
                if center { Spacer(minLength: 0) }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(right ? look.accent : look.fill)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(done && !right && !wrong ? 0.5 : wrong ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!done)
        .accessibilityLabel(b.options[i])
    }
}

@available(iOS 15.0, *)
private struct ReactionBoardView: View {
    let b: ReactionBoard
    let look: GamesLook
    let act: (GameInput) -> Void

    var body: some View {
        let go = b.state == .go
        let wait = b.state == .wait
        VStack(spacing: 6) {
            Text(b.big).font(.system(size: 30))
            Text(b.line).font(.system(size: 13.5, weight: .semibold)).foregroundColor(go ? .white : look.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .background(go ? Color(red: 0x16 / 255, green: 0xa3 / 255, blue: 0x4a / 255) : wait ? look.fill : look.soft)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(go ? Color.clear : wait ? look.line : look.accent.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        // On press, not on release, so the time is the visitor's.
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressDown() }.onEnded { _ in pressed = false })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(b.line)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if b.state != .done { act(.reaction) } }
    }

    @State private var pressed = false

    private func pressDown() {
        guard !pressed else { return }
        pressed = true
        if b.state != .done { act(.reaction) }
    }
}

/// The scramble's slots nudge sideways on a wrong word (web .cb-g-nope).
private struct Nudge: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        // 0, -5, 5, -3, 3, 0 over one unit.
        let p = travel - floor(travel)
        let keys: [CGFloat] = [0, -5, 5, -3, 3, 0]
        let x = p * 5
        let i = min(4, Int(x))
        let dx = keys[i] + (keys[i + 1] - keys[i]) * (x - CGFloat(i))
        return ProjectionTransform(CGAffineTransform(translationX: travel == floor(travel) ? 0 : dx, y: 0))
    }
}

@available(iOS 15.0, *)
private struct ScrambleBoardView: View {
    let b: ScrambleBoard
    let look: GamesLook
    let act: (GameInput) -> Void
    let reduced: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text(b.hint).font(.system(size: 30)).frame(maxWidth: .infinity).accessibilityHidden(true)
            HStack(spacing: 5) {
                ForEach(b.letters.indices, id: \.self) { i in slot(i) }
            }
            .frame(maxWidth: .infinity)
            .modifier(Nudge(travel: reduced ? 0 : CGFloat(b.nope)))
            .animation(reduced ? nil : .linear(duration: 0.4), value: b.nope)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Your word, tap a letter to take it back")
            HStack(spacing: 5) {
                ForEach(b.letters.indices, id: \.self) { i in
                    let used = b.placed.contains(i)
                    Button { act(.tile(i)) } label: {
                        Text(b.letters[i])
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(look.ink)
                            .frame(width: 36, height: 40)
                            .background(look.fill)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .opacity(used ? 0.2 : 1)
                            .scaleEffect(used ? 0.9 : 1)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!(used || b.solved))
                    .accessibilityLabel("Letter \(b.letters[i])")
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Letters")
            HStack {
                Spacer()
                GamesFootButton(look: look, label: b.skipLabel, disabled: b.solved) { act(.skip) }
                Spacer()
            }
        }
    }

    private func slot(_ i: Int) -> some View {
        let filled = i < b.placed.count && b.placed[i] >= 0 && b.placed[i] < b.letters.count
        let solvedLook = b.solved && !b.revealed
        let letter = filled ? b.letters[b.placed[i]] : ""
        return Button { act(.slot(i)) } label: {
            Text(letter)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(solvedLook ? .white : b.revealed ? look.muted : look.ink)
                .frame(width: 34, height: 40)
                .background(solvedLook ? look.accent : b.revealed ? look.fill : filled ? look.soft : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(solvedLook || b.revealed ? Color.clear : filled ? look.accent.opacity(0.55) : look.line, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(filled && !b.solved)
        .accessibilityLabel(filled ? "Space \(i + 1), \(letter)" : "Space \(i + 1), empty")
    }
}

// MARK: - Confetti (web ui.ts confetti)

@available(iOS 15.0, *)
private struct ConfettiBurst: View {
    let look: GamesLook
    let burst: Int
    let on: Bool
    @State private var falling = false
    @State private var showing = false

    private struct Piece {
        let x: CGFloat, dx: CGFloat, r: Double, d: Double, round: Bool
    }
    @State private var pieces: [Piece] = (0..<34).map { i in
        Piece(x: .random(in: 0...1), dx: .random(in: -60...60), r: .random(in: -360...360), d: .random(in: 0...0.15), round: i % 3 == 0)
    }

    var body: some View {
        GeometryReader { geo in
            if showing {
                let tints = [look.accent, Color(hex: "#f5a524"), look.accent.opacity(0.45), Color(hex: "#ff6b6b"), Color(hex: "#22c55e")]
                ZStack(alignment: .topLeading) {
                    ForEach(pieces.indices, id: \.self) { i in
                        let p = pieces[i]
                        RoundedRectangle(cornerRadius: p.round ? 4 : 2)
                            .fill(tints[i % tints.count])
                            .frame(width: p.round ? 8 : 7, height: p.round ? 8 : 11)
                            .rotationEffect(.degrees(falling ? p.r : 0))
                            .offset(x: p.x * geo.size.width + (falling ? p.dx : 0), y: falling ? 300 : -12)
                            .opacity(falling ? 0 : 1)
                            .animation(.timingCurve(0.25, 0.6, 0.4, 1, duration: 1.5).delay(p.d * 1.75), value: falling)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: burst) { n in
            guard on, n > 0 else { return }
            falling = false
            showing = true
            DispatchQueue.main.async { falling = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                showing = false
                falling = false
            }
        }
    }
}
