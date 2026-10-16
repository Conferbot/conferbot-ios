//
//  GreetingCardView.swift
//  Conferbot
//
//  The greeting card by the closed launcher, dressed as the web widget
//  dresses it (conferbot-widget css/polish-home.css .cb-greet and
//  .cb-greet--<style>, ts/home/firstImpression.ts, ts/home/greetingStyle.ts;
//  the React Native SDK's FloatingWidget/GreetingCard.tsx and
//  docs/greeting-card-native-spec.md): the plain card, a handwritten note, a
//  phone text (the default), a postcard, a sticky note, a typewriter, glass,
//  a push notification, neon, a voice note or an aurora edge, each with its
//  reveal. Fonts are the phone's nearest ones (Noteworthy, Marker Felt,
//  Georgia, Courier New); glass and the notification blur what is behind.
//

import SwiftUI
import UIKit

// MARK: - Timing (CSS keyframes, eased per segment)

/// A CSS cubic-bezier timing function.
struct CubicBezier {
    let x1: Double, y1: Double, x2: Double, y2: Double

    static let ease = CubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    static let easeIn = CubicBezier(x1: 0.42, y1: 0, x2: 1, y2: 1)
    static let easeInOut = CubicBezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    static let linear = CubicBezier(x1: 0, y1: 0, x2: 1, y2: 1)

    func callAsFunction(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        // Solve x(s) = t by Newton, then bisection.
        func bx(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * x1 + 3 * (1 - s) * s * s * x2 + s * s * s }
        func by(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * y1 + 3 * (1 - s) * s * s * y2 + s * s * s }
        var s = t
        for _ in 0..<8 {
            let d = 3 * (1 - s) * (1 - s) * x1 + 6 * (1 - s) * s * (x2 - x1) + 3 * s * s * (1 - x2)
            if abs(d) < 1e-6 { break }
            s -= (bx(s) - t) / d
        }
        if s < 0 || s > 1 || abs(bx(s) - t) > 1e-4 {
            var lo = 0.0, hi = 1.0
            s = t
            for _ in 0..<30 {
                if bx(s) < t { lo = s } else { hi = s }
                s = (lo + hi) / 2
            }
        }
        return by(s)
    }
}

/// A value at `ms` into keyframes [(offset 0...1, value)] lasting `dur` ms, eased per segment.
func keyframe(_ ms: Double, _ dur: Double, _ frames: [(Double, Double)], _ ease: CubicBezier) -> Double {
    guard let first = frames.first, let last = frames.last else { return 0 }
    let p = ms / dur
    if p <= first.0 { return first.1 }
    if p >= last.0 { return last.1 }
    for i in 1..<frames.count where p <= frames[i].0 {
        let a = frames[i - 1], b = frames[i]
        let local = (p - a.0) / max(1e-9, b.0 - a.0)
        return a.1 + (b.1 - a.1) * ease(local)
    }
    return last.1
}

// MARK: - Colours and fonts

private func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
    Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
}

/// The card's type: the style's family, the bot's font, or the system font.
private enum GreetingFamily { case card, system, note, marker, serif, mono }

private func greetingFont(_ family: GreetingFamily, _ size: CGFloat, _ weight: UIFont.Weight = .regular, italic: Bool = false, cardFont: String?) -> UIFont {
    let bold = weight.rawValue >= UIFont.Weight.semibold.rawValue
    var named: UIFont?
    switch family {
    case .note: named = UIFont(name: bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: size)
    case .marker: named = UIFont(name: "MarkerFelt-Wide", size: size)
    case .serif: named = UIFont(name: bold ? (italic ? "Georgia-BoldItalic" : "Georgia-Bold") : (italic ? "Georgia-Italic" : "Georgia"), size: size)
    case .mono: named = UIFont(name: bold ? "CourierNewPS-BoldMT" : "CourierNewPSMT", size: size)
    case .card: named = cardFont.flatMap { UIFont(name: $0, size: size) }
    case .system: named = nil
    }
    if let f = named { return f }
    let sys = UIFont.systemFont(ofSize: size, weight: weight)
    if italic, let d = sys.fontDescriptor.withSymbolicTraits(.traitItalic) { return UIFont(descriptor: d, size: size) }
    return sys
}

/// A CSS linear-gradient(angle) over a box of this size: the start and end points as SwiftUI unit points.
private func cssGradientPoints(_ degrees: Double, _ size: CGSize) -> (UnitPoint, UnitPoint) {
    let a = degrees * .pi / 180
    let dx = sin(a), dy = -cos(a)
    let len = abs(Double(size.width) * dx) + abs(Double(size.height) * dy)
    let w = max(1, Double(size.width)), h = max(1, Double(size.height))
    let sx = (w / 2 - dx * len / 2) / w, sy = (h / 2 - dy * len / 2) / h
    let ex = (w / 2 + dx * len / 2) / w, ey = (h / 2 + dy * len / 2) / h
    return (UnitPoint(x: sx, y: sy), UnitPoint(x: ex, y: ey))
}

@available(iOS 15.0, *)
private struct CSSLinearGradient<S: Shape>: View {
    let shape: S
    let degrees: Double
    let stops: [Gradient.Stop]

    var body: some View {
        GeometryReader { geo in
            let (s, e) = cssGradientPoints(degrees, geo.size)
            shape.fill(LinearGradient(stops: stops, startPoint: s, endPoint: e))
        }
    }
}

/// A CSS box-shadow (x y blur spread colour) under a shape; outsideOnly keeps it out from under a see-through card, as CSS does.
@available(iOS 15.0, *)
private struct CSSShadow<S: Shape>: View {
    let shape: S
    var x: CGFloat = 0, y: CGFloat, blur: CGFloat, spread: CGFloat, color: Color
    var outsideOnly = false

    var body: some View {
        let shadow = shape.fill(color)
            .padding(-spread)
            .offset(x: x, y: y)
            .blur(radius: blur / 2)
        if outsideOnly {
            shadow.mask(
                ZStack {
                    Rectangle().padding(-120)
                    shape.fill(Color.black).blendMode(.destinationOut)
                }
                .compositingGroup()
            )
        } else {
            shadow
        }
    }
}

// MARK: - Glyphs

/// The web's close glyph (viewBox -6 -6 24 24), at `size`.
private struct GreetingCloseGlyph: Shape {
    static let d = "m7.314 5.9l3.535-3.536A1 1 0 1 0 9.435.95L5.899 4.485L2.364.95A1 1 0 1 0 .95 2.364l3.535 3.535L.95 9.435a1 1 0 1 0 1.414 1.414l3.535-3.535l3.536 3.535a1 1 0 1 0 1.414-1.414L7.314 5.899z"
    private static let base = Path.fromSVG(d)

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        return Self.base.applying(CGAffineTransform(translationX: rect.minX + 6 * s, y: rect.minY + 6 * s).scaledBy(x: s, y: s))
    }
}

/// The phone text's tail (16x16): M0 0 C 2 9 7 14 16 16 C 8 16 3 14 0 11 Z.
private struct GreetingTail: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 16
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addCurve(to: CGPoint(x: 16 * s, y: 16 * s), control1: CGPoint(x: 2 * s, y: 9 * s), control2: CGPoint(x: 7 * s, y: 14 * s))
        p.addCurve(to: CGPoint(x: 0, y: 11 * s), control1: CGPoint(x: 8 * s, y: 16 * s), control2: CGPoint(x: 3 * s, y: 14 * s))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

/// The voice note's play triangle (viewBox 24): M8 5.5v13l10.5-6.5z.
private struct GreetingPlay: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 8 * s, y: 5.5 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: 18.5 * s))
        p.addLine(to: CGPoint(x: 18.5 * s, y: 12 * s))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

/// The note's wavy chip underline.
private struct GreetingWave: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY, amp: CGFloat = 1.5, length: CGFloat = 6
        p.move(to: CGPoint(x: rect.minX, y: mid))
        var x = rect.minX
        while x < rect.maxX {
            let step = min(1, rect.maxX - x)
            x += step
            p.addLine(to: CGPoint(x: x, y: mid + amp * sin((x - rect.minX) / length * 2 * .pi)))
        }
        return p
    }
}

// MARK: - Chips

@available(iOS 15.0, *)
private struct GreetingChipStyle: ButtonStyle {
    let draw: (Bool) -> AnyView
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(draw(configuration.isPressed)).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The chips wrap as the web's flex-wrap row (iOS 16+); one per line before.
@available(iOS 16.0, *)
private struct GreetingFlow: Layout {
    var spacing: CGFloat = 6
    var trailing = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let h = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = trailing ? bounds.maxX - row.width : bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var cur: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let w = min(s.width, width)
            if !cur.items.isEmpty && cur.width + spacing + w > width {
                rows.append(cur)
                cur = ([], 0, 0)
            }
            cur.width += (cur.items.isEmpty ? 0 : spacing) + w
            cur.items.append(i)
            cur.height = max(cur.height, s.height)
        }
        if !cur.items.isEmpty { rows.append(cur) }
        return rows
    }
}

// MARK: - The card

@available(iOS 15.0, *)
struct GreetingCardView: View {
    let card: GreetingCardData
    /// The launcher is on the left: the card grows from its bottom-left corner.
    var alignLeft = false
    let onPress: () -> Void
    let onClose: () -> Void
    let onStarter: (String) -> Void
    /// The card is going: "open" (opened from it, or the chat opened) or "close" (its x).
    var leaving: String? = nil
    /// The launcher under the card (the figure hands off toward its centre).
    var launcher: CGSize? = nil
    /// It has gone (its leaving moves are over).
    var onGone: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var figure = GreetingFigureModel()
    @State private var leftAt: Date?
    @State private var shownAt = Date()
    @State private var settled = false
    @State private var typed = 0
    @State private var typing: Task<Void, Never>?

    private var style: String { card.style }
    private var accent: Color { Color(hex: card.accent) }
    private func accent(_ a: Double) -> Color { Color(hex: card.accent).opacity(a) }
    private var lively: Bool { card.motion == "lively" && !reduceMotion }
    /// The phone text's typing moment: once per app session.
    private var imReveal: Bool { style == "imessage" && card.firstShow && !reduceMotion }

    /// When every one-off animation has ended (the ring and the caret keep their own clocks).
    private var settleMs: Double {
        switch style {
        case "imessage": return 1800
        case "voice": return 21 * 60 + 2400 + 100
        default: return card.motion == "off" ? 700 : 2100
        }
    }

    /// The card's width: its style's, never wider than the screen less 12 a side.
    private var width: CGFloat { min(CGFloat(Greeting.width(style)), UIScreen.main.bounds.width - 24) }

    /// What moves on the card: the owner's mascot, the bot's avatar (not on the text message, whose head is hidden), or nothing.
    private var figureKind: String? {
        card.mascot != nil ? "mascot" : card.head.avatar != nil && style != "imessage" ? "avatar" : nil
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: (settled || reduceMotion) && leftAt == nil)) { tl in
            let t = settled || reduceMotion ? 1e9 : tl.date.timeIntervalSince(shownAt) * 1000
            // Leaving: the collapse toward the launcher, or the fade down (polish-home.css).
            let leave = leftAt.flatMap { at in
                MascotMotion.cardLeaveTrack(card.motion, leaving ?? "open", reduced: reduceMotion).map { Keyframes.evaluate([$0], tl.date.timeIntervalSince(at) * 1000) }
            } ?? FxValues.rest()
            styled(t)
                .modifier(Entrance(style: style, motion: card.motion, reduced: reduceMotion, t: t, anchor: alignLeft ? .bottomLeading : .bottomTrailing))
                .modifier(FxTransformEffect(v: leave, order: "ts"))
                .opacity(min(1, max(0, leave.o)))
        }
        .frame(width: width)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { figure.cardHeight = Double(g.size.height) }
                .onChange(of: g.size.height) { figure.cardHeight = Double($0) }
        })
        .contentShape(Rectangle())
        .onTapGesture(perform: onPress)
        .allowsHitTesting(leaving == nil)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(card.text))
        .onAppear {
            shownAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + settleMs / 1000) { settled = true }
            startTyping()
            figure.toward = { [width, alignLeft, launcher, figureSize, weak figure] in
                // The figure sits at the card's top left (16, 14 in); the launcher 12 below the card, its outer edge in line.
                guard let l = launcher, let h = figure?.cardHeight else { return nil }
                let fx = 16 + figureSize / 2, fy = 14 + figureSize / 2
                let lx = alignLeft ? l.width / 2 : width - l.width / 2
                return (Double(lx - fx), h + Double(12 + l.height / 2 - fy))
            }
            figure.start(mode: card.motion, style: style, figure: figureKind, reduced: reduceMotion)
            if let reason = leaving { leave(reason) }
        }
        .onChange(of: leaving) { reason in
            if let reason = reason { leave(reason) }
        }
        .onDisappear {
            typing?.cancel()
            figure.stop()
        }
    }

    private var figureSize: CGFloat { card.mascot != nil ? 40 : 32 }

    /// The figure's hand-off or bow, the card's collapse or fade, then gone.
    private func leave(_ reason: String) {
        guard leftAt == nil else { return }
        leftAt = Date()
        let figureEnd = figure.hide(reason)
        let cardEnd = MascotMotion.cardLeaveTrack(card.motion, reason, reduced: reduceMotion).map { Keyframes.tracksEnd([$0]) } ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + (max(figureEnd, cardEnd) + 16) / 1000) { onGone?() }
    }

    /// The typewriter: from 260ms, a character every 34-64ms, a pause after punctuation.
    private func startTyping() {
        guard style == "typewriter", !reduceMotion else { typed = card.text.count; return }
        typed = 0
        let chars = Array(card.text)
        typing?.cancel()
        typing = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            for (i, ch) in chars.enumerated() {
                if Task.isCancelled { return }
                typed = i + 1
                try? await Task.sleep(nanoseconds: UInt64(Greeting.typeDelay(after: ch) * 1_000_000))
            }
        }
    }

    // MARK: Shared parts

    private func font(_ family: GreetingFamily, _ size: CGFloat, _ weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        greetingFont(family, size, weight, italic: italic, cardFont: card.font)
    }

    private func close(top: CGFloat, right: CGFloat, color: Color, circle: Color? = nil, size: CGFloat = 26, glyph: CGFloat = 20, shadow: Bool = false) -> some View {
        Button(action: onClose) {
            ZStack {
                if let c = circle {
                    Circle().fill(c).shadow(color: shadow ? Color.black.opacity(0.2) : .clear, radius: 3, x: 0, y: 2)
                }
                GreetingCloseGlyph().fill(color).frame(width: glyph, height: glyph)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Dismiss"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, top)
        .padding(.trailing, right)
    }

    /// The online dot and its one-off ping (lively 900ms, subtle 600ms after show).
    private func dot(_ t: Double) -> some View {
        let start = card.motion == "lively" ? 900.0 : 600.0
        let on = !reduceMotion && card.motion != "off" && style != "notification" && style != "postcard"
        let local = on ? t - start : -1
        let scale = local >= 0 ? keyframe(local, 500, [(0, 1), (0.4, 1.35), (1, 1)], CubicBezier(x1: 0.3, y1: 1.6, x2: 0.5, y2: 1)) : 1
        let ringO = local >= 0 && local < 1100 ? keyframe(local, 1100, [(0, 0.55), (1, 0)], CubicBezier(x1: 0.2, y1: 0.7, x2: 0.3, y2: 1)) : 0
        let ringS = local >= 0 ? keyframe(local, 1100, [(0, 1), (1, 3.2)], CubicBezier(x1: 0.2, y1: 0.7, x2: 0.3, y2: 1)) : 1
        return ZStack {
            Circle().fill(Color(hex: "#22c55e")).frame(width: 7, height: 7).scaleEffect(ringS).opacity(ringO)
            Circle().fill(Color(hex: "#22c55e")).frame(width: 7, height: 7).scaleEffect(scale)
        }
        .frame(width: 7, height: 7)
    }

    /// The bot's avatar, or the owner's mascot in its place (polish-home.css .cb-greet__mascot:
    /// 40 x 40, blinking, waving twice as the card appears), moved by the director.
    private func avatar(_ size: CGFloat, radius: CGFloat? = nil) -> some View {
        Group {
            if let m = card.mascot {
                GreetingFigure(model: figure, size: 40) {
                    MascotView(look: m.look, accent: m.accent, size: 40, mood: "wave", arm: "wave", waveCount: 2)
                }
                .frame(width: 40, height: 40)
                .padding(.top, -6)
                .padding(.bottom, -4)
                .padding(.leading, -2)
            } else if let url = card.head.avatar.flatMap(URL.init(string:)) {
                GreetingFigure(model: figure, size: size) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color(hex: "#eef2f7") }
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: radius ?? size / 2, style: .continuous))
                }
            }
        }
    }

    private struct HeadLook {
        var avatar: CGFloat = 32
        var avatarRadius: CGFloat?
        var showAvatar = true
        var name: UIFont
        var nameColor = Color(hex: "#0f172a")
        var nameTracking: CGFloat = 0
        var uppercase = false
        var nameGlow: Color?
        var status: UIFont
        var statusColor = Color(hex: "#64748b")
        var statusText: String?
        var dot = true
        var row = false
        var statusWraps = false
        var padRight: CGFloat = 22
    }

    private func head(_ h: HeadLook, _ t: Double) -> some View {
        let name = Text(h.uppercase ? card.head.name.uppercased() : card.head.name)
            .font(Font(h.name as CTFont))
            .tracking(h.nameTracking)
            .foregroundColor(h.nameColor)
            .lineLimit(1)
            .truncationMode(.tail)
        let showStatus = h.statusText != nil || card.head.online
        let status = HStack(spacing: 5) {
            if h.dot && h.statusText == nil { dot(t) }
            Text(h.statusText ?? "Online")
                .font(Font(h.status as CTFont))
                .foregroundColor(h.statusColor)
                .lineLimit(h.statusWraps ? 2 : 1)
                .lineSpacing(h.statusWraps ? max(0, h.status.pointSize * 1.25 - h.status.lineHeight) : 0)
                .fixedSize(horizontal: false, vertical: true)
        }
        return HStack(spacing: 10) {
            if h.showAvatar { avatar(h.avatar, radius: h.avatarRadius) }
            if h.row {
                HStack(spacing: 0) {
                    name
                    Spacer(minLength: 6)
                    if showStatus { status.padding(.trailing, 18) }
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    if let g = h.nameGlow {
                        name.shadow(color: g.opacity(0.9), radius: 4).shadow(color: g.opacity(0.6), radius: 9)
                    } else {
                        name
                    }
                    if showStatus { status }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.trailing, h.padRight)
    }

    /// The message, each word fading up in turn on a lively card (opacity only).
    private func message(_ t: Double, _ f: UIFont, lineHeight: CGFloat, color: Color, lines: Int = 3, italicPad: CGFloat = 0) -> some View {
        let text = card.text
        var out = Text("")
        let fade = lively && style != "imessage"
        let words = Self.tokens(text)
        let count = words.filter { !$0.space }.count
        if fade && count >= 2 {
            let step = min(55, (520 / Double(count - 1)).rounded(.down))
            var i = 0
            for w in words {
                if w.space { out = out + Text(w.s); continue }
                let o = keyframe(t - 380 - Double(i) * step, 320, [(0, 0), (1, 1)], CubicBezier(x1: 0.22, y1: 1, x2: 0.36, y2: 1))
                out = out + Text(w.s).foregroundColor(color.opacity(o))
                i += 1
            }
        } else {
            out = Text(text).foregroundColor(color)
        }
        let spacing = max(0, lineHeight - f.lineHeight)
        return out
            .font(Font(f as CTFont))
            .lineSpacing(spacing)
            .lineLimit(lines)
            .padding(.vertical, spacing / 2)
            .padding(.trailing, italicPad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func tokens(_ s: String) -> [(s: String, space: Bool)] {
        var out: [(s: String, space: Bool)] = []
        var cur = "", curSpace = false
        for ch in s {
            let sp = ch.isWhitespace
            if !cur.isEmpty && sp != curSpace { out.append((cur, curSpace)); cur = "" }
            cur.append(ch)
            curSpace = sp
        }
        if !cur.isEmpty { out.append((cur, curSpace)) }
        return out
    }

    private func chips(_ f: UIFont, color: Color, trailing: Bool = false, padV: CGFloat = 6, padH: CGFloat = 12,
                       note: Bool = false, opacity: Double = 1, background: @escaping (Bool) -> AnyView) -> some View {
        Group {
            if !card.starters.isEmpty {
                let items = ForEach(card.starters, id: \.self) { s in
                    Button { onStarter(s) } label: {
                        Text(s)
                            .font(Font(f as CTFont))
                            .foregroundColor(color)
                            .lineLimit(1)
                            .padding(.vertical, padV)
                            .padding(.horizontal, padH)
                            .overlay(alignment: .bottom) {
                                if note { GreetingWave().stroke(accent(0.5), lineWidth: 1).frame(height: 4).padding(.horizontal, padH).offset(y: 1) }
                            }
                    }
                    .buttonStyle(GreetingChipStyle(draw: background))
                }
                Group {
                    if #available(iOS 16.0, *) {
                        GreetingFlow(spacing: 6, trailing: trailing) { items }
                    } else {
                        VStack(alignment: trailing ? .trailing : .leading, spacing: 6) { items }
                            .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
                    }
                }
                .padding(.top, 2)
                .opacity(opacity)
            }
        }
    }

    /// The base chip: accent text on a faint accent fill with an accent hairline.
    private func baseChip(radius: CGFloat = 999) -> (Bool) -> AnyView {
        let a = card.accent
        return { pressed in
            AnyView(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(hex: a).opacity(pressed ? 0.13 : 0.07))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color(hex: a).opacity(pressed ? 0.4 : 0.22), lineWidth: 1)))
        }
    }

    private func plainChip(radius: CGFloat = 999, fill: Color, border: Color? = nil, glow: Color? = nil) -> (Bool) -> AnyView {
        { pressed in
            AnyView(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border ?? .clear, lineWidth: 1))
                .shadow(color: glow ?? .clear, radius: 5)
                .opacity(pressed ? 0.8 : 1))
        }
    }

    private var pad: EdgeInsets { EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16) }

    // MARK: Styles

    @ViewBuilder
    private func styled(_ t: Double) -> some View {
        switch style {
        case "imessage": imessage(t)
        case "note": note(t)
        case "postcard": postcard(t)
        case "sticky": sticky(t)
        case "typewriter": typewriter(t)
        case "glass": glass(t)
        case "notification": notification(t)
        case "neon": neon(t)
        case "voice": voice(t)
        case "aurora": aurora(t)
        default: plain(t)
        }
    }

    private var baseHead: HeadLook {
        HeadLook(name: font(.card, 13.5, .bold), status: font(.card, 12, .medium))
    }

    private func baseBody(_ t: Double, head h: HeadLook? = nil, msgColor: Color = Color(hex: "#1e293b"), chip: ((Bool) -> AnyView)? = nil, chipColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            head(h ?? baseHead, t)
            message(t, font(.card, 14, .medium), lineHeight: 20.3, color: msgColor)
            chips(font(.card, 13, .semibold), color: chipColor ?? accent, background: chip ?? baseChip())
        }
        .padding(pad)
    }

    // card: the base skeleton.
    private func plain(_ t: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return baseBody(t)
            .background(
                ZStack {
                    CSSShadow(shape: shape, y: 18, blur: 44, spread: -14, color: rgba(15, 23, 42, 0.32))
                    shape.fill(Color.white)
                    shape.inset(by: -0.5).stroke(rgba(15, 23, 42, 0.06), lineWidth: 1)
                }
            )
            .overlay(close(top: 10, right: 10, color: Color(hex: "#94a3b8")))
    }

    // note: handwritten on ruled paper, taped, tilted.
    private func note(_ t: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        var h = baseHead
        h.name = font(.note, 17, .bold)
        h.nameColor = Color(hex: "#1f2a44")
        h.status = font(.note, 12, .medium)
        h.statusColor = Color(hex: "#475569")
        return VStack(alignment: .leading, spacing: 8) {
            head(h, t)
            message(t, font(.note, 20), lineHeight: 26, color: Color(hex: "#1f2a44"))
            chips(font(.note, 16), color: accent, padV: 2, padH: 4, note: true, background: plainChip(radius: 4, fill: .clear))
        }
        .padding(EdgeInsets(top: 20, leading: 16, bottom: 14, trailing: 16))
        .background(
            ZStack {
                CSSShadow(shape: shape, y: 16, blur: 34, spread: -14, color: rgba(30, 41, 59, 0.45))
                CSSShadow(shape: shape, y: 1, blur: 0, spread: 0, color: rgba(30, 41, 59, 0.06))
                shape.fill(Color(hex: "#fffdf5"))
                // The ruling: 1px every 26 from 69 down, and the tile above 44 (spec 2).
                Canvas { ctx, size in
                    let H = Double(size.height)
                    var ys: [Double] = []
                    var y = 69.0
                    while y < H { ys.append(y); y += 26 }
                    var k = -Double(Int(H / 26) + 2)
                    while k < 4 { let v = 69 - H + 26 * k; if v >= 0 && v < 44 { ys.append(v) }; k += 1 }
                    for y in ys { ctx.fill(Path(CGRect(x: 0, y: y, width: Double(size.width), height: 1)), with: .color(rgba(59, 130, 246, 0.16))) }
                }
                .clipShape(shape)
            }
        )
        .overlay(alignment: .top) {
            Rectangle().fill(rgba(253, 230, 138, 0.72))
                .frame(width: 84, height: 20)
                .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)
                .rotationEffect(.degrees(2))
                .offset(y: -9)
                .allowsHitTesting(false)
        }
        .overlay(close(top: 10, right: 10, color: Color(hex: "#94a3b8")))
        .rotationEffect(.degrees(reduceMotion ? 0 : -1.6))
    }

    // imessage (default): typing dots, then the text bubble, "Delivered".
    private func imessage(_ t: Double) -> some View {
        let b = card.bubble
        let bubbleShape = RoundedRectangle(cornerRadius: 19, style: .continuous)
        let tail = Color(hex: b.tail)
        let msgFont = font(.card, 15)
        let spacing = max(0, 20.25 - msgFont.lineHeight)
        // Reveal: dots 0-1100ms, the pop at 1050ms, "Delivered" and chips at 1450ms.
        let pop = imReveal ? t - 1050 : 1e9
        let popScale = pop < 0 ? 0.4 : keyframe(pop, 420, [(0, 0.4), (1, 1)], CubicBezier(x1: 0.2, y1: 1.3, x2: 0.4, y2: 1))
        let popO = pop < 0 ? 0 : keyframe(pop, 420, [(0, 0), (1, 1)], CubicBezier(x1: 0.2, y1: 1.3, x2: 0.4, y2: 1))
        let late = imReveal ? keyframe(t - 1450, 300, [(0, 0), (1, 1)], .ease) : 1
        let dotsO = imReveal ? keyframe(t, 1100, [(0, 0), (0.15, 1), (0.8, 1), (1, 0)], .ease) : 0
        let dotsS = keyframe(t, 1100, [(0, 0.6), (0.15, 1), (0.8, 1), (1, 1.08)], .ease)
        return VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Text(card.text)
                    .font(Font(msgFont as CTFont))
                    .foregroundColor(Color(hex: b.fg))
                    .lineSpacing(spacing)
                    .lineLimit(3)
                    .padding(.vertical, 9 + spacing / 2)
                    .padding(.horizontal, 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        ZStack(alignment: .bottomTrailing) {
                            CSSShadow(shape: bubbleShape, y: 10, blur: 26, spread: -12, color: rgba(15, 23, 42, 0.45))
                            if b.bg.count > 1 {
                                CSSLinearGradient(shape: bubbleShape, degrees: 135, stops: [.init(color: Color(hex: b.bg[0]), location: 0), .init(color: Color(hex: b.bg[1]), location: 1)])
                            } else {
                                bubbleShape.fill(Color(hex: b.bg.first ?? "#1b55f3"))
                            }
                            GreetingTail().fill(tail).frame(width: 16, height: 16).offset(x: 5)
                        }
                    )
                    .scaleEffect(popScale, anchor: .bottomTrailing)
                    .opacity(popO)
                    .frame(maxWidth: 270 * 0.88, alignment: .trailing)
                if imReveal && t < 1100 {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { k in
                            let local = (t - Double(k) * 150).truncatingRemainder(dividingBy: 1000)
                            let on = t - Double(k) * 150 >= 0
                            Circle().fill(Color(hex: "#8e8e93")).frame(width: 7, height: 7)
                                .opacity(on ? keyframe(local, 1000, [(0, 0.35), (0.3, 1), (0.6, 0.35), (1, 0.35)], .easeInOut) : 0.35)
                                .offset(y: on ? keyframe(local, 1000, [(0, 0), (0.3, -3), (0.6, 0), (1, 0)], .easeInOut) : 0)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(
                        ZStack(alignment: .bottomTrailing) {
                            bubbleShape.fill(Color(hex: "#e9e9eb"))
                            GreetingTail().fill(Color(hex: "#e9e9eb")).frame(width: 16, height: 16).offset(x: 5)
                        }
                    )
                    .scaleEffect(dotsS)
                    .opacity(dotsO)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Text("Delivered")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#8e8e93"))
                .padding(.trailing, 6)
                .padding(.top, -2)
                .opacity(late)
            chips(font(.card, 13, .semibold), color: accent, trailing: true, opacity: late) { [b, a = card.accent] pressed in
                AnyView(ZStack {
                    let s = RoundedRectangle(cornerRadius: 17, style: .continuous)
                    CSSShadow(shape: s, y: pressed ? 8 : 6, blur: pressed ? 18 : 16, spread: -10, color: pressed ? Color(hex: a).opacity(0.8) : rgba(15, 23, 42, 0.45))
                    if pressed { s.fill(Color(hex: b.bg.first ?? a)) } else { s.fill(Color.white.opacity(0.94)) }
                    s.strokeBorder(Color(hex: a).opacity(0.35), lineWidth: 1)
                })
            }
        }
        .padding(.top, 18)
        .overlay(close(top: -6, right: -4, color: .white, circle: rgba(142, 142, 147, 0.9), size: 22, glyph: 16))
    }

    // postcard: airmail edge, stamp, postmark, serif.
    private func postcard(_ t: Double) -> some View {
        let outer = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let paper = Color(hex: "#fbf6ea")
        var h = baseHead
        h.showAvatar = false
        h.name = font(.serif, 12, .semibold)
        h.nameColor = Color(hex: "#8a6d4b")
        h.nameTracking = 1.44
        h.uppercase = true
        h.status = font(.serif, 17, .semibold, italic: true)
        h.statusColor = Color(hex: "#2b2118")
        h.statusText = "Greetings from \(card.head.name.isEmpty ? "us" : card.head.name)"
        h.dot = false
        h.statusWraps = true
        h.padRight = 62
        return VStack(alignment: .leading, spacing: 8) {
            head(h, t)
            message(t, font(.serif, 15, .medium, italic: true), lineHeight: 21.75, color: Color(hex: "#3b2f24"), italicPad: 40)
            chips(font(.serif, 13, .semibold), color: accent, background: baseChip(radius: 3))
        }
        .padding(pad)
        .background(
            ZStack(alignment: .topTrailing) {
                Rectangle().fill(paper)
                // The stamp: accent, a white frame, a perforated edge, a heart.
                ZStack {
                    Rectangle().fill(Color.white).frame(width: 44, height: 52)
                        .shadow(color: rgba(43, 33, 24, 0.25), radius: 2.5, x: 0, y: 1)
                    Canvas { ctx, size in
                        // Perforation: 3pt paper dots, 6 apart, 2.5 outside the stamp.
                        let r = CGRect(x: 7 - 2.5, y: 7 - 2.5, width: 40 + 5, height: 48 + 5)
                        func dots(_ a: CGPoint, _ b: CGPoint) {
                            let len = hypot(b.x - a.x, b.y - a.y), n = max(1, Int((len / 6).rounded()))
                            for i in 0..<n {
                                let f = CGFloat(i) / CGFloat(n)
                                let p = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: .color(paper))
                            }
                        }
                        dots(CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY))
                        dots(CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY))
                        dots(CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY))
                        dots(CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY))
                    }
                    .frame(width: 54, height: 62)
                    CSSLinearGradient(shape: Rectangle(), degrees: 160, stops: [.init(color: accent, location: 0), .init(color: accent(0.7), location: 1)])
                        .frame(width: 40, height: 48)
                    Text("\u{2665}").font(.custom("Georgia", size: 20)).foregroundColor(Color.white.opacity(0.92))
                }
                .frame(width: 54, height: 62)
                .padding(.top, 12 - 7)
                .padding(.trailing, 14 - 7)
                // The postmark over it: a ringed circle of fine lines, turned -14deg.
                Canvas { ctx, size in
                    let circle = Path(ellipseIn: CGRect(x: 1, y: 1, width: 42, height: 42))
                    var inner = ctx
                    inner.clip(to: Path(ellipseIn: CGRect(x: 2, y: 2, width: 40, height: 40)))
                    var y = 2.0 + 5
                    while y < 42 { inner.fill(Path(CGRect(x: 0, y: y, width: 44, height: 1)), with: .color(rgba(43, 33, 24, 0.28))); y += 6 }
                    ctx.stroke(circle, with: .color(rgba(43, 33, 24, 0.35)), lineWidth: 2)
                }
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-14))
                .padding(.top, 34)
                .padding(.trailing, 34)
            }
            .allowsHitTesting(false)
        )
        .padding(6)
        .background(
            ZStack {
                CSSShadow(shape: outer, y: 18, blur: 40, spread: -16, color: rgba(43, 33, 24, 0.5))
                // The airmail edge: red 12, paper 6, blue 12, paper 6, at 135deg from the top-left corner.
                Canvas { ctx, size in
                    let w = Double(size.width), hgt = Double(size.height)
                    let colors: [(Double, Double, Color)] = [(0, 12, Color(hex: "#d9383a")), (12, 18, paper), (18, 30, Color(hex: "#2754c5")), (30, 36, paper)]
                    var base = 0.0
                    let maxD = (w + hgt) / 2.squareRoot()
                    while base < maxD {
                        for (a, b, col) in colors {
                            let s0 = (base + a) * 2.squareRoot(), s1 = (base + b) * 2.squareRoot()
                            var p = Path()
                            p.move(to: CGPoint(x: s0, y: 0)); p.addLine(to: CGPoint(x: s1, y: 0))
                            p.addLine(to: CGPoint(x: s1 - hgt, y: hgt)); p.addLine(to: CGPoint(x: s0 - hgt, y: hgt))
                            p.closeSubpath()
                            ctx.fill(p, with: .color(col))
                        }
                        base += 36
                    }
                }
                .clipShape(outer)
            }
        )
        .overlay(close(top: -6, right: -6, color: Color(hex: "#94a3b8"), circle: paper, shadow: true))
    }

    // sticky: a yellow note in marker, the corner lifting, tilted.
    private func sticky(_ t: Double) -> some View {
        let shape = BubbleShape(corners: BubbleCorners(topLeft: 2, topRight: 2, bottomRight: 18, bottomLeft: 2))
        var h = baseHead
        h.avatar = 26
        h.name = font(.marker, 15)
        h.nameColor = Color(hex: "#3a2f00")
        h.status = font(.system, 12, .medium)
        h.statusColor = Color(hex: "#6b5a00")
        return VStack(alignment: .leading, spacing: 8) {
            head(h, t)
            message(t, font(.marker, 18), lineHeight: 23.4, color: Color(hex: "#2b2300"))
            chips(font(.system, 13, .semibold), color: Color(hex: "#3a2f00"), background: plainChip(fill: Color.white.opacity(0.55), border: rgba(58, 47, 0, 0.25)))
        }
        .padding(pad)
        .background(
            ZStack(alignment: .bottomTrailing) {
                CSSShadow(shape: shape, y: 22, blur: 30, spread: -18, color: rgba(90, 70, 0, 0.55))
                CSSLinearGradient(shape: shape, degrees: 170, stops: [.init(color: Color(hex: "#fff8b0"), location: 0), .init(color: Color(hex: "#ffec6e"), location: 1)])
                // Inset 0 -18 22 -18: a soft darkening along the inside bottom.
                LinearGradient(colors: [rgba(120, 90, 0, 0), rgba(120, 90, 0, 0.12)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .clipShape(shape)
                // The curl: a 22pt corner folded along its diagonal.
                Canvas { ctx, size in
                    let corner = BubbleShape(corners: BubbleCorners(topLeft: 0, topRight: 0, bottomRight: 18, bottomLeft: 0)).path(in: CGRect(origin: .zero, size: size))
                    ctx.clip(to: corner)
                    var tri = Path()
                    tri.move(to: .zero); tri.addLine(to: CGPoint(x: 22, y: 0)); tri.addLine(to: CGPoint(x: 0, y: 22)); tri.closeSubpath()
                    ctx.fill(corner, with: .linearGradient(Gradient(stops: [.init(color: rgba(0, 0, 0, 0.12), location: 0.5), .init(color: Color(hex: "#f4d63a"), location: 0.6), .init(color: Color(hex: "#f4d63a"), location: 1)]),
                                                         startPoint: .zero, endPoint: CGPoint(x: 22, y: 22)))
                    ctx.fill(tri, with: .color(Color(hex: "#ffe45c")))
                }
                .frame(width: 22, height: 22)
            }
        )
        .overlay(close(top: 10, right: 10, color: Color(hex: "#6b5a00")))
        .rotationEffect(.degrees(reduceMotion ? 0 : 1.8))
    }

    // typewriter: paper, typed out, a blinking caret.
    private func typewriter(_ t: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        var h = baseHead
        h.name = font(.mono, 13.5, .bold)
        h.nameTracking = 0.27
        h.status = font(.mono, 12, .medium)
        return VStack(alignment: .leading, spacing: 8) {
            head(h, t)
            TimelineView(.periodic(from: shownAt, by: 0.5)) { tl in
                let blink = Int(tl.date.timeIntervalSince(shownAt) * 2) % 2 == 0
                caretMessage(t, blink: blink)
            }
            chips(font(.mono, 13, .semibold), color: accent, background: baseChip(radius: 3))
        }
        .padding(pad)
        .background(
            ZStack {
                CSSShadow(shape: shape, y: 16, blur: 36, spread: -16, color: rgba(0, 0, 0, 0.45))
                shape.fill(Color(hex: "#fcfbf6"))
                Rectangle().fill(accent).frame(height: 3).frame(maxHeight: .infinity, alignment: .top).clipShape(shape)
            }
        )
        .overlay(close(top: 10, right: 10, color: Color(hex: "#94a3b8")))
    }

    private func caretMessage(_ t: Double, blink: Bool) -> some View {
        let f = font(.mono, 15, .semibold)
        let spacing = max(0, 22.5 - f.lineHeight)
        var out = Text(String(card.text.prefix(typed))).foregroundColor(Color(hex: "#1c1c1c"))
        if !reduceMotion {
            out = out + Text("\u{258C}").foregroundColor(accent.opacity(blink ? 1 : 0))
        }
        return out
            .font(Font(f as CTFont))
            .lineSpacing(spacing)
            .lineLimit(4)
            .padding(.vertical, spacing / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            // Keep the card's height as the whole text would set it, so it does not grow while typing.
            .background(
                Text(card.text).font(Font(f as CTFont)).lineSpacing(spacing).lineLimit(4).padding(.vertical, spacing / 2)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).hidden()
            )
            .accessibilityLabel(Text(card.text))
    }

    // glass: frosted, translucent, a brand glow from the top-right.
    private func glass(_ t: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        var h = baseHead
        h.statusColor = Color(hex: "#475569")
        return baseBody(t, head: h, msgColor: Color(hex: "#0f172a"),
                        chip: plainChip(fill: Color.white.opacity(0.7), border: rgba(15, 23, 42, 0.08)), chipColor: Color(hex: "#0f172a"))
            .background(
                ZStack {
                    CSSShadow(shape: shape, y: 24, blur: 48, spread: -20, color: rgba(15, 23, 42, 0.45), outsideOnly: true)
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(0.62))
                    // radial-gradient(120% 90% at 100% 0%, accent .22, transparent 60%)
                    Canvas { ctx, size in
                        var g = ctx
                        g.translateBy(x: size.width, y: 0)
                        g.scaleBy(x: size.width * 1.2 * 0.6, y: size.height * 0.9 * 0.6)
                        g.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                               with: .radialGradient(Gradient(colors: [accent(0.22), accent(0)]), center: .zero, startRadius: 0, endRadius: 1))
                    }
                    .clipShape(shape)
                    shape.strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                    Rectangle().fill(Color.white.opacity(0.9)).frame(height: 1).padding(.horizontal, 14)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            )
            .overlay(close(top: 10, right: 10, color: Color(hex: "#94a3b8")))
    }

    // notification: a push banner sliding down.
    private func notification(_ t: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        var h = baseHead
        h.avatar = 22
        h.avatarRadius = 6
        h.name = font(.system, 12, .semibold)
        h.nameColor = Color(hex: "#555555")
        h.nameTracking = 0.24
        h.uppercase = true
        h.status = font(.system, 12, .medium)
        h.statusColor = Color(hex: "#8e8e93")
        h.statusText = "now"
        h.dot = false
        h.row = true
        return VStack(alignment: .leading, spacing: 8) {
            head(h, t)
            message(t, font(.system, 14.5, .medium), lineHeight: 19.6, color: Color(hex: "#111111"))
            chips(font(.system, 13, .semibold), color: Color(hex: "#111111"), background: plainChip(radius: 12, fill: rgba(0, 0, 0, 0.06)))
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(
            ZStack {
                CSSShadow(shape: shape, y: 18, blur: 40, spread: -16, color: rgba(0, 0, 0, 0.45), outsideOnly: true)
                shape.fill(.ultraThinMaterial)
                shape.fill(rgba(246, 246, 248, 0.88))
                shape.strokeBorder(rgba(0, 0, 0, 0.08), lineWidth: 0.5)
            }
        )
        .overlay(close(top: 10, right: 10, color: Color(hex: "#94a3b8")))
    }

    // neon: a dark sign lit in the brand colour.
    private func neon(_ t: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        var h = baseHead
        h.nameColor = .white
        h.nameGlow = accent
        h.statusColor = Color(hex: "#a5a3c7")
        return baseBody(t, head: h, msgColor: Color(hex: "#ede9fe"),
                        chip: plainChip(fill: .clear, border: accent(0.8), glow: accent(0.35)), chipColor: Color(hex: "#f5f3ff"))
            .background(
                ZStack {
                    CSSShadow(shape: shape, y: 24, blur: 40, spread: -20, color: rgba(0, 0, 0, 0.7))
                    CSSShadow(shape: shape, y: 0, blur: 42, spread: -6, color: accent(0.5))
                    CSSShadow(shape: shape, y: 0, blur: 18, spread: 0, color: accent(0.55))
                    // radial-gradient(140% 120% at 0% 0%, #1b1530, #07070c 70%)
                    Canvas { ctx, size in
                        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "#07070c")))
                        var g = ctx
                        g.scaleBy(x: size.width * 1.4, y: size.height * 1.2)
                        g.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                               with: .radialGradient(Gradient(stops: [.init(color: Color(hex: "#1b1530"), location: 0), .init(color: Color(hex: "#07070c"), location: 0.7)]),
                                                     center: .zero, startRadius: 0, endRadius: 1))
                    }
                    .clipShape(shape)
                    shape.strokeBorder(accent(0.95), lineWidth: 1.5)
                }
            )
            .overlay(close(top: 10, right: 10, color: Color(hex: "#c4b5fd")))
    }

    // voice: a voice note - play, waveform, transcript.
    private func voice(_ t: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let b = card.bubble
        let fg = Color(hex: b.fg)
        return VStack(alignment: .leading, spacing: 8) {
            head(baseHead, t)
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.22))
                    GreetingPlay().fill(fg).frame(width: 14, height: 14)
                }
                .frame(width: 30, height: 30)
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<Greeting.voiceBars.count, id: \.self) { i in
                        // Each bar squashes to 35% and back, twice, 60ms after the one before.
                        let local = t - Double(i) * 60
                        let s = local < 0 || local >= 2400 || reduceMotion ? 1 : keyframe(local.truncatingRemainder(dividingBy: 1200), 1200, [(0, 1), (0.5, 0.35), (1, 1)], .easeInOut)
                        RoundedRectangle(cornerRadius: 2).fill(fg.opacity(0.85))
                            .frame(height: 26 * Greeting.voiceBars[i] / 100)
                            .scaleEffect(x: 1, y: s)
                    }
                }
                .frame(height: 26)
                Text(Greeting.voiceDuration(card.text))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(fg.opacity(0.9))
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 12))
            .background(
                Group {
                    if b.bg.count > 1 {
                        CSSLinearGradient(shape: Capsule(), degrees: 135, stops: [.init(color: Color(hex: b.bg[0]), location: 0), .init(color: Color(hex: b.bg[1]), location: 1)])
                    } else {
                        Capsule().fill(Color(hex: b.bg.first ?? card.accent))
                    }
                }
            )
            message(t, font(.card, 13, .medium, italic: true), lineHeight: 18.85, color: Color(hex: "#475569"))
                .padding(.horizontal, 4)
            chips(font(.card, 13, .semibold), color: accent, background: baseChip())
        }
        .padding(pad)
        .background(
            ZStack {
                CSSShadow(shape: shape, y: 20, blur: 40, spread: -18, color: rgba(15, 23, 42, 0.4))
                shape.fill(Color.white)
                shape.strokeBorder(rgba(15, 23, 42, 0.06), lineWidth: 1)
            }
        )
        .overlay(close(top: 10, right: 10, color: Color(hex: "#94a3b8")))
    }

    // aurora: a white card with a slowly turning coloured edge.
    private func aurora(_ t: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let colors = [accent, Color(hex: "#22d3ee"), Color(hex: "#a78bfa"), Color(hex: "#f472b6"), accent]
        return baseBody(t)
            .background(
                ZStack {
                    CSSShadow(shape: shape, y: 24, blur: 50, spread: -22, color: accent(0.55))
                    shape.fill(Color.white)
                    // conic-gradient(from 0deg, ...) turning once every 6s, seen as a 2pt ring.
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
                        let turn = reduceMotion ? 0 : tl.date.timeIntervalSince(shownAt).truncatingRemainder(dividingBy: 6) / 6 * 360
                        shape.strokeBorder(AngularGradient(colors: colors, center: .center, startAngle: .degrees(-90 + turn), endAngle: .degrees(270 + turn)), lineWidth: 2)
                    }
                }
            )
            .overlay(close(top: 10, right: 10, color: Color(hex: "#94a3b8")))
    }
}

// MARK: - Entrance

/// The card's entrance (polish-home.css): the spring (lively), the fade-up
/// (subtle / off), the notification's slide down, neon's flicker.
@available(iOS 15.0, *)
private struct Entrance: ViewModifier {
    let style: String
    let motion: String
    let reduced: Bool
    let t: Double
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        var o = 1.0, y = 0.0, s = 1.0
        if !reduced {
            switch style {
            case "neon":
                // steps(1): 0, 1, .3, 1, .55, 1 at 0/90/144/216/270/342ms.
                let steps: [(Double, Double)] = [(0, 0), (90, 1), (144, 0.3), (216, 1), (270, 0.55), (342, 1)]
                o = steps.last { t >= $0.0 }?.1 ?? 0
            case "notification":
                let e = CubicBezier(x1: 0.2, y1: 1.2, x2: 0.3, y2: 1)
                o = keyframe(t, 500, [(0, 0), (1, 1)], e)
                y = keyframe(t, 500, [(0, -14), (1, 0)], e)
                s = keyframe(t, 500, [(0, 0.96), (1, 1)], e)
            default:
                if motion == "lively" {
                    let e = CubicBezier(x1: 0.2, y1: 0.9, x2: 0.3, y2: 1)
                    o = keyframe(t, 620, [(0, 0), (0.55, 1), (1, 1)], e)
                    y = keyframe(t, 620, [(0, 14), (0.55, -3), (0.78, 1), (1, 0)], e)
                    s = keyframe(t, 620, [(0, 0.94), (0.55, 1.01), (0.78, 0.998), (1, 1)], e)
                } else {
                    let e = CubicBezier(x1: 0.22, y1: 1, x2: 0.36, y2: 1)
                    o = keyframe(t, 450, [(0, 0), (1, 1)], e)
                    y = keyframe(t, 450, [(0, 10), (1, 0)], e)
                    s = keyframe(t, 450, [(0, 0.98), (1, 1)], e)
                }
            }
        }
        return content
            .scaleEffect(s, anchor: anchor)
            .offset(y: y)
            .opacity(min(1, max(0, o)))
    }
}

// MARK: - The card's life

/// The greeting card's life, as the web runs it (ts/visibility/greeting.ts;
/// RN FloatingWidget/useGreeting.ts): decided once the bot's settings
/// arrive, shown after its delay unless the chat is open or the frequency
/// says no, gone for a while once closed or used.
@available(iOS 15.0, *)
@MainActor
final class GreetingController: ObservableObject {
    @Published private(set) var card: GreetingCardData?
    private var store: GreetingStore?
    private var timer: DispatchWorkItem?
    private var decidedFor: NSDictionary?

    /// The bot's settings, the chat's state or the agent changed: decide again.
    func update(customizations: [String: Any]?, chatOpen: Bool, botId: String?, agentBot: AgentBot?) {
        guard let c = customizations, let botId = botId, !chatOpen else {
            timer?.cancel()
            decidedFor = nil
            if card != nil { withAnimation(.easeIn(duration: 0.22)) { card = nil } }
            return
        }
        // Settings re-sent unchanged (a theme repaint) leave a card or its wait alone.
        let key = c as NSDictionary
        if let d = decidedFor, d.isEqual(to: c), card != nil || timer != nil { return }
        decidedFor = key
        timer?.cancel()
        timer = nil
        if store?.botId != botId { store = GreetingStore(botId: botId) }
        guard let store = store else { return }
        store.countVisit()
        guard let g = store.decide(c, signedIn: GreetingStore.signedIn(ChatState.shared.visitorContext)) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.timer = nil
            self.card = store.show(c, g, agentBot: agentBot)
        }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(g.delay), execute: work)
    }

    /// Closed with its X.
    func dismiss() {
        store?.dismiss()
        withAnimation(.easeIn(duration: 0.22)) { card = nil }
    }

    /// Used (tapped, or a starter chosen): rests like a close.
    func closeForNow() {
        store?.closeForNow()
        withAnimation(.easeIn(duration: 0.24)) { card = nil }
    }

    /// The chat opened: chatted, and a card on show rests.
    func chatOpened() {
        store?.chatOpened(showing: card != nil)
        timer?.cancel()
        timer = nil
        card = nil
    }
}
